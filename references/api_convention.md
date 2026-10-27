# API Gateway request conventions

Maintainer reference for the scripts. Agents operating the skill use the scripts, not raw requests.

## Base URL and account

`${BOOMI_API_URL}/apim/api/rest/v1/{accountId}`, where `accountId` is `BOOMI_ACCOUNT_ID`. `BOOMI_API_URL` defaults to `https://api.boomi.com`; European Platform users set it to `https://api.platform.gb.boomi.com`. This is a distinct path prefix from the general AtomSphere Platform API (`api/rest/v1`, no `apim`) that `boomi-integration` uses, and from both the API Control Plane API (its own tenant backend host) and the Cloud API Management V3 API (`api.mashery.com`) — three separate API families with separate auth models, despite the overlapping "API Management" name.

## Authentication

Every request carries HTTP Basic Authentication with the same Boomi Platform account credentials the rest of the family shares: username `BOOMI_TOKEN.${BOOMI_USERNAME}`, password `${BOOMI_API_TOKEN}`. No token exchange step — unlike API Control Plane's platform-JWT dance, this API accepts the Basic credential directly on every call, the same as the general Platform API's own `boomi_curl` pattern in `boomi-integration`.

## Rate limit

10 requests per second. Exceeding it returns HTTP 503. This limit does not count against the account's general Platform API usage limits, and vice versa. `agw_api` retries automatically on 503 with exponential backoff (0.5s, 1s, 2s, 4s, 8s — up to 5 retries), emitting a warning to stderr on each attempt; callers do not need their own retry logic for rate limits.

## Object endpoint paths

Object-name casing in the URL path is **not consistent** across objects — this is a genuine API quirk, not a documentation error, and the scripts intentionally reproduce it rather than normalizing it:

| Object | Path segment | Verbs |
|---|---|---|
| Plan | `plan` | GET `plan/{id}`, QUERY `plan/query`, CREATE `plan/`, UPDATE `plan/{id}/update` (POST, not PUT), DELETE `plan/{id}`, usage `plan/{id}/usage` |
| Application | `Application` | GET/QUERY/CREATE/UPDATE/DELETE, same shape as Plan |
| ApiKey | `apiKey` | GET/QUERY/CREATE/UPDATE/DELETE |
| KeyCallCount | `KeyCallCount` | QUERY only |
| PublishedApi | `PublishedApi` | QUERY only |
| AuthenticationSource | `AuthenticationSource` | QUERY only |
| AuthenticationSourceUser | `AuthenticationSourceUser` | GET/QUERY/CREATE/UPDATE/DELETE |
| AuthenticationSourceGroup | `AuthenticationSourceGroup` | GET/QUERY/CREATE/UPDATE/DELETE |
| AuthenticationSourceRole | `AuthenticationSourceRole` | GET/QUERY/CREATE/UPDATE/DELETE |
| Contract (deprecated) | `contract` | GET/QUERY/CREATE/UPDATE/DELETE; superseded by Plan, mention only |
| Plan Association (action, not an object) | `planAssociation` | ADD via POST, REMOVE via DELETE; XML request/response only, no JSON |
| Send Changes to Authentication Source (action) | `sendChangesToAuthSource/{id}` | POST, empty body |

There is no verb-namespaced UPDATE (`PUT`) anywhere in this API family: every object updates via `POST .../{id}/update`. This differs from API Control Plane's convention (`PUT` for update), so do not copy that assumption when extending these scripts.

Update is a full replace on Plan, Application, AuthenticationSourceGroup, and AuthenticationSourceUser: the request body must include the object's own id field matching the URL id (its absence returns `400 "URL ID ... does not match ... ID null"`), and any field left out of the body is cleared — or, for booleans, reset to a server-side default; AuthenticationSourceUser's `enabled` flips to `true` on omission even when it was `false` before — rather than preserved from its prior value. AuthenticationSourceRole exposes the same `POST .../{id}/update` shape but is not independently verified; treat it as full-replace too until proven otherwise. Scripts and skill content must treat every object's update as "send the complete desired object," never "send only the fields that changed" — **except the one ApiKey exception documented below.**

ApiKey has no separate id field in its CREATE/GET response — the `key` value itself (a UUID) is the id used in `apiKey/{id}` URLs for GET, UPDATE, and DELETE.

**ApiKey UPDATE does not full-replace `planId`/`contractId`.** Omitting both from an update body does not clear the key's existing Plan assignment — it survives unchanged. This contradicts the full-replace rule applied to every other object in this family. Other ApiKey fields' omission behavior is unverified, so still send the complete object as the safe default; this is a documented exception, not a license to send partial ApiKey bodies generally.

**To actually move a key to a different Plan, send the new `planId` value explicitly — don't omit it.** Updating a key with `planId` set to a different (already deployment-attached) Plan id changes the assignment immediately. **There is no way to clear a key's Plan back to pending/no-plan via update** — sending `planId: null` or `planId: ""` is accepted with `HTTP 200` but silently ignored; the prior value is retained. If a key needs to go back to "no plan," there is currently no scripted path; treat this as a platform limitation, not a client-side bug, until proven otherwise.

Nested object references in AuthenticationSourceGroup's `roles` and AuthenticationSourceUser's `groups` require **both** the id and name fields together, e.g. `{"roleId": "...", "roleName": "..."}` — supplying the id alone is rejected with `400 "roleName must be set"`; the same shape applies to `groups`.

Plan's `status` field is read-only through both CREATE and UPDATE: CREATE rejects it with an opaque `500 "Unspecified fault message"`, UPDATE rejects it with `400 "Please do not use a plan update to change the plan status."` even when the value matches the plan's current status. Omit `status` from both bodies entirely.

ApiKey CREATE succeeds even when `planId` references a Plan that isn't yet attached to the key's deployment — the key is created and `enabled: true`. A later UPDATE referencing that same key then fails with `500 "...plan... is not available to the deployment..."`. Attach the Plan to the deployment with `agw-deployment.sh add-plan` before updating a key that references it.

## Query and queryMore paging

List operations are POST-only (`.../query`), not GET-with-params. The request body is a `QueryFilter`:

```json
{"QueryFilter":{"expression":{"operator":"EQUALS","property":"name","argument":["foo"]}}}
```

Multiple conditions AND together via `nestedExpression`:

```json
{"QueryFilter":{"expression":{"operator":"and","nestedExpression":[
  {"operator":"EQUALS","property":"name","argument":["foo"]},
  {"operator":"EQUALS","property":"status","argument":["ENABLED"]}
]}}}
```

`BETWEEN` takes two arguments (used for `KeyCallCount`'s `timeBlock` filter, always required for that object to bound the result set). An empty `{"QueryFilter":{}}` is what `agw_filter_from_args` emits when no `--field value` pairs are given, intended to mean "return all records."

The response carries `numberOfResults` and, when the result set exceeds the per-call cap (100 records), a `queryToken`. `agw_query` in the common library loops `POST .../queryMore` with the raw token as a `text/plain` body until no token is returned, merging `.result` arrays with `jq -s 'add'`. This is the same query/queryMore shape `boomi-integration`'s `paginate_query` implements for the general Platform API — same mechanism, different object family and a different per-page cap (100 here; the general API caps differently).

## The three action-style endpoints

`Add Plans to Deployments` (`POST planAssociation`) and `Remove Plans from Deployments` (`DELETE planAssociation`) share one XML body shape, a list of `<apim:association componentId="" environmentId="" planId=""/>` elements, wrapped in the prefixed `<apim:PlanAssociations>` for add and `<apim:PlanAssociation>` (singular) for remove — this naming inconsistency is in the API itself, not a typo in `agw-deployment.sh`. `add-plan` returns HTTP 200 with an empty body on success and works as documented. Neither supports JSON.

**`remove-plan` is non-functional.** `agw-deployment.sh remove-plan` still sends the documented request and warns on every invocation. Use the platform UI (Deployed APIs > Plans tab) to detach a Plan instead. You also cannot remove all plans from a deployment while it holds accepted or pending subscriptions; reject those first.

`Send Changes to Authentication Source` (`POST sendChangesToAuthSource/{authSourceId}`) pushes local `AuthenticationSourceUser`/`Group`/`Role` changes to the Gateway without going through the UI. The request body must be empty (the script sends `Content-Length: 0` rather than omitting the flag, since some servers reject a POST with no explicit length). Response: `{true}` on success.

These are the only three operations in this API family that are action-shaped rather than object CRUD, per the platform's own `API_actions` reference page. Every other action listed on that page (deploy process, upgrade Java, cancel execution, etc.) is a general Platform API action unrelated to API Management — ignore them here.

## Errors

The docs for this object family do not show a worked error-response example (unlike API Control Plane's Spring Boot error shape). Treat the HTTP status code and raw response body as authoritative; `finish()` in the common library surfaces both to the agent rather than assuming a particular JSON error envelope.

## Plan Usage is XML-only

`GET plan/{id}/usage` explicitly does not support JSON responses per its own reference page — it is the one GET-style read in this family that stays XML regardless of the `Accept` header sent. `agw-plan.sh usage` still requests with `Accept: application/json` for consistency with every other call, and passes the raw response through; expect XML back and read it as text rather than parsing it as JSON.

## Specification sources

No published OpenAPI/Swagger document exists for this object family, unlike API Control Plane (`/v3/api-docs`) or the general Platform API. The authoritative source is the object-by-object reference pages under the Boomi APIM docs index: `https://help.boomi.com/md/docs/Atomsphere/API%20Management/llms.txt` (fetch any page as markdown by swapping `/docs/` for `/md/docs/` and appending `.md`).
