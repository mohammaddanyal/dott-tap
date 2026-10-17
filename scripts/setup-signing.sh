#!/bin/zsh
# One-time setup: creates a self-signed "Dott Tap Local Signing" certificate in its own
# keychain. Builds signed with it keep the same identity, so macOS keeps Dott Tap's
# Accessibility permission across updates (ad-hoc builds lose it every time).
#
# Nothing here is trusted system-wide and nothing goes into the login keychain.
# Secrets stay outside the repo in ~/.config/dott-tap (readable only by you).
set -euo pipefail

NAME="Dott Tap Local Signing"
CONF="$HOME/.config/dott-tap"
KC="$HOME/Library/Keychains/dott-tap-signing.keychain-db"

if [[ -f "$KC" && -f "$CONF/keychain-pass" ]]; then
  echo "Already set up: $KC"
  exit 0
fi

mkdir -p "$CONF"
chmod 700 "$CONF"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=$(openssl rand -hex 24)
P12PASS=$(openssl rand -hex 16)
print -r -- "$PASS" > "$CONF/keychain-pass"
chmod 600 "$CONF/keychain-pass"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/id.p12" -passout "pass:$P12PASS" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"            # never auto-lock
security unlock-keychain -p "$PASS" "$KC"
security import "$WORK/id.p12" -k "$KC" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a password dialog.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null

echo "Created $NAME in $KC"
