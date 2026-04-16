defmodule CortexEx.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/jsvitolo/cortex_ex"

  def project do
    [
      app: :cortex_ex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: false,
      deps: deps(),
      name: "CortexEx",
      description: "Runtime intelligence for Cortex — Elixir MCP tools for code analysis, debugging, and observability",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {CortexEx.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:oban, "~> 2.0", optional: true},
      {:telemetry, "~> 1.0", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:phoenix_pubsub, "~> 2.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
