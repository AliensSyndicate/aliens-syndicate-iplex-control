#!/usr/bin/env bash
set -e

echo "========================================================"
echo "  iPlex - Credenciais de Depuração Android & App Check"
echo "========================================================"

# 1. SHA-1 e SHA-256 do debug.keystore
DEBUG_KEYSTORE="$HOME/.android/debug.keystore"
if [ -f "$DEBUG_KEYSTORE" ]; then
  echo ""
  echo "🔑 Hashes SHA do Certificado (debug.keystore):"
  echo "   (Cole em: Firebase Console > Configurações do Projeto > Seus Aplicativos > Android)"
  keytool -list -v -keystore "$DEBUG_KEYSTORE" -alias androiddebugkey -storepass android -keypass android 2>/dev/null \
    | grep -E "^\s*(SHA1|SHA256):" | sed 's/^[ \t]*/   /'
else
  echo ""
  echo "⚠️ debug.keystore não encontrado em $DEBUG_KEYSTORE."
fi

# 2. Gerar novo UUID v4 para App Check
echo ""
echo "🆔 Novo Token de Depuração App Check (UUID v4):"
echo "   (Cole em: Firebase Console > App Check > Gerenciar tokens de depuração)"
if command -v uuidgen >/dev/null 2>&1; then
  NEW_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
elif command -v python3 >/dev/null 2>&1; then
  NEW_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
else
  NEW_UUID=$(node -e 'console.log(require("crypto").randomUUID())' 2>/dev/null || true)
fi
echo "   $NEW_UUID"

# 3. Detectar token ativo no dispositivo conectado (adb)
ADB_BIN="adb"
if ! command -v adb >/dev/null 2>&1; then
  if [ -f "$HOME/Library/Android/sdk/platform-tools/adb" ]; then
    ADB_BIN="$HOME/Library/Android/sdk/platform-tools/adb"
  fi
fi

if command -v "$ADB_BIN" >/dev/null 2>&1; then
  DEVICE=$("$ADB_BIN" devices | grep -w "device" | head -n 1 | awk '{print $1}')
  if [ -n "$DEVICE" ]; then
    echo ""
    echo "📱 Dispositivo conectado detectado ($DEVICE):"
    CAPTURED_TOKEN=$("$ADB_BIN" logcat -d 2>/dev/null | grep -oE "debug token \([a-f0-9-]{36}\)" | tail -n 1 | sed 's/debug token (//;s/)//')
    if [ -n "$CAPTURED_TOKEN" ]; then
      echo "   Token App Check ativo no logcat:"
      echo "   $CAPTURED_TOKEN"
    else
      echo "   Nenhum token encontrado recentemente no logcat do aparelho."
    fi
  fi
fi

echo ""
echo "========================================================"
