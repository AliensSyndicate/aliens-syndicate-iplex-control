# Perfis familiares — modelo, segurança e contrato com o Player

Estado em 19/10/2026. Regras permanentes resumidas em `AGENTS.md` §5 e §14.

## Modelo de dados (Firestore)

| Caminho | Conteúdo | Escrita |
|---|---|---|
| `families/{fid}/profiles/{pid}` | `name`, `type` (`admin`/`regular`/`kids`/`guest`), `linkedUid` (opcional), `enabled`, `permissions {allSpaces, spaces[]}`, `permissionsVersion`, `generations {favorites, watched, progress}` | só backend |
| `families/{fid}/profiles/{pid}/favorites/{docId}` e `.../wishlist/{docId}` | biblioteca pessoal (ver `CONTRACTS.md` §2.2): `contentId`, `title`, `generation`, `kind?`, `tmdbId?`, `tmdbKey?`, `catalogContentId?` | só backend |
| `families/{fid}/profiles/{pid}/watched/{contentId}` | `contentId`, `title`, `generation`, `completedAt` (novo: "Assistidos") | só backend |
| `families/{fid}/profiles/{pid}/watch_progress/{contentId}` | `position`, `duration`, `generation` | só backend |
| `families/{fid}/profile_links/{uid}` | `profileId` — uma conta, no máximo um perfil por família | só backend |
| `families/{fid}/profile_clear_jobs/{pid}_{categoria}` | estado da limpeza (`running`/`completed`/`failed`, `requestId`, `generation`) | só backend |
| `profile_link_codes/{sha256(código)}` | código de vinculação (10 min, uso único) | só backend; sem leitura de cliente |

Ids fixos: `admin` (perfil do administrador, criado em `createFamily`) e `guest` (visitante). Perfis legados sem `type` são tratados como `regular`, com `permissions.allSpaces = true` e gerações 0.

## Ações do callable `manager`

| Ação | Quem | Efeito |
|---|---|---|
| `saveProfile {name, type?, requestId?, id?}` | admin | cria (`regular`/`kids`, limite de 4 associados, idempotente por `requestId`) renomeia ou altera `regular` ↔ `kids` em edição explícita por `id`; tipos `admin`/`guest` protegidos |
| `setGuestEnabled {enabled, name?}` | admin | cria/ativa/desativa o visitante sem apagar configuração |
| `setProfilePermissions {profileId, kinds?, adult?, allSpaces?, spaces?}` | admin | `kinds` (`channel`/`movie`/`series`, todas as fontes) e adulto; campos ausentes são mantidos; incrementa `permissionsVersion` |
| `setProfilePreferences {kinds?}` | conta vinculada | restringe os próprios tipos dentro do limite (`beyond-limit`); `null` remove a restrição; adulto não muda (`permission-denied`) |
| `createProfileLinkCode {profileId}` | admin | código de 8 caracteres + QR `iplex://profile-link?v=1&code=`; revoga o anterior |
| `redeemProfileLink {code}` | conta que será vinculada | confirma; adiciona a conta à família se necessário; conflito → `account-already-linked` |
| `unlinkProfileAccount {profileId}` | admin | remove só o vínculo; perfil e dados permanecem; conta Firebase intacta |
| `clearProfileData {profileId, category, requestId}` | admin (qualquer perfil) ou conta vinculada (próprio perfil) | `category`: `favorites`, `wishlist`, `watched`, `progress`; incrementa a geração, exclui em páginas de 400 (inclui `profile_favorites`/`profile_progress` legados), conclui o job; repetição com o mesmo `requestId` não duplica |
| `listPlayerProfiles` | TV | perfis selecionáveis (visitante desabilitado omitido), com gerações e `permissionsVersion` |
| `listProfileSpaces` | TV/app | espaços visíveis para o perfil ativo (infantil: só espaços com conteúdo infantil) |
| `favorite` / `watchProgress` / `markWatched` | TV/app | exigem `generation` atual da categoria; visitante sempre rejeitado |

## Classificação infantil

Na Família, o botão "+" abre diretamente Adicionar membro. O toggle "Conta infantil" começa desligado. `requestMembership {code, familyId?, profileType?}` aceita apenas `regular`/`kids` e só pode ser chamado pelo administrador da própria família. A classificação fica no convite; `respondMembership` usa esse valor do servidor, nunca uma classificação enviada pelo convidado. Convites antigos sem o campo criam `regular`.

O administrador também pode alterar a classificação nos detalhes do integrante. `saveProfile` preserva o perfil, vínculo e dados e incrementa `permissionsVersion` quando muda o tipo. Ativar Infantil grava `permissions.adult = false`; voltar a Membro preserva os limites e preferências existentes, que o administrador pode ajustar pelos controles habituais. Nenhuma dessas ações cria contas Firebase Auth.

`functions/src/content_audience.ts`, aplicada no backend a cada leitura:
1. Sinal adulto no título ou na categoria → nunca infantil.
2. Classificação etária explícita do provedor (`tvg-rating`/`rating` no M3U; `age`/`mpaa_rating`/`certification` no Xtream) decide: só `L`/`Livre`/`G`/`TV-Y`/`TV-Y7`/`TV-G`/`0`–`7` e equivalentes contam como infantil; qualquer outra classificação exclui, mesmo em categoria infantil.
3. Sem classificação: apenas categorias explicitamente infantis (Infantil, Kids, Desenhos, Niños, Cartoon Network, Gloob, …). "Animação", "Família" e similares não bastam.

Catálogos publicados antes desta versão não têm `ageRating`; recebem-no na próxima sincronização. Até lá vale apenas a regra de categoria (conservadora).

## Sincronização e dispositivos offline

- Canal de sincronização: os listeners do Firestore já usados pelo app e pela TV (regras liberam leitura de `profiles` e subcoleções de mídia para membros e para a TV pareada da própria família).
- Ao ver `generations.{categoria}` aumentar, a TV deve descartar o cache local dessa categoria e reler os dados. Ao ver `permissionsVersion` mudar, deve chamar `listProfileSpaces` e invalidar listas em cache.
- Escritas offline enfileiradas com geração antiga são rejeitadas (`stale-generation`); sem geração, `generation-required`. Os marcadores guardam só números, nunca listas de conteúdo excluído.
- Permissões são revalidadas no servidor em cada leitura de catálogo e imediatamente antes de entregar a URL de reprodução (`resolveSourceStream`); conteúdo revogado deixa de ser servido mesmo que a TV ainda o tenha em cache.

## Pendências do Player (fora deste repositório)

O Player TV não está neste repositório. Para cumprir o contrato ele precisa:
1. Enviar `generation` (e `watchedGeneration` ao concluir) em `favorite`/`watchProgress`/`markWatched`. **Players antigos param de salvar favoritos e progresso** (decisão aprovada: rejeitar escritas sem geração).
2. Listar perfis por `listPlayerProfiles` (ou ler `profiles` filtrando `type == guest && enabled == false`).
3. Ouvir `profiles/{pid}` para gerações e `permissionsVersion` e invalidar caches.
4. Usar `listProfileSpaces` para montar a navegação.
5. Não persistir nada do visitante além do estado da sessão atual.

## Migração

Não há migração destrutiva. Famílias existentes:
- não têm perfil `admin`: o administrador continua com acesso total pelo próprio papel; o perfil `admin` é criado apenas em famílias novas;
- podem ter mais de 4 perfis legados: nenhum é apagado; só fica bloqueada a criação de novos até haver vaga;
- contas associadas antigas não têm `profile_links`: ao usar o Gestor, veem o catálogo sem filtro de perfil até serem vinculadas a um perfil.
