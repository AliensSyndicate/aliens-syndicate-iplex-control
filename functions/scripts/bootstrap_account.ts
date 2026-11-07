/**
 * Roda o `bootstrap` real do backend para uma conta já criada no Authentication
 * (mesmo efeito do primeiro login: users/{uid}, código público, família individual).
 * Idempotente. Credenciais do operador via ADC.
 *
 *   npx tsx scripts/bootstrap_account.ts <uid> <email-esperado> [--apply]
 *
 * Sem --apply só confere o UID e o e-mail.
 */
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {execute} from '../src/service';

initializeApp({projectId: process.env.GCLOUD_PROJECT || 'iplex-2c8fc'});
const [uid, expected, ...flags] = process.argv.slice(2);
if (!uid || !expected) { console.error('uso: bootstrap_account.ts <uid> <email> [--apply]'); process.exit(1); }

async function main() {
  const user = await getAuth().getUser(uid);
  if (user.email?.toLowerCase() !== expected.toLowerCase()) {
    console.error(`UID ${uid} pertence a ${user.email}, não a ${expected}. Nada foi feito.`); process.exit(1);
  }
  console.log(`Conta confirmada: ${user.email} (provedores: ${user.providerData.map(p => p.providerId).join(', ')})`);
  if (!flags.includes('--apply')) { console.log('Dry-run: use --apply para executar o bootstrap.'); process.exit(0); }
  await execute('bootstrap', {}, {uid});
  const data = (await getFirestore().doc(`users/${uid}`).get()).data();
  console.log(`bootstrap ok: publicCode=${data?.publicCode}, familyId=${data?.familyId}`);
}
main().catch(e => { console.error(e?.message ?? e); process.exit(1); });
