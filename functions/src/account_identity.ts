import {randomInt} from 'node:crypto';
import {getFirestore} from 'firebase-admin/firestore';
import {DomainError} from './domain';

export const PUBLIC_CODE = /^[A-Z0-9]{12}$/;
// New codes omit look-alike characters (0/O, 1/I/L); older codes stay valid via PUBLIC_CODE.
export const PUBLIC_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const alphabet = PUBLIC_CODE_ALPHABET;
export const generatePublicCode = () => Array.from({length:12},()=>alphabet[randomInt(alphabet.length)]).join('');

/** Idempotent online backfill. Reservation and account update commit together. */
export async function ensurePublicCode(uid:string, metadata:Record<string,unknown> = {}) {
  const db=getFirestore(), ref=db.doc(`users/${uid}`);
  for(let attempt=0;attempt<10;attempt++) {
    const candidate=generatePublicCode();
    const result=await db.runTransaction(async tx=>{
      const snap=await tx.get(ref);
      const rawExisting=snap.data()?.publicCode;
      const validExisting=typeof rawExisting==='string'&&PUBLIC_CODE.test(rawExisting)?rawExisting:null;
      const code=validExisting??candidate;
      const reservation=db.doc(`public_user_codes/${code}`), held=await tx.get(reservation);
      if(held.exists&&held.data()?.uid!==uid) {
        return null;
      }
      tx.set(reservation,{uid});
      const legacy=snap.data()?.familyId;
      tx.set(ref,{...metadata,publicCode:code,
        ...(legacy?{familyIds:Array.from(new Set([...(snap.data()?.familyIds??[]),legacy]))}:{}),
      },{merge:true});
      return code;
    });
    if(result)return result;
  }
  throw new DomainError('identity-unavailable');
}

/** Charge attempts in their own transaction, including unsuccessful lookups. */
export async function limitIdentityAttempts(uid:string,bucket='identity') {
  const db=getFirestore(),ref=db.doc(`identity_attempts/${bucket==='identity'?uid:`${bucket}_${uid}`}`),now=Date.now();
  await db.runTransaction(async tx=>{
    const d=(await tx.get(ref)).data();
    const count=d&&d.resetAt>now?d.count:0;
    if(count>=20)throw new DomainError('rate-limited');
    tx.set(ref,{count:count+1,resetAt:d&&d.resetAt>now?d.resetAt:now+3600000});
  });
}
