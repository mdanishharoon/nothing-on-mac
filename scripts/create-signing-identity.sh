#!/usr/bin/env bash
# Creates a free, self-signed code-signing identity in your login keychain.
#
# macOS remembers permissions (Bluetooth) per code signature. Ad-hoc signatures change on every
# build, so macOS treats each build as a new app and asks again. Signing every build and release
# with this one identity keeps the signature stable, so permission is asked once and survives
# updates. It does NOT replace Apple notarization: downloaders still approve the app once in
# System Settings > Privacy & Security.
#
# Run once. Keep the backup folder it prints: releases signed with a different identity make
# every user grant Bluetooth access again.
set -euo pipefail

name="Nothing on Mac Self-Signed"
backup="${1:-$HOME/nothing-on-mac-signing}"

if security find-certificate -c "$name" >/dev/null 2>&1; then
  echo "\"$name\" already exists in your keychain."
  exit 0
fi

mkdir -p "$backup"
chmod 700 "$backup"
cd "$backup"

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -subj "/CN=$name" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "basicConstraints=critical,CA:false" 2>/dev/null

password="$(openssl rand -hex 16)"
printf '%s\n' "$password" > p12-password.txt
chmod 600 key.pem p12-password.txt

# macOS's importer needs the older PKCS#12 algorithms.
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$name" -out identity.p12 \
  -passout "pass:$password" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# -T lets codesign use the key without a keychain prompt on every build.
security import identity.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P "$password" -T /usr/bin/codesign

echo
echo "Created \"$name\". Backup (keep it safe, never commit it): $backup"
