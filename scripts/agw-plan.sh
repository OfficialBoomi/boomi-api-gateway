#!/usr/bin/env bash
# Plan operations (quota and rate-limit definitions attached to API deployments).

source "$(dirname "$0")/agw-common.sh"

usage() {
  cat <<'EOF'
Usage: agw-plan.sh <subcommand> [args]

Subcommands:
  list [--name <n>] [--status ENABLED|DISABLED]
  get <plan-id>
  create <json-file|json-string>   required: name; optional: description, maxMessageSize, rateLimit, quotaLimit, rateLimitUnit (SECOND|MINUTE|HOUR|UNLIMITED), quotaLimitUnit (DAY|WEEK|MONTH|UNLIMITED)
  update <plan-id> <json-file|json-string>
  delete <plan-id>                 fails if the plan is attached to a deployment or an active subscription; deletion is permanent
  usage <plan-id>                  deployments and API keys using this plan (XML-only response per the API)

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
    agw_query plan "$filter" ; exit 0 ;;
  get)
    need "${1:-}" "Need <plan-id>"
    agw_api "$(agw_url "plan/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "plan/")" ;;
  update)
    need "${2:-}" "Need <plan-id> <json-file|json-string>"
    json_body "$2"
    # Update is POST .../plan/{id}/update, not PUT -- this API has no PUT verb.
    agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "plan/$1/update")" ;;
  delete)
    need "${1:-}" "Need <plan-id>"
    agw_api -X DELETE "$(agw_url "plan/$1")" ;;
  usage)
    need "${1:-}" "Need <plan-id>"
    agw_api "$(agw_url "plan/$1/usage")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
