defmodule CortexEx.Users.Store do
  @moduledoc """
  Storage behaviour for users and audit entries. Users cross this boundary as
  plain maps so callers never depend on Ecto.

  The implementation is picked from config: an explicit `:store` module wins,
  then the Ecto store when a `:repo` is configured, otherwise no store
  (config admins still work; everyone else is denied).
  """

  @type user :: %{
          email: String.t(),
          role: String.t(),
          can_write: boolean(),
          inserted_by: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @callback list_users() :: {:ok, [user()]} | {:error, term()}
  @callback get_user(email :: String.t()) :: {:ok, user() | nil} | {:error, term()}
  @callback insert_user(attrs :: map()) :: {:ok, user()} | {:error, term()}
  @callback update_user(email :: String.t(), attrs :: map()) :: {:ok, user()} | {:error, term()}
  @callback delete_user(email :: String.t()) :: :ok | {:error, term()}
  @callback insert_audit(entry :: map()) :: :ok | {:error, term()}
  @callback insert_audit_batch(entries :: [map()]) :: :ok | {:error, term()}

  @spec impl() :: module() | nil
  def impl do
    cond do
      store = Application.get_env(:cortex_ex, :store) ->
        store

      Application.get_env(:cortex_ex, :repo) != nil and
          Code.ensure_loaded?(CortexEx.Users.Store.Ecto) ->
        CortexEx.Users.Store.Ecto

      true ->
        nil
    end
  end
end
