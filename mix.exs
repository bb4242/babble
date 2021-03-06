defmodule Babble.MixProject do
  use Mix.Project

  def project do
    [
      app: :babble,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: applications(Mix.env()),
      mod: {Babble.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: elixirc_paths(:all) ++ ["test/support"]
  defp elixirc_paths(_all), do: ["lib"]

  defp applications(_all), do: [:logger]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dev and test dependencies
      {:ex_doc, "~> 0.18", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:credo, "~> 0.9.2", only: :dev, runtime: false},
      {:excoveralls, "~> 0.8.2", only: :test},
      {:pre_commit, github: "bb4242/elixir-pre-commit", tag: "cdef380", only: :dev},
      {:junit_formatter, "~> 2.1", only: :test},
      {:libcluster, "~> 3.0", runtime: false}
    ]
  end
end
