defmodule CortexEx.Users.Store.Memory do
  @moduledoc """
  In-memory store (Agent) used in tests and available as an explicit
  `config :cortex_ex, store: CortexEx.Users.Store.Memory` for repo-less
  setups. Not persistent — data is lost on restart.
  """

  @behaviour CortexEx.Users.Store

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{users: %{}, audits: []} end, name: __MODULE__)
  end

  def reset do
    ensure_started()
    Agent.update(__MODULE__, fn _ -> %{users: %{}, audits: []} end)
  end

  def audits do
    ensure_started()
    Agent.get(__MODULE__, &Enum.reverse(&1.audits))
  end

  @impl true
  def list_users do
    ensure_started()
    {:ok, Agent.get(__MODULE__, &(&1.users |> Map.values() |> Enum.sort_by(fn u -> u.email end)))}
  end

  @impl true
  def get_user(email) do
    ensure_started()
    {:ok, Agent.get(__MODULE__, &Map.get(&1.users, email))}
  end

  @impl true
  def insert_user(attrs) do
    ensure_started()
    email = attrs |> fetch(:email) |> String.downcase()

    user = %{
      email: email,
      role: fetch(attrs, :role) || "member",
      can_write: fetch(attrs, :can_write) || false,
      inserted_by: fetch(attrs, :inserted_by),
      inserted_at: DateTime.utc_now()
    }

    Agent.get_and_update(__MODULE__, fn state ->
      if Map.has_key?(state.users, email) do
        {{:error, :already_exists}, state}
      else
        {{:ok, user}, put_in(state.users[email], user)}
      end
    end)
  end

  @impl true
  def update_user(email, attrs) do
    ensure_started()

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.users, email) do
        nil ->
          {{:error, :not_found}, state}

        user ->
          user =
            Enum.reduce([:role, :can_write], user, fn key, acc ->
              case fetch(attrs, key) do
                nil -> acc
                value -> Map.put(acc, key, value)
              end
            end)

          {{:ok, user}, put_in(state.users[email], user)}
      end
    end)
  end

  @impl true
  def delete_user(email) do
    ensure_started()

    Agent.get_and_update(__MODULE__, fn state ->
      if Map.has_key?(state.users, email) do
        {:ok, %{state | users: Map.delete(state.users, email)}}
      else
        {{:error, :not_found}, state}
      end
    end)
  end

  @impl true
  def insert_audit(entry), do: insert_audit_batch([entry])

  @impl true
  def insert_audit_batch(entries) do
    ensure_started()
    Agent.update(__MODULE__, fn state -> %{state | audits: Enum.reverse(entries) ++ state.audits} end)
    :ok
  end

  # Map access that distinguishes an explicit `false`/`nil` from a missing key.
  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key))
    end
  end

  defp ensure_started do
    case start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end
end
