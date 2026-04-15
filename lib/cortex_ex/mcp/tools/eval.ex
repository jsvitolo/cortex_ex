defmodule CortexEx.MCP.Tools.Eval do
  @moduledoc false

  def tools do
    [
      %{
        name: "project_eval",
        description: """
        Evaluates Elixir code in the context of the running project.
        Has access to all project modules, dependencies, and runtime state.
        Use this to test functions, inspect data, or debug issues.
        The current Elixir version is: #{System.version()}
        """,
        inputSchema: %{
          type: "object",
          required: ["code"],
          properties: %{
            code: %{
              type: "string",
              description: "The Elixir code to evaluate"
            },
            timeout: %{
              type: "integer",
              description: "Timeout in milliseconds (default: 30000)"
            }
          }
        },
        callback: &project_eval/1
      }
    ]
  end

  def project_eval(%{"code" => code} = args) do
    timeout = Map.get(args, "timeout", 30_000)

    task =
      Task.async(fn ->
        try do
          {result, _bindings} = Code.eval_string(code, [], __ENV__)
          {:ok, inspect(result, pretty: true, limit: 50)}
        rescue
          e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
        catch
          kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, "Evaluation timed out after #{timeout}ms"}
    end
  end

  def project_eval(_), do: {:error, "code parameter is required"}
end
