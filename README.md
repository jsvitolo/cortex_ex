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
