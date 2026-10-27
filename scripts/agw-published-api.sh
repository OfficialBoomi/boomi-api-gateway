#!/usr/bin/env bash
# PublishedApi (QUERY-only): resolves a deployed API's live REST/SOAP/OData endpoint URLs.

source "$(dirname "$0")/agw-common.sh"

usage() {
  cat <<'EOF'
Usage: agw-published-api.sh list [--environmentId <id>] [--atomId <id>] [--componentId <id>]

QUERY-only object; no GET, CREATE, UPDATE, or DELETE.

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID; BOOMI_API_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
agw_init

case "$sub" in
  list)
    filter=$(agw_filter_from_args "$@")
    agw_query PublishedApi "$filter" ;;
  *) usage >&2; exit 1 ;;
esac
