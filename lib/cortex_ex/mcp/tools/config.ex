defmodule CortexEx.MCP.Tools.Config do
  @moduledoc false

  def tools do
    [
      %{
        name: "app_config",
        description: """
        Returns application configuration for an OTP app.
        Sensitive values (password, secret, token, key) are automatically masked.
        """,
        inputSchema: %{
          type: "object",
          required: ["app"],
          properties: %{
            app: %{
              type: "string",
              description: "OTP application name (e.g., 'my_app', 'phoenix', 'ecto')"
            }
          }
        },
        callback: &app_config/1
      },
      %{
        name: "list_apps",
        description: """
        Lists all loaded OTP applications with their description and version.
        Useful for understanding what libraries and applications are running.
        """,
        inputSchema: %{type: "object", properties: %{}},
        callback: &list_apps/1
      }
    ]
  end

  # ── app_config ────────────────────────────────────────────────

  def app_config(%{"app" => app_name}) do
    app = String.to_existing_atom(app_name)
    env = Application.get_all_env(app)

    if env == [] do
      {:error, "No configuration found for application: #{app_name}"}
    else
      result =
        env
        |> Enum.into(%{})
        |> mask_sensitive()
        |> stringify_keys()

      {:ok, Jason.encode!(result, pretty: true)}
    end
  rescue
    ArgumentError ->
      {:error, "Unknown application: #{app_name}"}

    e ->
      {:error, "app_config failed: #{Exception.message(e)}"}
  end

  def app_config(_), do: {:error, "app parameter is required"}

  # ── list_apps ─────────────────────────────────────────────────

  def list_apps(_args) do
    apps =
      Application.loaded_applications()
      |> Enum.map(fn {name, description, version} ->
        %{
          name: to_string(name),
          description: to_string(description),
          version: to_string(version)
        }
      end)
      |> Enum.sort_by(& &1.name)

    {:ok, Jason.encode!(apps, pretty: true)}
  rescue
    e -> {:error, "list_apps failed: #{Exception.message(e)}"}
  end

  # ── Sensitive value masking ───────────────────────────────────

  @sensitive_patterns ~w(password secret token key api_key private_key credential)

  defp mask_sensitive(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key_str = to_string(k) |> String.downcase()

      if Enum.any?(@sensitive_patterns, &String.contains?(key_str, &1)) do
        {k, "[FILTERED]"}
      else
        {k, mask_sensitive_value(v)}
      end
    end)
  end

  defp mask_sensitive(other), do: other

  defp mask_sensitive_value(map) when is_map(map), do: mask_sensitive(map)

  defp mask_sensitive_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.map(list, fn {k, v} ->
        key_str = to_string(k) |> String.downcase()

        if Enum.any?(@sensitive_patterns, &String.contains?(key_str, &1)) do
          {k, "[FILTERED]"}
        else
          {k, mask_sensitive_value(v)}
        end
      end)
    else
      Enum.map(list, &mask_sensitive_value/1)
    end
  end

  defp mask_sensitive_value(other), do: other

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(map) when is_map(map), do: stringify_keys(map)

  defp stringify_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Map.new(list, fn {k, v} -> {to_string(k), stringify_value(v)} end)
    else
      Enum.map(list, &stringify_value/1)
    end
  end

  defp stringify_value(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    to_string(atom)
  end

  defp stringify_value(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(&stringify_value/1)
  end

  defp stringify_value(pid) when is_pid(pid), do: inspect(pid)
  defp stringify_value(ref) when is_reference(ref), do: inspect(ref)
  defp stringify_value(fun) when is_function(fun), do: inspect(fun)
  defp stringify_value(other), do: other
end
