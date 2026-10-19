quero que # MODELAGEM FIRESTORE DEFINITIVA — IPLEX IPTV

**Projeto:** iPlex  
**Firebase Project:** `iplex-2c8fc`  
**Escopo:** Coleções de gerenciamento IPTV, compartilhamento de catálogos e ciclo de vida de jobs.

---

## 1. VISÃO GERAL DAS COLEÇÕES

```text
users/{uid}
families/{familyId}
family_members/{membershipId}
devices/{deviceId}
profiles/{profileId}

servers/{serverId}
iptv_sources/{sourceId}
iptv_catalogs/{catalogId}   (com espelho equivalente catalogs/{catalogId})
iptv_sync_jobs/{jobId}

user_notifications/{notificationId}
device_push_tokens/{tokenId}
```

---

## 2. DETALHAMENTO DAS ENTIDADES E ESQUEMAS

### 2.1 Servidores IPTV: `servers/{serverId}`
Representa a infraestrutura técnica e de rede do provedor.
- **Identificador (`serverId`):** Determinístico gerado a partir do hash do endpoint canônico normalizado (`srv_${identityHash.slice(0, 32)}`).
- **Segurança:** Acesso estritamente restrito ao backend (`allow read, write: if false;`).

```json
{
  "serverId": "srv_4a7f8e3b2c1d98e723a1b0c9d8e7f6a5",
  "type": "xtream",
  "canonicalEndpoint": "https://iptv.provider.com:8443/base",
  "identityHash": "4a7f8e3b2c1d98e723a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9",
  "status": "active",
  "createdAt": 1729252800000,
  "updatedAt": 1729252800000
}
```

### 2.2 Fontes IPTV: `iptv_sources/{sourceId}`
Cadastro individual da fonte IPTV de cada usuário/família. Mantém dualidade com `families/{familyId}/sources/{sourceId}` para máxima compatibilidade.

```json
{
  "sourceId": "src-abc123xyz",
  "familyId": "family-santos-1",
  "ownerUid": "firebase-auth-uid-1",
  "createdByUid": "firebase-auth-uid-1",
  "serverId": "srv_4a7f8e3b2c1d98e723a1b0c9d8e7f6a5",
  "catalogId": "cat_9f8e7d6c5b4a3a2b1c0d9e8f7a6b5c4d",
  "name": "Canais da Família",
  "type": "xtream",
  "format": "xtream",
  "host": "iptv.provider.com",
  "status": "ready",
  "authorizationStatus": "valid",
  "authorizationRevision": 1,
  "revision": 1,
  "enabled": true,
  "isProtected": false,
  "pinProtected": false,
  "hasEpg": true,
  "epgEnabled": true,
  "contentCount": 3500,
  "currentJobId": null,
  "errorCode": null,
  "lastSuccessfulSyncAt": 1729252800000,
  "lastSyncAt": 1729252800000,
  "lastAttemptAt": 1729252800000,
  "createdAt": 1729200000000,
  "updatedAt": 1729252800000
}
```

### 2.3 Catálogos Compartilhados: `iptv_catalogs/{catalogId}` e `catalogs/{catalogId}`
Representa os metadados do catálogo normalizado armazenado no Cloud Storage. Não contém senhas, tokens ou dados pessoais de usuários.

```json
{
  "catalogId": "cat_9f8e7d6c5b4a3a2b1c0d9e8f7a6b5c4d",
  "serverId": "srv_4a7f8e3b2c1d98e723a1b0c9d8e7f6a5",
  "schemaVersion": 1,
  "version": "cat_9f8e7d6c5b4a3a2b1c0d9e8f7a6b5c4d",
  "storagePath": "catalogs/cat_9f8e7d6c5b4a3a2b1c0d9e8f7a6b5c4d.json",
  "status": "ready",
  "contentCount": 3500,
  "activeSourceCount": 4,
  "integrityHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "lastSuccessfulSyncAt": 1729252800000,
  "lastAttemptAt": 1729252800000,
  "createdAt": 1729200000000,
  "updatedAt": 1729252800000
}
```

#### Subcoleção de Vínculos de Fontes: `iptv_catalogs/{catalogId}/sources/{sourceId}`
```json
{
  "sourceId": "src-abc123xyz",
  "familyId": "family-santos-1",
  "sourceRevision": 1,
  "validatedAt": 1729252800000,
  "active": true
}
```

### 2.4 Jobs de Sincronização: `iptv_sync_jobs/{jobId}`
Controla as etapas de execução duráveis e idempotentes dos workers de ingestão.

```json
{
  "jobId": "job-d4e5f6-789a",
  "familyId": "family-santos-1",
  "sourceId": "src-abc123xyz",
  "catalogId": "cat_9f8e7d6c5b4a3a2b1c0d9e8f7a6b5c4d",
  "requestedByUid": "firebase-auth-uid-1",
  "trigger": "manual",
  "status": "completed",
  "stage": "completed",
  "progress": 100,
  "messageCode": "iptv.sync.completed",
  "attempts": 1,
  "errorCode": null,
  "reusedCatalog": true,
  "createdAt": 1729252780000,
  "startedAt": 1729252782000,
  "finishedAt": 1729252800000,
  "updatedAt": 1729252800000
}
```

### 2.5 Notificações de Usuário: `users/{uid}/sync_notifications/{jobId}` e `user_notifications/{notificationId}`
Registra o evento de conclusão para notificação in-app (Bottom Sheet) e push (FCM).

```json
{
  "jobId": "job-d4e5f6-789a",
  "sourceId": "src-abc123xyz",
  "sourceName": "Canais da Família",
  "familyId": "family-santos-1",
  "recipientUid": "firebase-auth-uid-1",
  "status": "completed",
  "errorCode": null,
  "delivered": false,
  "pushStatus": "sent",
  "createdAt": 1729252800000
}
```

### 2.6 Tokens Push de Dispositivos: `device_push_tokens/{tokenHash}`
Multi-dispositivo por usuário, sem acesso direto por clientes.

```json
{
  "ownerUid": "firebase-auth-uid-1",
  "token": "fcm_device_registration_token",
  "platform": "flutter",
  "updatedAt": 1729252000000
}
```

---

## 3. REGRAS DE RETENÇÃO E POLÍTICA DE EXCLUSÃO

1. **Exclusão de Fonte:** Quando `deleteIptvSource` é executada:
   - Exclui `families/{fid}/sources/{sid}` e `iptv_sources/{sid}`.
   - Exclui `source_secrets/{fid}_{sid}`.
   - Exclui o vínculo na subcoleção `catalogs/{catalogId}/sources/{sid}`.
   - Decrementa `activeSourceCount` no catálogo.
   - Cancela jobs pendentes daquela fonte.
   - **PRESERVA:** `servers/{serverId}`, `catalogs/{catalogId}`, `iptv_catalogs/{catalogId}` e o arquivo JSON em Cloud Storage.
2. **Catálogos com `activeSourceCount == 0`:**
   - Permanecem armazenados indefinidamente.
   - Não são removidos após 30 dias.
   - São ignorados pela rotina diária de sincronização automática.
   - São reativados imediatamente quando uma nova fonte equivalente é cadastrada.
