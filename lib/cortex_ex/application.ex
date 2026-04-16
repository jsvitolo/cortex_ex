defmodule CortexEx.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CortexEx.LoggerBackend,
      CortexEx.ErrorTracker,
      CortexEx.RequestTracker,
      CortexEx.TelemetryTracker
    ]

    opts = [strategy: :one_for_one, name: CortexEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
