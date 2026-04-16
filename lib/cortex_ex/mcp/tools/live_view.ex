defmodule CortexEx.MCP.Tools.LiveView do
  @moduledoc false

  def tools do
    if live_view_available?() do
      [
        %{
          name: "live_views",
          description: """
          Lists all active Phoenix.LiveView processes.
          Each entry includes: pid, module, assigns_keys (list of assign names), and connected_at.
          Only available when Phoenix.LiveView is loaded.
          """,
          inputSchema: %{type: "object", properties: %{}},
          callback: &live_views/1
        },
        %{
          name: "live_view_assigns",
          description: """
          Returns the assigns of a specific LiveView process by PID.
          Large values are truncated. Only available when Phoenix.LiveView is loaded.
          """,
          inputSchema: %{
            type: "object",
            required: ["pid"],
            properties: %{
              pid: %{
                type: "string",
                description: "PID string (e.g., '#PID<0.123.0>' or '0.123.0')"
              }
            }
          },
          callback: &live_view_assigns/1
        }
      ]
    else
      []
    end
  end

  # ── live_views ────────────────────────────────────────────────

  def live_views(_args) do
    if not live_view_available?() do
      {:error, "Phoenix.LiveView is not available in this application"}
    else
      entries =
        Process.list()
        |> Enum.filter(&live_view?/1)
        |> Enum.map(&build_entry/1)
        |> Enum.reject(&is_nil/1)

      {:ok, Jason.encode!(entries, pretty: true)}
    end
  rescue
    e -> {:error, "live_views failed: #{Exception.message(e)}"}
  end

  # ── live_view_assigns ─────────────────────────────────────────

  def live_view_assigns(%{"pid" => pid_str}) do
    if not live_view_available?() do
      {:error, "Phoenix.LiveView is not available in this application"}
    else
      case parse_pid(pid_str) do
        {:ok, pid} ->
          if Process.alive?(pid) do
            get_assigns(pid)
          else
            {:error, "Process #{pid_str} is not alive"}
          end

        :error ->
          {:error, "Invalid PID format: #{pid_str}"}
      end
    end
  rescue
    e -> {:error, "live_view_assigns failed: #{Exception.message(e)}"}
  end

  def live_view_assigns(_), do: {:error, "pid parameter is required"}

  # ── Detection ─────────────────────────────────────────────────

  def live_view?(pid) when is_pid(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :"$initial_call") do
          {Phoenix.LiveView.Channel, :init, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def live_view?(_), do: false

  # ── Helpers ───────────────────────────────────────────────────

  defp live_view_available? do
    Code.ensure_loaded?(Phoenix.LiveView)
  end

  defp build_entry(pid) do
    socket = safe_get_socket(pid)
    assigns = get_assigns_map(socket)

    %{
      pid: inspect(pid),
      module: extract_module(socket),
      assigns_keys: Map.keys(assigns) |> Enum.map(&to_string/1) |> Enum.sort(),
      connected_at: extract_connected_at(pid),
      transport_pid: extract_transport_pid(socket)
    }
  rescue
    _ -> nil
  end

  defp safe_get_socket(pid) do
    try do
      state = :sys.get_state(pid, 500)
      extract_socket_from_state(state)
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  defp extract_socket_from_state(state) when is_map(state) do
    cond do
      match?(%{socket: _}, state) -> Map.get(state, :socket)
      match?(%{__struct__: _, assigns: _}, state) -> state
      true -> nil
    end
  end

  defp extract_socket_from_state(state) when is_tuple(state) do
    state
    |> Tuple.to_list()
    |> Enum.find_value(fn
      %{assigns: _} = s -> s
      _ -> nil
    end)
  end

  defp extract_socket_from_state(_), do: nil

  defp get_assigns_map(nil), do: %{}
  defp get_assigns_map(%{assigns: assigns}) when is_map(assigns), do: assigns
  defp get_assigns_map(_), do: %{}

  defp extract_module(%{view: mod}) when is_atom(mod),
    do: inspect(mod) |> String.replace("Elixir.", "")

  defp extract_module(%{__struct__: mod}) when is_atom(mod),
    do: inspect(mod) |> String.replace("Elixir.", "")

  defp extract_module(_), do: "unknown"

  defp extract_connected_at(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :"$initial_call") do
          {_, _, _} -> DateTime.utc_now() |> DateTime.to_iso8601()
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_transport_pid(%{transport_pid: p}) when is_pid(p), do: inspect(p)
  defp extract_transport_pid(_), do: nil

  defp get_assigns(pid) do
    socket = safe_get_socket(pid)
    assigns = get_assigns_map(socket)

    truncated =
      Enum.into(assigns, %{}, fn {k, v} ->
        {to_string(k), truncate_value(v)}
      end)

    result = %{
      pid: inspect(pid),
      module: extract_module(socket),
      assigns: truncated
    }

    {:ok, Jason.encode!(result, pretty: true)}
  rescue
    e -> {:error, "Failed to fetch assigns: #{Exception.message(e)}"}
  end

  defp truncate_value(v)
       when is_binary(v) or is_integer(v) or is_float(v) or is_boolean(v) or is_nil(v) do
    if is_binary(v) and byte_size(v) > 500 do
      binary_part(v, 0, 500) <> "... [truncated]"
    else
      v
    end
  end

  defp truncate_value(v) when is_atom(v), do: v

  defp truncate_value(v) when is_list(v) do
    if length(v) > 50 do
      (Enum.take(v, 50) |> Enum.map(&truncate_value/1)) ++ ["... [truncated #{length(v) - 50} more items]"]
    else
      Enum.map(v, &truncate_value/1)
    end
  end

  defp truncate_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp truncate_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp truncate_value(%Date{} = d), do: Date.to_iso8601(d)

  defp truncate_value(v) when is_map(v) do
    cond do
      match?(%{__struct__: _}, v) ->
        inspect(v, limit: 20, printable_limit: 300)

      map_size(v) > 30 ->
        v
        |> Enum.take(30)
        |> Enum.into(%{}, fn {k, val} -> {to_string(k), truncate_value(val)} end)
        |> Map.put("__truncated__", "#{map_size(v) - 30} more keys omitted")

      true ->
        Enum.into(v, %{}, fn {k, val} -> {to_string(k), truncate_value(val)} end)
    end
  end

  defp truncate_value(v), do: inspect(v, limit: 20, printable_limit: 300)

  defp parse_pid(str) when is_binary(str) do
    cleaned =
      str
      |> String.replace("#PID", "")
      |> String.replace("<", "")
      |> String.replace(">", "")
      |> String.trim()

    cleaned =
      if String.starts_with?(cleaned, "0.") or String.contains?(cleaned, ".") do
        cleaned
      else
        cleaned
      end

    try do
      pid =
        if String.starts_with?(cleaned, "<") or String.contains?(cleaned, ".") do
          :erlang.list_to_pid(~c"<" ++ String.to_charlist(cleaned) ++ ~c">")
        else
          :erlang.list_to_pid(~c"<" ++ String.to_charlist(cleaned) ++ ~c">")
        end

      {:ok, pid}
    rescue
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp parse_pid(_), do: :error
end
