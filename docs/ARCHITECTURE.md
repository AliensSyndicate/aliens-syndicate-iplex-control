# Arquitetura e operação

## Aplicativo

Flutter 3.47.4 / Dart 3.13.3. Riverpod injeta `ManagerRepository`, observa autenticação/conta/família e descarta streams de detalhes quando não usados. O repositório de produção usa Firebase Auth, Firestore e callable Functions; o substituto de testes está apenas em `test/`. Não há fallback de dados falsos em produção.

- `lib/app`: bootstrap, tema aplicado, go_router e shell com cinco branches persistentes.
- `lib/core/domain`: fronteira imutável de contas/famílias/metadados, falhas e repositório.
- `lib/core/data`: SDKs e providers. O cache Firestore em disco está desabilitado para evitar retenção entre contas.
- `lib/core/design_system`: material, tokens, átomos e componentes comuns.
- `lib/features`: autenticação, telas administrativas e controle.
- `lib/l10n`: ARBs en, pt_BR, es e pt como fallback exigido pelo gerador Flutter.
- `functions/src`: domínio puro, serviço transacional, adaptadores, sincronização e endpoints v2.

## Organização dos componentes

- `lib/core/design_system/components/`: um arquivo por controle reutilizável, como botão circular, campo de texto, avatar e estado vazio. `components.dart` reúne apenas exports para os consumidores do design system; os controles importam suas dependências diretamente.
- `lib/core/design_system/feedback/`: confirmação de remoção e apresentação de falhas. `localized_context.dart` concentra a extensão de localização.
- `lib/core/design_system/graphite_backdrop.dart` e `graphite_surface.dart`: fundo texturizado e superfícies físicas, respectivamente. Os painters ficam junto do componente que desenham.
- `lib/features/manager/`: cada tela ou formulário tem seu próprio arquivo (`users_page.dart`, `source_form.dart`, `source_detail_page.dart`, entre outros). `widgets/` contém componentes compartilhados entre essas telas, incluindo carregamento de listas e estados familiares.
- `lib/features/remote_control/remote_directional_pad.dart`: controle direcional independente; envio e confirmação dos comandos continuam em `remote_page.dart`.
- `lib/app/app.dart`: raiz do app, tema e idioma. `router.dart` concentra rotas e redirects; `router_refresh.dart`, `main_shell.dart`, `bottom_navigation.dart`, `session_loading_page.dart` e `route_access_page.dart` têm responsabilidades próprias.

O estado privado de um widget, seus painters e auxiliares usados por uma única tela permanecem no mesmo arquivo. Os tokens visuais continuam centralizados em `tokens.dart`. Os antigos agrupadores `forms.dart`, `list_pages.dart`, `account_pages.dart` e `empty_states.dart` foram substituídos por imports diretos dos arquivos correspondentes.

## Rotas e autorização
 
`/login`, `/loading`, `/family`, `/family/create`; branches `/home`, `/users`, `/devices`, `/iptv`, `/account`. Perfis, associados, favoritos, progresso, detalhes, formulários, QR, configurações e assinatura têm rotas próprias.
 
A rota inicial é `/home`, também após login/restauração. Família não é requisito para a Home ou para abrir as cinco abas.
Contas individuais operam plenamente sem família: adicionam e gerenciam dispositivos próprios e playlists IPTV próprias. A ausência de `familyId` nunca representa falta de permissão.
O sistema separa rigorosamente:
1. Contexto pessoal: o usuário administra seus recursos próprios sem exigir família.
2. Contexto familiar: o usuário pode administrar várias famílias ou participar como associado de outras, preservando seus recursos individuais.
O redirect e as regras de segurança validam autorização por recurso, proprietário e operação solicitada, nunca através de papéis globais inadequados.

As páginas principais das cinco abas mantêm `NoTransitionPage`. Telas filhas usam `HorizontalPageTransition`: entrada pela direita, saída para a direita ao voltar e deslocamento discreto da página anterior para a esquerda nas pilhas aninhadas. O router e o tema de `Navigator` compartilham o componente; as curvas e os tempos existentes são preservados (190 ms de entrada e 150 ms de retorno nas rotas do router). A preferência de acessibilidade para reduzir movimentos suprime o slide. A cobertura está em `test/page_transitions_test.dart`.

## Autenticação e Identidade Pública

Google usa `google_sign_in` 7 no mobile e popup Firebase na Web; Apple usa o provedor Firebase. UID é o identificador interno de autenticação, e-mail é metadado.
Cada usuário recebe um identificador público único alfanumérico persistente de 12 caracteres (ex: `A7K9M2P4X8Q3`), gerado de forma segura no backend (com garantia de unicidade via reserva `public_user_codes/{code}`). O identificador público não é senha nem token.
Na Home, um botão de QR Code na AppBar apresenta o QR Code e o código alfanumérico do usuário com botão de cópia.
`accountProvider` inicializa a conta uma vez por UID autenticado, via `initializeAccount`, e observa seu documento; isso atende tanto login quanto restauração. `bootstrap` persiste os metadados da conta e garante o código público, sem criar família automaticamente.

## Gestor gratuito e reprodução

Assinatura não participa dos guards administrativos. Qualquer conta autenticada pode abrir os planos pela Conta, inclusive sem família; somente o administrador lê os dados privados da assinatura familiar. `subscriptionProvider` é opcional e não bloqueia autenticação, Home ou operações de gestão gratuitas. A autorização de reprodução é calculada no servidor por `canStartPlayback`, usada em `acquireSession` e `heartbeat`, com verificação de dispositivo, perfil e limites de sessões (máximo 3 reproduções simultâneas e 1 por perfil). O primeiro vínculo de TV bem-sucedido inicia uma avaliação única de sete dias e preserva um período pago válido.

## Modelagem

```
users/{uid}                              conta, familyId ativo, familyIds[], iptvWorkspaceId, publicCode, idioma
public_user_codes/{code}                 reserva atômica {uid}
identity_attempts/{uid}                  rate limiting contra enumeração e abuso
family_requests/{requestId}              solicitações pendentes/aceitas/recusadas {familyId, issuerUid, recipientUid}
families/{familyId}                      adminId, ownerId, members {uid: role}, leases
  members/{uid}                         metadados públicos à família
  profiles/{profileId}                  perfil de visualização
    favorites/{contentId}               referência preservada
    watch_progress/{contentId}          posição/duração
  devices/{deviceId}                    espelho local do dispositivo
    commands/{commandId}                envelope de comando e ACK
  sources/{sourceId}                    metadados sem credenciais, versão ativa
  catalog/{version_source_item}         índice de consulta paginado
  private/subscription                 trial/status, somente admin lê
devices/{deviceId}                       registro canônico e status global do dispositivo
device_pairing_sessions/{hash}           sessões ativas de pareamento de TV
device_pairing_codes/{hash}              códigos de 6 dígitos para TV
source_secrets/{familyId_sourceId}       credenciais AES-256-GCM, somente backend
deletion_jobs/{uid}                     limpeza assíncrona
```

IPTV não exige configuração familiar. No primeiro cadastro válido de uma conta sem família, o backend cria um espaço `kind: personalIptv` no namespace existente `families/{scopeId}` e associa somente `iptvWorkspaceId` à conta. `familyId` continua ausente; não há trial ou perfis criados. As fontes e o catálogo pessoais usam esse escopo também após vínculo familiar posterior. Fontes familiares anteriores mantêm seu escopo e autorização. Ver [modelo e testes de IPTV pessoal](PERSONAL_IPTV.md).

Limites familiares/sessões estão no documento familiar para que uma transação arbitre concorrência. Até cinco pessoas, incluindo o administrador. Cadastro de TVs não tem limite de quantidade; leases simultâneos têm limite de três e expiram após 90 segundos. O mesmo perfil não pode pertencer a dois leases ativos. Nome das TVs é incluído nos erros.

O trial de sete dias começa no primeiro `linkDevice` bem-sucedido. Um campo persistente impede reinício. Somente o backend altera assinatura. Planos mensal/anual são apresentados como indisponíveis; nenhum SDK de cobrança ou pagamento fictício está integrado.

Firestore e Storage negam gravações privilegiadas do cliente. O usuário só lê sua conta e sua família; associado não lê assinatura. O Player só lê seu dispositivo e comandos. Segredos e tokens são inacessíveis a todos os clientes. Arquivos de catálogo no Storage não são públicos. Índices ficam em `firestore.indexes.json`.

## Identificação, Associação e Player

Associado: o usuário compartilha sua identificação pública única de 12 caracteres (código alfanumérico ou QR Code exibido pelo botão na AppBar da Home). O administrador identifica o usuário por leitura de QR Code ou busca por código (ambas protegidas contra enumeração e abuso). O administrador inicia a solicitação de associação (`requestMembership`), o convidado recebe a solicitação e a aceita (`respondMembership`), ingressando automaticamente na família sem exigir link transferível, WhatsApp ou aprovação redundante. O limite de 5 integrantes (1 administrador + até 4 associados) é estritamente garantido em transação atômica no backend.

TV: Player chama `beginDevicePair` com App Check válido, guarda token e exibe `iplex://link/device?token=...`. Gestor administrador chama `linkDevice`. Player chama `finishDevicePair` antes de expirar e troca o custom token no Firebase Auth. Claims incluem `familyId` e `deviceId`. O token de troca é de uso único.

Player chama `acquireSession(profileId)`, mantém `heartbeat(sessionId)` aproximadamente a cada 30 segundos e chama `releaseSession` quando encerra. Requisições vencidas e dispositivos revogados são recusados.

Gestor chama `sendCommand` com `commandId`, `deviceId`, `sessionId`, `commandType`; backend acrescenta timestamp e expiração de cinco segundos. Tipos: `up`, `down`, `left`, `right`, `ok`, `back`, `playPause`. Player observa snapshots de `commands`, ignora vencidos/duplicados/outras sessões, executa e chama `ackCommand`. Gestor distingue envio de confirmação. Não há polling periódico para comandos. Medir latência e custos com o Player real antes de aprovar o transporte em produção; trocar por canal dedicado se necessário.

O aplicativo Player não está neste repositório. Execução e ACK ponta a ponta permanecem dependentes dessa integração.

## IPTV

`saveSource` valida formato HTTPS e criptografa credenciais com AES-256-GCM. O segredo `IPTV_CREDENTIAL_KEY` é base64 de 32 bytes, gerenciado no backend. Nunca fornecer ao Flutter. Worker agendado a cada 30 minutos seleciona até dez fontes vencidas por execução e revalida fontes bem-sucedidas após seis horas; falhas têm nova tentativa após 30 minutos.

Acesso ao provedor tem DNS fixado a IP público, TLS, sem redirects, limite de bytes e timeout. Adaptadores M3U e listas Xtream normalizam canais/filmes/séries. JSON canônico é validado com Zod, versionado e salvo integralmente no Storage; referências de reprodução não são incluídas no JSON público. Equivalência usa conteúdo e host, nunca apenas host/credencial. Publicação troca o ponteiro após gravar o índice. Atualização vazia ou queda anormal de contagem mantém versão anterior.

Limitações atuais: temporadas/episódios/imagens e resolução de URLs de reprodução para o Player ainda precisam de implementação completa. Worker mantém versões antigas; política de retenção/limpeza e fila de processamento para cargas maiores precisam ser adicionadas antes de produção. A consulta de catálogo usa páginas de 30 e busca por prefixo, por fonte selecionada. Listas administrativas têm limite atual de leitura de 100 e precisam de paginação para famílias com muitas TVs/fontes.

## Configuração

Parâmetros opcionais de compilação: `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`, `FIREBASE_IOS_BUNDLE_ID`, `GOOGLE_SERVER_CLIENT_ID`, `APP_CHECK_WEB_KEY`, `APP_CHECK_DEBUG_TOKEN`, `TERMS_URL`, `PRIVACY_URL`.

`FIREBASE_PROJECT_ID` em produção deve ser `iplex-2c8fc`. Em debug com `USE_EMULATORS=true`, `demo-iplex` é aceito. Use `EMULATOR_HOST=10.0.2.2` no emulador Android e `127.0.0.1` no iOS Simulator. Para aparelho físico, encaminhe portas ou use endereço local apropriado. Nunca use credenciais de produção como fixtures.

Idioma do dispositivo: português é mapeado para pt_BR, espanhol para es, inglês para en, outros idiomas usam inglês. Preferência manual é persistida em `users/{uid}.locale` via backend e aplicada pela árvore do app.

## Publicação segura

Nenhum deploy foi executado por esta implementação. Antes de publicar: verificar projeto, edição/região, conteúdo das regras existentes, índices, Storage, billing, IAM, segredos, provedores OAuth e App Check. Testar emuladores primeiro, revisar alterações de regras e provisionar TTL de comandos/tokens. A região atual do código de Functions é `us-central1`; revisar latência e residência de dados com a configuração escolhida. Não publicar configuração de debug nas lojas.
