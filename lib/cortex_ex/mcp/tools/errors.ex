defmodule CortexEx.MCP.Tools.Errors do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_errors",
        description: """
        Returns recent captured exceptions with stacktraces, grouped by type.
        Errors are deduplicated — recurring identical errors show a count instead of duplicates.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            limit: %{
              type: "integer",
              description: "Maximum number of errors to return (default: 50)"
            }
          }
        },
        callback: &get_errors/1
      },
      %{
        name: "get_error_detail",
        description: """
        Returns full detail of a specific error by ID, including the complete stacktrace and context.
        """,
        inputSchema: %{
          type: "object",
          required: ["id"],
          properties: %{
            id: %{
              type: "string",
              description: "The error ID (e.g., 'err-1704067200000-a1b2')"
            }
          }
        },
        callback: &get_error_detail/1
      },
      %{
        name: "get_error_frequency",
        description: """
        Returns error frequency grouped by exception type + module + function.
        Useful for finding the most common errors. Optionally filter by module.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            module: %{
              type: "string",
              description: "Filter to a specific module (e.g., 'MyApp.Accounts'). Default: all modules."
            }
          }
        },
        callback: &get_error_frequency/1
      },
      %{
        name: "clear_errors",
        description: "Clears all captured errors from the buffer.",
        inputSchema: %{type: "object", properties: %{}},
        callback: &clear_errors/1
      }
    ]
  end

  def get_errors(args) do
    limit = Map.get(args, "limit", 50)
    errors = CortexEx.ErrorTracker.get_errors(limit)

    result =
      Enum.map(errors, fn e ->
        %{
          id: e.id,
          exception: e.exception,
          message: e.message,
          module: e.module,
          function: e.function,
          file: e.file,
          line: e.line,
          count: e.count,
          timestamp: DateTime.to_iso8601(e.timestamp)
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "get_errors failed: #{Exception.message(e)}"}
  end

  def get_error_detail(%{"id" => id}) do
    case CortexEx.ErrorTracker.get_error_detail(id) do
      nil ->
        {:error, "Error not found: #{id}"}

      error ->
        result = %{
          id: error.id,
          exception: error.exception,
          message: error.message,
          stacktrace: error.stacktrace,
          module: error.module,
          function: error.function,
          file: error.file,
          line: error.line,
          count: error.count,
          timestamp: DateTime.to_iso8601(error.timestamp),
          context: error.context
        }

        {:ok, Jason.encode!(result, pretty: true)}
    end
  rescue
    e -> {:error, "get_error_detail failed: #{Exception.message(e)}"}
  end

  def get_error_detail(_), do: {:error, "id parameter is required"}

  def get_error_frequency(args) do
    module = Map.get(args, "module")
    freq = CortexEx.ErrorTracker.get_error_frequency(module)

    result =
      Enum.map(freq, fn f ->
        %{
          exception: f.exception,
          module: f.module,
          function: f.function,
          total_count: f.total_count,
          last_seen: DateTime.to_iso8601(f.last_seen)
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "get_error_frequency failed: #{Exception.message(e)}"}
  end

  def clear_errors(_args) do
    CortexEx.ErrorTracker.clear_errors()
    {:ok, "Errors cleared"}
  rescue
    e -> {:error, "clear_errors failed: #{Exception.message(e)}"}
  end
end
