#!/usr/bin/env bash
# Plan-to-deployment association. The underlying API accepts XML only -- no JSON
# request or response support -- so this script is the one exception to the
# family's JSON-in/JSON-out convention: it takes plain positional triples and
# builds the XML body itself.

source "$(dirname "$0")/agw-common.sh"

usage() {
  cat <<'EOF'
Usage: agw-deployment.sh <subcommand> <component-id> <environment-id> <plan-id> [<component-id> <environment-id> <plan-id> ...]

Subcommands:
  add-plan       add one or more plans to deployments
  remove-plan    NON-FUNCTIONAL: the REST API returns "Unable to read message
                 body." Use the platform UI instead: Deployed APIs > select the
                 API > Plans tab. You cannot remove all plans while accepted or
                 pending subscriptions exist -- reject those first.

Triples are positional and repeatable. The API returns HTTP 200 with an empty body
on success; it does not support JSON.

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID; BOOMI_API_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
agw_init

(( $# > 0 && $# % 3 == 0 )) || { echo "ERROR: need one or more <component-id> <environment-id> <plan-id> triples" >&2; exit 1; }

# The API requires the apim: prefix on the root element, not just the association elements.
build_associations_xml() {
  local wrapper="$1"; shift
  local xml="<apim:${wrapper} xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:bns=\"http://api.platform.boomi.com/\" xmlns:apim=\"http://apim.api.platform.boomi.com/\">"
  while [[ $# -gt 0 ]]; do
    xml+="<apim:association componentId=\"$1\" environmentId=\"$2\" planId=\"$3\"/>"
    shift 3
  done
  xml+="</apim:${wrapper}>"
  printf '%s' "$xml"
}

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

case "$sub" in
  add-plan)
    build_associations_xml PlanAssociations "$@" > "$BODY_FILE"
    agw_api -X POST -H "Content-Type: application/xml" --data-binary "@$BODY_FILE" "$(agw_url planAssociation)" ;;
  remove-plan)
    echo "WARN: remove-plan is non-functional and will return HTTP 400 'Unable to read message body'. Use the platform UI (Deployed APIs > Plans tab) to detach a plan instead. Run 'agw-deployment.sh --help' for detail." >&2
    build_associations_xml PlanAssociation "$@" > "$BODY_FILE"
    agw_api -X DELETE -H "Content-Type: application/xml" --data-binary "@$BODY_FILE" "$(agw_url planAssociation)" ;;
  *) usage >&2; exit 1 ;;
esac

finish
