import {createHash, randomBytes} from 'node:crypto';
import {z} from 'zod';

export type PlatformType = 'android_tv' | 'tizen' | 'webos';

export type IdentitySource =
  | 'android_settings_secure_android_id'
  | 'android_widevine_device_unique_id'
  | 'tizen_duid_api'
  | 'tizen_systeminfo_tizenid'
  | 'tizen_app_install_fallback'
  | 'webos_device_id_service'
  | 'webos_app_install_fallback';

export type IdentityScope = 'app_scoped' | 'vendor_scoped' | 'hardware_global';
export type IdentityStability = 'hardware_stable' | 'os_reinstall_stable' | 'installation_persistent';

export interface DeviceIdentityInfo {
  platform: PlatformType;
  nativeDeviceId: string;
  identitySource: IdentitySource;
  identityScope: IdentityScope;
  identityStability: IdentityStability;
  manufacturer: string;
  model: string;
}

/**
 * Common abstraction for TV platform identification as defined by Codex Section 6.
 * Implementations run within the respective TV Player environments (Android TV wrapper,
 * Samsung Tizen web app, LG webOS hosted app).
 */
export abstract class DeviceIdentityProvider {
  abstract readonly platform: PlatformType;
  abstract getIdentity(): Promise<DeviceIdentityInfo>;
}

/**
 * Android TV implementation.
 * Queries Android Settings.Secure.ANDROID_ID or Widevine Device Unique ID via native bridge.
 * Scope: app-scoped/signing-key scoped on Android 8.0+; changes only upon factory reset.
 */
export class AndroidTvIdentityProvider extends DeviceIdentityProvider {
  readonly platform: PlatformType = 'android_tv';

  constructor(
    private readonly nativeBridge?: {
      getAndroidId: () => Promise<string>;
      getManufacturer?: () => Promise<string>;
      getModel?: () => Promise<string>;
    }
  ) {
    super();
  }

  async getIdentity(): Promise<DeviceIdentityInfo> {
    const rawId = this.nativeBridge
      ? await this.nativeBridge.getAndroidId()
      : 'android_fallback_install_' + randomBytes(16).toString('hex');

    const manufacturer = this.nativeBridge?.getManufacturer
      ? await this.nativeBridge.getManufacturer()
      : 'Google';

    const model = this.nativeBridge?.getModel
      ? await this.nativeBridge.getModel()
      : 'Android TV';

    return {
      platform: 'android_tv',
      nativeDeviceId: rawId.trim(),
      identitySource: 'android_settings_secure_android_id',
      identityScope: 'app_scoped',
      identityStability: 'os_reinstall_stable',
      manufacturer,
      model,
    };
  }
}

/**
 * Samsung Tizen implementation.
 * Attempts official `webapis.productinfo.getDuid()` or `tizen.systeminfo.getCapability()`.
 * If restricted for third-party apps, falls back to persistent secure storage.
 */
export class SamsungTizenIdentityProvider extends DeviceIdentityProvider {
  readonly platform: PlatformType = 'tizen';

  constructor(
    private readonly tizenApi?: {
      getDuid?: () => string;
      getPersistentStorageId?: () => string;
      getModel?: () => string;
    }
  ) {
    super();
  }

  async getIdentity(): Promise<DeviceIdentityInfo> {
    let rawId = '';
    let source: IdentitySource = 'tizen_app_install_fallback';
    let stability: IdentityStability = 'installation_persistent';

    if (this.tizenApi?.getDuid) {
      try {
        rawId = this.tizenApi.getDuid();
        if (rawId && rawId.length > 4) {
          source = 'tizen_duid_api';
          stability = 'hardware_stable';
        }
      } catch {
        rawId = '';
      }
    }

    if (!rawId && this.tizenApi?.getPersistentStorageId) {
      rawId = this.tizenApi.getPersistentStorageId();
    }

    if (!rawId) {
      rawId = 'tizen_persistent_install_' + randomBytes(16).toString('hex');
    }

    return {
      platform: 'tizen',
      nativeDeviceId: rawId.trim(),
      identitySource: source,
      identityScope: source === 'tizen_duid_api' ? 'vendor_scoped' : 'app_scoped',
      identityStability: stability,
      manufacturer: 'Samsung',
      model: this.tizenApi?.getModel ? this.tizenApi.getModel() : 'Smart TV Tizen',
    };
  }
}

/**
 * LG webOS implementation.
 * Queries `webOS.deviceInfo` or Luna service if permitted.
 * For 3rd-party web apps, persistent application storage serves as the standard fallback.
 */
export class LgWebOsIdentityProvider extends DeviceIdentityProvider {
  readonly platform: PlatformType = 'webos';

  constructor(
    private readonly webosApi?: {
      getDeviceId?: () => Promise<string>;
      getPersistentStorageId?: () => string;
      getModel?: () => string;
    }
  ) {
    super();
  }

  async getIdentity(): Promise<DeviceIdentityInfo> {
    let rawId = '';
    let source: IdentitySource = 'webos_app_install_fallback';
    let stability: IdentityStability = 'installation_persistent';

    if (this.webosApi?.getDeviceId) {
      try {
        rawId = await this.webosApi.getDeviceId();
        if (rawId && rawId.length > 4) {
          source = 'webos_device_id_service';
          stability = 'hardware_stable';
        }
      } catch {
        rawId = '';
      }
    }

    if (!rawId && this.webosApi?.getPersistentStorageId) {
      rawId = this.webosApi.getPersistentStorageId();
    }

    if (!rawId) {
      rawId = 'webos_persistent_install_' + randomBytes(16).toString('hex');
    }

    return {
      platform: 'webos',
      nativeDeviceId: rawId.trim(),
      identitySource: source,
      identityScope: source === 'webos_device_id_service' ? 'vendor_scoped' : 'app_scoped',
      identityStability: stability,
      manufacturer: 'LG',
      model: this.webosApi?.getModel ? this.webosApi.getModel() : 'LG webOS TV',
    };
  }
}

/**
 * Calculate deterministic canonical device ID.
 * Collisions between platforms are prevented by prefixing platform identifier.
 * Output format: `dev_<sha256(platform:nativeId).substring(0, 32)>`
 */
export function calculateCanonicalDeviceId(platform: PlatformType, nativeDeviceId: string): string {
  const normalizedPlatform = platform.toLowerCase().trim();
  const normalizedNativeId = nativeDeviceId.trim();
  const digest = createHash('sha256')
    .update(`iplex:platform:${normalizedPlatform}:native:${normalizedNativeId}`)
    .digest('hex');
  return `dev_${digest.substring(0, 32)}`;
}

/**
 * Calculate fingerprint for safe audit/logging and masked display.
 */
export function calculateIdentityFingerprint(platform: PlatformType, nativeDeviceId: string): string {
  const digest = createHash('sha256')
    .update(`fp:${platform}:${nativeDeviceId.trim()}`)
    .digest('hex');
  return `${platform.substring(0, 3)}_${digest.substring(0, 16)}`;
}

/**
 * Mask fingerprint for user-facing UI (e.g., `dev_••••a1b2`).
 */
export function maskIdentityFingerprint(canonicalId: string): string {
  if (canonicalId.length <= 8) return canonicalId;
  const tail = canonicalId.slice(-4);
  return `dev_••••${tail}`;
}

/**
 * Generate human-friendly manual pairing code.
 * Format: 6-digits formatted as `XXX-XXX` or 6 uppercase chars with safe alphabet.
 */
export function generatePairingCode(): { code: string; formatted: string; hash: string } {
  // Use numeric 6-digit code for remote-control convenience on TVs
  const num = Math.floor(100000 + Math.random() * 900000).toString();
  const formatted = `${num.substring(0, 3)}-${num.substring(3, 6)}`;
  const hash = createHash('sha256').update(num).digest('hex');
  return { code: num, formatted, hash };
}

/**
 * Hash normalized pairing code for constant-time comparison in backend.
 */
export function hashPairingCode(rawCode: string): string {
  const normalized = rawCode.replace(/[^a-zA-Z0-9]/g, '').toLowerCase().trim();
  return createHash('sha256').update(normalized).digest('hex');
}

export const platformSchema = z.enum(['android_tv', 'tizen', 'webos']);

export const pairingSessionInputSchema = z.object({
  name: z.string().trim().min(1).max(100),
  platform: platformSchema.default('android_tv'),
  manufacturer: z.string().trim().max(100).optional(),
  model: z.string().trim().max(100).optional(),
  nativeDeviceId: z.string().trim().min(1).max(256).optional(),
  identitySource: z.string().trim().max(100).optional(),
  identityScope: z.string().trim().max(100).optional(),
  identityStability: z.string().trim().max(100).optional(),
});
