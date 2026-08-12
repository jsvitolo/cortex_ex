defmodule CortexEx.MCP.Server do
  @moduledoc false

  alias CortexEx.Audit
  alias CortexEx.Identity
  alias CortexEx.MCP.Tools
  alias CortexEx.Users

  def handle_request(req), do: handle_request(req, nil)

  def handle_request(%{"method" => "initialize"} = req, _identity) do
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

  def handle_request(%{"method" => "notifications/initialized"}, _identity) do
    # Notification -- no response
    nil
  end

  def handle_request(%{"method" => "tools/list"} = req, identity) do
    case permissions(identity) do
      :denied ->
        unauthorized(req)

      perms ->
        tools =
          perms
          |> Tools.list_for()
          |> Enum.map(&Map.take(&1, [:name, :description, :inputSchema]))

        %{
          "jsonrpc" => "2.0",
          "id" => req["id"],
          "result" => %{"tools" => tools}
        }
    end
  end

  def handle_request(%{"method" => "tools/call", "params" => params} = req, identity) do
    name = params["name"]
    arguments = params["arguments"] || %{}

    case permissions(identity) do
      :denied ->
        unauthorized(req)

      perms ->
        result = Tools.call(name, arguments, perms)
        audit(identity, name, arguments, result)

        case result do
          {:ok, value} ->
            tool_result(req, to_string(value), false)

          {:error, :forbidden} ->
            tool_result(req, "Access denied: this tool requires write permission.", true)

          {:error, reason} ->
            tool_result(req, "Error: #{reason}", true)
        end
    end
  end

  def handle_request(%{"method" => "ping"} = req, _identity) do
    %{"jsonrpc" => "2.0", "id" => req["id"], "result" => %{}}
  end

  # Unknown methods with id get error response
  def handle_request(%{"id" => id, "method" => method}, _identity) when not is_nil(id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32601, "message" => "Method not found", "data" => method}
    }
  end

  # Notifications (no id) -- never respond
  def handle_request(_, _identity), do: nil

  # nil identity means auth is disabled (open/dev mode) — full access.
  defp permissions(nil), do: :admin
  defp permissions(%Identity{email: email}), do: Users.get_permissions(email)

  defp audit(nil, _name, _arguments, _result), do: :ok

  defp audit(%Identity{email: email}, name, arguments, result) do
    status =
      case result do
        {:ok, _} -> :ok
        {:error, :forbidden} -> :denied
        {:error, _} -> :error
      end

    Audit.tool_call(email, name, arguments, status)
  end

  defp tool_result(req, text, is_error) do
    result = %{"content" => [%{"type" => "text", "text" => text}]}
    result = if is_error, do: Map.put(result, "isError", true), else: result

    %{"jsonrpc" => "2.0", "id" => req["id"], "result" => result}
  end

  defp unauthorized(req) do
    %{
      "jsonrpc" => "2.0",
      "id" => req["id"],
      "error" => %{"code" => -32001, "message" => "Unauthorized", "data" => "email not in allowlist"}
    }
  end
end
