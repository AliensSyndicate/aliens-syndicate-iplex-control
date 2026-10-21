# Estado de implementação e validação — 19/10/2026

## Atualização 20/10/2026 — sincronização IPTV (sem deploy, commit ou push)

Diagnóstico completo em [IPTV/iptv_sync_diagnosis_2026-10-20.md](IPTV/iptv_sync_diagnosis_2026-10-20.md).

- **Causa em produção**: o backend implantado falha na resolução DNS (Node ≥ 20) e na transação de publicação (leitura após escrita), sem log útil. Corrigido localmente; **exige deploy**.
- Download robusto (redirecionamento, gzip, charset, User‑Agent alternativo, limites, erros classificados), parsers M3U/Xtream tolerantes, séries M3U com episódios, episódios Xtream sob demanda, índice de streams criptografado para reprodução.
- Control mostra nova tentativa agendada, erro específico com detalhe técnico, catálogo anterior preservado e contagem por tipo.
- Validação: 88 unitários, 14 de regras, 67 de integração (servidor IPTV controlado com HTTP real); 238 testes Flutter; 164 testes Web. Listas reais: 476 e 11 365 itens sincronizados pelo trigger; reprodução no Web confirmada.

## Atualização 20/10/2026 — integração Control ↔ Web ↔ App (sem deploy, commit ou push)

Contratos v1 em [CONTRACTS.md](CONTRACTS.md). Relatório completo, matriz e plano de implantação/rollback em `aliens-syndicate-iplex-web/docs/INTEGRACAO-2026-10-20.md`.

- **Controle remoto removido** (tela, rota, `sendCommand`/`ackCommand`, regras de `commands`). O Control não pausa, avança, para nem navega a TV.
- **Assistir na TV** (`features/watch_on_tv/`): busca na Home → título → escolha da TV (e do episódio, em séries) → `requestPlayback` → status ao vivo do pedido (`play_requests`). Backend em `functions/src/play_requests.ts`.
- **PIN parental** (`functions/src/parental.ts`, tela Família › Controle parental): hash scrypt, 5 tentativas por TV, aplicado no `acquireSession`.
- **Desvinculação imediata**: revogação do refresh token + marcador para o ouvinte da TV (≈1 s na Samsung).
- **EPG na TV**: `readSourceEpg` liberado na `player`.
- Correções: favorito pelo Control sem `generation` (sempre rejeitado); primeira família aceita não virava contexto ativo (conta ficava sem acesso à família).

Validação: 79 unitários, 14 de regras e 62 de integração (backend); `flutter analyze` limpo e 235 testes Flutter; E2E com emuladores + iPlex Web + Samsung UN65TU7020 (Tizen 5.5) + Control no iPhone 17 Pro Simulator (ver relatório). Ferramenta: `functions/scripts/e2e_tv.ts`.

## Atualização — perfis familiares, visitante, infantil e limpeza de dados

Perfis de mídia independentes de conta (1 administrador, 4 associados, visitante opcional), vinculação posterior por código temporário de uso único, permissões por fonte × tipo de conteúdo, perfil infantil restrito no backend, três limpezas independentes com confirmação e exclusão real no Firestore, gerações contra restauração offline. Detalhes e contrato do Player em [Perfis familiares](FAMILY_PROFILES.md).

Pendente fora do repositório: o Player TV precisa adotar `generation` e `listPlayerProfiles`/`listProfileSpaces`; até lá ele não consegue salvar favoritos/progresso (escritas sem geração são rejeitadas por decisão do responsável). Sem deploy.

## Atualização — validação ponta a ponta e correções de integração

Correções com causa identificada:
- Publicação de catálogo IPTV falhava sempre (`catalog-publication-failed`): a transação lia `sources/{id}` e jobs irmãos depois de escrever. Leituras movidas para o início; jobs irmãos agora notificam a própria fonte.
- Todo download por URL falhava com `provider-unavailable` (`ERR_INVALID_IP_ADDRESS`): o `lookup` fixado contra SSRF não atendia a forma `{all: true}` usada pelo Node ≥ 20. Corrigido em `pinnedLookup` com teste de requisição real.
- Callables disparavam `syncIptvCatalog` sem aguardar após responder, disputando a lease com o trigger `processIptvSyncJobTrigger`; removido (trigger + recuperação a cada minuto continuam responsáveis).
- Modo emulador do Gestor nunca alcançava o backend: `enforceAppCheck` rejeitava chamadas sem App Check e o app usava o projectId de produção. App Check segue obrigatório fora do emulador; o app usa `FIREBASE_PROJECT_ID` no modo emulador.
- Pareamento: consultas por código de 6 dígitos sem limite (força bruta) agora consomem cota (20/h); sessão expirada/consumida retorna `pairing-expired`; scanner e código manual mostram a mensagem específica.
- Aba principal renomeada para **Família** (estava "Usuários"); textos de vínculo de TV não presumem família; moldura do scanner não cobre mais o aviso de câmera indisponível; códigos IPTV `invalid-epg`, `catalog-integrity`, `worker-retries-exhausted` e `source-secret-unavailable` com mensagens próprias (pt/en/es).
- Novos códigos públicos sem caracteres ambíguos (0/O, 1/I/L); QR do usuário versionado (`iplex://user?v=1&code=`), leitura do formato anterior mantida.

Ferramentas: `functions/scripts/dev_pairing_qr.ts` (TV simulada com sessão real, só emulador), `functions/scripts/e2e_callable.ts` (cenários A–D via HTTP callable), skill `.claude/skills/iplex-e2e-validation`.

Validação executada: `flutter analyze` limpo; 223 testes Flutter; 70 testes unitários backend; 12 de regras e 40 de integração nos emuladores; cenários A–D via callable com Functions Emulator (inclui M3U pública real com 477 itens publicada pelo trigger); Gestor no iPhone 17 Pro Simulator contra os emuladores (Home sem família, QR do usuário, pareamento por código com TV simulada, lista de dispositivos, criação de família). Sem deploy. Não validado: câmera física, OAuth Google/Apple real, TV Player real, entrega FCM, Android (sem AVD disponível).

## Registro anterior — 17/10/2026

## Atualização — salvamento de URL IPTV e padrão dos inputs

Corrigida a incompatibilidade entre o formulário atual e a versão antiga do backend. `manager`, `synchronizeCatalogs` e `purgeDeletedAccounts` foram publicadas em `iplex-2c8fc` e confirmadas ativas. O salvamento M3U/M3U8 sem família foi validado em emuladores; mensagens de validação, conexão e timeout agora orientam a nova tentativa. Ver [IPTV pessoal](PERSONAL_IPTV.md).

Inputs de texto, busca, PIN e seletores compartilham label fixo no topo, controle com 56 dp e label/borda brancos em foco. A validação fica abaixo da superfície. Validação: 154 testes Flutter e 50 testes backend (13 unitários, 10 de regras, 27 de integração), análise estática limpa e APK debug compilado. Captura do formulário atualizada. Os registros seguintes descrevem etapas anteriores.

## Atualização — IPTV sem configuração familiar

A conta sem família pode cadastrar, editar e sincronizar fontes diretamente. Um espaço privado é criado apenas na primeira gravação válida, preservado ao ingressar em uma família e incluído na exclusão da conta. Home e busca consultam o catálogo pessoal; fontes familiares existentes preservam suas permissões. Validação: 113 testes Flutter e 44 testes backend aprovados (11 unitários, 10 de regras, 23 de integração). Implementação, compatibilidade e dependência de implantação em [IPTV pessoal](PERSONAL_IPTV.md).

## Atualização — Gestor gratuito e assinatura do Player

Planos agora disponíveis a toda conta autenticada; dados privados familiares continuam exclusivos do administrador. Administração não exige assinatura. Política de reprodução explícita no servidor, com negação segura e preservação de trial único, pagamento válido e limites de sessões. Validação: análise Flutter limpa, 107 testes Flutter e 36 testes backend aprovados (11 unitários, 9 de regras, 16 de integração). Ver [relatório e pendências de implantação/Player](FREE_MANAGER_ACCESS.md). As validações abaixo registram etapas anteriores.

## Atualização — autenticação e navegação inicial

Corrigido o redirect obrigatório para família. Login e restauração agora chegam à Home; Contas Familiares é acesso manual em Usuários. Foram acrescentados skeletons e estados distintos de ausência de dados, sincronização, busca vazia e erro, preservando o design. Validação desta correção: `flutter analyze` limpo e 57 testes Flutter passaram. Ver [relatório da correção](AUTH_NAVIGATION.md). O restante deste documento registra o estado da implementação anterior.

A identidade visual foi refinada a partir da imagem grafite mais recente e inspecionada em capturas de widgets Flutter. O projeto completo ainda não atende todos os critérios de produção da missão inicial.

## Implementado no código

- Cinco abas go_router com preservação de estado, redirecionamento por sessão e autorização de ações administrativas.
- Design system grafite compartilhado, grão fosco, bordas físicas, luz consistente, sombras internas recortadas, botões circulares, seleção rebaixada, barra inferior reta, campos/seletores/avatar/listas/diálogos.
- Telas de autenticação, família, associados, perfis, dispositivos, fontes, catálogo, favoritos, progresso, conta, preferências e assinatura sem cobrança.
- Repositório Firebase e bootstrap; idiomas en/pt_BR/es com preferência persistente.
- Backend v2 com autorização, tokens temporários, transações familiares e de sessões, trial único, comandos com TTL/ACK e proteção das credenciais de fonte.
- Worker de sincronização M3U/listas Xtream, validação, armazenamento de versões e publicação por ponteiro.
- Regras Firestore e Storage locais; leitura de catálogo exige vínculo ativo com a versão publicada. Fallback de metadados de conta é limitado a nome/e-mail/data de atualização; cliente não pode atribuir família ou privilégios.

## Parcial ou pendente de implementação

- Catálogo: temporadas/episódios/imagens, referências completas para resolução autorizada pelo Player, seções editoriais reais de destaques/lançamentos e busca além de prefixo por fonte.
- Favoritos/progresso persistem no perfil; resolução de disponibilidade e conflitos mais elaborados ainda precisam ser concluídos. A indicação atual de indisponibilidade é conservadora e não comprova remoção da origem.
- Paginação das listas administrativas acima de 100 registros.
- Retenção de catálogos antigos, limpeza de arquivos compartilhados e fila/escala de processamento para volume elevado.
- Observabilidade operacional, políticas de retry mais completas, revisão de quotas e validação da exclusão de conta em todos os cenários nativos.
- Ajuda/suporte precisa de destino real; links legais precisam ser fornecidos na configuração.

## Bloqueado ou sem validação externa

- Player TV não fornecido: pairing real, heartbeat, consumo de comandos/ACK, latência e exclusividade no produto TV não foram testados ponta a ponta.
- Google/Apple OAuth em dispositivos reais e revogação Apple não foram validados nesta execução.
- Provedores IPTV reais, Scheduler, Storage e workers em produção não foram validados; nenhum deploy foi realizado nesta execução.
- Build iOS Simulator bloqueado pela resolução oficial das dependências: Firebase Apple 13.0.0 requer GTMSessionFetcher >=4; Google Sign-In iOS 9 exige <4. A incompatibilidade consta nas [notas oficiais do Firebase](https://firebase.google.com/support/release-notes/ios). Não foram aplicados patches em SDKs ou mudanças na assinatura de distribuição.

## Firebase: auditoria inicial e estado posterior

A auditoria inicial encontrou apps vazios/API Firestore desabilitada. Consulta somente leitura posterior encontrou apps Android/iOS/Web registrados e banco `(default)` STANDARD, modo nativo, região `nam5`. Os arquivos locais também passaram a incluir configuração FlutterFire. Essa verificação posterior atualiza o bloqueio inicial; não comprova Functions, IAM, billing, provedores OAuth ou validação de produção. A pasta passou a possuir Git durante o trabalho; alterações já existentes, inclusive staged, foram preservadas.

Serviços usados no código: Authentication, Firestore, callable/scheduled Functions v2, Storage Admin, App Check, Crashlytics e Analytics (coleta Analytics desativada). Não há billing de loja ou player de mídia no Gestor.

## Comandos e resultados

- `flutter pub get`: dependências resolvidas.
- `dart format .`: executado inicialmente; também percorreu exemplos gerados em build. Nas verificações posteriores, formatação foi limitada a `lib test`.
- `dart format lib test`: sem alterações pendentes na última execução.
- `flutter analyze`: sem problemas na validação visual.
- `flutter test --dart-define=SCREENSHOTS=true`: 27 testes passaram. Capturas inspecionadas: login, controle, direcional, Início, Usuários, Dispositivos, IPTV, Conta, preferências e formulário de fonte. Dados de listas das capturas são fixtures exclusivas de testes.
- Layouts: 390×844; 320×640 com texto 1,8×; controle 740×360 com texto 1,5×. Inclui estados de erro, cancelamento de confirmação e validação de URL.
- `npm --prefix functions run check`: TypeScript compila; 9 testes de domínio/adaptadores passaram.
- Emuladores Auth/Firestore em `demo-iplex`: verificação inicial passou com 5 testes de regras e 5 de integração do serviço. Durante a revisão posterior um teste detectou gravação irrestrita de conta; regras foram corrigidas e testes de regressão acrescentados. Resultado final: 7 testes de regras e 5 testes de integração do serviço passaram, sem falhas.
- `flutter build apk --debug`: APK de depuração gerado em `build/app/outputs/flutter-apk/app-debug.apk`. Não é release para distribuição.
- `flutter build ios --simulator --debug`: falhou no resolvedor SPM, conforme bloqueio acima; nenhum binário iOS gerado.

Total da execução final: 48 testes passaram (27 Flutter, 9 domínio/adaptadores, 7 regras, 5 integrações do serviço). O APK final foi recompilado após a calibração da paleta e os últimos ajustes de componentes.

Esses testes locais não substituem login OAuth, teste de câmera/QR, sincronização de provedor real ou execução no Player TV.

## Principais arquivos

`lib/core/design_system/{tokens,graphite_material,components}.dart`, `lib/app/app.dart`, `lib/features/authentication/login_page.dart`, `lib/features/manager/`, `lib/features/remote_control/remote_page.dart`, `lib/core/data/`, `lib/l10n/`, `functions/src/`, `functions/test/`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `test/visual_test.dart` e `test/widget_test.dart`.

## Próximas ações de produção

Resolver uma combinação oficialmente compatível do Firebase/Google Sign-In no iOS; validar OAuth/App Check e configuração legal; concluir as partes de catálogo e disponibilidade; integrar o Player ao contrato; provisionar/verificar segredos, IAM, Storage e agendamentos; revisar custos e regras existentes antes de qualquer deploy. Não publicar nas lojas até concluir esses itens.
