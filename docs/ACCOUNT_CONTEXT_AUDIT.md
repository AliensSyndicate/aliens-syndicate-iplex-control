# Auditoria inicial — 19/10/2026

Antes de alterar código, foram examinados service.ts, iptv_workspace.ts,
index.ts, firestore.rules, repositório Firebase, providers, router, telas de
família/dispositivos/IPTV/Home/Configurações e componentes do design system.

- Banco existente confirmado por consulta somente leitura: iplex-2c8fc,
  (default), Firestore STANDARD / FIRESTORE_NATIVE, nam5.
- Bootstrap já não cria família; fallback Flutter pode ocultar falha no backend.
- users.familyId representa vínculo único e contexto implícito. createFamily e
  joinFamily recusam um segundo vínculo. Papel administrativo deriva desse campo.
- Dispositivos exigem família no backend; router exige admin para add/edit.
  Listagem e detalhes usam familyId, sem escopo pessoal.
- renameDevice/deleteDevice aceitam documento global existente sem validar o
  escopo dele: risco de alteração cruzada, mesmo quando a cópia local não existe.
- IPTV pessoal já tem espaço privado kind: personalIptv no namespace families,
  ownerId e iptvWorkspaceId, sem associação familiar, assinatura ou trial.
- Convite usa token transferível por link e adesão imediata; não há código
  público persistente, busca nominal limitada ou solicitação endereçada.
- Trial e leases são por titularidade de escopo, com sete dias, três leases e
  exclusividade de perfil. Gestão não exige assinatura. Manter essa política.
- Regras negam mutações privilegiadas do cliente. Conta privada só é lida pelo
  titular. ACL de families é a fonte de autoridade. subscriptions top-level
  permite associado e precisa da mesma privacidade de private/subscription.
- UI reutilizável: PageTemplate, CircularButton, AppModalSheet, AppSurface,
  EntryTile, AppButton, AppTextField, EmptyState e scanner existentes.
- Traduções reais: app_pt.arb (pt_BR/fallback pt), app_en.arb e app_es.arb.
- Não há AGENTS.md, .agents, .codex, skills locais ou agentes especializados
  neste checkout nem AGENTS.md nos diretórios ancestrais inspecionados.
- Não há URL oficial de instalação. Usuário autorizou configuração provisória;
  link de loja não será apresentado como oficial sem existir.
- Há alterações staged anteriores em docs, router, tokens, telas e testes.
  Devem ser preservadas; nada será revertido ou commitado automaticamente.

Consultas existentes: streams em families/{scope}/subcoleção, conta por UID,
catálogo por fonte/versão, jobs por familyId/requestedByUid. Novas leituras:
solicitações por recipientUid/status, famílias pelos IDs backend-owned da conta.
Novas escritas privilegiadas permanecem exclusivamente em Functions.
