defmodule CortexExV03Test do
  use ExUnit.Case

  # ── Runtime: supervision_tree ────────────────────────────────

  describe "CortexEx.MCP.Tools.Runtime supervision_tree" do
    test "returns the CortexEx supervisor tree" do
      assert {:ok, json} = CortexEx.MCP.Tools.Runtime.supervision_tree(%{})
      assert {:ok, tree} = Jason.decode(json)

      assert tree["name"] =~ "CortexEx.Supervisor"
      assert tree["status"] == "alive"
      assert is_list(tree["children"])
      assert tree["child_count"] > 0

      # Should contain known children
      child_ids = Enum.map(tree["children"], & &1["id"])
      assert Enum.any?(child_ids, &(&1 =~ "ErrorTracker"))
      assert Enum.any?(child_ids, &(&1 =~ "LoggerBackend"))
    end

    test "accepts a specific supervisor name" do
      assert {:ok, json} =
               CortexEx.MCP.Tools.Runtime.supervision_tree(%{"supervisor" => "CortexEx.Supervisor"})

      assert {:ok, tree} = Jason.decode(json)
      assert tree["name"] =~ "CortexEx.Supervisor"
      assert tree["child_count"] > 0
    end

    test "falls back to CortexEx.Supervisor for non-existent supervisor" do
      assert {:ok, json} =
               CortexEx.MCP.Tools.Runtime.supervision_tree(%{
                 "supervisor" => "NonExistent.Supervisor"
               })

      assert {:ok, result} = Jason.decode(json)
      # Falls back to CortexEx.Supervisor since module can't be resolved
      assert result["name"] =~ "CortexEx.Supervisor"
      assert result["status"] == "alive"
    end
  end

  # ── Runtime: process_info ────────────────────────────────────

  describe "CortexEx.MCP.Tools.Runtime process_info" do
    test "returns info for self()" do
      pid_str = inspect(self())
      assert {:ok, json} = CortexEx.MCP.Tools.Runtime.process_info(%{"pid" => pid_str})
      assert {:ok, info} = Jason.decode(json)

      assert Map.has_key?(info, "memory")
      assert Map.has_key?(info, "message_queue_len")
      assert Map.has_key?(info, "status")
      assert Map.has_key?(info, "reductions")
      assert is_integer(info["memory"])
      assert is_integer(info["message_queue_len"])
    end

    test "accepts 0.X.0 format" do
      [_, nums] = Regex.run(~r/<(.+)>/, inspect(self()))
      assert {:ok, json} = CortexEx.MCP.Tools.Runtime.process_info(%{"pid" => nums})
      assert {:ok, _info} = Jason.decode(json)
    end

    test "returns error for dead process" do
      pid = spawn(fn -> :ok end)
      Process.sleep(50)
      pid_str = inspect(pid)
      assert {:error, msg} = CortexEx.MCP.Tools.Runtime.process_info(%{"pid" => pid_str})
      assert msg =~ "not alive"
    end

    test "returns error for invalid pid format" do
      assert {:error, msg} = CortexEx.MCP.Tools.Runtime.process_info(%{"pid" => "invalid"})
      assert msg =~ "Invalid PID format"
    end

    test "requires pid parameter" do
      assert {:error, "pid parameter is required"} =
               CortexEx.MCP.Tools.Runtime.process_info(%{})
    end
  end

  # ── Runtime: genserver_state ─────────────────────────────────

  describe "CortexEx.MCP.Tools.Runtime genserver_state" do
    test "returns state for CortexEx.ErrorTracker" do
      assert {:ok, state} =
               CortexEx.MCP.Tools.Runtime.genserver_state(%{"name" => "CortexEx.ErrorTracker"})

      assert is_binary(state)
      # State should be an inspected Elixir term
      assert String.length(state) > 0
    end

    test "returns error for non-existent GenServer" do
      assert {:error, msg} =
               CortexEx.MCP.Tools.Runtime.genserver_state(%{"name" => "NonExistent.Server"})

      assert msg =~ "not found"
    end

    test "requires name parameter" do
      assert {:error, "name parameter is required"} =
               CortexEx.MCP.Tools.Runtime.genserver_state(%{})
    end
  end

  # ── Runtime: ets_tables ──────────────────────────────────────

  describe "CortexEx.MCP.Tools.Runtime ets_tables" do
    test "lists at least some ETS tables" do
      assert {:ok, json} = CortexEx.MCP.Tools.Runtime.ets_tables(%{})
      assert {:ok, tables} = Jason.decode(json)

      assert is_list(tables)
      assert length(tables) > 0

      # Each table should have expected fields
      table = List.first(tables)
      assert Map.has_key?(table, "name")
      assert Map.has_key?(table, "type")
      assert Map.has_key?(table, "size")
      assert Map.has_key?(table, "memory")
      assert Map.has_key?(table, "owner")
      assert Map.has_key?(table, "protection")
    end
  end

  # ── Runtime: ets_lookup ──────────────────────────────────────

  describe "CortexEx.MCP.Tools.Runtime ets_lookup" do
    setup do
      # Create a test ETS table
      table = :cortex_ex_test_ets

      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end

      :ets.new(table, [:named_table, :set, :public])
      :ets.insert(table, {:test_key, "test_value"})

      on_exit(fn ->
        if :ets.info(table) != :undefined do
          :ets.delete(table)
        end
      end)

      %{table: table}
    end

    test "looks up an existing key", %{table: _table} do
      assert {:ok, result} =
               CortexEx.MCP.Tools.Runtime.ets_lookup(%{
                 "table" => "cortex_ex_test_ets",
                 "key" => "test_key"
               })

      assert result =~ "test_value"
    end

    test "returns empty for non-existent key" do
      assert {:ok, result} =
               CortexEx.MCP.Tools.Runtime.ets_lookup(%{
                 "table" => "cortex_ex_test_ets",
                 "key" => "nonexistent"
               })

      assert result =~ "[]"
    end

    test "returns error for non-existent table" do
      assert {:error, msg} =
               CortexEx.MCP.Tools.Runtime.ets_lookup(%{
                 "table" => "nonexistent_table_xyz",
                 "key" => "foo"
               })

      assert msg =~ "not found"
    end

    test "requires both parameters" do
      assert {:error, _} = CortexEx.MCP.Tools.Runtime.ets_lookup(%{})
      assert {:error, _} = CortexEx.MCP.Tools.Runtime.ets_lookup(%{"table" => "t"})
      assert {:error, _} = CortexEx.MCP.Tools.Runtime.ets_lookup(%{"key" => "k"})
    end
  end

  # ── Runtime: get_config ──────────────────────────────────────

  describe "CortexEx.MCP.Tools.Runtime get_config" do
    test "returns config for a known app" do
      assert {:ok, json} = CortexEx.MCP.Tools.Runtime.get_config(%{"app" => "logger"})
      assert {:ok, config} = Jason.decode(json)
      assert is_map(config)
    end

    test "masks sensitive values" do
      # Temporarily set a sensitive config value
      Application.put_env(:cortex_ex, :test_password, "supersecret")
      Application.put_env(:cortex_ex, :test_normal, "visible")

      on_exit(fn ->
        Application.delete_env(:cortex_ex, :test_password)
        Application.delete_env(:cortex_ex, :test_normal)
      end)

      assert {:ok, json} = CortexEx.MCP.Tools.Runtime.get_config(%{"app" => "cortex_ex"})
      assert {:ok, config} = Jason.decode(json)

      assert config["test_password"] == "[FILTERED]"
      assert config["test_normal"] == "visible"
    end

    test "requires app parameter" do
      assert {:error, "app parameter is required"} =
               CortexEx.MCP.Tools.Runtime.get_config(%{})
    end
  end

  # ── Config tool ──────────────────────────────────────────────

  describe "CortexEx.MCP.Tools.Config" do
    test "app_config returns config for a known app" do
      assert {:ok, json} = CortexEx.MCP.Tools.Config.app_config(%{"app" => "logger"})
      assert {:ok, config} = Jason.decode(json)
      assert is_map(config)
    end

    test "app_config returns error for unknown app" do
      assert {:error, msg} =
               CortexEx.MCP.Tools.Config.app_config(%{"app" => "nonexistent_app_xyz"})

      assert msg =~ "Unknown application"
    end

    test "app_config masks sensitive values" do
      Application.put_env(:cortex_ex, :api_key, "secret123")
      on_exit(fn -> Application.delete_env(:cortex_ex, :api_key) end)

      assert {:ok, json} = CortexEx.MCP.Tools.Config.app_config(%{"app" => "cortex_ex"})
      assert {:ok, config} = Jason.decode(json)
      assert config["api_key"] == "[FILTERED]"
    end

    test "app_config requires app parameter" do
      assert {:error, "app parameter is required"} =
               CortexEx.MCP.Tools.Config.app_config(%{})
    end

    test "list_apps returns loaded applications" do
      assert {:ok, json} = CortexEx.MCP.Tools.Config.list_apps(%{})
      assert {:ok, apps} = Jason.decode(json)

      assert is_list(apps)
      assert length(apps) > 0

      names = Enum.map(apps, & &1["name"])
      assert "cortex_ex" in names
      assert "elixir" in names
      assert "logger" in names

      # Each app has expected fields
      app = List.first(apps)
      assert Map.has_key?(app, "name")
      assert Map.has_key?(app, "description")
      assert Map.has_key?(app, "version")
    end
  end

  # ── Oban tools (graceful when unavailable) ───────────────────

  describe "CortexEx.MCP.Tools.Oban" do
    test "tools returns empty list when Oban not available" do
      # Oban is optional, so in test env it may or may not be loaded
      tools = CortexEx.MCP.Tools.Oban.tools()
      assert is_list(tools)

      unless Code.ensure_loaded?(Oban) do
        assert tools == []
      end
    end

    test "oban_queues returns error when Oban not available" do
      unless Code.ensure_loaded?(Oban) do
        assert {:error, msg} = CortexEx.MCP.Tools.Oban.oban_queues(%{})
        assert msg =~ "not available"
      end
    end

    test "oban_workers returns error when Oban not available" do
      unless Code.ensure_loaded?(Oban) do
        assert {:error, msg} = CortexEx.MCP.Tools.Oban.oban_workers(%{})
        assert msg =~ "not available"
      end
    end

    test "failed_jobs returns error when Oban not available" do
      unless Code.ensure_loaded?(Oban) do
        assert {:error, msg} = CortexEx.MCP.Tools.Oban.failed_jobs(%{})
        assert msg =~ "not available"
      end
    end

    test "retry_job requires id parameter" do
      assert {:error, "id parameter is required"} =
               CortexEx.MCP.Tools.Oban.retry_job(%{})
    end

    test "retry_job returns error when Oban not available" do
      unless Code.ensure_loaded?(Oban) do
        assert {:error, msg} = CortexEx.MCP.Tools.Oban.retry_job(%{"id" => 1})
        assert msg =~ "not available"
      end
    end
  end

  # ── Tool Registry ────────────────────────────────────────────

  describe "v0.3 tool registration" do
    test "new tools are listed in registry" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      # Runtime tools
      assert "supervision_tree" in names
      assert "process_info" in names
      assert "genserver_state" in names
      assert "ets_tables" in names
      assert "ets_lookup" in names
      assert "get_config" in names

      # Config tools
      assert "app_config" in names
      assert "list_apps" in names

      # Oban tools are only registered if Oban is available
      if Code.ensure_loaded?(Oban) do
        assert "oban_queues" in names
        assert "oban_workers" in names
        assert "failed_jobs" in names
        assert "retry_job" in names
      end
    end

    test "v0.1 and v0.2 tools are still registered" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      # v0.1 tools
      assert "xref_graph" in names
      assert "project_eval" in names
      assert "get_docs" in names

      # v0.2 tools
      assert "get_errors" in names
      assert "get_logs" in names
      assert "get_recent_requests" in names
    end
  end
end
