import {createHash, randomBytes, createCipheriv, createDecipheriv} from 'node:crypto';
import {z} from 'zod';
export const MAX_MEMBERS = 5;
export const MAX_SESSIONS = 3;
export const LEASE_MS = 90_000;
export const TOKEN_MS = 5 * 60_000;
export const TRIAL_MS = 7 * 86400_000;
export class DomainError extends Error {
  constructor(readonly code: string, readonly details: Record<string, unknown> = {}) { super(code); }
}
export type Lease = {id: string; deviceId: string; deviceName: string; profileId: string; expiresAt: number};
export type Subscription = {status: 'notStarted'|'trial'|'active'|'cancelled'|'expired'|'pending'|'lifetime'; trialStartedAt?: number; trialEndsAt?: number; paidUntil?: number};
// Playback policy only. Manager operations authorize identity and family role.
// Missing or malformed subscription metadata never grants playback.
export function canStartPlayback(s: Subscription | undefined, now: number): boolean {
  if (!s) return false;
  // Lifetime is granted only by the backend (coupon or administrative grant) and never expires.
  if (s.status === 'lifetime') return true;
  return (s.status === 'trial' && Number.isFinite(s.trialEndsAt) && (s.trialEndsAt ?? 0) > now) || ((s.status === 'active' || s.status === 'cancelled') && Number.isFinite(s.paidUntil) && (s.paidUntil ?? 0) > now);
}
export function startTrial(s: Subscription = {status:'notStarted'}, now: number): Subscription {
  if (s.trialStartedAt !== undefined) return s;
  // Linking the first TV must not replace a longer, already valid paid right.
  const status = canStartPlayback(s, now) && s.status !== 'trial' ? s.status : 'trial';
  return {...s, status, trialStartedAt:now, trialEndsAt:now+TRIAL_MS};
}
export function acquire(leases: Lease[], next: Lease, now: number): Lease[] {
  const live = leases.filter(x=>x.expiresAt>now);
  const profile = live.find(x=>x.profileId===next.profileId && x.deviceId!==next.deviceId);
  if(profile) throw new DomainError('profile-in-use', {deviceName:profile.deviceName});
  const others=live.filter(x=>x.deviceId!==next.deviceId);
  if(others.length>=MAX_SESSIONS) throw new DomainError('session-limit', {devices:others.map(x=>x.deviceName)});
  return [...others,next];
}
export function addMember(members: Record<string,string>, uid:string) {
  if(members[uid]) throw new DomainError('already-linked');
  if(Object.keys(members).length>=MAX_MEMBERS) throw new DomainError('family-limit');
  return {...members,[uid]:'member'};
}
export const nameSchema=z.string().trim().min(1).max(80);
export const idSchema=z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
export const tokenSchema=z.string().regex(/^[a-f0-9]{64}$/);
export const sourceFormatSchema = z.enum(['m3u', 'url', 'file', 'xtream', 'other_m3u8', 'direct_stream']);
export const pinSchema = z.string().regex(/^\d{4,6}$/);

export const sourceSchema = z.object({
  name: nameSchema,
  format: sourceFormatSchema,
  url: z.string().max(2048).optional(),
  fileName: z.string().max(256).optional(),
  filePath: z.string().max(512).optional(),
  epgUrl: z.string().url().max(2048).optional().nullable(),
  username: z.string().max(256).optional(),
  password: z.string().max(512).optional(),
  isProtected: z.boolean().optional(),
  pinHash: z.string().optional(),
}).superRefine((x, ctx) => {
  if (x.format === 'file') {
    // File sources have fileName or local storage reference
  } else {
    if (!x.url) {
      ctx.addIssue({code: 'custom', message: 'url-required'});
      return;
    }
    try {
      const u = new URL(x.url);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) ctx.addIssue({code: 'custom', message: 'https-required'});
    } catch {
      ctx.addIssue({code: 'custom', message: 'https-required'});
    }
  }
  if (x.epgUrl) {
    try {
      const u = new URL(x.epgUrl);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) ctx.addIssue({code: 'custom', message: 'epg-https-required'});
    } catch {
      ctx.addIssue({code: 'custom', message: 'epg-https-required'});
    }
  }
  if (x.format === 'xtream' && (!x.username || !x.password)) {
    ctx.addIssue({code: 'custom', message: 'credentials-required'});
  }
});

export const sourceInputSchema = z.object({
  id: idSchema.optional(),
  requestId: idSchema.optional(),
  expectedRevision: z.number().int().positive().optional(),
  name: nameSchema,
  format: sourceFormatSchema,
  url: z.string().max(2048).optional(),
  fileName: z.string().max(256).optional(),
  fileContent: z.string().max(20 * 1024 * 1024).refine(v => Buffer.byteLength(v, 'utf8') <= 20 * 1024 * 1024, 'file-too-large').optional(),
  epgUrl: z.string().url().max(2048).optional().nullable(),
  username: z.string().max(256).optional(),
  password: z.string().max(512).optional(),
  isProtected: z.boolean().optional(),
  pin: pinSchema.optional(),
  confirmPin: pinSchema.optional(),
}).superRefine((x, ctx) => {
  if (x.format === 'file') {
    if (!x.id && !x.fileContent) {
      ctx.addIssue({code: 'custom', message: 'file-required'});
    }
  } else {
    if (!x.url && !x.id) {
      ctx.addIssue({code: 'custom', message: 'url-required'});
      return;
    }
    if (x.url) try {
      const u = new URL(x.url);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) ctx.addIssue({code: 'custom', message: 'https-required'});
    } catch {
      ctx.addIssue({code: 'custom', message: 'https-required'});
    }
  }
  if (x.epgUrl) {
    try {
      const u = new URL(x.epgUrl);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) ctx.addIssue({code: 'custom', message: 'epg-https-required'});
    } catch {
      ctx.addIssue({code: 'custom', message: 'epg-https-required'});
    }
  }
  if (x.format === 'xtream') {
    if (!x.id && !x.username) ctx.addIssue({code: 'custom', message: 'credentials-required'});
    if (!x.id && !x.password) ctx.addIssue({code: 'custom', message: 'credentials-required'});
  }
  if (x.isProtected) {
    if (!x.id && !x.pin) {
      ctx.addIssue({code: 'custom', message: 'pin-required'});
    }
    if (x.pin && x.pin !== x.confirmPin) {
      ctx.addIssue({code: 'custom', message: 'pin-mismatch'});
    }
  }
});
export const hash=(value:string)=>createHash('sha256').update(value).digest('hex');
export const newToken=()=>randomBytes(32).toString('hex');
export function seal(value:unknown, key:string):string {
 const bytes=Buffer.from(key,'base64'); if(bytes.length!==32)throw new Error('invalid-encryption-key');
 const iv=randomBytes(12), cipher=createCipheriv('aes-256-gcm',bytes,iv);
 const body=Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]);
 return Buffer.concat([iv,cipher.getAuthTag(),body]).toString('base64');
}
export function unseal<T>(value:string,key:string):T {
 const bytes=Buffer.from(value,'base64'); const decipher=createDecipheriv('aes-256-gcm',Buffer.from(key,'base64'),bytes.subarray(0,12));
 decipher.setAuthTag(bytes.subarray(12,28));
 return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)),decipher.final()]).toString('utf8')) as T;
}
