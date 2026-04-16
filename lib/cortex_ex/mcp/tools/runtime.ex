defmodule CortexEx.MCP.Tools.Runtime do
  @moduledoc false

  def tools do
    [
      %{
        name: "supervision_tree",
        description: """
        Returns the supervision tree of the running application as nested JSON.
        For each process: name, module, pid, status (alive/dead), and child count.
        Walks the tree recursively starting from the application's main supervisor.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            supervisor: %{
              type: "string",
              description:
                "Supervisor module name to start from (default: auto-detected application supervisor)"
            }
          }
        },
        callback: &supervision_tree/1
      },
      %{
        name: "process_info",
        description: """
        Returns detailed information about a specific process by PID string.
        Includes: current_function, message_queue_len, memory, status, registered_name, links.
        """,
        inputSchema: %{
          type: "object",
          required: ["pid"],
          properties: %{
            pid: %{
              type: "string",
              description:
                "PID string (e.g., '#PID<0.123.0>' or '0.123.0')"
            }
          }
        },
        callback: &process_info/1
      },
      %{
        name: "genserver_state",
        description: """
        Returns the internal state of a running GenServer by registered name or module name.
        Uses :sys.get_state/2 with a timeout. State is inspected and truncated if large.
        """,
        inputSchema: %{
          type: "object",
          required: ["name"],
          properties: %{
            name: %{
              type: "string",
              description:
                "Registered name or module name of the GenServer (e.g., 'CortexEx.ErrorTracker')"
            },
            timeout: %{
              type: "integer",
              description: "Timeout in milliseconds (default: 5000)"
            }
          }
        },
        callback: &genserver_state/1
      },
      %{
        name: "ets_tables",
        description: """
        Lists all ETS tables in the system with metadata:
        name, type, size (number of objects), memory (words), owner PID, and protection level.
        """,
        inputSchema: %{type: "object", properties: %{}},
        callback: &ets_tables/1
      },
      %{
        name: "ets_lookup",
        description: """
        Looks up a key in a named ETS table and returns the matching entries.
        The key is matched as a string or atom depending on what the table uses.
        """,
        inputSchema: %{
          type: "object",
          required: ["table", "key"],
          properties: %{
            table: %{
              type: "string",
              description: "ETS table name (e.g., 'my_cache')"
            },
            key: %{
              type: "string",
              description: "Key to look up in the table"
            }
          }
        },
        callback: &ets_lookup/1
      },
      %{
        name: "get_config",
        description: """
        Returns application configuration for an OTP app.
        If a key is provided, returns only that specific config value.
        Sensitive values (password, secret, token, key) are automatically masked.
        """,
        inputSchema: %{
          type: "object",
          required: ["app"],
          properties: %{
            app: %{
              type: "string",
              description: "OTP application name (e.g., 'my_app', 'phoenix')"
            },
            key: %{
              type: "string",
              description: "Specific config key to retrieve (optional, returns all if omitted)"
            }
          }
        },
        callback: &get_config/1
      }
    ]
  end

  # ── supervision_tree ──────────────────────────────────────────

  def supervision_tree(args) do
    supervisor = resolve_supervisor(Map.get(args, "supervisor"))
    tree = walk_supervisor(supervisor)
    {:ok, Jason.encode!(tree, pretty: true)}
  rescue
    e -> {:error, "supervision_tree failed: #{Exception.message(e)}"}
  end

  defp resolve_supervisor(nil) do
    # Auto-detect: try the host app's supervisor first, fallback to CortexEx.Supervisor
    case find_app_supervisor() do
      nil -> CortexEx.Supervisor
      sup -> sup
    end
  end

  defp resolve_supervisor(name) do
    case safe_string_to_module(name) do
      nil -> CortexEx.Supervisor
      mod -> mod
    end
  end

  defp find_app_supervisor do
    # Look through loaded applications for the main app supervisor
    # Skip known OTP/library apps
    skip = ~w(kernel stdlib elixir cortex_ex logger compiler)a

    Application.loaded_applications()
    |> Enum.reject(fn {app, _, _} -> app in skip end)
    |> Enum.find_value(fn {app, _, _} ->
      case Application.get_env(app, :mod) do
        {_mod, _args} ->
          # Try to find the supervisor by convention: AppName.Supervisor
          sup_mod =
            app
            |> to_string()
            |> Macro.camelize()
            |> then(&Module.concat([&1, "Supervisor"]))

          if process_alive?(sup_mod), do: sup_mod, else: nil

        _ ->
          nil
      end
    end)
  end

  defp process_alive?(name) do
    case Process.whereis(name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp walk_supervisor(supervisor) do
    pid = resolve_pid(supervisor)

    case pid do
      nil ->
        %{name: inspect(supervisor), error: "Process not found"}

      pid ->
        children =
          try do
            Supervisor.which_children(pid)
          rescue
            _ -> []
          catch
            :exit, _ -> []
          end

        child_nodes =
          Enum.map(children, fn {id, child_pid, type, modules} ->
            child_info = %{
              id: format_id(id),
              type: to_string(type),
              modules: Enum.map(modules, &inspect/1)
            }

            case {child_pid, type} do
              {:undefined, _} ->
                Map.merge(child_info, %{
                  pid: nil,
                  status: "dead",
                  children: [],
                  child_count: 0
                })

              {pid, :supervisor} when is_pid(pid) ->
                sub_tree = walk_supervisor(pid)

                Map.merge(child_info, %{
                  pid: inspect(pid),
                  status: if(Process.alive?(pid), do: "alive", else: "dead"),
                  children: Map.get(sub_tree, :children, []),
                  child_count: Map.get(sub_tree, :child_count, 0)
                })

              {pid, _worker} when is_pid(pid) ->
                Map.merge(child_info, %{
                  pid: inspect(pid),
                  status: if(Process.alive?(pid), do: "alive", else: "dead"),
                  children: [],
                  child_count: 0
                })

              _ ->
                Map.merge(child_info, %{
                  pid: nil,
                  status: "unknown",
                  children: [],
                  child_count: 0
                })
            end
          end)

        %{
          name: inspect(supervisor),
          pid: inspect(pid),
          status: if(Process.alive?(pid), do: "alive", else: "dead"),
          children: child_nodes,
          child_count: length(child_nodes)
        }
    end
  end

  defp resolve_pid(pid) when is_pid(pid), do: pid

  defp resolve_pid(name) when is_atom(name) do
    Process.whereis(name)
  end

  defp resolve_pid(_), do: nil

  defp format_id(id) when is_atom(id), do: inspect(id)
  defp format_id(id), do: inspect(id)

  # ── process_info ──────────────────────────────────────────────

  def process_info(%{"pid" => pid_string}) do
    case parse_pid(pid_string) do
      nil ->
        {:error, "Invalid PID format: #{pid_string}. Use '#PID<0.123.0>' or '0.123.0'"}

      pid ->
        info_keys = [
          :current_function,
          :message_queue_len,
          :memory,
          :status,
          :registered_name,
          :links,
          :reductions,
          :heap_size,
          :stack_size,
          :total_heap_size
        ]

        case Process.info(pid, info_keys) do
          nil ->
            {:error, "Process #{pid_string} is not alive"}

          info ->
            result =
              info
              |> Enum.into(%{})
              |> Map.update(:current_function, nil, &inspect/1)
              |> Map.update(:links, [], fn links -> Enum.map(links, &inspect/1) end)
              |> Map.update(:registered_name, nil, fn
                [] -> nil
                name -> inspect(name)
              end)
              |> Map.put(:pid, inspect(pid))

            {:ok, Jason.encode!(result, pretty: true)}
        end
    end
  rescue
    e -> {:error, "process_info failed: #{Exception.message(e)}"}
  end

  def process_info(_), do: {:error, "pid parameter is required"}

  defp parse_pid(str) when is_binary(str) do
    # Handle formats: "#PID<0.123.0>", "<0.123.0>", "0.123.0"
    cleaned =
      str
      |> String.replace(~r/^#PID</, "")
      |> String.replace(~r/^</, "")
      |> String.replace(~r/>$/, "")
      |> String.trim()

    case String.split(cleaned, ".") do
      [a, b, c] ->
        with {n1, ""} <- Integer.parse(a),
             {n2, ""} <- Integer.parse(b),
             {n3, ""} <- Integer.parse(c) do
          :erlang.list_to_pid(~c"<#{n1}.#{n2}.#{n3}>")
        else
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # ── genserver_state ───────────────────────────────────────────

  def genserver_state(%{"name" => name} = args) do
    timeout = Map.get(args, "timeout", 5_000)

    case resolve_genserver(name) do
      nil ->
        {:error, "GenServer not found or not running: #{name}"}

      server ->
        state = :sys.get_state(server, timeout)
        inspected = inspect(state, pretty: true, limit: 100, printable_limit: 4096)
        {:ok, inspected}
    end
  rescue
    e -> {:error, "genserver_state failed: #{Exception.message(e)}"}
  catch
    :exit, {:timeout, _} ->
      {:error, "Timeout getting state for #{args["name"]}"}

    :exit, reason ->
      {:error, "Failed to get state: #{inspect(reason)}"}
  end

  def genserver_state(_), do: {:error, "name parameter is required"}

  defp resolve_genserver(name) do
    # Try as module atom first
    case safe_string_to_module(name) do
      nil ->
        # Try as a registered atom name
        try do
          atom = String.to_existing_atom(name)

          case Process.whereis(atom) do
            nil -> nil
            _pid -> atom
          end
        rescue
          _ -> nil
        end

      mod ->
        case Process.whereis(mod) do
          nil -> nil
          _pid -> mod
        end
    end
  end

  # ── ets_tables ────────────────────────────────────────────────

  def ets_tables(_args) do
    tables =
      :ets.all()
      |> Enum.map(fn table ->
        info = :ets.info(table)

        %{
          name: format_ets_name(table),
          type: to_string(info[:type]),
          size: info[:size],
          memory: info[:memory],
          owner: inspect(info[:owner]),
          protection: to_string(info[:protection]),
          named_table: info[:named_table]
        }
      end)
      |> Enum.sort_by(& &1.name)

    {:ok, Jason.encode!(tables, pretty: true)}
  rescue
    e -> {:error, "ets_tables failed: #{Exception.message(e)}"}
  end

  defp format_ets_name(name) when is_atom(name), do: to_string(name)
  defp format_ets_name(ref) when is_reference(ref), do: inspect(ref)
  defp format_ets_name(other), do: inspect(other)

  # ── ets_lookup ────────────────────────────────────────────────

  def ets_lookup(%{"table" => table_name, "key" => key}) do
    table = resolve_ets_table(table_name)

    case table do
      nil ->
        {:error, "ETS table not found: #{table_name}"}

      table ->
        # Try both atom and string keys
        results =
          try do
            :ets.lookup(table, key)
          rescue
            _ -> []
          end

        results =
          if results == [] do
            try do
              atom_key = String.to_existing_atom(key)
              :ets.lookup(table, atom_key)
            rescue
              _ -> []
            end
          else
            results
          end

        inspected = inspect(results, pretty: true, limit: 50, printable_limit: 4096)
        {:ok, inspected}
    end
  rescue
    e -> {:error, "ets_lookup failed: #{Exception.message(e)}"}
  end

  def ets_lookup(%{"table" => _}), do: {:error, "key parameter is required"}
  def ets_lookup(%{"key" => _}), do: {:error, "table parameter is required"}
  def ets_lookup(_), do: {:error, "table and key parameters are required"}

  defp resolve_ets_table(name) do
    # Try as an existing atom name first
    try do
      atom = String.to_existing_atom(name)

      case :ets.info(atom) do
        :undefined -> nil
        _ -> atom
      end
    rescue
      _ -> nil
    end
  end

  # ── get_config ────────────────────────────────────────────────

  def get_config(%{"app" => app_name} = args) do
    app = String.to_existing_atom(app_name)
    key = Map.get(args, "key")

    result =
      if key do
        key_atom = String.to_existing_atom(key)
        value = Application.get_env(app, key_atom)
        mask_sensitive(%{key_atom => value})
      else
        env = Application.get_all_env(app)
        mask_sensitive(Enum.into(env, %{}))
      end

    {:ok, Jason.encode!(stringify_keys(result), pretty: true)}
  rescue
    e -> {:error, "get_config failed: #{Exception.message(e)}"}
  end

  def get_config(_), do: {:error, "app parameter is required"}

  # ── Helpers ───────────────────────────────────────────────────

  @sensitive_patterns ~w(password secret token key api_key private_key credential)

  defp mask_sensitive(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key_str = to_string(k) |> String.downcase()

      if Enum.any?(@sensitive_patterns, &String.contains?(key_str, &1)) do
        {k, "[FILTERED]"}
      else
        {k, mask_sensitive_value(v)}
      end
    end)
  end

  defp mask_sensitive(other), do: other

  defp mask_sensitive_value(map) when is_map(map), do: mask_sensitive(map)

  defp mask_sensitive_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.map(list, fn {k, v} ->
        key_str = to_string(k) |> String.downcase()

        if Enum.any?(@sensitive_patterns, &String.contains?(key_str, &1)) do
          {k, "[FILTERED]"}
        else
          {k, mask_sensitive_value(v)}
        end
      end)
    else
      Enum.map(list, &mask_sensitive_value/1)
    end
  end

  defp mask_sensitive_value(other), do: other

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(map) when is_map(map), do: stringify_keys(map)

  defp stringify_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Map.new(list, fn {k, v} -> {to_string(k), stringify_value(v)} end)
    else
      Enum.map(list, &stringify_value/1)
    end
  end

  defp stringify_value(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    to_string(atom)
  end

  defp stringify_value(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(&stringify_value/1)
  end

  defp stringify_value(pid) when is_pid(pid), do: inspect(pid)
  defp stringify_value(ref) when is_reference(ref), do: inspect(ref)
  defp stringify_value(fun) when is_function(fun), do: inspect(fun)
  defp stringify_value(other), do: other

  defp safe_string_to_module(name) do
    # Try to resolve "Elixir.Foo.Bar" or "Foo.Bar" to an atom
    mod_name =
      if String.starts_with?(name, "Elixir.") do
        name
      else
        "Elixir." <> name
      end

    try do
      mod = String.to_existing_atom(mod_name)

      if Code.ensure_loaded?(mod) do
        mod
      else
        nil
      end
    rescue
      _ -> nil
    end
  end
end
