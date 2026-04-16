defmodule CortexEx.MCP.Tools.Migrations do
  @moduledoc false

  def tools do
    if ecto_available?() do
      [
        %{
          name: "plan_migration",
          description: """
          Given an Ecto schema module, returns a suggested migration template
          that creates the corresponding table with the schema's fields and types.
          Useful for bootstrapping migrations from an already-defined schema.
          """,
          inputSchema: %{
            type: "object",
            required: ["schema"],
            properties: %{
              schema: %{
                type: "string",
                description:
                  "Fully qualified schema module name (e.g., 'MyApp.Accounts.User')"
              }
            }
          },
          callback: &plan_migration/1
        }
      ]
    else
      []
    end
  end

  def plan_migration(%{"schema" => schema_str}) when is_binary(schema_str) do
    module = parse_module(schema_str)

    cond do
      not Code.ensure_loaded?(module) ->
        {:error, "Schema module not found: #{schema_str}"}

      not function_exported?(module, :__schema__, 1) ->
        {:error, "Module is not an Ecto schema: #{schema_str}"}

      true ->
        build_plan(module)
    end
  rescue
    e -> {:error, "plan_migration failed: #{Exception.message(e)}"}
  end

  def plan_migration(_), do: {:error, "schema parameter is required"}

  defp build_plan(module) do
    source = module.__schema__(:source)
    fields = module.__schema__(:fields)
    pk_fields = module.__schema__(:primary_key)

    # Exclude primary key (id) and timestamps from adds
    excluded = Enum.concat(pk_fields, [:inserted_at, :updated_at])
    addable = Enum.reject(fields, &(&1 in excluded))

    types =
      Enum.map(addable, fn field ->
        {field, module.__schema__(:type, field)}
      end)

    migration = build_migration_template(source, types, pk_fields)
    {:ok, migration}
  end

  @doc """
  Builds a migration template string for the given table/fields/primary_key.
  Exposed for testability.
  """
  def build_migration_template(source, fields, _pk) do
    module_name = Macro.camelize(source)

    field_lines =
      Enum.map_join(fields, "\n", fn {name, type} ->
        "      add :#{name}, :#{elixir_type_to_ecto(type)}"
      end)

    """
    # Suggested migration for #{source}

    ```elixir
    defmodule MyApp.Repo.Migrations.Create#{module_name} do
      use Ecto.Migration

      def change do
        create table(:#{source}) do
    #{field_lines}

          timestamps()
        end
      end
    end
    ```
    """
  end

  @doc """
  Maps an Ecto field type atom to its migration type string.
  """
  def elixir_type_to_ecto(:id), do: "integer"
  def elixir_type_to_ecto(:integer), do: "integer"
  def elixir_type_to_ecto(:float), do: "float"
  def elixir_type_to_ecto(:decimal), do: "decimal"
  def elixir_type_to_ecto(:string), do: "string"
  def elixir_type_to_ecto(:binary), do: "binary"
  def elixir_type_to_ecto(:boolean), do: "boolean"
  def elixir_type_to_ecto(:date), do: "date"
  def elixir_type_to_ecto(:time), do: "time"
  def elixir_type_to_ecto(:naive_datetime), do: "naive_datetime"
  def elixir_type_to_ecto(:utc_datetime), do: "utc_datetime"
  def elixir_type_to_ecto(:utc_datetime_usec), do: "utc_datetime_usec"
  def elixir_type_to_ecto(:binary_id), do: "binary_id"
  def elixir_type_to_ecto(:map), do: "map"
  def elixir_type_to_ecto({:array, _inner}), do: "array"
  def elixir_type_to_ecto({:parameterized, _, _}), do: "string"
  def elixir_type_to_ecto(type) when is_atom(type), do: Atom.to_string(type)
  def elixir_type_to_ecto(type), do: inspect(type)

  defp parse_module(str) do
    parts = String.split(str, ".")
    Module.concat(parts)
  end

  defp ecto_available? do
    Code.ensure_loaded?(Ecto.Schema)
  end
end
