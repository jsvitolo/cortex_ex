defmodule CortexEx.RequestTracker do
  @moduledoc false
  use GenServer

  @max_size 2000
  @sensitive_keys ~w(password token secret authorization api_key apikey secret_key private_key)

  # -- Public API --

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def track_request(conn, duration_ms) do
    GenServer.cast(__MODULE__, {:track, conn, duration_ms})
  end

  def get_recent_requests(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_recent, limit})
  end

  def get_request_detail(id) do
    GenServer.call(__MODULE__, {:get_detail, id})
  end

  def replay_request(id) do
    GenServer.call(__MODULE__, {:replay, id})
  end

  def clear_requests do
    GenServer.call(__MODULE__, :clear)
  end

  # -- GenServer callbacks --

  @impl true
  def init(_) do
    {:ok, %{requests: [], max_size: @max_size}}
  end

  @impl true
  def handle_cast({:track, conn, duration_ms}, state) do
    entry = build_entry(conn, duration_ms)
    requests = [entry | state.requests] |> Enum.take(state.max_size)
    {:noreply, %{state | requests: requests}}
  end

  @impl true
  def handle_call({:get_recent, limit}, _from, state) do
    result = Enum.take(state.requests, limit)
    {:reply, result, state}
  end

  def handle_call({:get_detail, id}, _from, state) do
    result = Enum.find(state.requests, &(&1.id == id))
    {:reply, result, state}
  end

  def handle_call({:replay, id}, _from, state) do
    result =
      case Enum.find(state.requests, &(&1.id == id)) do
        nil ->
          nil

        req ->
          %{
            curl: build_curl_command(req),
            method: req.method,
            path: req.path,
            params: req.params,
            query_string: req.query_string
          }
      end

    {:reply, result, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | requests: []}}
  end

  # -- Private helpers --

  defp build_entry(conn, duration_ms) do
    %{
      id: generate_id(),
      method: conn.method,
      path: conn.request_path,
      params: sanitize_params(conn.params),
      query_string: conn.query_string || "",
      status: conn.status,
      duration_ms: duration_ms,
      timestamp: DateTime.utc_now(),
      request_id: get_request_id(conn),
      remote_ip: format_remote_ip(conn.remote_ip)
    }
  end

  defp sanitize_params(%Plug.Conn.Unfetched{}), do: %{}

  defp sanitize_params(params) when is_map(params) do
    Enum.into(params, %{}, fn
      {key, value} when is_binary(key) ->
        if sensitive_key?(key) do
          {key, "[FILTERED]"}
        else
          {key, sanitize_value(value)}
        end

      {key, value} ->
        {key, sanitize_value(value)}
    end)
  end

  defp sanitize_params(_), do: %{}

  defp sanitize_value(value) when is_map(value), do: sanitize_params(value)

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value

  defp sensitive_key?(key) do
    lower = String.downcase(key)
    Enum.any?(@sensitive_keys, &String.contains?(lower, &1))
  end

  defp get_request_id(conn) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [id | _] -> id
      _ -> nil
    end
  end

  defp format_remote_ip(ip) when is_tuple(ip) do
    ip |> :inet.ntoa() |> to_string()
  end

  defp format_remote_ip(ip), do: to_string(ip)

  defp build_curl_command(req) do
    method_flag =
      case req.method do
        "GET" -> ""
        "HEAD" -> "-I"
        method -> "-X #{method}"
      end

    url = "http://localhost:4000#{req.path}"

    url =
      if req.query_string != "" do
        "#{url}?#{req.query_string}"
      else
        url
      end

    data_flag =
      if req.method in ["POST", "PUT", "PATCH"] and req.params != %{} do
        " -H 'Content-Type: application/json' -d '#{Jason.encode!(req.params)}'"
      else
        ""
      end

    "curl #{method_flag} '#{url}'#{data_flag}" |> String.trim()
  end

  defp generate_id do
    unix_ms = System.system_time(:millisecond)
    "req-#{unix_ms}-#{:erlang.unique_integer([:positive]) |> rem(0xFFFF)}"
  end
end
