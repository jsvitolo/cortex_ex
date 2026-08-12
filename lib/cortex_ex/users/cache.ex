defmodule CortexEx.Users.Cache do
  @moduledoc """
  ETS cache for permission lookups. Invalidated on every user write; the TTL
  (default 60s) is the fallback for multi-node deployments.
  """

  use GenServer

  @table :cortex_ex_permissions
  @default_ttl_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec get(String.t()) :: {:ok, term()} | :miss
  def get(email) do
    case :ets.lookup(@table, email) do
      [{^email, perms, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at <= ttl_ms() do
          {:ok, perms}
        else
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @spec put(String.t(), term()) :: :ok
  def put(email, perms) do
    :ets.insert(@table, {email, perms, System.monotonic_time(:millisecond)})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec invalidate(String.t()) :: :ok
  def invalidate(email) do
    :ets.delete(@table, email)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ttl_ms, do: Application.get_env(:cortex_ex, :permission_cache_ttl, @default_ttl_ms)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
