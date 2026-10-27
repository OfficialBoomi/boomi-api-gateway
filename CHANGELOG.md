# Changelog

## 0.0.2

- boomi-api-control-plane: skill content (scope, credentials, object model, workflows, payload templates), references (concept model, API conventions), and CLI scripts (common library plus env-check, org, gateway, environment, discovery, api, product, plan, application, subscription, approval, governance, job)
- boomi-api-control-plane: fixes and doc corrections from end-to-end verification
- boomi-api-control-plane: add API policy template functionality
- boomi-api-gateway: build the skill baseline (SKILL.md, CLAUDE.md, references, scripts for plans, applications, API keys, published APIs, authentication sources, plan-to-deployment associations) and multiple rounds of claim validations and subsequent updates
- boomi-api-gateway: move Developer Portal out of scope; fix accepted/rejected subscription-state attribution in concept model; add HTTP 503 retry with exponential backoff in agw_api
- Update auth source and remove-plan docs with GraphQL references
- Stop tracking agent instruction files so the plugin stays agent-neutral
- Add `boomi-cloud-api-management` scripts for the CAM V3 management API
- Add CAM body field reference
- Document CAM `.env` keys in README
- Wireframe four skills: `boomi-api-gateway`, `boomi-cloud-api-management`, `boomi-api-control-plane`, `boomi-api-architecture`

