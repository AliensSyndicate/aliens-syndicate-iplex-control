# Contratos do ecossistema iPlex — v1 (20/10/2026)

Fonte única dos formatos trocados entre **iPlex Control** (Flutter, este
repositório), **iPlex Web** (`aliens-syndicate-iplex-web`), **iPlex App**
(shell Samsung, `aliens-syndicate-iplex-app`) e o backend Firebase
(`functions/`, projeto `iplex-2c8fc`). O backend é a autoridade: nenhum
cliente decide acesso.

Regra de evolução: campo/ação **novo** = mesma versão (clientes ignoram o que
não conhecem). Mudança **incompatível** = nova versão aqui, `schemaVersion`
novo nos documentos afetados e atualização coordenada dos consumidores
(ver "Implantação coordenada").

## 1. Endpoints

| Callable | App Check | Quem chama | Identidade |
|---|---|---|---|
| `manager` | **obrigatório** | iPlex Control | conta Firebase (pessoa) + `contextFamilyId` |
| `player` | não (Tizen 5.5 não suporta reCAPTCHA) | iPlex Web (TV/navegador) | custom token `tv_<deviceId>`, claims `deviceId`, `familyId`, `credentialVersion`, verificado com `checkRevoked` |
| `iplexWebTmdb` (codebase `iplex-web`, HTTP `/api/tmdb/*`) | não (TV) / **sim** (Control) | iPlex Web e iPlex Control | Item do catálogo: Bearer da TV → `player.authorizeMetadata`; Bearer da conta + `X-Firebase-AppCheck` → `manager.authorizeMetadata`. **Descoberta editorial** `/api/tmdb/discover/{movie,tv,tv/:id/season/:n,person}/:id`: só conta + App Check → `manager.authorizeDiscovery` (nunca TV, nunca perfil infantil, cota de 600/10 min por conta; sem conteúdo adulto) |

`player` aceita só uma **lista fechada** (`functions/src/player.ts`):
públicas com cota (`beginDevicePair`, `finishDevicePair`) e de dispositivo
(`listPlayerProfiles`, `verifyProfilePin`, `acquireSession`, `heartbeat`,
`releaseSession`, `listProfileSpaces`, `readSourceCatalog`, `readSourceSeries`,
`readSourceEpg`, `resolveSourceStream`, `authorizeMetadata`, `readPlayerLibrary`,
`readPlayerGenerations`, `favorite`, `watchProgress`, `markWatched`,
`claimPlayRequest`, `updatePlayRequest`). Ações que mudam estado exigem
`requestId` (32 hex, uso único) e `issuedAt` (±2 min).

Erros: `HttpsError.message` = código de domínio (`DomainError.code`). Os
clientes mapeiam o código para mensagens próprias (nunca genéricas).

## 2. Entidades

| Entidade | Onde | Campos do contrato |
|---|---|---|
| Usuário | `users/{uid}` | `publicCode` (12), `familyId` (**a única família da conta**), `homeFamilyId` (família individual; estacionada enquanto a conta é membro de outra), `photoUrl?` (foto https do provedor, escrita só pelo backend), `familyIds[]` (índice legado, não é lista de vínculos), `iptvWorkspaceId?` (legado), `locale` |
| Família | `families/{fid}` | `name`, `individual?`, `adminUid`, `members{uid: admin\|member}`, `leases[]`, `parked?` (família individual cujo titular entrou em outra; sem membros, nada é apagado), `kind?='personalIptv'` (legado: promovido a família individual no bootstrap) |
| Membro (conta) | `families/{fid}/members/{uid}` | `uid`, `name`, `role: admin\|member`, `photoUrl?`, `joinedAt` |
| Convite | `family_requests/{id}` | `familyId`, `issuerUid`, `recipientUid`, `recipientName`, `recipientPhotoUrl?`, `status: pending\|accepted\|declined\|cancelled`, `expiresAt`; leem o convidado e o administrador da família emissora |
| Perfil | `families/{fid}/profiles/{pid}` | `name`, `type: admin\|regular\|kids\|guest` (imutável), `enabled`, `permissions{allSpaces, spaces[]}`, `generations{favorites, watched, progress}`, `permissionsVersion` |
| Dispositivo (TV) | `families/{fid}/devices/{did}` | `name`, `platform`, `model`, `status`, `credentialVersion`, `sessionId`, `onlineUntil`, `pinUnlock?`, `pinSession?`, `pendingPlayRequest?` |
| Assinatura | `families/{fid}/private/subscription` (só admin lê) | `status: notStarted\|trial\|active\|cancelled\|expired\|pending`, `trialEndsAt`, `paidUntil` — política em `canStartPlayback` |
| PIN pessoal | `families/{fid}/private/personal_pin_{pid}` (nenhum cliente lê) | `pinHash` (scrypt), `salt`, `profileId`, `uid`, `updatedAt` |
| Fonte IPTV | `families/{fid}/sources/{sid}` | `name`, `format`, `status`, `version` (catálogo publicado), `revision`, `enabled`, `isProtected`; credenciais só em `source_secrets` (AES-256-GCM) |
| Item de catálogo (canal, filme, série) | resposta de `readSourceCatalog` | `id` = sha256(`sourceId:catalogItemId`) (estável, público), `sourceId`, `kind: channel\|movie\|series`, `title` (original da fonte), `category`, `providerRef`, `epgId?`, `year?`, `ageRating?` |
| Temporada/Episódio | resposta de `readSourceSeries` | `details.seasons[]{seasonNumber,name}`, `details.episodes{<temporada>: [{id, title, season, episodeNum}]}`; episódio é sempre referenciado por `episodeId` |
| Favorito / Lista de desejos | `profiles/{pid}/favorites/{docId}`, `profiles/{pid}/wishlist/{docId}` | ver §2.2 |
| Progresso | `profiles/{pid}/watch_progress/{contentId}` | `contentId` (episódio: `<itemId>_e<episodeId>`), `position`, `duration` (s), `generation`, `updatedAt` |
| Sessão de reprodução (lease) | `families/{fid}.leases[]` | `id`, `deviceId`, `deviceName`, `profileId`, `expiresAt` (90 s, renovado pelo heartbeat). Máx. **3** por família, **1** por perfil (`acquire` em `domain.ts`) |
| Solicitação de reprodução | `families/{fid}/devices/{did}/play_requests/{id}` | ver §4 |

Escritas de favoritos/assistidos/progresso exigem a `generation` atual do
perfil (`stale-generation` caso contrário). Visitante nunca persiste
(`guest-not-persisted`).

## 2.2 Biblioteca pessoal (Favoritos + Lista de desejos) — `functions/src/library.ts`

Identidade canônica de um título = **TMDB id + tipo** (`tmdbKey`: `movie:603` ≠
`tv:603`). O vínculo com a IPTV é opcional; a disponibilidade nunca é condição
para salvar.

| Campo | Significado |
|---|---|
| `docId` | id do item do catálogo (legado, canais) ou `tmdb-<movie\|tv>-<id>` |
| `contentId` | id público do item do catálogo quando vinculado (compatível com a TV); senão `docId` |
| `catalogContentId`, `sourceId` | último vínculo confiável com o catálogo (opcionais) |
| `kind` | `channel` \| `movie` \| `series` |
| `tmdbId`, `tmdbKey` | identidade editorial (opcional para canais/itens legados) |
| `title`, `originalTitle?`, `year?`, `poster?` | metadados para exibir sem a fonte (`poster` só `https://image.tmdb.org/`) |
| `generation`, `updatedAt` | ambas as listas usam `generations.favorites`; “Limpar favoritos” limpa as duas |

- `saveLibraryItem {profileId, generation, list, kind, contentId?, sourceId?, tmdbId?, title, originalTitle?, year?, poster?, remove?}` (só `manager`, só o perfil vinculado à conta): mescla linhas do mesmo título (mesmo item, mesmo vínculo ou mesmo `tmdbKey`) — nunca duplica entre fontes. Item do catálogo é verificado contra o que o perfil vê; o `tmdbId` publicado pelo provedor prevalece. Perfil infantil só salva itens do catálogo que vê (`content-unavailable`). Lista de desejos não aceita canais.
- `readHome` (`schemaVersion: 2`) acrescenta `library {favorites[], wishlist[]}` (itens do catálogo com `available: true` e `library {id, tmdbId?}`; títulos sem catálogo como entrada editorial `available: false`, nunca para perfil infantil) e `saved {favorites[], wishlist[]}` (chaves: ids de item, `docId` e `tmdb:<movie|tv>:<id>`). `favorites`/`myList`/`favoriteIds` mantêm o contrato anterior.
- Player no celular (Control, conta logada, sem `deviceId`): `startMobilePlayback {deviceName?}` → `{sessionId, profileId, pinRequired, generations, expiresAt}` (perfil da própria conta; recusa `subscription-required`, `profile-in-use`, `session-limit`); `mobilePlaybackHeartbeat {sessionId}` a cada 30 s (lease de 90 s); `stopMobilePlayback {sessionId}`. `resolveSourceStream {id, itemId, episodeId?, sessionId}` e `verifyAdultPin {sessionId, pin}` exigem essa sessão; sem ela, `player-required`. Progresso pelo `watchProgress` existente com `playId/startedAt/seq/origin`. Estado do celular em `families/{fid}/mobile_sessions/{uid}` (só backend).
- Conteúdo adulto (mesmas regras da TV): `readSourceCatalog {adult: true}` devolve só itens adultos (aba Adulto do Control) e `{adult: false}` nenhum (demais abas e busca); sem o campo, tudo (clientes antigos). `readHome.adultKinds` lista os tipos com adulto visível ao perfil na fonte selecionada (vazio = sem aba Adulto). Lançamentos, recentes, buscas recentes, `readProfileLibrary` e `resolveTitle` nunca trazem adulto. No Control o administrador segue o próprio "Conteúdo adulto".
- Correspondência com o catálogo (`TitleResolver`): vínculo salvo → `tmdbId` do provedor (Xtream `tmdb`/`tmdb_id`, campo `tmdbId` do item, `parser-6`) → título exato + ano exato, só se nenhum item com mesmo título/ano declarar outro `tmdbId`. Ambíguo = não vinculado. Vínculo a item que o perfil não pode mais ver oculta a entrada. Quando a correspondência aparece, `readHome` grava o vínculo na mesma linha (sem nova linha, sem salvar de novo).
- `resolveTitle {kind, tmdbId, title?, originalTitle?, year?, sourceId?}` → `{item|null, match}`: item reproduzível autorizado do título editorial (habilita “Assistir na TV”).
- TV: `favorite` (player) passa a reutilizar/remover a linha canônica do mesmo item; `readPlayerLibrary` inalterado (vê os títulos vinculados; a Lista de desejos não é exposta à TV).

## 2.1 Uma conta, uma família

- `bootstrap` (idempotente, a cada abertura do Gestor) cria a **família individual** da conta
  (`individual: true`, `adminUid` = a conta, perfil `admin`, assinatura `notStarted`) quando ela não
  tem família ativa, e copia a foto do provedor (`photoUrl`) sem nunca substituí-la por vazio.
  Contas antigas: a associação ativa é mantida; um espaço `personalIptv` é promovido no lugar a
  família individual (fontes, dispositivos e histórico mantêm os identificadores).
- `createFamily` → `already-in-family`; `selectContext` só aceita a própria família
  (`family-exclusive`); `contextFamilyId`/`familyId` de outra família → `permission-denied`.
- Convite: `lookupPublicUser`/`requestMembership` (só administrador; o convidado precisa estar sozinho
  na própria família → `user-unavailable`), `respondMembership {id, accept}`,
  `cancelMembershipRequest {id}` (administrador). Aceitar move a conta de forma atômica:
  se a família individual tem fontes, dispositivos, TVs em uso, perfis ou histórico →
  `individual-family-has-resources` (nada é movido); se está vazia, é **estacionada**
  (`parked`, `members: {}`), sem exclusão, e volta quando a conta sai da família.
  Os demais convites pendentes da conta são cancelados; aceitações simultâneas de duas famílias
  resultam em uma só (`already-in-family`). O vínculo por código de perfil (`redeemProfileLink`) segue a mesma regra.
- `removeMember {id}` (administrador) e `leaveFamily` (membro) devolvem a conta à família individual
  (restaurada ou criada); o administrador não sai (`administrator-protected`).

## 3. PIN do perfil (PIN pessoal)

- O PIN parental foi removido (`setParentalPin`/`clearParentalPin` → `invalid-action`).
- `manager.setPersonalPin {pin, confirmPin, currentPin?}` e `manager.clearPersonalPin {currentPin}` —
  somente a conta vinculada ao perfil.
- `player.listPlayerProfiles` → `{account:{name, photoUrl|null}, profiles:[{…, generations, pinRequired}]}`.
  `account` identifica a **conta** vinculada à TV (administrador da família): nome e foto https do
  provedor, nunca credenciais nem perfis de visualização; `photoUrl: null` = avatar padrão.
  `pinRequired` = o perfil tem PIN pessoal. `generations` inclui `wishlist` (geração própria da Lista de desejos).
- `player.verifyProfilePin {profileId, pin}` →
  `{verified, required, attemptsLeft?, retryAt?}`. 5 erros → bloqueio de 15 min
  por TV (`pin-locked`, `details.retryAt`). Perfil sem PIN pessoal: `{verified: true, required: false}`.
- `player.verifyAdultPin {profileId, pin}` (com sessão ativa do perfil): mesmo PIN pessoal, libera um
  título adulto (uso único, consumido por `resolveSourceStream`). Sem PIN pessoal: `{verified: true,
  required: false}` e o adulto toca sem PIN (se o administrador liberou o adulto para o perfil).
- `player.acquireSession` de perfil que exige PIN só passa com liberação
  recente (2 min, uso único, mesmo perfil) ou sessão de PIN válida (15 min,
  renovada pelo heartbeat) → senão `profile-pin-required`.
- `player.releaseSession {sessionId, suspend?}`: sem `suspend` (troca de perfil,
  saída) a sessão de PIN termina; com `suspend: true` (multitarefa) continua.

## 4. Solicitação de reprodução (Control → TV) — `schemaVersion: 1`

O Control **não é controle remoto**: só pede para iniciar um título.

```
{ schemaVersion: 1, deviceId, familyId, requesterUid, requesterName,
  sourceId, itemId, episodeId|null, episodeLabel|null, kind, title,
  status, errorCode|null, createdAt, updatedAt, expiresAt, deliveredAt, finishedAt, expireAt(TTL) }
```

Estados: `pending → delivered → (confirming) → started | declined | failed`;
`pending → expired | superseded`. `revoked` (id `device-unlinked`) é só o
marcador de desvinculação para o ouvinte da TV.

| Etapa | Chamada | Validações |
|---|---|---|
| Pedir | `manager.requestPlayback {deviceId, sourceId, itemId, episodeId?, episodeLabel?, requestId}` | pessoa membro do escopo; item visível ao perfil de quem pede **e** ao perfil ativo da TV; TV vinculada com lease ativo (`device-offline`); assinatura (`subscription-required`); série exige episódio (`episode-required`); idempotente por `requestId`; 1 pedido a cada 2 s por TV; pedidos pendentes anteriores viram `superseded`; validade 60 s |
| Receber | ouvinte Firestore (regra: só a TV dona com `credentialVersion` atual) + reserva no heartbeat (`{playRequest:{id, expiresAt}}`) | — |
| Aceitar | `player.claimPlayRequest {playRequestId}` | credencial atual; uma vez; antes de expirar; revalida visibilidade para o perfil ativo → `delivered` (com o conteúdo) ou `failed`/`expired` |
| Resultado | `player.updatePlayRequest {playRequestId, status, errorCode?}` | transições fechadas; `confirming` sem resposta em 45 s não pode virar `started` |

#### 4.1 Retomada e progresso (v1.1, compatível)

- `requestPlayback {…, resume:true}`: o backend lê o progresso do **perfil de quem pede** (o que o Control
  mostrou) para o `contentId` do filme (`itemId`) ou do episódio (`{itemId}_e{episodeId}`) e guarda `resumeHint` no pedido.
- `claimPlayRequest` devolve, com `resume:true`, `resumePositionSec` e `resumeDurationSec` — escolhidos entre o
  `resumeHint` e o progresso do **perfil ativo da TV** (mesmo perfil: vale o mais recente; perfis diferentes: vale o
  que o Control mostrou). Ausentes quando o título não foi iniciado (< 10 s), está concluído (≥ 95 % ou últimos 30 s) ou é canal.
  A TV abre `/assistir?…&r=1&ra=<segundos>`; sem `ra`, usa a biblioteca local só depois de carregada.
- `watchProgress` aceita, opcionais (TVs antigas continuam válidas): `playId`, `startedAt`, `seq`, `origin`
  (`start|resume|restart`) e `userSeek`. O documento `watch_progress/{contentId}` guarda a última sessão aceita e o
  backend responde `{ok:true, ignored}` (sem erro) para: `stale-event` (seq repetido/fora de ordem), `stale-session`
  (sessão mais antiga, ex.: outra TV), `initial-zero` (zero de inicialização sobre progresso salvo) e
  `resume-not-applied` (retomada que não chegou ao ponto salvo, ex.: stream sem seek). Reinício intencional
  (`origin:restart`) e seek do usuário (`userSeek`) sempre são aceitos, inclusive para trás.
- A TV só grava depois de confirmar a posição restaurada (ou de desistir sem gravar), uma gravação por vez e a cada ≥ 30 s / ≥ 10 s de deslocamento,
  mais pausa, seek e saída; falha de rede repete a posição mais recente.

Códigos de falha: `content-not-allowed`, `source-protected`,
`content-unavailable`, `stream-unavailable`, `playback-failed`,
`format-unsupported`, `session-limit`, `subscription-required`, `no-answer`, `busy`.

Política na TV (aprovada para v1, ajustável): sem reprodução em andamento →
inicia direto; com reprodução em andamento → pergunta na TV ("Assistir agora" /
"Continuar assistindo", 40 s sem resposta = `declined/no-answer`). Nunca
substitui em silêncio. Na seleção de perfis, o pedido espera a escolha até expirar.

## 5. Ponte TV ↔ Web

`iplex-bridge` v1, contrato em `aliens-syndicate-iplex-app/src/bridge/protocol.ts`
(cópia fiel em `aliens-syndicate-iplex-web/src/platform/bridge/protocol.ts`,
conferida por teste). Sem alterações nesta versão.

## 6. Validação nas fronteiras

- Backend: `zod` em toda entrada (`idSchema`, `nameSchema`, enums), regras do
  Firestore com escrita só pelo backend.
- Web: `src/services/api/validation.ts` (perfis, PIN, heartbeat, claim,
  documento do Firestore); resposta fora do formato = `backend-outdated`.
- Control: `Entry`/modelos com leitura defensiva; códigos de erro mapeados em
  `failure_feedback.dart`.

## 7. Implantação coordenada

Ordem: índices/TTL e regras do Firestore → Functions `iplex-gestor`
(`manager`, `player`, gatilhos) → Function `iplexWebTmdb` → Hosting do Web →
build do Control nas lojas. O Web publicado hoje já chama a `player`; o
Control antigo continua funcionando com o `manager` novo (ações removidas:
`sendCommand`/`ackCommand`, usadas só pela tela de controle remoto removida).
Detalhes e rollback: `aliens-syndicate-iplex-web/docs/INTEGRACAO-2026-10-20.md`.
