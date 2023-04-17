defmodule Excessibility.MixProject do
  use Mix.Project

  def project do
    [
      app: :excessibility,
      version: "0.3.0",
      elixir: "~> 1.12",
      start_permanent: false,
      description: description(),
      package: package(),
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp description do
    """
    Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Andrew Moore"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/launchscout/excessibility"}
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
      {:credo, ">= 1.5.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.18", only: :dev},
      {:floki, ">= 0.28.0"},
      {:gettext, ">= 0.0.0"},
      {:phoenix, ">= 1.5.0"},
      {:phoenix_live_view, ">= 0.17.5"},
      {:wallaby, ">= 0.25.0"}
    ]
  end

  defp aliases do
    [
      "assets.deploy": [
        "cmd --cd assets node build.mjs --deploy",
        "phx.digest"
      ]
    ]
  end
end
