if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule CortexEx.Router do
    @moduledoc """
    Mounts the CortexEx admin UI in the host router.

    **The admin UI does no browser authentication itself** — mount it inside
    a pipeline that already authenticates admins:

        import CortexEx.Router

        scope "/" do
          pipe_through [:browser, :require_admin_user]
          cortex_ex_admin "/cortex_ex/admin"
        end

    The acting admin's email is resolved from
    `config :cortex_ex, admin_email_source: {MyApp.Accounts, :current_email, []}`
    (an MFA receiving the conn), falling back to `conn.assigns[:current_email]`.
    The resolved email must map to an `:admin` in `CortexEx.Users` — otherwise
    the page renders access denied.

    Note: `cortex_ex_admin/1` opens its own `live_session`, so it cannot be
    called inside another `live_session` block.
    """

    defmacro cortex_ex_admin(path) do
      quote do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        live_session :cortex_ex_admin, session: {CortexEx.Router, :__session__, []} do
          live unquote(path), CortexEx.AdminLive, :index
        end
      end
    end

    @doc false
    def __session__(conn) do
      email =
        case Application.get_env(:cortex_ex, :admin_email_source) do
          {mod, fun, args} -> apply(mod, fun, [conn | args])
          nil -> conn.assigns[:current_email]
        end

      %{"cortex_ex_admin_email" => email}
    end
  end
end
