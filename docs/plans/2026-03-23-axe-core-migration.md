# Axe-Core Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace Pa11y + ChromicPDF with Playwright + axe-core, simplify MCP surface from 11 tools to 3, add snapshot management and URL checking mix tasks.

**Architecture:** A small Node.js script (`assets/axe-runner.js`) uses Playwright to load URLs and run axe-core, replacing both Pa11y (a11y checks) and ChromicPDF (screenshots). The Elixir side calls it via `System.cmd`/`Subprocess`. MCP tools become thin wrappers around mix tasks.

**Tech Stack:** Elixir, Playwright, @axe-core/playwright, Node.js

**Design Doc:** `docs/plans/2026-03-23-axe-core-migration-design.md`

---

## Phase 1: New Engine (axe-runner.js + Elixir wrapper)

### Task 1: Create axe-runner.js

**Files:**
- Create: `assets/axe-runner.js`
- Modify: `assets/package.json`

**Step 1: Update package.json**

Replace contents of `assets/package.json`:
```json
{
  "dependencies": {
    "@axe-core/playwright": "^4.0.0",
    "playwright": "^1.50.0"
  }
}
```

**Step 2: Write axe-runner.js**

Create `assets/axe-runner.js`:
```js
const { chromium } = require("playwright");
const { AxeBuilder } = require("@axe-core/playwright");

async function main() {
  const args = process.argv.slice(2);
  const url = args[0];
  if (!url) {
    console.error(JSON.stringify({ error: "Usage: node axe-runner.js <url> [--screenshot path] [--wait-for selector] [--disable-rules rule1,rule2]" }));
    process.exit(1);
  }

  let screenshotPath = null;
  let waitFor = null;
  let disableRules = [];

  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--screenshot" && args[i + 1]) screenshotPath = args[++i];
    else if (args[i] === "--wait-for" && args[i + 1]) waitFor = args[++i];
    else if (args[i] === "--disable-rules" && args[i + 1]) disableRules = args[++i].split(",");
  }

  const browser = await chromium.launch();
  const page = await browser.newPage();

  try {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    if (waitFor) await page.waitForSelector(waitFor, { timeout: 10000 });

    let builder = new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]);
    if (disableRules.length > 0) builder = builder.disableRules(disableRules);

    const results = await builder.analyze();

    if (screenshotPath) await page.screenshot({ path: screenshotPath, fullPage: true });

    console.log(JSON.stringify(results));
  } catch (err) {
    console.error(JSON.stringify({ error: err.message }));
    process.exit(1);
  } finally {
    await browser.close();
  }
}

main();
```

**Step 3: Install dependencies and test manually**

Run:
```bash
cd assets && npm install && npx playwright install chromium && cd ..
```

Then test:
```bash
echo '<html lang="en"><head><title>Test</title></head><body><img src="x.png"></body></html>' > /tmp/test-axe.html
node assets/axe-runner.js "file:///tmp/test-axe.html" | jq '.violations[].id'
```
Expected: `"image-alt"` (img without alt text)

**Step 4: Commit**

```bash
git add assets/package.json assets/axe-runner.js
git commit -m "feat: add axe-runner.js using Playwright + axe-core"
```

---

### Task 2: Create Elixir AxeRunner wrapper

**Files:**
- Create: `lib/excessibility/axe_runner.ex`
- Create: `test/axe_runner_test.exs`

**Step 1: Write the failing test**

Create `test/axe_runner_test.exs`:
```elixir
defmodule Excessibility.AxeRunnerTest do
  use ExUnit.Case, async: true

  alias Excessibility.AxeRunner

  @tmp_dir System.tmp_dir!()

  describe "run/2" do
    test "returns violations for inaccessible HTML" do
      html = ~s(<html lang="en"><head><title>Test</title></head><body><img src="x.png"></body></html>)
      path = Path.join(@tmp_dir, "axe_test_#{System.unique_integer([:positive])}.html")
      File.write!(path, html)

      {:ok, result} = AxeRunner.run("file://#{path}")

      assert is_list(result.violations)
      assert Enum.any?(result.violations, &(&1["id"] == "image-alt"))
    after
      File.rm(path)
    end

    test "returns passes for accessible HTML" do
      html = ~s(<html lang="en"><head><title>Test</title></head><body><h1>Hello</h1></body></html>)
      path = Path.join(@tmp_dir, "axe_test_#{System.unique_integer([:positive])}.html")
      File.write!(path, html)

      {:ok, result} = AxeRunner.run("file://#{path}")

      assert result.violations == [] or
             not Enum.any?(result.violations, &(&1["impact"] == "critical"))
    after
      File.rm(path)
    end

    test "supports http URLs" do
      # This tests against a live URL — skip if no network
      {:ok, result} = AxeRunner.run("https://example.com")
      assert is_list(result.violations)
    end

    test "captures screenshot when requested" do
      html = ~s(<html lang="en"><head><title>Test</title></head><body><p>Hi</p></body></html>)
      html_path = Path.join(@tmp_dir, "axe_ss_#{System.unique_integer([:positive])}.html")
      png_path = Path.join(@tmp_dir, "axe_ss_#{System.unique_integer([:positive])}.png")
      File.write!(html_path, html)

      {:ok, _result} = AxeRunner.run("file://#{html_path}", screenshot: png_path)

      assert File.exists?(png_path)
    after
      File.rm(html_path)
      File.rm(png_path)
    end

    test "returns error for invalid URL" do
      assert {:error, _reason} = AxeRunner.run("file:///nonexistent/path.html")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/axe_runner_test.exs`
Expected: FAIL — module `Excessibility.AxeRunner` not found

**Step 3: Write implementation**

Create `lib/excessibility/axe_runner.ex`:
```elixir
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
    args = build_args(url, opts)
    runner_path = axe_runner_path()

    unless File.exists?(runner_path) do
      {:error, "axe-runner.js not found at #{runner_path}. Run `mix excessibility.install` first."}
    end

    timeout = Keyword.get(opts, :timeout, 30_000)

    case System.cmd("node", [runner_path | args],
           stderr_to_stdout: false,
           env: [{"NODE_NO_WARNINGS", "1"}]
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, result} -> {:ok, normalize_result(result)}
          {:error, _} -> {:error, "Failed to parse axe-core output"}
        end

      {_output, _code} ->
        {:error, "axe-core check failed for #{url}"}
    end
  end

  defp build_args(url, opts) do
    args = [url]

    args =
      case Keyword.get(opts, :screenshot) do
        nil -> args
        path -> args ++ ["--screenshot", path]
      end

    args =
      case Keyword.get(opts, :wait_for) do
        nil -> args
        selector -> args ++ ["--wait-for", selector]
      end

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
      Path.join([dependency_root(), "assets/axe-runner.js"])
  end

  defp dependency_root do
    Mix.Project.deps_paths()[:excessibility] || File.cwd!()
  end
end
```

**Step 4: Run tests**

Run: `mix test test/axe_runner_test.exs`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/excessibility/axe_runner.ex test/axe_runner_test.exs
git commit -m "feat: add AxeRunner Elixir wrapper for axe-core"
```

---

## Phase 2: Swap mix tasks to use new engine

### Task 3: Rewrite `mix excessibility` to use AxeRunner

**Files:**
- Modify: `lib/mix/tasks/excessibility.ex`
- Modify: `test/mix/tasks/excessibility_test.exs`

**Step 1: Update the mix task**

Replace `run_pa11y/1`, `pa11y_path/0`, `pa11y_config_args/0` with axe-core equivalents. The task interface stays the same (`mix excessibility` and `mix excessibility test/file.exs`).

Key changes:
- `run_pa11y(files)` becomes `run_axe(files)` — calls `AxeRunner.run("file://#{path}")` per file
- Remove Pa11y path resolution and config
- Add axe-core config support (`:axe_disable_rules` from app env)
- Update output formatting to show axe-core impact levels and help URLs
- Update moduledoc to reference axe-core instead of Pa11y

**Step 2: Update tests**

Update `test/mix/tasks/excessibility_test.exs` — change any Pa11y mocks to AxeRunner expectations. Since AxeRunner calls `System.cmd`, mock at that level or use the existing SystemBehaviour mock.

**Step 3: Run tests**

Run: `mix test test/mix/tasks/excessibility_test.exs`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/mix/tasks/excessibility.ex test/mix/tasks/excessibility_test.exs
git commit -m "feat: swap mix excessibility from Pa11y to axe-core"
```

---

### Task 4: Add `mix excessibility.check` for arbitrary URLs

**Files:**
- Create: `lib/mix/tasks/excessibility_check.ex`
- Create: `test/mix/tasks/excessibility_check_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule Mix.Tasks.Excessibility.CheckTest do
  use ExUnit.Case

  describe "run/1" do
    test "checks a URL and reports violations" do
      # Write a local HTML file with known violations
      path = Path.join(System.tmp_dir!(), "check_test_#{System.unique_integer([:positive])}.html")
      File.write!(path, ~s(<html lang="en"><head><title>T</title></head><body><img src="x"></body></html>))

      assert ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Excessibility.Check.run(["file://#{path}"])
      end) =~ "image-alt"
    after
      File.rm(path)
    end

    test "exits with error when no URL provided" do
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Excessibility.Check.run([])
      end
    end
  end
end
```

**Step 2: Write the mix task**

Create `lib/mix/tasks/excessibility_check.ex`:
```elixir
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
```

**Step 3: Run tests**

Run: `mix test test/mix/tasks/excessibility_check_test.exs`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/mix/tasks/excessibility_check.ex test/mix/tasks/excessibility_check_test.exs
git commit -m "feat: add mix excessibility.check for arbitrary URL checking"
```

---

### Task 5: Add `mix excessibility.snapshots` for snapshot management

**Files:**
- Create: `lib/mix/tasks/excessibility_snapshots.ex`
- Create: `test/mix/tasks/excessibility_snapshots_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule Mix.Tasks.Excessibility.SnapshotsTest do
  use ExUnit.Case

  @snapshot_dir "test/excessibility/html_snapshots"

  setup do
    File.mkdir_p!(@snapshot_dir)
    on_exit(fn -> File.rm_rf!(@snapshot_dir) end)
  end

  describe "list (no args)" do
    test "lists snapshots with sizes" do
      File.write!(Path.join(@snapshot_dir, "test1.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "test2.html"), "<html><body>more</body></html>")

      output = ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Excessibility.Snapshots.run([])
      end)

      assert output =~ "test1.html"
      assert output =~ "test2.html"
      assert output =~ "2 snapshot(s)"
    end

    test "shows message when no snapshots" do
      output = ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Excessibility.Snapshots.run([])
      end)

      assert output =~ "No snapshots"
    end
  end

  describe "--clean" do
    test "deletes all snapshots" do
      File.write!(Path.join(@snapshot_dir, "test1.html"), "<html></html>")

      ExUnit.CaptureIO.capture_io([input: "y\n"], fn ->
        Mix.Tasks.Excessibility.Snapshots.run(["--clean"])
      end)

      assert Path.join(@snapshot_dir, "*.html") |> Path.wildcard() == []
    end
  end
end
```

**Step 2: Write the mix task**

Create `lib/mix/tasks/excessibility_snapshots.ex`:
```elixir
defmodule Mix.Tasks.Excessibility.Snapshots do
  @shortdoc "Manage accessibility snapshots"

  @moduledoc """
  List, clean, or open HTML snapshots.

  ## Usage

      # List all snapshots
      mix excessibility.snapshots

      # Delete all snapshots
      mix excessibility.snapshots --clean

      # Open a snapshot in the browser
      mix excessibility.snapshots --open snapshot_name.html
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [clean: :boolean, open: :string])

    cond do
      Keyword.get(opts, :clean, false) -> clean_snapshots()
      open = Keyword.get(opts, :open) -> open_snapshot(open)
      true -> list_snapshots()
    end
  end

  defp list_snapshots do
    files = snapshot_files()

    if files == [] do
      Mix.shell().info("No snapshots found in #{snapshot_dir()}")
    else
      Mix.shell().info("#{length(files)} snapshot(s) in #{snapshot_dir()}\n")

      Enum.each(files, fn file ->
        %{size: size} = File.stat!(file)
        name = Path.basename(file)
        Mix.shell().info("  #{name} (#{format_size(size)})")
      end)
    end
  end

  defp clean_snapshots do
    files = snapshot_files()

    if files == [] do
      Mix.shell().info("No snapshots to clean.")
    else
      if Mix.shell().yes?("Delete #{length(files)} snapshot(s)?") do
        Enum.each(files, &File.rm!/1)
        Mix.shell().info("Deleted #{length(files)} snapshot(s).")
      end
    end
  end

  defp open_snapshot(name) do
    path =
      if String.contains?(name, "/") do
        name
      else
        Path.join(snapshot_dir(), name)
      end

    if File.exists?(path) do
      open_cmd = case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "start"
      end

      System.cmd(open_cmd, [path])
    else
      Mix.shell().error("Snapshot not found: #{path}")
    end
  end

  defp snapshot_files do
    snapshot_dir()
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.sort()
  end

  defp snapshot_dir do
    output_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    Path.join(output_path, "html_snapshots")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end
```

**Step 3: Run tests**

Run: `mix test test/mix/tasks/excessibility_snapshots_test.exs`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/mix/tasks/excessibility_snapshots.ex test/mix/tasks/excessibility_snapshots_test.exs
git commit -m "feat: add mix excessibility.snapshots for snapshot management"
```

---

## Phase 3: Remove Pa11y + ChromicPDF

### Task 6: Remove ChromicPDF dependency and screenshot code

**Files:**
- Modify: `mix.exs` — remove `{:chromic_pdf, ">= 1.14.0"}` from deps
- Modify: `lib/snapshot.ex` — remove `screenshot/2`, `screenshot_path/1`, `ensure_chromic_pdf_started/0`, and the `screenshot?` option handling (~lines 168-205)
- Modify: `test/test_helper.exs` — remove ChromicPDF startup block (lines 15-31)
- Modify: `test/snapshot_test.exs` — remove `@tag :screenshot` tests
- Modify: `test/error_cases_test.exs` — remove ChromicPDF-related error tests

Screenshot functionality is replaced by AxeRunner's `--screenshot` option.

**Step 1: Make changes**

In `mix.exs`, delete the chromic_pdf line:
```elixir
# DELETE THIS LINE:
{:chromic_pdf, ">= 1.14.0"},
```

In `lib/snapshot.ex`, remove:
- Lines 168-175 (screenshot? conditional block)
- Lines 176-205 (screenshot_path, screenshot, ensure_chromic_pdf_started functions)
- Line 9 in moduledoc ("Screenshot generation via ChromicPDF")
- Line 51 (`:screenshot?` option doc)

In `test/test_helper.exs`, replace lines 15-31 (the CI/ChromicPDF block) with nothing — just delete that block entirely.

In `test/snapshot_test.exs`, delete any test tagged with `@tag :screenshot`.

In `test/error_cases_test.exs`, delete the "Snapshot screenshot failures" describe block.

**Step 2: Run tests**

Run: `mix deps.get && mix test`
Expected: All pass (screenshot tests removed, no ChromicPDF references remain)

**Step 3: Verify no remaining references**

Run: `grep -r "ChromicPDF\|chromic_pdf" lib/ test/ mix.exs`
Expected: No results

**Step 4: Commit**

```bash
git add mix.exs lib/snapshot.ex test/test_helper.exs test/snapshot_test.exs test/error_cases_test.exs
git commit -m "chore: remove ChromicPDF dependency, screenshots now via Playwright"
```

---

### Task 7: Remove Pa11y references

**Files:**
- Delete: `assets/package.json` is already updated (Task 1)
- Modify: `lib/mix/tasks/install.ex` — replace Pa11y npm install with Playwright/axe-core install, remove `pa11y.json` creation
- Modify: `test/mix/tasks/excessibility_install_test.exs` — update expectations
- Verify: no remaining `pa11y` references in `lib/` or `test/`

**Step 1: Update installer**

In `lib/mix/tasks/install.ex`:
- Replace `npm install` of Pa11y with `npm install` of `@axe-core/playwright` + `npx playwright install chromium`
- Replace `ensure_pa11y_config` (creates `pa11y.json`) with nothing or an axe config equivalent
- Update all user-facing messages to reference axe-core instead of Pa11y
- Update config references: `:pa11y_path` → `:axe_runner_path`, `:pa11y_config` → `:axe_disable_rules`

**Step 2: Update install tests**

**Step 3: Verify no remaining Pa11y references**

Run: `grep -ri "pa11y" lib/ test/ --include="*.ex" --include="*.exs"`
Expected: No results (except possibly in design docs)

**Step 4: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/mix/tasks/install.ex test/mix/tasks/excessibility_install_test.exs
git commit -m "chore: remove Pa11y, installer now sets up Playwright + axe-core"
```

---

## Phase 4: Simplify MCP Surface

### Task 8: Delete removed MCP tools, prompts, and resources

**Files to delete:**

MCP Tools (8 files):
- `lib/excessibility/mcp/tools/check_route.ex`
- `lib/excessibility/mcp/tools/e11y_check.ex`
- `lib/excessibility/mcp/tools/e11y_debug.ex`
- `lib/excessibility/mcp/tools/explain_issue.ex`
- `lib/excessibility/mcp/tools/list_violations.ex`
- `lib/excessibility/mcp/tools/suggest_fixes.ex`
- `lib/excessibility/mcp/tools/analyze_timeline.ex`
- `lib/excessibility/mcp/tools/list_analyzers.ex`

MCP Prompts (9 files):
- `lib/excessibility/mcp/prompts/accessible_form.ex`
- `lib/excessibility/mcp/prompts/accessible_modal.ex`
- `lib/excessibility/mcp/prompts/accessible_navigation.ex`
- `lib/excessibility/mcp/prompts/accessible_table.ex`
- `lib/excessibility/mcp/prompts/debug_liveview.ex`
- `lib/excessibility/mcp/prompts/fix_a11y_issue.ex`
- `lib/excessibility/mcp/prompts/fix_event_cascade.ex`
- `lib/excessibility/mcp/prompts/fix_memory_leak.ex`
- `lib/excessibility/mcp/prompts/optimize_liveview.ex`

MCP Resources (2 files):
- `lib/excessibility/mcp/resources/timeline.ex`
- `lib/excessibility/mcp/resources/analyzer.ex`

**Also delete corresponding test files** for any removed tools/prompts/resources.

**Step 1: Delete all files above**

```bash
git rm lib/excessibility/mcp/tools/{check_route,e11y_check,e11y_debug,explain_issue,list_violations,suggest_fixes,analyze_timeline,list_analyzers}.ex
git rm -r lib/excessibility/mcp/prompts/
git rm lib/excessibility/mcp/resources/{timeline,analyzer}.ex
# Also delete corresponding test files
```

**Step 2: Compile to verify no dangling references**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile. The registry auto-discovers modules, so deleting files should just shrink the list.

**Step 3: Delete corresponding test files**

Find and delete any test files for removed tools/prompts/resources.

**Step 4: Run tests**

Run: `mix test`
Expected: All pass (tests for deleted modules are gone)

**Step 5: Commit**

```bash
git commit -m "chore: remove 8 MCP tools, 9 prompts, 2 resources"
```

---

### Task 9: Create new MCP tools (a11y_check, debug)

**Files:**
- Create: `lib/excessibility/mcp/tools/a11y_check.ex`
- Create: `lib/excessibility/mcp/tools/debug.ex`
- Modify: `lib/excessibility/mcp/tools/get_snapshots.ex` (if needed — may already be fine)
- Create: `test/mcp/tools/a11y_check_test.exs`
- Create: `test/mcp/tools/debug_test.exs`

**Step 1: Write a11y_check tool**

Create `lib/excessibility/mcp/tools/a11y_check.ex`:
- Accepts `url` (check live URL directly via AxeRunner) or `test_args` (run tests then check snapshots via `mix excessibility`) or nothing (check existing snapshots)
- Returns structured JSON with violations, impact levels, help URLs

**Step 2: Write debug tool**

Create `lib/excessibility/mcp/tools/debug.ex`:
- Wraps `mix excessibility.debug` via Subprocess
- Accepts `test_args` and analyzer options
- Returns timeline + analysis results

**Step 3: Write tests for both**

**Step 4: Run tests**

Run: `mix test test/mcp/tools/`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/excessibility/mcp/tools/{a11y_check,debug}.ex test/mcp/tools/
git commit -m "feat: add simplified MCP tools (a11y_check, debug)"
```

---

## Phase 5: Update Docs and Plugin

### Task 10: Update documentation and plugin files

**Files:**
- Modify: `mix.exs` — update description (remove Pa11y reference)
- Modify: `priv/claude-plugin/.claude-plugin/plugin.json` — update description, keywords
- Modify: `priv/claude-plugin/.claude-plugin/hooks/SessionStart.md` — update to reference axe-core
- Modify: `priv/claude-plugin/skills/e11y-tdd/SKILL.md` — update Pa11y → axe-core references
- Modify: `priv/claude-plugin/skills/e11y-fix/SKILL.md` — rewrite for axe-core error format
- Modify: `README.md` — update all Pa11y/ChromicPDF references, add URL checking docs

**Step 1: Update mix.exs description**

```elixir
defp description do
  """
  Library for accessibility snapshot testing in Phoenix applications using axe-core and Playwright.
  """
end
```

**Step 2: Update plugin files**

Replace Pa11y references with axe-core throughout. Update tool names in SessionStart.md to match new 3-tool surface.

**Step 3: Update README**

- Replace Pa11y install instructions with Playwright/axe-core
- Add `mix excessibility.check` documentation
- Add `mix excessibility.snapshots` documentation
- Update MCP tool documentation
- Remove ChromicPDF screenshot docs, replace with Playwright screenshot

**Step 4: Commit**

```bash
git add mix.exs priv/ README.md
git commit -m "docs: update all references from Pa11y/ChromicPDF to axe-core/Playwright"
```

---

## Phase 6: Final Verification

### Task 11: Full integration test and cleanup

**Step 1: Run full test suite**

```bash
mix test
```
Expected: All pass

**Step 2: Run linting**

```bash
mix format
mix credo
```
Expected: No issues

**Step 3: Verify no stale references**

```bash
grep -ri "pa11y\|chromic_pdf\|ChromicPDF" lib/ test/ mix.exs assets/
```
Expected: No results

**Step 4: Verify MCP server starts**

```bash
echo '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"capabilities":{}}}' | mix run --no-halt -e "Excessibility.MCP.Server.start()"
```
Expected: Returns server info with 3 tools listed

**Step 5: Test axe-runner end-to-end**

```bash
mix excessibility.check https://example.com
```
Expected: Returns axe-core results for example.com

**Step 6: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: final cleanup for axe-core migration"
```
