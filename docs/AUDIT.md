# Auditoria — 17/10/2026

Raiz: aliens_syndicate_iplex_control. Auditoria realizada antes de editar fontes.

- Flutter 3.47.4 stable, Dart 3.13.3; Android SDK 36/37, Java 17, Xcode 27 e CocoaPods disponíveis.
- Base existente: contador Flutter, Cupertino Icons e flutter_lints 6; um teste do contador. Sem gerenciamento de estado, rotas, Firebase, componentes de negócio ou documentação específica.
- Android/iOS são templates; identificadores com.example preservados até definição de identificadores de distribuição. iOS mínimo 15.0. Nenhuma assinatura de distribuição alterada.
- Nenhum .git nesta pasta: não foi possível inspecionar diff/histórico. Estruturas de plataformas preservadas.
- Referências fornecidas em anexos temporários: superfície grafite e ergonomia de controle circular. Assets locais anteriores são somente ícones/launch images do template.
- flutter doctor -v: sem problemas. SDK exige acesso ao cache externo à pasta, aprovado pelo ambiente.
- Firebase remoto, consultas somente leitura: apps:list retornou lista vazia; firestore:databases:list retornou 403 API desabilitada; functions:list falhou. Não é possível verificar edição do Firestore, regras existentes, provedores Auth, Storage e IAM com os resultados disponíveis. Nenhum recurso remoto modificado.

## Decisões

Preservar projeto e plataformas. Introduzir Riverpod e go_router pois não há soluções anteriores. SDK Firestore padrão com modelo documental; edição remota permanece pendente de provisionamento/verificação. Desenvolvimento/testes isolados usam demo-iplex em emuladores. Produção fica bloqueada até registros Android/iOS, provedores OAuth, App Check, edição/região de banco, Storage, IAM e segredos serem configurados.

Prioridade: tokens/componentes; shell/rotas; repositório Firebase; backend transacional; UI dos fluxos; processamento IPTV; testes e documentação. Nenhum dado demonstrativo em produção, nenhuma reprodução no Gestor, nenhum pagamento. Transporte remoto via snapshots Firestore com TTL e ACK (sem polling), dependente do contrato do Player.

## Referências técnicas

- Hugeicons Flutter gratuito, Stroke Rounded, MIT: https://pub.dev/packages/hugeicons/license e https://hugeicons.com/docs/integrations/flutter
- Firebase OAuth: https://firebase.google.com/docs/auth/flutter/federated-auth

## Riscos externos

OAuth Google/Apple e exclusão/revogação Apple precisam de configuração e validação nativas. Player separado ainda não fornecido. Provedores IPTV reais não fornecidos. Deploy/custos/região/IAM não verificados. Builds locais não provam autenticação ou integração real.

## Verificação posterior

Durante o trabalho a pasta passou a ter repositório Git e configurações FlutterFire. Uma nova consulta somente leitura confirmou apps Android/iOS/Web e Firestore `(default)` STANDARD em `nam5`. O registro inicial acima é histórico e não descreve mais a disponibilidade desses recursos. Ver `STATUS.md` para o estado consolidado; nenhum deploy foi executado nesta implementação.
