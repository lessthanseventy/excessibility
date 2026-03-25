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

  If Playwright fails (timeout, WAF block, protocol error), automatically
  falls back to fetching the HTML via curl and scanning it as a local file.
  The fallback won't execute JavaScript, so SPA content may be missing,
  but server-rendered pages get full results.

  ## Options

    * `:screenshot` - Path to save a PNG screenshot
    * `:wait_for` - CSS selector to wait for before running axe
    * `:disable_rules` - List of axe rule IDs to disable
    * `:fallback` - Fall back to curl if Playwright fails (default: `true`)

  Returns `{:ok, result}` where result has `:violations`, `:passes`, `:incomplete` keys,
  or `{:error, reason}`. When curl fallback is used, result also has `:fallback` key.
  """
  def run(url, opts \\ []) do
    runner_path = axe_runner_path()

    if File.exists?(runner_path) do
      case run_playwright(runner_path, url, opts) do
        {:ok, result} ->
          {:ok, result}

        {:error, reason} = error ->
          fallback? = Keyword.get(opts, :fallback, true)
          remote_url? = String.starts_with?(url, "http")

          if fallback? and remote_url? do
            run_curl_fallback(runner_path, url, opts, reason)
          else
            error
          end
      end
    else
      {:error, "axe-runner.js not found at #{runner_path}. Run `mix excessibility.install` first."}
    end
  end

  defp run_playwright(runner_path, url, opts) do
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

  defp run_curl_fallback(runner_path, url, opts, original_error) do
    tmp_path = Path.join(System.tmp_dir!(), "axe_fallback_#{System.unique_integer([:positive])}.html")

    # Mimic a real Chrome browser fingerprint to bypass WAFs
    curl_args = [
      "-sL",
      "--max-time",
      "15",
      "--compressed",
      "-H",
      "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      "-H",
      "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
      "-H",
      "Accept-Language: en-US,en;q=0.9",
      "-H",
      "Accept-Encoding: gzip, deflate, br",
      "-H",
      "Sec-Fetch-Dest: document",
      "-H",
      "Sec-Fetch-Mode: navigate",
      "-H",
      "Sec-Fetch-Site: none",
      "-H",
      "Sec-Fetch-User: ?1",
      "-H",
      "Sec-Ch-Ua: \"Chromium\";v=\"125\", \"Not.A/Brand\";v=\"24\"",
      "-H",
      "Sec-Ch-Ua-Mobile: ?0",
      "-H",
      "Sec-Ch-Ua-Platform: \"Linux\"",
      "-H",
      "Upgrade-Insecure-Requests: 1",
      "-H",
      "Cache-Control: max-age=0",
      "-o",
      tmp_path,
      "-w",
      "%{http_code}",
      url
    ]

    case System.cmd("curl", curl_args, stderr_to_stdout: false) do
      {status_code, 0} ->
        code = String.trim(status_code)

        if code in ["200", "301", "302"] and File.exists?(tmp_path) do
          file_url = "file://" <> tmp_path
          # Don't fallback again, no screenshots for curl-fetched pages
          fallback_opts = Keyword.drop(opts, [:screenshot, :fallback])

          result = run_playwright(runner_path, file_url, fallback_opts)

          File.rm(tmp_path)

          case result do
            {:ok, data} ->
              {:ok, Map.put(data, :fallback, %{method: :curl, original_error: original_error})}

            _ ->
              File.rm(tmp_path)
              {:error, "Playwright failed (#{original_error}), curl fallback also failed"}
          end
        else
          File.rm(tmp_path)
          {:error, "Playwright failed (#{original_error}), curl got HTTP #{code}"}
        end

      _ ->
        File.rm(tmp_path)
        {:error, "Playwright failed (#{original_error}), curl also failed"}
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
