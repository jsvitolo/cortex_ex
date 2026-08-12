defmodule CortexEx do
  @behaviour Plug

  alias CortexEx.Auth

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    cond do
      # Only the paths this plug owns are forwarded; anything else under
      # /cortex_ex (e.g. the admin LiveView) belongs to the host router.
      match?(["cortex_ex", owned | _] when owned in ["mcp", "health"], conn.path_info) ->
        ["cortex_ex" | rest] = conn.path_info

        conn
        |> Plug.Conn.put_private(:cortex_ex_opts, opts)
        |> Plug.forward(rest, CortexEx.MCP.Router, [])
        |> Plug.Conn.halt()

      conn.method == "GET" and resource_metadata_request?(conn) ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(Auth.resource_metadata()))
        |> Plug.Conn.halt()

      # Other /cortex_ex paths (admin UI) fall through to the host router,
      # skipping request tracking like the rest of the cortex_ex namespace.
      match?(["cortex_ex" | _], conn.path_info) ->
        conn

      true ->
        # Track only host-app requests — MCP request bodies (tool args,
        # credentials) must not land in the buffer exposed by request tools.
        CortexEx.RequestTracker.Plug.call(conn, [])
    end
  end

  defp resource_metadata_request?(%{path_info: [".well-known", "oauth-protected-resource" | _] = path}) do
    Auth.enabled?() and path == Auth.metadata_path_info()
  end

  defp resource_metadata_request?(_), do: false
end
