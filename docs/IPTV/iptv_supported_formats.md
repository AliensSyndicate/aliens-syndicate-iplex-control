# CODEX — iPlex: Formatos IPTV Suportados e Capacidades Técnicas

## 1. Visão Geral
O iPlex implementa arquitetura aberta, modular e extensível para consumo e processamento de fontes IPTV. O sistema não impõe dependência de fornecedores comerciais, não restringe o usuário a formatos específicos e garante paridade de processamento entre fontes remotas e arquivos locais.

---

## 2. Matriz de Formatos Técnicos

| Formato | Identificador Técnico | Protocolos | Entradas Aceitas | Capacidades Extraídas | Limitações Conhecidas |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Xtream Codes API** | `xtream` | HTTP, HTTPS | URL do servidor, Usuário, Senha, Porta | Canais ao vivo, Filmes (VOD), Séries, Temporadas, Episódios, Categorias originais, Ícones/Capas, EPG | Requer servidor ativo com autenticação válida. Servidores parciais podem omitir VOD ou séries sem falhar o sincronismo. |
| **M3U / M3U Plus** | `m3u` | HTTP, HTTPS, Arquivo Local | URL remota, Arquivo importado (.m3u, .m3u8) | Canais ao vivo, Filmes, Séries em lista, `group-title`, `tvg-id`, `tvg-name`, `tvg-logo` | Não possui paginação nativa nem hierarquia de temporadas/episódios sem atributos específicos. |
| **HLS Manifest** | `other_m3u8` | HTTP, HTTPS | URL remota (.m3u8) | Live Stream único, Master manifest com variantes de bitrate/resolução | Não representa catálogo de múltiplos canais; trata manifestos de mídia e master como um único stream contínuo. |
| **Direct Stream** | `direct_stream` | HTTP, HTTPS | URL de mídia direta (.mp4, .mkv, .ts, .mpd, .avi) | Mídia única de vídeo/áudio ou stream direto com metadados | Não possui EPG ou categorias complexas; classificado diretamente como stream/filme individual. |
| **Adaptadores Futuros** | Extensível | HTTP, HTTPS, WebSockets | Registrados via `IptvAdapterRegistry` | Definidas pelo adaptador customizado | Depende da implementação do adaptador no backend. |

---

## 3. Especificação Detalhada por Formato

### 3.1 Xtream Codes API (`xtream`)
- **Parâmetros de Entrada:**
  - `url`: Host do servidor (com ou sem porta explícita). Exemplo: `http://iptv.server.io:8080/`.
  - `username`: Nome de usuário fornecido pelo provedor.
  - `password`: Senha de autenticação.
- **Validação de Acesso:**
  - Endpoint consultado: `player_api.php?username={user}&password={pass}`.
  - O sistema valida:
    - Status de autorização (`user_info.auth == 1` ou `'1'` ou `true`).
    - Validade temporal (`exp_date` não expirada).
    - Status da conta (`active`, `trial`, `enabled`, `1`).
- **Descoberta Multi-Endpoint:**
  - `action=get_live_streams` e `action=get_live_categories` -> Canais.
  - `action=get_vod_streams` e `action=get_vod_categories` -> Filmes.
  - `action=get_series` e `action=get_series_categories` -> Séries.
  - `action=get_series_info&series_id={id}` -> Temporadas e Episódios normalizados.
- **Tolerância a Provedores Parciais:**
  - Se o provedor não disponibiliza Filmes ou Séries (retorna array vazio ou HTTP 501), o sincronismo importa os Canais normalmente sem abortar o catálogo.

### 3.2 M3U / M3U Plus (`m3u`)
- **Parâmetros de Entrada:**
  - URL remota ou Arquivo local `.m3u` / `.m3u8`.
- **Parsing de Metadados:**
  - Reconhece tags padrão: `#EXTM3U`, `#EXTINF:`.
  - Extrai atributos: `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`.
  - Preserva integralmente os nomes originais das categorias e dos canais (sem dedução ou renomeação artificial).
  - Suporta URLs com redirecionamentos HTTP (até 5 saltos) e User-Agent padrão de TV Players (`IPTVSmarters/1.0`).

### 3.3 HLS Playback Manifest (`other_m3u8`)
- **Diferenciação Fundamental:**
  - **Catálogo M3U:** Lista contendo dezenas ou milhares de canais com metadados `#EXTINF`.
  - **Manifesto HLS Master:** Arquivo de reprodução contendo variantes `#EXT-X-STREAM-INF` de diferentes taxas de bits.
  - **Manifesto HLS Media/Segmentos:** Arquivo de reprodução com `#EXT-X-TARGETDURATION`, `#EXT-X-MEDIA-SEQUENCE` e segmentos de vídeo (`.ts`, `.aac`).
- **Comportamento no iPlex:**
  - Manifestos HLS são classificados como `isSingleStream: true`.
  - O sistema **NUNCA** trata cada segmento `.ts` ou cada variante de qualidade como um canal independente.
  - O catálogo resultante contém exatamente um item apontando para a URL do manifesto.

### 3.4 Direct Stream (`direct_stream`)
- **Extensões Suportadas:** `.mp4`, `.mkv`, `.ts`, `.mpd`, `.avi`, `.mov`, `.flv`.
- **Content-Types:** `video/mp4`, `video/mp2t`, `video/x-matroska`, `application/dash+xml`.
- **Classificação:** Se o arquivo indicar filme/VOD (.mp4, .mkv), é tipado como `kind: 'movie'`. Streams ao vivo diretos (.ts) são tipados como `kind: 'channel'`.

---

## 4. Contrato de Segurança e Privacidade
1. **Credenciais Isoladas:** Senhas, tokens e credenciais nunca entram no catálogo compartilhado nem em logs de auditoria.
2. **SSRF Guard:** Validação estrita de endereços IP via `ipaddr.js`. Rejeita loopback, redes privadas (RFC 1918), link-local, multicast e metadados de nuvem.
3. **Limites de Processamento:** Teto de 64 MB para playlists M3U, timeout de download de 30 a 60 segundos e orçamento global de 5 minutos por execução.
