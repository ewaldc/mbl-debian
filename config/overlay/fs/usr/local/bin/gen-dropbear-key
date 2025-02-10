#!/bin/sh +ux
# We set the sh +ux flags so that we error on undefined variables and error on bad commands

help() {
  echo >&2 "$0 [-f] [-p] [-q] [<priv_key_file>] [<key_type>] [<key_comment>]"
  echo >&2
  echo >&2 "-q / --quiet to silent all output (except -p if passed)"
  echo >&2 "-p / --pubkey to output public key after generation"
  echo >&2 "-f / --force to force replacing existing key"
  echo >&2
  echo >&2 "<priv_key_file> can be any valid filename [default: '$HOME/.ssh/id_dropbear']"
  echo >&2 "<key_type> can be 'rsa', 'dss', 'ecdsa' or 'ed25519' [default: 'ed25519']"
  echo >&2 "<key_comment> can be be any valid ascii string [default: '$USER@$(hostname)'"
  echo >&2
}

REPLACE_KEY=""
OUTPUT_PUBKEY=""
QUIET=""
for ARG in "$@"; do
  case "$ARG" in
    '-h'|'-help'|'--help') help; exit 255;;
    '-f'|'-force'|'--force') REPLACE_KEY="Y"; shift;;
    '-p'|'-pubkey'|'--pubkey') OUTPUT_PUBKEY="Y"; shift;;
    '-q'|'-quiet'|'--quiet') QUIET="Y"; shift;;
    '-'*) echo >&2 "ERROR: unknown argument '$ARG'"; echo >&2; help; exit 255;;
  esac
done

# Ensure that dropbearkey is installed
command -v 'dropbearkey' >/dev/null 2>&1 || { echo >&2 "I require dropbearkey but it's not installed.  Aborting."; exit 1; }

# Will accept private key file name as first argument
PRIVATE_KEY_FILE="${1:-"$HOME/.ssh/id_dropbear"}"
PUBLIC_KEY_FILE="${PRIVATE_KEY_FILE}.pub"

# Will accept key type as second argument
KEY_TYPE="${2:-"ed25519"}"

KEY_COMMENT="${3:-"$USER@$(hostname)"}"
KEY_DIR="$(dirname "$PRIVATE_KEY_FILE")"

# Ensure the directory exists
mkdir -p "$KEY_DIR"
# Set permissions for directory
chmod 700 "$KEY_DIR"

[ -f "$PRIVATE_KEY_FILE" -a -z "$REPLACE_KEY" ] && { echo >&2 "ERROR: $PRIVATE_KEY_FILE already exists. Pass -f/--force to override"; exit 1; }
rm -f "$PRIVATE_KEY_FILE"

# Generate an RSA key using dropbear
if [ -z "$QUIET" ]; then
  dropbearkey -t "$KEY_TYPE" -f "$PRIVATE_KEY_FILE" >/dev/null || { echo >&2 "ERROR: failed generating private key"; exit 1; }
  echo >&2 "Key generation complete"
else
  dropbearkey -t "$KEY_TYPE" -f "$PRIVATE_KEY_FILE" 2>/dev/null >/dev/null || { echo >&2 "ERROR: failed generating private key"; exit 1; }
fi
[ -f "$PRIVATE_KEY_FILE" ] || { echo >&2 "ERROR: private key file $PRIVATE_KEY_FILE does not exist"; exit 1; }

# Set permissions for private key
chmod 600 "$PRIVATE_KEY_FILE"

# Output Public Key (override if exists)
PUBLIC_KEY="$(dropbearkey -y -f "$PRIVATE_KEY_FILE" 2>/dev/null | grep "ssh-${KEY_TYPE} " | cut -f2 -d ' ')"
echo "ssh-${KEY_TYPE} ${PUBLIC_KEY} ${KEY_COMMENT}" > "$PUBLIC_KEY_FILE"
# Set permissions for public key
chmod 644 "$PUBLIC_KEY_FILE"

if [ -n "$OUTPUT_PUBKEY" ]; then
  # Show Public Key
  if [ -z "$QUIET" ]; then
    echo >&2 "Private Key:"
  fi
  cat "$PUBLIC_KEY_FILE"
fi
