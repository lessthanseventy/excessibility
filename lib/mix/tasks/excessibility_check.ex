defmodule Mix.Tasks.Excessibility.Check do
  @shortdoc "Run accessibility check on a URL"

  @moduledoc """
  Runs axe-core accessibility checks against any URL.

  ## Usage

      # Check a live website
      mix excessibility.check https://example.com

      # Check a local dev server
      mix excessibility.check http://localhost:4000/

      # Check with options
      mix excessibility.check https://example.com --wait-for "#main" --screenshot /tmp/shot.png

  ## Options

    * `--wait-for` - CSS selector to wait for before checking
    * `--screenshot` - Path to save a PNG screenshot
    * `--disable-rules` - Comma-separated axe rule IDs to skip
  """

  use Mix.Task

  alias Excessibility.AxeRunner

  @requirements ["app.config"]

  @impl Mix.Task
  def run([]) do
    Mix.raise("Usage: mix excessibility.check <url> [--wait-for selector] [--screenshot path]")
  end

  def run(args) do
    {opts, [url | _], _} =
      OptionParser.parse(args,
        strict: [wait_for: :string, screenshot: :string, disable_rules: :string]
      )

    runner_opts =
      opts
      |> Keyword.take([:wait_for, :screenshot])
      |> then(fn o ->
        case Keyword.get(opts, :disable_rules) do
          nil -> o
          rules -> Keyword.put(o, :disable_rules, String.split(rules, ","))
        end
      end)

    Mix.shell().info("Checking #{url}...\n")

    case AxeRunner.run(url, runner_opts) do
      {:ok, result} ->
        format_results(url, result)

      {:error, reason} ->
        Mix.shell().error("Error: #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp format_results(url, result) do
    violations = result.violations

    if violations == [] do
      Mix.shell().info("No accessibility violations found for #{url}")
    else
      Mix.shell().info("Found #{length(violations)} violation(s) for #{url}\n")

      Enum.each(violations, fn v ->
        impact = String.upcase(v["impact"] || "unknown")
        Mix.shell().info("  [#{impact}] #{v["id"]}: #{v["description"]}")
        Mix.shell().info("    Help: #{v["helpUrl"]}")
        Mix.shell().info("    #{length(v["nodes"])} element(s) affected\n")
      end)

      exit({:shutdown, 1})
    end
  end
end
