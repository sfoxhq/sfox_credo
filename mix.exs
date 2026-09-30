defmodule SfoxCredo.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :sfox_credo,
      description: "Credo checks used for Elixir projects at sFOX.",
      version: @version,
      source_url: "https://github.com/sfoxhq/sfox_credo",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :dev,
      deps: deps(),
      docs: &docs/0,
      package: package(),
      test_coverage: test_coverage(),
      dialyzer: [
        plt_add_apps: [:mix, :credo],
        plt_local_path: "priv/plts/project",
        plt_core_path: "priv/plts/core"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp package do
    [
      maintainers: ["sFOX"],
      licenses: ["Apache-2.0"],
      files: ~w(lib .formatter.exs mix.exs licences/* *.md),
      links: %{
        "GitHub" => "https://github.com/sfoxhq/sfox_credo",
        "Changelog" => "https://github.com/sfoxhq/sfox_credo/blob/main/CHANGELOG.md",
        "Issues" => "https://github.com/sfoxhq/sfox_credo/issues"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CONTRIBUTING.md": [filename: "CONTRIBUTING", title: "Contributing"],
        "CODE_OF_CONDUCT.md": [filename: "CODE_OF_CONDUCT", title: "Code of Conduct"],
        "CHANGELOG.md": [filename: "CHANGELOG", title: "CHANGELOG"],
        "LICENCE.md": [filename: "LICENCE", title: "Licence"],
        "licences/APACHE-2.0.txt": [filename: "APACHE-2.0", title: "Apache License, version 2.0"],
        "licences/dco.txt": [filename: "dco", title: "Developer Certificate of Origin"]
      ],
      canonical: "https://sfox-credo.hexdocs.pm/"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:castore, "~> 1.0", optional: true},
      {:credo, "~> 1.0", runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:test]},
      {:ex_doc, "~> 0.29", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp test_coverage do
    [
      tool: ExCoveralls
    ]
  end
end
