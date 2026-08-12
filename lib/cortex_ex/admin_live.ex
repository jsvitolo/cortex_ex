if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule CortexEx.AdminLive do
    @moduledoc false

    use Phoenix.LiveView

    alias CortexEx.Users

    @impl true
    def mount(_params, session, socket) do
      actor = session["cortex_ex_admin_email"]
      permissions = if is_binary(actor), do: Users.get_permissions(actor), else: :denied

      socket =
        socket
        |> assign(actor: actor, authorized?: permissions == :admin, error: nil, users: [])
        |> maybe_load_users()

      {:ok, socket}
    end

    @impl true
    def handle_event("add_user", params, socket) do
      attrs = %{
        email: params["email"],
        role: "member",
        can_write: params["can_write"] == "true",
        inserted_by: socket.assigns.actor
      }

      attrs
      |> Users.add_user(socket.assigns.actor)
      |> handle_result(socket)
    end

    def handle_event("toggle_write", %{"email" => email, "to" => to}, socket) do
      email
      |> Users.set_can_write(to == "true", socket.assigns.actor)
      |> handle_result(socket)
    end

    def handle_event("set_role", %{"email" => email, "role" => role}, socket) do
      email
      |> Users.set_role(role, socket.assigns.actor)
      |> handle_result(socket)
    end

    def handle_event("remove_user", %{"email" => email}, socket) do
      email
      |> Users.remove_user(socket.assigns.actor)
      |> handle_result(socket)
    end

    defp handle_result(result, socket) do
      case result do
        {:error, reason} ->
          {:noreply, socket |> assign(error: format_error(reason)) |> maybe_load_users()}

        _ok ->
          {:noreply, socket |> assign(error: nil) |> maybe_load_users()}
      end
    end

    defp maybe_load_users(%{assigns: %{authorized?: true}} = socket),
      do: assign(socket, users: Users.list_users())

    defp maybe_load_users(socket), do: socket

    defp format_error(:no_store_configured),
      do: "No store configured — set `config :cortex_ex, repo: MyApp.Repo` and run the migration."

    defp format_error(:config_admin_immutable),
      do: "Config-bootstrapped admins can only be changed in config."

    defp format_error(reason), do: "Operation failed: #{inspect(reason)}"

    @impl true
    def render(assigns) do
      ~H"""
      <div style="max-width: 780px; margin: 2rem auto; font-family: system-ui, sans-serif;">
        <h1 style="font-size: 1.4rem;">CortexEx — Access Control</h1>

        <%= if not @authorized? do %>
          <p style="padding: 1rem; background: #fef2f2; color: #b91c1c; border-radius: 6px;">
            Access denied. Your email (<code><%= @actor || "unknown" %></code>) is not a CortexEx admin.
          </p>
        <% else %>
          <%= if @error do %>
            <p style="padding: 0.75rem; background: #fef2f2; color: #b91c1c; border-radius: 6px;">
              <%= @error %>
            </p>
          <% end %>

          <form phx-submit="add_user" style="display: flex; gap: 0.5rem; margin: 1rem 0; align-items: center;">
            <input
              type="email"
              name="email"
              placeholder="email@empresa.com"
              required
              style="flex: 1; padding: 0.5rem; border: 1px solid #d1d5db; border-radius: 6px;"
            />
            <label style="display: flex; gap: 0.25rem; align-items: center;">
              <input type="checkbox" name="can_write" value="true" /> write
            </label>
            <button style="padding: 0.5rem 1rem; background: #4f46e5; color: white; border: 0; border-radius: 6px; cursor: pointer;">
              Add
            </button>
          </form>

          <table style="width: 100%; border-collapse: collapse;">
            <thead>
              <tr style="text-align: left; border-bottom: 2px solid #e5e7eb;">
                <th style="padding: 0.5rem;">Email</th>
                <th style="padding: 0.5rem;">Role</th>
                <th style="padding: 0.5rem;">Write</th>
                <th style="padding: 0.5rem;"></th>
              </tr>
            </thead>
            <tbody>
              <%= for user <- @users do %>
                <tr style="border-bottom: 1px solid #f3f4f6;">
                  <td style="padding: 0.5rem;"><%= user.email %></td>
                  <td style="padding: 0.5rem;">
                    <%= user.role %>
                    <%= if user.source == :config do %>
                      <span style="font-size: 0.75rem; background: #eef2ff; color: #4f46e5; padding: 0.1rem 0.4rem; border-radius: 4px;">
                        config
                      </span>
                    <% end %>
                  </td>
                  <td style="padding: 0.5rem;">
                    <%= if user.role == "admin" do %>
                      —
                    <% else %>
                      <button
                        phx-click="toggle_write"
                        phx-value-email={user.email}
                        phx-value-to={to_string(not user.can_write)}
                        style="cursor: pointer; border: 1px solid #d1d5db; border-radius: 6px; padding: 0.2rem 0.6rem; background: white;"
                      >
                        <%= if user.can_write, do: "on", else: "off" %>
                      </button>
                    <% end %>
                  </td>
                  <td style="padding: 0.5rem; text-align: right;">
                    <%= if user.source != :config do %>
                      <%= if user.role == "admin" do %>
                        <button
                          phx-click="set_role"
                          phx-value-email={user.email}
                          phx-value-role="member"
                          style="cursor: pointer; border: 0; background: none; color: #4f46e5;"
                        >
                          demote
                        </button>
                      <% else %>
                        <button
                          phx-click="set_role"
                          phx-value-email={user.email}
                          phx-value-role="admin"
                          style="cursor: pointer; border: 0; background: none; color: #4f46e5;"
                        >
                          promote
                        </button>
                      <% end %>
                      <button
                        phx-click="remove_user"
                        phx-value-email={user.email}
                        data-confirm={"Remove #{user.email}?"}
                        style="cursor: pointer; border: 0; background: none; color: #b91c1c;"
                      >
                        remove
                      </button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
      """
    end
  end
end
