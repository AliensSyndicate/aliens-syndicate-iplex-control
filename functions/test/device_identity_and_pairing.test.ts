import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AndroidTvIdentityProvider,
  SamsungTizenIdentityProvider,
  LgWebOsIdentityProvider,
  calculateCanonicalDeviceId,
  calculateIdentityFingerprint,
  maskIdentityFingerprint,
  generatePairingCode,
  hashPairingCode,
} from '../src/device_identity';

test('1. Android TV identity provider extracts stable Android ID', async () => {
  const provider = new AndroidTvIdentityProvider({
    getAndroidId: async () => '4a8b79c2d1e0f3a5',
    getManufacturer: async () => 'Sony',
    getModel: async () => 'BRAVIA 4K TV',
  });
  const identity = await provider.getIdentity();
  assert.equal(identity.platform, 'android_tv');
  assert.equal(identity.nativeDeviceId, '4a8b79c2d1e0f3a5');
  assert.equal(identity.identitySource, 'android_settings_secure_android_id');
  assert.equal(identity.identityScope, 'app_scoped');
  assert.equal(identity.identityStability, 'os_reinstall_stable');
  assert.equal(identity.manufacturer, 'Sony');
  assert.equal(identity.model, 'BRAVIA 4K TV');
});

test('2. Samsung Tizen provider uses DUID when available', async () => {
  const provider = new SamsungTizenIdentityProvider({
    getDuid: () => 'TIZEN_DUID_987654321',
    getModel: () => 'Samsung Neo QLED 65',
  });
  const identity = await provider.getIdentity();
  assert.equal(identity.platform, 'tizen');
  assert.equal(identity.nativeDeviceId, 'TIZEN_DUID_987654321');
  assert.equal(identity.identitySource, 'tizen_duid_api');
  assert.equal(identity.identityStability, 'hardware_stable');
  assert.equal(identity.manufacturer, 'Samsung');
});

test('3. Samsung Tizen provider falls back to persistent storage when DUID is restricted', async () => {
  const provider = new SamsungTizenIdentityProvider({
    getDuid: () => {
      throw new Error('SecurityError: Permission denied');
    },
    getPersistentStorageId: () => 'tizen_storage_fallback_123',
  });
  const identity = await provider.getIdentity();
  assert.equal(identity.platform, 'tizen');
  assert.equal(identity.nativeDeviceId, 'tizen_storage_fallback_123');
  assert.equal(identity.identitySource, 'tizen_app_install_fallback');
  assert.equal(identity.identityStability, 'installation_persistent');
});

test('4. LG webOS provider uses device service when authorized', async () => {
  const provider = new LgWebOsIdentityProvider({
    getDeviceId: async () => 'LG_WEBOS_DEVICE_ID_XYZ',
    getModel: () => 'LG OLED C3',
  });
  const identity = await provider.getIdentity();
  assert.equal(identity.platform, 'webos');
  assert.equal(identity.nativeDeviceId, 'LG_WEBOS_DEVICE_ID_XYZ');
  assert.equal(identity.identitySource, 'webos_device_id_service');
  assert.equal(identity.identityStability, 'hardware_stable');
});

test('5. LG webOS provider falls back to installation-persistent ID when service unavailable', async () => {
  const provider = new LgWebOsIdentityProvider({
    getPersistentStorageId: () => 'webos_persistent_uuid_456',
  });
  const identity = await provider.getIdentity();
  assert.equal(identity.platform, 'webos');
  assert.equal(identity.nativeDeviceId, 'webos_persistent_uuid_456');
  assert.equal(identity.identitySource, 'webos_app_install_fallback');
  assert.equal(identity.identityStability, 'installation_persistent');
});

test('6. Canonical device ID is deterministic and platform collision-free', () => {
  const nativeId = 'shared_hardware_id_12345';
  const androidId = calculateCanonicalDeviceId('android_tv', nativeId);
  const tizenId = calculateCanonicalDeviceId('tizen', nativeId);
  const webosId = calculateCanonicalDeviceId('webos', nativeId);

  // Determinism
  assert.equal(androidId, calculateCanonicalDeviceId('android_tv', nativeId));
  assert.equal(tizenId, calculateCanonicalDeviceId('tizen', nativeId));
  assert.equal(webosId, calculateCanonicalDeviceId('webos', nativeId));

  // No cross-platform collision
  assert.notEqual(androidId, tizenId);
  assert.notEqual(androidId, webosId);
  assert.notEqual(tizenId, webosId);

  assert.ok(androidId.startsWith('dev_'));
  assert.equal(androidId.length, 36);
});

test('7. Fingerprint masking obscures private hardware ID', () => {
  const canonicalId = 'dev_1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d';
  const masked = maskIdentityFingerprint(canonicalId);
  assert.equal(masked, 'dev_••••5c6d');
});

test('8. Pairing code generator creates 6-digit formatted code with SHA-256 hash', () => {
  const codeObj = generatePairingCode();
  assert.match(codeObj.code, /^\d{6}$/);
  assert.match(codeObj.formatted, /^\d{3}-\d{3}$/);
  assert.equal(hashPairingCode(codeObj.formatted), codeObj.hash);
  assert.equal(hashPairingCode(codeObj.code), codeObj.hash);
});
