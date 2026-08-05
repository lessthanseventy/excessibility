defmodule Excessibility.ScannerTest do
  use ExUnit.Case, async: true

  alias Excessibility.Scanner

  @tmp_dir System.tmp_dir!()

  describe "scan/2 — happy paths" do
    @tag timeout: 60_000
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

    @tag timeout: 60_000
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

    @tag timeout: 60_000
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

    @tag timeout: 60_000
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

    @tag timeout: 60_000
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

    @tag timeout: 60_000
    test "warns when a linked stylesheet is missing" do
      path =
        write_tmp_html("""
        <html lang="en"><head><title>Test</title>
        <link rel="stylesheet" href="file:///nonexistent/assets/app.css">
        </head>
        <body><h1>Hello</h1></body></html>
        """)

      on_exit(fn -> File.rm(path) end)

      {:ok, report} = Scanner.scan("file://#{path}")

      assert [warning | _] = report.warnings
      assert warning =~ "stylesheet"
      assert warning =~ "/nonexistent/assets/app.css"
    end

    @tag timeout: 60_000
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

  describe "scan/2 — playwright resolution" do
    @tag timeout: 60_000
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

    @tag timeout: 60_000
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

    @tag timeout: 60_000
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
