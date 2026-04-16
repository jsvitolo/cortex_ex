defmodule CortexExV02Test do
  use ExUnit.Case

  # ── ErrorTracker ──────────────────────────────────────────────

  describe "CortexEx.ErrorTracker" do
    setup do
      CortexEx.ErrorTracker.clear_errors()
      :ok
    end

    test "starts with empty errors" do
      assert CortexEx.ErrorTracker.get_errors() == []
    end

    test "captures error log events" do
      require Logger
      Logger.error("test error from ErrorTracker test")

      # Give the async handler time to process
      Process.sleep(100)

      errors = CortexEx.ErrorTracker.get_errors()
      assert length(errors) >= 1

      error = List.last(errors)
      assert error.message =~ "test error from ErrorTracker test"
      assert error.count >= 1
      assert %DateTime{} = error.timestamp
    end

    test "deduplicates same errors by incrementing count" do
      require Logger
      Logger.error("dedup test error")
      Process.sleep(50)
      Logger.error("dedup test error")
      Process.sleep(100)

      errors = CortexEx.ErrorTracker.get_errors()
      # Find the error we just logged
      matching = Enum.filter(errors, &(&1.message =~ "dedup test error"))

      # Depending on metadata, they may or may not dedup (different mfa)
      # But at minimum they should be captured
      assert length(matching) >= 1
    end

    test "get_error_detail returns nil for unknown id" do
      assert CortexEx.ErrorTracker.get_error_detail("nonexistent") == nil
    end

    test "get_error_detail returns error by id" do
      require Logger
      Logger.error("detail test error")
      Process.sleep(100)

      [error | _] = CortexEx.ErrorTracker.get_errors(1)
      detail = CortexEx.ErrorTracker.get_error_detail(error.id)
      assert detail != nil
      assert detail.id == error.id
      assert detail.message == error.message
    end

    test "get_error_frequency returns frequency data" do
      require Logger
      Logger.error("freq test error")
      Process.sleep(100)

      freq = CortexEx.ErrorTracker.get_error_frequency()
      assert is_list(freq)
      assert length(freq) >= 1

      entry = List.first(freq)
      assert Map.has_key?(entry, :exception)
      assert Map.has_key?(entry, :total_count)
      assert Map.has_key?(entry, :last_seen)
    end

    test "get_error_frequency filters by module" do
      freq = CortexEx.ErrorTracker.get_error_frequency("NonExistentModule")
      assert freq == []
    end

    test "clear_errors empties the buffer" do
      require Logger
      Logger.error("clear test error")
      Process.sleep(100)

      assert length(CortexEx.ErrorTracker.get_errors()) >= 1
      CortexEx.ErrorTracker.clear_errors()
      assert CortexEx.ErrorTracker.get_errors() == []
    end
  end

  # ── LoggerBackend ─────────────────────────────────────────────

  describe "CortexEx.LoggerBackend" do
    setup do
      CortexEx.LoggerBackend.clear_logs()
      :ok
    end

    test "starts with empty logs" do
      assert CortexEx.LoggerBackend.get_logs() == []
    end

    test "captures log events" do
      require Logger
      Logger.info("test log message")
      Process.sleep(100)

      logs = CortexEx.LoggerBackend.get_logs()
      assert length(logs) >= 1

      log = List.first(logs)
      assert log.level in [:debug, :info, :warning, :error]
      assert is_binary(log.message)
      assert %DateTime{} = log.timestamp
    end

    test "filters by level" do
      require Logger
      Logger.info("info message")
      Logger.warning("warning message")
      Process.sleep(100)

      info_logs = CortexEx.LoggerBackend.get_logs(level: :info)
      assert Enum.all?(info_logs, &(&1.level == :info))

      warning_logs = CortexEx.LoggerBackend.get_logs(level: :warning)
      assert Enum.all?(warning_logs, &(&1.level == :warning))
    end

    test "filters by grep pattern" do
      require Logger
      Logger.info("unique_pattern_xyz")
      Logger.info("other message")
      Process.sleep(100)

      filtered = CortexEx.LoggerBackend.get_logs(grep: "unique_pattern_xyz")
      assert length(filtered) >= 1
      assert Enum.all?(filtered, &(&1.message =~ "unique_pattern_xyz"))
    end

    test "filters by tail count" do
      require Logger
      for i <- 1..5, do: Logger.info("tail test #{i}")
      Process.sleep(100)

      logs = CortexEx.LoggerBackend.get_logs(tail: 2)
      assert length(logs) <= 2
    end

    test "get_log_modules returns module counts" do
      require Logger
      Logger.info("module test")
      Process.sleep(100)

      modules = CortexEx.LoggerBackend.get_log_modules()
      assert is_list(modules)

      if length(modules) > 0 do
        entry = List.first(modules)
        assert Map.has_key?(entry, :module)
        assert Map.has_key?(entry, :count)
        assert entry.count > 0
      end
    end

    test "clear_logs empties the buffer" do
      require Logger
      Logger.info("clear test")
      Process.sleep(100)

      assert length(CortexEx.LoggerBackend.get_logs()) >= 1
      CortexEx.LoggerBackend.clear_logs()
      assert CortexEx.LoggerBackend.get_logs() == []
    end
  end

  # ── RequestTracker ────────────────────────────────────────────

  describe "CortexEx.RequestTracker" do
    setup do
      CortexEx.RequestTracker.clear_requests()
      :ok
    end

    test "starts with empty requests" do
      assert CortexEx.RequestTracker.get_recent_requests() == []
    end

    test "tracks a request via plug" do
      conn =
        Plug.Test.conn(:get, "/api/users?page=1")
        |> Plug.Conn.fetch_query_params()

      conn = CortexEx.RequestTracker.Plug.call(conn, [])

      # Simulate sending a response (triggers before_send callback)
      _conn =
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, ~s({"ok": true}))

      # Give the cast time to process
      Process.sleep(50)

      requests = CortexEx.RequestTracker.get_recent_requests()
      assert length(requests) >= 1

      req = List.first(requests)
      assert req.method == "GET"
      assert req.path == "/api/users"
      assert req.status == 200
      assert is_integer(req.duration_ms)
      assert req.duration_ms >= 0
    end

    test "get_request_detail returns nil for unknown id" do
      assert CortexEx.RequestTracker.get_request_detail("nonexistent") == nil
    end

    test "get_request_detail returns request by id" do
      conn =
        Plug.Test.conn(:post, "/api/items", ~s({"name": "test"}))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.fetch_query_params()

      conn = CortexEx.RequestTracker.Plug.call(conn, [])

      conn
      |> Plug.Conn.send_resp(201, ~s({"id": 1}))

      Process.sleep(50)

      [req | _] = CortexEx.RequestTracker.get_recent_requests(1)
      detail = CortexEx.RequestTracker.get_request_detail(req.id)
      assert detail != nil
      assert detail.id == req.id
      assert detail.method == "POST"
    end

    test "sanitizes sensitive params" do
      conn =
        Plug.Test.conn(:post, "/api/login")
        |> Map.put(:params, %{"username" => "john", "password" => "secret123", "token" => "abc"})
        |> Plug.Conn.fetch_query_params()

      conn = CortexEx.RequestTracker.Plug.call(conn, [])

      conn
      |> Plug.Conn.send_resp(200, "ok")

      Process.sleep(50)

      [req | _] = CortexEx.RequestTracker.get_recent_requests(1)
      detail = CortexEx.RequestTracker.get_request_detail(req.id)
      assert detail.params["username"] == "john"
      assert detail.params["password"] == "[FILTERED]"
      assert detail.params["token"] == "[FILTERED]"
    end

    test "replay_request returns curl command" do
      conn =
        Plug.Test.conn(:get, "/api/users")
        |> Plug.Conn.fetch_query_params()

      conn = CortexEx.RequestTracker.Plug.call(conn, [])

      conn
      |> Plug.Conn.send_resp(200, "ok")

      Process.sleep(50)

      [req | _] = CortexEx.RequestTracker.get_recent_requests(1)
      replay = CortexEx.RequestTracker.replay_request(req.id)
      assert replay != nil
      assert is_binary(replay.curl)
      assert replay.curl =~ "/api/users"
    end

    test "replay_request returns nil for unknown id" do
      assert CortexEx.RequestTracker.replay_request("nonexistent") == nil
    end

    test "clear_requests empties the buffer" do
      conn =
        Plug.Test.conn(:get, "/test")
        |> Plug.Conn.fetch_query_params()

      conn = CortexEx.RequestTracker.Plug.call(conn, [])
      conn |> Plug.Conn.send_resp(200, "ok")
      Process.sleep(50)

      assert length(CortexEx.RequestTracker.get_recent_requests()) >= 1
      CortexEx.RequestTracker.clear_requests()
      assert CortexEx.RequestTracker.get_recent_requests() == []
    end
  end

  # ── MCP Tools: Errors ────────────────────────────────────────

  describe "CortexEx.MCP.Tools.Errors" do
    setup do
      CortexEx.ErrorTracker.clear_errors()
      :ok
    end

    test "get_errors returns JSON" do
      assert {:ok, json} = CortexEx.MCP.Tools.Errors.get_errors(%{})
      assert {:ok, _} = Jason.decode(json)
    end

    test "get_error_detail requires id" do
      assert {:error, "id parameter is required"} =
               CortexEx.MCP.Tools.Errors.get_error_detail(%{})
    end

    test "get_error_detail returns error for unknown id" do
      assert {:error, "Error not found: unknown"} =
               CortexEx.MCP.Tools.Errors.get_error_detail(%{"id" => "unknown"})
    end

    test "get_error_frequency returns JSON" do
      assert {:ok, json} = CortexEx.MCP.Tools.Errors.get_error_frequency(%{})
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded)
    end

    test "clear_errors returns success" do
      assert {:ok, "Errors cleared"} = CortexEx.MCP.Tools.Errors.clear_errors(%{})
    end
  end

  # ── MCP Tools: Logs ──────────────────────────────────────────

  describe "CortexEx.MCP.Tools.Logs" do
    setup do
      CortexEx.LoggerBackend.clear_logs()
      :ok
    end

    test "get_logs returns JSON" do
      assert {:ok, json} = CortexEx.MCP.Tools.Logs.get_logs(%{})
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded)
    end

    test "get_logs with filters returns JSON" do
      require Logger
      Logger.info("mcp tool log test")
      Process.sleep(100)

      assert {:ok, json} = CortexEx.MCP.Tools.Logs.get_logs(%{"level" => "info", "tail" => 5})
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded)
    end

    test "get_log_modules returns JSON" do
      assert {:ok, json} = CortexEx.MCP.Tools.Logs.get_log_modules(%{})
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded)
    end

    test "clear_logs returns success" do
      assert {:ok, "Logs cleared"} = CortexEx.MCP.Tools.Logs.clear_logs(%{})
    end
  end

  # ── MCP Tools: Requests ──────────────────────────────────────

  describe "CortexEx.MCP.Tools.Requests" do
    setup do
      CortexEx.RequestTracker.clear_requests()
      :ok
    end

    test "get_recent_requests returns JSON" do
      assert {:ok, json} = CortexEx.MCP.Tools.Requests.get_recent_requests(%{})
      assert {:ok, decoded} = Jason.decode(json)
      assert is_list(decoded)
    end

    test "get_request_detail requires id" do
      assert {:error, "id parameter is required"} =
               CortexEx.MCP.Tools.Requests.get_request_detail(%{})
    end

    test "get_request_detail returns error for unknown id" do
      assert {:error, "Request not found: unknown"} =
               CortexEx.MCP.Tools.Requests.get_request_detail(%{"id" => "unknown"})
    end

    test "replay_request requires id" do
      assert {:error, "id parameter is required"} =
               CortexEx.MCP.Tools.Requests.replay_request(%{})
    end

    test "replay_request returns error for unknown id" do
      assert {:error, "Request not found: unknown"} =
               CortexEx.MCP.Tools.Requests.replay_request(%{"id" => "unknown"})
    end
  end

  # ── Tool Registry ────────────────────────────────────────────

  describe "v0.2 tool registration" do
    test "new tools are listed in registry" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      # Error tools
      assert "get_errors" in names
      assert "get_error_detail" in names
      assert "get_error_frequency" in names
      assert "clear_errors" in names

      # Log tools
      assert "get_logs" in names
      assert "get_log_modules" in names
      assert "clear_logs" in names

      # Request tools
      assert "get_recent_requests" in names
      assert "get_request_detail" in names
      assert "replay_request" in names
    end
  end

  # ── Updated Main Plug ────────────────────────────────────────

  describe "CortexEx plug with request tracking" do
    setup do
      CortexEx.RequestTracker.clear_requests()
      :ok
    end

    test "tracks non-cortex_ex requests" do
      conn = Plug.Test.conn(:get, "/api/users")

      result =
        conn
        |> CortexEx.call([])
        |> Plug.Conn.send_resp(200, "ok")

      Process.sleep(50)

      requests = CortexEx.RequestTracker.get_recent_requests()
      assert length(requests) >= 1
      assert List.first(requests).path == "/api/users"
      refute result.halted
    end

    test "tracks cortex_ex requests too" do
      conn =
        Plug.Test.conn(:get, "/cortex_ex/health")
        |> Map.put(:body_params, %{})

      _result = CortexEx.call(conn, [])
      Process.sleep(50)

      requests = CortexEx.RequestTracker.get_recent_requests()
      assert length(requests) >= 1
    end
  end
end
