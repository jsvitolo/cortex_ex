defmodule CortexExTest do
  use ExUnit.Case

  describe "CortexEx plug" do
    test "init/1 returns opts unchanged" do
      assert CortexEx.init([]) == []
      assert CortexEx.init(foo: :bar) == [foo: :bar]
    end

    test "call/2 passes through non-cortex_ex paths" do
      conn = Plug.Test.conn(:get, "/other")
      result = CortexEx.call(conn, [])
      # Should pass through without halting
      refute result.halted
    end
  end

  describe "CortexEx.MCP.Server" do
    test "handles initialize request" do
      req = %{"method" => "initialize", "id" => 1, "jsonrpc" => "2.0"}
      result = CortexEx.MCP.Server.handle_request(req)

      assert result["jsonrpc"] == "2.0"
      assert result["id"] == 1
      assert result["result"]["protocolVersion"] == "2024-11-05"
      assert result["result"]["serverInfo"]["name"] == "cortex_ex"
    end

    test "handles tools/list request" do
      req = %{"method" => "tools/list", "id" => 2, "jsonrpc" => "2.0"}
      result = CortexEx.MCP.Server.handle_request(req)

      assert result["jsonrpc"] == "2.0"
      assert result["id"] == 2
      assert is_list(result["result"]["tools"])
    end

    test "handles ping request" do
      req = %{"method" => "ping", "id" => 3, "jsonrpc" => "2.0"}
      result = CortexEx.MCP.Server.handle_request(req)

      assert result["jsonrpc"] == "2.0"
      assert result["id"] == 3
      assert result["result"] == %{}
    end

    test "handles notifications/initialized with nil" do
      req = %{"method" => "notifications/initialized"}
      assert CortexEx.MCP.Server.handle_request(req) == nil
    end

    test "handles unknown method with error" do
      req = %{"method" => "unknown/method", "id" => 4, "jsonrpc" => "2.0"}
      result = CortexEx.MCP.Server.handle_request(req)

      assert result["jsonrpc"] == "2.0"
      assert result["id"] == 4
      assert result["error"]["code"] == -32601
    end

    test "handles unknown notification (no id) with nil" do
      req = %{"method" => "unknown/notification"}
      assert CortexEx.MCP.Server.handle_request(req) == nil
    end
  end

  describe "CortexEx.MCP.Tools" do
    test "list_all returns a list of tools" do
      tools = CortexEx.MCP.Tools.list_all()
      assert is_list(tools)

      # Should have at least the xref tools, eval, docs, routes, contexts
      names = Enum.map(tools, & &1.name)
      assert "xref_graph" in names
      assert "xref_callers" in names
      assert "project_eval" in names
      assert "get_docs" in names
      assert "routes" in names
      assert "contexts" in names
    end

    test "call with unknown tool returns error" do
      assert {:error, "Unknown tool: nonexistent"} = CortexEx.MCP.Tools.call("nonexistent", %{})
    end
  end

  describe "CortexEx.MCP.Tools.Eval" do
    test "evaluates simple expression" do
      assert {:ok, "6"} = CortexEx.MCP.Tools.Eval.project_eval(%{"code" => "1 + 2 + 3"})
    end

    test "returns error for invalid code" do
      assert {:error, _} = CortexEx.MCP.Tools.Eval.project_eval(%{"code" => "this is not valid"})
    end

    test "returns error when code param missing" do
      assert {:error, "code parameter is required"} = CortexEx.MCP.Tools.Eval.project_eval(%{})
    end
  end

  describe "CortexEx.MCP.Tools.Docs" do
    test "returns error for missing reference param" do
      assert {:error, "reference parameter is required"} =
               CortexEx.MCP.Tools.Docs.get_docs(%{})
    end

    test "fetches module docs for Enum" do
      result = CortexEx.MCP.Tools.Docs.get_docs(%{"reference" => "Enum"})
      assert {:ok, content} = result
      assert content =~ "Enum"
    end

    test "returns error for nonexistent module" do
      result =
        CortexEx.MCP.Tools.Docs.get_docs(%{"reference" => "NonExistentModule12345"})

      assert {:error, _} = result
    end
  end

  describe "CortexEx.MCP.Tools.Xref" do
    test "xref_callers returns error without module param" do
      assert {:error, "module parameter is required"} =
               CortexEx.MCP.Tools.Xref.xref_callers(%{})
    end
  end
end
