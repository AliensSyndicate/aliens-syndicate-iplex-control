# ARQUITETURA DE SINCRONIZAÇÃO IPTV EM BACKGROUND — IPLEX

**Projeto:** `aliens_syndicate_iplex_control`  
**Firebase:** `iplex-2c8fc`  
**Status:** Implementado, validado e coberto por testes automatizados (Node.js backend + Flutter client).

---

## 1. VISÃO GERAL E FLUXO COMPLETO

O iPlex implementa uma arquitetura de sincronização assíncrona, durável e resiliente, delegando todo o download, parsing de catálogos volumosos (M3U, Xtream Codes, M3U8 alternativo e arquivos locais) para workers no backend. O cliente Flutter nunca realiza download nem parsing de grandes listas na thread principal nem consome a memória do dispositivo móvel.

```mermaid
sequenceDiagram
    autonumber
    actor User as Usuário (Flutter App)
    participant Client as Flutter Client (Riverpod)
    participant Backend as Backend (Cloud Functions)
    participant Firestore as Cloud Firestore
    participant Storage as Cloud Storage
    participant FCM as Firebase Cloud Messaging

    User->>Client: Salva ou toca em "Sincronizar"
    Client->>Backend: Chamada Callable (saveSource / syncSource)
    Backend->>Backend: Normaliza URL e gera identityHash do servidor
    Backend->>Firestore: Cria ou reutiliza servers/{serverId}
    Backend->>Firestore: Cria job em iptv_sync_jobs/{jobId} (status: queued)
    Backend->>Firestore: Atualiza iptv_sources/{sourceId} (currentJobId, status: queued)
    Backend-->>Client: Retorno imediato { id: sourceId, jobId: jobId }
    Client->>User: Libera UI imediatamente; exibe GlobalIptvSyncProgress

    Firestore->>Backend: Trigger onDocumentCreated(iptv_sync_jobs/{jobId})
    Backend->>Backend: Valida segurança, SSRF e desencripta credenciais
    Backend->>Firestore: Atualiza job (stage: downloading, progress: null)
    Backend->>Backend: Download controlado e streaming de dados
    Backend->>Firestore: Atualiza job (stage: parsing, progress: 30)
    Backend->>Backend: Processa e normaliza canais, filmes, séries e EPG
    Backend->>Firestore: Atualiza job (stage: uploading_catalog, progress: 80)
    Backend->>Storage: Grava catálogo JSON versionado
    Backend->>Firestore: Atualiza iptv_sources/{sourceId} (catalogId, lastSyncAt, status: ready)
    Backend->>Firestore: Finaliza job (status: completed, stage: completed, progress: 100)
    Backend->>Firestore: Cria evento users/{uid}/sync_notifications/{jobId}
    Backend->>FCM: Dispara push notification para todos os dispositivos do usuário

    alt App em primeiro plano (Foreground)
        Firestore-->>Client: Stream watchPendingNotifications / watchActiveSyncJobs
        Client->>User: Exibe IptvSyncResultSheet (deduplicado) e oculta barra global
    else App em segundo plano ou fechado (Background / Cold Start)
        FCM-->>User: Push Notification no sistema operacional
        User->>Client: Toca na notificação
        Client->>Client: Restaura autenticação e navega para /iptv/{sourceId}
    end
```

---

## 2. IDENTIFICAÇÃO E NORMALIZAÇÃO DE SERVIDORES

Para evitar duplicação de infraestrutura e viabilizar inteligência de conectividade, cada fonte IPTV remota é mapeada para a coleção interna `servers/{serverId}`.

### 2.1 Regras de Normalização Técnica
1. **Esquema:** Apenas `http` ou `https` são permitidos; esquema é normalizado para minúsculas.
2. **Host:** Convertido para minúsculas; proteção contra SSRF e rejeição de loops locais (`127.0.0.1`, `localhost`, `169.254.169.254`, redes privadas RFC1918).
3. **Porta:** Normalizada explicitamente. Se omitida, adota 80 para HTTP e 443 para HTTPS.
4. **Caminho-Base Relevante:**
   - Para **Xtream Codes**, remove sufixos operacionais como `/player_api.php`, `/get.php`, `/xmltv.php`, mantendo o caminho-base real do serviço.
   - Preserva subcaminhos relevantes que diferenciem instâncias de servidores (não utiliza apenas o domínio).
   - Remove query strings e credenciais (`username`, `password`, `token`).
5. **Arquivos Locais (M3U File):** Quando a fonte for importada via arquivo direto sem endpoint remoto, `serverId` é gravado como `null`.
6. **Múltiplos Hosts:** Playlists com múltiplos hosts CDN não assumem servidor único arbitrário; o servidor representa estritamente o endpoint de origem da lista.

### 2.2 Cálculo de Identidade Estável (`identityHash`)
O identificador técnico estável é calculado via HMAC/SHA-256 sobre a URL canônica normalizada:
$$\text{identityHash} = \text{SHA-256}(\text{type} + ":" + \text{canonicalEndpoint})$$
$$\text{serverId} = \text{identityHash.substring}(0, 32)$$

### 2.3 Modelo da Coleção `servers/{serverId}`
```json
{
  "serverId": "4a7f8e3b2c1d...",
  "type": "xtream",
  "canonicalEndpoint": "https://iptv.provider.com:8080/base",
  "identityHash": "4a7f8e3b2c1d...",
  "status": "active",
  "createdAt": "2026-10-18T12:00:00Z",
  "updatedAt": "2026-10-18T12:00:00Z"
}
```
*Observação de Segurança:* A coleção `servers` é de uso estritamente interno do backend. Credenciais ou dados familiares nunca são armazenados aqui. Regras do Firestore bloqueiam qualquer leitura/escrita direta por clientes.

---

## 3. MODELO DE DADOS NO FIRESTORE

### 3.1 Fonte IPTV: `iptv_sources/{sourceId}`
Mantém compatibilidade com `families/{familyId}/sources/{sourceId}` através de escrita atômica dual:
```json
{
  "sourceId": "src-123",
  "familyId": "family-xyz",
  "ownerUid": "user-abc",
  "serverId": "4a7f8e3b2c1d...",
  "name": "Minha Lista IPTV",
  "type": "xtream",
  "status": "ready",
  "catalogId": "src-123-1729252800000",
  "currentJobId": "job-999",
  "lastSyncAt": "Timestamp",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

### 3.2 Jobs de Sincronização: `iptv_sync_jobs/{jobId}`
```json
{
  "jobId": "job-999",
  "familyId": "family-xyz",
  "sourceId": "src-123",
  "requestedByUid": "user-abc",
  "status": "completed",
  "stage": "completed",
  "progress": 100,
  "messageCode": "iptv.sync.completed",
  "startedAt": "Timestamp",
  "finishedAt": "Timestamp",
  "errorCode": null,
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp"
}
```

### 3.3 Dispositivos FCM: `users/{uid}/fcm_tokens/{tokenHash}`
Suporte multi-dispositivo por usuário:
```json
{
  "token": "fcm_token_string",
  "platform": "android",
  "updatedAt": "Timestamp"
}
```

### 3.4 Notificações Persistentes: `users/{uid}/sync_notifications/{jobId}`
```json
{
  "jobId": "job-999",
  "sourceId": "src-123",
  "sourceName": "Minha Lista IPTV",
  "status": "completed",
  "errorCode": null,
  "delivered": false,
  "createdAt": "Timestamp",
  "deliveredAt": null
}
```

---

## 4. CICLO DE VIDA DO JOB E CÁLCULO DE PROGRESSO

### 4.1 Estados do Job (`status`)
- `queued`: Enfileirado no Firestore, aguardando execução pelo worker.
- `running`: Worker em execução ativa.
- `completed`: Sucesso terminal; catálogo validado e publicado no Cloud Storage.
- `failed`: Falha terminal; catálogo anterior preservado intacto.
- `cancelled`: Cancelado (por exemplo, na exclusão da fonte).

### 4.2 Etapas Sequenciais (`stage`)
1. `queued` (Progresso: 0%)
2. `identifying_server` (Progresso: 5%)
3. `validating_source` (Progresso: 10%)
4. `downloading` (Progresso: `null` — Indeterminado)
5. `parsing` (Progresso: 30%)
6. `normalizing` (Progresso: 60%)
7. `uploading_catalog` (Progresso: 85%)
8. `publishing_catalog` (Progresso: 95%)
9. `completed` (Progresso: 100%)

### 4.3 Regras de Progresso Real e Monotônico
- Quando o volume total de dados for desconhecido (etapa de download via streaming/chunks desconhecidos), `progress` é explicitamente `null`.
- O Flutter renderiza animação contínua (indeterminada) sem inventar porcentagens fictícias baseadas em timers.
- Quando em etapas com métricas reais, `progress` avança monotonicamente de 0 a 100.
- Na presença de múltiplos jobs simultâneos na família, a barra global calcula a média consistente ou preserva estado indeterminado se algum job for indeterminado.

---

## 5. EXPERIÊNCIA VISUAL NO FLUTTER

### 5.1 Barra Global de Progresso (`GlobalIptvSyncProgress`)
- **Posicionamento:** Imediatamente abaixo da área da Status Bar (`MediaQuery.paddingOf(context).top`) e acima do conteúdo / AppBar.
- **Dimensões:** Altura de 2.5 dp, largura total de 100%.
- **Toques:** Envolvida em `IgnorePointer(child: ...)` para garantir que nenhum botão ou gesto do usuário seja bloqueado.
- **Layout:** Sem saltos de layout; utiliza transições suaves de opacidade (`AnimatedOpacity`, 250ms) e animação neumórfica linear (`LinearGradient` em `AppColors.brandBlue`).
- **Persistência:** Conectada via Riverpod (`globalIptvSyncProgressProvider`). A barra permanece ativa e sem reinício durante a navegação entre abas (Home, IPTV, Dispositivos, Família, Settings).

### 5.2 Bottom Sheet de Resultado (`IptvSyncResultSheet`)
Apresentado automaticamente em conclusão terminal (`completed` ou `failed`):
- **Sucesso:**
  - Título: **IPTV sincronizada**
  - Mensagem: **Sua lista IPTV foi atualizada com sucesso.**
  - Exibe o nome da fonte.
  - Ações: **Ver IPTV** (navega para `/iptv/{sourceId}`) e **Fechar**.
- **Falha:**
  - Título: **Falha na sincronização**
  - Mapeamento amigável de erro baseado em `errorCode` (sem expor credenciais, URLs internas ou senhas):
    - `invalid-credentials` $\rightarrow$ "Credenciais inválidas."
    - `provider-unavailable` $\rightarrow$ "Não foi possível conectar ao servidor."
    - `invalid-catalog` / `suspicious-catalog` $\rightarrow$ "Playlist inválida."
    - `timeout` $\rightarrow$ "Tempo de conexão esgotado."
    - Outros $\rightarrow$ "Erro temporário de processamento."
  - Ações: **Tentar novamente** e **Fechar**.
- **Deduplicação:** Gerenciada por `syncNotificationTrackerProvider`, garantindo que nenhum sheet seja aberto duas vezes para o mesmo `jobId`.

---

## 6. PUSH NOTIFICATIONS E ABERTURA COM APP FECHADO

### 6.1 Integração Firebase Cloud Messaging
1. Ao iniciar a sessão, o aplicativo registra o token FCM do dispositivo em `users/{uid}/fcm_tokens/{tokenHash}`.
2. Na finalização do worker backend, se o job concluir (`completed` ou `failed`), o backend busca todos os tokens daquele usuário e despacha o payload via `messaging().sendEachForMulticast()`.
3. Limpeza automática: tokens inválidos ou expirados retornados pelo FCM são expurgados do Firestore.

### 6.2 Payloads Seguros
O payload contém exclusivamente metadados operacionais:
```json
{
  "jobId": "job-999",
  "sourceId": "src-123",
  "eventType": "sync_completed",
  "status": "completed"
}
```
*Zero exposição:* Nenhuma URL de stream, token ou credencial é enviada no push.

### 6.3 Navegação ao Tocar no Push
- **Cold Start (App Encerrado):** `FirebaseMessaging.instance.getInitialMessage()` recupera o payload, inicializa a autenticação com splash protetor e roteia diretamente para `/iptv/{sourceId}`.
- **Background:** `FirebaseMessaging.onMessageOpenedApp` intercepta o toque e navega para `/iptv/{sourceId}`.
- **Foreground:** Prioriza o `IptvSyncResultSheet`, evitando poluição visual com pushes duplicados.

---

## 7. SEGURANÇA E PROTEÇÃO DE INFRAESTRUTURA

1. **Proteção Contra SSRF:** O worker backend valida todos os IPs resolvidos por DNS antes de abrir conexão HTTP, bloqueando endereços de loopback, RFC1918 e metadados de nuvem (`169.254.169.254`).
2. **Criptografia em Repouso:** Credenciais Xtream são cifradas usando AES-GCM 256-bit antes da gravação no Firestore.
3. **Preservação de Catálogo Anterior:** Durante uma nova sincronização, o catálogo antigo permanece publicado no Cloud Storage. O novo catálogo só é promovido após validação estrutural completa de integridade.
4. **Isolamento Entre Famílias:** As regras de segurança do Firestore garantem que apenas membros autorizados da família administradora possam ler jobs ou disparar mutações.

---

## 8. TESTES AUTOMATIZADOS E COBERTURA

| Componente | Suíte de Testes | Cenários Cobertos | Resultado |
|---|---|---|---|
| **Backend** | `npm run check && npm test` | Normalização de endpoints, identityHash, SSRF, AES-GCM, XMLTV, cotas | 21 testes ✅ |
| **Flutter Domain** | `domain_models_test.dart` | Parse de modelos de jobs, fontes e servidores | 11 testes ✅ |
| **Flutter Four Formats** | `iptv_four_formats_test.dart` | 4 formatos IPTV, validação de URLs, senhas em branco, RBAC | 20 cenários ✅ |
| **Flutter Sync Flow** | `iptv_sync_flow_test.dart` | Barra global, opacidade, animação indeterminada, progresso determístico, deduplicação de sheets, navegação persistente | 10 cenários ✅ |
| **Total do Projeto** | `flutter test` | Toda a aplicação incluindo rotas, autenticação, catálogo e UI | 198 testes ✅ |

---

## 9. PENDÊNCIAS E RECOMENDAÇÕES PARA PRODUÇÃO

1. **Deploy de Cloud Functions:** Realizar `firebase deploy --only functions,firestore:rules,firestore:indexes,storage` no projeto `iplex-2c8fc` quando autorizada a janela de deploy.
2. **APNs no iOS:** Fazer upload do arquivo de chave de autenticação APNs (`.p8`) no console do Firebase para entrega de notificações no iOS físico.
3. **Dispositivos Físicos:** Executar validação de recebimento de push em dispositivos reais Android e iOS em modo suspensão profunda (Doze Mode).
