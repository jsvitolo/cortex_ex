defmodule CortexEx.MCP.Tools.Telemetry do
  @moduledoc false

  def tools do
    [
      %{
        name: "telemetry_metrics",
        description: """
        Returns recent telemetry events captured by the TelemetryTracker.
        Optionally filter by event name prefix (e.g. "phoenix.endpoint" or "ecto.repo").
        Each event includes measurements (duration, memory) and metadata (params, result).
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            event: %{
              type: "string",
              description:
                "Event name prefix (dotted form, e.g. 'phoenix.endpoint' or 'ecto.repo.query')"
            },
            limit: %{
              type: "integer",
              description: "Maximum number of events to return (default: 100)"
            }
          }
        },
        callback: &telemetry_metrics/1
      },
      %{
        name: "slow_queries",
        description: """
        Returns Ecto query events that exceeded the given duration threshold.
        Each entry includes SQL, total duration (ms), source, and params.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            threshold_ms: %{
              type: "integer",
              description: "Minimum duration in milliseconds to include (default: 100)"
            }
          }
        },
        callback: &slow_queries/1
      },
      %{
        name: "slow_requests",
        description: """
        Returns Phoenix endpoint/controller events that exceeded the given duration threshold.
        Each entry includes path, method, status, and duration (ms).
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            threshold_ms: %{
              type: "integer",
              description: "Minimum duration in milliseconds to include (default: 500)"
            }
          }
        },
        callback: &slow_requests/1
      }
    ]
  end

  # ── telemetry_metrics ─────────────────────────────────────────

  def telemetry_metrics(args) do
    event = Map.get(args, "event")
    limit = Map.get(args, "limit", 100)

    events = CortexEx.TelemetryTracker.get_metrics(event, limit)

    result = Enum.map(events, &format_event/1)
    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "telemetry_metrics failed: #{Exception.message(e)}"}
  end

  # ── slow_queries ──────────────────────────────────────────────

  def slow_queries(args) do
    threshold = Map.get(args, "threshold_ms", 100)
    events = CortexEx.TelemetryTracker.get_slow_queries(threshold)

    result =
      Enum.map(events, fn e ->
        meta = e.metadata
        m = e.measurements

        %{
          event: format_event_name(e.name),
          sql: truncate_string(meta[:query] || meta["query"] || ""),
          source: to_string(meta[:source] || meta["source"] || ""),
          params: inspect_params(meta[:params] || meta["params"]),
          repo: to_string(meta[:repo] || meta["repo"] || ""),
          duration_ms: native_to_ms(total_duration(m)),
          queue_time_ms: native_to_ms(Map.get(m, :queue_time)),
          query_time_ms: native_to_ms(Map.get(m, :query_time)),
          decode_time_ms: native_to_ms(Map.get(m, :decode_time)),
          timestamp: DateTime.to_iso8601(e.timestamp)
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "slow_queries failed: #{Exception.message(e)}"}
  end

  # ── slow_requests ─────────────────────────────────────────────

  def slow_requests(args) do
    threshold = Map.get(args, "threshold_ms", 500)
    events = CortexEx.TelemetryTracker.get_slow_requests(threshold)

    result =
      Enum.map(events, fn e ->
        meta = e.metadata
        m = e.measurements

        %{
          event: format_event_name(e.name),
          method: extract_method(meta),
          path: extract_path(meta),
          status: extract_status(meta),
          controller: to_string(meta[:controller] || meta["controller"] || ""),
          action: to_string(meta[:action] || meta["action"] || ""),
          duration_ms: native_to_ms(Map.get(m, :duration)),
          timestamp: DateTime.to_iso8601(e.timestamp)
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "slow_requests failed: #{Exception.message(e)}"}
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp format_event(e) do
    %{
      name: format_event_name(e.name),
      measurements: format_measurements(e.measurements),
      metadata: e.metadata,
      timestamp: DateTime.to_iso8601(e.timestamp)
    }
  end

  defp format_event_name(name) when is_list(name) do
    name |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  defp format_event_name(name), do: to_string(name)

  defp format_measurements(m) when is_map(m) do
    Enum.into(m, %{}, fn
      {k, v} when k in [:duration, :total_time, :queue_time, :query_time, :decode_time, :idle_time] and is_integer(v) ->
        {k, %{native: v, ms: native_to_ms(v)}}

      {k, v} ->
        {k, v}
    end)
  end

  defp format_measurements(_), do: %{}

  defp total_duration(m) when is_map(m) do
    explicit = Map.get(m, :total_time) || Map.get(m, :duration)

    cond do
      is_integer(explicit) ->
        explicit

      true ->
        [:queue_time, :query_time, :decode_time, :idle_time]
        |> Enum.reduce(0, fn k, acc ->
          case Map.get(m, k) do
            v when is_integer(v) -> acc + v
            _ -> acc
          end
        end)
    end
  end

  defp total_duration(_), do: 0

  defp native_to_ms(nil), do: nil

  defp native_to_ms(v) when is_integer(v) do
    try do
      System.convert_time_unit(v, :native, :microsecond) / 1000.0
    rescue
      _ -> v / 1_000_000.0
    end
  end

  defp native_to_ms(_), do: nil

  defp truncate_string(s) when is_binary(s) do
    if byte_size(s) > 2000 do
      binary_part(s, 0, 2000) <> "... [truncated]"
    else
      s
    end
  end

  defp truncate_string(other), do: inspect(other)

  defp inspect_params(nil), do: ""
  defp inspect_params(params), do: inspect(params, limit: 20, printable_limit: 500)

  defp extract_method(meta) do
    cond do
      is_binary(meta[:method]) -> meta[:method]
      is_binary(meta["method"]) -> meta["method"]
      true -> to_string(meta[:method] || meta["method"] || "")
    end
  end

  defp extract_path(meta) do
    cond do
      is_binary(meta[:request_path]) -> meta[:request_path]
      is_binary(meta["request_path"]) -> meta["request_path"]
      is_binary(meta[:path]) -> meta[:path]
      is_binary(meta["path"]) -> meta["path"]
      is_binary(meta[:route]) -> meta[:route]
      is_binary(meta["route"]) -> meta["route"]
      true -> to_string(meta[:request_path] || meta[:path] || "")
    end
  end

  defp extract_status(meta) do
    case meta[:status] || meta["status"] || meta[:status_code] || meta["status_code"] do
      v when is_integer(v) -> v
      v when is_binary(v) -> v
      _ -> nil
    end
  end
end
