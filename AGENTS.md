# iPlex — Diretrizes de Engenharia, Regras de Negócio e Instruções para Agentes

## REGRA PERMANENTE OBRIGATÓRIA — PRIORIDADE MÁXIMA

> **"Antes de implementar qualquer interface, reutilizar os componentes existentes. Criar novos componentes somente quando não houver equivalente adequado, preservando integralmente a identidade visual atual do iPlex."**

### Diretrizes de Design Visual
1. **Identidade Visual**: Dark Industrial Neumorphism e Atomic Design com as cores, espaçamentos, raios e sombras existentes.
2. **Reutilização Estrita**:
   - Telas e páginas: `PageTemplate`, `Scaffold`.
   - Botões: `CircularButton` (alvo 48 dp), `AppButton` (ação primária/secundária com estado ocupado).
   - Campos de entrada: `AppTextField`, `AppDropdownField`, `AppInputFrame`.
   - Listas e cartões: `EntryTile`, `NeumorphicListTile`, `SectionHeader`, `NeumorphicSectionHeader`.
   - Superfícies e modais: `AppSurface`, `AppModalSheet`, `GraphiteBackdrop`, `GraphiteSurface`.
   - Estados: `EmptyState`, `ErrorState`, `AppLoadingSkeleton`.
3. **Proibições Estritas**:
   - É proibido redesenhar telas sem solicitação explícita.
   - É proibido criar estilos visuais paralelos ou paletas ad-hoc.
   - É proibido alterar tipografia arbitrariamente.
   - É proibido inventar novos padrões de cards ou substituir componentes funcionais por alternativas puramente visuais.
   - É proibido adicionar botões extras que não foram solicitados.
   - É proibido remover ou tornar transparente o fundo sólido do menu principal (`BottomNavigation`), que deve ter a mesma cor do fundo das telas (`GraphiteBackdrop`).
4. **Padrão de Notificações, Feedbacks e Modais**:
   - **Sheets em vez de SnackBars**: Todo aviso, mensagem de erro ou feedback informativo do projeto DEVE ser apresentado via Bottom Sheet modal (`showAppModalSheet` ou `showAppFeedbackSheet`). O uso de `SnackBar` para notificações gerais é proibido.
   - **Exceção Obrigatória — Erro ao Conectar Dispositivo**: A única exceção ao uso de Bottom Sheets é o erro ao conectar/parear dispositivo (`showDeviceConnectionFailure`), que DEVE ser exibido via `SnackBar`.
   - **Margem superior dos Bottom Sheets**: todo sheet, inclusive o que ocupa a tela toda, tem margem superior igual à altura da status bar do dispositivo (`showAppModalSheet` aplica `useSafeArea: true`; não usar `showModalBottomSheet` direto sem ele).
   - **Sobreposição Obrigatória do Menu Principal**: Todo Bottom Sheet (`useRootNavigator: true`) e todo SnackBar DEVE se sobrepor ao menu principal (`BottomNavigation`), garantindo visibilidade limpa e sem cortes.

---

## 1. REGRA FUNDAMENTAL — CONTA INDIVIDUAL

Todo usuário pode utilizar o iPlex Gestor sem possuir família vinculada.

Ao cadastrar uma conta:
- Criar a conta de usuário normalmente no Firebase Auth e Firestore.
- Gerar seu identificador público único alfanumérico de 12 caracteres de forma segura e atômica.
- **NÃO criar família automaticamente.**
- **NÃO exigir assinatura.**
- **NÃO exigir associação familiar.**
- Permitir acesso a todas as funcionalidades de gerenciamento.

O usuário individual tem pleno direito de:
- Adicionar dispositivos.
- Listar seus dispositivos vinculados.
- Editar seus dispositivos próprios.
- Desvincular seus dispositivos próprios.
- Adicionar playlists IPTV (M3U, Xtream Codes, HLS, etc.).
- Editar suas playlists IPTV próprias.
- Excluir suas playlists IPTV próprias.
- Acessar Perfil e Configurações.
- Criar famílias quando desejar.

**A ausência de `familyId` nunca representa falta de permissão.**

---

## 2. CONTEXTOS DE AUTORIZAÇÃO

O sistema opera com separação estrita entre dois contextos:

1. **Contexto pessoal**:
   - O usuário administra seus próprios recursos (dispositivos e playlists IPTV).
   - Nenhuma família é obrigatória.
2. **Contexto familiar**:
   - As permissões dependem do vínculo do usuário com aquela família específica (administrador ou associado).

O mesmo usuário pode:
- Administrar várias famílias.
- Participar como associado de outras famílias.
- Continuar utilizando seus recursos individuais privados.

**Nunca utilizar um papel global para determinar todas as permissões.**
A autorização (no Flutter, nas Cloud Functions e nas Firestore Security Rules) deve sempre considerar:
- UID autenticado.
- Recurso solicitado.
- Proprietário do recurso (`ownerId` / `ownerUid`).
- Família de destino, quando aplicável.
- Papel do usuário naquela família (`admin` vs `member`).
- Operação solicitada.

---

## 3. CORREÇÃO DE BLOQUEIOS INDEVIDOS

Mensagens como:
`"Você não tem permissão para esta ação."`
**NUNCA podem aparecer** simplesmente porque:
- O usuário não criou família.
- O usuário não possui assinatura ativa.
- O usuário ainda não adicionou membros.
- O usuário está utilizando sua conta individual.

A autorização é aplicada por recurso na arquitetura, nunca mascarando erros ou escondendo mensagens legítimas de segurança.

---

## 4. PÁGINA FAMÍLIA

- A página deve se chamar **Família** (`FamilyPage`).
- **NÃO renomeá-la para Usuários.**
- Quando o usuário não possuir famílias:
  - Exibir o estado vazio no padrão visual existente (`EmptyState`).
  - Disponibilizar ação **Criar família** (`createFamily`).
- Ao selecionar Criar família:
  - Abrir formulário (`NameForm`).
  - Solicitar nome da família.
  - Validar os dados.
  - Criar a família no backend via Cloud Function `createFamily`.
  - Associar o criador como administrador.
- Permitir que um usuário administre mais de uma família.
- Preservar o layout atual dos cards de família (`EntryTile`). Não adicionar botões extras não solicitados.

---

## 5. LIMITE DE INTEGRANTES E PERFIS DE MÍDIA

A unidade da família é o **perfil de mídia** (`families/{fid}/profiles/{pid}`), separado da conta Firebase:
- 1 perfil **administrador** (id fixo `admin`, criado com a família e vinculado à conta do administrador).
- Até **4 associados** (tipos `regular` ou `kids`; perfis legados sem tipo contam como `regular`).
- 1 **visitante** opcional (id fixo `guest`), que não ocupa vaga de associado.

Regras permanentes:
1. Perfil pode existir sem conta (criação direta pelo administrador, com `requestId` idempotente).
2. Uma conta liga-se a no máximo um perfil por família (`profile_links/{uid}`); vincular nunca recria o perfil nem altera favoritos, histórico, progresso ou permissões. Sem mesclagem automática: conflito retorna `account-already-linked`.
3. Vincular exige código temporário (10 min), de uso único, emitido pelo administrador e confirmado pela conta (`createProfileLinkCode` → `redeemProfileLink`), com limite de tentativas.
4. Desvincular (`unlinkProfileAccount`) ou remover a conta da família (`removeMember`) **mantém o perfil e seus dados**; a vaga só é liberada ao excluir o perfil.
5. O tipo do perfil é imutável após a criação (trocar `kids` por `regular` liberaria conteúdo restrito).
6. Contas da família continuam limitadas a cinco (administrador + 4) em transação; aceitar uma solicitação de associação cria um perfil `regular` vinculado e consome vaga de associado.

---

## 6. IDENTIFICADOR PÚBLICO DO USUÁRIO

Cada usuário possui um código alfanumérico único de 12 caracteres (exemplo: `A7K9M2P4X8Q3`):
- Gerado de forma segura no backend (`account_identity.ts`).
- Persistente e imutável pelo cliente.
- Garantia de unicidade via coleção de reserva atômica `public_user_codes/{code}`.
- Associado à conta (`users/{uid}.publicCode`).
- **Não utilizado como senha nem como token de autenticação.**
- Gerado de forma idempotente para contas existentes através de backfill seguro.

---

## 7. QR CODE DO USUÁRIO NA HOME

Na Home do iPlex Gestor (`CatalogPageView`), a AppBar possui um botão de QR Code (`CircularButton(icon: AppIcons.qr)`):
- Ao tocar, abre a apresentação no padrão visual existente (`PublicIdentitySheet` via `AppModalSheet`).
- Exibe o QR Code representativo da identificação pública do usuário.
- Exibe o código alfanumérico de 12 caracteres formatado.
- Disponibiliza botão de copiar código com feedback de cópia.
- Permite fechar a qualquer momento.
- Não expõe credenciais ou dados sensíveis.
- **O QR Code do usuário é público e DIFERENTE do QR Code de pareamento da TV.**

---

## 8. ADICIONAR MEMBROS À FAMÍLIA

O administrador identifica um novo membro exclusivamente por duas formas:
1. Ler o QR Code público do usuário (`/users/scan`).
2. Buscar pelo código alfanumérico de 12 caracteres.

**PROIBIDO: Implementar convite familiar por link transferível ou WhatsApp.**

Fluxo de associação:
1. Administrador busca pelo código ou lê o QR Code (`lookupPublicUser`).
2. Apresentam-se as informações públicas mínimas (nome e código).
3. Backend valida elegibilidade, família e limite de vagas.
4. Administrador envia solicitação de associação (`requestMembership`).
5. Usuário convidado visualiza a solicitação na aba Família e decide aceitar ou recusar (`respondMembership`).
6. Ao aceitar, o usuário é associado automaticamente à família, sem exigir segunda aprovação do administrador.
7. O limite de 5 integrantes é revalidado na transação de aceitação.
8. Rate limiting estrito no backend protege as buscas contra enumeração e abuso.

---

## 9. COMPARTILHAR APLICATIVO

Na tela Configurações (`SettingsPage`), existe a opção **Compartilhar aplicativo**:
- Abre o compartilhamento nativo do Android (`ACTION_SEND`) ou iOS (`UIActivityViewController`).
- Compartilha a mensagem oficial com o link de instalação do iPlex configurado no projeto (`AppSharing.message`).
- Permite envio via WhatsApp, Telegram, e-mail e qualquer app nativo.
- Não inventa URLs de lojas.
- **Esse compartilhamento NÃO representa convite familiar.**

---

## 10. DISPOSITIVOS E PLAYLISTS IPTV

- Dispositivos e playlists suportam **propriedade individual**.
- Não é exigido `familyId` para operações pessoais.
- O pareamento de TV por QR Code e código manual de 6 dígitos é preservado integralmente.
- O identificador permanente da TV (`canonicalDeviceId`) é independente do token temporário de pareamento.
- Isolamento estrito impede acesso cruzado entre contas e famílias.

---

## 11. ASSINATURAS E REPRODUÇÃO

- O gerenciamento no iPlex Gestor é **gratuito**.
- Dispositivos vinculados são ilimitados.
- Teste gratuito de 7 dias iniciado na primeira vinculação bem-sucedida de uma TV (`startTrial`).
- Concedido uma única vez conforme o escopo de titularidade.
- Máximo de 3 reproduções simultâneas (`leases`).
- Máximo de 1 sessão de reprodução por perfil.
- Controle de reprodução e expiração executado exclusivamente pelo backend (`canStartPlayback`, `acquireSession`, `heartbeat`, `releaseSession`).

---

## 12. INSTRUÇÕES OBSOLETAS REMOVIDAS

Ficam terminantemente revogadas e proibidas as seguintes práticas anteriores:
- ~~Criação automática de famílias no bootstrap.~~
- ~~Obrigatoriedade de familyId para gerenciar recursos pessoais.~~
- ~~Bloqueio de telas de gerenciamento por falta de assinatura.~~
- ~~Convite familiar por link ou token transferível.~~
- ~~QR Code do usuário exibido exclusivamente no perfil.~~
- ~~Papéis globais de autorização.~~

---

## 13. VALIDAÇÃO OBRIGATÓRIA ANTES DE DECLARAR CONCLUSÃO

Compilar, `flutter analyze` ou testes unitários verdes **não** encerram uma tarefa. Para qualquer alteração em fluxo de conta, família, dispositivos ou IPTV:

1. `flutter analyze` e `flutter test`.
2. `npm --prefix functions run check` (build + testes unitários).
3. `firebase emulators:exec --only auth,firestore,storage --project demo-iplex "npm --prefix functions run test:rules && npm --prefix functions run test:integration"`.
4. Cenários ponta a ponta pelo callable real: com `firebase emulators:start --only auth,firestore,functions,storage --project demo-iplex` ativo, `npm --prefix functions run e2e:callable`.
5. Interface: executar o Gestor contra os emuladores (`--dart-define=USE_EMULATORS=true --dart-define=FIREBASE_PROJECT_ID=demo-iplex`) e conferir a tela alterada.

Regras permanentes desta etapa:
- QR Code de TV para teste é gerado **somente** por `functions/scripts/dev_pairing_qr.ts` (sessão real do backend nos emuladores). Nunca criar token fictício nem atalho de teste aceito em produção.
- `EMULATOR_TEST_SIGN_IN` e o relaxamento de App Check existem apenas no emulador/debug; não estender a builds de release nem a projetos reais.
- Códigos de erro do backend (pareamento e IPTV) devem chegar ao usuário com mensagem localizada específica; não colapsar em mensagem genérica.
- Não declarar validado o que não foi executado. Relatar limitações externas (TV física, OAuth real, deploy) explicitamente.

---

## 14. PERFIS: PERMISSÕES, INFANTIL, VISITANTE E LIMPEZA DE DADOS

- **Espaço** = fonte IPTV × tipo de conteúdo (`{sourceId}:{channel|movie|series}`). Permissões em `profiles/{pid}.permissions {allSpaces, spaces}`; o administrador sempre acessa tudo.
- **Infantil** (regra do sistema, não configurável): só recebe itens classificados como infantis por `functions/src/content_audience.ts` (classificação etária explícita do provedor primeiro; sem ela, apenas categorias explicitamente infantis; sinais adultos sempre excluem; ambíguo = excluído). Nunca exibir cadeados, cards bloqueados ou títulos restritos.
- O filtro é aplicado **no backend** (`readSourceCatalog`, `readSourceSeries`, `resolveSourceStream`, `listProfileSpaces`). Na TV o perfil vem da lease do servidor, não do parâmetro do cliente.
- **Visitante**: habilitar/desabilitar mantém a configuração; desabilitado não aparece em `listPlayerProfiles` e não inicia sessão; nunca persiste favoritos, assistidos ou progresso (`guest-not-persisted`).
- **Limpezas** (`clearProfileData`): três categorias independentes (`favorites`, `watched`, `progress`), somente administrador, exclusão real e paginada no Firestore (inclusive coleções legadas `profile_favorites`/`profile_progress`), job idempotente por `requestId`, bloqueio de concorrência (`clear-in-progress`).
- **Gerações**: cada limpeza incrementa `profiles/{pid}.generations.{categoria}` antes de excluir. Toda escrita de favorito/assistido/progresso deve enviar a geração atual; ausente ou antiga é rejeitada (`generation-required`/`stale-generation`), impedindo que TVs offline restaurem dados excluídos.
- Toda exclusão no app passa por `confirmAndRun` (bottom sheet com processamento, sem envio duplicado, sucesso só após o backend).
- Contrato do Player detalhado em `docs/FAMILY_PROFILES.md`.

---

## 15. LOJAS, IDENTIFICADORES E ASSINATURAS (DECISÕES OFICIAIS)

- **Identificador Android/Google Play:** `com.alienssyndicate.iplex_control` (substitui `com.example…` e `com.alienssyndicate.iplex`). Bundle IDs da Apple não aceitam `_`: o iOS usará uma variante a definir quando a etapa Apple for liberada.
- **Firebase:** projeto `iplex-2c8fc`.
- **Plataforma comercial prioritária:** Google Play. iOS comercial **adiado**: não acessar App Store Connect, não cadastrar produtos Apple, não ativar checkout iOS (a abstração `StoreBilling` já comporta uma implementação futura).
- **Gestor gratuito.** Assinatura controla somente o direito de reprodução no iPlex Player; nada de gerenciamento (família, perfis, IPTV, dispositivos, configurações) depende dela.
- **Produto Google Play:** assinatura `iplex_playback` com planos-base `monthly` (P1M, R$ 9,90 pretendido) e `annual` (P1Y, R$ 99,90 pretendido), renovação automática, sem oferta de teste gratuito. Preços exibidos sempre os retornados pela loja.
- **Assinatura familiar:** comprada e administrada pelo administrador do escopo (família ou conta pessoal); grava `families/{fid}/private/subscription` só pelo backend. Limite de 3 reproduções simultâneas preservado.
- **Validação:** só o backend concede direito (`verifyPlayPurchase` + notificações RTDN no tópico Pub/Sub `play-billing-notifications`), sempre relendo o estado na Google Play Developer API. Token vinculado à conta (`obfuscatedAccountId`) e a uma única família.
- **Checkout desativado por padrão:** `app_config/payments.paymentsEnabled` ausente/false. Ligar exige autorização explícita do responsável. A flag nunca concede reprodução. `testerUids` permite teste isolado.
- **Proibido:** teste gratuito automático, cobrança pública sem autorização, checkout externo, confirmação de compra pelo cliente.
