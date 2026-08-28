defmodule ExCoinbase.MixProject do
  use Mix.Project

  @version "0.2.2"
  @source_url "https://github.com/drdray1/ex_coinbase"

  def project do
    [
      app: :ex_coinbase,
      version: @version,
      test_coverage: [summary: [threshold: 90]],
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
      {:decimal, "~> 2.0 or ~> 3.0"},
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
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExCoinbase",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "REST API": [
          ExCoinbase.Accounts,
          ExCoinbase.Products,
          ExCoinbase.Orders,
          ExCoinbase.Predictions,
          ExCoinbase.Predictions.Kalshi,
          ExCoinbase.Fees,
          ExCoinbase.Portfolio,
          ExCoinbase.Futures,
          ExCoinbase.Convert,
          ExCoinbase.PaymentMethods,
          ExCoinbase.Public
        ],
        Authentication: [
          ExCoinbase.Auth,
          ExCoinbase.JWT
        ],
        WebSocket: [
          ExCoinbase.WebSocket,
          ExCoinbase.WebSocket.Client,
          ExCoinbase.WebSocket.Connection,
          ExCoinbase.WebSocket.MarketDataConnection
        ],
        Client: [
          ExCoinbase.Client,
          ExCoinbase.Query
        ]
      ]
    ]
  end
end
