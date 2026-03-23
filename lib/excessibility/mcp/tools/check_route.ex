defmodule Excessibility.MCP.Tools.CheckRoute do
  @moduledoc """
  MCP tool for checking a URL for accessibility issues without needing a test file.

  This tool can check a running Phoenix app's routes directly by:
  1. Checking if the app is running on the configured port
  2. Rendering the route and capturing HTML
  3. Running axe-core on the captured HTML
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.Subprocess

  @impl true
  def name, do: "check_route"

  @impl true
  def description do
    "FAST: Check a running Phoenix app for accessibility issues. " <>
      "Use this FIRST before slower test-based tools. Requires app running on localhost."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "url" => %{
          "type" => "string",
          "description" => "The URL or path to check (e.g., '/users' or 'http://localhost:4000/users')"
        },
        "port" => %{
          "type" => "integer",
          "description" => "Port the Phoenix app is running on (default: 4000)"
        },
        "wait_for" => %{
          "type" => "string",
          "description" => "CSS selector to wait for before checking (optional)"
        },
        "timeout" => %{
          "type" => "integer",
          "description" => "Timeout in ms (default: 30000). Increase for slow pages."
        }
      },
      "required" => ["url"]
    }
  end

  @impl true
  def execute(%{"url" => url} = args, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    wait_for = Map.get(args, "wait_for")
    timeout = Map.get(args, "timeout", 30_000)

    # Parse port from URL if it's a full URL, otherwise use the port arg or default
    {full_url, port} = normalize_url_and_port(url, Map.get(args, "port", 4000))

    if progress_callback, do: progress_callback.("Checking if app is running...", 0)

    case check_app_running(port) do
      :ok ->
        run_check(full_url, wait_for, timeout, progress_callback)

      {:error, :not_running} ->
        {:error, "Phoenix app not running on port #{port}. Start it with: mix phx.server"}
    end
  end

  def execute(_args, _opts) do
    {:error, "Missing required argument: url"}
  end

  defp normalize_url_and_port(url, default_port) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        # Parse port from full URL
        port = parse_port_from_url(url, default_port)
        {url, port}

      String.starts_with?(url, "/") ->
        {"http://localhost:#{default_port}#{url}", default_port}

      true ->
        {"http://localhost:#{default_port}/#{url}", default_port}
    end
  end

  defp parse_port_from_url(url, default_port) do
    case URI.parse(url) do
      %URI{port: nil} -> default_port
      %URI{port: port} -> port
    end
  end

  defp check_app_running(port) do
    case :gen_tcp.connect(~c"localhost", port, [:binary], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        {:error, :not_running}
    end
  end

  defp run_check(url, wait_for, timeout, progress_callback) do
    if progress_callback, do: progress_callback.("Running accessibility check...", 20)

    case run_axe_check(url, timeout) do
      {:ok, output} ->
        if progress_callback, do: progress_callback.("Parsing results...", 80)

        violations = parse_axe_output(output)
        summary = build_summary(violations)

        if progress_callback, do: progress_callback.("Complete", 100)

        {:ok,
         %{
           "url" => url,
           "violations" => violations,
           "summary" => summary
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_axe_check(url, timeout) do
    axe_runner_path = find_axe_runner()

    if axe_runner_path do
      {output, _exit_code} =
        Subprocess.run("node", [axe_runner_path, url], timeout: timeout, stderr_to_stdout: true)

      {:ok, output}
    else
      {:error, "axe-runner.js not found. Run: mix excessibility.install"}
    end
  end

  defp find_axe_runner do
    configured = Application.get_env(:excessibility, :axe_runner_path)

    if configured && File.exists?(configured) do
      configured
    else
      # Look in the dep's assets directory
      dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
      runner = Path.join([dep_path, "assets", "axe-runner.js"])
      if File.exists?(runner), do: runner
    end
  end

  defp parse_axe_output(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, data} when is_list(data) ->
        Enum.map(data, &parse_issue/1)

      {:ok, %{"issues" => issues}} when is_list(issues) ->
        Enum.map(issues, &parse_issue/1)

      _ ->
        []
    end
  end

  defp parse_issue(issue) when is_map(issue) do
    code = Map.get(issue, "code") || "unknown"
    rule = extract_rule(code)

    %{
      "code" => code,
      "type" => Map.get(issue, "type", "error"),
      "message" => Map.get(issue, "message", ""),
      "selector" => Map.get(issue, "selector"),
      "context" => Map.get(issue, "context"),
      "rule" => rule,
      "fix_hint" => get_fix_hint(rule)
    }
  end

  defp extract_rule(code) when is_binary(code) do
    cond do
      String.contains?(code, "H37") -> "H37"
      String.contains?(code, "H44") -> "H44"
      String.contains?(code, "H32") -> "H32"
      String.contains?(code, "H57") -> "H57"
      String.contains?(code, "F65") -> "F65"
      String.contains?(code, "contrast") or String.contains?(code, "Contrast") -> "contrast"
      true -> code
    end
  end

  defp get_fix_hint("H37"), do: "Add alt attribute to image"
  defp get_fix_hint("H44"), do: "Add label with for attribute"
  defp get_fix_hint("H32"), do: "Add submit button to form"
  defp get_fix_hint("H57"), do: "Add lang attribute to html"
  defp get_fix_hint("F65"), do: "Add title to iframe"
  defp get_fix_hint("contrast"), do: "Increase color contrast"
  defp get_fix_hint(_), do: nil

  defp build_summary(violations) do
    by_type = Enum.group_by(violations, & &1["type"])
    by_rule = Enum.group_by(violations, & &1["rule"])

    %{
      "total" => length(violations),
      "errors" => length(Map.get(by_type, "error", [])),
      "warnings" => length(Map.get(by_type, "warning", [])),
      "by_rule" => Map.new(by_rule, fn {rule, issues} -> {rule, length(issues)} end)
    }
  end
end
