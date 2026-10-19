# ARQUITETURA DEFINITIVA DO BACKEND IPTV, CATÁLOGOS COMPARTILHADOS E SINCRONIZAÇÃO INTELIGENTE — IPLEX

**Projeto:** iPlex  
**Aplicativo Gestor:** Flutter / Dart  
**TV Player:** React / TypeScript  
**Firebase Project:** `iplex-2c8fc`  
**Ambiente:** Firebase Authentication, Firestore, Cloud Storage, Cloud Run, Cloud Scheduler, Cloud Tasks e Firebase Cloud Messaging.

---

## 1. VISÃO GERAL E PRINCÍPIOS FUNDAMENTAIS

O iPlex implementa uma arquitetura backend de alta eficiência para gerenciamento e sincronização de fontes IPTV, permitindo que catálogos de conteúdo comprovadamente equivalentes sejam compartilhados de maneira segura entre múltiplos usuários, evitando downloads redundantes, reprocessamento desnecessário e sobrecarga de armazenamento.

### Princípio Fundamental: Servidor vs. Catálogo
- **Servidor (`servers/{serverId}`):** Representa a entidade técnica de rede e infraestrutura de hospedagem (endereço canônico normalizado, protocolo, porta e caminho-base).
- **Catálogo (`catalogs/{catalogId}` / `iptv_catalogs/{catalogId}`):** Representa os dados e metadados normalizados de conteúdo disponibilizados para consumo do aplicativo Player (canais ao vivo, filmes VOD, séries, temporadas, episódios e categorias).
- **Fonte IPTV (`iptv_sources/{sourceId}`):** Representa o cadastro individual e legítimo de um usuário/família, contendo suas credenciais isoladas e criptografadas em repouso (`source_secrets`), preferências, favoritos, PIN e histórico de reprodução.

> [!IMPORTANT]
> Um servidor pode fornecer catálogos completamente distintos dependendo das credenciais, pacote contratado ou rota do provedor. A detecção do mesmo servidor **não** implica automaticamente no compartilhamento de catálogo.

---

## 2. REQUISITOS E CRITÉRIOS DE EQUIVALÊNCIA DE CATÁLOGOS

O compartilhamento de catálogo processado só é autorizado quando houver **comprovação técnica e criptográfica de equivalência** após validação individual e independente das credenciais do novo usuário:

1. **Validação de Credenciais:** O backend autentica o novo cadastro diretamente contra o provedor (ex: `player_api.php` para Xtream Codes verificando `auth.user_info.auth == 1` e `status == 'active'`).
2. **Escopo de Acesso Efetivo:** O provedor é consultado utilizando estritamente as credenciais daquele usuário.
3. **Assinatura e Prova de Integridade (`iptv_catalog_proofs`):**
   - Para listas M3U/M3U8: Hash SHA-256 do corpo do manifesto normalizado e da identidade de origem.
   - Para Xtream Codes: Hash da estrutura canônica de categorias, streams ao vivo, filmes VOD e séries com suas temporadas e episódios normalizados.
4. **Reutilização Inteligente:** Se a assinatura corresponder a um catálogo ativo já processado no Cloud Storage, o backend valida o hash de integridade (`integrityHash`), vincula o `sourceId` ao `catalogId` e evita novo download e upload integral.
5. **Falha Segura (Fail-Closed):** Caso haja qualquer divergência de pacotes, canais ausentes ou impossibilidade de confirmar equivalência, o backend processa o catálogo de forma independente, garantindo que nenhum usuário receba menos ou mais conteúdo do que suas credenciais permitem.

---

## 3. REGRA DEFINITIVA DE RETENÇÃO E CONTROLE DE ATIVOS

### Retenção Indefinida
- **CATÁLOGOS E SERVIDORES NUNCA SÃO EXCLUÍDOS POR INATIVIDADE.**
- A regra anterior de exclusão automática após 30 dias foi **definitivamente extinta**.
- Quando o último usuário de um catálogo desvincula ou exclui sua fonte:
  - Remove-se apenas o vínculo individual daquele usuário.
  - O documento do servidor é preservado intacto.
  - O documento do catálogo é preservado intacto.
  - O JSON versionado no Cloud Storage é preservado intacto.
  - A data da última sincronização bem-sucedida é preservada.
  - As sincronizações automáticas periódicas deste catálogo são suspensas (`activeSourceCount == 0`).

### Controle Transacional de Usuários Ativos
- O backend rastreia `activeSourceCount` diretamente no documento do catálogo.
- Subcoleção `sources/{sourceId}` registra cada vínculo familiar ativo com `{sourceId, familyId, validatedAt, active: true}`.
- Reconciliação periódica (`reconcileCatalogActiveSources`) audita a consistência entre o contador numérico e os documentos reais de fontes habilitadas no Firestore.

### Reativação Transacional
Quando um usuário voltar a cadastrar uma fonte associada a um catálogo inativo:
1. Valida as credenciais do novo usuário.
2. Identifica o catálogo correspondente via prova criptográfica.
3. Cria o novo vínculo individual.
4. Incrementa `activeSourceCount`.
5. Reativa as sincronizações automáticas.
6. Preserva o último JSON válido para consumo imediato enquanto a nova sincronização é enfileirada e processada.

---

## 4. FLUXO DE SINCRONIZAÇÃO MANUAL E AUTOMÁTICA

### Sincronização Automática Diária
- **Horário:** **00:00 — Horário de Brasília (`America/Sao_Paulo`)** todos os dias.
- **Configuração:** Cloud Scheduler configurado com timezone explícito `America/Sao_Paulo`.
- **Agrupamento Inteligente:** O scanner diário inspeciona os catálogos existentes, ignora catálogos inativos (`activeSourceCount == 0`), seleciona uma fonte representativa por catálogo ativo e enfileira **apenas um job de sincronização por catálogo compartilhado**, evitando downloads e uploads duplicados.

### Sincronização Manual Individual
- Disparada sob demanda quando o usuário toca em "Sincronizar" nos detalhes da sua IPTV.
- Acompanhamento individual e exclusivo daquela fonte e usuário.
- Se houver um job de catálogo compatível já em execução, a solicitação manual é vinculada a ele, reportando progresso em tempo real e disparando notificação somente para o usuário solicitante.

---

## 5. EXPERIÊNCIA DO CLIENTE (FLUTTER APP)

1. **Barra Global de Progresso:**
   - Posicionada abaixo da Status Bar e acima da AppBar.
   - Altura de 2.5 dp, largura total, estilo Dark Industrial Neumorphism.
   - `IgnorePointer` garante toques transparentes sem bloqueio de navegação.
   - Apresenta progresso indeterminado quando o tamanho for desconhecido (download via streaming) e monotônico em etapas determinísticas.
2. **Bottom Sheet de Conclusão:**
   - Sucesso: título "IPTV sincronizada" e texto "Sua lista IPTV foi atualizada com sucesso."
   - Falha: título "Falha na sincronização" com erro amigável sem exposição de credenciais ou URLs.
   - Deduplicação via `SyncNotificationNotifier`.
3. **Push Notifications:**
   - Integração com FCM e `user_notifications`.
   - Disparado exclusivamente quando o app estiver em segundo plano ou fechado.
   - Toque no push abre diretamente os detalhes da IPTV correspondente (`/iptv/{sourceId}`).
4. **Data da Última Sincronização:**
   - Exibida no Card da listagem e na tela de Detalhes.
   - Formato localizado: "Última sincronização: 18/10/2026 às 00:00" ou "Nunca sincronizada".

---

## 6. SEGURANÇA E PROTEÇÃO DE DADOS

- **Criptografia em Repouso:** Credenciais Xtream e tokens cifrados com AES-256-GCM em `source_secrets`.
- **Proteção contra SSRF:** Resolução DNS prévia e bloqueio de IPs de loopback, redes privadas (RFC 1918) e metadados de nuvem (`169.254.169.254`).
- **Resolução de Streams Segura:** As URLs privadas e tokens de stream nunca são expostas nos catálogos compartilhados; o Player autenticado obtém a URL efêmera via Cloud Function `resolveSourceStream`.
- **Firestore Security Rules:** Escrita proibida para clientes diretos em `servers`, `catalogs`, `iptv_catalogs`, `source_secrets`, `iptv_sources` e `iptv_sync_jobs`.
