defmodule CortexEx.MCP.Tools.Logs do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_logs",
        description: """
        Returns filtered application logs. Supports filtering by level, module, grep pattern,
        time window, and request ID. Logs are returned newest-first.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            tail: %{
              type: "integer",
              description: "Number of most recent entries to return (default: 50)"
            },
            grep: %{
              type: "string",
              description: "Regex pattern to filter log messages (case-insensitive)"
            },
            module: %{
              type: "string",
              description: "Filter by module name (e.g., 'MyApp.Accounts')"
            },
            level: %{
              type: "string",
              description: "Filter by log level: debug, info, warning, error"
            },
            since: %{
              type: "string",
              description: "Show logs from last N time units (e.g., '5m', '1h', '30s')"
            },
            request_id: %{
              type: "string",
              description: "Filter by request ID to correlate all logs for one request"
            }
          }
        },
        callback: &get_logs/1
      },
      %{
        name: "get_log_modules",
        description: """
        Returns the top 20 modules by log volume. Useful for finding noisy modules
        or understanding which parts of the application log most.
        """,
        inputSchema: %{type: "object", properties: %{}},
        callback: &get_log_modules/1
      },
      %{
        name: "clear_logs",
        description: "Clears all captured logs from the buffer.",
        inputSchema: %{type: "object", properties: %{}},
        callback: &clear_logs/1
      }
    ]
  end

  def get_logs(args) do
    opts =
      []
      |> maybe_add_opt(:tail, Map.get(args, "tail"))
      |> maybe_add_opt(:grep, Map.get(args, "grep"))
      |> maybe_add_opt(:module, Map.get(args, "module"))
      |> maybe_add_opt(:level, parse_level(Map.get(args, "level")))
      |> maybe_add_opt(:since, Map.get(args, "since"))
      |> maybe_add_opt(:request_id, Map.get(args, "request_id"))

    logs = CortexEx.LoggerBackend.get_logs(opts)

    result =
      Enum.map(logs, fn log ->
        %{
          level: to_string(log.level),
          message: log.message,
          module: log.module,
          function: log.function,
          file: log.file,
          line: log.line,
          timestamp: DateTime.to_iso8601(log.timestamp),
          pid: log.pid,
          request_id: log.request_id
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "get_logs failed: #{Exception.message(e)}"}
  end

  def get_log_modules(_args) do
    modules = CortexEx.LoggerBackend.get_log_modules()
    {:ok, Jason.encode!(modules, pretty: true)}
  rescue
    e -> {:error, "get_log_modules failed: #{Exception.message(e)}"}
  end

  def clear_logs(_args) do
    CortexEx.LoggerBackend.clear_logs()
    {:ok, "Logs cleared"}
  rescue
    e -> {:error, "clear_logs failed: #{Exception.message(e)}"}
  end

  defp parse_level(nil), do: nil
  defp parse_level("debug"), do: :debug
  defp parse_level("info"), do: :info
  defp parse_level("warning"), do: :warning
  defp parse_level("warn"), do: :warning
  defp parse_level("error"), do: :error
  defp parse_level(_), do: nil

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: [{key, value} | opts]
end
