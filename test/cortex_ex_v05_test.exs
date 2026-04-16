defmodule CortexExV05Test do
  use ExUnit.Case

  alias CortexEx.MCP.Tools

  # ── Tests Tool ───────────────────────────────────────────────

  describe "CortexEx.MCP.Tools.Tests" do
    test "file_to_test maps lib paths to test paths" do
      assert Tools.Tests.file_to_test("lib/my_app/accounts.ex") ==
               "test/my_app/accounts_test.exs"

      assert Tools.Tests.file_to_test("lib/foo/bar/baz.ex") ==
               "test/foo/bar/baz_test.exs"

      assert Tools.Tests.file_to_test("lib/cortex_ex.ex") ==
               "test/cortex_ex_test.exs"
    end

    test "tools/0 registers run_impacted_tests and run_stale_tests" do
      names = Tools.Tests.tools() |> Enum.map(& &1.name)
      assert "run_impacted_tests" in names
      assert "run_stale_tests" in names
    end

    test "run_impacted_tests returns friendly message when no test files exist" do
      assert {:ok, msg} =
               Tools.Tests.run_impacted_tests(%{
                 "files" => ["lib/nonexistent/path_that_cannot_exist.ex"]
               })

      assert msg =~ "No corresponding test files found"
    end

    test "run_impacted_tests requires files parameter" do
      assert {:error, msg} = Tools.Tests.run_impacted_tests(%{})
      assert msg =~ "files parameter is required"
    end
  end

  # ── CortexBridge Tool ────────────────────────────────────────

  describe "CortexEx.MCP.Tools.CortexBridge save_to_cortex_memory" do
    test "returns formatted JSON with memory payload" do
      assert {:ok, output} =
               Tools.CortexBridge.save_to_cortex_memory(%{
                 "title" => "Use pattern matching in function heads",
                 "content" => "Prefer pattern matching over conditionals in function heads.",
                 "type" => "best_practice"
               })

      assert output =~ "mcp__cortex__memory"

      json_part = String.split(output, "\n\n", parts: 2) |> List.last()
      assert {:ok, decoded} = Jason.decode(json_part)

      assert decoded["type"] == "best_practice"
      assert decoded["title"] == "Use pattern matching in function heads"
      assert decoded["source"] == "cortex_ex"
      assert is_binary(decoded["project"])
    end

    test "returns error when required fields are missing" do
      assert {:error, msg} = Tools.CortexBridge.save_to_cortex_memory(%{"title" => "t"})
      assert msg =~ "required"
    end
  end

  describe "CortexEx.MCP.Tools.CortexBridge sync_errors_to_memory" do
    setup do
      if Process.whereis(CortexEx.ErrorTracker) do
        CortexEx.ErrorTracker.clear_errors()
      end

      :ok
    end

    test "filters errors by min_count threshold" do
      # Without any errors tracked we should get an empty list formatted.
      assert {:ok, output} = Tools.CortexBridge.sync_errors_to_memory(%{"min_count" => 3})
      assert output =~ "frequent errors found"

      json_part = String.split(output, "\n\n", parts: 2) |> List.last()
      assert {:ok, list} = Jason.decode(json_part)
      assert is_list(list)
    end

    test "returns formatted anti_pattern memories for frequent errors" do
      if Process.whereis(CortexEx.ErrorTracker) do
        assert {:ok, output} = Tools.CortexBridge.sync_errors_to_memory(%{})
        assert output =~ "mcp__cortex__memory"
      end
    end
  end

  # ── Migrations Tool ──────────────────────────────────────────

  describe "CortexEx.MCP.Tools.Migrations" do
    test "tools/0 returns empty list when Ecto is not available" do
      # If Ecto is loaded (likely not in this project's deps), include the tool.
      tools = Tools.Migrations.tools()

      if Code.ensure_loaded?(Ecto.Schema) do
        names = Enum.map(tools, & &1.name)
        assert "plan_migration" in names
      else
        assert tools == []
      end
    end

    test "plan_migration returns error for non-existent module" do
      if Code.ensure_loaded?(Ecto.Schema) do
        assert {:error, msg} =
                 Tools.Migrations.plan_migration(%{
                   "schema" => "ThisModule.Does.Not.Exist.AtAll#{:erlang.unique_integer([:positive])}"
                 })

        assert msg =~ "not found" or msg =~ "not an Ecto schema"
      end
    end

    test "build_migration_template produces valid-looking migration" do
      template =
        Tools.Migrations.build_migration_template(
          "users",
          [{:name, :string}, {:age, :integer}, {:active, :boolean}],
          [:id]
        )

      assert template =~ "create table(:users)"
      assert template =~ "add :name, :string"
      assert template =~ "add :age, :integer"
      assert template =~ "add :active, :boolean"
      assert template =~ "timestamps()"
      assert template =~ "CreateUsers"
    end

    test "elixir_type_to_ecto maps common Ecto types" do
      assert Tools.Migrations.elixir_type_to_ecto(:integer) == "integer"
      assert Tools.Migrations.elixir_type_to_ecto(:string) == "string"
      assert Tools.Migrations.elixir_type_to_ecto(:boolean) == "boolean"
      assert Tools.Migrations.elixir_type_to_ecto(:utc_datetime) == "utc_datetime"
      assert Tools.Migrations.elixir_type_to_ecto(:binary_id) == "binary_id"
      assert Tools.Migrations.elixir_type_to_ecto({:array, :string}) == "array"
    end
  end

  # ── Hex Tool ─────────────────────────────────────────────────

  describe "CortexEx.MCP.Tools.Hex" do
    test "tools/0 registers search_hex_docs" do
      names = Tools.Hex.tools() |> Enum.map(& &1.name)
      assert "search_hex_docs" in names
    end

    test "search_hex_docs requires q parameter" do
      assert {:error, msg} = Tools.Hex.search_hex_docs(%{})
      assert msg =~ "q parameter is required"
    end

    @tag :external
    test "search_hex_docs returns results for a real query" do
      assert {:ok, output} =
               Tools.Hex.search_hex_docs(%{
                 "q" => "GenServer",
                 "packages" => ["elixir"]
               })

      assert is_binary(output)
      assert output =~ "result"
    end
  end

  # ── Tool Registry ────────────────────────────────────────────

  describe "v0.5 tool registration" do
    test "tests tools are registered" do
      names = Tools.list_all() |> Enum.map(& &1.name)
      assert "run_impacted_tests" in names
      assert "run_stale_tests" in names
    end

    test "cortex_bridge tools are registered" do
      names = Tools.list_all() |> Enum.map(& &1.name)
      assert "save_to_cortex_memory" in names
      assert "sync_errors_to_memory" in names
    end

    test "hex tools are registered" do
      names = Tools.list_all() |> Enum.map(& &1.name)
      assert "search_hex_docs" in names
    end

    test "migration tools registered when Ecto available" do
      names = Tools.list_all() |> Enum.map(& &1.name)

      if Code.ensure_loaded?(Ecto.Schema) do
        assert "plan_migration" in names
      end
    end

    test "v0.1 through v0.4 tools remain registered" do
      names = Tools.list_all() |> Enum.map(& &1.name)

      # v0.1
      assert "xref_graph" in names
      assert "project_eval" in names
      # v0.2
      assert "get_errors" in names
      assert "get_logs" in names
      # v0.3
      assert "supervision_tree" in names
      assert "app_config" in names
      # v0.4
      assert "telemetry_metrics" in names
    end
  end
end
