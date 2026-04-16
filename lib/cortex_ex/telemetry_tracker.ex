defmodule CortexEx.TelemetryTracker do
  @moduledoc false
  use GenServer

  @max_size 2000
  @handler_id :cortex_ex_telemetry_tracker

  # Events we attach to. We try to attach to all of them but any that don't
  # exist in the host app simply never fire.
  @default_events [
    [:phoenix, :endpoint, :stop],
    [:phoenix, :controller, :dispatch, :stop],
    [:phoenix, :live_view, :mount, :stop],
    [:phoenix, :live_view, :handle_params, :stop],
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :router_dispatch, :stop],
    [:ecto, :repo, :query],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  # -- Public API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attach telemetry handlers. Called automatically at init but can be re-invoked
  to re-attach after detach or in tests.
  """
  def attach do
    GenServer.call(__MODULE__, :attach)
  end

  @doc """
  Detach telemetry handlers.
  """
  def detach do
    GenServer.call(__MODULE__, :detach)
  end

  @doc """
  Manually record an event (primarily for testing or custom event forwarding).
  """
  def record(event_name, measurements, metadata) do
    GenServer.cast(__MODULE__, {:record, event_name, measurements, metadata})
  end

  @doc """
  Return recent events, optionally filtered by event name prefix.

  `event_filter` can be:
    - `nil` → all events
    - a list like `[:phoenix, :endpoint]` → match events whose name starts with this prefix
    - a string like `"phoenix.endpoint"` → same semantics, dotted form
  """
  def get_metrics(event_filter \\ nil, limit \\ 100) do
    GenServer.call(__MODULE__, {:get_metrics, event_filter, limit})
  end

  @doc """
  Return Ecto query events whose total duration exceeded `threshold_ms`.
  """
  def get_slow_queries(threshold_ms \\ 100) do
    GenServer.call(__MODULE__, {:slow_queries, threshold_ms})
  end

  @doc """
  Return Phoenix endpoint/controller events whose duration exceeded `threshold_ms`.
  """
  def get_slow_requests(threshold_ms \\ 500) do
    GenServer.call(__MODULE__, {:slow_requests, threshold_ms})
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # -- GenServer callbacks --

  @impl true
  def init(opts) do
    max_size = Keyword.get(opts, :max_size, @max_size)
    state = %{events: [], max_size: max_size, attached?: false}

    state =
      if telemetry_available?() do
        do_attach(state)
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.attached? do
      do_detach()
    end

    :ok
  end

  @impl true
  def handle_call(:attach, _from, state) do
    if telemetry_available?() do
      new_state = do_attach(state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :telemetry_unavailable}, state}
    end
  end

  def handle_call(:detach, _from, state) do
    if state.attached?, do: do_detach()
    {:reply, :ok, %{state | attached?: false}}
  end

  def handle_call({:get_metrics, event_filter, limit}, _from, state) do
    filter = normalize_filter(event_filter)

    result =
      state.events
      |> filter_by_event(filter)
      |> Enum.take(limit)

    {:reply, result, state}
  end

  def handle_call({:slow_queries, threshold_ms}, _from, state) do
    threshold_native = ms_to_native(threshold_ms)

    result =
      state.events
      |> Enum.filter(fn e ->
        ecto_query_event?(e.name) and total_duration_native(e.measurements) >= threshold_native
      end)

    {:reply, result, state}
  end

  def handle_call({:slow_requests, threshold_ms}, _from, state) do
    threshold_native = ms_to_native(threshold_ms)

    result =
      state.events
      |> Enum.filter(fn e ->
        http_event?(e.name) and
          native_duration(e.measurements) >= threshold_native
      end)

    {:reply, result, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | events: []}}
  end

  @impl true
  def handle_cast({:record, event_name, measurements, metadata}, state) do
    entry = build_entry(event_name, measurements, metadata)
    events = [entry | state.events] |> Enum.take(state.max_size)
    {:noreply, %{state | events: events}}
  end

  # -- :telemetry handler callback --

  # Invoked by :telemetry on each attached event. Must be a 4-arity function.
  # We wrap everything in try/catch so an unexpected event structure never
  # crashes the emitting process.
  def handle_event(event_name, measurements, metadata, _config) do
    try do
      GenServer.cast(__MODULE__, {:record, event_name, measurements, metadata})
    catch
      _, _ -> :ok
    end

    :ok
  end

  # -- Private helpers --

  defp telemetry_available? do
    Code.ensure_loaded?(:telemetry) and function_exported?(:telemetry, :attach_many, 4)
  end

  defp do_attach(%{attached?: true} = state), do: state

  defp do_attach(state) do
    # Detach first in case a stale handler exists (safe no-op otherwise)
    do_detach()

    try do
      :telemetry.attach_many(
        @handler_id,
        @default_events,
        &__MODULE__.handle_event/4,
        %{}
      )

      %{state | attached?: true}
    rescue
      _ -> state
    catch
      _, _ -> state
    end
  end

  defp do_detach do
    if telemetry_available?() do
      try do
        :telemetry.detach(@handler_id)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    else
      :ok
    end
  end

  defp build_entry(event_name, measurements, metadata) do
    %{
      name: Enum.map(List.wrap(event_name), &to_atom_safe/1),
      measurements: sanitize_measurements(measurements),
      metadata: sanitize_metadata(metadata),
      timestamp: DateTime.utc_now()
    }
  end

  defp to_atom_safe(v) when is_atom(v), do: v
  defp to_atom_safe(v) when is_binary(v), do: String.to_atom(v)
  defp to_atom_safe(v), do: v

  defp sanitize_measurements(m) when is_map(m), do: m
  defp sanitize_measurements(_), do: %{}

  # Metadata can contain things that are not JSON-serializable (pids, structs,
  # conns, Ecto queries). We keep scalar fields and inspect non-serializable ones.
  defp sanitize_metadata(m) when is_map(m) do
    Enum.into(m, %{}, fn {k, v} -> {k, sanitize_value(v)} end)
  end

  defp sanitize_metadata(_), do: %{}

  defp sanitize_value(v)
       when is_binary(v) or is_integer(v) or is_float(v) or is_boolean(v) or is_nil(v),
       do: v

  defp sanitize_value(v) when is_atom(v), do: v

  defp sanitize_value(v) when is_list(v) do
    Enum.map(v, &sanitize_value/1)
  end

  defp sanitize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp sanitize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp sanitize_value(%Date{} = d), do: Date.to_iso8601(d)

  defp sanitize_value(v) when is_map(v) do
    cond do
      match?(%{__struct__: _}, v) ->
        inspect(v, limit: 50, printable_limit: 200)

      true ->
        Enum.into(v, %{}, fn {k, val} -> {k, sanitize_value(val)} end)
    end
  end

  defp sanitize_value(v) when is_tuple(v) do
    v |> Tuple.to_list() |> Enum.map(&sanitize_value/1)
  end

  defp sanitize_value(v) when is_pid(v), do: inspect(v)
  defp sanitize_value(v) when is_reference(v), do: inspect(v)
  defp sanitize_value(v) when is_port(v), do: inspect(v)
  defp sanitize_value(v) when is_function(v), do: inspect(v)
  defp sanitize_value(v), do: inspect(v, limit: 50, printable_limit: 200)

  defp normalize_filter(nil), do: nil
  defp normalize_filter([]), do: nil

  defp normalize_filter(filter) when is_list(filter) do
    Enum.map(filter, &to_atom_safe/1)
  end

  defp normalize_filter(filter) when is_binary(filter) do
    filter
    |> String.split([".", "/", " "], trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  defp normalize_filter(filter) when is_atom(filter), do: [filter]

  defp filter_by_event(events, nil), do: events

  defp filter_by_event(events, prefix) when is_list(prefix) do
    Enum.filter(events, fn e ->
      starts_with?(e.name, prefix)
    end)
  end

  defp starts_with?(_name, []), do: true
  defp starts_with?([], _prefix), do: false

  defp starts_with?([h | rest_name], [h | rest_prefix]),
    do: starts_with?(rest_name, rest_prefix)

  defp starts_with?(_, _), do: false

  defp ecto_query_event?(name) when is_list(name) do
    match?([:ecto | _], name) and :query in name
  end

  defp ecto_query_event?(_), do: false

  defp http_event?(name) when is_list(name) do
    case name do
      [:phoenix, :endpoint, :stop] -> true
      [:phoenix, :controller, :dispatch, :stop] -> true
      [:phoenix, :router_dispatch, :stop] -> true
      _ -> false
    end
  end

  defp http_event?(_), do: false

  # Total duration for Ecto events is the sum of queue/query/decode times.
  # Fall back to :duration if present.
  defp total_duration_native(m) when is_map(m) do
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

  defp total_duration_native(_), do: 0

  defp native_duration(m) when is_map(m) do
    case Map.get(m, :duration) do
      v when is_integer(v) -> v
      _ -> 0
    end
  end

  defp native_duration(_), do: 0

  defp ms_to_native(ms) when is_integer(ms) or is_float(ms) do
    try do
      System.convert_time_unit(trunc(ms), :millisecond, :native)
    rescue
      _ -> trunc(ms) * 1_000_000
    end
  end
end
