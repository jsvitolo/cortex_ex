defmodule CortexEx.MCP.Tools.Routes do
  @moduledoc false

  def tools do
    [
      %{
        name: "routes",
        description: """
        Lists all Phoenix routes with HTTP method, path, controller/live_view, action, and pipe_through pipelines.
        Equivalent to `mix phx.routes` but as a structured MCP tool.
        """,
        inputSchema: %{type: "object", properties: %{}},
        callback: &get_routes/1
      }
    ]
  end

  def get_routes(_args) do
    routers = find_routers()

    routes =
      Enum.flat_map(routers, fn router ->
        if function_exported?(router, :__routes__, 0) do
          router.__routes__()
          |> Enum.map(fn route ->
            %{
              method: route.verb |> to_string() |> String.upcase(),
              path: route.path,
              plug: inspect(route.plug),
              plug_opts: inspect(route.plug_opts),
              pipe_through: Map.get(route, :pipe_through, []) |> Enum.map(&to_string/1)
            }
          end)
        else
          []
        end
      end)

    case routes do
      [] -> {:error, "No Phoenix routes found"}
      _ -> {:ok, Jason.encode!(routes, pretty: true)}
    end
  rescue
    e -> {:error, "routes failed: #{Exception.message(e)}"}
  end

  defp find_routers do
    project_modules()
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__routes__, 0)
    end)
  end

  defp project_modules do
    app = Mix.Project.config()[:app]
    Application.load(app)
    {:ok, modules} = :application.get_key(app, :modules)
    modules
  rescue
    _ -> []
  end
end
