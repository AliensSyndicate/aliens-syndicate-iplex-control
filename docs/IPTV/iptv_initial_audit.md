# Auditoria inicial — 18/10/2026

Auditoria realizada antes das mudanças desta solicitação. O índice Git já continha alterações IPTV; elas foram preservadas e revisadas.

- Flutter/Riverpod/GoRouter; backend Functions v2 Node 22, Firestore Standard `(default)` em `nam5`, Storage privado; projeto `iplex-2c8fc`.
- Infraestrutura real consultada: Cloud Run `manager`, `purgedeletedaccounts`, `synchronizecatalogs`. Scheduler existente: sincronização a cada 30 minutos em UTC, purge a cada 60 minutos UTC. Não havia os triggers novos publicados.
- Famílias, membros, dispositivos, perfis, fontes e catálogo legado em subcoleções `families`; mirrors superiores parciais. Credenciais AES-GCM em `source_secrets`. Fontes pessoais usam família técnica `personalIptv` sem liberar playback pago.
- Pipeline: quatro formatos, download HTTPS limitado com DNS fixado, M3U/HLS/Xtream, XMLTV, Storage por hash, leases por fonte, jobs, FCM e Flutter em andamento.
- Divergências: seis horas por fonte no código; identidade do catálogo confundida com resumo sem vínculos; catálogo inteiro replicado no Firestore; categorias Xtream eram apenas IDs; temporadas/episódios ausentes; resolução de streams ausente; percentuais fixos; notificações automáticas e destinatário sobrescrito; sheets perdidos durante outro modal; jobs antigos podiam executar sobre revisão nova; exclusão lia após escrever; regras permitiam forjar campos administrativos em users, ler catálogos globais e acessar versões antigas.
- Testes encontrados: unidade TS, integração Auth/Firestore/Storage, regras e widgets Flutter. Os relatórios prévios não são evidência de execução nesta revisão.
- O Player React/TypeScript não está neste repositório. Seu caminho foi solicitado; compatibilidade de execução externa depende de inspeção e teste desse cliente.

Decisão: conservar famílias/fontes existentes como autoridade, mirrors superiores compatíveis e `catalogs` como coleção equivalente a `iptv_catalogs`; snapshots compartilhados imutáveis e contratos aditivos v1. Nenhuma migração destrutiva de documentos ou exclusão de catálogos.
