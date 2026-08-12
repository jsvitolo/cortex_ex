defmodule CortexEx.Auth.Plug do
  @moduledoc false

  import Plug.Conn

  alias CortexEx.Auth

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      # Runs inside the forwarded MCP router, so path_info is relative.
      conn.path_info == ["health"] ->
        conn

      Auth.config() == nil ->
        assign(conn, :cortex_ex_identity, nil)

      true ->
        authenticate(conn)
    end
  end

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, identity} <- Auth.verify_token(String.trim(token)) do
      assign(conn, :cortex_ex_identity, identity)
    else
      [] -> unauthorized(conn, "invalid_request", "missing bearer token")
      {:error, reason} -> unauthorized(conn, "invalid_token", to_string(reason))
      _ -> unauthorized(conn, "invalid_request", "malformed authorization header")
    end
  end

  defp unauthorized(conn, error, description) do
    www_authenticate =
      ~s(Bearer error="#{error}", error_description="#{description}", ) <>
        ~s(resource_metadata="#{Auth.resource_metadata_url()}")

    conn
    |> put_resp_header("www-authenticate", www_authenticate)
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: error, error_description: description}))
    |> halt()
  end
end
