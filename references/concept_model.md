# API Gateway concept model

Contents
- Purpose and position
- API Service and API Proxy components
- Environments and the Dev/Test/Prod lifecycle
- Plans
- Applications, API keys, and usage
- Authentication Sources
- Developer Portal (out of scope)
- Policies and policy templates
- Keyless Plans
- Dashboard
- Related surfaces this skill does not operate

## Purpose and position

The Boomi API Gateway is a single-tenant control point that sits between API consumers and backend systems. It is the runtime: it terminates inbound HTTP traffic, enforces authentication and policy, and routes to whichever Boomi Process or external host the deployed component targets. Install placement follows the consumer population — an internal application zone for internal-only traffic, a DMZ for external consumers. One Gateway instance usually serves several Boomi environments; a strict pre-production/production policy split is the main reason to run two Gateways instead of one.

## API Service and API Proxy components

Two component types route through the Gateway. An **API Service** component defines REST, SOAP, or OData endpoints backed by a Boomi Process. An **API Proxy** component forwards traffic to an external host outside Boomi. Both are built and configured in `boomi-integration` — this skill operates the Gateway they deploy to (plans, applications, keys, authentication sources) but does not build or configure the components themselves.

## Environments and the Dev/Test/Prod lifecycle

Components deploy to a Boomi environment, which is attached to a Gateway through the platform's environment-to-Gateway configuration. Promoting an API from Dev to Test to Prod means deploying the same component to different environments; multiple versions can run simultaneously so consumers are not broken by an in-flight upgrade.

## Plans

A Plan is the quota and rate-limit definition attached to a deployment. One API key references exactly one Plan (or, for the deprecated Contract object, one Contract — Plan supersedes it). A deployment needs an Authentication Source before a Plan can be added to it.

Limits: `maxMessageSize` (bytes, blank for unlimited), `rateLimit` with `rateLimitUnit` (SECOND, MINUTE, HOUR, UNLIMITED — per-node, so it multiplies by node count in a cluster), `quotaLimit` with `quotaLimitUnit` (DAY, WEEK, MONTH, UNLIMITED — account/environment-wide, resets at UTC midnight, weekly resets Sunday, monthly resets the 1st). In multi-tenant cloud environments, precedence runs Cloud Attachment Quota (HTTP Request Rate) first, then the Plan's own Rate Limit, then Quota Limit.

A Plan cannot be deleted while attached to a deployment or in use by an active subscription; deletion is otherwise permanent, with no undelete.

Plans attach to and detach from deployments through the `Add Plans to Deployments` / `Remove Plans from Deployments` actions (`agw-deployment.sh`), not through the Plan object's own CRUD. You cannot remove every Plan from a deployment while it has accepted or pending subscriptions; reject those first.

## Applications, API keys, and usage

An Application is the consumer identity — a named entity with owner contact info (name, email, phone, company, website) that Subscriptions and API keys attach to. **Disabling an Application does not change its API keys' own `enabled` field or their Plan/API/environment assignment.** This skill has no tool that calls a deployed API's live runtime endpoint as a consumer would, so whether the Gateway actually rejects live traffic from that key anyway (enforcement at the runtime layer, invisible to the management API) is not known and not claimed either way — treat "does disabling an Application suspend live traffic" as genuinely open, not false. **An Application with an active key/subscription CAN be deleted — deletion succeeds immediately with no guard and cascades to delete the key with it.** Do not instruct a user to delete keys before deleting the Application; it is unnecessary.

An API key belongs to one Application, one deployed API, one environment, and (once attached) one Plan. A key created without a `planId` starts in a **pending** state and stays there until a Plan is attached; a key with `planId` set is enabled immediately. **To move a key to a different Plan, update it with the new `planId` set explicitly — this works immediately.** There is no way to clear a key's Plan back to pending/no-plan: sending `planId: null` or `""` on update is accepted with `HTTP 200` but silently ignored, leaving the prior Plan in place — treat "return a key to pending" as unsupported by this API until proven otherwise. `contractId` is the deprecated predecessor to `planId` — when both are present, `planId` wins. The ApiKey object has no status/state field beyond `enabled`/`deleted` — "pending" and "disabled" are observable only via `enabled`/`planId`, and "deleted" via `deleted`. **"Accepted" and "rejected" are documented delete-eligible states on the subscription/key lifecycle — producer-side approval mechanics that the Developer Portal exposes but does not own. There is no distinguishing field on the ApiKey object for these states** — this skill cannot produce or observe either state. A key already deleted cannot be deleted again (`400 "The API Key was already deleted"`).

`KeyCallCount` is a usage/analytics QUERY object keyed by `apiKey`, `timeBlock`, `httpStatus`, and `environmentId` — always bound the query by a `timeBlock` range (`BETWEEN` with two ISO-8601 timestamps); the docs recommend never querying it unbounded.

`PublishedApi` resolves a deployment's live endpoint URLs (REST Swagger, SOAP 1.1/1.2 WSDL, OData 2 service URL) given an environment/atom/component — the tool for handing a consumer the actual URL to call. It is QUERY-only.

## Authentication Sources

An Authentication Source bridges the Gateway to an identity provider. Documented types are OPENID, SAML, and BASIC; `type` values also include `BASIC_GATEWAY` (a migrated, non-deprecated Basic source) and `JWT`, so do not treat `type` as limited to the three documented values. The Authentication Source object itself is QUERY-only through this API — you cannot create, update, or delete a source this way, only look one up by `name` or `type` to get its `authSourceId`. That lookup only ever returns `description`, `authSourceId`, `name`, and `type` — the same four fields regardless of source type. None of the type-specific configuration visible in the platform UI (JWT issuer, audience, JWKS/signing key; Basic realm or credential source; etc.) is retrievable through the REST API. The GraphQL API can read these fields via inline fragments (JWT issuer/jwksUrl/audiences, Basic users/groups, OpenID clientId/issuer, SAML ssoUrl/logoutUrl) but GraphQL is not yet implemented in this skill.

What you *can* manage programmatically are the source's local identities: `AuthenticationSourceUser` (userName, credential, enabled, groups), `AuthenticationSourceGroup` (groupName, roles), and `AuthenticationSourceRole` (roleName) — each with full CRUD. After changing any of these, call `Send Changes to Authentication Source` (`agw-auth-source.sh send-changes <auth-source-id>`) to push the change to the Gateway; edits are not live until pushed.

JWT and mutual TLS client-certificate authentication are the two methods the platform documentation recommends for securing a Gateway-fronted API.

## Developer Portal (out of scope)

The Developer Portal (API discovery, self-service registration, theming/branding, try-it-out UI) is out of scope — it is a content/CMS surface with no scripted API surface. No sibling skill covers it either; it is platform-UI-only. The Portal's consumer-facing data (Applications, subscriptions, API keys) is the same object set this skill already operates; only the Portal's own theming, branding, and catalog-page configuration fall outside.

## Policies and policy templates

The Gateway enforces a catalog of roughly 30 policies at the network edge, before traffic reaches the backend: security/auth (mTLS client cert, HMAC, role-based access control, IP filtering, CORS), traffic/routing (dynamic routing, circuit breaker, resource filtering, HTTP method override, URL rewriting, traffic shadowing, REST-to-SOAP), transformation (attribute/content assignment via Freemarker templates, header/query-param transforms, JSON/XML/HTML conversions), validation and threat protection (request/JSON/XML validation, JSON/XML/GraphQL/regex threat protection, request content limits), and custom code (sandboxed Groovy with an allow-list, HTTP callout, caching, mocking). An expression-language syntax (`{...}`) drives dynamic policy configuration against request/response transaction data.

None of these individual policies has a REST or SOAP API for configuration — they are UI-only (Policy Rules tab, or the Deployed APIs Custom Policies tab). There is nothing to script here; explain the catalog conceptually and point the user to the platform UI.

**Policy templates** are a separate, reusable feature: a named, versioned bundle of policy rules that can be created, edited, deleted, and assigned to API-deployment paths — this part is UI-driven (Policy Templates tab) with no REST/SOAP API, though templates are queryable and assignable through GraphQL. Policy templates created here show up automatically in API Control Plane from a connected Gateway environment, where `boomi-api-control-plane` can read and apply them — but template creation, editing, and deletion stay a Gateway (this skill's) concern; API Control Plane never writes a template, only reads and assigns one.

## Keyless Plans

A Keyless Plan removes the `X-API-KEY` header requirement from a deployment — useful only when consumers genuinely cannot be reconfigured to send a key, since it also removes whatever authentication that key was providing. When a deployment is keyless, rate and quota limits fall back to tracking by client IP instead of by key. Toggling this has no REST/SOAP endpoint; it is a UI toggle on the Deployed APIs Plans page, or (per the platform documentation) scriptable through a GraphQL `gatewayUpdate` mutation whose schema is not yet in this skill's reference material — mention the capability, but there is no script for it in this pass.

## Dashboard

The API Management Dashboard is a UI-only reporting page (total calls, errors, response times, top-5 APIs, call/error logs), not an API object despite living in the same reference-doc family as the true API objects above. It only covers data from 2023-05-01 onward; a separate Legacy Dashboard covers anything earlier. Nothing to script.

## Related surfaces this skill does not operate

- **API Service and API Proxy component authoring** — building, configuring, and testing the components themselves is `boomi-integration` territory; this skill only operates what those components deploy into.
- **API Control Plane** — the federated, multi-gateway management layer above this Gateway (and others) is `boomi-api-control-plane`. It reads and assigns this Gateway's policy templates but never creates them.
- **Cloud API Management** — the separate SaaS product (formerly Mashery) is `boomi-cloud-api-management`, with its own V3 management API and no relationship to this Gateway's object model.
- **Audit logs** — this API family exposes a narrow audit-log query surface (`api.application`, `api.authentication_source`, `api.contract`, `api.deployment`, `api.gateway_settings`, `api.portal_settings`, `api.environment_settings`, `api.key` — no Plan or Subscription audit type exists), deferred for this pass to stay consistent with `boomi-api-control-plane`'s own deferred audit-log stance.
- **Gateway installation and infrastructure** (system requirements, Docker/Kubernetes/EKS, runtime release scheduling, forward proxy, outbound SSL/mTLS, OpenTelemetry) is operational/infrastructure setup with no corresponding object API — out of scope for a scripted skill surface; point the user to the platform documentation and UI for install and infra work.
