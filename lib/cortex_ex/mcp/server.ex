defmodule CortexEx.MCP.Server do
  @moduledoc false

  def handle_request(%{"method" => "initialize"} = req) do
    %{
      "jsonrpc" => "2.0",
      "id" => req["id"],
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "serverInfo" => %{
          "name" => "cortex_ex",
          "version" => Mix.Project.config()[:version] || "0.1.0"
        },
        "capabilities" => %{"tools" => %{}}
      }
    }
  end

  def handle_request(%{"method" => "notifications/initialized"}) do
    # Notification -- no response
    nil
  end

  def handle_request(%{"method" => "tools/list"} = req) do
    tools = CortexEx.MCP.Tools.list_all()

    %{
      "jsonrpc" => "2.0",
      "id" => req["id"],
      "result" => %{"tools" => tools}
    }
  end

  def handle_request(%{"method" => "tools/call", "params" => params} = req) do
    name = params["name"]
    arguments = params["arguments"] || %{}

    case CortexEx.MCP.Tools.call(name, arguments) do
      {:ok, result} ->
        %{
          "jsonrpc" => "2.0",
          "id" => req["id"],
          "result" => %{
            "content" => [%{"type" => "text", "text" => to_string(result)}]
          }
        }

      {:error, reason} ->
        %{
          "jsonrpc" => "2.0",
          "id" => req["id"],
          "result" => %{
            "content" => [%{"type" => "text", "text" => "Error: #{reason}"}],
            "isError" => true
          }
        }
    end
  end

  def handle_request(%{"method" => "ping"} = req) do
    %{"jsonrpc" => "2.0", "id" => req["id"], "result" => %{}}
  end

  # Unknown methods with id get error response
  def handle_request(%{"id" => id, "method" => method}) when not is_nil(id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32601, "message" => "Method not found", "data" => method}
    }
  end

  # Notifications (no id) -- never respond
  def handle_request(_), do: nil
end
