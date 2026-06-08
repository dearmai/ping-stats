#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRUST_LOCAL=false
APP_PATH="$ROOT_DIR/build/PingStats.app"

for arg in "$@"; do
  case "$arg" in
    --trust-local)
      TRUST_LOCAL=true
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      echo "Usage: scripts/sign-self-signed.sh [--trust-local] [path/to/PingStats.app]" >&2
      exit 1
      ;;
    *)
      APP_PATH="$arg"
      ;;
  esac
done

IDENTITY_NAME="${PINGSTATS_CODESIGN_IDENTITY:-PingStats Self Signed Code Signing}"
OPENSSL_BIN="${OPENSSL_BIN:-/usr/bin/openssl}"
DIST_DIR="$ROOT_DIR/dist"
CERT_PATH="$DIST_DIR/PingStatsSelfSigned.cer"
ZIP_PATH="$DIST_DIR/PingStats.zip"
P12_PASSWORD="${PINGSTATS_P12_PASSWORD:-pingstats-local-signing}"

if [[ -z "$OPENSSL_BIN" || ! -x "$OPENSSL_BIN" ]]; then
  echo "openssl was not found. Set OPENSSL_BIN=/path/to/openssl and retry." >&2
  exit 1
fi

cd "$ROOT_DIR"

if [[ ! -d "$APP_PATH" ]]; then
  scripts/build-app.sh >/dev/null
fi

mkdir -p "$DIST_DIR"

login_keychain() {
  security login-keychain | tr -d ' "'
}

identity_exists() {
  security find-identity -p codesigning -v | grep -Fq "\"$IDENTITY_NAME\""
}

certificate_exists() {
  security find-certificate -c "$IDENTITY_NAME" -p >/dev/null 2>&1
}

export_certificate() {
  security find-certificate -c "$IDENTITY_NAME" -p > "$CERT_PATH"
}

trust_exported_certificate() {
  export_certificate
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$(login_keychain)" \
    "$CERT_PATH"
}

create_identity() {
  local keychain
  local work_dir
  keychain="$(login_keychain)"
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/pingstats-cert.XXXXXX")"
  trap 'rm -rf "$work_dir"' RETURN

  cat > "$work_dir/openssl.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = $IDENTITY_NAME
O = PingStats

[ codesign_ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

  "$OPENSSL_BIN" req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -x509 \
    -days 3650 \
    -config "$work_dir/openssl.cnf" \
    -keyout "$work_dir/codesign.key" \
    -out "$work_dir/codesign.crt"

  if "$OPENSSL_BIN" version | grep -q "OpenSSL 3"; then
    "$OPENSSL_BIN" pkcs12 \
      -export \
      -legacy \
      -passout "pass:$P12_PASSWORD" \
      -name "$IDENTITY_NAME" \
      -inkey "$work_dir/codesign.key" \
      -in "$work_dir/codesign.crt" \
      -out "$work_dir/codesign.p12"
  else
    "$OPENSSL_BIN" pkcs12 \
      -export \
      -passout "pass:$P12_PASSWORD" \
      -name "$IDENTITY_NAME" \
      -inkey "$work_dir/codesign.key" \
      -in "$work_dir/codesign.crt" \
      -out "$work_dir/codesign.p12"
  fi

  security import "$work_dir/codesign.p12" \
    -k "$keychain" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

  if [[ "$TRUST_LOCAL" == "true" ]]; then
    security add-trusted-cert \
      -r trustRoot \
      -p codeSign \
      -k "$keychain" \
      "$work_dir/codesign.crt"
  fi

  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "$keychain" >/dev/null 2>&1 || true
}

if ! identity_exists && certificate_exists && [[ "$TRUST_LOCAL" == "true" ]]; then
  echo "Trusting existing self-signed certificate for code signing: $IDENTITY_NAME"
  trust_exported_certificate
fi

if ! identity_exists && ! certificate_exists; then
  echo "Creating self-signed code signing identity: $IDENTITY_NAME"
  create_identity
fi

if ! identity_exists; then
  if certificate_exists; then
    export_certificate
  fi

  cat >&2 <<EOF
Code signing identity is present but not trusted for code signing: $IDENTITY_NAME

Self-signed certificates are not trusted automatically. To let this script mark
the certificate trusted for code signing on this Mac, run:

  scripts/sign-self-signed.sh --trust-local

That changes your login keychain trust settings. On another Mac, import
dist/PingStatsSelfSigned.cer in Keychain Access and trust it for code signing,
or use Control-click > Open for first launch.
EOF
  exit 1
fi

export_certificate

codesign \
  --force \
  --deep \
  --strict \
  --options runtime \
  --timestamp=none \
  --sign "$IDENTITY_NAME" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

cat <<EOF
Signed app: $APP_PATH
Zip package: $ZIP_PATH
Public certificate: $CERT_PATH

On another Mac, this self-signed certificate is not trusted automatically.
Open the app with Control-click > Open, or import and trust $CERT_PATH in Keychain Access.
EOF
