defmodule CortexEx.MCP.Tools.Ecto do
  @moduledoc false

  def tools do
    if ecto_available?() do
      [
        %{
          name: "ecto_schemas",
          description: """
          Lists all Ecto schema modules with their fields, types, and associations.
          Returns detailed schema information including field types, primary keys,
          associations (has_many, belongs_to, has_one), and source table name.
          """,
          inputSchema: %{type: "object", properties: %{}},
          callback: &ecto_schemas/1
        }
      ]
    else
      []
    end
  end

  def ecto_schemas(_args) do
    schemas =
      project_modules()
      |> Enum.filter(&ecto_schema?/1)
      |> Enum.map(&schema_info/1)

    case schemas do
      [] -> {:error, "No Ecto schemas found"}
      _ -> {:ok, Jason.encode!(schemas, pretty: true)}
    end
  rescue
    e -> {:error, "ecto_schemas failed: #{Exception.message(e)}"}
  end

  defp ecto_schema?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1)
  end

  defp schema_info(module) do
    fields =
      module.__schema__(:fields)
      |> Enum.map(fn field ->
        %{name: field, type: inspect(module.__schema__(:type, field))}
      end)

    associations =
      module.__schema__(:associations)
      |> Enum.map(fn assoc ->
        info = module.__schema__(:association, assoc)

        %{
          name: assoc,
          type: assoc_type(info),
          related: inspect(info.related)
        }
      end)

    %{
      module: inspect(module),
      source: module.__schema__(:source),
      primary_key: module.__schema__(:primary_key),
      fields: fields,
      associations: associations
    }
  end

  defp assoc_type(%{cardinality: :one, relationship: :parent}), do: "belongs_to"
  defp assoc_type(%{cardinality: :one}), do: "has_one"
  defp assoc_type(%{cardinality: :many}), do: "has_many"
  defp assoc_type(_), do: "unknown"

  defp ecto_available? do
    Code.ensure_loaded?(Ecto.Schema)
  end

  defp project_modules do
    app = Mix.Project.config()[:app]
    Application.load(app)
    {:ok, modules} = :application.get_key(app, :modules)
    modules
  rescue
    _ -> []
  end
end
