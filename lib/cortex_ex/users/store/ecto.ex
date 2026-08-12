if Code.ensure_loaded?(Ecto.Schema) do
  defmodule CortexEx.Users.Store.Ecto do
    @moduledoc false

    @behaviour CortexEx.Users.Store

    import Ecto.Query, only: [from: 2]

    alias CortexEx.Audit.Entry
    alias CortexEx.Users.User

    @impl true
    def list_users do
      users = repo!().all(from(u in User, order_by: u.email))
      {:ok, Enum.map(users, &to_map/1)}
    rescue
      e -> store_error(e)
    end

    @impl true
    def get_user(email) do
      case repo!().get_by(User, email: email) do
        nil -> {:ok, nil}
        user -> {:ok, to_map(user)}
      end
    rescue
      e -> store_error(e)
    end

    @impl true
    def insert_user(attrs) do
      case repo!().insert(User.changeset(%User{}, attrs)) do
        {:ok, user} -> {:ok, to_map(user)}
        {:error, changeset} -> {:error, changeset_errors(changeset)}
      end
    rescue
      e -> store_error(e)
    end

    @impl true
    def update_user(email, attrs) do
      case repo!().get_by(User, email: email) do
        nil ->
          {:error, :not_found}

        user ->
          case repo!().update(User.changeset(user, attrs)) do
            {:ok, user} -> {:ok, to_map(user)}
            {:error, changeset} -> {:error, changeset_errors(changeset)}
          end
      end
    rescue
      e -> store_error(e)
    end

    @impl true
    def delete_user(email) do
      case repo!().get_by(User, email: email) do
        nil -> {:error, :not_found}
        user -> repo!().delete(user) |> then(fn _ -> :ok end)
      end
    rescue
      e -> store_error(e)
    end

    @impl true
    def insert_audit(entry) do
      repo!().insert_all(Entry, [entry])
      :ok
    rescue
      e -> store_error(e)
    end

    @impl true
    def insert_audit_batch(entries) do
      repo!().insert_all(Entry, entries)
      :ok
    rescue
      e -> store_error(e)
    end

    defp repo! do
      Application.get_env(:cortex_ex, :repo) ||
        raise "CortexEx: no :repo configured — set `config :cortex_ex, repo: MyApp.Repo`"
    end

    defp to_map(%User{} = user) do
      %{
        email: user.email,
        role: user.role,
        can_write: user.can_write,
        inserted_by: user.inserted_by,
        inserted_at: user.inserted_at
      }
    end

    defp changeset_errors(changeset) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    end

    defp store_error(exception) do
      {:error, {:store_unavailable, Exception.message(exception)}}
    end
  end
end
