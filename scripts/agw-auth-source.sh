#!/usr/bin/env bash
# Authentication Source operations: the top-level source (QUERY-only) plus its
# local users, groups, and roles (full CRUD), and pushing changes to the Gateway.

source "$(dirname "$0")/agw-common.sh"

usage() {
  cat <<'EOF'
Usage: agw-auth-source.sh <subcommand> [args]

Subcommands:
  list [--name <n>] [--type <t>]        QUERY-only; no GET, CREATE, UPDATE, or DELETE on the source itself.
                                         type values include OPENID, SAML, BASIC, BASIC_GATEWAY, and JWT.
                                         Only description/authSourceId/name/type come back; no type-specific
                                         config (e.g. JWT issuer, JWKS) -- read that in the platform UI.
  send-changes <auth-source-id>                        pushes local user/group/role changes to the Gateway

  user-list [--userName <n>] [--authSourceId <id>] [--groupName <n>] [--enabled true|false]
  user-get <user-id>
  user-create <json-file|json-string>   required: userName, authSourceId; optional: credential ({"password":".."}), enabled, groups
  user-update <user-id> <json-file|json-string>
  user-delete <user-id>

  group-list [--groupName <n>] [--roleName <n>] [--authSourceId <id>]
  group-get <group-id>
  group-create <json-file|json-string>   required: groupName, authSourceId; optional: description, roles
  group-update <group-id> <json-file|json-string>
  group-delete <group-id>

  role-list [--roleName <n>] [--authSourceId <id>]
  role-get <role-id>
  role-create <json-file|json-string>   required: roleName, authSourceId; optional: description
  role-update <role-id> <json-file|json-string>
  role-delete <role-id>

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID; BOOMI_API_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
agw_init

# crud_op <object-path> <op> [args...] -- shared list/get/create/update/delete dispatch.
crud_op() {
  local path="$1" op="$2"; shift 2
  case "$op" in
    list)
      local filter; filter=$(agw_filter_from_args "$@")
      agw_query "$path" "$filter" ; exit 0 ;;
    get)
      need "${1:-}" "Need <id>"
      agw_api "$(agw_url "$path/$1")" ;;
    create)
      need "${1:-}" "Need <json-file|json-string>"
      json_body "$1"
      agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "$path/")" ;;
    update)
      need "${2:-}" "Need <id> <json-file|json-string>"
      json_body "$2"
      agw_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(agw_url "$path/$1/update")" ;;
    delete)
      need "${1:-}" "Need <id>"
      agw_api -X DELETE "$(agw_url "$path/$1")" ;;
  esac
  finish
  exit 0
}

case "$sub" in
  list)
    filter=$(agw_filter_from_args "$@")
    agw_query AuthenticationSource "$filter" ; exit 0 ;;
  send-changes)
    need "${1:-}" "Need <auth-source-id>"
    agw_api -X POST -H "Content-Length: 0" "$(agw_url "sendChangesToAuthSource/$1")" ;;
  user-list)   crud_op AuthenticationSourceUser  list   "$@" ;;
  user-get)    crud_op AuthenticationSourceUser  get    "$@" ;;
  user-create) crud_op AuthenticationSourceUser  create "$@" ;;
  user-update) crud_op AuthenticationSourceUser  update "$@" ;;
  user-delete) crud_op AuthenticationSourceUser  delete "$@" ;;
  group-list)   crud_op AuthenticationSourceGroup  list   "$@" ;;
  group-get)    crud_op AuthenticationSourceGroup  get    "$@" ;;
  group-create) crud_op AuthenticationSourceGroup  create "$@" ;;
  group-update) crud_op AuthenticationSourceGroup  update "$@" ;;
  group-delete) crud_op AuthenticationSourceGroup  delete "$@" ;;
  role-list)   crud_op AuthenticationSourceRole  list   "$@" ;;
  role-get)    crud_op AuthenticationSourceRole  get    "$@" ;;
  role-create) crud_op AuthenticationSourceRole  create "$@" ;;
  role-update) crud_op AuthenticationSourceRole  update "$@" ;;
  role-delete) crud_op AuthenticationSourceRole  delete "$@" ;;
  *) usage >&2; exit 1 ;;
esac

finish
