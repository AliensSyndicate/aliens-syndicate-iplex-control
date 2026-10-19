# CODEX — iPlex: Pipeline de Detecção Automática de Fontes IPTV

## 1. Visão Geral do Pipeline
O serviço de detecção automática do iPlex analisa a entrada fornecida pelo usuário, identifica o protocolo e o formato subjacente e direciona o processamento para o adaptador correspondente, sem exigir conhecimento técnico aprofundado por parte do usuário.

```text
Fonte cadastrada
       |
       v
Validação de entrada
       |
       v
Identificação de formato
       |
       v
Seleção do adaptador
       |
       v
Validação de acesso
       |
       v
Extração de conteúdo
       |
       v
Normalização
       |
       v
Catálogo JSON
```

---

## 2. Etapas de Detecção Técnica

Localização: `functions/src/iptv_detection.ts`

### Etapa 1: Validação de Entrada
- Checagem de schema via Zod (`sourceSchema`).
- Verificação de URLs bem formadas e esquemas permitidos (`http:`, `https:`).
- Bloqueio de credenciais embutidas na autoridade da URL (`http://user:pass@host`).

### Etapa 2: Inspeção Estática (Sem Conexão)
1. **Fontes de Arquivo Local:**
   - Fontes com `format === 'file'` são imediatamente atribuídas ao `M3uPlaylistAdapter`.
2. **URLs Xtream Explícitas:**
   - URLs contendo `player_api.php` ou fontes com `username` e `password` explícitos.
3. **URLs M3U com Parâmetros de Script:**
   - URLs contendo `get.php` acompanhadas de `type=m3u`, `type=m3u_plus` ou `output=ts` são classificadas como **M3U Playlist** e **NÃO** como API Xtream Codes JSON.
4. **Extensões de Mídia Direta:**
   - URLs terminadas em `.mp4`, `.mkv`, `.ts`, `.mpd`, `.avi`, `.mov`, `.flv` são atribuídas ao `DirectStreamAdapter`.

### Etapa 3: Sonda Dinâmica (Assinatura de Conteúdo)
Se o formato não for conclusivo a partir da inspeção estática:
1. Uma requisição HTTP segura (respeitando SSRF e timeout de 30s) realiza a leitura dos primeiros bytes.
2. **Análise de Magic Headers e Tags:**
   - Se o corpo contém `#EXT-X-STREAM-INF` ou `#EXT-X-TARGETDURATION`: Seleciona `HlsManifestAdapter`.
   - Se o corpo começa com `#EXTM3U` ou `#EXTINF:`: Seleciona `M3uPlaylistAdapter`.
   - Se o corpo é JSON e contém `"user_info"` e `"auth"`: Seleciona `XtreamAdapter`.
3. **Consulta ao Registro Extensível:**
   - Caso nenhuma assinatura padrão corresponda, o `IptvAdapterRegistry` consulta os adaptadores customizados via `supports(source, sample)`.

### Etapa 4: Tratamento de Formato Desconhecido
Se o conteúdo recebido for HTML genérico (páginas de erro, blogs, portais), texto arbitrário ou binário desconhecido:
- O sistema lança o erro explícito `DomainError('unrecognized-source-format')`.
- O erro é mapeado para uma mensagem amigável no app ("Formato de fonte não reconhecido"), sem falhas genéricas silenciosas.

---

## 3. Segurança e Logs Sanitizados
- **Sanitização de URLs (`sanitizeLogUrl`):**
  - Todas as funções de logging limpam os parâmetros sensíveis (`username`, `password`, `token`, `key`, `secret`), substituindo os valores por `***`.
  - Exemplo:
    - Entrada: `https://provider.io/get.php?username=client123&password=supersecret&type=m3u`
    - Log: `https://provider.io/get.php?username=***&password=***&type=m3u`

---

## 4. Matriz de Decisão do Pipeline

| Entrada | Formato Declarado | Indicadores Encontrados | Formato Identificado | Adaptador Selecionado |
| :--- | :--- | :--- | :--- | :--- |
| `http://srv:8080/player_api.php` | `xtream` | Endpoint `player_api.php`, credenciais | `xtream` | `XtreamAdapter` |
| `http://srv/get.php?type=m3u_plus` | `m3u` ou `url` | `get.php` + `type=m3u_plus` | `m3u` | `M3uPlaylistAdapter` |
| `http://srv/live.m3u8` | `other_m3u8` ou `url` | `#EXT-X-STREAM-INF` / HLS manifest | `other_m3u8` | `HlsManifestAdapter` |
| `http://srv/movie.mp4` | `direct_stream` ou `url` | Extensão `.mp4`, Content-Type video | `direct_stream` | `DirectStreamAdapter` |
| `playlist.m3u` | `file` | Arquivo em Storage | `file` | `M3uPlaylistAdapter` |
| `http://srv/portal.html` | `url` | Resposta HTML comum | Desconhecido | Lança `unrecognized-source-format` |
