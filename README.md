# iPlex

Aplicativo Flutter de administração do ecossistema iPlex para Android e iOS. O Gestor administra família, perfis, TVs, fontes IPTV, catálogo e preferências. O Player da TV é um produto separado.

## Executar

```sh
flutter pub get
flutter run
```

O Firebase configurado é `iplex-2c8fc`. As opções nativas existentes são carregadas por `lib/firebase_options.dart`. É possível fornecer opções por `--dart-define-from-file`; veja [configuração e operação](docs/ARCHITECTURE.md). O aplicativo apresenta erro de configuração quando a inicialização não está disponível. Autenticação Google/Apple e operações de backend precisam dos respectivos serviços configurados.

## Verificar

```sh
dart format lib test
flutter analyze
flutter test
npm --prefix functions ci
npm --prefix functions run check
firebase emulators:exec --project demo-iplex --only firestore,auth 'npm --prefix functions run test:rules && npm --prefix functions run test:integration'
```

Use o projeto `demo-iplex` nos testes de emuladores. As suítes de backend exigem variáveis de emulador; não são testes de produção.

## Publicar Regras no Firebase

Comandos da CLI do Firebase para publicar as regras de segurança e índices:

```sh
# Atualizar apenas as regras de segurança do Firestore
firebase deploy --only firestore:rules

# Atualizar regras e índices do Firestore
firebase deploy --only firestore

# Atualizar regras de segurança do Storage
firebase deploy --only storage

# Especificando explicitamente o projeto (se necessário)
firebase deploy --only firestore:rules --project iplex-2c8fc
```

## Credenciais de Depuração Android & App Check (SHA e UUID)

Para obter os hashes SHA do certificado ou gerar/obter o UUID v4 para o Firebase App Check:

### Comando Rápido (Tudo em um)

```sh
./tool/debug_tokens.sh
```

Esse script exibe:
- **SHA-1 e SHA-256** do `~/.android/debug.keystore` (para colar nas *Configurações do Projeto > Seus Aplicativos > Android*).
- **Novo UUID v4** gerado para registrar no *Firebase Console > App Check > Gerenciar tokens de depuração*.
- **Token ativo do aparelho** capturado direto do logcat caso um dispositivo Android esteja conectado via USB/adb.

### Comandos Manuais

```sh
# 1. Obter SHA-1 e SHA-256 da keystore de debug:
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep -E "^\s*(SHA1|SHA256):"

# 2. Gerar um novo UUID v4 para o App Check:
uuidgen | tr '[:upper:]' '[:lower:]'

# 3. Capturar o token do App Check emitido pelo aparelho conectado:
~/Library/Android/sdk/platform-tools/adb logcat -d | grep -oE "debug token \([a-f0-9-]{36}\)" | tail -n 1
```


- [Fluxo de autenticação, navegação e estados de tela](docs/AUTH_NAVIGATION.md)
- [Identidade visual e componentes](docs/DESIGN_SYSTEM.md)
- [Arquitetura, dados, protocolo e configuração](docs/ARCHITECTURE.md)
- [Auditoria inicial](docs/AUDIT.md)
- [Validação e pendências](docs/STATUS.md)
- [Captura do controle](docs/screenshots/remote.png)
- [Captura de dispositivos](docs/screenshots/devices.png)
