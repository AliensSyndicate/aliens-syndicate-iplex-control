# Home do Control ("Meu iPlex") — 21/10/2026

Implementação local, **não publicada**. Capturas (simulador + emuladores, pipeline real de sincronização) em `docs/screenshots/home/`.

## Estrutura
- **Cabeçalho**: barra de pesquisa (catálogo autorizado da fonte selecionada, `readSourceCatalog` — mesmo contrato da Home anterior) + botão de seleção de IPTV. O QR Code público foi movido para **Conta**.
- **Seções** (só aparecem com conteúdo real, até 10 cards cada, listas horizontais independentes): Favoritos · Continuar assistindo · Minha lista · Filmes recém-adicionados · Séries recém-adicionadas. Tudo vazio → estado vazio discreto com “Explorar o catálogo” (foca a busca). Carregamento → skeleton; falha → erro com nova tentativa.
- **Sheet de detalhes**: backdrop, pôster, título, ano, duração, classificação, gêneros, sinopse, elenco (TMDB quando há correspondência confiável; senão só os dados da fonte). Canais: “Canal ao vivo”, categoria e EPG (Agora/A seguir via `readSourceEpg`) — sem duração/elenco. Ações: **Continuar assistindo na TV** (com progresso), **Assistir na TV** (fluxo existente `requestPlayback`; série → escolha de episódio), **Favoritos** (canal) ou **Minha lista** (filme/série). Nenhum comando de controle remoto.

## Contratos reutilizados (sem coleções novas)
| Seção | Origem |
|---|---|
| Favoritos | `families/{fid}/profiles/{pid}/favorites` — itens de **canal** (= “Canais favoritos” do Web/TV) |
| Minha lista | mesma coleção `favorites` — **filmes e séries** (= “Minha lista” do Web/TV) |
| Continuar assistindo | `watch_progress` (< 95%), episódios `<itemSérie>_e<episódio>` (mesmo contrato da TV) |
| Recém-adicionados | campo `addedAt` do item, gravado da data `added` publicada pelo provedor Xtream; fontes sem data (M3U) não exibem a seção |

Gerações limpas no Gestor são ignoradas, como na TV. O perfil é o vinculado à conta no escopo atual (`profile_links/{uid}`); sem perfil/visitante, o sheet não oferece ações de lista.

## Backend
- `manager` → `readHome` (`iptv_catalog_access.ts`): resolve favoritos/progresso em itens que o perfil ainda pode abrir (mesmas regras de `readSourceCatalog`/`canSee`, fontes protegidas bloqueadas são puladas) + recentes da fonte selecionada.
- Itens do catálogo: `imageRef` (logo/capa da fonte — `https`, sem credenciais/tokens na URL) e `addedAt`. Versão do parser `parser-4`: a próxima sincronização de cada fonte regrava o catálogo com esses campos.
- `manager` → `authorizeMetadata` para contas do Control; `iplexWebTmdb` aceita a conta do Control **com App Check** (autoriza pela `manager`), TVs continuam pela `player`. A chave TMDB fica no servidor.
- `requestPlayback` aceita `resume`; a TV (`PlayRequestCoordinator`) abre o player com `r=1`.

## Seleção de IPTV
Bottom sheet com todas as fontes, estado de sincronização e indicador da selecionada; só fontes com catálogo publicado podem ser escolhidas. A escolha vale por conta+escopo, persiste entre aberturas (`shared_preferences`) e afeta busca e recém-adicionados; as seções pessoais agregam todas as fontes.

## Publicação necessária (pendente de autorização)
1. Functions do Control: `manager`, `player`, `processIptvSyncJobTrigger`, `recoverIptvJobs` (readHome, metadados, `resume`, parser-4).
2. Functions do Web: `iplexWebTmdb` (rota do Control).
3. Hosting do Web (`resume` na TV).
4. Novo build do Control — **antes do passo 1 a Home do Control em produção mostraria erro**, então o app só deve ser distribuído depois.
5. Ressincronizar as fontes para gravar `addedAt`/`imageRef`.
