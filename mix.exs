defmodule Excessibility.MixProject do
  use Mix.Project

  @source_url "https://github.com/lessthanseventy/excessibility"
  @version "0.8.2"

  def project do
    [
      app: :excessibility,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: false,
      name: "Excessibility",
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "LICENSE.md"],
      groups_for_modules: [
        Core: [
          Excessibility,
          Excessibility.Snapshot,
          Excessibility.HTML,
          Excessibility.Source
        ],
        Behaviours: [
          Excessibility.SystemBehaviour,
          Excessibility.BrowserBehaviour
        ],
        Implementations: [
          Excessibility.System,
          Excessibility.LiveView
        ]
      ]
    ]
  end

  defp description do
    """
    Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby.
    """
  end

  defp package do
    [
      files: ["lib", "assets", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Andrew Moore"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/lessthanseventy/excessibility"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:chromic_pdf, ">= 1.14.0"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.0", only: :test},
      {:ex_doc, "~> 0.18", only: :dev, runtime: false},
      {:floki, ">= 0.30.0"},
      {:igniter, ">= 0.7.0", runtime: false},
      {:jason, "~> 1.4"},
      {:mix_test_interactive, "~> 5.0", only: :dev, runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:phoenix, ">= 1.5.0"},
      {:phoenix_live_view, ">= 0.17.0"},
      {:styler, "~> 0.9", only: [:dev, :test], runtime: false},
      {:wallaby, ">= 0.25.0"}
    ]
  end
end
