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
    CortexEx.MCP.Tools.PubSub,
    CortexEx.MCP.Tools.Tests,
    CortexEx.MCP.Tools.CortexBridge,
    CortexEx.MCP.Tools.Migrations,
    CortexEx.MCP.Tools.Hex
  ]

  def list_all do
    Enum.flat_map(@tool_modules, fn mod ->
      if Code.ensure_loaded?(mod), do: mod.tools(), else: []
    end)
    # Tools without an explicit access level are treated as :write (fail closed).
    |> Enum.map(&Map.put_new(&1, :access, :write))
  end

  @doc "Tools visible to a caller with the given permissions."
  def list_for(permissions) do
    Enum.filter(list_all(), &allowed?(permissions, &1.access))
  end

  def call(name, arguments), do: call(name, arguments, :admin)

  def call(name, arguments, permissions) do
    case Enum.find(list_all(), &(&1.name == name)) do
      nil ->
        {:error, "Unknown tool: #{name}"}

      tool ->
        if allowed?(permissions, tool.access) do
          tool.callback.(arguments)
        else
          {:error, :forbidden}
        end
    end
  end

  defp allowed?(:admin, _access), do: true
  defp allowed?({:member, _}, :read), do: true
  defp allowed?({:member, can_write}, :write), do: can_write
  defp allowed?(_, _), do: false
end
