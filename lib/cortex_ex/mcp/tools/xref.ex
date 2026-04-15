defmodule CortexEx.MCP.Tools.Xref do
  @moduledoc false

  def tools do
    [
      %{
        name: "xref_graph",
        description: """
        Returns the cross-reference dependency graph from the Elixir compiler.
        This is 100% accurate -- it knows every module call, including through aliases and macros.
        Returns a JSON array of {caller, callee, file, line} entries.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            module: %{
              type: "string",
              description:
                "Filter to only show calls from this module (e.g., 'MyApp.Accounts'). Default: show all."
            }
          }
        },
        callback: &xref_graph/1
      },
      %{
        name: "xref_callers",
        description: """
        Returns all modules/functions that call into the specified module.
        Useful for understanding who depends on a module before changing it.
        """,
        inputSchema: %{
          type: "object",
          required: ["module"],
          properties: %{
            module: %{
              type: "string",
              description: "The module name to find callers for (e.g., 'MyApp.Accounts')"
            }
          }
        },
        callback: &xref_callers/1
      }
    ]
  end

  def xref_graph(args) do
    module_filter = Map.get(args, "module")
    calls = get_xref_calls()

    edges =
      calls
      |> maybe_filter_caller(module_filter)
      |> Enum.map(fn call ->
        {callee_mod, callee_fun, callee_arity} = call.callee

        %{
          caller: inspect(call.caller_module),
          callee: inspect(callee_mod),
          callee_function: "#{callee_fun}/#{callee_arity}",
          file: call.file,
          line: call.line
        }
      end)
      |> Enum.uniq_by(&{&1.caller, &1.callee, &1.callee_function})

    {:ok, Jason.encode!(edges, pretty: true)}
  rescue
    e -> {:error, "xref_graph failed: #{Exception.message(e)}"}
  end

  def xref_callers(%{"module" => module_str}) do
    module = Module.concat([module_str])
    calls = get_xref_calls()

    callers =
      calls
      |> Enum.filter(fn call ->
        {callee_mod, _fun, _arity} = call.callee
        callee_mod == module
      end)
      |> Enum.map(fn call ->
        {_callee_mod, callee_fun, callee_arity} = call.callee

        %{
          module: inspect(call.caller_module),
          calls: "#{callee_fun}/#{callee_arity}",
          file: call.file,
          line: call.line
        }
      end)
      |> Enum.uniq_by(&{&1.module, &1.calls})

    {:ok, Jason.encode!(callers, pretty: true)}
  rescue
    e -> {:error, "xref_callers failed: #{Exception.message(e)}"}
  end

  def xref_callers(_), do: {:error, "module parameter is required"}

  defp get_xref_calls do
    # Mix.Tasks.Xref.calls/0 is deprecated but still the best programmatic API
    # available for runtime xref data. Compilation tracers are the future replacement.
    Mix.Tasks.Xref.calls()
  end

  defp maybe_filter_caller(calls, nil), do: calls

  defp maybe_filter_caller(calls, module_str) do
    module = Module.concat([module_str])
    Enum.filter(calls, &(&1.caller_module == module))
  end
end
