/**
 * Leitura dos oito conjuntos (manifesto, blocos e diferenças) pelo backend.
 * A TV nunca lê `catalogs/**` direto: cada resposta passa por `authorize` (credencial,
 * lease, assinatura, PIN) e é filtrada para o perfil ativo (permissões de espaço,
 * conteúdo adulto, classificação etária), como em readSourceCatalog.
 */
import {z} from 'zod';
import {DomainError, hash, idSchema} from './domain';
import {isAdultContent} from './content_audience';
import {spaceAllowed} from './family_profiles';
import {authorize, canSee, load, type Viewer} from './iptv_catalog_access';
import {ITEM_SETS, MAX_DELTA_CHAIN, SET_NAMES, persistCatalogSets, readChunk, readDeltaChunk, readManifest, type CatalogManifest, type SetName, type SetRecord} from './catalog_sets';
import type {Identity} from './service';

const setSchema = z.enum(SET_NAMES);
const isItemSet = (set: SetName) => (ITEM_SETS as readonly string[]).includes(set);
const MAX_DELTA_RECORDS = 30000;

/** Mesma forma pública de readSourceCatalog (compatível com o cliente atual). */
const publicItem = (sourceId: string, version: string, record: SetRecord) => ({...record, id: hash(`${sourceId}:${record.id}`), catalogItemId: record.id, sourceId, version});

/** O perfil pode ver conteúdo adulto? (limite do administrador E preferência do membro; o administrador liga/desliga o próprio.) */
export const adultEnabled = (viewer: Viewer): boolean => !viewer || viewer.permissions.adult;

function visibleRecords(viewer: Viewer, sourceId: string, set: SetName, records: SetRecord[]): SetRecord[] {
  // Categorias fixas do conteúdo adulto: só para quem está habilitado (e tem o tipo liberado).
  if (set === 'adult_categories') {
    if (!adultEnabled(viewer)) return [];
    if (!viewer) return records;
    return records.filter(r => spaceAllowed(viewer.permissions, sourceId, String(r.kind)));
  }
  if (isItemSet(set)) return records.filter(r => canSee(viewer, sourceId, r as unknown as Parameters<typeof canSee>[2]));
  // Categorias: sem permissão para o tipo/adulto, o nome nem é enviado (vazias são ocultadas pelo cliente).
  if (!viewer) return records;
  return records.filter(r => {
    const kind = String(r.kind);
    if (!spaceAllowed(viewer.permissions, sourceId, kind)) return false;
    return viewer.permissions.adult || !isAdultContent({category: String(r.name ?? '')});
  });
}
const shape = (viewer: Viewer, sourceId: string, version: string, set: SetName, records: SetRecord[]) => {
  const visible = visibleRecords(viewer, sourceId, set, records);
  return isItemSet(set) ? visible.map(r => publicItem(sourceId, version, r)) : visible;
};

/** Impressão digital do que este perfil pode ver: se mudar (adulto, espaços, tipo), o cache da TV é refeito. */
const viewerFingerprint = (viewer: Viewer) =>
  hash(JSON.stringify(viewer ? {t: viewer.type, a: viewer.permissions.adult, all: viewer.permissions.allSpaces, s: [...viewer.permissions.spaces].sort(), k: viewer.permissions.kinds} : null));

async function currentManifest(actor: Identity, input: Record<string, unknown>) {
  const id = idSchema.parse(input.id), access = await authorize(actor, id, false, input.profileId);
  const version = access.data.version as string;
  if (input.version && input.version !== version) throw new DomainError('source-conflict');
  let manifest = await readManifest(version);
  // Fontes já sincronizadas antes deste formato: monta os conjuntos uma vez, sem nova sincronização.
  if (!manifest) manifest = await persistCatalogSets(version, await load(version), null);
  return {id, version, access, manifest};
}

export async function readCatalogManifest(input: Record<string, unknown>, actor: Identity) {
  const {id, version, manifest, access} = await currentManifest(actor, input);
  return {
    schemaVersion: manifest.schemaVersion, sourceId: id, version, previousVersion: manifest.previousVersion, viewerKey: viewerFingerprint(access.viewer),
    // Habilitação do conteúdo adulto neste perfil (definida no iPlex Control): o menu "Adulto" da TV depende dela.
    adultEnabled: adultEnabled(access.viewer),
    // Sem contagens de itens: elas revelariam o volume de conteúdo oculto ao perfil.
    sets: Object.fromEntries(SET_NAMES.map(name => [name, {chunks: manifest.sets[name].chunks, hash: manifest.sets[name].hash}])),
    deltaAvailable: !!manifest.delta,
  };
}

export async function readCatalogChunk(input: Record<string, unknown>, actor: Identity) {
  const set = setSchema.parse(input.set), n = z.number().int().min(0).max(9999).parse(input.n);
  const {id, version, access, manifest} = await currentManifest(actor, input);
  if (n >= manifest.sets[set].chunks) throw new DomainError('not-found');
  let rows: SetRecord[];
  try { rows = await readChunk(version, set, n); } catch { throw new DomainError('catalog-integrity'); }
  return {schemaVersion: 1, sourceId: id, version, set, n, chunks: manifest.sets[set].chunks, records: shape(access.viewer, id, version, set, rows)};
}

type Step = {version: string; sets: Partial<Record<SetName, {upserts: unknown[]; deletes: string[]}>>};
/** Cadeia de diferenças {from → versão atual}; null quando não for confiável (cliente reconstrói). */
async function deltaChain(version: string, from: string): Promise<CatalogManifest[] | null> {
  const chain: CatalogManifest[] = [];
  let cursor: string | null = version;
  while (cursor && chain.length < MAX_DELTA_CHAIN) {
    const manifest = await readManifest(cursor);
    if (!manifest?.delta) return null;
    chain.unshift(manifest);
    if (manifest.delta.from === from) return chain;
    cursor = manifest.previousVersion;
  }
  return null;
}

export async function readCatalogDelta(input: Record<string, unknown>, actor: Identity) {
  const from = z.string().regex(/^[a-f0-9]{64}$/).parse(input.from);
  const {id, version, access, manifest} = await currentManifest(actor, input);
  if (from === version) return {schemaVersion: 1, sourceId: id, from, to: version, full: false, steps: [] as Step[]};
  const chain = await deltaChain(version, from);
  if (!chain) return {schemaVersion: 1, sourceId: id, from, to: version, full: true, reason: 'history-unavailable', manifestHash: manifest.version};
  let total = 0;
  for (const m of chain) for (const name of SET_NAMES) total += (m.delta!.sets[name]?.upserts ?? 0) + (m.delta!.sets[name]?.deletes ?? 0);
  if (total > MAX_DELTA_RECORDS) return {schemaVersion: 1, sourceId: id, from, to: version, full: true, reason: 'too-large'};
  const steps: Step[] = [];
  try {
    for (const m of chain) {
      const step: Step = {version: m.version, sets: {}};
      for (const name of SET_NAMES) {
        const summary = m.delta!.sets[name];
        if (!summary || (!summary.upserts && !summary.deletes)) continue;
        const upserts: SetRecord[] = [], deletes: string[] = [];
        for (let n = 0; n < summary.chunks; n += 1) {
          const part = await readDeltaChunk(m.version, m.delta!.from, name, n);
          upserts.push(...part.upserts); deletes.push(...part.deletes);
        }
        step.sets[name] = {upserts: shape(access.viewer, id, m.version, name, upserts), deletes: isItemSet(name) ? deletes.map(d => hash(`${id}:${d}`)) : deletes};
      }
      steps.push(step);
    }
  } catch { return {schemaVersion: 1, sourceId: id, from, to: version, full: true, reason: 'delta-integrity'}; }
  return {schemaVersion: 1, sourceId: id, from, to: version, full: false, steps};
}
