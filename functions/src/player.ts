/**
 * Endpoint `player`: o iPlex Web na Smart TV fala com o backend por aqui.
 *
 * Por quê: a callable `manager` exige Firebase App Check, e o único provedor
 * web (reCAPTCHA Enterprise) é incompatível com o Chromium 69 do Samsung
 * Tizen 5.5 (fecha o app). O `manager` continua exigindo App Check para o
 * Gestor; a TV usa este endpoint, que NÃO exige App Check e, em troca:
 *
 *  - aceita só uma LISTA FECHADA de ações de Player;
 *  - ações protegidas exigem a credencial de dispositivo emitida no pareamento
 *    (custom token `tv_<deviceId>` com claims deviceId/familyId), validada pelo
 *    Firebase no servidor. Nada vindo do corpo da requisição identifica a TV;
 *  - toda regra de negócio é a MESMA do `manager` (execute() em service.ts):
 *    dispositivo vinculado e família ativa, assinatura, lease (3 sessões, 1 por
 *    perfil), permissões do perfil e classificação infantil;
 *  - desvincular no Gestor apaga o documento do dispositivo: toda ação protegida
 *    passa a falhar com device-revoked imediatamente;
 *  - beginDevicePair/finishDevicePair são a única exceção sem credencial:
 *    criam/consomem uma sessão de pareamento de 5 min, de uso único, que só
 *    vira credencial depois de um administrador autenticado no Gestor (com
 *    App Check) confirmar. Têm cotas por janela; não dão acesso a perfis,
 *    catálogo ou reprodução.
 *
 * Endereço de rede e User-Agent NUNCA são prova de identidade; o endereço é
 * usado apenas para repartir as cotas anti-abuso.
 */
import {createHash} from 'node:crypto';
import {getFirestore} from 'firebase-admin/firestore';
import {DomainError} from './domain';
import {activePlayer,type Identity} from './service';
import {authorizeMetadata,readPlayerLibrary} from './iptv_catalog_access';

/** Pré-pareamento: sem credencial, com cotas. */
export const PLAYER_PUBLIC_ACTIONS: ReadonlySet<string> = new Set(['beginDevicePair', 'finishDevicePair']);

/** Ações de Player que exigem a credencial do dispositivo vinculado. */
export const PLAYER_DEVICE_ACTIONS: ReadonlySet<string> = new Set([
  'readPlayerLibrary',
  'readPlayerGenerations',
  'authorizeMetadata',
  'listPlayerProfiles',
  'listProfileSpaces',
  'syncPlayerSource',
  'acquireSession',
  'heartbeat',
  'reportPlayback',
  'releaseSession',
  'verifyProfilePin',
  'verifyAdultPin',
  'claimPlayRequest',
  'updatePlayRequest',
  'readSourceCatalog',
  'readCatalogManifest',
  'readCatalogChunk',
  'readCatalogDelta',
  'readSourceSeries',
  'readSourceEpg',
  'resolveSourceStream',
  'favorite',
  'wishlist',
  'watchProgress',
  'markWatched',
]);

export interface PlayerAuth {
  uid: string;
  token: Record<string, unknown>;
}

/**
 * Identidade do Player a partir do token VERIFICADO pelo Firebase. Recusa
 * contas de pessoa, claims ausentes ou incoerentes e tokens que não vieram do
 * custom token de pareamento.
 */
export function playerIdentity(auth: PlayerAuth | undefined): Identity {
  if (!auth) throw new DomainError('unauthenticated');
  if (!auth.token || typeof auth.token !== 'object' || typeof auth.uid !== 'string') throw new DomainError('device-required');
  const {deviceId, familyId} = auth.token;
  const provider = (auth.token.firebase as {sign_in_provider?: unknown} | undefined)?.sign_in_provider;
  if (typeof deviceId !== 'string' || typeof familyId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(deviceId) || !/^[A-Za-z0-9_-]{1,128}$/.test(familyId)) throw new DomainError('device-required');
  if (auth.uid !== `tv_${deviceId}` || provider !== 'custom') throw new DomainError('device-required');
  return {uid: auth.uid, deviceId, familyId, ...(typeof auth.token.credentialVersion==='string'?{credentialVersion:auth.token.credentialVersion}:{}), authTime: typeof auth.token.auth_time === 'number' ? auth.token.auth_time : undefined};
}

export interface QuotaRule {
  bucket: string;
  max: number;
  windowMs: number;
}

/** Cotas das ações sem credencial (por janela). */
export const PUBLIC_QUOTAS: Record<string, {global: QuotaRule; network: QuotaRule}> = {
  // Uma TV gera um código a cada 5 min; folga para várias TVs na mesma rede.
  beginDevicePair: {
    global: {bucket: 'player_begin_global', max: 600, windowMs: 10 * 60_000},
    network: {bucket: 'player_begin_net', max: 20, windowMs: 10 * 60_000},
  },
  // Consulta com recuo exponencial (3 s → 15 s): ~40 consultas por código.
  finishDevicePair: {
    global: {bucket: 'player_finish_global', max: 20000, windowMs: 10 * 60_000},
    network: {bucket: 'player_finish_net', max: 400, windowMs: 10 * 60_000},
  },
};

export type QuotaFn = (key: string, rule: QuotaRule, now: number) => Promise<void>;

/**
 * Cota em janela fixa, no mesmo padrão de identity_attempts (coleção sem
 * acesso de clientes nas regras do Firestore).
 */
export const firestoreQuota: QuotaFn = async (key, rule, now) => {
  const db = getFirestore();
  const window = Math.floor(now / rule.windowMs);
  const ref = db.doc(`identity_attempts/${rule.bucket}_${key}_${window}`);
  await db.runTransaction(async tx => {
    const count = ((await tx.get(ref)).data()?.count as number | undefined) ?? 0;
    if (count >= rule.max) throw new DomainError('rate-limited');
    tx.set(ref, {count: count + 1, resetAt: (window + 1) * rule.windowMs, expireAt: new Date((window + 2) * rule.windowMs)});
  });
};

/** Repartição anti-abuso por rede (hash; nunca guardado em claro, nunca prova). */
export function networkKey(ip: string | undefined): string {
  return createHash('sha256').update(`player-net:${ip || 'unknown'}`).digest('hex').slice(0, 32);
}

const PUBLIC_PAYLOAD_LIMIT = 4096;

export interface PlayerRequest {
  action: unknown;
  payload: unknown;
  auth: PlayerAuth | undefined;
  ip: string | undefined;
}

export interface PlayerDeps {
  execute: (action: string, input: unknown, actor: Identity | undefined, key?: string) => Promise<unknown>;
  quota: QuotaFn;
  consume?: (actor:Identity, action:string, payload:Record<string,unknown>, now:number)=>Promise<void>;
  now: () => number;
}

export async function runPlayer(request: PlayerRequest, key: string, deps: PlayerDeps): Promise<unknown> {
  const action = typeof request.action === 'string' ? request.action : '';
  const payload = request.payload ?? {};
  if (PLAYER_PUBLIC_ACTIONS.has(action)) {
    if (JSON.stringify(payload).length > PUBLIC_PAYLOAD_LIMIT) throw new DomainError('invalid-argument');
    const now = deps.now(), quotas = PUBLIC_QUOTAS[action]!;
    await deps.quota('all', quotas.global, now);
    await deps.quota(networkKey(request.ip), quotas.network, now);
    // Sem identidade: o pareamento não depende de quem chama, só do token/código.
    return deps.execute(action, payload, undefined, key);
  }
  if (!PLAYER_DEVICE_ACTIONS.has(action)) throw new DomainError('invalid-action');
  const actor = playerIdentity(request.auth);
  const now=deps.now();
  await deps.quota(networkKey(actor.uid),{bucket:'player_device',max:600,windowMs:60_000},now);
  if(!payload||typeof payload!=='object'||Array.isArray(payload)||JSON.stringify(payload).length>16384)throw new DomainError('invalid-argument');
  const p=payload as Record<string,unknown>;
  if(SENSITIVE_ACTIONS.has(action)){
   if(!deps.consume)throw new DomainError('operation-failed');
   await deps.consume(actor,action,p,now);
  }
  if(action==='authorizeMetadata')return authorizeMetadata(p,actor);
  if(action==='readPlayerLibrary')return readPlayerLibrary(p,actor);
  if(action==='readPlayerGenerations')return getFirestore().runTransaction(async tx=>(await activePlayer(tx,actor,p.profileId)).view.generations);
  return deps.execute(action, payload, actor, key);
}

/** One-use request id for operations which change access or persistent state. */
export const SENSITIVE_ACTIONS=new Set(['acquireSession','releaseSession','resolveSourceStream','favorite','wishlist','watchProgress','markWatched','verifyProfilePin','verifyAdultPin','claimPlayRequest','updatePlayRequest']);
export async function consumePlayerRequest(actor:Identity,action:string,payload:Record<string,unknown>,now:number){
 const requestId=payload.requestId,issuedAt=payload.issuedAt;
 if(typeof requestId!=='string'||!/^[a-f0-9]{32}$/.test(requestId)||typeof issuedAt!=='number'||!Number.isFinite(issuedAt)||Math.abs(now-issuedAt)>120_000)throw new DomainError('request-expired');
 const ref=getFirestore().doc(`player_requests/${networkKey(actor.uid)}_${requestId}`);
 await getFirestore().runTransaction(async tx=>{
  if((await tx.get(ref)).exists)throw new DomainError('request-replayed');
  tx.create(ref,{action,expireAt:new Date(now+300_000)});
 });
}
