#!/usr/bin/env bash
# Application operations (consumer identities that hold API keys).

source "$(dirname "$0")/agw-common.sh"

usage() {
  cat <<'EOF'
Usage: agw-application.sh <subcommand> [args]

Subcommands:
  list [--applicationName <n>] [--companyName <n>] [--deleted true|false] [--enabled true|false]
  get <application-id>
  create <json-file|json-string>   required: applicationName; optional: companyName, companyWebsite, contactName, contactEmail, contactPhone, description, notes, enabled
  update <application-id> <json-file|json-string>
  delete <application-id>

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
    agw_query Application "$filter" ; exit 0 ;;
  get)
    need "${1:-}" "Need <application-id>"
    agw_api "$(agw_url "Application/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "Application/")" ;;
  update)
    need "${2:-}" "Need <application-id> <json-file|json-string>"
    json_body "$2"
    agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "Application/$1/update")" ;;
  delete)
    need "${1:-}" "Need <application-id>"
    agw_api -X DELETE "$(agw_url "Application/$1")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
