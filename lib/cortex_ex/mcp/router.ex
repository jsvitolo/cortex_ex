defmodule CortexEx.MCP.Router do
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # MCP initialize
  post "/mcp" do
    body = conn.body_params
    response = CortexEx.MCP.Server.handle_request(body)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(response))
  end

  # Health check
  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok", version: Mix.Project.config()[:version]}))
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
