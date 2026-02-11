defmodule ExCoinbase.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dray/ex_coinbase"

  def project do
    [
      app: :ex_coinbase,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Elixir client for the Coinbase Advanced Trade API",
      package: package(),

      # Docs
      name: "ExCoinbase",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ExCoinbase.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:decimal, "~> 2.0"},
      {:websockex, "~> 0.4"},
      {:plug, "~> 1.14", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExCoinbase",
      extras: ["README.md"],
      groups_for_modules: [
        "REST API": [
          ExCoinbase.Accounts,
          ExCoinbase.Products,
          ExCoinbase.Orders,
          ExCoinbase.Fees,
          ExCoinbase.Portfolio
        ],
        Authentication: [
          ExCoinbase.Auth,
          ExCoinbase.JWT
        ],
        WebSocket: [
          ExCoinbase.WebSocket,
          ExCoinbase.WebSocket.Client,
          ExCoinbase.WebSocket.Connection
        ],
        Client: [
          ExCoinbase.Client
        ]
      ]
    ]
  end
end
