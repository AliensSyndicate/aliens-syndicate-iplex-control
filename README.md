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

- [Fluxo de autenticação, navegação e estados de tela](docs/AUTH_NAVIGATION.md)
- [Identidade visual e componentes](docs/DESIGN_SYSTEM.md)
- [Arquitetura, dados, protocolo e configuração](docs/ARCHITECTURE.md)
- [Auditoria inicial](docs/AUDIT.md)
- [Validação e pendências](docs/STATUS.md)
- [Captura do controle](docs/screenshots/remote.png)
- [Captura de dispositivos](docs/screenshots/devices.png)
