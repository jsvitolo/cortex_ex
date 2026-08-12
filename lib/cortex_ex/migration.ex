if Code.ensure_loaded?(Ecto.Migration) do
  defmodule CortexEx.Migration do
    @moduledoc """
    Migrations for the tables cortex_ex needs in the host app's database.

    Create a migration in the host app:

        defmodule MyApp.Repo.Migrations.AddCortexEx do
          use Ecto.Migration

          def up, do: CortexEx.Migration.up()
          def down, do: CortexEx.Migration.down()
        end

    Accepts `prefix: "schema_name"` on both `up/1` and `down/1`.
    """

    @current_version 1

    def up(opts \\ []), do: CortexEx.Migrations.V01.up(opts)

    def down(opts \\ []), do: CortexEx.Migrations.V01.down(opts)

    def migrated_version, do: @current_version
  end
end
