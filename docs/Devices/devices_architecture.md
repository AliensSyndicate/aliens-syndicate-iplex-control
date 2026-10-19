# Arquitetura do Módulo Dispositivos — iPlex

## 1. Visão Geral
O módulo **Dispositivos** do ecossistema iPlex é responsável pela vinculação, gerenciamento e controle de televisores conectados (Android TV, Samsung Tizen e LG webOS) a partir do aplicativo móvel iPlex Gestor (Flutter/Dart para iOS e Android).

A arquitetura adota estritamente os princípios de **Clean Architecture** e **Atomic Design**, integrando-se aos serviços em nuvem do Firebase (`iplex-2c8fc`), respeitando as políticas de gratuidade do Gestor, o início do período de teste de 7 dias na primeira vinculação, o isolamento multi-tenant de famílias e o limite de até 3 reproduções simultâneas.

---

## 2. Estrutura de Diretórios (Clean Architecture)

```text
lib/features/devices/
├── data/
│   ├── models/
│   └── repositories/
│       └── device_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── device_entity.dart
│   │   └── pairing_session_entity.dart
│   └── repositories/
│       └── device_repository.dart
└── presentation/
    ├── controllers/
    │   └── device_controller.dart
    ├── pages/
    │   ├── device_list_page.dart
    │   ├── device_add_page.dart
    │   ├── device_qr_scanner_page.dart
    │   ├── device_manual_code_page.dart
    │   ├── device_confirm_pairing_page.dart
    │   ├── device_pairing_success_page.dart
    │   └── device_detail_page.dart
    └── widgets/
        ├── device_card.dart
        └── device_unlink_modal.dart
```

---

## 3. Camadas e Responsabilidades

### 3.1. Domain
- **`DeviceEntity`**: Entidade pura de negócio com identidade canônica, status, plataforma, metadados de hardware (fabricante/modelo), impressão digital de identidade (`nativeIdentityFingerprint`), timestamps de vinculação e método de conectividade em tempo real `isOnline(now)`.
- **`PairingSessionEntity`**: Entidade que representa os dados de uma TV detectada em sessão de pareamento ativa antes da confirmação de vinculação.
- **`DeviceRepository`**: Contrato abstrato que define as operações do ciclo de vida:
  - `watchDevices(familyId)`
  - `watchDevice(familyId, deviceId)`
  - `inspectPairingSession({token, code})`
  - `linkDevice({token, code, name})`
  - `renameDevice(deviceId, newName)`
  - `unlinkDevice(deviceId)`

### 3.2. Data
- **`DeviceRepositoryImpl`**: Implementa o contrato consumindo o `ManagerRepository` (Cloud Functions e Firestore). Mapeia documentos `devices/{deviceId}` e coleções da família para entidades puras.

### 3.3. Presentation
- **`device_controller.dart`**: Provedores Riverpod (`deviceRepositoryProvider`, `familyDevicesStreamProvider`, `deviceDetailStreamProvider`, `devicePairingProvider`).
- **Páginas**:
  1. `DeviceListPage`: Listagem principal sob `FamilyScope`, exibindo `DeviceCard`, badge de status online/offline, carregamento via skeleton (`AppLoadingSkeleton`) e estado vazio.
  2. `DeviceAddPage`: Entrada no fluxo com instruções passo a passo (1 a 4) e escolhas de leitura de QR Code ou digitação manual.
  3. `DeviceQrScannerPage`: Scanner de câmera em tempo real (`MobileScanner`) com viewfinder neumórfico, tratamento de permissão e rotação de câmera.
  4. `DeviceManualCodePage`: Entrada acessível e resiliente de código numérico de 6 dígitos formatado.
  5. `DeviceConfirmPairingPage`: Exibição de dados inspecionados da TV (nome, plataforma, fabricante, modelo, ID mascarado `dev_••••xxxx`) com confirmação explícita obrigatória antes do vínculo. Bloqueia TV pertencente a outra família.
  6. `DevicePairingSuccessPage`: Feedback neumórfico de sucesso, nome da TV vinculada e redirecionamento para detalhes ou listagem.
  7. `DeviceDetailPage`: Detalhes técnicos, status de conexão em tempo real, atalho para controle remoto e ação de desvinculação com modal.

---

## 4. Integração com o TV Player
O TV Player (React/TypeScript) interage com o backend via Cloud Functions e Firestore:
1. Ao iniciar não vinculado, o Player obtém sua identidade nativa via `DeviceIdentityProvider`.
2. O Player solicita uma sessão de pareamento temporária chamando `beginDevicePair`.
3. O Player exibe na tela o QR Code (`iplex://pair?token=...`) e o código manual de 6 dígitos formatado (`XXX-XXX`).
4. Quando o Gestor vincula a TV, a sessão transita para `claimed: true`. O Player finaliza o pareamento via `finishDevicePair` e recebe um Firebase Custom Token com claims de `deviceId` e `familyId`.
