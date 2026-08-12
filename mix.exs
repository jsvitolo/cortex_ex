defmodule CortexEx.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/jsvitolo/cortex_ex"

  def project do
    [
      app: :cortex_ex,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:joken, "~> 2.6"},
      {:ecto_sql, "~> 3.10", optional: true},
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
