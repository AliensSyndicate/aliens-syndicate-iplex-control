# Identidade visual — grafite físico

Referência principal: imagem do controle grafite fornecida pelo usuário em 17/10/2026. A referência define o material e a iluminação, e não adiciona funções de climatização ou bloqueio ao aplicativo.

## Material compartilhado

`graphite_material.dart` pinta o fundo contínuo, o grão fosco, as faces e as bordas. A luz vem do alto à esquerda. A sombra projetada fica abaixo e à direita; as cavidades usam sombras realmente recortadas dentro do contorno. Não há imagens de tela usadas como botões.

- Fundo: #39373A, com variação discreta entre #403E41 e #2C2C2C.
- Faces: #403E41 / #353336; botões circulares: #28272A / #3F3D40.
- Sulco externo: #101012. Reflexo de borda: #636365, usado somente em linhas finas.
- Texto: #E5E3E5. Texto secundário: #B5B4B6.
- Cor semântica moderada para status e erros; seleção depende da profundidade.

Amostragem do PNG original (medianas de regiões sem ícones): fundo superior #403E41, fundo lateral #3D3B3E, fundo inferior #2C2C2C; disco iluminado #5F5D60, disco inferior #1E1E1E, centro #434144. Os acabamentos interpolam essas amostras para preservar o efeito físico em dimensões diferentes.

Os valores estão em `AppColors`, `AppSpacing`, `AppDimensions`, `AppRadii`, `AppTypography` e `AppMotion`. As superfícies compartilham o mesmo pintor; não precisam de cores/sombras por tela.

## Componentes

- `GraphiteBackdrop`: material contínuo sob as rotas.
- `GraphiteSurface`: acabamentos de painel, botão e disco, com modo rebaixado.
- `CircularButton`: círculo, foco, semântica acionável, estado selecionado/pressionado e alvo mínimo de 48 dp.
- `AppButton`: ação larga com o mesmo acabamento físico e estados ocupado/desabilitado.
- `AppTextField` e `AppDropdownField`: compartilham `AppInputFrame`, com label fixo acima, controle de 56 dp (`AppDimensions.input`) e label/borda brancos em foco. Erros aparecem abaixo, sem alterar a altura do controle. Busca e PIN usam o mesmo componente; o `FocusNode` externo permanece sob responsabilidade de quem o forneceu.
- `AppAvatar`: dimensões quadradas fixas para que o avatar permaneça circular.
- `EntryTile`, `EmptyState`, `ErrorState`, `PageTemplate`: listas e estados reutilizáveis.
- `BottomNavigation`: cinco botões circulares em superfície reta, sem cápsula ou contorno externo.
- `RemoteDirectionalPad`: disco circular único, direções integradas à face e botão OK em cavidade central. Voltar e reproduzir/pausar têm símbolos das ações reais.

O catálogo da tela Início consulta fontes reais. Cartazes estáticos e botões sem ação não são utilizados para simular conteúdo disponível.

## Verificação visual

As capturas em `docs/screenshots/` são de widgets Flutter renderizados, não montagens. Dados de exemplo das capturas de listas existem exclusivamente em `test/visual_test.dart`. Eles nunca são carregados pelo aplicativo em produção.

Os testes carregam a fonte Roboto e a fonte de ícones do SDK, evitando blocos Ahem nas capturas. Incluem dimensões 390 × 844, telas estreitas com texto ampliado e controle em 740 × 360. O controle pode rolar em telas baixas.

## Regra Visual Obrigatória — Prioridade Máxima

"Antes de implementar qualquer interface, reutilizar os componentes existentes. Criar novos componentes somente quando não houver equivalente adequado, preservando integralmente a identidade visual atual do iPlex."

Regras estritas:
1. Auditar os componentes existentes antes de criar qualquer interface.
2. Reutilizar `PageTemplate`, `CircularButton`, `AppButton`, `AppTextField`, `EntryTile`, `EmptyState`, `ErrorState`, `AppModalSheet` e `AppSurface`.
3. É proibido redesenhar telas sem solicitação, criar estilos visuais paralelos, introduzir novas paletas ou modificar tipografia arbitrariamente.
4. Seguir rigorosamente Dark Industrial Neumorphism e Atomic Design com as cores, espaçamentos, raios e sombras existentes.

