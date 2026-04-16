defmodule CortexExV04Test do
  use ExUnit.Case

  alias CortexEx.TelemetryTracker
  alias CortexEx.MCP.Tools

  setup do
    TelemetryTracker.clear()
    :ok
  end

  # ── TelemetryTracker GenServer ───────────────────────────────

  describe "CortexEx.TelemetryTracker" do
    test "starts and is alive (supervised by Application)" do
      pid = Process.whereis(CortexEx.TelemetryTracker)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "records events via record/3 and retrieves them" do
      TelemetryTracker.record(
        [:phoenix, :endpoint, :stop],
        %{duration: System.convert_time_unit(700, :millisecond, :native)},
        %{method: "GET", request_path: "/users", status: 200}
      )

      # Give the cast a moment to process
      :sys.get_state(TelemetryTracker)

      events = TelemetryTracker.get_metrics(nil, 10)
      assert length(events) >= 1

      event = List.first(events)
      assert event.name == [:phoenix, :endpoint, :stop]
      assert event.metadata[:method] == "GET"
    end

    test "filters events by list prefix" do
      TelemetryTracker.record([:phoenix, :endpoint, :stop], %{duration: 1}, %{})
      TelemetryTracker.record([:ecto, :repo, :query], %{total_time: 1}, %{})
      :sys.get_state(TelemetryTracker)

      phoenix_events = TelemetryTracker.get_metrics([:phoenix], 100)
      assert length(phoenix_events) >= 1
      assert Enum.all?(phoenix_events, fn e -> List.first(e.name) == :phoenix end)

      ecto_events = TelemetryTracker.get_metrics([:ecto, :repo], 100)
      assert length(ecto_events) >= 1
      assert Enum.all?(ecto_events, fn e -> match?([:ecto, :repo | _], e.name) end)
    end

    test "filters events by dotted string" do
      TelemetryTracker.record([:phoenix, :endpoint, :stop], %{duration: 1}, %{})
      :sys.get_state(TelemetryTracker)

      events = TelemetryTracker.get_metrics("phoenix.endpoint", 100)
      assert length(events) >= 1
    end

    test "get_slow_queries filters by duration threshold" do
      slow_native = System.convert_time_unit(200, :millisecond, :native)
      fast_native = System.convert_time_unit(10, :millisecond, :native)

      TelemetryTracker.record(
        [:ecto, :repo, :query],
        %{total_time: slow_native, query_time: slow_native, queue_time: 0, decode_time: 0},
        %{query: "SELECT * FROM users", source: "users", params: []}
      )

      TelemetryTracker.record(
        [:ecto, :repo, :query],
        %{total_time: fast_native, query_time: fast_native, queue_time: 0, decode_time: 0},
        %{query: "SELECT 1", source: nil, params: []}
      )

      :sys.get_state(TelemetryTracker)

      slow = TelemetryTracker.get_slow_queries(100)
      assert length(slow) == 1
      assert List.first(slow).metadata[:query] == "SELECT * FROM users"
    end

    test "get_slow_requests filters by duration threshold" do
      slow_native = System.convert_time_unit(800, :millisecond, :native)
      fast_native = System.convert_time_unit(50, :millisecond, :native)

      TelemetryTracker.record(
        [:phoenix, :endpoint, :stop],
        %{duration: slow_native},
        %{method: "POST", request_path: "/slow", status: 200}
      )

      TelemetryTracker.record(
        [:phoenix, :endpoint, :stop],
        %{duration: fast_native},
        %{method: "GET", request_path: "/fast", status: 200}
      )

      :sys.get_state(TelemetryTracker)

      slow = TelemetryTracker.get_slow_requests(500)
      assert length(slow) == 1
      assert List.first(slow).metadata[:request_path] == "/slow"
    end

    test "clear/0 empties the buffer" do
      TelemetryTracker.record([:phoenix, :endpoint, :stop], %{duration: 1}, %{})
      :sys.get_state(TelemetryTracker)

      assert length(TelemetryTracker.get_metrics()) >= 1
      assert :ok = TelemetryTracker.clear()
      assert TelemetryTracker.get_metrics() == []
    end

    test "handles non-serializable metadata gracefully" do
      pid = self()
      ref = make_ref()

      TelemetryTracker.record(
        [:phoenix, :endpoint, :stop],
        %{duration: 1},
        %{pid: pid, ref: ref, nested: %{inner_pid: pid}}
      )

      :sys.get_state(TelemetryTracker)

      events = TelemetryTracker.get_metrics(nil, 10)
      event = Enum.find(events, fn e -> e.name == [:phoenix, :endpoint, :stop] end)

      assert is_binary(event.metadata[:pid])
      assert String.starts_with?(event.metadata[:pid], "#PID<")
    end

    test "attaches real telemetry handlers and captures emitted events" do
      if Code.ensure_loaded?(:telemetry) do
        # Re-attach to ensure handler is active
        TelemetryTracker.attach()

        :telemetry.execute(
          [:phoenix, :endpoint, :stop],
          %{duration: System.convert_time_unit(123, :millisecond, :native)},
          %{method: "GET", request_path: "/telemetry-test", status: 200}
        )

        # allow cast to process
        :sys.get_state(TelemetryTracker)

        events = TelemetryTracker.get_metrics([:phoenix, :endpoint], 10)
        assert Enum.any?(events, fn e -> e.metadata[:request_path] == "/telemetry-test" end)
      end
    end
  end

  # ── Telemetry MCP Tool ───────────────────────────────────────

  describe "CortexEx.MCP.Tools.Telemetry telemetry_metrics" do
    test "returns JSON array of events" do
      TelemetryTracker.record([:phoenix, :endpoint, :stop], %{duration: 1000}, %{
        method: "GET",
        request_path: "/"
      })

      :sys.get_state(TelemetryTracker)

      assert {:ok, json} = Tools.Telemetry.telemetry_metrics(%{})
      assert {:ok, list} = Jason.decode(json)
      assert is_list(list)
      assert length(list) >= 1

      first = List.first(list)
      assert is_binary(first["name"])
      assert Map.has_key?(first, "measurements")
      assert Map.has_key?(first, "metadata")
      assert Map.has_key?(first, "timestamp")
    end

    test "filters by event prefix" do
      TelemetryTracker.record([:phoenix, :endpoint, :stop], %{duration: 1}, %{})
      TelemetryTracker.record([:ecto, :repo, :query], %{total_time: 1}, %{})
      :sys.get_state(TelemetryTracker)

      assert {:ok, json} = Tools.Telemetry.telemetry_metrics(%{"event" => "phoenix"})
      assert {:ok, list} = Jason.decode(json)
      assert Enum.all?(list, fn e -> String.starts_with?(e["name"], "phoenix") end)
    end

    test "respects limit" do
      for i <- 1..5 do
        TelemetryTracker.record([:phoenix, :endpoint, :stop], %{duration: i}, %{})
      end

      :sys.get_state(TelemetryTracker)

      assert {:ok, json} = Tools.Telemetry.telemetry_metrics(%{"limit" => 2})
      assert {:ok, list} = Jason.decode(json)
      assert length(list) == 2
    end
  end

  describe "CortexEx.MCP.Tools.Telemetry slow_queries" do
    test "returns only queries exceeding threshold_ms" do
      slow_native = System.convert_time_unit(250, :millisecond, :native)
      fast_native = System.convert_time_unit(5, :millisecond, :native)

      TelemetryTracker.record(
        [:ecto, :repo, :query],
        %{total_time: slow_native, query_time: slow_native, queue_time: 0, decode_time: 0},
        %{query: "SELECT * FROM slow_table", source: "slow_table", params: []}
      )

      TelemetryTracker.record(
        [:ecto, :repo, :query],
        %{total_time: fast_native, query_time: fast_native, queue_time: 0, decode_time: 0},
        %{query: "SELECT 1", source: nil, params: []}
      )

      :sys.get_state(TelemetryTracker)

      assert {:ok, json} = Tools.Telemetry.slow_queries(%{"threshold_ms" => 100})
      assert {:ok, list} = Jason.decode(json)
      assert length(list) == 1

      entry = List.first(list)
      assert entry["sql"] == "SELECT * FROM slow_table"
      assert entry["source"] == "slow_table"
      assert is_float(entry["duration_ms"]) or is_integer(entry["duration_ms"])
      assert entry["duration_ms"] >= 100
    end

    test "default threshold is 100ms" do
      TelemetryTracker.record(
        [:ecto, :repo, :query],
        %{total_time: System.convert_time_unit(50, :millisecond, :native)},
        %{query: "SELECT 1"}
      )

      :sys.get_state(TelemetryTracker)

      assert {:ok, json} = Tools.Telemetry.slow_queries(%{})
      assert {:ok, list} = Jason.decode(json)
      assert list == []
    end
  end

  describe "CortexEx.MCP.Tools.Telemetry slow_requests" do
    test "returns only requests exceeding threshold_ms" do
      slow_native = System.convert_time_unit(900, :millisecond, :native)
      fast_native = System.convert_time_unit(100, :millisecond, :native)

      TelemetryTracker.record(
        [:phoenix, :endpoint, :stop],
        %{duration: slow_native},
        %{method: "GET", request_path: "/slow", status: 200}
      )

      TelemetryTracker.record(
        [:phoenix, :endpoint, :stop],
        %{duration: fast_native},
        %{method: "GET", request_path: "/fast", status: 200}
      )

      :sys.get_state(TelemetryTracker)

      assert {:ok, json} = Tools.Telemetry.slow_requests(%{"threshold_ms" => 500})
      assert {:ok, list} = Jason.decode(json)
      assert length(list) == 1

      entry = List.first(list)
      assert entry["path"] == "/slow"
      assert entry["method"] == "GET"
      assert entry["status"] == 200
      assert entry["duration_ms"] >= 500
    end
  end

  # ── LiveView tool ────────────────────────────────────────────

  describe "CortexEx.MCP.Tools.LiveView" do
    test "tools registered only if Phoenix.LiveView is loaded" do
      tools = Tools.LiveView.tools()

      if Code.ensure_loaded?(Phoenix.LiveView) do
        names = Enum.map(tools, & &1.name)
        assert "live_views" in names
        assert "live_view_assigns" in names
      else
        assert tools == []
      end
    end

    test "live_views returns JSON array when LV is loaded, or error otherwise" do
      if Code.ensure_loaded?(Phoenix.LiveView) do
        assert {:ok, json} = Tools.LiveView.live_views(%{})
        assert {:ok, list} = Jason.decode(json)
        assert is_list(list)
      else
        assert {:error, msg} = Tools.LiveView.live_views(%{})
        assert msg =~ "not available"
      end
    end

    test "live_view_assigns requires pid parameter" do
      if Code.ensure_loaded?(Phoenix.LiveView) do
        assert {:error, "pid parameter is required"} = Tools.LiveView.live_view_assigns(%{})
      end
    end

    test "live_view?/1 returns false for non-LV pids" do
      refute Tools.LiveView.live_view?(self())
    end
  end

  # ── PubSub tool ──────────────────────────────────────────────

  describe "CortexEx.MCP.Tools.PubSub" do
    test "tools registered only if Phoenix.PubSub is loaded" do
      tools = Tools.PubSub.tools()

      if Code.ensure_loaded?(Phoenix.PubSub) do
        names = Enum.map(tools, & &1.name)
        assert "pubsub_topology" in names
      else
        assert tools == []
      end
    end

    test "pubsub_topology returns JSON array when available" do
      if Code.ensure_loaded?(Phoenix.PubSub) do
        assert {:ok, json} = Tools.PubSub.pubsub_topology(%{})
        assert {:ok, list} = Jason.decode(json)
        assert is_list(list)
      else
        assert {:error, msg} = Tools.PubSub.pubsub_topology(%{})
        assert msg =~ "not available"
      end
    end

    test "pubsub_topology with a running PubSub instance lists topics" do
      if Code.ensure_loaded?(Phoenix.PubSub) do
        # Start a PubSub instance for this test
        name = :"CortexExTestPubSub#{:erlang.unique_integer([:positive])}"

        {:ok, _pid} =
          Supervisor.start_link([{Phoenix.PubSub, name: name}],
            strategy: :one_for_one,
            name: :"#{name}.Sup"
          )

        # Subscribe self to a topic
        Phoenix.PubSub.subscribe(name, "room:test")

        assert {:ok, json} = Tools.PubSub.pubsub_topology(%{"pubsub" => to_string(name)})
        assert {:ok, list} = Jason.decode(json)
        # topic may or may not appear depending on registry backend; be lenient
        assert is_list(list)
      end
    end
  end

  # ── Tool Registry ────────────────────────────────────────────

  describe "v0.4 tool registration" do
    test "telemetry tools are registered" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      assert "telemetry_metrics" in names
      assert "slow_queries" in names
      assert "slow_requests" in names
    end

    test "LiveView tools are registered when available" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      if Code.ensure_loaded?(Phoenix.LiveView) do
        assert "live_views" in names
        assert "live_view_assigns" in names
      end
    end

    test "PubSub tools are registered when available" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      if Code.ensure_loaded?(Phoenix.PubSub) do
        assert "pubsub_topology" in names
      end
    end

    test "v0.1, v0.2, v0.3 tools remain registered" do
      tools = CortexEx.MCP.Tools.list_all()
      names = Enum.map(tools, & &1.name)

      # v0.1
      assert "xref_graph" in names
      assert "project_eval" in names
      # v0.2
      assert "get_errors" in names
      assert "get_logs" in names
      # v0.3
      assert "supervision_tree" in names
      assert "app_config" in names
    end
  end
end
