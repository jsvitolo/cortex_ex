defmodule CortexEx.Application do
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    CortexEx.Auth.validate_config!()

    unless CortexEx.Auth.enabled?() do
      Logger.warning(
        "CortexEx MCP endpoint is UNAUTHENTICATED — do not expose it publicly. " <>
          "Configure `config :cortex_ex, CortexEx.Auth, ...` for production use."
      )
    end

    children =
      [
        CortexEx.LoggerBackend,
        CortexEx.ErrorTracker,
        CortexEx.RequestTracker,
        CortexEx.TelemetryTracker,
        CortexEx.Users.Cache,
        CortexEx.Audit
      ] ++ auth_children()

    opts = [strategy: :one_for_one, name: CortexEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp auth_children do
    if CortexEx.Auth.enabled?(), do: [CortexEx.Auth.JwksCache], else: []
  end
end
