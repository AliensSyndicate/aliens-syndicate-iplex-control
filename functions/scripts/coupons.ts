/**
 * Operação de cupons e acesso vitalício (Admin SDK, credenciais do operador via ADC).
 *
 *   npx tsx scripts/coupons.ts create [--uses 1] [--expires 2027-12-31] [--note "texto"]
 *       Cria um cupom vitalício e imprime o código UMA vez (só o hash fica no Firestore).
 *   npx tsx scripts/coupons.ts disable <código>
 *   npx tsx scripts/coupons.ts grant <email> [--apply]
 *       Concede vitalício direto ao escopo que o usuário administra. Sem --apply só mostra o que faria.
 *
 * Projeto: GCLOUD_PROJECT (padrão iplex-2c8fc).
 */
import {randomBytes} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {couponRef, lifetimeSubscription, type Coupon} from '../src/coupons';

initializeApp({projectId: process.env.GCLOUD_PROJECT || 'iplex-2c8fc'});
const [command, arg, ...rest] = process.argv.slice(2);
const flag = (name: string) => {
  const all = [arg, ...rest], i = all.indexOf(`--${name}`);
  return i >= 0 ? all[i + 1] : undefined;
};
const has = (name: string) => [arg, ...rest].includes(`--${name}`);

/** Sem 0/O/1/I para ditar sem ambiguidade. Formato IPLEX-XXXX-XXXX-XXXX. */
function newCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', bytes = randomBytes(12);
  const chars = [...bytes].map(b => alphabet[b % alphabet.length]).join('');
  return `IPLEX-${chars.slice(0, 4)}-${chars.slice(4, 8)}-${chars.slice(8, 12)}`;
}

async function create() {
  const code = newCode(), uses = Number(flag('uses') ?? 1), expires = flag('expires');
  if (!Number.isInteger(uses) || uses < 1) throw new Error('--uses deve ser inteiro >= 1');
  const coupon: Coupon = {plan: 'lifetime', maxRedemptions: uses, redemptions: 0, createdAt: Date.now(),
    ...(expires ? {expiresAt: Date.parse(`${expires}T23:59:59-03:00`)} : {}), ...(flag('note') ? {note: flag('note')} : {})};
  if (coupon.expiresAt !== undefined && !Number.isFinite(coupon.expiresAt)) throw new Error('--expires inválido (AAAA-MM-DD)');
  await couponRef(code).create(coupon);
  console.log(`Cupom vitalício criado (${uses} uso(s)${expires ? `, válido até ${expires}` : ''}):\n\n  ${code}\n\nGuarde agora: o código não é armazenado.`);
}

async function disable() {
  if (!arg) throw new Error('informe o código');
  await couponRef(arg).update({disabled: true});
  console.log('Cupom desativado.');
}

async function grant() {
  if (!arg) throw new Error('informe o e-mail');
  const user = await getAuth().getUserByEmail(arg), db = getFirestore();
  const profile = (await db.doc(`users/${user.uid}`).get()).data();
  // As TVs vinculam na família (users.familyId) e é lá que o Player confere a assinatura.
  const scopeId = (profile?.familyId ?? profile?.iptvWorkspaceId) as string | undefined;
  if (!scopeId) throw new Error(`${arg} (${user.uid}) não administra família/escopo`);
  const family = (await db.doc(`families/${scopeId}`).get()).data();
  const admin = (family?.adminUid ?? family?.adminId) === user.uid || (family?.kind === 'personalIptv' && family?.ownerId === user.uid);
  if (!admin) throw new Error(`${arg} não é administrador de families/${scopeId}`);
  const ref = db.doc(`families/${scopeId}/private/subscription`), current = (await ref.get()).data();
  console.log(`Usuário: ${arg} (${user.uid})\nEscopo: families/${scopeId}\nAtual: ${JSON.stringify(current ?? null)}`);
  if (!has('apply')) return console.log('\nSimulação: rode de novo com --apply para gravar status lifetime.');
  await ref.set(lifetimeSubscription(current, Date.now(), {lifetimeSource: 'grant', grantedBy: 'operator'}));
  console.log('\nVitalício concedido.');
}

const commands: Record<string, () => Promise<void>> = {create, disable, grant};
if (!commands[command ?? '']) {
  console.error('uso: coupons.ts create|disable|grant …');
  process.exit(1);
}
commands[command!]!().catch(error => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
