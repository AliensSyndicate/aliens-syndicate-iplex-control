/**
 * Development-only TV simulator for pairing without a physical Player.
 *
 *   npx tsx scripts/dev_pairing_qr.ts create [--wait]   # real session + QR files
 *   npx tsx scripts/dev_pairing_qr.ts cleanup           # removes simulated TVs
 *
 * It calls the same `beginDevicePair`/`finishDevicePair` code the Player uses, so
 * the QR carries a genuine single-use backend token. It refuses to run unless
 * the Firestore and Auth emulators are configured for a `demo-` project: there
 * is no production switch and nothing here is deployed.
 */
import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {randomUUID} from 'node:crypto';
import {mkdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import QRCode from 'qrcode';
import {execute} from '../src/service';
import {hash} from '../src/domain';
import {hashPairingCode} from '../src/device_identity';

const project = process.env.GCLOUD_PROJECT ?? 'demo-iplex';
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST || !project.startsWith('demo-')) {
  console.error('Refusing to run: set FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST for a demo- project.');
  process.exit(2);
}
initializeApp({projectId: project});
const db = getFirestore(), registry = db.collection('dev_simulated_devices');

async function create(wait: boolean) {
  const nativeDeviceId = `simulated-${randomUUID()}`;
  const session = await execute('beginDevicePair', {
    name: 'iPlex Test TV', platform: 'android_tv', manufacturer: 'iPlex', model: 'Simulated TV',
    nativeDeviceId, identitySource: 'simulated', identityScope: 'test_only', identityStability: 'test_only',
  }, undefined) as {token: string; code: string; formattedCode: string; deviceId: string; expiresAt: number};
  await registry.doc(session.deviceId).set({tokenHash: hash(session.token), codeHash: hashPairingCode(session.code), nativeDeviceId, createdAt: Date.now()});
  const uri = `iplex://pair?token=${session.token}`, out = join(__dirname, '..', '..', 'build', 'dev-pairing');
  mkdirSync(out, {recursive: true});
  await QRCode.toFile(join(out, 'pairing-qr.png'), uri, {width: 480, margin: 2});
  writeFileSync(join(out, 'pairing-qr.svg'), await QRCode.toString(uri, {type: 'svg', margin: 2}));
  console.log(await QRCode.toString(uri, {type: 'terminal', small: true}));
  console.log(`deviceId     ${session.deviceId}`);
  console.log(`manual code  ${session.formattedCode}`);
  console.log(`expires at   ${new Date(session.expiresAt).toISOString()}`);
  console.log(`QR files     ${out}/pairing-qr.{png,svg}`);
  if (!wait) return;
  console.log('Waiting for the Gestor to confirm the pairing…');
  const ref = db.doc(`link_tokens/${hash(session.token)}`);
  while (Date.now() < session.expiresAt) {
    if ((await ref.get()).data()?.used) {
      // Same exchange the Player performs once the Gestor confirms.
      await execute('finishDevicePair', {token: session.token}, undefined);
      const device = (await db.doc(`devices/${session.deviceId}`).get()).data();
      console.log(`Linked: ${device?.displayName} (${device?.ownership}) by ${device?.linkedByUid}; Player credential issued.`);
      return;
    }
    await new Promise(r => setTimeout(r, 1500));
  }
  console.log('Session expired before confirmation.');
}

async function cleanup() {
  const rows = await registry.get();
  for (const row of rows.docs) {
    const device = await db.doc(`devices/${row.id}`).get(), familyId = device.data()?.familyId;
    const batch = db.batch();
    if (familyId) batch.delete(db.doc(`families/${familyId}/devices/${row.id}`));
    batch.delete(device.ref);
    batch.delete(db.doc(`link_tokens/${row.data().tokenHash}`));
    batch.delete(db.doc(`device_pairing_sessions/${row.data().tokenHash}`));
    if (row.data().codeHash) batch.delete(db.doc(`device_pairing_codes/${row.data().codeHash}`));
    batch.delete(row.ref);
    await batch.commit();
  }
  console.log(`Removed ${rows.size} simulated device(s).`);
}

const [command, flag] = process.argv.slice(2);
(command === 'cleanup' ? cleanup() : command === 'create' ? create(flag === '--wait') : Promise.reject(new Error('usage: create [--wait] | cleanup')))
  .then(() => process.exit(0), error => { console.error(error); process.exit(1); });
