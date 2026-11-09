defmodule Excessibility.MixProject do
  use Mix.Project

  @source_url "https://github.com/lessthanseventy/excessibility"
  @version "0.21.0"

  @internal_modules [
    Excessibility.Capture,
    Excessibility.Debug.BenchmarkRun,
    Excessibility.Debug.Report,
    Excessibility.DigestCompare.Aggregate,
    Excessibility.DigestCompare.Notes,
    Excessibility.Scanner.Runner,
    Excessibility.TelemetryCapture.Diff,
    Excessibility.TelemetryCapture.EctoCapture,
    Excessibility.TelemetryCapture.Filter,
    Excessibility.TelemetryCapture.Formatter,
    Excessibility.TelemetryCapture.SnapshotStore,
    Excessibility.TelemetryCapture.Timeline,
    Excessibility.TelemetryCapture.Writer
  ]

  def project do
    [
      app: :excessibility,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: false,
      name: "Excessibility",
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      test_ignore_filters: [~r"/support/"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "docs/library-api.md",
        "docs/llm-debugging.md",
        "docs/telemetry-analysis.md",
        "CHANGELOG.md",
        "LICENSE.md"
      ],
      groups_for_modules: [
        "Accessibility snapshots": [
          Excessibility,
          Excessibility.Scanner,
          Excessibility.Snapshot,
          Excessibility.SnapshotDiff,
          Excessibility.HTML,
          Excessibility.Source,
          Excessibility.LiveView,
          Excessibility.LiveViewHelpers,
          Excessibility.Paths
        ],
        "LiveView rules": ~r/Excessibility\.LiveViewRules/,
        Review: ~r/Excessibility\.Review/,
        "Telemetry capture": [
          Excessibility.TelemetryCapture,
          Excessibility.TelemetryCapture.Analyzer,
          Excessibility.TelemetryCapture.Enricher,
          Excessibility.TelemetryCapture.Profiles,
          Excessibility.TelemetryCapture.Registry
        ],
        Analyzers: ~r/Excessibility\.TelemetryCapture\.Analyzers\./,
        Enrichers: ~r/Excessibility\.TelemetryCapture\.Enrichers\./,
        "Digest and benchmark": [
          Excessibility.Digest,
          Excessibility.DigestCompare,
          Excessibility.Benchmark,
          Excessibility.QueryEvidence,
          Excessibility.QueryPlan,
          Excessibility.SQLFingerprint,
          Excessibility.Dialect
        ],
        "MCP server": ~r/Excessibility\.MCP/,
        Behaviours: [
          Excessibility.SystemBehaviour,
          Excessibility.BrowserBehaviour,
          Excessibility.ScannerBehaviour,
          Excessibility.System
        ],
        "Mix tasks": ~r/Mix\.Tasks\./
      ],
      filter_modules: &public_module?/2
    ]
  end

  defp description do
    """
    Library for accessibility snapshot testing in Phoenix applications using axe-core and Playwright.
    """
  end

  defp package do
    [
      files: [
        "lib",
        "assets/package.json",
        "assets/package-lock.json",
        "assets/axe-runner.js",
        "assets/axe-crawl.js",
        "assets/resolve-playwright.js",
        "bin",
        "priv",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
      ],
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
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.0", only: :test},
      # ecto_sql + postgrex are exercised only by the DB-gated privacy regression
      # (test/telemetry_capture_real_postgres_test.exs); skipped without a database.
      {:ecto_sql, "~> 3.0", only: :test},
      {:postgrex, "~> 0.17", only: :test},
      {:ex_doc, "~> 0.18", only: :dev, runtime: false},
      {:floki, "~> 0.30"},
      {:igniter, "~> 0.7", optional: true, runtime: false},
      {:jason, "~> 1.4"},
      {:mix_test_interactive, "~> 6.0", only: :dev, runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:phoenix, "~> 1.5"},
      {:phoenix_live_view, "~> 0.17 or ~> 1.0"},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
      # Wallaby is optional - add it to your project if you want Wallaby.Session support.
      # `runtime: false` keeps the modules compiled and on the code path (so the
      # `Wallaby.Session` struct and `Code.ensure_loaded?/1` in `Excessibility.Source`
      # still work) but stops Wallaby's OTP application from auto-starting under
      # `mix test`. That auto-start runs `Wallaby.Chrome.validate/0`, which *raises*
      # when no `chromedriver` is on `PATH` — crashing the pure-unit suite on any
      # machine without a browser driver, even though every test mocks `:browser_mod`
      # and never needs a live driver.
      {:wallaby, "~> 0.25", optional: true, only: :test, runtime: false}
    ]
  end

  defp public_module?(mod, _meta) do
    name = inspect(mod)

    mod not in @internal_modules and not String.contains?(name, ".Dialect.")
  end
end
