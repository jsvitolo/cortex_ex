defmodule CortexExV06AuthzTest do
  use ExUnit.Case

  import CortexEx.AuthCase, only: [identity: 1]

  alias CortexEx.Audit
  alias CortexEx.MCP.Server
  alias CortexEx.MCP.Tools
  alias CortexEx.Users
  alias CortexEx.Users.Store.Memory

  setup do
    Application.put_env(:cortex_ex, :store, Memory)
    # Drain audit entries buffered by earlier tests before resetting the store.
    Audit.flush()
    Memory.reset()
    CortexEx.Users.Cache.clear()

    on_exit(fn ->
      Application.delete_env(:cortex_ex, :store)
      Application.delete_env(:cortex_ex, :admins)
      CortexEx.Users.Cache.clear()
    end)

    :ok
  end

  describe "Users.get_permissions/1" do
    test "config admins win, regardless of store" do
      Application.put_env(:cortex_ex, :admins, ["Boss@Empresa.com"])

      assert Users.get_permissions("boss@empresa.com") == :admin
      assert Users.get_permissions("BOSS@EMPRESA.COM") == :admin
    end

    test "unknown emails are denied" do
      assert Users.get_permissions("stranger@empresa.com") == :denied
    end

    test "no store configured fails closed" do
      Application.delete_env(:cortex_ex, :store)
      CortexEx.Users.Cache.clear()

      assert Users.get_permissions("someone@empresa.com") == :denied
    end

    test "stored users resolve role and can_write" do
      {:ok, _} = Users.add_user(%{email: "reader@empresa.com"}, "boss@empresa.com")
      {:ok, _} = Users.add_user(%{email: "writer@empresa.com", can_write: true}, "boss@empresa.com")
      {:ok, _} = Users.add_user(%{email: "chief@empresa.com", role: "admin"}, "boss@empresa.com")

      assert Users.get_permissions("reader@empresa.com") == {:member, false}
      assert Users.get_permissions("writer@empresa.com") == {:member, true}
      assert Users.get_permissions("chief@empresa.com") == :admin
    end

    test "writes invalidate the cache so changes apply on the next request" do
      # Prime the cache with a denial
      assert Users.get_permissions("late@empresa.com") == :denied

      {:ok, _} = Users.add_user(%{email: "late@empresa.com", can_write: true}, "boss@empresa.com")
      assert Users.get_permissions("late@empresa.com") == {:member, true}

      {:ok, _} = Users.set_can_write("late@empresa.com", false, "boss@empresa.com")
      assert Users.get_permissions("late@empresa.com") == {:member, false}

      :ok = Users.remove_user("late@empresa.com", "boss@empresa.com")
      assert Users.get_permissions("late@empresa.com") == :denied
    end

    test "config admins cannot be modified or removed" do
      Application.put_env(:cortex_ex, :admins, ["boss@empresa.com"])

      assert {:error, :config_admin_immutable} =
               Users.add_user(%{email: "boss@empresa.com"}, "boss@empresa.com")

      assert {:error, :config_admin_immutable} =
               Users.set_can_write("boss@empresa.com", false, "boss@empresa.com")

      assert {:error, :config_admin_immutable} =
               Users.remove_user("boss@empresa.com", "boss@empresa.com")
    end
  end

  describe "Tools.list_for/1 and call/3" do
    test "read-only members do not see write tools" do
      names = Enum.map(Tools.list_for({:member, false}), & &1.name)

      refute "project_eval" in names
      refute "retry_job" in names
      refute "clear_logs" in names
      assert "get_errors" in names
      assert "routes" in names
    end

    test "writers and admins see everything" do
      all = length(Tools.list_all())

      assert length(Tools.list_for({:member, true})) == all
      assert length(Tools.list_for(:admin)) == all
      assert Tools.list_for(:denied) == []
    end

    test "every tool declares an explicit access level" do
      assert Enum.all?(Tools.list_all(), &(&1.access in [:read, :write]))
    end

    test "forbidden is distinct from unknown" do
      assert {:error, :forbidden} =
               Tools.call("project_eval", %{"code" => "1"}, {:member, false})

      assert {:error, "Unknown tool: nope"} = Tools.call("nope", %{}, {:member, false})

      assert {:ok, _} = Tools.call("project_eval", %{"code" => "1"}, {:member, true})
    end
  end

  describe "Server with identity" do
    test "tools/list is filtered by permissions and JSON-encodable" do
      {:ok, _} = Users.add_user(%{email: "reader@empresa.com"}, "boss@empresa.com")

      req = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      response = Server.handle_request(req, identity("reader@empresa.com"))

      names = Enum.map(response["result"]["tools"], & &1.name)
      refute "project_eval" in names
      assert "get_errors" in names

      # Callbacks are stripped, so the response must encode cleanly.
      assert is_binary(Jason.encode!(response))
    end

    test "denied identity gets JSON-RPC -32001" do
      req = %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}
      response = Server.handle_request(req, identity("stranger@empresa.com"))

      assert response["error"]["code"] == -32001
    end

    test "write tool call by read-only member returns isError result" do
      {:ok, _} = Users.add_user(%{email: "reader@empresa.com"}, "boss@empresa.com")

      req = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "project_eval", "arguments" => %{"code" => "1"}}
      }

      response = Server.handle_request(req, identity("reader@empresa.com"))

      assert response["result"]["isError"] == true
      assert [%{"text" => "Access denied" <> _}] = response["result"]["content"]
    end

    test "nil identity (auth disabled) keeps full access" do
      req = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "project_eval", "arguments" => %{"code" => "40 + 2"}}
      }

      response = Server.handle_request(req, nil)
      assert [%{"text" => "42"}] = response["result"]["content"]
    end
  end

  describe "Audit" do
    test "tool calls are buffered and flushed to the store" do
      {:ok, _} = Users.add_user(%{email: "writer@empresa.com", can_write: true}, "boss@empresa.com")

      req = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "project_eval", "arguments" => %{"code" => "1 + 1"}}
      }

      Server.handle_request(req, identity("writer@empresa.com"))
      Audit.flush()

      audits = Memory.audits()
      entry = Enum.find(audits, &(&1.action == "tool_call"))

      assert entry.actor_email == "writer@empresa.com"
      assert entry.tool_name == "project_eval"
      assert entry.result_status == "ok"
    end

    test "denied calls are audited with denied status" do
      {:ok, _} = Users.add_user(%{email: "reader@empresa.com"}, "boss@empresa.com")

      req = %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "tools/call",
        "params" => %{"name" => "clear_logs", "arguments" => %{}}
      }

      Server.handle_request(req, identity("reader@empresa.com"))
      Audit.flush()

      entry = Enum.find(Memory.audits(), &(&1.tool_name == "clear_logs"))
      assert entry.result_status == "denied"
    end

    test "oversized args are truncated" do
      big = String.duplicate("x", 5_000)
      Audit.tool_call("dev@empresa.com", "project_eval", %{"code" => big}, :ok)
      Audit.flush()

      entry = Enum.find(Memory.audits(), &(&1.tool_name == "project_eval"))
      assert %{"_truncated" => _, "_original_bytes" => bytes} = entry.args
      assert bytes > 2_000
    end

    test "user management is audited synchronously" do
      {:ok, _} = Users.add_user(%{email: "novo@empresa.com"}, "boss@empresa.com")
      {:ok, _} = Users.set_role("novo@empresa.com", "admin", "boss@empresa.com")
      :ok = Users.remove_user("novo@empresa.com", "boss@empresa.com")

      actions = Memory.audits() |> Enum.map(& &1.action)

      assert "user_added" in actions
      assert "role_changed" in actions
      assert "user_removed" in actions
    end
  end
end
