# Gestor gratuito e autorização de reprodução

## Resultado da auditoria

O Gestor pode ser utilizado por qualquer conta autenticada sem assinatura ativa. A Home e as cinco abas não dependem de família, dispositivo, fonte ou assinatura. Operações familiares preservam as permissões existentes. Avaliação expirada não bloqueia criação, edição, exclusão, sincronização, configurações, logout ou exclusão de conta.

Não havia paywall de assinatura nas operações administrativas auditadas. `go_router`, providers de conta/família, formulários, repositório, listeners de autenticação, callable `manager`, worker IPTV e regras locais não exigiam pagamento para administrar. As condições de assinatura no serviço já protegiam exclusivamente início e renovação de sessões de reprodução. Portanto, não foram removidas proteções de reprodução nem inventados bloqueios para removê-los.

A restrição encontrada estava na consulta de planos: `/account/subscription` exigia família e administração em `router.dart`, e o acesso na Conta só aparecia para administradores. Esses requisitos foram removidos apenas da consulta informativa. Contas sem família e associados agora consultam planos mensal/anual. Os detalhes privados da assinatura familiar continuam exclusivos do administrador; regras Firestore e Storage não precisaram ser relaxadas.

## Políticas distintas

| Capacidade | Autorização |
| --- | --- |
| Entrar no Gestor e consultar planos | Identidade autenticada, verificada por `authProvider` e pelo router |
| Administrar família, perfis e dispositivos | Identidade, vínculo e papel administrativo; `adminProvider` na interface e `family(tx, actor, true)` no servidor |
| Gerenciar IPTV pessoal | Identidade e propriedade do espaço privado; configuração familiar opcional; ver [IPTV pessoal](PERSONAL_IPTV.md) |
| Gerenciar fontes familiares existentes | Identidade, vínculo e papel administrativo familiar preservados |
| Navegar e pesquisar o catálogo | Identidade, acesso ao espaço pessoal ou familiar e versão publicada de uma fonte existente |
| Controlar Player | Vínculo familiar, dispositivo e sessão técnica válidos; validade do comando, deduplicação e rate limit |
| Iniciar/renovar reprodução | `canStartPlayback` no servidor, além de identidade do Player, família, dispositivo, perfil e limites de sessões |

Nenhum booleano fornecido pelo cliente concede reprodução. O servidor lê o documento privado da assinatura dentro da transação em `acquireSession` e `heartbeat`. Metadados ausentes, datas ausentes/não finitas, assinatura pendente e prazo vencido negam reprodução. O erro `subscription-required` inclui `plansRoute: /account/subscription`; o Gestor possui mensagem localizada de reprodução, sem paywall administrativo.

`player()` também exige UID correspondente à identidade emitida pelo pareamento (`tv_<deviceId>`), claims de família/dispositivo, existência desses documentos e família não marcada para exclusão. Perfil deve existir na família. Permanecem até três leases simultâneos e exclusividade de perfil por TV. A quantidade de dispositivos vinculados não é limitada a três.

## Avaliação e interface

O primeiro `linkDevice` bem-sucedido grava uma avaliação de exatamente sete dias. `trialStartedAt` persistido impede repetição em vínculos posteriores, bootstrap ou criação de perfis. Corrigido um caso adicional: vincular a primeira TV não substitui uma assinatura paga válida pelo estado de avaliação, preservando `paidUntil`.

A tela informa explicitamente que o Gestor é gratuito e que a assinatura se refere ao Player. Mensal/anual permanecem informativos e indisponíveis para compra, sem checkout, preço inventado ou ativação simulada. Estados `active` e `cancelled` com prazo pago vencido são apresentados como expirados, assim como avaliação vencida. Ausência de metadados conhecidos é apresentada como indisponibilidade.

`subscriptionProvider` é opcional e separado da autenticação/roteamento. Só consulta dados privados para administrador, descarta-os quando o papel muda e permite tentativa manual após erro. Skeleton e feedback ficam na área de situação da assinatura; planos e explicação permanecem disponíveis durante carregamento ou falha.

## Segurança preservada

- Autenticação Google/Apple e App Check da callable.
- Papéis familiares e autorização novamente verificada no backend.
- Escritas privilegiadas exclusivamente no backend; cliente não pode criar, alterar ou excluir assinatura, nem inserir flags de acesso em sua conta.
- Segredos de IPTV com AES-GCM; fontes, sincronização e consulta de catálogo sem condição de assinatura.
- Catálogo canônico sem URLs protegidas de reprodução; referências M3U irreversíveis e credenciais fora do catálogo público aos membros.
- Firestore limitado à família; assinatura privada apenas para administrador; tokens e segredos inacessíveis; Storage sem acesso direto do cliente.
- Pareamento temporário de uso único, limites de família, leases e proteção de perfis simultâneos.

O [resultado da auditoria de regras](FREE_MANAGER_SECURITY_AUDIT.json) registra o escopo e a avaliação da skill Firebase Security Rules Auditor.

## Arquivos desta alteração

- `lib/app/router.dart` e `lib/features/manager/account_page.dart`: acesso informativo a planos para todas as contas autenticadas.
- `lib/core/data/subscription_provider.dart`: consulta privada opcional, conforme papel familiar.
- `lib/features/manager/subscription_page.dart` e `widgets/subscription_status_card.dart`: Gestor gratuito, planos, estados e datas.
- `lib/core/design_system/feedback/failure_feedback.dart`, ARBs e localizações geradas: mensagem específica de reprodução e textos em en/pt_BR/es, com fallback pt.
- `functions/src/domain.ts` e `service.ts`: política nomeada de reprodução, negação segura, identidade do Player, preservação do período pago e indicação da rota dos planos.
- `test/free_manager_access_test.dart`, `functions/test/free_manager.integration.ts`, `domain.test.ts` e `security.rules.ts`: cobertura de acesso, privacidade e autorização.
- Este relatório, auditoria JSON, arquitetura, estado de validação e captura `docs/screenshots/subscription-plans.png`.

## Cobertura dos cenários solicitados

| Cenário | Evidência |
| --- | --- |
| 1. Novo usuário sem assinatura na Home | Navegação inicial existente e testes de acesso gratuito |
| 2. Cinco abas sem assinatura | Testes Flutter com estado `notStarted` e `expired`, sem leitura de assinatura |
| 3. Criar família sem assinatura | Formulário Flutter e transação real nos emuladores; avaliação ainda não iniciada |
| 4. Adicionar perfil | Formulário Flutter e endpoint real |
| 5. Cadastrar dispositivo | Pareamento e `linkDevice` nos emuladores sem direito de reprodução |
| 6. Cadastrar IPTV | Formulário Flutter e M3U/Xtream nos emuladores |
| 7. Editar IPTV | Formulário Flutter e atualização real com preservação de senha |
| 8. Sincronizar sem assinatura | Ação de tela e `syncSource` real com estados sem avaliação/expirado/pendente |
| 9. Acessar Conta | Navegação das cinco abas |
| 10. Consultar planos | Conta sem família, associado e administrador; sem leitura privada para os dois primeiros |
| 11. Negar reprodução sem direito | Metadados ausentes, estado sem avaliação, expirado, pendente e flags falsas de cliente nos emuladores |
| 12. Reprodução com avaliação válida | `acquireSession` real com estado `trial` |
| 13. Reprodução com assinatura ativa | `acquireSession` real com estado `active`; cancelamento mantém apenas prazo pago válido |
| 14. Gestor após expiração | Abas, perfil, IPTV, dispositivos e controle técnico continuam autorizados |
| 15. Dados privados sem autenticação | Regras reais no emulador e redirecionamento Flutter para Login |
| 16. Associado sem administração | Regras, endpoints reais e guards Flutter; consulta de planos continua permitida |
| 17. Mais de três TVs vinculadas | Cinco vínculos reais com avaliação expirada; renomear e remover permitidos |
| 18. Quarta reprodução simultânea | Teste transacional concorrente existente admite somente três |
| 19. Um perfil em duas TVs | Teste transacional concorrente existente admite apenas uma |

Também testados: renovação negada após expiração, encerramento permitido, dispositivo revogado, identidade incompatível, perfil de outra família, trial único, preservação de pagamento, skeleton, erro/retry e descarte de dados ao perder administração.

## Validação e limites

- `flutter analyze`: sem problemas.
- `flutter test`: 107 testes passaram (92 existentes e 15 novos).
- `npm --prefix functions run check`: TypeScript compilou e 11 testes unitários passaram.
- `firebase emulators:exec --project demo-iplex --only firestore,auth`: 9 testes de regras e 16 testes de integração passaram.
- `flutter build apk --debug`: APK gerado em `build/app/outputs/flutter-apk/app-debug.apk`.
- Total: 143 testes aprovados; `git diff --check` sem erros.

Os testes de integração exercitam Auth/Firestore locais e o serviço real. O worker IPTV foi auditado e a solicitação de sincronização testada; não foi efetuada conexão com provedores externos nesta tarefa. Sem novas dependências, checkout ou mocks de produção.

A compilação Android mantém o aviso existente de compatibilidade futura do Kotlin Gradle Plugin aplicado pelos plugins Firebase. Ele não impediu o build; dependências e configuração nativa foram preservadas nesta tarefa.

O código do aplicativo iPlex Player e seu resolvedor final de URLs de reprodução não estão neste repositório. A integração do Player deve respeitar a negação do backend, validade dos leases e indicação de planos antes de reproduzir; entrega de mídia e OAuth em aparelhos reais não são comprovados pelos emuladores. Não houve deploy em `iplex-2c8fc`: as alterações do backend precisam ser publicadas pelo fluxo de implantação do projeto.
