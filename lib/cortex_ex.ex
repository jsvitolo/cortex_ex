defmodule CortexEx do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["cortex_ex" | rest]} = conn, opts) do
    conn
    |> Plug.Conn.put_private(:cortex_ex_opts, opts)
    |> Plug.forward(rest, CortexEx.MCP.Router, [])
    |> Plug.Conn.halt()
  end

  def call(conn, _opts), do: conn
end
