defmodule Lumen.MixProject do
  use Mix.Project

  def project do
    [
      app: :lumen,
      description: "Mix support for the Lumen compiler/runtime",
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs]},
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["Apache 2.0"],
      links: %{
        GitHub: "https://github.com/bitwalker/lumen-elixir",
      }
    ]
  end
end
