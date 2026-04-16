defmodule CortexEx.LoggerBackend do
  @moduledoc false
  use GenServer

  @max_size 5000

  # -- Public API --

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get filtered logs.

  Options:
    - tail: integer — last N entries (default 50)
    - grep: string — regex filter on message
    - module: string — filter by module name
    - level: atom — filter by log level (:debug, :info, :warning, :error)
    - since: string — entries in last N minutes (e.g., "5m", "1h")
    - request_id: string — correlate by request ID
  """
  def get_logs(opts \\ []) do
    GenServer.call(__MODULE__, {:get_logs, opts})
  end

  def get_log_modules do
    GenServer.call(__MODULE__, :get_log_modules)
  end

  def clear_logs do
    GenServer.call(__MODULE__, :clear_logs)
  end

  # -- GenServer callbacks --

  @impl true
  def init(_) do
    handler_id = :cortex_ex_log_handler

    :logger.add_handler(handler_id, __MODULE__, %{
      level: :all,
      filter_default: :log,
      filters: []
    })

    {:ok, %{logs: [], max_size: @max_size, handler_id: handler_id}}
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    :logger.remove_handler(handler_id)
    :ok
  end

  @impl true
  def handle_call({:get_logs, opts}, _from, state) do
    result =
      state.logs
      |> apply_filters(opts)
      |> Enum.take(Keyword.get(opts, :tail, 50))

    {:reply, result, state}
  end

  def handle_call(:get_log_modules, _from, state) do
    modules =
      state.logs
      |> Enum.group_by(& &1.module)
      |> Enum.map(fn {module, entries} -> %{module: module, count: length(entries)} end)
      |> Enum.sort_by(& &1.count, :desc)
      |> Enum.take(20)

    {:reply, modules, state}
  end

  def handle_call(:clear_logs, _from, state) do
    {:reply, :ok, %{state | logs: []}}
  end

  @impl true
  def handle_info({:log_entry, entry}, state) do
    logs = [entry | state.logs] |> Enum.take(state.max_size)
    {:noreply, %{state | logs: logs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- :logger handler callbacks --

  def adding_handler(config) do
    {:ok, config}
  end

  def removing_handler(_config) do
    :ok
  end

  def changing_config(_action, _old_config, new_config) do
    {:ok, new_config}
  end

  def log(%{level: level, msg: msg, meta: meta}, _config) do
    entry = %{
      level: level,
      message: format_message(msg),
      module: extract_module(meta),
      function: extract_function(meta),
      file: Map.get(meta, :file, "") |> to_string(),
      line: Map.get(meta, :line, nil),
      timestamp: timestamp_from_meta(meta),
      pid: meta |> Map.get(:pid) |> format_pid(),
      request_id: Map.get(meta, :request_id, nil),
      metadata: extract_metadata(meta)
    }

    send(__MODULE__, {:log_entry, entry})
    :ok
  rescue
    # Never crash the logger
    _ -> :ok
  end

  # -- Private helpers --

  defp format_message({:string, chardata}), do: IO.chardata_to_string(chardata)

  defp format_message({:report, report}) when is_map(report) do
    case Map.get(report, :message) do
      nil -> inspect(report)
      message -> to_string(message)
    end
  end

  defp format_message({:report, report}) when is_list(report) do
    case Keyword.get(report, :message) do
      nil -> inspect(report)
      message -> to_string(message)
    end
  end

  defp format_message({format, args}) when is_list(args) do
    try do
      :io_lib.format(format, args) |> IO.chardata_to_string()
    rescue
      _ -> to_string(format)
    end
  end

  defp format_message(_), do: ""

  defp extract_module(meta) do
    case Map.get(meta, :mfa) do
      {mod, _fun, _arity} -> inspect(mod) |> String.replace("Elixir.", "")
      _ -> "unknown"
    end
  end

  defp extract_function(meta) do
    case Map.get(meta, :mfa) do
      {_mod, fun, arity} when is_atom(fun) and is_integer(arity) -> "#{fun}/#{arity}"
      _ -> "unknown"
    end
  end

  defp format_pid(nil), do: nil
  defp format_pid(pid) when is_pid(pid), do: inspect(pid)
  defp format_pid(other), do: to_string(other)

  defp timestamp_from_meta(meta) do
    case Map.get(meta, :time) do
      nil -> DateTime.utc_now()
      time_us -> DateTime.from_unix!(time_us, :microsecond)
    end
  end

  defp extract_metadata(meta) do
    meta
    |> Map.drop([:time, :mfa, :file, :line, :pid, :gl, :request_id, :domain, :report_cb, :erl_level, :level])
    |> Enum.into(%{}, fn
      {k, v} when is_pid(v) -> {k, inspect(v)}
      {k, v} when is_port(v) -> {k, inspect(v)}
      {k, v} when is_reference(v) -> {k, inspect(v)}
      {k, v} -> {k, v}
    end)
  end

  defp apply_filters(logs, opts) do
    logs
    |> filter_by_level(Keyword.get(opts, :level))
    |> filter_by_module(Keyword.get(opts, :module))
    |> filter_by_grep(Keyword.get(opts, :grep))
    |> filter_by_since(Keyword.get(opts, :since))
    |> filter_by_request_id(Keyword.get(opts, :request_id))
  end

  defp filter_by_level(logs, nil), do: logs

  defp filter_by_level(logs, level) when is_atom(level) do
    Enum.filter(logs, &(&1.level == level))
  end

  defp filter_by_level(logs, level) when is_binary(level) do
    filter_by_level(logs, String.to_existing_atom(level))
  rescue
    _ -> logs
  end

  defp filter_by_module(logs, nil), do: logs

  defp filter_by_module(logs, module) do
    Enum.filter(logs, &(&1.module == module))
  end

  defp filter_by_grep(logs, nil), do: logs

  defp filter_by_grep(logs, pattern) do
    case Regex.compile(pattern, [:caseless]) do
      {:ok, regex} -> Enum.filter(logs, &Regex.match?(regex, &1.message))
      _ -> logs
    end
  end

  defp filter_by_since(logs, nil), do: logs

  defp filter_by_since(logs, since_str) do
    case parse_duration(since_str) do
      {:ok, seconds} ->
        cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)
        Enum.filter(logs, &(DateTime.compare(&1.timestamp, cutoff) != :lt))

      :error ->
        logs
    end
  end

  defp filter_by_request_id(logs, nil), do: logs

  defp filter_by_request_id(logs, request_id) do
    Enum.filter(logs, &(&1.request_id == request_id))
  end

  defp parse_duration(str) when is_binary(str) do
    case Regex.run(~r/^(\d+)(m|h|s)$/, str) do
      [_, num, "m"] -> {:ok, String.to_integer(num) * 60}
      [_, num, "h"] -> {:ok, String.to_integer(num) * 3600}
      [_, num, "s"] -> {:ok, String.to_integer(num)}
      _ -> :error
    end
  end

  defp parse_duration(_), do: :error
end
