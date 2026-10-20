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
| `iplexWebTmdb` (codebase `iplex-web`, HTTP `/api/tmdb/*`) | não | iPlex Web | Bearer = ID token da TV; delega a autorização a `player.authorizeMetadata` |

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
| Usuário | `users/{uid}` | `publicCode` (12), `familyId` (contexto ativo), `familyIds[]`, `iptvWorkspaceId?`, `locale` |
| Família | `families/{fid}` | `name`, `adminUid`, `members{uid: admin\|member}`, `leases[]`, `parental{pinConfigured, updatedAt}`, `kind?='personalIptv'` |
| Perfil | `families/{fid}/profiles/{pid}` | `name`, `type: admin\|regular\|kids\|guest` (imutável), `enabled`, `permissions{allSpaces, spaces[]}`, `generations{favorites, watched, progress}`, `permissionsVersion` |
| Dispositivo (TV) | `families/{fid}/devices/{did}` | `name`, `platform`, `model`, `status`, `credentialVersion`, `sessionId`, `onlineUntil`, `pinUnlock?`, `pinSession?`, `pendingPlayRequest?` |
| Assinatura | `families/{fid}/private/subscription` (só admin lê) | `status: notStarted\|trial\|active\|cancelled\|expired\|pending`, `trialEndsAt`, `paidUntil` — política em `canStartPlayback` |
| PIN parental | `families/{fid}/private/parental` (nenhum cliente lê) | `pinHash` (scrypt), `salt`, `updatedAt`, `updatedByUid` |
| Fonte IPTV | `families/{fid}/sources/{sid}` | `name`, `format`, `status`, `version` (catálogo publicado), `revision`, `enabled`, `isProtected`; credenciais só em `source_secrets` (AES-256-GCM) |
| Item de catálogo (canal, filme, série) | resposta de `readSourceCatalog` | `id` = sha256(`sourceId:catalogItemId`) (estável, público), `sourceId`, `kind: channel\|movie\|series`, `title` (original da fonte), `category`, `providerRef`, `epgId?`, `year?`, `ageRating?` |
| Temporada/Episódio | resposta de `readSourceSeries` | `details.seasons[]{seasonNumber,name}`, `details.episodes{<temporada>: [{id, title, season, episodeNum}]}`; episódio é sempre referenciado por `episodeId` |
| Favorito | `profiles/{pid}/favorites/{contentId}` | `contentId`, `title`, `generation`, `updatedAt` |
| Progresso | `profiles/{pid}/watch_progress/{contentId}` | `contentId` (episódio: `<itemId>_e<episodeId>`), `position`, `duration` (s), `generation`, `updatedAt` |
| Sessão de reprodução (lease) | `families/{fid}.leases[]` | `id`, `deviceId`, `deviceName`, `profileId`, `expiresAt` (90 s, renovado pelo heartbeat). Máx. **3** por família, **1** por perfil (`acquire` em `domain.ts`) |
| Solicitação de reprodução | `families/{fid}/devices/{did}/play_requests/{id}` | ver §4 |

Escritas de favoritos/assistidos/progresso exigem a `generation` atual do
perfil (`stale-generation` caso contrário). Visitante nunca persiste
(`guest-not-persisted`).

## 3. PIN parental

- `manager.setParentalPin {pin, confirmPin}` (4 dígitos) e
  `manager.clearParentalPin` — somente administrador.
- `player.listPlayerProfiles` → `{parentalPin:{configured}, profiles:[{…, pinRequired}]}`.
  `pinRequired = (perfil admin|regular) && (família tem perfil kids)`.
- `player.verifyProfilePin {profileId, pin}` →
  `{verified, required, attemptsLeft?, retryAt?}`. 5 erros → bloqueio de 15 min
  por TV (`pin-locked`, `details.retryAt`). Sem PIN definido:
  `parental-pin-not-configured` (adultos ficam bloqueados — falha fechada).
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
