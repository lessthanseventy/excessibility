defmodule Excessibility.AxeRunner do
  @moduledoc """
  Runs axe-core accessibility checks via Playwright.

  Wraps `assets/axe-runner.js` which launches a headless browser,
  navigates to the given URL, and runs axe-core analysis.

  Supports both `file://` URLs (for snapshots) and `http://` URLs
  (for live applications, storybook, or arbitrary websites).
  """

  @doc """
  Runs axe-core against the given URL.

  ## Options

    * `:screenshot` - Path to save a PNG screenshot
    * `:wait_for` - CSS selector to wait for before running axe
    * `:disable_rules` - List of axe rule IDs to disable
    * `:timeout` - Timeout in ms (default: 30_000)

  Returns `{:ok, result}` where result has `:violations`, `:passes`, `:incomplete` keys,
  or `{:error, reason}`.
  """
  def run(url, opts \\ []) do
    runner_path = axe_runner_path()

    if File.exists?(runner_path) do
      run_axe(runner_path, url, opts)
    else
      {:error, "axe-runner.js not found at #{runner_path}. Run `mix excessibility.install` first."}
    end
  end

  defp run_axe(runner_path, url, opts) do
    args = build_args(url, opts)

    case System.cmd("node", [runner_path | args],
           stderr_to_stdout: false,
           env: [{"NODE_NO_WARNINGS", "1"}]
         ) do
      {output, 0} ->
        parse_output(output, url)

      {_output, _code} ->
        {:error, "axe-core check failed for #{url}"}
    end
  end

  defp parse_output(output, url) do
    case Jason.decode(output) do
      {:ok, result} -> {:ok, normalize_result(result)}
      {:error, _} -> {:error, "Failed to parse axe-core output for #{url}"}
    end
  end

  defp build_args(url, opts) do
    [url]
    |> maybe_add_flag(opts, :screenshot, "--screenshot")
    |> maybe_add_flag(opts, :wait_for, "--wait-for")
    |> maybe_add_rules_flag(opts)
  end

  defp maybe_add_flag(args, opts, key, flag) do
    case Keyword.get(opts, key) do
      nil -> args
      value -> args ++ [flag, to_string(value)]
    end
  end

  defp maybe_add_rules_flag(args, opts) do
    case Keyword.get(opts, :disable_rules) do
      nil -> args
      rules -> args ++ ["--disable-rules", Enum.join(rules, ",")]
    end
  end

  defp normalize_result(result) do
    %{
      violations: Map.get(result, "violations", []),
      passes: Map.get(result, "passes", []),
      incomplete: Map.get(result, "incomplete", [])
    }
  end

  defp axe_runner_path do
    Application.get_env(:excessibility, :axe_runner_path) ||
      Path.join([dependency_root(), "assets", "axe-runner.js"])
  end

  defp dependency_root do
    case Mix.Project.deps_paths()[:excessibility] do
      nil -> File.cwd!()
      path -> path
    end
  end
end
