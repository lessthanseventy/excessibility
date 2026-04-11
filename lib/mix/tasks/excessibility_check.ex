defmodule Mix.Tasks.Excessibility.Check do
  @shortdoc "Run accessibility check on a URL"

  @moduledoc """
  Runs axe-core accessibility checks against any URL.

  This task is a thin wrapper around `Excessibility.Scanner.scan/2`.

  ## Usage

      # Check a live website
      mix excessibility.check https://example.com

      # Check a local dev server
      mix excessibility.check http://localhost:4000/

      # Check with options
      mix excessibility.check https://example.com --wait-for "#main" --screenshot /tmp/shot.png

  ## Options

    * `--wait-for` — CSS selector to wait for before checking
    * `--wait-until` — `load` | `domcontentloaded` | `networkidle`
    * `--screenshot` — Path to save a PNG screenshot
    * `--disable-rules` — Comma-separated axe rule IDs to skip
    * `--tags` — Comma-separated axe tags (default: `wcag2a,wcag2aa`)
    * `--timeout` — Navigation timeout in ms (default: `30000`)
    * `--viewport` — Viewport size as `WxH` (default: `1280x720`)
    * `--user-agent` — Override the default Chrome UA
  """

  use Mix.Task

  alias Excessibility.Scanner

  @requirements ["app.config"]

  @strict [
    wait_for: :string,
    wait_until: :string,
    screenshot: :string,
    disable_rules: :string,
    tags: :string,
    timeout: :integer,
    viewport: :string,
    user_agent: :string
  ]

  @impl Mix.Task
  def run([]) do
    Mix.raise("Usage: mix excessibility.check <url> [options]")
  end

  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: @strict)

    url =
      case positional do
        [url | _] -> url
        [] -> Mix.raise("Missing URL. Usage: mix excessibility.check <url> [options]")
      end

    scan_opts = build_scan_opts(opts)

    Mix.shell().info("Checking #{url}...\n")

    case Scanner.scan(url, scan_opts) do
      {:ok, report} ->
        print_report(url, report)

      {:error, reason} ->
        Mix.shell().error("Error: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp build_scan_opts(opts) do
    opts
    |> Enum.reduce([], fn
      {:wait_for, v}, acc -> Keyword.put(acc, :wait_for, v)
      {:wait_until, v}, acc -> Keyword.put(acc, :wait_until, parse_wait_until(v))
      {:screenshot, v}, acc -> Keyword.put(acc, :screenshot, v)
      {:disable_rules, v}, acc -> Keyword.put(acc, :disable_rules, String.split(v, ","))
      {:tags, v}, acc -> Keyword.put(acc, :tags, String.split(v, ","))
      {:timeout, v}, acc -> Keyword.put(acc, :timeout, v)
      {:viewport, v}, acc -> Keyword.put(acc, :viewport, parse_viewport(v))
      {:user_agent, v}, acc -> Keyword.put(acc, :user_agent, v)
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp parse_wait_until(v) when v in ["load", "domcontentloaded", "networkidle"], do: String.to_atom(v)

  defp parse_wait_until(other), do: Mix.raise("Invalid --wait-until value: #{other}")

  defp parse_viewport(v) do
    case String.split(v, "x") do
      [w, h] ->
        with {wi, ""} <- Integer.parse(w),
             {hi, ""} <- Integer.parse(h) do
          {wi, hi}
        else
          _ -> Mix.raise("Invalid --viewport: #{v} (expected WxH, e.g. 1280x720)")
        end

      _ ->
        Mix.raise("Invalid --viewport: #{v} (expected WxH, e.g. 1280x720)")
    end
  end

  defp print_report(url, %{violations: []}) do
    Mix.shell().info("No accessibility violations found for #{url}")
  end

  defp print_report(url, %{violations: violations}) do
    Mix.shell().info("Found #{length(violations)} violation(s) for #{url}\n")

    Enum.each(violations, fn v ->
      impact_label = v.impact |> impact_label() |> String.upcase()
      Mix.shell().info("  [#{impact_label}] #{v.id}: #{v.description}")
      Mix.shell().info("    Help: #{v.help_url}")
      Mix.shell().info("    #{length(v.nodes)} element(s) affected\n")
    end)

    exit({:shutdown, 1})
  end

  defp impact_label(nil), do: "unknown"
  defp impact_label(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp impact_label(other), do: to_string(other)

  defp format_error(:timeout), do: "scan timed out"
  defp format_error({:http_error, status}), do: "HTTP #{status}"
  defp format_error({:navigation_failed, msg}), do: "navigation failed: #{msg}"
  defp format_error({:playwright_error, msg}), do: msg
  defp format_error({:invalid_url, reason}), do: "invalid URL (#{reason})"
  defp format_error(other), do: inspect(other)
end
