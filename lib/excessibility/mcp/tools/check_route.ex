defmodule Excessibility.MCP.Tools.CheckRoute do
  @moduledoc """
  MCP tool for checking a URL for accessibility issues without needing a test file.

  This tool can check a running Phoenix app's routes directly by:
  1. Checking if the app is running on the configured port
  2. Rendering the route and capturing HTML
  3. Running Pa11y on the captured HTML
  """

  @behaviour Excessibility.MCP.Tool

  @impl true
  def name, do: "check_route"

  @impl true
  def description do
    "Check a URL for accessibility issues without needing a test file. " <>
      "Requires the Phoenix app to be running. Returns structured violations."
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
          "description" => "Timeout in milliseconds (default: 30000)"
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
    if progress_callback, do: progress_callback.("Running Pa11y...", 20)

    pa11y_args = build_pa11y_args(url, wait_for, timeout)

    case run_pa11y(pa11y_args) do
      {:ok, output} ->
        if progress_callback, do: progress_callback.("Parsing results...", 80)

        violations = parse_pa11y_output(output)
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

  defp build_pa11y_args(url, wait_for, timeout) do
    base_args = ["--reporter", "json", "--timeout", to_string(timeout)]

    args =
      if wait_for do
        base_args ++ ["--wait-for-selector", wait_for]
      else
        base_args
      end

    args ++ [url]
  end

  defp find_pa11y do
    configured = Application.get_env(:excessibility, :pa11y_path)

    if configured && File.exists?(configured) do
      configured
    else
      # Always use system pa11y for MCP since we run from a different directory
      System.find_executable("pa11y") || System.find_executable("npx")
    end
  end

  defp run_pa11y(args) do
    case find_pa11y() do
      nil ->
        {:error, "Pa11y not found. Install with: npm install -g pa11y"}

      pa11y_path ->
        {cmd, cmd_args} = build_pa11y_command(pa11y_path, args)
        {output, _exit_code} = System.cmd(cmd, cmd_args, stderr_to_stdout: true)
        {:ok, output}
    end
  end

  defp build_pa11y_command(pa11y_path, args) do
    if String.ends_with?(pa11y_path, "npx") do
      {pa11y_path, ["pa11y" | args]}
    else
      {pa11y_path, args}
    end
  end

  defp parse_pa11y_output(output) when is_binary(output) do
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
