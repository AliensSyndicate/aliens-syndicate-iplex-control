# IPTV sem configuração familiar

A aba IPTV permite abrir o cadastro e salvar M3U ou Xtream em uma conta autenticada sem criar ou vincular uma família. A Home também consulta e pesquisa esse catálogo. A primeira gravação válida prepara um espaço privado da conta em uma única transação; abrir a aba/formulário não grava dados.

## Propriedade e compatibilidade

`users/{uid}.iptvWorkspaceId` é uma referência controlada exclusivamente pelo backend. Ela não altera `familyId`, não cria perfis/dispositivos e não inicia avaliação. O espaço possui `kind: personalIptv`, `ownerId`, `adminId` e somente o proprietário em `members`. Credenciais continuam criptografadas em `source_secrets`.

Para manter compatibilidade com o worker, o catálogo canônico, índices e regras existentes, o espaço usa o namespace técnico `families/{scopeId}`. Isso não representa vínculo familiar da conta: o backend familiar continua resolvendo apenas `familyId`. Não são criados documento de assinatura, convites ou membros familiares nesse fluxo.

`Account.iptvScopeId` resolve primeiro o espaço pessoal e, para contas sem ele que já usavam fontes familiares, mantém o `familyId` existente. Essas fontes compartilhadas preservam suas permissões administrativas. `canManageIptvProvider` é separado de `adminProvider`: possuir IPTV pessoal não concede autorização para administrar perfis, dispositivos ou outra família.

Ao criar ou ingressar em uma família posteriormente, a referência pessoal permanece estável. Fontes e catálogo pessoais continuam no seu espaço, sem migração, perda de acesso ou compartilhamento automático com associados. Não há seleção arbitrária de espaço pelo cliente: o servidor lê a conta e verifica a propriedade a cada operação de fontes.

## Fluxos alterados

- Aba IPTV: estado vazio com “Adicionar fonte”, sem `FamilyScope`.
- Router: cadastro/edição de IPTV usa sua política própria; fontes compartilhadas continuam exigindo administração familiar.
- Providers e catálogo da Home: leem o escopo de IPTV, independentemente da presença de família.
- `saveSource`: valida entrada e criptografia antes de confirmar a criação do espaço e a fonte. Gravações iniciais concorrentes convergem para um único espaço.
- `syncSource` e `deleteSource`: resolvem o mesmo espaço no servidor, mantendo proteção e quotas existentes.
- Exclusão da conta: revoga imediatamente os membros do espaço pessoal e enfileira a remoção de fontes, catálogo e segredos no worker de limpeza.
- Textos de pré-requisitos familiares: mencionam dispositivos/perfis, preservando o acesso a IPTV.

## Validação

Testes Flutter cobrem primeiro cadastro, edição/sincronização, falha com nova tentativa, estado vazio em pt_BR, catálogo/busca na Home e persistência da autorização pessoal ao ingressar como associado. Os testes de integração exercitam as operações reais no Auth/Firestore Emulator: M3U/Xtream, segredo preservado, concorrência, isolamento entre contas, campos de escopo enviados pelo cliente ignorados, vínculo familiar posterior e exclusão da conta. Os testes de regras negam leitura por terceiros, acesso direto a segredos e alteração de `iptvWorkspaceId` pelo cliente.

O worker de catálogos mantém sua estrutura e não exige família ou assinatura para sincronizar fontes desse namespace. As proteções de reprodução do Player permanecem intactas. Nenhum mock de produção, checkout ou dependência foi adicionado.

Validação final: `flutter analyze` limpo; 113 testes Flutter; 11 testes unitários TypeScript; 10 testes de regras e 23 testes de integração nos emuladores aprovados. `npm run check` e `flutter build apk --debug` concluídos; `git diff --check` sem erros. A captura `docs/screenshots/iptv-unlinked.png` foi atualizada e inspecionada com o botão de cadastro direto.

A investigação do erro de salvamento confirmou, por comparação com o código publicado, que a callable ainda exigia família e aceitava somente os formatos antigos. As funções `manager`, `synchronizeCatalogs` e `purgeDeletedAccounts` foram atualizadas no projeto `iplex-2c8fc` e confirmadas como `ACTIVE`. As URLs com formatos `m3u`, `url` e `other_m3u8` foram exercitadas nos emuladores sem família ou assinatura, incluindo edição, exclusão e proteção dos segredos.

A exclusão de uma fonte por URL não acessa mais arquivos no Storage; uploads são removidos depois da transação. Tentativas incorretas de PIN são confirmadas antes de retornar erro, preservando o bloqueio após cinco tentativas. O app apresenta mensagens específicas para validação, conexão e timeout e mantém os campos preenchidos para nova tentativa. Foram aprovados 13 testes unitários, 10 de regras e 27 de integração. A conexão com um provedor real depende da URL cadastrada pelo usuário e não foi validada com fixtures de produção.

## Travamento durante desenvolvimento

No aparelho conectado, a VM ficou em `PauseException` por `NoSuchMethodError` em um callback de foco de `_NeumorphicTextFieldState`. O código atual não registra esse callback manual: o estado antigo persistiu após hot reload da refatoração dos campos. Nesse caso, a pausa do depurador bloqueia toda a interface, mesmo com o backend respondendo. Foi necessário atualizar a instalação preservando os dados e iniciar um processo novo; alterações estruturais de listeners exigem hot restart em vez de apenas hot reload.
