if Code.ensure_loaded?(Ecto.Schema) do
  defmodule CortexEx.Audit.Entry do
    @moduledoc false

    use Ecto.Schema

    schema "cortex_ex_audit_log" do
      field :actor_email, :string
      field :action, :string
      field :tool_name, :string
      field :args, :map
      field :result_status, :string
      field :metadata, :map

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end
  end
end
