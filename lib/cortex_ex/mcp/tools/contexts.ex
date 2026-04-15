defmodule CortexEx.MCP.Tools.Contexts do
  @moduledoc false

  def tools do
    [
      %{
        name: "contexts",
        description: """
        Lists Phoenix contexts (business logic modules) with their public functions and associated schemas.
        Contexts are detected by convention: modules in lib/app_name/ that are not controllers, views, channels, or schemas.
        """,
        inputSchema: %{type: "object", properties: %{}},
        callback: &get_contexts/1
      }
    ]
  end

  def get_contexts(_args) do
    app = Mix.Project.config()[:app]
    app_module = app |> to_string() |> Macro.camelize()

    contexts =
      project_modules()
      |> Enum.filter(&context_module?(&1, app_module))
      |> Enum.map(&context_info/1)
      |> Enum.sort_by(& &1.module)

    case contexts do
      [] -> {:error, "No Phoenix contexts found"}
      _ -> {:ok, Jason.encode!(contexts, pretty: true)}
    end
  rescue
    e -> {:error, "contexts failed: #{Exception.message(e)}"}
  end

  defp context_module?(mod, app_module) do
    mod_str = inspect(mod)

    # Must be a direct child of the app module (e.g., MyApp.Accounts, not MyApp.Accounts.User)
    parts = String.split(mod_str, ".")

    length(parts) == 2 and
      hd(parts) == app_module and
      Code.ensure_loaded?(mod) and
      not is_schema?(mod) and
      not is_web_module?(mod_str) and
      has_public_functions?(mod)
  end

  defp is_schema?(mod) do
    function_exported?(mod, :__schema__, 1)
  end

  defp is_web_module?(mod_str) do
    String.contains?(mod_str, "Web") or
      String.contains?(mod_str, "Controller") or
      String.contains?(mod_str, "View") or
      String.contains?(mod_str, "Channel") or
      String.contains?(mod_str, "Socket") or
      String.contains?(mod_str, "Live")
  end

  defp has_public_functions?(mod) do
    mod.__info__(:functions)
    |> Enum.any?(fn {name, _arity} ->
      not String.starts_with?(to_string(name), "_")
    end)
  end

  defp context_info(mod) do
    functions =
      mod.__info__(:functions)
      |> Enum.reject(fn {name, _} -> String.starts_with?(to_string(name), "_") end)
      |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)

    %{
      module: inspect(mod),
      functions: functions,
      function_count: length(functions)
    }
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
