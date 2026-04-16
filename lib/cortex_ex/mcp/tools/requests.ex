defmodule CortexEx.MCP.Tools.Requests do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_recent_requests",
        description: """
        Returns recent HTTP requests with method, path, status code, and duration.
        Useful for understanding what requests the application is handling and finding slow endpoints.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            limit: %{
              type: "integer",
              description: "Maximum number of requests to return (default: 50)"
            }
          }
        },
        callback: &get_recent_requests/1
      },
      %{
        name: "get_request_detail",
        description: """
        Returns full detail of a specific request by ID, including params, headers, and timing.
        Sensitive fields (password, token, secret) are automatically filtered.
        """,
        inputSchema: %{
          type: "object",
          required: ["id"],
          properties: %{
            id: %{
              type: "string",
              description: "The request ID (e.g., 'req-1704067200000-1234')"
            }
          }
        },
        callback: &get_request_detail/1
      },
      %{
        name: "replay_request",
        description: """
        Returns a curl command and request info to replay a previous request.
        Useful for debugging — replay the exact request that caused an error.
        """,
        inputSchema: %{
          type: "object",
          required: ["id"],
          properties: %{
            id: %{
              type: "string",
              description: "The request ID to replay"
            }
          }
        },
        callback: &replay_request/1
      }
    ]
  end

  def get_recent_requests(args) do
    limit = Map.get(args, "limit", 50)
    requests = CortexEx.RequestTracker.get_recent_requests(limit)

    result =
      Enum.map(requests, fn req ->
        %{
          id: req.id,
          method: req.method,
          path: req.path,
          status: req.status,
          duration_ms: req.duration_ms,
          timestamp: DateTime.to_iso8601(req.timestamp),
          request_id: req.request_id
        }
      end)

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "get_recent_requests failed: #{Exception.message(e)}"}
  end

  def get_request_detail(%{"id" => id}) do
    case CortexEx.RequestTracker.get_request_detail(id) do
      nil ->
        {:error, "Request not found: #{id}"}

      req ->
        result = %{
          id: req.id,
          method: req.method,
          path: req.path,
          params: req.params,
          query_string: req.query_string,
          status: req.status,
          duration_ms: req.duration_ms,
          timestamp: DateTime.to_iso8601(req.timestamp),
          request_id: req.request_id,
          remote_ip: req.remote_ip
        }

        {:ok, Jason.encode!(result, pretty: true)}
    end
  rescue
    e -> {:error, "get_request_detail failed: #{Exception.message(e)}"}
  end

  def get_request_detail(_), do: {:error, "id parameter is required"}

  def replay_request(%{"id" => id}) do
    case CortexEx.RequestTracker.replay_request(id) do
      nil ->
        {:error, "Request not found: #{id}"}

      replay ->
        {:ok, Jason.encode!(replay, pretty: true)}
    end
  rescue
    e -> {:error, "replay_request failed: #{Exception.message(e)}"}
  end

  def replay_request(_), do: {:error, "id parameter is required"}
end
