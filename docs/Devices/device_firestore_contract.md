# iPlex — Contrato Firestore do Módulo Dispositivos

## 1. Coleções do Módulo

O módulo Dispositivos interage com quatro estruturas principais no Firebase Firestore (`iplex-2c8fc`):

1. `devices/{deviceId}` (Coleção global canônica)
2. `device_pairing_sessions/{sessionId}` (Sessões temporárias de pareamento)
3. `link_tokens/{tokenHash}` (Indexação de lookup rápido de tokens/códigos)
4. `families/{familyId}/devices/{deviceId}` (Espelho de subcoleção para consultas restritas à família)

---

## 2. Especificação dos Documentos

### 2.1. Coleção Canônica: `devices/{deviceId}`

Armazena o registro de longo prazo da TV. O `deviceId` é o ID canônico determinístico gerado no formato `dev_<sha256(platform:nativeId).substring(0,32)>`.

```typescript
interface DeviceDocument {
  deviceId: string;                     // ID canônico iPlex (ex: 'dev_e3b0c44298fc1c149afbf4c8996fb924')
  familyId: string;                     // ID da família à qual o dispositivo está vinculado
  displayName: string;                  // Nome amigável configurado pelo usuário (ex: 'TV Sala de Estar')
  platform: 'android_tv' | 'tizen' | 'webos'; // Plataforma do Player
  manufacturer: string;                 // Fabricante detectado (ex: 'Samsung', 'LG', 'Sony')
  model: string;                        // Modelo detectado (ex: 'QN55Q60A', 'OLED55C1')
  
  // Metadados de Identidade Nativa (sanitizados e mascarados)
  nativeIdentityFingerprint: string;    // SHA-256 do identificador nativo (nunca o ID bruto)
  identitySource: string;               // Ex: 'Settings.Secure.ANDROID_ID', 'bada.getDuid', 'webos.deviceInfo'
  identityScope: 'app' | 'vendor' | 'global';
  identityStability: 'stable' | 'installation_bound' | 'ephemeral';
  
  // Status e Presença
  status: 'linked' | 'unlinked' | 'pairing';
  onlineUntil?: FirebaseFirestore.Timestamp; // Presença aproximada calculada por heartbeat (TTL curto)
  lastSeenAt?: FirebaseFirestore.Timestamp;  // Último registro de atividade conhecido
  sessionId?: string;                        // ID da sessão ativa atual na TV (se online)
  
  // Auditoria
  linkedAt: FirebaseFirestore.Timestamp;     // Data/hora da vinculação inicial
  linkedByUid: string;                       // UID do usuário Gestor que confirmou a vinculação
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}
```

### 2.2. Sessões Temporárias: `device_pairing_sessions/{sessionId}`

Gerenciada exclusivamente pelas Cloud Functions com TTL estrito de 5 minutos.

```typescript
interface DevicePairingSessionDocument {
  pairingSessionId: string;             // ID único da sessão
  deviceId: string;                     // ID canônico da TV que gerou a sessão
  tokenHash: string;                    // SHA-256 do token do QR Code
  pairingCodeHash: string;              // SHA-256 do código manual (6 dígitos normalizados)
  
  // Metadados pré-carregados da TV para inspeção no Gestor
  platform: 'android_tv' | 'tizen' | 'webos';
  manufacturer: string;
  model: string;
  displayName: string;
  maskedId: string;                     // ID canônico mascarado para exibição segura
  
  // Ciclo de Vida
  status: 'pending' | 'completed' | 'expired' | 'cancelled';
  createdAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp; // Timestamp estrito (createdAt + 300 segundos)
  
  // Dados de Conclusão (preenchidos após linkDevice)
  claimedByUid?: string;
  claimedFamilyId?: string;
  completedAt?: FirebaseFirestore.Timestamp;
}
```

### 2.3. Índice de Lookup: `link_tokens/{tokenHash}`

Permite resolução em $O(1)$ tanto do token de QR Code quanto do código manual de 6 dígitos sem varreduras lineares na coleção de sessões.

```typescript
interface LinkTokenDocument {
  sessionId: string;
  deviceId: string;
  expiresAt: FirebaseFirestore.Timestamp;
  createdAt: FirebaseFirestore.Timestamp;
}
```

---

## 3. Regras de Segurança (`firestore.rules`)

As regras no Firestore garantem que clientes (Gestor ou TV) não possam adulterar nem forjar sessões ou registros de dispositivos diretamente:

```javascript
// Dispositivos Globais
match /devices/{deviceId} {
  // Leitura permitida para membros autenticados da família dona do dispositivo
  allow read: if isAuthenticated() && (
    resource.data.familyId == currentUserFamilyId() ||
    isAdmin()
  );
  
  // Escrita direta bloqueada aos clientes:
  // Todas as mutações (vincular, desvincular, renomear) devem passar por Cloud Functions
  allow write: if false;
}

// Sessões Temporárias de Pareamento
match /device_pairing_sessions/{sessionId} {
  // A TV ou o Gestor podem ler sua própria sessão (por exemplo para ouvir o status 'completed')
  allow read: if isAuthenticated();
  
  // Bloqueio de criação/modificação por cliente:
  // Apenas a Cloud Function com Firebase Admin SDK pode criar ou marcar como 'completed'
  allow write: if false;
}

match /link_tokens/{tokenHash} {
  allow read, write: if false; // 100% restrito a chamadas de backend
}
```

---

## 4. Estratégia de Presença (Online / Offline)

1. **Separação de Conceitos:**
   - `status`: Vínculo administrativo com a família (`linked` ou `unlinked`).
   - `isOnline`: Estado volátil de conexão em tempo real da TV.
2. **Heartbeat com TTL:**
   - O Player envia um heartbeat a cada 60 segundos enquanto reproduz ou navega.
   - O backend ou o client marca `onlineUntil = now + 120s`.
   - No Gestor, `isOnline` é derivado:
     $$\text{isOnline} = (\text{onlineUntil} \neq \text{null}) \land (\text{onlineUntil} > \text{DateTime.now()})$$
   - Isso evita que TVs em suspensão ou com queda de energia permaneçam com indicador falso de "Online".
