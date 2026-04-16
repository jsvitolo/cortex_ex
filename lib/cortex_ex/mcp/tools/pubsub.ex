defmodule CortexEx.MCP.Tools.PubSub do
  @moduledoc false

  def tools do
    if pubsub_available?() do
      [
        %{
          name: "pubsub_topology",
          description: """
          Lists Phoenix.PubSub topics with their subscribers.
          Each entry includes: topic, pubsub (server name), subscriber_count, and subscribers (pids).
          Only available when Phoenix.PubSub is loaded.
          """,
          inputSchema: %{
            type: "object",
            properties: %{
              pubsub: %{
                type: "string",
                description:
                  "Optional: filter to a specific PubSub server name (e.g. 'MyApp.PubSub')"
              }
            }
          },
          callback: &pubsub_topology/1
        }
      ]
    else
      []
    end
  end

  # ── pubsub_topology ───────────────────────────────────────────

  def pubsub_topology(args) do
    if not pubsub_available?() do
      {:error, "Phoenix.PubSub is not available in this application"}
    else
      filter = Map.get(args, "pubsub")
      pubsubs = discover_pubsubs()

      pubsubs =
        case filter do
          nil -> pubsubs
          name -> Enum.filter(pubsubs, fn p -> to_string(p) == name end)
        end

      result =
        pubsubs
        |> Enum.flat_map(&extract_topics/1)
        |> Enum.sort_by(& &1.topic)

      {:ok, Jason.encode!(result, pretty: true)}
    end
  rescue
    e -> {:error, "pubsub_topology failed: #{Exception.message(e)}"}
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp pubsub_available? do
    Code.ensure_loaded?(Phoenix.PubSub)
  end

  # Discover PubSub instances. Phoenix.PubSub backed by Registry uses a Registry
  # named `<pubsub_name>`. We iterate registered processes and pick the ones
  # whose names look like PubSub servers (registered process + has :pg or Registry).
  defp discover_pubsubs do
    Process.registered()
    |> Enum.filter(&pubsub_process?/1)
  end

  defp pubsub_process?(name) when is_atom(name) do
    # Heuristics: name contains "PubSub" or the process has Phoenix.PubSub dict entry.
    name_str = to_string(name) |> String.replace("Elixir.", "")

    cond do
      String.contains?(name_str, "PubSub") and not String.contains?(name_str, "Adapter") ->
        pid = Process.whereis(name)
        pid != nil and Process.alive?(pid) and has_registry?(name)

      true ->
        false
    end
  rescue
    _ -> false
  end

  defp has_registry?(name) do
    try do
      case Registry.meta(name, :pubsub) do
        {:ok, _} -> true
        :error -> false
      end
    rescue
      ArgumentError -> false
      _ -> false
    catch
      _, _ -> false
    end
  end

  # Extract topics + subscribers from a PubSub server by walking its Registry.
  defp extract_topics(pubsub_name) do
    try do
      # Phoenix.PubSub.PG2 / PG use a Registry named identically to the pubsub.
      # Registry entries are keyed by topic. Use Registry.select/2 to enumerate.
      guard_spec = [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}]

      entries =
        try do
          Registry.select(pubsub_name, guard_spec)
        rescue
          _ -> []
        catch
          _, _ -> []
        end

      entries
      |> Enum.group_by(fn {topic, _pid} -> topic end, fn {_topic, pid} -> pid end)
      |> Enum.map(fn {topic, pids} ->
        uniq_pids = Enum.uniq(pids)

        %{
          topic: to_string(topic),
          pubsub: to_string(pubsub_name) |> String.replace("Elixir.", ""),
          subscriber_count: length(uniq_pids),
          subscribers: Enum.map(uniq_pids, &inspect/1)
        }
      end)
    rescue
      _ -> []
    catch
      _, _ -> []
    end
  end
end
