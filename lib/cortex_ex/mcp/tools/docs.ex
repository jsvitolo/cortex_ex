defmodule CortexEx.MCP.Tools.Docs do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_docs",
        description: """
        Returns the documentation for a given Elixir module or function.
        Works for project modules and dependencies. Uses the exact versions in the project.
        Reference format: "Module", "Module.function", or "Module.function/arity".
        """,
        inputSchema: %{
          type: "object",
          required: ["reference"],
          properties: %{
            reference: %{
              type: "string",
              description: "Module, Module.function, or Module.function/arity"
            }
          }
        },
        callback: &get_docs/1
      }
    ]
  end

  def get_docs(%{"reference" => ref}) do
    case parse_reference(ref) do
      {:ok, mod, nil, _} ->
        get_module_docs(mod)

      {:ok, mod, fun, arity} ->
        get_function_docs(mod, fun, arity)

      :error ->
        {:error, "Could not parse reference: #{ref}"}
    end
  end

  def get_docs(_), do: {:error, "reference parameter is required"}

  defp get_module_docs(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, "text/markdown", %{"en" => content}, _, _} ->
        {:ok, "# #{inspect(mod)}\n\n#{content}"}

      _ ->
        {:error, "No documentation found for #{inspect(mod)}"}
    end
  end

  defp get_function_docs(mod, fun, arity) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, "text/markdown", _, _, docs} ->
        matching =
          Enum.filter(docs, fn
            {{kind, ^fun, a}, _, _, %{"en" => _}, _} when kind in [:function, :macro] ->
              arity == :any or a == arity

            _ ->
              false
          end)

        case matching do
          [] ->
            {:error, "No docs found for #{inspect(mod)}.#{fun}/#{arity}"}

          docs ->
            formatted = Enum.map_join(docs, "\n\n---\n\n", &format_doc(mod, &1))
            {:ok, formatted}
        end

      _ ->
        {:error, "No documentation available for #{inspect(mod)}"}
    end
  end

  defp format_doc(mod, {{_kind, fun, arity}, _, signatures, %{"en" => content}, _}) do
    sig = Enum.join(signatures, "\n")
    "## #{inspect(mod)}.#{fun}/#{arity}\n\n```elixir\n#{sig}\n```\n\n#{content}"
  end

  defp parse_reference(ref) do
    case Code.string_to_quoted(ref) do
      {:ok, {:/, _, [call, arity]}} when is_integer(arity) ->
        parse_call(call, arity)

      {:ok, call} ->
        parse_call(call, :any)

      _ ->
        :error
    end
  end

  defp parse_call({{:., _, [mod, fun]}, _, _}, arity), do: parse_mod(mod, fun, arity)
  defp parse_call(mod, :any), do: parse_mod(mod, nil, :any)
  defp parse_call(_, _), do: :error

  defp parse_mod({:__aliases__, _, parts}, fun, arity),
    do: {:ok, Module.concat(parts), fun, arity}

  defp parse_mod(mod, fun, arity) when is_atom(mod), do: {:ok, mod, fun, arity}
  defp parse_mod(_, _, _), do: :error
end
