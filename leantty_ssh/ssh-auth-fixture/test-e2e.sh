#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
fixture_root=$(mktemp -d)
server_pid=''

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf -- "$fixture_root"
}
trap cleanup EXIT INT TERM

random_value() {
  od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
}

password=$(random_value)
account=$(random_value)
token=$(random_value)
second_token=$(random_value)
key_passphrase=$(random_value)
credentials_path="$fixture_root/server-credentials"
client_secrets_path="$fixture_root/client-secrets"

printf 'password=%s\naccount=%s\ntoken=%s\nsecond_token=%s\n' \
  "$password" "$account" "$token" "$second_token" >"$credentials_path"
printf 'key_passphrase=%s\n' "$key_passphrase" >"$client_secrets_path"
chmod 600 "$credentials_path" "$client_secrets_path"
unset password account token second_token

cargo build --locked --offline --manifest-path "$repo_root/leantty_ssh/Cargo.toml" \
  -p leantty-ssh-auth-fixture
fixture_binary="$repo_root/leantty_ssh/target/debug/leantty-ssh-auth-fixture"
"$fixture_binary" 127.0.0.1:0 "$credentials_path" 120 \
  >"$fixture_root/server.out" 2>"$fixture_root/server.err" &
server_pid=$!

ready_line=''
for _ in $(seq 1 200); do
  ready_line=$(grep -m1 '^LEANTTY_SSH_AUTH_FIXTURE_READY ' "$fixture_root/server.out" || true)
  if [[ -n "$ready_line" ]]; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo 'SSH authentication fixture exited before readiness' >&2
    sed -n '1,80p' "$fixture_root/server.err" >&2
    exit 1
  fi
  sleep 0.05
done
if [[ -z "$ready_line" ]]; then
  echo 'SSH authentication fixture did not become ready' >&2
  exit 1
fi
address=${ready_line#*address=}
address=${address%% *}
port=${address##*:}

ssh-keygen -q -t ed25519 -N '' -f "$fixture_root/id_ed25519"
ssh-keygen -q -t rsa -b 3072 -N "$key_passphrase" -f "$fixture_root/id_rsa_encrypted"
unset key_passphrase

askpass_path="$fixture_root/askpass.sh"
cat >"$askpass_path" <<'ASKPASS'
#!/usr/bin/env bash
set -euo pipefail
read_value() {
  sed -n "s/^$1=//p" "$2"
}
case "${1:-}" in
  *passphrase*) read_value key_passphrase "$LEANTTY_CLIENT_SECRETS" ;;
  *Account*) read_value account "$LEANTTY_SERVER_CREDENTIALS" ;;
  *Second*) read_value second_token "$LEANTTY_SERVER_CREDENTIALS" ;;
  *One-time*) read_value token "$LEANTTY_SERVER_CREDENTIALS" ;;
  *[Pp]assword*) read_value password "$LEANTTY_SERVER_CREDENTIALS" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$askpass_path"
export SSH_ASKPASS="$askpass_path"
export SSH_ASKPASS_REQUIRE=force
export DISPLAY=leantty-fixture
export LEANTTY_SERVER_CREDENTIALS="$credentials_path"
export LEANTTY_CLIENT_SECRETS="$client_secrets_path"

run_case() {
  local name=$1
  local user=$2
  shift 2
  local output
  if ! output=$(setsid -w ssh -F /dev/null \
    -o BatchMode=no \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$fixture_root/known_hosts" \
    -p "$port" "$@" "$user@127.0.0.1" true 2>"$fixture_root/client.err"); then
    echo "SSH fixture case failed: $name" >&2
    sed -n '1,80p' "$fixture_root/client.err" >&2
    tail -n 80 "$fixture_root/server.err" >&2
    exit 1
  fi
  if [[ "$output" != 'LEANTTY_AUTH_FIXTURE_OK' ]]; then
    echo "SSH fixture case returned unexpected output: $name" >&2
    exit 1
  fi
  echo "SSH fixture case passed: $name"
}

run_case password password \
  -o PreferredAuthentications=password -o PubkeyAuthentication=no
run_case publickey-unencrypted publickey \
  -o PreferredAuthentications=publickey -o IdentitiesOnly=yes -i "$fixture_root/id_ed25519"
run_case publickey-encrypted publickey \
  -o PreferredAuthentications=publickey -o IdentitiesOnly=yes -i "$fixture_root/id_rsa_encrypted"
run_case password-keyboard-interactive password-kbdint \
  -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no
run_case publickey-password publickey-password \
  -o PreferredAuthentications=publickey,password -o IdentitiesOnly=yes -i "$fixture_root/id_ed25519"
run_case publickey-keyboard-interactive publickey-kbdint \
  -o PreferredAuthentications=publickey,keyboard-interactive -o IdentitiesOnly=yes -i "$fixture_root/id_ed25519"
run_case keyboard-interactive-multiround kbdint-multiround \
  -o PreferredAuthentications=keyboard-interactive -o PubkeyAuthentication=no
run_case keyboard-interactive-zero-prompt kbdint-zero \
  -o PreferredAuthentications=keyboard-interactive -o PubkeyAuthentication=no

echo 'SSH AUTH FIXTURE E2E SUCCESS'
