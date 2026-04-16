defmodule CortexEx.MCP.Tools.Hex do
  @moduledoc false

  @search_endpoint "https://search.hexdocs.pm/"

  def tools do
    [
      %{
        name: "search_hex_docs",
        description: """
        Searches the HexDocs documentation index (https://search.hexdocs.pm/)
        for the given query. By default, results are filtered to packages present
        in the project's dependencies. Tidewave-compatible.
        """,
        inputSchema: %{
          type: "object",
          required: ["q"],
          properties: %{
            q: %{
              type: "string",
              description: "Search query"
            },
            packages: %{
              type: "array",
              items: %{type: "string"},
              description:
                "Optional list of package names to restrict the search to. If omitted, uses project deps."
            }
          }
        },
        callback: &search_hex_docs/1
      }
    ]
  end

  def search_hex_docs(%{"q" => query} = args) when is_binary(query) and query != "" do
    packages = Map.get(args, "packages", [])
    filter = build_filter(packages)

    url =
      @search_endpoint <>
        "?q=" <>
        URI.encode(query) <>
        "&query_by=doc,title&filter_by=" <> URI.encode(filter)

    ensure_inets_started()

    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 10_000}], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        handle_response(to_string(body))

      {:ok, {{_, status, _}, _, body}} ->
        {:error, "HexDocs search returned HTTP #{status}: #{to_string(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "search_hex_docs failed: #{Exception.message(e)}"}
  end

  def search_hex_docs(_), do: {:error, "q parameter is required"}

  defp handle_response(body) do
    case Jason.decode(body) do
      {:ok, %{"hits" => hits, "found" => found}} ->
        {:ok, format_results(found, hits)}

      {:ok, %{"hits" => hits}} ->
        {:ok, format_results(length(hits), hits)}

      {:ok, other} ->
        {:error, "Unexpected response shape: #{inspect(other)}"}

      {:error, reason} ->
        {:error, "Failed to parse response: #{inspect(reason)}"}
    end
  end

  defp format_results(found, hits) do
    header = "Found #{found} result(s)\n\n"

    body =
      hits
      |> Enum.take(25)
      |> Enum.map_join("\n\n", &format_hit/1)

    header <> body
  end

  defp format_hit(%{"document" => doc}) do
    title = Map.get(doc, "title", "(no title)")
    package = Map.get(doc, "package", "?")
    ref = Map.get(doc, "ref", "")
    type = Map.get(doc, "type", "")
    snippet = Map.get(doc, "doc", "") |> truncate(200)

    "## #{title} (#{package})\n" <>
      "Type: #{type}\n" <>
      (if ref == "", do: "", else: "Ref: #{ref}\n") <>
      "\n#{snippet}"
  end

  defp format_hit(hit), do: inspect(hit)

  defp truncate(str, len) when is_binary(str) do
    if String.length(str) > len do
      String.slice(str, 0, len) <> "..."
    else
      str
    end
  end

  defp truncate(_, _), do: ""

  defp build_filter([]) do
    deps = get_deps_list()

    if deps == [] do
      ""
    else
      "package:=[#{Enum.join(deps, ", ")}]"
    end
  end

  defp build_filter(packages) when is_list(packages) do
    "package:=[#{Enum.join(packages, ", ")}]"
  end

  defp get_deps_list do
    Mix.Project.deps_paths()
    |> Map.keys()
    |> Enum.map(&to_string/1)
  rescue
    _ -> []
  end

  defp ensure_inets_started do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    :ok
  end
end
