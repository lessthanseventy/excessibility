defmodule Excessibility.Scanner do
  @moduledoc """
  Runtime scanner for arbitrary URLs.

  Unlike the ExUnit integration in `Excessibility`, this module is intended
  to be called from application code — LiveViews, background jobs, CLI
  wrappers, external HTTP APIs, etc. It launches Playwright (via
  `assets/axe-runner.js`), navigates to the given URL, and runs axe-core
  analysis, returning a structured report.

  ## Usage

      {:ok, report} = Excessibility.Scanner.scan("https://example.com")

      for v <- report.violations do
        IO.puts("[\#{v.impact}] \#{v.id}: \#{v.description}")
      end

  On failure, returns `{:error, reason}` where `reason` is a typed tuple
  (see `t:scan_error/0`). Pattern-match cleanly from LiveView handlers:

      case Excessibility.Scanner.scan(url, timeout: 20_000) do
        {:ok, report} -> send(self(), {:scan_complete, report})
        {:error, :timeout} -> send(self(), {:scan_failed, :timeout})
        {:error, {:http_error, status}} -> ...
        {:error, {:navigation_failed, msg}} -> ...
        {:error, {:invalid_url, _}} -> ...
        {:error, {:playwright_error, msg}} -> ...
      end

  ## Fallback behavior

  If Playwright fails to reach a remote URL (timeout, WAF block, or
  navigation error), the scanner automatically retries by fetching the
  HTML via `curl` and scanning it as a local file. This won't execute
  JavaScript, so SPA content may be missing, but server-rendered pages
  still get full results. When the fallback path is used, the returned
  report has a non-nil `:fallback` field. Disable with `fallback: false`.

  `file://` URLs never fall back (curl can't fetch them).

  ## Reusing an existing Playwright installation

  By default the scanner uses the Playwright copy bundled under this
  library's `assets/` directory. Projects that already have Playwright
  installed (with browsers downloaded) can point Excessibility at it and
  skip the second browser download:

      config :excessibility, playwright_path: "assets/node_modules/playwright"

  To skip the bundled `npm install` entirely, point Excessibility at a
  host `node_modules` directory that provides both `playwright` and
  `@axe-core/playwright`:

      config :excessibility, node_modules_path: "assets/node_modules"

  Relative paths are expanded from the project root. Note that resolving
  `@axe-core/playwright` from the host also pins the axe-core version, so
  `engine.axe_version` in reports follows the host installation — an axe
  minor bump can change finding sets relative to earlier baselines.
  """
  @behaviour Excessibility.ScannerBehaviour

  alias Excessibility.Scanner.Runner

  @typedoc "axe-core impact level, normalized to an atom."
  @type impact :: :critical | :serious | :moderate | :minor | nil

  @typedoc "A single offending element within a violation."
  @type node_info :: %{
          target: [String.t()],
          html: String.t(),
          failure_summary: String.t()
        }

  @typedoc "A single axe-core violation."
  @type violation :: %{
          id: String.t(),
          impact: impact(),
          description: String.t(),
          help: String.t(),
          help_url: String.t(),
          tags: [String.t()],
          nodes: [node_info()]
        }

  @typedoc "Engine metadata for a scan."
  @type engine_info :: %{
          axe_version: String.t() | nil,
          chromium_version: String.t() | nil
        }

  @typedoc "Metadata describing a curl fallback, when one was used."
  @type fallback_info :: %{method: atom(), original_error: term()} | nil

  @typedoc "A complete scan report."
  @type report :: %{
          url: String.t(),
          final_url: String.t(),
          violations: [violation()],
          incomplete: [violation()],
          passes_count: non_neg_integer(),
          inapplicable_count: non_neg_integer(),
          timestamp: DateTime.t(),
          duration_ms: non_neg_integer(),
          engine: engine_info(),
          warnings: [String.t()],
          clipping: clipping_info(),
          fallback: fallback_info()
        }

  @typedoc "Structured scan failure."
  @type scan_error ::
          :timeout
          | {:http_error, non_neg_integer()}
          | {:navigation_failed, String.t()}
          | {:playwright_error, String.t()}
          | {:invalid_url, atom()}

  @typedoc "An interactive element that is mostly outside the visible area."
  @type clipped_element :: %{
          selector: String.t(),
          width: non_neg_integer(),
          visible: non_neg_integer(),
          ratio: float(),
          html: String.t()
        }

  @typedoc "Clipping measurements, present when `:check_clipping` is set."
  @type clipping_info :: %{page_overflow?: boolean(), clipped: [clipped_element()]} | nil

  @typedoc "Per-viewport axe results, returned when `:viewports` is used."
  @type viewport_result :: %{
          viewport: {pos_integer(), pos_integer()},
          violations: [violation()],
          incomplete: [violation()],
          passes_count: non_neg_integer(),
          inapplicable_count: non_neg_integer(),
          clipping: clipping_info()
        }

  @typedoc "A multi-viewport scan report."
  @type multi_report :: %{
          url: String.t(),
          final_url: String.t(),
          results: [viewport_result()],
          timestamp: DateTime.t(),
          duration_ms: non_neg_integer(),
          engine: engine_info(),
          warnings: [String.t()],
          fallback: fallback_info()
        }

  @typedoc "Options accepted by `scan/2` and `scan_viewports/3`."
  @type scan_opts :: [
          timeout: pos_integer(),
          wait_for: String.t(),
          wait_until: :load | :domcontentloaded | :networkidle,
          viewport: {pos_integer(), pos_integer()},
          check_clipping: boolean(),
          clipping_ratio: float(),
          tags: [String.t()],
          user_agent: String.t() | nil,
          screenshot: Path.t() | nil,
          disable_rules: [String.t()],
          fallback: boolean()
        ]

  @default_opts [timeout: 30_000, tags: ["wcag2a", "wcag2aa"], fallback: true]

  @doc """
  Scan a URL and return a structured accessibility report.

  ## Options

    * `:timeout` — Navigation/analysis timeout in ms (default: `30_000`)
    * `:wait_for` — CSS selector to wait for before running axe
    * `:wait_until` — Playwright wait state: `:load` | `:domcontentloaded` |
      `:networkidle` (default: `:load` for remote, `:domcontentloaded` for file)
    * `:viewport` — `{width, height}` tuple (default: `{1280, 720}`)
    * `:check_clipping` — measure interactive elements (`a`, `button`,
      `input`, `select`, `textarea`, `[phx-click]`, `[role="button"]`)
      whose visible width falls below `:clipping_ratio`, plus page-level
      horizontal overflow. axe has no rule for content that is technically
      in the DOM but slid outside the visible area, yet that is the actual
      user-facing WCAG 1.4.10 failure. Results land in `:clipping` (per
      viewport under `scan_viewports/3`). Default `false`.
    * `:clipping_ratio` — minimum visible-width ratio before an element
      counts as clipped (default: `0.9`)
    * `:tags` — axe-core tag filter (default: `["wcag2a", "wcag2aa"]`)
    * `:user_agent` — Override the default Chrome UA string
    * `:screenshot` — Path to save a full-page PNG
    * `:disable_rules` — List of axe rule IDs to skip
    * `:fallback` — Fall back to curl + file:// on Playwright failure
      (default: `true`, remote URLs only)

  ## Returns

  `{:ok, report}` on success or `{:error, reason}` where reason is one of
  the `t:scan_error/0` tuples.
  """
  @impl Excessibility.ScannerBehaviour
  @spec scan(String.t(), scan_opts()) :: {:ok, report()} | {:error, scan_error()}
  def scan(url, opts \\ []) when is_binary(url) do
    if Keyword.has_key?(opts, :viewports), do: raise(ArgumentError, "scan/2 scans one viewport: use scan_viewports/3")
    scanned(url, opts)
  end

  @doc """
  Scan a URL at each of `viewports` (`{width, height}` tuples) in one browser session and return
  the per-viewport results as a `t:multi_report/0`. WCAG 1.4.10 Reflow only shows up at narrow
  widths, so `[{1440, 900}, {320, 800}]` is the recommended pair for snapshot scanning. A
  `:screenshot` is suffixed per viewport (`name.1440x900.png`). `opts` are those of `scan/2`.
  """
  @impl Excessibility.ScannerBehaviour
  @spec scan_viewports(String.t(), [{pos_integer(), pos_integer()}], scan_opts()) ::
          {:ok, multi_report()} | {:error, scan_error()}
  def scan_viewports(url, [_ | _] = viewports, opts \\ []) when is_binary(url) do
    scanned(url, Keyword.put(opts, :viewports, viewports))
  end

  # ── URL validation ─────────────────────────────────────────────────

  defp validate_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme}} when scheme in ["http", "https", "file"] ->
        {:ok, url}

      {:ok, %URI{scheme: nil}} ->
        {:error, {:invalid_url, :missing_scheme}}

      {:ok, %URI{scheme: _other}} ->
        {:error, {:invalid_url, :unsupported_scheme}}

      {:error, _reason} ->
        {:error, {:invalid_url, :parse_failed}}
    end
  end

  # ── Core scan + fallback ───────────────────────────────────────────

  defp do_scan(url, opts) do
    runner_path = axe_runner_path()

    if File.exists?(runner_path) do
      Runner.run_with_fallback(runner_path, url, opts)
    else
      {:error, {:playwright_error, "axe-runner.js not found at #{runner_path}. Run `mix excessibility.install` first."}}
    end
  end

  # ── Playwright invocation ──────────────────────────────────────────

  def parse_output(output, url) do
    case Jason.decode(output) do
      {:ok, %{"error" => _} = err} ->
        {:error, classify_error(err)}

      {:ok, result} when is_map(result) ->
        {:ok, normalize_result(result, url)}

      _ ->
        {:error, {:playwright_error, "failed to parse axe-core output"}}
    end
  end

  def parse_error_output(output) do
    case Jason.decode(output) do
      {:ok, %{"error" => _} = err} -> {:ok, classify_error(err)}
      _ -> :unparseable
    end
  end

  defp classify_error(%{"error" => "timeout"}), do: :timeout
  defp classify_error(%{"error" => "http_error", "status" => status}), do: {:http_error, status}
  defp classify_error(%{"error" => "navigation_failed"} = e), do: {:navigation_failed, message_of(e)}
  defp classify_error(%{"error" => "playwright_error"} = e), do: {:playwright_error, message_of(e)}
  defp classify_error(%{"error" => "invalid_args"} = e), do: {:playwright_error, message_of(e)}
  defp classify_error(%{"error" => other} = e), do: {:playwright_error, "#{other}: #{message_of(e)}"}

  defp message_of(%{"message" => msg}) when is_binary(msg), do: msg
  defp message_of(_), do: ""

  # ── Argument building ──────────────────────────────────────────────

  # ── Result normalization ───────────────────────────────────────────

  defp normalize_result(%{"results" => results} = result, url) when is_list(results) do
    %{
      url: url,
      final_url: Map.get(result, "final_url") || url,
      results: Enum.map(results, &normalize_viewport_result/1),
      timestamp: parse_timestamp(Map.get(result, "timestamp")),
      duration_ms: Map.get(result, "duration_ms", 0),
      engine: normalize_engine(Map.get(result, "engine", %{})),
      warnings: normalize_warnings(Map.get(result, "warnings", [])),
      fallback: nil
    }
  end

  defp normalize_result(result, url) do
    %{
      url: url,
      final_url: Map.get(result, "final_url") || url,
      violations: normalize_violations(Map.get(result, "violations", [])),
      incomplete: normalize_violations(Map.get(result, "incomplete", [])),
      passes_count: Map.get(result, "passes_count", 0),
      inapplicable_count: Map.get(result, "inapplicable_count", 0),
      timestamp: parse_timestamp(Map.get(result, "timestamp")),
      duration_ms: Map.get(result, "duration_ms", 0),
      engine: normalize_engine(Map.get(result, "engine", %{})),
      warnings: normalize_warnings(Map.get(result, "warnings", [])),
      clipping: normalize_clipping(Map.get(result, "clipping")),
      fallback: nil
    }
  end

  defp normalize_warnings(warnings) when is_list(warnings), do: Enum.filter(warnings, &is_binary/1)
  defp normalize_warnings(_), do: []

  defp normalize_clipping(%{} = clipping) do
    %{
      page_overflow?: Map.get(clipping, "page_overflow", false) == true,
      clipped: clipping |> Map.get("clipped", []) |> Enum.map(&normalize_clipped_element/1)
    }
  end

  defp normalize_clipping(_), do: nil

  defp normalize_clipped_element(element) do
    %{
      selector: Map.get(element, "selector", ""),
      width: Map.get(element, "width", 0),
      visible: Map.get(element, "visible", 0),
      ratio: Map.get(element, "ratio", 0.0) / 1,
      html: Map.get(element, "html", "")
    }
  end

  defp normalize_viewport_result(result) do
    %{
      viewport: parse_viewport(Map.get(result, "viewport")),
      violations: normalize_violations(Map.get(result, "violations", [])),
      incomplete: normalize_violations(Map.get(result, "incomplete", [])),
      passes_count: Map.get(result, "passes_count", 0),
      inapplicable_count: Map.get(result, "inapplicable_count", 0),
      clipping: normalize_clipping(Map.get(result, "clipping"))
    }
  end

  defp parse_viewport(spec) when is_binary(spec) do
    with [w, h] <- String.split(spec, "x"),
         {width, ""} <- Integer.parse(w),
         {height, ""} <- Integer.parse(h) do
      {width, height}
    else
      _ -> nil
    end
  end

  defp parse_viewport(_), do: nil

  defp normalize_engine(engine) when is_map(engine) do
    %{
      axe_version: Map.get(engine, "axe_version"),
      chromium_version: Map.get(engine, "chromium_version")
    }
  end

  defp normalize_engine(_), do: %{axe_version: nil, chromium_version: nil}

  defp normalize_violations(violations) when is_list(violations) do
    Enum.map(violations, fn v ->
      %{
        id: Map.get(v, "id", ""),
        impact: normalize_impact(Map.get(v, "impact")),
        description: Map.get(v, "description", ""),
        help: Map.get(v, "help", ""),
        help_url: Map.get(v, "helpUrl", ""),
        tags: Map.get(v, "tags", []),
        nodes: normalize_nodes(Map.get(v, "nodes", []))
      }
    end)
  end

  defp normalize_violations(_), do: []

  defp normalize_nodes(nodes) when is_list(nodes) do
    Enum.map(nodes, fn n ->
      %{
        target: Map.get(n, "target", []),
        html: Map.get(n, "html", ""),
        failure_summary: Map.get(n, "failureSummary", "")
      }
    end)
  end

  defp normalize_nodes(_), do: []

  defp normalize_impact("critical"), do: :critical
  defp normalize_impact("serious"), do: :serious
  defp normalize_impact("moderate"), do: :moderate
  defp normalize_impact("minor"), do: :minor
  defp normalize_impact(_), do: nil

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  # ── curl fallback ──────────────────────────────────────────────────

  # ── Runner discovery ───────────────────────────────────────────────

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

  defp scanned(url, opts) do
    with {:ok, validated_url} <- validate_url(url) do
      do_scan(validated_url, Keyword.merge(@default_opts, opts))
    end
  end
end
