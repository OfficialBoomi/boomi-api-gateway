#!/usr/bin/env bash
# API key operations. Keys are secrets: output is masked unless --show is passed.

# Whole-script trace off: apiKey responses carry the key value, echoed after agw_api's fence.
set +x

source "$(dirname "$0")/agw-common.sh"

usage() {
  cat <<'EOF'
Usage: agw-key.sh <subcommand> [args]

Subcommands:
  list [--applicationId <id>] [--environmentId <id>] [--apiId <id>] [--show]
  get <key-id> [--show]
  create <json-file|json-string> [--show]   required: apiId, environmentId, applicationId; optional: planId (omit to create the key pending, until a plan is attached)
  update <key-id> <json-file|json-string> [--show]
  delete <key-id>
  call-count --key-id <key-id> --timeBlock-start <iso8601> --timeBlock-end <iso8601> [--environmentId <id>] [--httpStatus <code>]
                                             usage counts for a key; always bound by a time block; resolves the key value from the id, never takes it as input

Keys print masked (e.g. ****ab12) unless --show is given.

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID; BOOMI_API_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift

# Strips --show from the argument list into the global ARGS array; sets SHOW=1 if found.
# Bash 3.2 has no mapfile, so this builds the array directly rather than through a pipe.
SHOW=0
ARGS=()
strip_show() {
  ARGS=()
  local a
  for a in "$@"; do
    if [[ "$a" == "--show" ]]; then SHOW=1; else ARGS+=("$a"); fi
  done
}

mask_and_print() {
  if (( SHOW )); then
    finish
    return
  fi
  agw_ok || finish
  if [[ -n "$RESPONSE_BODY" ]]; then
    echo "$RESPONSE_BODY" | jq 'def mask: if type != "string" then . elif length > 4 then "****" + .[-4:] else . end;
      if type == "array" then map(if has("key") then .key |= mask else . end)
      elif type == "object" and has("result") then .result |= map(if has("key") then .key |= mask else . end)
      elif has("key") then .key |= mask
      else . end'
  else
    echo "OK (HTTP $RESPONSE_CODE)"
  fi
}

agw_init
strip_show "$@"

case "$sub" in
  list)
    filter=$(agw_filter_from_args "${ARGS[@]+"${ARGS[@]}"}")
    RESPONSE_BODY=$(agw_query apiKey "$filter")
    RESPONSE_CODE=200
    mask_and_print ; exit 0 ;;
  get)
    need "${ARGS[0]:-}" "Need <key-id>"
    agw_api "$(agw_url "apiKey/${ARGS[0]}")"
    mask_and_print ; exit 0 ;;
  create)
    need "${ARGS[0]:-}" "Need <json-file|json-string>"
    json_body "${ARGS[0]}"
    agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "apiKey/")"
    mask_and_print ; exit 0 ;;
  update)
    need "${ARGS[1]:-}" "Need <key-id> <json-file|json-string>"
    json_body "${ARGS[1]}"
    agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "apiKey/${ARGS[0]}/update")"
    mask_and_print ; exit 0 ;;
  delete)
    need "${ARGS[0]:-}" "Need <key-id>"
    agw_api -X DELETE "$(agw_url "apiKey/${ARGS[0]}")"
    finish ; exit 0 ;;
  call-count)
    keyId="" envId="" httpStatus="" tbStart="" tbEnd=""
    set -- "${ARGS[@]+"${ARGS[@]}"}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --key-id) keyId="$2"; shift 2 ;;
        --environmentId) envId="$2"; shift 2 ;;
        --httpStatus) httpStatus="$2"; shift 2 ;;
        --timeBlock-start) tbStart="$2"; shift 2 ;;
        --timeBlock-end) tbEnd="$2"; shift 2 ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    need "$keyId" "Need --key-id <key-id>"
    need "$tbStart" "Need --timeBlock-start <iso8601>"
    need "$tbEnd" "Need --timeBlock-end <iso8601>"

    # Resolve the key value from its id; the caller never supplies the secret directly.
    agw_api "$(agw_url "apiKey/$keyId")"
    agw_ok || { echo "ERROR: HTTP $RESPONSE_CODE" >&2; echo "$RESPONSE_BODY" >&2; exit 1; }
    keyValue=$(echo "$RESPONSE_BODY" | jq -r '.key // empty')
    [[ -n "$keyValue" ]] || { echo "ERROR: key $keyId has no key value." >&2; exit 1; }

    exprs=$(jq -cn --arg s "$tbStart" --arg e "$tbEnd" '[{"operator":"BETWEEN","property":"timeBlock","argument":[$s,$e]}]')
    exprs=$(jq -c --arg v "$keyValue" '. + [{"operator":"EQUALS","property":"apiKey","argument":[$v]}]' <<<"$exprs")
    [[ -n "$envId" ]] && exprs=$(jq -c --arg v "$envId" '. + [{"operator":"EQUALS","property":"environmentId","argument":[$v]}]' <<<"$exprs")
    [[ -n "$httpStatus" ]] && exprs=$(jq -c --arg v "$httpStatus" '. + [{"operator":"EQUALS","property":"httpStatus","argument":[$v]}]' <<<"$exprs")
    filter=$(jq -c '{"QueryFilter":{"expression":{"operator":"and","nestedExpression": .}}}' <<<"$exprs")
    RESPONSE_BODY=$(agw_query KeyCallCount "$filter")
    RESPONSE_CODE=200
    finish ; exit 0 ;;
  *) usage >&2; exit 1 ;;
esac
