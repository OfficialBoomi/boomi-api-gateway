#!/usr/bin/env bash
# Shared utilities for boomi-api-gateway CLI tools; sourced, not executed directly.

set -euo pipefail

# --- Environment ---

load_env() {
  local env_file=".env"
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: .env file not found in $(pwd)" >&2
    exit 1
  fi
  # No set -a: .env values stay in-shell. Trace off: xtrace would echo every assignment.
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x
  source "$env_file"
  if (( _xtrace_enabled )); then set -x; fi
}

# The one by-name expansion in the skill; ${!name} lands the value in a traced command.
var_is_set() {
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x
  local rc=0
  [[ -n "${!1:-}" ]] || rc=1
  if (( _xtrace_enabled )); then set -x; fi
  return $rc
}

require_env() {
  local missing=()
  for var in "$@"; do
    var_is_set "$var" || missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}" >&2
    echo "Check your .env file." >&2
    exit 1
  fi
}

require_tools() {
  local missing=()
  for tool in "$@"; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

# Standard preamble for every script: .env, curl, base URL.
agw_init() {
  load_env
  require_tools curl jq
  require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID
  BOOMI_API_URL="${BOOMI_API_URL:-https://api.boomi.com}"
}

# --- Argument handling ---

help_requested() {
  local arg
  for arg in "$@"; do
    case "$arg" in --help|-h) usage; exit 0 ;; esac
  done
}

need() {
  # need <value> <message>
  [[ -n "${1:-}" ]] || { echo "ERROR: $2" >&2; exit 1; }
}

# --- Version ---

_skill_version() {
  cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null || echo "unknown"
}

AGW_USER_AGENT="boomi-companion/boomi-api-gateway/$(_skill_version)"

# --- URL and query helpers ---

# The AtomSphere API Management surface: same account credentials as the general
# Platform API, its own path prefix (apim/api/rest/v1), and inconsistent object-name
# casing (plan, apiKey, Application, KeyCallCount, AuthenticationSourceUser, ...).
# Pass the object path exactly as the object's own reference doc shows it.
agw_url() {
  echo "${BOOMI_API_URL%/}/apim/api/rest/v1/${BOOMI_ACCOUNT_ID}/$1"
}

# Percent-encode a query value (unreserved chars pass through).
urlencode() {
  local s="$1" i c out=""
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

# --- Request bodies ---

# Resolve a JSON argument to a file path: an existing file is used as-is, anything else is
# treated as inline JSON written to a temp file removed on exit.
BODY_FILE=""
json_body() {
  if [[ -f "$1" ]]; then
    BODY_FILE="$1"
  else
    BODY_FILE=$(mktemp)
    trap 'rm -f "$BODY_FILE"' EXIT
    printf '%s' "$1" > "$BODY_FILE"
  fi
}

# --- API helpers ---

# Emits a curl config file on stdout for `curl -K -`, keeping credentials out of argv.
curl_cfg() {
  (( $# % 2 == 0 )) || { echo "ERROR: curl_cfg needs directive/value pairs" >&2; return 1; }
  local val
  while [[ $# -gt 1 ]]; do
    val="$2"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    printf '%s = "%s"\n' "$1" "$val"
    shift 2
  done
}

# Sets RESPONSE_BODY and RESPONSE_CODE. Basic auth reaches curl via stdin config, so
# stdin is reserved: never pipe into agw_api, or use @- bodies.
RESPONSE_BODY=""
RESPONSE_CODE=""
agw_api() {
  # Fence xtrace: the API token is expanded below; retry loop stays inside the fence.
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x

  local ssl_flag=""
  [[ "${BOOMI_VERIFY_SSL:-true}" == "false" ]] && ssl_flag="-k"

  local tmpfile rc attempt
  local backoffs
  backoffs=(0.5 1 2 4 8)
  tmpfile=$(mktemp)

  for (( attempt=0; ; attempt++ )); do
    set +e
    RESPONSE_CODE=$(curl_cfg user "BOOMI_TOKEN.${BOOMI_USERNAME}:${BOOMI_API_TOKEN}" \
      | curl -s $ssl_flag \
          --max-time "${BOOMI_TIMEOUT:-60}" \
          -A "$AGW_USER_AGENT" \
          -K - \
          -H "Accept: application/json" \
          -o "$tmpfile" -w "%{http_code}" \
          "$@")
    rc=$?
    set -e

    if (( rc != 0 )) || [[ -z "$RESPONSE_CODE" || "$RESPONSE_CODE" == "000" ]]; then
      RESPONSE_BODY=$(cat "$tmpfile")
      rm -f "$tmpfile"
      if (( _xtrace_enabled )); then set -x; fi
      echo "ERROR: could not reach the API Management API -- network or connection failure (curl exit ${rc})." >&2
      echo "  Check BOOMI_API_URL, network, and BOOMI_TIMEOUT (${BOOMI_TIMEOUT:-60}s)." >&2
      return 1
    fi

    [[ "$RESPONSE_CODE" == "503" ]] && (( attempt < ${#backoffs[@]} )) || break

    echo "WARN: HTTP 503 (rate limit); retry $((attempt+1))/${#backoffs[@]} after ${backoffs[$attempt]}s..." >&2
    sleep "${backoffs[$attempt]}"
  done

  RESPONSE_BODY=$(cat "$tmpfile")
  rm -f "$tmpfile"

  if (( _xtrace_enabled )); then set -x; fi
  return 0
}

agw_ok() {
  (( RESPONSE_CODE >= 200 && RESPONSE_CODE < 300 ))
}

# Print body on success (or a status line for empty 2xx), error + body on failure.
finish() {
  if ! agw_ok; then
    echo "ERROR: HTTP $RESPONSE_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi
  if [[ -z "$RESPONSE_BODY" ]]; then
    echo "OK (HTTP $RESPONSE_CODE)"
  else
    echo "$RESPONSE_BODY"
  fi
}

# --- Query and queryMore paging ---

# POST <object-path>/query with a JSON QueryFilter body, then follow queryToken via
# <object-path>/queryMore until exhausted. Prints one merged JSON array to stdout.
# Usage: agw_query <object-path> <query-filter-json>
agw_query() {
  local path="$1" filter="$2"
  local pages
  pages=$(mktemp)
  trap 'rm -f "$pages"' RETURN

  json_body "$filter"
  agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "$path/query")"
  agw_ok || { echo "ERROR: HTTP $RESPONSE_CODE" >&2; echo "$RESPONSE_BODY" >&2; return 1; }

  echo "$RESPONSE_BODY" | jq -c '.result // []' >> "$pages"
  local token
  token=$(echo "$RESPONSE_BODY" | jq -r '.queryToken // empty')

  while [[ -n "$token" ]]; do
    RESPONSE_BODY=""
    agw_api -X POST -H "Content-Type: text/plain" --data-binary "$token" "$(agw_url "$path/queryMore")"
    agw_ok || { echo "WARN: ${path}/queryMore failed (HTTP $RESPONSE_CODE); returning partial results." >&2; break; }
    echo "$RESPONSE_BODY" | jq -c '.result // []' >> "$pages"
    token=$(echo "$RESPONSE_BODY" | jq -r '.queryToken // empty')
  done

  jq -s 'add // []' "$pages"
}

# Builds a flat AND QueryFilter from --field value pairs (EQUALS). Prints JSON.
# An empty argument list yields an empty QueryFilter, which the API treats as "all".
# Usage: agw_filter_from_args "$@"
agw_filter_from_args() {
  local exprs="[]" key
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        key="${1#--}"
        [[ $# -ge 2 ]] || { echo "ERROR: $1 needs a value" >&2; exit 1; }
        exprs=$(jq -c --arg p "$key" --arg v "$2" '. + [{"operator":"EQUALS","property":$p,"argument":[$v]}]' <<<"$exprs")
        shift 2 ;;
      *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
    esac
  done
  jq -c 'if length == 0 then {"QueryFilter":{}}
         elif length == 1 then {"QueryFilter":{"expression": .[0]}}
         else {"QueryFilter":{"expression":{"operator":"and","nestedExpression": .}}} end' <<<"$exprs"
}
