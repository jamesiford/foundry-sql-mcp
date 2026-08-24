# Portal walkthrough: verifying the Foundry-to-MCP authentication chain

A companion to [How Foundry-to-MCP authentication is supposed to work](auth-chain-reference.md) for
people working in the portals rather than the CLI. Every check below is a place to click and a value
to compare. Nothing here changes anything until the **Fix** column says so.

Work top to bottom. Earlier checks invalidate later ones, so a failure at check 2 makes checks 5 and
6 meaningless until it is corrected.

Collect these first — every check refers to at least one:

| Value | Where it comes from |
|---|---|
| MCP application (client) ID | Entra ID → App registrations → your MCP app → Overview |
| Tenant ID | same Overview page |
| Container App FQDN | Azure portal → Container App → Overview → Application Url |
| Foundry project name | Foundry portal → project → Overview |

---

## Check 0 — Which component is answering?

**Do this one first. It determines which half of the list is even relevant.**

Open the Container App's **Application Url** in a browser, with nothing appended:

```text
https://<container-app-fqdn>/
```

| What you see | Meaning | Where to go next |
|---|---|---|
| `{"status":"Healthy","version":"2.0.9","app-name":"dab_oss_2.0.9"}` | The request reached DAB. Nothing is intercepting it | Checks 1, 2, 5, 6, 7 |
| A **Microsoft sign-in page** | Container Apps built-in authentication is answering **before** DAB | **Check 4 — that is the fault** |
| Nothing, timeout, or a Container Apps error page | The app is not running or ingress is wrong | Check 3 |

DAB serves that health payload without a token by design. It is the fastest way to prove the
container is running, reachable, and not sitting behind another authentication layer.

> A `401` from the agent tells you nothing on its own — every component in the path can produce one.
> This check splits the problem in half in about ten seconds.

---

## Check 1 — Entra application: token shape

**Portal:** Entra ID → **App registrations** → your MCP app → **Manifest**

Find `requestedAccessTokenVersion` in the JSON.

| Value | Verdict |
|---|---|
| `2` | Correct |
| `null` or `1` | **Wrong** — this alone breaks every call |

**Why it matters.** This property decides the shape of every claim DAB validates. Neither the portal
nor `az ad app create` sets it, and the unset default is v1:

| | `aud` claim | `iss` claim |
|---|---|---|
| v1 — the default | `api://<client-id>` | `https://sts.windows.net/<tenant-id>/` |
| v2 — required | `<client-id>` | `https://login.microsoftonline.com/<tenant-id>/v2.0` |

DAB expects the v2 shape, so an unset value fails **both** claims at once — while the token still
correctly carries `Mcp.Invoke`. Nothing upstream reports a problem.

**Fix:** set it to `2` in the Manifest and **Save**. No rebuild or redeploy is needed. Tokens already
issued stay valid for up to an hour, so allow for that before concluding it did not work.

---

## Check 2 — Entra application: identity and permission definition

**Portal:** same app registration.

| Blade | Look for | Expected |
|---|---|---|
| **Overview** | Application ID URI | `api://<client-id>` |
| **App roles** | A role named `Mcp.Invoke` | Present, **Enabled**, Allowed member types = **Applications** |

If Allowed member types is *Users/Groups* only, a managed identity can never hold the role — a
managed identity is an application.

---

## Check 3 — Enterprise application: who is allowed to get a token

**Portal:** Entra ID → **Enterprise applications** → search the **same app name** → your MCP app

> App registrations and Enterprise applications are two views of the same identity. Role
> *assignments* live on the Enterprise application, not the registration. Looking in the wrong one is
> a common source of "the assignment is missing".

| Blade | Look for | Expected |
|---|---|---|
| **Properties** | Assignment required? | **Yes** |
| **Users and groups** | An entry for the Foundry project identity | Present, with role **Invoke SQL MCP** (`Mcp.Invoke`) |

The Foundry project identity appears under its own name — usually the project or account name, not a
person. If Assignment required is **Yes** and the assignment is missing, Entra refuses to issue the
token at all. The agent still reports a connection failure, which misleadingly points at the endpoint.

**Fix:** **Add user/group** → select the Foundry project identity → assign `Mcp.Invoke`.

---

## Check 4 — Container App: built-in authentication must be OFF

**Portal:** Azure portal → your Container App → **Settings** → **Authentication**

| What you see | Verdict |
|---|---|
| No identity provider configured | **Correct** |
| An identity provider listed / authentication enabled | **Wrong — this is a fault** |

**Why it matters.** Container Apps built-in authentication ("Easy Auth") validates callers itself and
returns `401` **before traffic reaches the container**. DAB never sees the request, so nothing in the
container logs will show it. It is not part of this design: Foundry authenticates to DAB directly with
an Entra token and DAB performs its own validation.

This is the most likely cause when Check 0 shows a Microsoft sign-in page.

**Fix:** remove the identity provider, or set authentication to disabled. Then repeat Check 0 — you
should now get the JSON health payload.

---

## Check 5 — Container App: ingress and revision

**Portal:** Container App → **Ingress**

| Setting | Expected |
|---|---|
| Ingress | Enabled |
| Ingress traffic | **Accepting traffic from anywhere** |
| Target port | `5000` |

Foundry is public in this topology and calls the endpoint over the internet. Internal-only ingress
cannot be reached.

**Portal:** Container App → **Revisions and replicas**

| Setting | Expected |
|---|---|
| Active revision | Running, and it is the one you expect |
| Min replicas | `1` for demos |

Min replicas of `0` causes a slow first call, never a `401`. Set it to `1` so demos are not sluggish,
but do not treat it as an authentication fix.

### 5a — Confirm you are looking at the app the agent is actually calling

**Portal:** Azure portal → **Container Apps** (the list) → filter to your resource group

If more than one Container App exists — which is normal after a few troubleshooting attempts — note
each **Application Url**. The FQDN in the agent's error message must match the app you are inspecting.

> The container name shown inside a revision does **not** have to match the app name. Reading the app
> name from a log header is unreliable. Read it from this list.

---

## Check 6 — What is actually inside the running image

**Portal:** Container App → **Console** → select the running replica and container → **Connect**

Then run:

```bash
cat /App/dab-config.json
```

Compare against:

| Config value | Expected |
|---|---|
| `authentication.provider` | `EntraID` |
| `jwt.audience` | the **bare client ID GUID** — no `api://` prefix |
| `jwt.issuer` | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| `host.mode` | `production` |
| `mcp.enabled` | `true` |

**If `audience` is `00000000-0000-0000-0000-000000000000` or `issuer` contains `11111111-1111-…`,
the image was built from the committed configuration and no token can ever validate.** Those are
placeholders that `scripts/build-demo-mcp.ps1` substitutes into an ignored build context. Building
directly from `src/mcp-server/` skips that substitution.

**Fix:** rebuild through the script with the real application and tenant IDs, push, and deploy a new
revision. This is a build-time value — correcting the app registration does nothing for an image that
already has the wrong one baked in.

### 6a — Entity permissions, while you have the file open

In the same output, check the `permissions` on each entity:

```json
"permissions": [
  { "role": "Mcp.Invoke",    "actions": ["read"] },
  { "role": "authenticated", "actions": ["read"] }
]
```

Foundry does not send the `X-MS-API-ROLE` header, so DAB evaluates the call as its built-in
`authenticated` role. Every entity the agent uses must grant `authenticated`, or a role matching a
claim the token actually carries.

This is a **different failure** from a 401. If authentication succeeds but the role is not granted,
DAB returns `Authorization Failure: Access Not Allowed` — which appears in the container logs and
looks like a data problem.

---

## Check 7 — Foundry project connection

**Portal:** Foundry portal → your project → **Build** → **Tools** → your MCP connection

| Setting | Expected |
|---|---|
| Target / endpoint | `https://<container-app-fqdn>/mcp` — no trailing slash, no extra path, no query string |
| Authentication | **Microsoft Entra — project managed identity** |
| Audience | `api://<client-id>` |

**The two audience values are intentionally different.** This connection requests `api://<client-id>`;
Entra issues a token whose `aud` is the bare GUID, which is what DAB validates (Check 6). Making them
identical looks like a fix and is not one.

Confirm the FQDN here matches the app from Check 5a.

---

## Check 8 — The agent definition

**Portal:** Foundry portal → project → **Agents** → your agent

| Setting | Expected |
|---|---|
| Version | The **latest** version, and it references the current connection |
| Tools | The MCP connection from Check 7 |
| Allowed tools | Only tools that exist for **your** entities |

Agent versions are immutable. Editing or recreating a connection does **not** update a version that
is already registered — the agent must be re-registered and the new version selected.

The repository's default allowed-tools list includes demo stored-procedure tools such as
`get_transfer_summary_by_client`. If the server has been pointed at different entities, those tools no
longer exist. The generic tools — `describe_entities`, `read_records`, `aggregate_records` — work for
any entity set.

---

## Summary sheet

Fill this in as you go. It converts "it returns 401" into a specific failing hop.

| # | Check | Where | Expected | Observed |
|---|---|---|---|---|
| 0 | Who answers `/` | Browser | DAB health JSON | |
| 1 | Token version | App registration → Manifest | `2` | |
| 2 | App ID URI + app role | App registration | `api://<id>`, `Mcp.Invoke`, Applications | |
| 3 | Role assignment | Enterprise application → Users and groups | Foundry project identity present | |
| 4 | Built-in auth | Container App → Authentication | No provider | |
| 5 | Ingress | Container App → Ingress | External, port 5000 | |
| 5a | Correct app | Container Apps list | FQDN matches the agent error | |
| 6 | Image config | Container App → Console | Real GUID + `/v2.0` issuer | |
| 6a | Entity permissions | same file | grants `authenticated` | |
| 7 | Connection | Foundry → Tools | MI auth, `api://<id>`, `/mcp` | |
| 8 | Agent version | Foundry → Agents | Latest, correct tools | |

---

## If you need to prove the rest of the chain works

Temporarily accepting unauthenticated calls is a legitimate way to isolate authentication from
everything else, but **it needs two changes, not one**.

Switching `host.mode` to `development` is not sufficient. Entity permissions grant `authenticated`
and `Mcp.Invoke`, so an anonymous caller maps to the `anonymous` role and is still refused — this time
by the authorization layer, with `Authorization Failure: Access Not Allowed` rather than a 401. That
looks like a new problem and is not.

To test anonymously, add an `anonymous` role with `read` to each entity **as well as** relaxing
authentication, then revert both.
