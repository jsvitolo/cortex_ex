defmodule CortexEx.MCP.Tools do
  @moduledoc false

  @tool_modules [
    CortexEx.MCP.Tools.Xref,
    CortexEx.MCP.Tools.Ecto,
    CortexEx.MCP.Tools.Routes,
    CortexEx.MCP.Tools.Contexts,
    CortexEx.MCP.Tools.Eval,
    CortexEx.MCP.Tools.Docs,
    CortexEx.MCP.Tools.Errors,
    CortexEx.MCP.Tools.Logs,
    CortexEx.MCP.Tools.Requests,
    CortexEx.MCP.Tools.Runtime,
    CortexEx.MCP.Tools.Oban,
    CortexEx.MCP.Tools.Config,
    CortexEx.MCP.Tools.Telemetry,
    CortexEx.MCP.Tools.LiveView,
    CortexEx.MCP.Tools.PubSub
  ]

  def list_all do
    Enum.flat_map(@tool_modules, fn mod ->
      if Code.ensure_loaded?(mod), do: mod.tools(), else: []
    end)
  end

  def call(name, arguments) do
    tool = Enum.find(list_all(), &(&1.name == name))

    if tool do
      tool.callback.(arguments)
    else
      {:error, "Unknown tool: #{name}"}
    end
  end
end
