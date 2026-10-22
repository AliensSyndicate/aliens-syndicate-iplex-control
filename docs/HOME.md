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
- Itens do catálogo: `imageRef` (logo/capa da fonte — `http` ou `https` como publicado, sem credenciais/tokens na URL) e `addedAt`. Versão do parser `parser-6` (acrescenta `tmdbId` publicado pelo provedor Xtream): a próxima sincronização de cada fonte regrava o catálogo com esses campos.
- `manager` → `authorizeMetadata` para contas do Control; `iplexWebTmdb` aceita a conta do Control **com App Check** (autoriza pela `manager`), TVs continuam pela `player`. A chave TMDB fica no servidor.
- `requestPlayback` aceita `resume`; a TV (`PlayRequestCoordinator`) abre o player com `r=1`.

## Seleção de IPTV
Bottom sheet com todas as fontes, estado de sincronização e indicador da selecionada; só fontes com catálogo publicado podem ser escolhidas. A escolha vale por conta+escopo, persiste entre aberturas (`shared_preferences`) e afeta busca e recém-adicionados; as seções pessoais agregam todas as fontes.

## Publicação necessária (pendente de autorização)
1. Functions do Control: `manager`, `player`, `processIptvSyncJobTrigger`, `recoverIptvJobs` (readHome v2, biblioteca, descoberta, `resume`, parser-6).
2. Functions do Web: `iplexWebTmdb` (rota do Control + `/api/tmdb/discover/*`).
3. Hosting do Web (`resume` na TV).
4. Novo build do Control — **antes do passo 1 a Home do Control em produção mostraria erro**, então o app só deve ser distribuído depois.
5. Ressincronizar as fontes para gravar `addedAt`/`imageRef`.

## Detalhes em tela completa, pessoas e biblioteca (21/10/2026)
- O sheet de detalhes foi substituído por páginas completas nas rotas da aba Home: `/home/title` (item do catálogo em `extra`), `/home/title/:kind/:tmdbId` (título editorial) e `/home/person/:id`. A pilha de navegação é preservada (Home → filme → pessoa → outro filme …) e o Voltar percorre a mesma pilha. O visual reaproveita o do sheet (arte fixa com gradiente, título, fatos, estrelas, `AppButton`) e `PageTemplate`/`EntryTile`/`SectionHeader`/`AppAvatar`.
- Linhas da Home: **Favoritos** (canais e títulos) · Continuar assistindo · **Lista de desejos** · recentes. Títulos salvos que nenhuma fonte oferece aparecem com o pôster do TMDB. Toque longo em qualquer card abre as duas ações.
- “Assistir na TV” só aparece com item reproduzível autorizado (`resolveTitle` para títulos editoriais); caso contrário, aviso discreto de indisponibilidade, com Favoritos/Lista de desejos funcionando.
- Séries: temporadas do TMDB (editorial) separadas dos episódios disponíveis na fonte IPTV (únicos enviados à TV).
- Perfil infantil: sem descoberta editorial (sem página de pessoa, sem títulos fora do catálogo). Visitante: sem ações de lista.
- Contrato completo: `CONTRACTS.md` §2.2. Capturas (dados de teste dos testes de widget): `docs/screenshots/details/`.
- Ajustes visuais da página de título: fundo = pôster original do TMDB (`posterOriginal`, `cover`) com transição para o preto na parte inferior; selo de classificação indicativa ClassInd (`AgeRatingBadge`) com os motivos do TMDB (`certificationDescriptors`) logo antes das estrelas; direção (filme) / criação (série) antes da sinopse; elenco só com atores, fotos 3:4 clicáveis; botões sem ícones; sinopse completa.
