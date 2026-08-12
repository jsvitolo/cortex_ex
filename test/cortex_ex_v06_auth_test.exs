defmodule CortexExV06AuthTest do
  use ExUnit.Case

  import CortexEx.AuthCase

  defp mcp_conn(body, headers \\ []) do
    conn =
      Plug.Test.conn(:post, "/cortex_ex/mcp", Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")

    Enum.reduce(headers, conn, fn {key, value}, conn ->
      Plug.Conn.put_req_header(conn, key, value)
    end)
  end

  defp ping_body, do: %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}

  describe "open mode (no auth config)" do
    test "MCP requests work without a token" do
      conn = CortexEx.call(mcp_conn(ping_body()), [])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["result"] == %{}
    end

    test "well-known metadata endpoint is not served" do
      conn = Plug.Test.conn(:get, "/.well-known/oauth-protected-resource/cortex_ex/mcp")
      result = CortexEx.call(conn, [])

      # Falls through to the host app (not halted by CortexEx)
      refute result.halted
    end

    test "unowned /cortex_ex paths fall through to the host router" do
      # e.g. the admin LiveView mounted at /cortex_ex/admin by the host
      conn = Plug.Test.conn(:get, "/cortex_ex/admin")
      result = CortexEx.call(conn, [])

      refute result.halted
      assert result.status == nil
    end
  end

  describe "auth enabled" do
    setup do
      jwk = generate_jwk()
      put_auth_config(public_jwks(jwk))
      start_supervised!(CortexEx.Auth.JwksCache)
      %{jwk: jwk}
    end

    test "401 without token, with WWW-Authenticate pointing at resource metadata" do
      conn = CortexEx.call(mcp_conn(ping_body()), [])

      assert conn.status == 401
      assert [www] = Plug.Conn.get_resp_header(conn, "www-authenticate")
      assert www =~ "Bearer"
      assert www =~ "resource_metadata=\"https://app.test/.well-known/oauth-protected-resource/cortex_ex/mcp\""
    end

    test "200 with a valid token", %{jwk: jwk} do
      token = sign_token(jwk, default_claims())
      conn = CortexEx.call(mcp_conn(ping_body(), [{"authorization", "Bearer #{token}"}]), [])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["result"] == %{}
    end

    test "rejects bad tokens", %{jwk: jwk} do
      now = System.system_time(:second)

      bad_tokens = [
        sign_token(jwk, default_claims(%{"exp" => now - 3600})),
        sign_token(jwk, default_claims(%{"iss" => "https://evil.test"})),
        sign_token(jwk, default_claims(%{"aud" => "https://other.test"})),
        sign_token(jwk, default_claims(%{"email" => "dev@outra.com"})),
        sign_token(jwk, default_claims(%{"email_verified" => false})),
        sign_token(jwk, default_claims(%{"hd" => "outra.com"})),
        sign_token(jwk, Map.delete(default_claims(), "email")),
        sign_token(jwk, default_claims(), kid: "unknown-kid"),
        hs256_token(default_claims()),
        sign_token(generate_jwk(), default_claims()),
        "not-a-jwt"
      ]

      for token <- bad_tokens do
        conn = CortexEx.call(mcp_conn(ping_body(), [{"authorization", "Bearer #{token}"}]), [])
        assert conn.status == 401, "expected 401 for token: #{String.slice(token, 0, 40)}"
      end
    end

    test "health stays open" do
      conn = CortexEx.call(Plug.Test.conn(:get, "/cortex_ex/health"), [])

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["status"] == "ok"
    end

    test "serves RFC 9728 protected resource metadata" do
      conn = CortexEx.call(Plug.Test.conn(:get, "/.well-known/oauth-protected-resource/cortex_ex/mcp"), [])

      assert conn.status == 200
      assert conn.halted

      body = Jason.decode!(conn.resp_body)
      assert body["resource"] == audience()
      assert body["authorization_servers"] == [issuer()]
      assert body["bearer_methods_supported"] == ["header"]
    end

    test "identity is threaded into the server", %{jwk: jwk} do
      token = sign_token(jwk, default_claims(%{"email" => "Dev@#{domain()}"}))

      body = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => "project_eval", "arguments" => %{"code" => "1 + 1"}}
      }

      # No allowlist store configured: only config admins pass. Add the email
      # as a config admin so the call succeeds end-to-end.
      Application.put_env(:cortex_ex, :admins, ["dev@#{domain()}"])
      on_exit(fn -> Application.delete_env(:cortex_ex, :admins) end)
      CortexEx.Users.Cache.clear()

      conn = CortexEx.call(mcp_conn(body, [{"authorization", "Bearer #{token}"}]), [])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert [%{"text" => "2"}] = response["result"]["content"]
    end
  end

  describe "config validation" do
    test "raises on partial auth config" do
      Application.put_env(:cortex_ex, CortexEx.Auth, issuer: "https://auth.test")
      on_exit(fn -> Application.delete_env(:cortex_ex, CortexEx.Auth) end)

      assert_raise ArgumentError, ~r/missing \[:audience, :allowed_domain\]/, fn ->
        CortexEx.Auth.validate_config!()
      end
    end
  end

  describe "request tracking" do
    test "MCP request bodies do not enter the request buffer" do
      CortexEx.RequestTracker.clear_requests()

      body = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "project_eval", "arguments" => %{"code" => "System.get_env()"}}
      }

      CortexEx.call(mcp_conn(body), [])
      Process.sleep(50)

      assert CortexEx.RequestTracker.get_recent_requests() == []
    end
  end
end
