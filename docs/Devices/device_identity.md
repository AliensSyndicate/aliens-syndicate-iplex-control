# Identidade Nativa da TV por Plataforma — iPlex

## 1. Princípio Fundamental
O identificador principal de uma TV no iPlex **nunca é um UUID aleatório gerado a cada execução**, nem o código de pareamento temporário, nem o IP da rede local.

A identidade canônica do dispositivo (`deviceId`) é **calculada deterministicamente no backend** a partir da melhor identidade nativa oficial disponibilizada pela plataforma operacional da TV.

```text
deviceId = "dev_" + sha256("iplex:platform:" + platform + ":native:" + nativeDeviceId).substring(0, 32)
```

Essa abordagem garante:
1. **Determinismo**: Uma mesma TV física sempre produz o mesmo `deviceId`.
2. **Resistência a Colisão**: Identificadores nativos idênticos entre plataformas distintas (ex.: mesmo hash acidental entre Android TV e LG) produzem `deviceId` totalmente distintos devido ao prefixo de escopo da plataforma.
3. **Não-Vazamento de Hardware**: O hardware ID bruto nunca é exposto publicamente no cliente nem utilizado como token de autorização.

---

## 2. Auditoria Técnica por Plataforma

### 2.1. Android TV
- **API Oficial:** `Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)`.
- **Escopo e Limitações:** No Android 8.0+ (API 26+), o `ANDROID_ID` possui escopo por chave de assinatura do aplicativo e por perfil de usuário. Ele permanece estável entre atualizações e reinstalações do aplicativo assinado pela mesma chave de desenvolvedor. Ele só é redefinido em caso de restauração para os padrões de fábrica (Factory Reset).
- **Segurança Adicional:** Integração opcional com Widevine Device Unique ID (`MediaDrm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)`).
- **Classificação:**
  - `identitySource`: `android_settings_secure_android_id`
  - `identityScope`: `app_scoped`
  - `identityStability`: `os_reinstall_stable`

### 2.2. Samsung Tizen
- **API Oficial:** `webapis.productinfo.getDuid()` ou `tizen.systeminfo.getCapability('http://tizen.org/system/tizenid')`.
- **Privilégios e Restrições:** A API de DUID exige privilégios de nível de parceiro Samsung (`http://developer.samsung.com/privilege/network.public`). Aplicativos de loja geral de terceiros que não possuem privilégio de parceiro são bloqueados pelo sistema de segurança da Samsung.
- **Estratégia de Fallback Autorizada:** Quando o DUID não está acessível sem privilégios restritos, o TV Player utiliza um identificador persistente de instalação gerado criptograficamente e mantido em IndexedDB/LocalStorage protegido.
- **Classificação:**
  - Quando DUID disponível:
    - `identitySource`: `tizen_duid_api`
    - `identityScope`: `vendor_scoped`
    - `identityStability`: `hardware_stable`
  - Fallback de instalação:
    - `identitySource`: `tizen_app_install_fallback`
    - `identityScope`: `app_scoped`
    - `identityStability`: `installation_persistent`

### 2.3. LG webOS
- **API Oficial:** `webOS.deviceInfo` e serviço Luna (`luna://com.webos.service.sm`).
- **Privilégios e Restrições:** Identificadores físicos de nível de hardware (como serial de fábrica ou MAC address de placa de rede) são terminantemente protegidos pela LG para aplicativos 3rd-party de loja pública. `webOS.deviceInfo` disponibiliza `modelName`, `version` e resolução, mas não identificador físico perpétuo.
- **Estratégia de Fallback Autorizada:** Aplicação web hospedada ou empacotada utiliza UUID persistente armazenado de forma estável no armazenamento local protegido da aplicação.
- **Classificação:**
  - Quando serviço Luna disponível:
    - `identitySource`: `webos_device_id_service`
    - `identityScope`: `vendor_scoped`
    - `identityStability`: `hardware_stable`
  - Fallback de instalação:
    - `identitySource`: `webos_app_install_fallback`
    - `identityScope`: `app_scoped`
    - `identityStability`: `installation_persistent`

---

## 3. Contrato Unificado no Backend

```typescript
export interface DeviceIdentityInfo {
  platform: 'android_tv' | 'tizen' | 'webos';
  nativeDeviceId: string;
  identitySource: IdentitySource;
  identityScope: IdentityScope;
  identityStability: IdentityStability;
  manufacturer: string;
  model: string;
}
```

O backend armazena esses metadados nos documentos de `devices/{deviceId}` e na sessão de pareamento para auditoria, suporte e validação de concorrência.
