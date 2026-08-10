defmodule Excessibility.ScannerTest do
  # NOT async: several tests override global `Application` env keys
  # (`:playwright_path`, `:node_modules_path`) that `Excessibility.Scanner`
  # reads at scan time. Two tests set contradictory values — one a valid path
  # expecting `{:ok, ...}`, another `/nonexistent/...` expecting a
  # `{:playwright_error, ...}` — so running them concurrently let one test's env
  # (or its `on_exit` cleanup) leak into another's scan, an intermittent
  # left/right mismatch. Serial execution keeps each override isolated to its
  # own test. The scans are external Playwright subprocesses, so losing
  # ExUnit-level parallelism costs almost nothing here.
  use ExUnit.Case, async: false

  alias Excessibility.Scanner

  @moduletag timeout: 60_000

  @tmp_dir System.tmp_dir!()

  describe "scan/2 — happy paths" do
    test "returns a report with violations for inaccessible HTML" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><img src="x.png"></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}")

      assert is_list(report.violations)
      assert Enum.any?(report.violations, &(&1.id == "image-alt"))

      violation = Enum.find(report.violations, &(&1.id == "image-alt"))
      assert violation.impact in [:critical, :serious, :moderate, :minor]
      assert is_binary(violation.description)
      assert is_binary(violation.help_url)
      assert is_list(violation.nodes)
    end

    test "returns an empty violation list for accessible HTML" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}")

      refute Enum.any?(report.violations, &(&1.impact == :critical))
    end

    test "report shape includes all documented fields" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}")

      assert is_binary(report.url)
      assert is_binary(report.final_url)
      assert is_list(report.violations)
      assert is_list(report.incomplete)
      assert is_integer(report.passes_count) and report.passes_count >= 0
      assert is_integer(report.inapplicable_count) and report.inapplicable_count >= 0
      assert %DateTime{} = report.timestamp
      assert is_integer(report.duration_ms) and report.duration_ms >= 0
      assert is_map(report.engine)
      assert Map.has_key?(report.engine, :axe_version)
      assert Map.has_key?(report.engine, :chromium_version)
      assert is_nil(report.fallback)
      assert report.warnings == []
    end

    test "captures screenshot when :screenshot option set" do
      html_path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><p>Hi</p></body></html>
        """)

      png_path = Path.join(@tmp_dir, "scanner_ss_#{System.unique_integer([:positive])}.png")

      on_exit(fn ->
        File.rm(html_path)
        File.rm(png_path)
      end)

      {:ok, _report} = Scanner.scan("file://#{html_path}", screenshot: png_path)

      assert File.exists?(png_path)
    end

    test "applies linked CSS before analyzing so hidden content is excluded" do
      css_path = Path.join(@tmp_dir, "scanner_css_#{System.unique_integer([:positive])}.css")
      File.write!(css_path, ".modal { display: none; }")

      # The unlabeled input is a critical `label` violation — unless the
      # stylesheet is applied first, which hides the containing modal.
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title>
        <link rel="stylesheet" href="file://#{css_path}">
        </head>
        <body><h1>Hello</h1>
        <div class="modal"><input type="text" id="hidden-input"></div>
        </body></html>
        """)

      on_exit(fn ->
        File.rm(path)
        File.rm(css_path)
      end)

      {:ok, report} = Scanner.scan("file://#{path}")

      refute Enum.any?(report.violations, &(&1.id == "label"))
      assert report.warnings == []
    end

    test "warns 'failed to load' when a linked stylesheet is missing" do
      # Under file:// Chromium attaches a non-null empty CSSStyleSheet to a
      # <link> whose file doesn't exist, so this must classify via the
      # failed network request, not link.sheet (issue #137).
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title>
        <link rel="stylesheet" href="file:///nonexistent/assets/app.css">
        </head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}")

      assert Enum.any?(
               report.warnings,
               &(&1 =~ "stylesheet failed to load" and &1 =~ "/nonexistent/assets/app.css")
             )

      refute Enum.any?(report.warnings, &(&1 =~ "stylesheet import failed"))
    end

    test "does not warn 'failed to load' when the sheet loaded but a nested @import failed" do
      # Chromium fires an error event on the <link> when a nested @import
      # fails even though the sheet itself loaded and applied. That must
      # not read as "the stylesheet doesn't exist" — only as degraded
      # styling from the missing import.
      css_path = Path.join(@tmp_dir, "excessibility_import_#{System.unique_integer([:positive])}.css")

      File.write!(css_path, """
      @import url("file:///nonexistent/excessibility/missing-import.css");
      body { color: rgb(20, 20, 20); }
      """)

      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title>
        <link rel="stylesheet" href="file://#{css_path}">
        </head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn ->
        File.rm(path)
        File.rm(css_path)
      end)

      {:ok, report} = Scanner.scan("file://#{path}")

      refute Enum.any?(report.warnings, &(&1 =~ "stylesheet failed to load"))
      assert Enum.any?(report.warnings, &(&1 =~ "stylesheet import failed" and &1 =~ "missing-import.css"))
    end

    test "respects :disable_rules option" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><img src="x.png"></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}", disable_rules: ["image-alt"])

      refute Enum.any?(report.violations, &(&1.id == "image-alt"))
    end
  end

  describe "scan/2 — multiple viewports" do
    test "returns per-viewport results and actually applies each width" do
      # The media query hides the unlabeled input below 400px, so axe must
      # report the label violation at 1440px but not at 320px — proving the
      # scan genuinely ran at both widths.
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title>
        <style>@media (max-width: 400px) { .wide-only { display: none; } }</style>
        </head>
        <body><h1>Hello</h1>
        <div class="wide-only"><input type="text" id="wide-input"></div>
        </body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}", viewports: [{1440, 900}, {320, 800}])

      assert [wide, narrow] = report.results
      assert wide.viewport == {1440, 900}
      assert narrow.viewport == {320, 800}

      assert Enum.any?(wide.violations, &(&1.id == "label"))
      refute Enum.any?(narrow.violations, &(&1.id == "label"))

      assert is_integer(wide.passes_count)
      assert is_list(narrow.incomplete)
    end

    test "suffixes screenshots per viewport" do
      html_path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><p>Hi</p></body></html>
        """)

      png_base = Path.join(@tmp_dir, "scanner_vp_#{System.unique_integer([:positive])}.png")
      wide_png = String.replace(png_base, ".png", ".1440x900.png")
      narrow_png = String.replace(png_base, ".png", ".320x800.png")

      on_exit(fn ->
        File.rm(html_path)
        File.rm(wide_png)
        File.rm(narrow_png)
      end)

      {:ok, _report} =
        Scanner.scan("file://#{html_path}",
          viewports: [{1440, 900}, {320, 800}],
          screenshot: png_base
        )

      assert File.exists?(wide_png)
      assert File.exists?(narrow_png)
    end

    test "single :viewport keeps the flat report shape" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}", viewport: {800, 600})

      assert is_list(report.violations)
      refute Map.get(report, :results)
    end
  end

  describe "scan/2 — clipping detection" do
    # A 300px button whose left edge sits at 250px: fully visible at
    # 1440px, but only 70px (23%) visible at 320px — axe reports nothing
    # at either width, which is exactly why the check exists.
    @clipped_button ~s(<button style="position:absolute; left:250px; width:300px">Ship it</button>)

    test "flags interactive elements clipped at narrow widths, per viewport" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1>#{@clipped_button}</body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} =
        Scanner.scan("file://#{path}", viewports: [{1440, 900}, {320, 800}], check_clipping: true)

      assert [wide, narrow] = report.results

      assert wide.clipping.clipped == []
      refute wide.clipping.page_overflow?

      assert [clip] = narrow.clipping.clipped
      assert clip.selector =~ "button"
      assert clip.ratio < 0.9
      assert clip.visible < clip.width
      assert narrow.clipping.page_overflow?
    end

    test "clipping is nil when not requested" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1>#{@clipped_button}</body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}", viewports: [{320, 800}])

      assert [narrow] = report.results
      assert narrow.clipping == nil
    end

    test "works in single-viewport mode and respects :clipping_ratio" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1>#{@clipped_button}</body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}", viewport: {320, 800}, check_clipping: true)
      assert [%{selector: _}] = report.clipping.clipped

      # At a 0.1 threshold the 23%-visible button is no longer flagged,
      # but the page-level overflow is still reported.
      {:ok, lenient} =
        Scanner.scan("file://#{path}",
          viewport: {320, 800},
          check_clipping: true,
          clipping_ratio: 0.1
        )

      assert lenient.clipping.clipped == []
      assert lenient.clipping.page_overflow?
    end
  end

  describe "scan/2 — playwright resolution" do
    test "honors the :playwright_path config override" do
      bundled = Path.expand("assets/node_modules/playwright", File.cwd!())
      Application.put_env(:excessibility, :playwright_path, bundled)
      on_exit(fn -> Application.delete_env(:excessibility, :playwright_path) end)

      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      assert {:ok, _report} = Scanner.scan("file://#{path}")
    end

    test "honors the :node_modules_path config override for playwright and the axe wrapper" do
      bundled = Path.expand("assets/node_modules", File.cwd!())
      Application.put_env(:excessibility, :node_modules_path, bundled)
      on_exit(fn -> Application.delete_env(:excessibility, :node_modules_path) end)

      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      assert {:ok, report} = Scanner.scan("file://#{path}")
      assert report.engine.axe_version
    end

    test "reports an actionable error when :node_modules_path is invalid" do
      Application.put_env(:excessibility, :node_modules_path, "/nonexistent/node_modules")
      on_exit(fn -> Application.delete_env(:excessibility, :node_modules_path) end)

      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      assert {:error, {:playwright_error, message}} = Scanner.scan("file://#{path}", fallback: false)
      assert message =~ "/nonexistent/node_modules"
      assert message =~ "EXCESSIBILITY_NODE_MODULES_PATH"
    end

    test "reports an actionable error when :playwright_path is invalid" do
      Application.put_env(:excessibility, :playwright_path, "/nonexistent/playwright")
      on_exit(fn -> Application.delete_env(:excessibility, :playwright_path) end)

      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title></head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      assert {:error, {:playwright_error, message}} = Scanner.scan("file://#{path}", fallback: false)
      assert message =~ "/nonexistent/playwright"
      assert message =~ "EXCESSIBILITY_PLAYWRIGHT_PATH"
    end
  end

  describe "scan/2 — error tuples" do
    test "returns {:error, {:invalid_url, :parse_failed}} for unparseable input" do
      assert {:error, {:invalid_url, :parse_failed}} = Scanner.scan("not a url")
    end

    test "returns {:error, {:invalid_url, :missing_scheme}} for bare host" do
      assert {:error, {:invalid_url, :missing_scheme}} = Scanner.scan("example.com/foo")
    end

    test "returns {:error, {:invalid_url, :unsupported_scheme}} for weird scheme" do
      assert {:error, {:invalid_url, :unsupported_scheme}} = Scanner.scan("ftp://example.com/")
    end

    test "returns {:error, {:navigation_failed, _}} for nonexistent file" do
      assert {:error, {:navigation_failed, _msg}} = Scanner.scan("file:///nonexistent/path.html")
    end
  end

  defp write_tmp_html(html) do
    path = Path.join(@tmp_dir, "scanner_test_#{System.unique_integer([:positive])}.html")
    File.write!(path, html)
    path
  end
end
