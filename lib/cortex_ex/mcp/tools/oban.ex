defmodule CortexEx.MCP.Tools.Oban do
  @moduledoc false

  def tools do
    if oban_available?() do
      [
        %{
          name: "oban_queues",
          description: """
          Lists configured Oban queues with their concurrency limits.
          Only available when Oban is installed and configured in the host application.
          """,
          inputSchema: %{type: "object", properties: %{}},
          callback: &oban_queues/1
        },
        %{
          name: "oban_workers",
          description: """
          Lists Oban worker modules found in the project.
          Detects modules that implement the Oban.Worker behaviour (have a perform/1 function).
          """,
          inputSchema: %{type: "object", properties: %{}},
          callback: &oban_workers/1
        },
        %{
          name: "failed_jobs",
          description: """
          Returns recently failed/discarded Oban jobs with error details.
          Includes: id, worker, queue, args, errors, and attempted_at timestamp.
          """,
          inputSchema: %{
            type: "object",
            properties: %{
              limit: %{
                type: "integer",
                description: "Maximum number of failed jobs to return (default: 20)"
              }
            }
          },
          callback: &failed_jobs/1
        },
        %{
          name: "retry_job",
          description: """
          Retries a failed Oban job by its ID. The job will be re-enqueued for processing.
          """,
          inputSchema: %{
            type: "object",
            required: ["id"],
            properties: %{
              id: %{
                type: "integer",
                description: "The Oban job ID to retry"
              }
            }
          },
          callback: &retry_job/1
        }
      ]
    else
      []
    end
  end

  # ── oban_queues ───────────────────────────────────────────────

  def oban_queues(_args) do
    if not oban_available?() do
      {:error, "Oban is not available in this application"}
    else
      config = apply(Oban, :config, [])

      queues =
        case Map.get(config, :queues, []) do
          queues when is_list(queues) ->
            Enum.map(queues, fn
              {name, limit} when is_integer(limit) ->
                %{name: to_string(name), limit: limit}

              {name, opts} when is_list(opts) ->
                %{name: to_string(name), limit: Keyword.get(opts, :limit, "unknown"), opts: inspect(opts)}

              other ->
                %{name: inspect(other), limit: "unknown"}
            end)

          _ ->
            []
        end

      {:ok, Jason.encode!(queues, pretty: true)}
    end
  rescue
    e -> {:error, "oban_queues failed: #{Exception.message(e)}"}
  end

  # ── oban_workers ──────────────────────────────────────────────

  def oban_workers(_args) do
    if not oban_available?() do
      {:error, "Oban is not available in this application"}
    else
      workers =
        :code.all_loaded()
        |> Enum.filter(fn {mod, _} -> is_oban_worker?(mod) end)
        |> Enum.map(fn {mod, _} ->
          %{
            module: inspect(mod),
            has_perform: function_exported?(mod, :perform, 1)
          }
        end)
        |> Enum.sort_by(& &1.module)

      {:ok, Jason.encode!(workers, pretty: true)}
    end
  rescue
    e -> {:error, "oban_workers failed: #{Exception.message(e)}"}
  end

  # ── failed_jobs ───────────────────────────────────────────────

  def failed_jobs(args) do
    if not oban_available?() do
      {:error, "Oban is not available in this application"}
    else
      if not repo_available?() do
        {:error, "No Ecto repo available to query Oban jobs"}
      else
        limit = Map.get(args, "limit", 20)
        repo = get_repo()

        import Ecto.Query, only: [from: 2]

        jobs =
          from(j in oban_job_schema(),
            where: j.state in ["discarded", "retryable"],
            order_by: [desc: j.attempted_at],
            limit: ^limit,
            select: %{
              id: j.id,
              worker: j.worker,
              queue: j.queue,
              args: j.args,
              errors: j.errors,
              state: j.state,
              attempted_at: j.attempted_at,
              attempt: j.attempt,
              max_attempts: j.max_attempts
            }
          )
          |> repo.all()
          |> Enum.map(fn job ->
            Map.update(job, :attempted_at, nil, fn
              nil -> nil
              dt -> to_string(dt)
            end)
          end)

        {:ok, Jason.encode!(jobs, pretty: true)}
      end
    end
  rescue
    e -> {:error, "failed_jobs failed: #{Exception.message(e)}"}
  end

  # ── retry_job ─────────────────────────────────────────────────

  def retry_job(%{"id" => id}) when is_integer(id) do
    if not oban_available?() do
      {:error, "Oban is not available in this application"}
    else
      case apply(Oban, :retry_job, [id]) do
        :ok ->
          {:ok, Jason.encode!(%{status: "retried", job_id: id}, pretty: true)}

        {:error, reason} ->
          {:error, "Failed to retry job #{id}: #{inspect(reason)}"}
      end
    end
  rescue
    e -> {:error, "retry_job failed: #{Exception.message(e)}"}
  end

  def retry_job(%{"id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> retry_job(%{"id" => int_id})
      _ -> {:error, "Invalid job ID: #{id}. Must be an integer."}
    end
  end

  def retry_job(_), do: {:error, "id parameter is required"}

  # ── Helpers ───────────────────────────────────────────────────

  defp oban_available? do
    Code.ensure_loaded?(Oban)
  end

  defp repo_available? do
    get_repo() != nil
  end

  defp get_repo do
    # Try to find the repo from Oban config or common patterns
    if oban_available?() do
      try do
        config = apply(Oban, :config, [])
        Map.get(config, :repo)
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end
  end

  defp oban_job_schema do
    if Code.ensure_loaded?(Oban.Job), do: Oban.Job, else: nil
  end

  defp is_oban_worker?(mod) do
    Code.ensure_loaded?(mod) &&
      function_exported?(mod, :perform, 1) &&
      has_oban_behaviour?(mod)
  end

  defp has_oban_behaviour?(mod) do
    if Code.ensure_loaded?(Oban.Worker) do
      behaviours = mod.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
      Oban.Worker in behaviours
    else
      false
    end
  rescue
    _ -> false
  end
end
