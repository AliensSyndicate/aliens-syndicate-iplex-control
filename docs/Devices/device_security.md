# iPlex — Modelo de Segurança do Módulo Dispositivos (Device Security)

## 1. Princípios Fundamentais de Segurança

O módulo Dispositivos adota uma abordagem de **Defesa em Profundidade (Defense-in-Depth)** e **Zero-Trust**:

1. **Identificador Nativo $\neq$ Token de Autorização:** O identificador físico/nativo da TV identifica o aparelho para estabilidade cadastral, mas **nunca** é utilizado como segredo ou prova de posse.
2. **Tokens Efêmeros e Descartáveis:** QR Codes e códigos manuais contêm exclusivamente referências a sessões de curta duração e de uso único (Single-Use).
3. **Validação e Transação Exclusiva no Backend:** Nenhuma vinculação ou desvinculação ocorre por manipulação direta no banco de dados pelo app cliente.
4. **Proteção Anti-Sequestro (Anti-Hijacking):** O conhecimento circunstancial de um QR code não permite roubar uma TV já associada a outra família.

---

## 2. Ameaças Identificadas e Contramedidas

### 2.1. Sequestro de TV por Fotografia do QR Code (Shoulder Surfing / QR Theft)
- **Ameaça:** Uma visita ou terceiro fotografa o QR Code exibido na TV da sala e tenta vinculá-la à sua própria conta no Gestor.
- **Contramedida:**
  - Se a TV já estiver vinculada à Família do proprietário, a transação no backend (`linkDevice`) detecta que `currentFamilyId != requestFamilyId` e rejeita a operação com o código `device-already-linked-elsewhere`.
  - O QR Code só fica visível quando o aparelho está no modo inicial desvinculado ou quando o usuário expressamente seleciona "Alterar Vínculo" com autorização prévia.

### 2.2. Ataque de Força Bruta no Código Manual de 6 Dígitos
- **Ameaça:** Um atacante gera códigos manuais aleatórios tentando adivinhar uma sessão de pareamento aberta.
- **Contramedida:**
  - O código manual possui 6 caracteres decimais ($1.000.000$ de combinações).
  - O TTL de cada sessão é restrito a **5 minutos (300 segundos)**.
  - Cada tentativa incorreta incrementa o contador `failedAttempts`. Ao atingir 5 tentativas falhas, a sessão é imediatamente cancelada com `status: 'cancelled'` e o hash de lookup é purgado.
  - Probabilidade de sucesso por força bruta antes da invalidação da sessão:
    $$P \le \frac{5}{1.000.000} = 0.0005\%$$

### 2.3. Ataque de Replay e Reutilização de Token
- **Ameaça:** Reenvio de uma requisição `linkDevice` previamente capturada na rede.
- **Contramedida:**
  - A operação `linkDevice` executa dentro de uma **Firestore Transaction**.
  - A sessão de pareamento é comutada de `pending` para `completed` atomicamente no mesmo commit em que o dispositivo é associado à família.
  - Qualquer chamada subsequente com o mesmo token encontra `status: 'completed'` ou inexistente e é rejeitada com `session-already-consumed`.

### 2.4. Vazamento de Identificadores Sensíveis e Privacidade
- **Ameaça:** Exposição de números de série, endereços MAC ou IMEI em logs ou payloads públicos.
- **Contramedida:**
  - O Gestor e a TV nunca trafegam o ID nativo bruto.
  - O identificador armazenado é o `nativeIdentityFingerprint` (SHA-256 criptográfico).
  - O identificador exibido na interface do usuário é mascarado (`maskedId`: primeiros 6 e últimos 4 caracteres, com máscara no miolo, ex: `dev_48f9••••••••••••3a1c`).

---

## 3. Segurança no Ciclo de Desvinculação (Unlinking & Revocation)

Ao desvincular um dispositivo (`deleteDevice` / `unlinkDevice`):

1. **Exclusão Lógica e Desassociação:**
   - O documento em `devices/{deviceId}` tem seu campo `status` alterado para `unlinked`, e o `familyId` é limpo.
   - O documento em `families/{familyId}/devices/{deviceId}` é excluído.
2. **Revogação de Sessões em Andamento:**
   - Quaisquer sessões ativas de reprodução IPTV vinculadas a esse `deviceId` são encerradas no backend.
3. **Limpeza no Player:**
   - O TV Player, ouvindo as alterações do seu registro via Firestore snapshot, detecta `status: 'unlinked'` ou ausência de vínculo.
   - O Player descarta imediatamente do `localStorage`/`SecureStorage` os tokens de sessão familiar, limpa a memória e retorna à tela de boas-vindas com novo QR code para pareamento.

---

## 4. Regras de Assinatura e Limite de Reprodução

- **Gestor:** 100% gratuito para administração e pareamento de TVs.
- **Período de Teste:** O teste de 7 dias é iniciado de forma automática e atômica na **primeira vinculação bem-sucedida** de uma TV àquela família. Se a família já tiver consumido o teste anteriormente, o contador não é reiniciado.
- **Dispositivos Ilimitados:** A família pode cadastrar quantas TVs desejar.
- **Controle de Concorrência de Stream:** Vincular a TV não concede reprodução irrestrita. O backend valida:
  - Máximo de **3 reproduções simultâneas** por família.
  - Máximo de **1 reprodução por perfil**.
  - Validação contínua do status da assinatura a cada requisição de stream.
