defmodule CortexEx.MCP.Tools.CortexBridge do
  @moduledoc false

  def tools do
    [
      %{
        name: "save_to_cortex_memory",
        description: """
        Formats a memory payload for Cortex.
        Returns a JSON structure the agent can pass directly to
        `mcp__cortex__memory(action="save", ...)`. Types include:
        best_practice, anti_pattern, architecture, context.
        """,
        inputSchema: %{
          type: "object",
          required: ["title", "content", "type"],
          properties: %{
            title: %{
              type: "string",
              description: "Memory title"
            },
            content: %{
              type: "string",
              description: "Memory content (markdown supported)"
            },
            type: %{
              type: "string",
              description: "Memory type: best_practice, anti_pattern, architecture, context"
            }
          }
        },
        callback: &save_to_cortex_memory/1
      },
      %{
        name: "sync_errors_to_memory",
        description: """
        Collects recent frequent errors (count >= 3) from the ErrorTracker
        and formats them as anti_pattern memories ready to be saved to Cortex.
        Returns a list the agent can iterate to call
        `mcp__cortex__memory(action="save", ...)` for each entry.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            min_count: %{
              type: "integer",
              description: "Minimum occurrence count to include (default: 3)"
            }
          }
        },
        callback: &sync_errors_to_memory/1
      }
    ]
  end

  def save_to_cortex_memory(%{"title" => title, "content" => content, "type" => type}) do
    memory = %{
      type: type,
      title: title,
      content: content,
      source: "cortex_ex",
      project: project_name()
    }

    formatted = Jason.encode!(memory, pretty: true)
    prefix = "# Memory formatted — pass to mcp__cortex__memory(action=\"save\", ...):\n\n"
    {:ok, prefix <> formatted}
  rescue
    e -> {:error, "save_to_cortex_memory failed: #{Exception.message(e)}"}
  end

  def save_to_cortex_memory(_),
    do: {:error, "title, content, and type parameters are required"}

  def sync_errors_to_memory(args) do
    min_count = Map.get(args, "min_count", 3)

    errors =
      if tracker_available?() do
        CortexEx.ErrorTracker.get_errors(50)
      else
        []
      end

    memories =
      errors
      |> Enum.filter(&(&1.count >= min_count))
      |> Enum.map(&error_to_memory/1)

    header =
      "# #{length(memories)} frequent errors found. Pass each to mcp__cortex__memory(action=\"save\"):\n\n"

    {:ok, header <> Jason.encode!(memories, pretty: true)}
  rescue
    e -> {:error, "sync_errors_to_memory failed: #{Exception.message(e)}"}
  end

  defp error_to_memory(error) do
    content = """
    Exception: #{error.exception}
    Module: #{error.module}
    Function: #{error.function}
    File: #{error.file}:#{error.line}
    Occurrences: #{error.count}
    Message: #{error.message}

    This error recurred #{error.count} times. Consider adding defensive handling,
    input validation, or additional tests around this code path.
    """

    %{
      type: "anti_pattern",
      title: "Frequent error: #{error.exception} in #{error.module}",
      content: content,
      source: "cortex_ex",
      project: project_name()
    }
  end

  defp tracker_available? do
    case Process.whereis(CortexEx.ErrorTracker) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp project_name do
    case Mix.Project.config()[:app] do
      nil -> "unknown"
      app -> to_string(app)
    end
  rescue
    _ -> "unknown"
  end
end
