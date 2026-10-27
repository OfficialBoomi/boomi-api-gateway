---
name: boomi-api-gateway
description: >-
  Operates the Boomi API Gateway and the Boomi API Management features around it — gateway runtimes, plans, applications, and subscriptions. Use when the user works with the Boomi API Gateway, API Management plans, or subscriptions. Not for Cloud API Management (CAM, formerly Mashery), API Control Plane (ACP), or the Boomi API Gateway Developer Portal (platform UI only — no skill covers it).
---

# boomi-api-gateway

## Scope

In: Boomi API Gateway runtimes; plans; applications; subscriptions.

Out: API Service components — they are Boomi platform components built with `boomi-integration`. Cloud API Management → `boomi-cloud-api-management`. API Control Plane → `boomi-api-control-plane`. Developer Portal — platform UI only; no skill covers it.

## What the API Gateway is

The Boomi API Gateway is a single-tenant control point between API consumers and backend systems. It hosts the required authentication sources and is the deployment target for two component types built in `boomi-integration`: **API Service** components (REST/SOAP/OData endpoints backed by a Boomi Process) and **API Proxy** components (forwarding to an external host). The Gateway enforces authentication, rate/quota limits, and policy at the network edge, and supports promoting an API across Dev, Test, and Prod environments with multiple versions running at once. Read `references/concept_model.md` for the full picture.

## Credentials

The scripts authenticate with the Boomi Platform credentials the family already uses, read from the workspace `.env`. Never accept them as arguments or paste them into chat.

| Key | Value |
|---|---|
| `BOOMI_USERNAME`, `BOOMI_API_TOKEN`, `BOOMI_ACCOUNT_ID` | Boomi Platform user, API token, and account ID. Sent directly as HTTP Basic Auth on every call — this API family needs no token exchange, unlike API Control Plane's platform-JWT model. |
| `BOOMI_API_URL` | Optional. Defaults to `https://api.boomi.com`. European Platform users set `https://api.platform.gb.boomi.com`. |

Run any script with `--help` to confirm required credentials; there is no separate env-check script since there is no token exchange step to verify.

## Object model

| Object | Purpose | Key fields |
|---|---|---|
| Plan | Quota and rate-limit definition attached to a deployment. | `name`, `maxMessageSize`, `rateLimit`/`rateLimitUnit`, `quotaLimit`/`quotaLimitUnit`, `status` ENABLED/DISABLED |
| Application | Consumer identity holding API keys. | `applicationName`, `companyName`, `contactEmail`, `enabled`, `deleted` |
| ApiKey | One key: one Application, one API, one environment, one Plan. | `apiId`, `applicationId`, `environmentId`, `planId` (omit for pending), `key`, `enabled` |
| KeyCallCount | Usage/analytics for a key, QUERY-only. | `apiKey`, `timeBlock`, `httpStatus`, `environmentId`, `count` |
| PublishedApi | Resolves a deployment's live endpoint URLs, QUERY-only. | `environmentId`, `atomId`, `componentId`, `rest`/`soap11`/`soap12`/`odata2` |
| AuthenticationSource | Gateway-level identity bridge, QUERY-only. | `name`, `type` (varies by tenant, not limited to OPENID/SAML/BASIC — see `references/concept_model.md`), `authSourceId` |
| AuthenticationSourceUser/Group/Role | Local identities under an Authentication Source. | `userName`/`groupName`/`roleName`, `authSourceId` |
| Contract (deprecated) | Superseded by Plan. Mention only. | `contractId`, `maxMessageSize`, `rateLimit`, `quotaLimit` |

A subscription here is the Application–ApiKey–Plan relationship above, not a distinct object — this API family has no `Subscription` object like API Control Plane's. `platformType` and cross-gateway approval flows belong to API Control Plane's object model, not this one.

Read `references/concept_model.md` for relationships, limits precedence, and the policy concepts that have no scripted surface.

## Core workflows

**Orient.** Confirm credentials with any read, e.g. `agw-plan.sh list`.

**Create and attach a Plan.** `agw-plan.sh create` (required: `name`), then `agw-deployment.sh add-plan <component-id> <environment-id> <plan-id>` to attach it to a deployment. A deployment needs an Authentication Source before a Plan can be added. A Plan attached to a deployment cannot be deleted until it is detached. **Detaching has no working API path — `agw-deployment.sh remove-plan` is non-functional; detach a Plan from a deployment in the platform UI instead** (Deployed APIs > Plans tab).

**Register a consumer.** `agw-application.sh create` (required: `applicationName`), then `agw-key.sh create` with `apiId`, `environmentId`, `applicationId`, and `planId`. Create succeeds even if that Plan isn't yet attached to the deployment, but a later `agw-key.sh update` referencing it then fails with `500 "...plan... is not available to the deployment..."` — attach the Plan first with `agw-deployment.sh add-plan` to avoid this. Omitting `planId` leaves the key pending until an attached Plan is set with `agw-key.sh update`. **To move a key to a different (already-attached) Plan, send the new `planId` explicitly in an update — this works immediately.** There is no way to send a key back to pending once a Plan is set: `planId: null`/`""` is accepted but silently ignored.

**Look up a live endpoint.** `agw-published-api.sh list --environmentId <id> --componentId <id>` returns the deployment's REST/SOAP/OData URLs to hand to a consumer.

**Check usage.** `agw-key.sh call-count --key-id <key-id> --timeBlock-start <iso8601> --timeBlock-end <iso8601>`; always bound by a time range. The script resolves the key value from its id internally, never accepting the secret as input. `agw-plan.sh usage <plan-id>` lists the deployments and keys using a Plan (XML response — this one endpoint does not support JSON).

**Manage Authentication Source identities.** The Authentication Source itself has no create — if the tenant doesn't already have one, create it in the platform UI first. Once one exists, `agw-auth-source.sh user-create` / `group-create` / `role-create` (each needs `authSourceId`, from `agw-auth-source.sh list`), then `agw-auth-source.sh send-changes <auth-source-id>` to push the change to the Gateway — edits are not live until pushed.

**Policies, policy templates, Keyless Plans, Dashboard.** No REST/SOAP API exists for these; explain them conceptually per `references/concept_model.md` and point the user to the platform UI. Do not attempt to script them.

## Payload templates

Create bodies send only writable fields. **Update bodies are a full replace, not a merge: the id field matching the URL is required, and any field left out of the body is cleared on the object, not preserved.** This holds for Plan, Application, AuthenticationSourceGroup, and AuthenticationSourceUser; treat AuthenticationSourceRole the same way until proven otherwise — the risk of an unnecessary full re-send is low, the risk of an unverified partial update clearing fields is not. Always re-send the object's current fields plus your change — read it with `get` first if you don't already have the current state in hand.

**ApiKey is the one exception: omitting `planId`/`contractId` from an update does NOT clear the key's Plan assignment — it survives untouched.** Still send ApiKey's other fields in full as the safe default; only the Plan-assignment omission behavior diverges from full-replace.

```json
{"name": "gold", "description": "", "maxMessageSize": 0, "rateLimit": 9999, "quotaLimit": 9999, "rateLimitUnit": "MINUTE", "quotaLimitUnit": "MONTH"}
```
Plan create. Only `name` is required. Update needs this same shape plus `planId` matching the URL id, and every field you want to keep. **Never include `status` in either body** — create rejects it with an opaque 500, and update rejects it with a 400 even when it matches the current value; status isn't settable through either call.

```json
{"applicationName": "newApp", "companyName": "Acme", "contactName": "Jane", "contactEmail": "jane@example.com", "contactPhone": "", "companyWebsite": "", "description": "", "notes": ""}
```
Application create. Only `applicationName` is required. Update needs this same shape plus `applicationId` matching the URL id; `applicationName` stays required on update too, and any other field you omit is cleared.

```json
{"apiId": "<api-id>", "environmentId": "<env-id>", "applicationId": "<application-id>", "planId": "<plan-id>"}
```
ApiKey create. `apiId`, `environmentId`, `applicationId` are required. Omit `planId` to create the key pending. **The response has no separate id field — the `key` value itself (a UUID) is the id used in `get`/`update`/`delete` URLs.** Update needs this same shape plus `key` matching the URL id. Omitting `planId`/`contractId` from an update does not clear the existing Plan assignment — to actually move the key to a different Plan, send that Plan's id explicitly; there is no way to send it back to pending (`null`/`""` are silently ignored). The object has no status field beyond `enabled`/`deleted` — don't look for a separate "pending"/"accepted"/"rejected" field, it doesn't exist.

```json
{"userName": "jdoe", "authSourceId": "<auth-source-id>", "credential": {"password": "..."}, "enabled": true, "groups": [{"groupId": "<group-id>", "groupName": "<group-name>"}]}
```
AuthenticationSourceUser create. `userName` and `authSourceId` are required. Update is a full replace — omitting `groups` clears the user's group assignments, and omitting `enabled` resets it to `true` regardless of its prior value. Always send `enabled` explicitly on update if the user should stay disabled. A `groups` entry needs both `groupId` and `groupName`, not the id alone.

```json
{"groupName": "readers", "authSourceId": "<auth-source-id>", "description": "", "roles": [{"roleId": "<role-id>", "roleName": "<role-name>"}]}
```
AuthenticationSourceGroup create. `groupName` and `authSourceId` are required. Update is a full replace — omitting `description` or `roles` clears them. A `roles` entry needs both `roleId` and `roleName`; the id alone is rejected with `400 "roleName must be set"`.

```json
{"roleName": "viewer", "authSourceId": "<auth-source-id>", "description": ""}
```
AuthenticationSourceRole create. `roleName` and `authSourceId` are required.

## Listing and paging

Every `list`/`user-list`/`group-list`/`role-list` sub-command accepts `--field value` filters that become an EQUALS `QueryFilter`; multiple filters AND together. Results page automatically through `queryToken`/`queryMore` inside the common library — the agent always receives one merged array, never a raw page. `KeyCallCount` additionally requires `--timeBlock-start`/`--timeBlock-end` on `agw-key.sh call-count`, since the API expects that object bounded by a time range.

## Scripts inventory

Resolve `<skill-path>` once (the directory holding this file) and invoke scripts from the project workspace so `.env` resolves. Every script has `--help`.

| Script | Sub-commands |
|---|---|
| `agw-plan.sh` | list, get, create, update, delete, usage |
| `agw-application.sh` | list, get, create, update, delete |
| `agw-key.sh` | list, get, create, update, delete, call-count |
| `agw-published-api.sh` | list |
| `agw-auth-source.sh` | list, send-changes, user-list/get/create/update/delete, group-list/get/create/update/delete, role-list/get/create/update/delete |
| `agw-deployment.sh` | add-plan, remove-plan (non-functional; use the platform UI) |

Always reach the API through these scripts. Do not hand-roll requests, URLs, or authorization headers.

## References

- `references/concept_model.md`. Use when: explaining how Plans, Applications, API keys, Authentication Sources, policies, policy templates, and Keyless Plans relate; which of these have no scripted surface and why.
- `references/api_convention.md`. Use when: extending or debugging the scripts; you need the endpoint path table, query/queryMore mechanics, or the XML-only action endpoints' request shape.
- Boomi documentation. Use when: a question goes beyond this skill. The API Management help index is `https://help.boomi.com/md/docs/Atomsphere/API%20Management/llms.txt`; fetch a page as markdown by swapping `/docs/` for `/md/docs/` and appending `.md`.
