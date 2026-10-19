# MODELAGEM DE DADOS DO ECOSSISTEMA FIRESTORE — IPLEX

**Projeto Firebase:** `iplex-2c8fc`  
**Aplicativos Integrados:**  
- **Gestor (Mobile & Web):** Flutter  
- **TV Player (Smart TVs):** React / TypeScript (Android TV, Tizen, webOS)

---

## 1. Princípio Arquitetural e Visão Geral

A arquitetura do Firestore no ecossistema iPlex foi padronizada em **coleções de primeiro nível** (root collections) independentes. Cada documento possui identificador estável próprio e relaciona-se aos demais principalmente através de **`familyId`** (e subsidiariamente por `profileId`, `deviceId` e `sourceId`).

### Diretrizes Centrais
1. **Identificador Canônico:** `familyId` é a chave mestra de isolamento de dados de uma família.
2. **Administração:** `families/{familyId}` referencia `adminUid` (UID do Firebase Authentication do administrador). O vínculo de entidades com a família é sempre `familyId`, nunca `adminUid`.
3. **Auditoria Transparente:** Entidades mutáveis contêm `createdByUid` e `updatedByUid`.
4. **Isolamento e Segurança de Segredos:** O Firestore acessível pelo cliente **nunca** armazena credenciais em texto claro (senhas, URLs com credenciais embutidas, tokens ou PINs). Segredos são criptografados com AES-256-GCM em `source_secrets` ou gerenciados estritamente pelo Cloud Functions / Secret Manager.
5. **Separação de Identidades:** Usuários autenticados (`users`) são distintos de identidades de reprodução (`profiles`).
6. **Desacoplamento de Catálogo Extenso:** Grandes volumes de metadados de catálogo residem no Cloud Storage como JSONs versionados (`storagePath`), mantendo o Firestore enxuto apenas com metadados e ponteiros.
7. **Regra de Negócio de Reprodução:** O Gestor (Flutter) é 100% gratuito. Apenas o TV Player requer avaliação válida (trial de 7 dias) ou assinatura ativa.

---

## 2. Mapa das Coleções de Primeiro Nível

```text
/users/{uid}
/families/{familyId}
/family_members/{membershipId}
/profiles/{profileId}
/devices/{deviceId}
/iptv_sources/{sourceId}
/iptv_sync_jobs/{jobId}
/catalogs/{catalogId}
/subscriptions/{subscriptionId}
/playback_sessions/{sessionId}
/profile_favorites/{favoriteId}
/profile_progress/{progressId}
```

Coleções internas protegidas (sem leitura/escrita direta por clientes):
```text
/source_secrets/{sourceId}
/link_tokens/{tokenHash}
/deletion_jobs/{uid}
/iptv_cleanup/{cleanupId}
/iptv_requests/{requestHash}
```

---

## 3. Especificação Detalhada das Coleções

### 3.1 `users/{uid}`
Armazena os dados cadastrais do usuário autenticado no Firebase Authentication.
- **ID do Documento:** UID do Firebase Auth (`request.auth.uid`).
- **Permissões:** Leitura e atualização pelo próprio usuário autenticado.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `uid` | `string` | UID do Firebase Authentication |
| `displayName` | `string` | Nome de exibição do usuário |
| `email` | `string` | E-mail da conta |
| `photoUrl` | `string?` | URL da foto do perfil (opcional) |
| `primaryFamilyId`| `string?` | ID da família principal do usuário |
| `locale` | `string` | Idioma de preferência (`pt_BR`, `en`, `es`, `system`) |
| `status` | `string` | Situação da conta (`active`, `suspended`, `deleted`) |
| `createdAt` | `Timestamp`| Data/hora de criação |
| `updatedAt` | `Timestamp`| Data/hora da última atualização |

---

### 3.2 `families/{familyId}`
Representa a conta familiar central.
- **ID do Documento:** UUID v4 ou ID alfanumérico gerado pelo backend.
- **Permissões:** Leitura por qualquer membro ativo da família; escrita restrita a Cloud Functions transacionais.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `adminUid` | `string` | UID do Firebase Auth do administrador da família |
| `name` | `string` | Nome da família (ex: "Família Santos") |
| `status` | `string` | `active`, `suspended`, `deleting` |
| `maxMembers` | `number` | Limite máximo de membros permitidos (padrão: `5`) |
| `createdAt` | `Timestamp`| Data/hora de criação |
| `updatedAt` | `Timestamp`| Data/hora da última atualização |

---

### 3.3 `family_members/{membershipId}`
Controla o vínculo entre um usuário e uma família, seu papel e status.
- **ID do Documento:** Determinístico `${familyId}_${userUid}` ou gerado pelo backend.
- **Permissões:** Leitura por membros da mesma família; escrita restrita a Cloud Functions (validação de limite de 5 membros e prevenção de auto-promoção).

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | Referência a `families/{familyId}` |
| `userUid` | `string` | Referência ao UID do usuário |
| `role` | `string` | Papel: `'admin'` ou `'member'` |
| `status` | `string` | Situação: `'active'`, `'invited'`, `'revoked'` |
| `joinedAt` | `Timestamp`| Momento da adesão |

---

### 3.4 `profiles/{profileId}`
Representa uma identidade de reprodução (visualização da TV), desacoplada de contas do Firebase Auth.
- **ID do Documento:** UUID v4.
- **Permissões:** Leitura por membros da família e dispositivos TV da família; escrita via backend.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família à qual o perfil pertence |
| `name` | `string` | Nome do perfil (ex: "Sala", "Kids", "Carlos") |
| `avatarKey` | `string` | Identificador do avatar gráfico (ex: `'avatar-01'`) |
| `status` | `string` | `'active'`, `'archived'` |
| `createdByUid` | `string` | UID de quem criou o perfil |
| `createdAt` | `Timestamp`| Data de criação |
| `updatedAt` | `Timestamp`| Data da última alteração |

---

### 3.5 `devices/{deviceId}`
Representa uma Smart TV ou dispositivo reprodutor pareado.
- **ID do Documento:** ID seguro gerado durante o pareamento via link token.
- **Permissões:** Leitura por membros da família e pelo próprio dispositivo autenticado com custom token (`tv_{deviceId}`). Escrita controlada via backend.
- **Nota:** MAC address **nunca** é utilizado como chave de segurança.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família proprietária |
| `displayName` | `string` | Nome do aparelho (ex: "Samsung 65 QLED Sala") |
| `platform` | `string` | Plataforma: `'android_tv'`, `'tizen'`, `'webos'` |
| `status` | `string` | Situação: `'linked'`, `'unlinked'`, `'revoked'` |
| `lastSeenAt` | `Timestamp`| Último contato ou heartbeat recebido |
| `linkedAt` | `Timestamp`| Momento do vínculo com a família |
| `linkedByUid` | `string` | UID do usuário que autorizou o pareamento |

---

### 3.6 `iptv_sources/{sourceId}`
Cadastro de listas e provedores IPTV. Suporta os quatro formatos padronizados sem expor credenciais em texto claro.
- **ID do Documento:** ID único da fonte.
- **Formatos Suportados (`type`):**
  - `url`: Lista M3U via URL remota HTTPS.
  - `file`: Arquivo de lista M3U/M3U8 enviado pelo usuário.
  - `xtream`: Conexão com API Xtream Codes (host/porta/usuário/senha cifrados).
  - `m3u8_alternative`: Variação M3U8 para fluxos alternativos.
- **Permissões:** Leitura por membros da família; escrita restrita ao backend callable.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família proprietária |
| `name` | `string` | Nome descritivo da lista |
| `type` | `string` | `'url'`, `'file'`, `'xtream'`, `'m3u8_alternative'` |
| `status` | `string` | `'ready'`, `'queued'`, `'syncing'`, `'error'` |
| `catalogId` | `string?` | Referência ao catálogo gerado em `catalogs/{catalogId}` |
| `credentialsRef`| `string?`| Referência interna para `source_secrets/{sourceId}` |
| `epgEnabled` | `boolean` | Se o EPG está ativo |
| `pinProtected` | `boolean` | Se o acesso requer desbloqueio por PIN |
| `contentCount` | `number` | Quantidade de itens/canais sincronizados |
| `createdByUid` | `string` | UID do criador |
| `updatedByUid` | `string` | UID de quem atualizou |
| `createdAt` | `Timestamp`| Data de cadastro |
| `updatedAt` | `Timestamp`| Data de modificação |
| `lastSyncAt` | `Timestamp?`| Momento da última sincronização com sucesso |
| `errorCode` | `string?` | Código de erro caso `status == 'error'` |

---

### 3.7 `iptv_sync_jobs/{jobId}`
Rastreamento e idempotência dos jobs assíncronos de sincronização de catálogo IPTV.
- **ID do Documento:** UUID v4.
- **Permissões:** Leitura por membros da família; escrita estritamente interna do backend.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família |
| `sourceId` | `string` | ID da fonte IPTV sendo sincronizada |
| `status` | `string` | `'pending'`, `'running'`, `'completed'`, `'failed'` |
| `requestedByUid`| `string`| UID de quem solicitou |
| `startedAt` | `Timestamp`| Início do processamento |
| `finishedAt` | `Timestamp?`| Conclusão |
| `errorCode` | `string?` | Detalhes em caso de falha |

---

### 3.8 `catalogs/{catalogId}`
Metadados resumidos de catálogo. Catálogos extensos residem em arquivo JSON versionado no Cloud Storage.
- **ID do Documento:** Hash canônico ou ID único do catálogo.
- **Permissões:** Leitura autorizada pelo backend ou via storage signed URL.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `status` | `string` | `'ready'`, `'processing'`, `'error'` |
| `version` | `number` | Versão incremental do catálogo |
| `storagePath` | `string` | Caminho do JSON no Cloud Storage (ex: `catalogs/cat-1/v12.json`) |
| `contentCount`| `number` | Número total de canais, filmes e séries |
| `createdAt` | `Timestamp`| Data de criação da versão |
| `updatedAt` | `Timestamp`| Data de atualização |

---

### 3.9 `subscriptions/{subscriptionId}`
Direito de reprodução familiar e controle de cobrança.
- **ID do Documento:** `${familyId}` ou UUID gerado pela integração com Stripe/gateway.
- **Regras de Negócio:**
  - O Gestor permanece livre independentemente de assinatura.
  - O direito de reprodução no TV Player exige avaliação (`trialing`) ou plano pago ativo.
  - Avaliação gratuita de 7 dias é ativada de forma atômica no primeiro vínculo de TV.
  - Modificações de plano e status são autorizadas apenas por webhooks e Cloud Functions confiáveis.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família |
| `status` | `string` | `'not_started'`, `'trialing'`, `'active'`, `'cancelled'`, `'expired'` |
| `plan` | `string` | Identificador do plano (ex: `'monthly'`, `'annual'`) |
| `trialStartedAt`| `Timestamp?`| Início da avaliação de 7 dias |
| `trialEndsAt` | `Timestamp?`| Fim da avaliação de 7 dias |
| `currentPeriodEndsAt`| `Timestamp?`| Vencimento do período pago |
| `updatedAt` | `Timestamp`| Data de atualização |

---

### 3.10 `playback_sessions/{sessionId}`
Controle concorrente de reprodução e leases de TV em tempo real.
- **ID do Documento:** UUID v4 gerado no backend ao iniciar reprodução.
- **Regras Atômicas:**
  - Máximo de **3 TVs reproduzindo simultaneamente** por família (`MAX_SESSIONS = 3`).
  - Máximo de **1 dispositivo ativo por perfil** (evita colisões de perfil).
  - Leases possuem expiração de 90 segundos (`leaseExpiresAt`).
  - A TV envia heartbeats para renovar a validade.
  - Sessões abandonadas expiram automaticamente sem bloquear novos acessos.

| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família |
| `profileId` | `string` | ID do perfil em reprodução |
| `deviceId` | `string` | ID do dispositivo TV |
| `status` | `string` | `'active'`, `'released'`, `'expired'` |
| `startedAt` | `Timestamp`| Momento de início |
| `lastHeartbeatAt`| `Timestamp`| Momento do último sinal de vida |
| `leaseExpiresAt`| `Timestamp`| Prazo final do lease atual |

---

### 3.11 `profile_favorites/{favoriteId}` & `profile_progress/{progressId}`
Favoritos e histórico de progresso atrelados a cada perfil de visualização.
- **IDs Determinísticos:**
  - Favorito: `${profileId}_${contentId}`
  - Progresso: `${profileId}_${contentId}`
- **Preservação de Histórico:** Conteúdos indisponíveis no catálogo atual são preservados para integridade histórica.

#### `profile_favorites/{favoriteId}`
| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família |
| `profileId` | `string` | ID do perfil |
| `contentId` | `string` | Identificador do canal, filme ou episódio |
| `catalogId` | `string?` | Identificador do catálogo de origem |
| `title` | `string` | Nome de exibição do conteúdo |
| `createdAt` | `Timestamp`| Data da inclusão |
| `updatedAt` | `Timestamp`| Data da atualização |

#### `profile_progress/{progressId}`
| Campo | Tipo | Descrição |
| :--- | :--- | :--- |
| `familyId` | `string` | ID da família |
| `profileId` | `string` | ID do perfil |
| `contentId` | `string` | Identificador do vídeo |
| `catalogId` | `string?` | Identificador do catálogo |
| `position` | `number` | Posição atual de reprodução em milissegundos |
| `duration` | `number` | Duração total do vídeo em milissegundos |
| `updatedAt` | `Timestamp`| Data da última atualização |

---

## 4. Consultas e Índices Compostos

Para garantir consultas performáticas sem leituras completas (full scan), foram configurados os seguintes índices compostos em `firestore.indexes.json`:

1. **`iptv_sources`**:
   - `familyId` (ASC), `status` (ASC)
   - `familyId` (ASC), `updatedAt` (DESC)
2. **`devices`**:
   - `familyId` (ASC), `status` (ASC)
3. **`profiles`**:
   - `familyId` (ASC), `createdAt` (ASC)
4. **`family_members`**:
   - `familyId` (ASC), `status` (ASC)
5. **`iptv_sync_jobs`**:
   - `sourceId` (ASC), `startedAt` (DESC)
   - `familyId` (ASC), `startedAt` (DESC)
6. **`playback_sessions`**:
   - `familyId` (ASC), `status` (ASC), `leaseExpiresAt` (ASC)
7. **`profile_favorites`**:
   - `profileId` (ASC), `updatedAt` (DESC)
8. **`profile_progress`**:
   - `profileId` (ASC), `updatedAt` (DESC)

---

## 5. Implementação no Código Dart (Flutter)

A camada de domínio em Flutter segue rigorosamente Clean Architecture, immutability, `snake_case` nos arquivos e `PascalCase` nas classes:

- [user_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/user_model.dart) (`UserModel`)
- [family_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/family_model.dart) (`FamilyModel`)
- [family_member_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/family_member_model.dart) (`FamilyMemberModel`)
- [profile_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/profile_model.dart) (`ProfileModel`)
- [device_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/device_model.dart) (`DeviceModel`)
- [iptv_source_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/iptv_source_model.dart) (`IptvSourceModel`)
- [iptv_sync_job_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/iptv_sync_job_model.dart) (`IptvSyncJobModel`)
- [catalog_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/catalog_model.dart) (`CatalogModel`)
- [subscription_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/subscription_model.dart) (`SubscriptionModel`)
- [playback_session_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/playback_session_model.dart) (`PlaybackSessionModel`)
- [profile_favorite_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/profile_favorite_model.dart) (`ProfileFavoriteModel`)
- [profile_progress_model.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models/profile_progress_model.dart) (`ProfileProgressModel`)
- [models.dart](file:///Users/charlessantos/Workspace/aliens_syndicate_iplex_control/lib/core/domain/models.dart) (Fachada pública exportando todos os modelos com 100% de retrocompatibilidade com componentes legados).
