# Correção do fluxo inicial de autenticação

## Causa confirmada

Em `lib/app/app.dart`, o redirect global do go_router continha uma condição que enviava todo usuário sem `account.familyId` para `/family`. Também redirecionava o usuário que já tinha família para fora das rotas de família. Isso tornava a criação/vinculação familiar uma etapa obrigatória e impedia o acesso à Home no primeiro login.

A rota inicial já era `/home` e a Home já era a primeira branch, índice 0. Não foi necessário recriar o shell nem mudar as cinco abas.

## Comportamento atual

1. Splash aguarda a resposta do Firebase Auth.
2. Sem sessão: Login, mantendo eventual deep link interno.
3. Com sessão: `accountProvider` chama `initializeAccount(uid)` e observa a conta. Esse passo é compartilhado entre login, restauração e tentativas manuais; não cria família, perfis, TVs ou fontes.
4. Conta pronta: Home, índice 0. Se houver um deep link explícito e autorizado, o destino recebido é preservado, inclusive query e fragmento.
5. Falha ou timeout ao preparar a conta: mensagem, botão Tentar novamente e opção Sair. Não há criação de dados fictícios nem redirecionamento por ausência de família.

A inicialização preserva o bootstrap Firebase existente e seu fallback restrito aos metadados da própria conta. Google, Apple, UID, persistência de sessão, logout e reautenticação permanecem no mesmo repositório. Uma troca de UID invalida o estado anterior; respostas antigas de catálogo são descartadas.

`RouterRefresh` agrupa atualizações de Auth/conta/família por frame para que redirecionamentos não disputem uma localização antiga. Logout aguarda chegar a um Login sem destino residual; o próximo login normal abre Home. Um novo deep link solicitado depois do logout continua preservável.

## Contas Familiares e segurança

Na aba IPTV, uma conta ainda sem família mostra o estado vazio específico de fontes (`SourcesEmptyState`) com acesso direto a “Adicionar fonte”. Essa aba não usa `FamilyScope`; cadastro, detalhes, edição, sincronização e catálogo usam um espaço privado da conta quando não há vínculo familiar. As fontes familiares existentes mantêm suas permissões. Ver [IPTV independente da configuração familiar](PERSONAL_IPTV.md).

`/family` e `/family/create` conservam seus caminhos e agora pertencem à branch de Usuários. Usuários oferece acesso manual a Contas Familiares. A página tem retorno normal, criação voluntária quando não há família e listagem/detalhes/convite autorizado quando há vínculo. A associação familiar é feita por solicitação endereçada (leitura de QR Code ou busca por código de 12 caracteres), nunca por link transferível.

Home e as cinco abas são acessíveis com uma conta autenticada mesmo sem família. Contas individuais gerenciam seus próprios dispositivos e playlists IPTV. Operações que de fato exigem vínculo ou administração familiar continuam protegidas. Tentativas de abrir um formulário administrativo por URL sem permissão exibem uma explicação e ações de recuperação. O backend é o garantidor final da autorização.

## Estados e feedback

| Condição | Feedback |
| --- | --- |
| Auth ainda não respondeu | Splash e Verificando sua sessão |
| Inicialização da conta pendente | Splash e Preparando sua conta |
| Inicialização falhou/expirou | Mensagem, Tentar novamente e Sair |
| Sem família ou sem fontes | Bem-vindo ao iPlex, explicação e ações de dispositivos/IPTV |
| Família exigida por uma operação | Explicação e acesso manual por Usuários |
| Fontes/listas sendo lidas | Skeleton reutilizável no material grafite |
| Fontes aguardando processamento | Status de sincronização, acesso a IPTV e Tentar novamente |
| Fontes sem versão e com falha | Mensagem de falha de sincronização e ações de recuperação |
| Catálogo sendo carregado | Skeleton, sem anunciar lista vazia antes da resposta |
| Catálogo respondeu vazio | Boas-vindas e orientação contextual |
| Busca sem resultados | Mensagem específica e Limpar busca |
| Requisição falhou | Erro e Tentar novamente; não é tratado como lista vazia |
| Favoritos sem perfis | Explicação e formulário existente de criação, quando autorizado |
| Conta sem vínculo familiar | Sem família vinculada, sem atribuir papel de associado |

Os skeletons são estáticos, sem dependências adicionais, reutilizam os tokens/componentes existentes e expõem uma única descrição de carregamento ao leitor de tela. A identidade grafite, a barra inferior, os ícones, as fontes e as animações existentes foram preservados. As novas mensagens estão em en, pt_BR e es, além do fallback pt usado pelo gerador.

Sem família, as ações da Home abrem as seções correspondentes, que explicam o vínculo necessário para uma operação. Com família e autorização de administrador, abrem os formulários existentes. Associados recebem navegação de consulta, sem acesso administrativo.

## Validação executada

- `flutter gen-l10n`: geração concluída.
- `dart format lib test`: concluído.
- `flutter analyze`: nenhum problema encontrado.
- `flutter test --dart-define=SCREENSHOTS=true`: **57 testes passaram**, sendo 30 novos testes de navegação/estados e 27 testes já existentes.
- `git diff --check`: sem erros de whitespace.
- `flutter build apk --debug`: concluído; APK atualizado em `build/app/outputs/flutter-apk/app-debug.apk`.

Os dez cenários solicitados estão cobertos: visitante; primeiro login; login existente; sessão persistente; acesso manual à família; retorno à aba; logout; rota privada sem sessão; ausência de dados; deep link autorizado. Também foram verificados erros/timeouts, tentativas manuais, permissões administrativas, ausência de perfis, mudança de família com resposta atrasada, unicidade da Home e texto ampliado em tela estreita.

Capturas renderizadas e inspecionadas:

- `docs/screenshots/home-welcome.png`
- `docs/screenshots/home-skeleton.png`
- `docs/screenshots/session-retry.png`

## Arquivos alterados

Os caminhos agrupados abaixo registram a implementação original desta correção. Após a reorganização dos componentes, rotas ficam em `lib/app/router.dart`, feedback da sessão em `session_loading_page.dart` e cada tela administrativa possui seu próprio arquivo. Consulte a [organização atual](ARCHITECTURE.md#organização-dos-componentes).

- `lib/app/app.dart`: política de redirect, agrupamento de refresh, Splash/feedback e vínculo das rotas familiares à branch Usuários.
- `lib/core/domain/repository.dart`, `lib/core/data/{firebase_repository,providers}.dart`: inicialização única da conta por sessão, validação de UID e descarte seguro de estado.
- `lib/features/manager/{catalog_page,list_pages,forms,account_pages,empty_states}.dart`: estados, ações e acesso manual à família.
- `lib/core/design_system/loading_skeleton.dart`: componente de carregamento que reutiliza o design existente.
- `lib/l10n/`: mensagens e localizações geradas.
- `test/navigation_test.dart` e adaptação da interface em `test/widget_test.dart`.
- Documentação e capturas.

## Limites da validação

Os testes usam a fronteira explícita de repositório em memória; não comprovam OAuth Google/Apple em aparelho real nem entrega de links pelo Android/iOS. A correção preserva o destino que chega ao go_router. Configuração de provedores e de links nativos permanece dependente do ambiente existente. Não houve deploy ou mudança do projeto `iplex-2c8fc`.
