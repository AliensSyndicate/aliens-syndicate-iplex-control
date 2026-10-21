import {DomainError} from './domain';
import {
  defaultAdapterRegistry,
  findM3uStream,
  IptvAdapterRegistry,
  IptvSourceAdapter,
  normalizeSeriesDetail,
  playlistBody,
  ProviderFetch,
  ProviderSnapshot,
  Source,
  validateXtream,
  xtreamUrl,
} from './iptv_adapters';
import {detectSourceFormat} from './iptv_detection';
import {fetchProvider} from './catalog';

export {
  Source,
  ProviderFetch,
  ProviderSnapshot,
  xtreamUrl,
  validateXtream,
  playlistBody,
  normalizeSeriesDetail,
  findM3uStream,
};

/**
 * Fetch using this source's secret before consulting any shared proof.
 * Uses the Extensible IPTV Adapter Architecture and Automatic Detection Pipeline.
 * Raw responses never enter global Firestore documents or public object metadata.
 */
export async function fetchSnapshot(
  source: Source,
  fid: string,
  sourceId: string,
  fetch: ProviderFetch = fetchProvider,
  registry: IptvAdapterRegistry = defaultAdapterRegistry
): Promise<ProviderSnapshot> {
  const transport = fetch;
  let downloaded = 0;
  const deadline = Date.now() + 300000;
  // One download per URL and sync: detection, access validation and extraction
  // share the same response (lists used to be downloaded up to three times,
  // tripling time, provider connections and the 64 MB budget).
  const responses = new Map<string, Promise<string>>();

  const budgetedFetch: ProviderFetch = url => {
    let pending = responses.get(url);
    if (!pending) {
      pending = (async () => {
        if (Date.now() > deadline) throw new DomainError('provider-time-budget', {reason: 'sync-budget'});
        const body = await transport(url);
        downloaded += Buffer.byteLength(body, 'utf8');
        if (downloaded > 64 * 1024 * 1024) throw new DomainError('catalog-too-large', {bytes: downloaded});
        return body;
      })();
      responses.set(url, pending);
      // Failures are not cached: an explicit retry (Xtream lists) hits the network again.
      pending.catch(() => responses.delete(url));
    }
    return pending;
  };

  // 1. Detect format and select adapter
  const detection = await detectSourceFormat(source, budgetedFetch, registry);
  const adapter = detection.adapter;

  // 2. Validate provider access
  await adapter.validateAccess(source, budgetedFetch);

  // 3. Extract and normalize catalog using the adapter
  return adapter.extractCatalog(source, fid, sourceId, budgetedFetch);
}
