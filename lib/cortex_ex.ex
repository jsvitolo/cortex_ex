defmodule CortexEx do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    conn = CortexEx.RequestTracker.Plug.call(conn, [])

    case conn.path_info do
      ["cortex_ex" | rest] ->
        conn
        |> Plug.Conn.put_private(:cortex_ex_opts, opts)
        |> Plug.forward(rest, CortexEx.MCP.Router, [])
        |> Plug.Conn.halt()

      _ ->
        conn
    end
  end
end
