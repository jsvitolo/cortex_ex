defmodule CortexEx.Audit do
  @moduledoc """
  Audit log. Tool calls are buffered and batch-inserted (async, flushed every
  2s or at 50 entries); user-management changes are written synchronously.
  Without a store, entries fall back to the Logger.

  Config:

      config :cortex_ex, audit: [flush_interval: 2_000, max_buffer: 50, args_limit: 2_000]
  """

  use GenServer
  require Logger

  alias CortexEx.Users.Store

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec tool_call(String.t(), String.t(), map(), :ok | :error | :denied) :: :ok
  def tool_call(actor_email, tool_name, args, status) do
    entry = %{
      actor_email: actor_email,
      action: "tool_call",
      tool_name: tool_name,
      args: truncate_args(args),
      result_status: to_string(status),
      metadata: %{},
      inserted_at: DateTime.utc_now()
    }

    GenServer.cast(__MODULE__, {:entry, entry})
  end

  @spec admin_action(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def admin_action(actor_email, action, metadata) do
    entry = %{
      actor_email: actor_email,
      action: action,
      tool_name: nil,
      args: nil,
      result_status: "ok",
      metadata: metadata,
      inserted_at: DateTime.utc_now()
    }

    GenServer.call(__MODULE__, {:sync_entry, entry})
  end

  @doc "Forces a buffer flush. Mainly for tests and graceful shutdown checks."
  @spec flush() :: :ok
  def flush, do: GenServer.call(__MODULE__, :flush)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    schedule_flush()
    {:ok, %{buffer: []}}
  end

  @impl true
  def handle_cast({:entry, entry}, state) do
    state = %{state | buffer: [entry | state.buffer]}

    if length(state.buffer) >= max_buffer() do
      {:noreply, do_flush(state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:sync_entry, entry}, _from, state) do
    {:reply, write([entry]), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, :ok, do_flush(state)}
  end

  @impl true
  def handle_info(:flush, state) do
    schedule_flush()
    {:noreply, do_flush(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    do_flush(state)
    :ok
  end

  defp do_flush(%{buffer: []} = state), do: state

  defp do_flush(%{buffer: buffer} = state) do
    write(Enum.reverse(buffer))
    %{state | buffer: []}
  end

  defp write(entries) do
    case Store.impl() do
      nil ->
        Enum.each(entries, fn entry ->
          Logger.info("CortexEx.Audit (no store configured): #{inspect(entry)}")
        end)

        :ok

      store ->
        case store.insert_audit_batch(entries) do
          :ok ->
            :ok

          {:error, reason} = error ->
            Logger.warning("CortexEx.Audit: failed to persist #{length(entries)} entries: #{inspect(reason)}")
            error
        end
    end
  end

  defp truncate_args(args) do
    limit = audit_config(:args_limit, 2_000)
    json = Jason.encode!(args)

    if byte_size(json) > limit do
      %{"_truncated" => String.slice(json, 0, limit), "_original_bytes" => byte_size(json)}
    else
      args
    end
  rescue
    _ -> %{"_unencodable" => true}
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, audit_config(:flush_interval, 2_000))

  defp max_buffer, do: audit_config(:max_buffer, 50)

  defp audit_config(key, default) do
    :cortex_ex |> Application.get_env(:audit, []) |> Keyword.get(key, default)
  end
end
