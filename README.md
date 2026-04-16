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

## License

MIT
