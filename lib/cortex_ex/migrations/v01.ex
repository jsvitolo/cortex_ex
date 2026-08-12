if Code.ensure_loaded?(Ecto.Migration) do
  defmodule CortexEx.Migrations.V01 do
    @moduledoc false

    use Ecto.Migration

    def up(opts) do
      prefix = opts[:prefix]

      create_if_not_exists table(:cortex_ex_users, prefix: prefix) do
        add :email, :string, null: false
        add :role, :string, null: false, default: "member"
        add :can_write, :boolean, null: false, default: false
        add :inserted_by, :string
        timestamps(type: :utc_datetime_usec)
      end

      create_if_not_exists unique_index(:cortex_ex_users, [:email], prefix: prefix)

      create_if_not_exists table(:cortex_ex_audit_log, prefix: prefix) do
        add :actor_email, :string
        add :action, :string, null: false
        add :tool_name, :string
        add :args, :map
        add :result_status, :string
        add :metadata, :map
        add :inserted_at, :utc_datetime_usec, null: false
      end

      create_if_not_exists index(:cortex_ex_audit_log, [:actor_email], prefix: prefix)
      create_if_not_exists index(:cortex_ex_audit_log, [:inserted_at], prefix: prefix)
      create_if_not_exists index(:cortex_ex_audit_log, [:action], prefix: prefix)
    end

    def down(opts) do
      prefix = opts[:prefix]

      drop_if_exists table(:cortex_ex_audit_log, prefix: prefix)
      drop_if_exists table(:cortex_ex_users, prefix: prefix)
    end
  end
end
