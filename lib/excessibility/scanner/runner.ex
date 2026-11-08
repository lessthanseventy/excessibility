defmodule Excessibility.Scanner.Runner do
  @moduledoc """
  Runs `axe-runner.js` through Playwright for `Excessibility.Scanner`, falling
  back to a curl fetch of the page when the browser cannot reach the URL.
  """

  alias Excessibility.Scanner

  def run_with_fallback(runner_path, url, opts) do
    case run_playwright(runner_path, url, opts) do
      {:ok, report} ->
        {:ok, Map.put(report, :url, url)}

      {:error, reason} = error ->
        fallback? = Keyword.get(opts, :fallback, true)
        remote? = String.starts_with?(url, "http")

        if fallback? and remote? and fallback_eligible?(reason) do
          run_curl_fallback(runner_path, url, opts, reason)
        else
          error
        end
    end
  end

  def fallback_eligible?(:timeout), do: true
  def fallback_eligible?({:navigation_failed, _}), do: true
  def fallback_eligible?({:playwright_error, _}), do: true
  def fallback_eligible?(_), do: false

  def run_curl_fallback(runner_path, url, opts, original_error) do
    tmp_path = Path.join(System.tmp_dir!(), "axe_fallback_#{System.unique_integer([:positive])}.html")

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
      "Upgrade-Insecure-Requests: 1",
      "-o",
      tmp_path,
      "-w",
      "%{http_code}",
      url
    ]

    case System.cmd("curl", curl_args, stderr_to_stdout: false) do
      {status_code, 0} ->
        code = String.trim(status_code)
        process_curl_result(code, tmp_path, runner_path, url, opts, original_error)

      _ ->
        File.rm(tmp_path)
        {:error, original_error}
    end
  end

  defp process_curl_result(code, tmp_path, runner_path, url, opts, original_error) when code in ["200", "301", "302"] do
    if File.exists?(tmp_path) do
      file_url = "file://" <> tmp_path
      fallback_opts = Keyword.drop(opts, [:screenshot, :fallback])
      result = run_playwright(runner_path, file_url, fallback_opts)
      File.rm(tmp_path)

      case result do
        {:ok, report} ->
          {:ok,
           report
           |> Map.put(:url, url)
           |> Map.put(:final_url, url)
           |> Map.put(:fallback, %{method: :curl, original_error: original_error})}

        _ ->
          {:error, original_error}
      end
    else
      {:error, {:playwright_error, "curl reported #{code} but wrote no body"}}
    end
  end

  defp process_curl_result(code, tmp_path, _runner_path, _url, _opts, _original_error) do
    File.rm(tmp_path)

    case Integer.parse(code) do
      {status, _} when status >= 400 -> {:error, {:http_error, status}}
      _ -> {:error, {:playwright_error, "curl got HTTP #{code}"}}
    end
  end

  defp run_playwright(runner_path, url, opts) do
    args = build_args(url, opts)

    case System.cmd("node", [runner_path | args],
           stderr_to_stdout: false,
           env: [{"NODE_NO_WARNINGS", "1"} | playwright_env()]
         ) do
      {output, 0} ->
        Scanner.parse_output(output, url)

      {output, _code} ->
        case Scanner.parse_error_output(output) do
          {:ok, error} -> {:error, error}
          :unparseable -> {:error, {:playwright_error, String.trim(output)}}
        end
    end
  end

  defp playwright_env do
    Enum.flat_map(
      [{"EXCESSIBILITY_PLAYWRIGHT_PATH", :playwright_path}, {"EXCESSIBILITY_NODE_MODULES_PATH", :node_modules_path}],
      fn {var, key} ->
        case Application.get_env(:excessibility, key) do
          nil -> []
          path -> [{var, Path.expand(path)}]
        end
      end
    )
  end

  defp build_args(url, opts) do
    [url]
    |> maybe_add(opts, :screenshot, "--screenshot", &to_string/1)
    |> maybe_add(opts, :wait_for, "--wait-for", &to_string/1)
    |> maybe_add_wait_until(opts)
    |> maybe_add(opts, :timeout, "--timeout", &to_string/1)
    |> maybe_add(opts, :user_agent, "--user-agent", &to_string/1)
    |> maybe_add_list(opts, :disable_rules, "--disable-rules")
    |> maybe_add_list(opts, :tags, "--tags")
    |> maybe_add_viewport(opts)
    |> maybe_add_viewports(opts)
    |> maybe_add_clipping(opts)
  end

  defp maybe_add_clipping(args, opts) do
    if Keyword.get(opts, :check_clipping, false) do
      args = args ++ ["--check-clipping"]

      case Keyword.get(opts, :clipping_ratio) do
        ratio when is_float(ratio) and ratio > 0 and ratio <= 1 -> args ++ ["--clipping-ratio", to_string(ratio)]
        _ -> args
      end
    else
      args
    end
  end

  defp maybe_add(args, opts, key, flag, fmt) do
    case Keyword.get(opts, key) do
      nil -> args
      "" -> args
      value -> args ++ [flag, fmt.(value)]
    end
  end

  defp maybe_add_list(args, opts, key, flag) do
    case Keyword.get(opts, key) do
      nil -> args
      [] -> args
      list when is_list(list) -> args ++ [flag, Enum.join(list, ",")]
    end
  end

  defp maybe_add_wait_until(args, opts) do
    case Keyword.get(opts, :wait_until) do
      nil -> args
      value when value in [:load, :domcontentloaded, :networkidle] -> args ++ ["--wait-until", Atom.to_string(value)]
      value when is_binary(value) -> args ++ ["--wait-until", value]
      _ -> args
    end
  end

  defp maybe_add_viewport(args, opts) do
    case Keyword.get(opts, :viewport) do
      {w, h} when is_integer(w) and is_integer(h) and w > 0 and h > 0 ->
        args ++ ["--viewport", "#{w}x#{h}"]

      _ ->
        args
    end
  end

  defp maybe_add_viewports(args, opts) do
    specs =
      opts
      |> Keyword.get(:viewports, [])
      |> Enum.filter(&valid_viewport?/1)
      |> Enum.map_join(",", fn {w, h} -> "#{w}x#{h}" end)

    if specs == "", do: args, else: args ++ ["--viewports", specs]
  end

  defp valid_viewport?({w, h}) when is_integer(w) and is_integer(h) and w > 0 and h > 0, do: true
  defp valid_viewport?(_), do: false
end
