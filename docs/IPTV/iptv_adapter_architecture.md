# CODEX — iPlex: Arquitetura de Adaptadores IPTV

## 1. Princípios Arquiteturais
A camada de sincronização IPTV do iPlex foi desenhada com base no padrão **Adapter + Registry**. O núcleo do pipeline de sincronização desconhece detalhes de protocolos externos: ele interage exclusivamente com a interface `IptvSourceAdapter`.

```text
                  +-------------------------+
                  |    IptvSyncEngine       |
                  | (iptv_sync / ingestion) |
                  +------------+------------+
                               |
                               v
                  +-------------------------+
                  |   IptvAdapterRegistry   |
                  +------------+------------+
                               |
       +-----------------------+-----------------------+
       |                       |                       |
       v                       v                       v
+---------------+       +---------------+       +---------------+
| XtreamAdapter |       |  M3uAdapter   |       |  HlsAdapter   |
+---------------+       +---------------+       +---------------+
       |                       |                       |
       v                       v                       v
+---------------+       +---------------+       +---------------+
| DirectAdapter |       | FutureAdapter |       | CustomAdapter |
+---------------+       +---------------+       +---------------+
```

---

## 2. Contrato da Interface `IptvSourceAdapter`

Localização: `functions/src/iptv_adapters.ts`

```typescript
export interface SourceLimitations {
  readonly supportsEpg: boolean;
  readonly supportsSeries: boolean;
  readonly supportsVod: boolean;
  readonly supportsCatchup: boolean;
  readonly isSingleStream: boolean;
}

export interface IptvSourceAdapter {
  readonly name: string;
  readonly format: string;

  /**
   * Avalia se a fonte pode ser processada por este adaptador.
   */
  supports(source: Source, sample?: {contentType?: string; body?: string}): Promise<boolean> | boolean;

  /**
   * Valida as credenciais ou a disponibilidade de acesso ao recurso.
   */
  validateAccess(source: Source, fetch: ProviderFetch): Promise<void>;

  /**
   * Normaliza e identifica o servidor em servers/{serverId}.
   * Retorna null se não houver servidor convencional (ex: arquivos locais).
   */
  identifyServer(source: Source): {canonicalEndpoint: string; identityHash: string} | null;

  /**
   * Extrai e normaliza o catálogo em formato ProviderSnapshot e JSON versionado.
   */
  extractCatalog(source: Source, fid: string, sourceId: string, fetch: ProviderFetch): Promise<ProviderSnapshot>;

  /**
   * Informa as capacidades e limitações do adaptador.
   */
  getLimitations(source: Source): SourceLimitations;
}
```

---

## 3. Adaptadores Implementados

### 3.1 `XtreamAdapter`
- **Responsabilidade:** Consumo de APIs Xtream Codes (`player_api.php`).
- **Endpoints de Descoberta:** Canais, Filmes, Séries, Episódios e Temporadas.
- **Normalização de Séries:** Estrutura aninhada `{seasons: [...], episodes: { [season]: [...] } }`.
- **Tolerância a Falhas:** Continua a execução caso o provedor falhe ao entregar detalhes de uma série específica ou não implemente VOD.

### 3.2 `M3uPlaylistAdapter`
- **Responsabilidade:** Consumo de listas M3U / M3U Plus remotas e arquivos locais.
- **Parsing:** Interpretação linear e segura com buffer de 64 MB.
- **Identidade:** Deduplicação precisa baseada no conteúdo completo e categorias originais.

### 3.3 `HlsManifestAdapter`
- **Responsabilidade:** Manifestos HLS diretos de canais ao vivo e reprodução de mídia.
- **Diferenciação:** Bloqueia a fragmentação de segmentos de vídeo em falsos canais; emite exatamente 1 item de catálogo (`isSingleStream: true`).

### 3.4 `DirectStreamAdapter`
- **Responsabilidade:** Arquivos de vídeo e streams diretos (`.mp4`, `.mkv`, `.ts`, `.mpd`).
- **Classificação:** Classifica como filme ou canal único de acordo com o container.

---

## 4. Registro Dinâmico e Extensibilidade (`IptvAdapterRegistry`)

Novos adaptadores podem ser adicionados ao sistema em tempo de execução sem alteração de schemas ou do código-fonte de sincronização:

```typescript
import {defaultAdapterRegistry, IptvSourceAdapter} from './iptv_adapters';

export class StalkerMinistraAdapter implements IptvSourceAdapter {
  readonly name = 'Stalker Portal / Ministra';
  readonly format = 'stalker';

  supports(source, sample) {
    return source.url?.includes('/stalker_portal/') ?? false;
  }

  async validateAccess(source, fetch) {
    // handshake com o portal Stalker
  }

  identifyServer(source) {
    // normalização de endpoint
  }

  async extractCatalog(source, fid, sourceId, fetch) {
    // extração normalizada
  }

  getLimitations(source) {
    return {
      supportsEpg: true,
      supportsSeries: true,
      supportsVod: true,
      supportsCatchup: true,
      isSingleStream: false,
    };
  }
}

// Registro no registry compartilhado:
defaultAdapterRegistry.register(new StalkerMinistraAdapter());
```

---

## 5. Contrato de Saída: Catálogo Normalizado (Cloud Storage)

Todos os adaptadores produzem um documento JSON padronizado armazenado em `catalogs/{version}.json`, validado pelo `catalogSchema`:

```json
{
  "schemaVersion": 1,
  "items": [
    {
      "id": "hash_canonical_id",
      "title": "Nome do Conteúdo",
      "titleKey": "nome do conteudo",
      "kind": "channel",
      "category": "Nome Original da Categoria",
      "providerRef": "ref_original",
      "epgId": "id_epg_opcional",
      "imageRef": "hash_icone_opcional",
      "containerExtension": "ts"
    }
  ],
  "categories": [
    {
      "id": "cat_id",
      "name": "Nome Original",
      "kind": "channel"
    }
  ],
  "seriesDetails": {
    "series_id": {
      "seasons": [],
      "episodes": {}
    }
  }
}
```
Este contrato é 100% consumível pelo TV Player (React/TypeScript) e pelo App Flutter sem dependência de lógica específica de cada fornecedor.
