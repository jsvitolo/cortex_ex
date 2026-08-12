if Code.ensure_loaded?(Ecto.Schema) do
  defmodule CortexEx.Users.User do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    schema "cortex_ex_users" do
      field :email, :string
      field :role, :string, default: "member"
      field :can_write, :boolean, default: false
      field :inserted_by, :string

      timestamps(type: :utc_datetime_usec)
    end

    def changeset(user, attrs) do
      user
      |> cast(attrs, [:email, :role, :can_write, :inserted_by])
      |> update_change(:email, &String.downcase/1)
      |> validate_required([:email])
      |> validate_format(:email, ~r/@/)
      |> validate_inclusion(:role, ["member", "admin"])
      |> unique_constraint(:email)
    end
  end
end
