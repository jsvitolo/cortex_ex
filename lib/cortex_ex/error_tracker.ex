defmodule CortexEx.ErrorTracker do
  @moduledoc false
  use GenServer

  @max_size 1000

  # -- Public API --

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_errors(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_errors, limit})
  end

  def get_error_detail(id) do
    GenServer.call(__MODULE__, {:get_error_detail, id})
  end

  def get_error_frequency(module \\ nil) do
    GenServer.call(__MODULE__, {:get_error_frequency, module})
  end

  def clear_errors do
    GenServer.call(__MODULE__, :clear_errors)
  end

  # -- GenServer callbacks --

  @impl true
  def init(_) do
    handler_id = :cortex_ex_error_handler

    :logger.add_handler(handler_id, __MODULE__, %{
      level: :error,
      filter_default: :log,
      filters: []
    })

    {:ok, %{errors: [], max_size: @max_size, handler_id: handler_id}}
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    :logger.remove_handler(handler_id)
    :ok
  end

  @impl true
  def handle_call({:get_errors, limit}, _from, state) do
    errors =
      state.errors
      |> Enum.take(limit)
      |> Enum.map(&sanitize_for_output/1)

    {:reply, errors, state}
  end

  def handle_call({:get_error_detail, id}, _from, state) do
    result =
      case Enum.find(state.errors, &(&1.id == id)) do
        nil -> nil
        error -> sanitize_for_output(error)
      end

    {:reply, result, state}
  end

  def handle_call({:get_error_frequency, module_filter}, _from, state) do
    freq =
      state.errors
      |> maybe_filter_module(module_filter)
      |> Enum.group_by(&{&1.exception, &1.module, &1.function})
      |> Enum.map(fn {{exception, module, function}, entries} ->
        total_count = Enum.reduce(entries, 0, fn e, acc -> acc + e.count end)
        latest = List.first(entries)

        %{
          exception: exception,
          module: module,
          function: function,
          total_count: total_count,
          last_seen: latest.timestamp
        }
      end)
      |> Enum.sort_by(& &1.total_count, :desc)

    {:reply, freq, state}
  end

  def handle_call(:clear_errors, _from, state) do
    {:reply, :ok, %{state | errors: []}}
  end

  @impl true
  def handle_info({:log_event, entry}, state) do
    {:noreply, add_error(state, entry)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- :logger handler callbacks --

  # Called by :logger when adding the handler
  def adding_handler(config) do
    {:ok, config}
  end

  # Called by :logger when removing the handler
  def removing_handler(_config) do
    :ok
  end

  # Called by :logger for changing configuration
  def changing_config(_action, _old_config, new_config) do
    {:ok, new_config}
  end

  # Called by :logger on each log event at :error level
  def log(%{level: :error, msg: msg, meta: meta}, _config) do
    entry = parse_log_event(msg, meta)

    if entry do
      send(__MODULE__, {:log_event, entry})
    end

    :ok
  end

  def log(_event, _config), do: :ok

  # -- Private helpers --

  defp parse_log_event({:report, %{report: report}}, meta) when is_list(report) do
    # OTP crash report format
    parse_crash_report(report, meta)
  end

  defp parse_log_event({:report, report}, meta) when is_map(report) do
    # Structured report (e.g., from Logger)
    parse_map_report(report, meta)
  end

  defp parse_log_event({:string, message}, meta) do
    build_entry_from_message(IO.chardata_to_string(message), meta)
  end

  defp parse_log_event({:report, report}, meta) when is_list(report) do
    # Keyword list report
    message = Keyword.get(report, :message, inspect(report))
    build_entry_from_message(to_string(message), meta)
  end

  defp parse_log_event({format, args}, meta) when is_list(args) do
    message =
      try do
        :io_lib.format(format, args) |> IO.chardata_to_string()
      rescue
        _ -> to_string(format)
      end

    build_entry_from_message(message, meta)
  end

  defp parse_log_event(_, _), do: nil

  defp parse_crash_report(report, meta) do
    case extract_exception_from_report(report) do
      {exception, message, stacktrace_str} ->
        {mod, fun, file, line} = extract_location_from_meta(meta)

        %{
          id: generate_id(),
          exception: exception,
          message: message,
          stacktrace: stacktrace_str,
          module: mod,
          function: fun,
          file: file,
          line: line,
          timestamp: timestamp_from_meta(meta),
          count: 1,
          context: extract_context(meta)
        }

      nil ->
        # Fallback: treat as a generic error message
        message = inspect(report)
        build_entry_from_message(message, meta)
    end
  end

  defp parse_map_report(report, meta) do
    message = Map.get(report, :message, inspect(report))
    build_entry_from_message(to_string(message), meta)
  end

  defp build_entry_from_message(message, meta) do
    {mod, fun, file, line} = extract_location_from_meta(meta)

    %{
      id: generate_id(),
      exception: "RuntimeError",
      message: message,
      stacktrace: "",
      module: mod,
      function: fun,
      file: file,
      line: line,
      timestamp: timestamp_from_meta(meta),
      count: 1,
      context: extract_context(meta)
    }
  end

  defp extract_exception_from_report(report) do
    # OTP crash reports typically have a :error key with {exception, stacktrace}
    with {:ok, reason} <- find_report_reason(report),
         {exception, stacktrace} <- parse_reason(reason) do
      exception_name = exception.__struct__ |> inspect() |> String.replace("Elixir.", "")
      message = Exception.message(exception)
      stacktrace_str = Exception.format_stacktrace(stacktrace)
      {exception_name, message, stacktrace_str}
    else
      _ -> nil
    end
  end

  defp find_report_reason(report) when is_list(report) do
    case Keyword.get(report, :error) do
      nil ->
        case Keyword.get(report, :reason) do
          nil -> :error
          reason -> {:ok, reason}
        end

      error ->
        {:ok, error}
    end
  end

  defp parse_reason({%{__exception__: true} = exception, stacktrace}) when is_list(stacktrace) do
    {exception, stacktrace}
  end

  defp parse_reason(_), do: nil

  defp extract_location_from_meta(meta) do
    mod = meta |> Map.get(:mfa, {nil, nil, nil}) |> elem(0) |> safe_inspect_module()
    fun = meta |> Map.get(:mfa, {nil, nil, nil}) |> format_mfa_function()
    file = Map.get(meta, :file, "") |> to_string()
    line = Map.get(meta, :line, nil)
    {mod, fun, file, line}
  end

  defp safe_inspect_module(nil), do: "unknown"
  defp safe_inspect_module(mod) when is_atom(mod), do: inspect(mod) |> String.replace("Elixir.", "")
  defp safe_inspect_module(mod), do: to_string(mod)

  defp format_mfa_function({_mod, fun, arity}) when is_atom(fun) and is_integer(arity) do
    "#{fun}/#{arity}"
  end

  defp format_mfa_function(_), do: "unknown"

  defp timestamp_from_meta(meta) do
    case Map.get(meta, :time) do
      nil -> DateTime.utc_now()
      time_us -> DateTime.from_unix!(time_us, :microsecond)
    end
  end

  defp extract_context(meta) do
    meta
    |> Map.take([:pid, :request_id, :domain])
    |> Enum.into(%{}, fn
      {:pid, pid} when is_pid(pid) -> {:pid, inspect(pid)}
      {k, v} -> {k, v}
    end)
  end

  defp add_error(state, entry) do
    # Dedup: if same exception+module+function exists, increment count
    case Enum.find_index(state.errors, &same_error?(&1, entry)) do
      nil ->
        errors = [entry | state.errors] |> Enum.take(state.max_size)
        %{state | errors: errors}

      idx ->
        existing = Enum.at(state.errors, idx)
        updated = %{existing | count: existing.count + 1, timestamp: entry.timestamp}
        errors = List.replace_at(state.errors, idx, updated)
        # Move to front (most recent)
        {updated_entry, rest} = List.pop_at(errors, idx)
        %{state | errors: [updated_entry | rest]}
    end
  end

  defp same_error?(a, b) do
    a.exception == b.exception and a.module == b.module and a.function == b.function
  end

  defp maybe_filter_module(errors, nil), do: errors

  defp maybe_filter_module(errors, module) do
    Enum.filter(errors, &(&1.module == module))
  end

  defp sanitize_for_output(error) do
    Map.drop(error, [:__struct__])
  end

  defp generate_id do
    unix_ms = System.system_time(:millisecond)
    hash = :erlang.phash2(:erlang.unique_integer(), 0xFFFF)
    "err-#{unix_ms}-#{Integer.to_string(hash, 16) |> String.downcase()}"
  end
end
