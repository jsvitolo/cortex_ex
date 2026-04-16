defmodule CortexEx.RequestTracker.Plug do
  @moduledoc false
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start_time = System.monotonic_time(:millisecond)

    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time(:millisecond) - start_time
      CortexEx.RequestTracker.track_request(conn, duration)
      conn
    end)
  end
end
