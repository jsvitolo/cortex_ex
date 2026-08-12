# CortexEx

Runtime intelligence for [Cortex](https://github.com/jsvitolo/cortex) -- Elixir MCP tools for code analysis, debugging, and observability.

## Installation

Add `cortex_ex` to your `mix.exs`:

```elixir
def deps do
  [{:cortex_ex, "~> 0.1", only: :dev}]
end
```

Then in your `lib/my_app_web/endpoint.ex`, add before the `if code_reloading?` block:

```elixir
if Mix.env() == :dev do
  plug CortexEx
end
```

## Available Tools

### v0.1 -- Code Intelligence

| Tool | Description |
|------|-------------|
| `xref_graph` | Cross-reference dependency graph from the Elixir compiler (100% accurate) |
| `xref_callers` | Find all callers of a module |
| `ecto_schemas` | List all Ecto schemas with fields, types, and associations |
| `routes` | List Phoenix routes with methods, paths, controllers, pipelines |
| `contexts` | List Phoenix contexts with public functions |
| `project_eval` | Evaluate Elixir code in the project runtime |
| `get_docs` | Get documentation for modules and functions |

### v0.2 -- Runtime Diagnostics

| Tool | Description |
|------|-------------|
| `get_errors` | Recent captured exceptions with stacktraces |
| `get_error_detail` | Full detail of a specific error by ID |
| `get_error_frequency` | Error frequency grouped by type + module + function |
| `clear_errors` | Clear captured errors buffer |
| `get_logs` | Recent log entries with level/metadata filtering |
| `clear_logs` | Clear log buffer |
| `recent_requests` | Recent HTTP request/response pairs |
| `request_detail` | Full detail of a specific request |

### v0.3 -- Process Introspection

| Tool | Description |
|------|-------------|
| `supervision_tree` | Supervision tree of the running application |
| `process_info` | Detailed info about a specific process |
| `oban_queues` | Oban queues with concurrency limits |
| `oban_workers` | Oban worker modules |
| `failed_jobs` | Recently failed Oban jobs |
| `retry_job` | Retry a failed Oban job |
| `app_config` | Application configuration |

### v0.4 -- Observability

| Tool | Description |
|------|-------------|
| `telemetry_metrics` | Recent telemetry events with filtering |
| `slow_queries` | Ecto queries exceeding duration threshold |
| `slow_requests` | HTTP requests exceeding duration threshold |
| `live_views` | Active Phoenix LiveView processes |
| `live_view_assigns` | Assigns for a specific LiveView |
| `pubsub_topology` | PubSub topics and subscribers |

### v0.5 -- Cortex Integration

| Tool | Description |
|------|-------------|
| `run_impacted_tests` | Run tests matching changed source files |
| `run_stale_tests` | Run `mix test --stale` using the compiler's stale detection |
| `save_to_cortex_memory` | Format a memory payload for Cortex MCP `memory(action="save")` |
| `sync_errors_to_memory` | Collect frequent errors as anti_pattern memories |
| `plan_migration` | Suggest an Ecto migration template from a schema module |
| `search_hex_docs` | Search HexDocs (https://search.hexdocs.pm) filtered by project deps |

### v0.6 -- Auth & Access Control

Everything needed to run cortex_ex in **production**: OAuth 2.1 resource-server
auth (MCP spec 2025-06-18 / RFC 9728), a per-email allowlist with read/write
permissions stored in the host app's database, an admin LiveView, and audit
logging.

With no config, cortex_ex behaves exactly as before (open, dev-only) and logs
a warning at boot.

#### 1. Authentication (OAuth 2.1 resource server)

cortex_ex validates RS256 JWTs issued by an external authorization server
(WorkOS AuthKit, Auth0, or any OIDC-compliant AS) that brokers Google login:

```elixir
# config/runtime.exs
config :cortex_ex, CortexEx.Auth,
  issuer: "https://your-tenant.authkit.app",
  audience: "https://app.empresa.com/cortex_ex/mcp",
  allowed_domain: "empresa.com"
  # optional: jwks_uri, email_claim, resource, jwks_ttl_seconds
```

Claude discovers the auth flow automatically: a 401 with `WWW-Authenticate`
points at `/.well-known/oauth-protected-resource/cortex_ex/mcp`, and the OAuth
flow (dynamic client registration + browser login) runs from there. The
`.mcp.json` needs only the URL.

**Required AS-side configuration** (the library's email-domain check is defense
in depth, not a substitute):

- Allow **only** the Google connection, restricted to your Workspace domain
  (WorkOS: SSO connection scoped to the org; Auth0: single Google connection +
  an Action checking the `hd` claim).
- Put the user's `email` into the **access token** (WorkOS JWT template /
  Auth0 post-login Action). If it lands under a namespaced claim, set
  `email_claim`.

#### 2. Allowlist & permissions

Domain restriction alone is coarse — each email must also be allowlisted, with
a permission level. Tools are classified `:read` (introspection) or `:write`
(`project_eval`, `run_impacted_tests`, `run_stale_tests`, `retry_job`,
`clear_errors`, `clear_logs`). Roles: `member` (with a `can_write` flag) and
`admin`. `tools/list` only shows what the caller may use; `tools/call`
re-enforces; removal or demotion applies on the next request.

```elixir
config :cortex_ex,
  repo: MyApp.Repo,
  admins: ["voce@empresa.com"]   # bootstrap admins from config — lockout-proof
```

Migration (tables `cortex_ex_users` and `cortex_ex_audit_log`):

```elixir
defmodule MyApp.Repo.Migrations.AddCortexEx do
  use Ecto.Migration

  def up, do: CortexEx.Migration.up()
  def down, do: CortexEx.Migration.down()
end
```

#### 3. Admin UI

```elixir
# router.ex — mount inside YOUR OWN authenticated admin pipeline;
# the admin page does no browser auth by itself.
import CortexEx.Router

scope "/" do
  pipe_through [:browser, :require_admin_user]
  cortex_ex_admin "/cortex_ex/admin"
end

# config — how to resolve the acting admin's email from the conn
config :cortex_ex, admin_email_source: {MyApp.Accounts, :current_email, []}
```

The resolved email must itself be a cortex_ex `admin` (config or DB) — others
see access denied.

#### 4. Audit log

Every `tools/call` (actor, tool, truncated args, ok/error/denied) and every
user-management change is recorded in `cortex_ex_audit_log`. Tool calls are
batch-flushed asynchronously; management changes are written synchronously.

```elixir
config :cortex_ex, audit: [flush_interval: 2_000, max_buffer: 50, args_limit: 2_000]
```

#### Degradation matrix

| Auth config | Repo config | Result |
|---|---|---|
| none | — | Open (dev mode), warning at boot |
| set | set | Full enforcement: JWT + domain + allowlist |
| set | none | Only config `admins:` have access; everyone else denied |
| partial | — | Raises at boot |

## MCP Configuration

Add to your `.mcp.json`:

```json
{
  "mcpServers": {
    "cortex_ex": {
      "url": "http://localhost:4000/cortex_ex/mcp"
    }
  }
}
```

In production use the public HTTPS URL; Claude handles the OAuth login flow
automatically when auth is enabled.

## License

MIT
