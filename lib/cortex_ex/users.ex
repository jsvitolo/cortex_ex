defmodule CortexEx.Users do
  @moduledoc """
  User allowlist and permissions.

  Permission resolution order: config admins (`config :cortex_ex, admins:
  [...]`, immune to lockout and store failures) → ETS cache → store. Store
  errors deny access (fail closed).
  """

  require Logger

  alias CortexEx.Audit
  alias CortexEx.Users.{Cache, Store}

  @type permissions :: :admin | {:member, can_write :: boolean()} | :denied

  @spec config_admins() :: [String.t()]
  def config_admins do
    :cortex_ex
    |> Application.get_env(:admins, [])
    |> Enum.map(&String.downcase/1)
  end

  @spec get_permissions(String.t()) :: permissions()
  def get_permissions(email) when is_binary(email) do
    email = String.downcase(email)

    if email in config_admins() do
      :admin
    else
      case Cache.get(email) do
        {:ok, perms} ->
          perms

        :miss ->
          perms = lookup(email)
          Cache.put(email, perms)
          perms
      end
    end
  end

  def get_permissions(_), do: :denied

  @doc "All users: config admins (locked) first, then stored users."
  @spec list_users() :: [map()]
  def list_users do
    stored =
      case Store.impl() do
        nil ->
          []

        store ->
          case store.list_users() do
            {:ok, users} -> users
            {:error, reason} -> warn_store(reason) && []
          end
      end

    config =
      Enum.map(config_admins(), fn email ->
        %{email: email, role: "admin", can_write: true, inserted_by: "config", inserted_at: nil, source: :config}
      end)

    config ++ Enum.map(stored, &Map.put(&1, :source, :db))
  end

  @spec add_user(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def add_user(attrs, actor) do
    email = attrs |> fetch_email() |> String.downcase()

    with :ok <- refuse_config_admin(email),
         {:ok, store} <- require_store(),
         {:ok, user} <- store.insert_user(Map.put(attrs, :email, email)) do
      Cache.invalidate(email)
      Audit.admin_action(actor, "user_added", %{email: email, role: user.role, can_write: user.can_write})
      {:ok, user}
    end
  end

  @spec set_can_write(String.t(), boolean(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_can_write(email, can_write, actor) when is_boolean(can_write) do
    update_stored(email, %{can_write: can_write}, actor, "permission_changed", %{can_write: can_write})
  end

  @spec set_role(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_role(email, role, actor) when role in ["member", "admin"] do
    update_stored(email, %{role: role}, actor, "role_changed", %{role: role})
  end

  @spec remove_user(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_user(email, actor) do
    email = String.downcase(email)

    with :ok <- refuse_config_admin(email),
         {:ok, store} <- require_store(),
         :ok <- store.delete_user(email) do
      Cache.invalidate(email)
      Audit.admin_action(actor, "user_removed", %{email: email})
      :ok
    end
  end

  defp update_stored(email, attrs, actor, action, metadata) do
    email = String.downcase(email)

    with :ok <- refuse_config_admin(email),
         {:ok, store} <- require_store(),
         {:ok, user} <- store.update_user(email, attrs) do
      Cache.invalidate(email)
      Audit.admin_action(actor, action, Map.put(metadata, :email, email))
      {:ok, user}
    end
  end

  defp lookup(email) do
    case Store.impl() do
      nil ->
        :denied

      store ->
        case store.get_user(email) do
          {:ok, nil} -> :denied
          {:ok, %{role: "admin"}} -> :admin
          {:ok, %{can_write: can_write}} -> {:member, can_write}
          {:error, reason} -> warn_store(reason) && :denied
        end
    end
  end

  defp refuse_config_admin(email) do
    if email in config_admins(), do: {:error, :config_admin_immutable}, else: :ok
  end

  defp require_store do
    case Store.impl() do
      nil -> {:error, :no_store_configured}
      store -> {:ok, store}
    end
  end

  defp fetch_email(attrs) do
    attrs[:email] || attrs["email"] || raise ArgumentError, "email is required"
  end

  defp warn_store(reason) do
    Logger.warning("CortexEx.Users: store error, failing closed: #{inspect(reason)}")
    true
  end
end
