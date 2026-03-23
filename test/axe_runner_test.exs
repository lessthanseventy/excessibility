defmodule Excessibility.AxeRunnerTest do
  use ExUnit.Case, async: true

  alias Excessibility.AxeRunner

  @tmp_dir System.tmp_dir!()

  describe "run/2" do
    @tag timeout: 60_000
    test "returns violations for inaccessible HTML" do
      path = write_tmp_html("""
      <html lang="en"><head><title>Test</title></head>
      <body><img src="x.png"></body></html>
      """)

      on_exit(fn -> File.rm(path) end)

      {:ok, result} = AxeRunner.run("file://#{path}")

      assert is_list(result.violations)
      assert Enum.any?(result.violations, &(&1["id"] == "image-alt"))
    end

    @tag timeout: 60_000
    test "returns no critical violations for accessible HTML" do
      path = write_tmp_html("""
      <html lang="en"><head><title>Test</title></head>
      <body><h1>Hello</h1></body></html>
      """)

      on_exit(fn -> File.rm(path) end)

      {:ok, result} = AxeRunner.run("file://#{path}")

      refute Enum.any?(result.violations, &(&1["impact"] == "critical"))
    end

    @tag timeout: 60_000
    test "captures screenshot when requested" do
      html_path = write_tmp_html("""
      <html lang="en"><head><title>Test</title></head>
      <body><p>Hi</p></body></html>
      """)

      png_path = Path.join(@tmp_dir, "axe_ss_#{System.unique_integer([:positive])}.png")

      on_exit(fn ->
        File.rm(html_path)
        File.rm(png_path)
      end)

      {:ok, _result} = AxeRunner.run("file://#{html_path}", screenshot: png_path)

      assert File.exists?(png_path)
    end

    @tag timeout: 60_000
    test "respects disable_rules option" do
      path = write_tmp_html("""
      <html lang="en"><head><title>Test</title></head>
      <body><img src="x.png"></body></html>
      """)

      on_exit(fn -> File.rm(path) end)

      {:ok, result} = AxeRunner.run("file://#{path}", disable_rules: ["image-alt"])

      refute Enum.any?(result.violations, &(&1["id"] == "image-alt"))
    end

    @tag timeout: 60_000
    test "returns error for nonexistent file" do
      assert {:error, _reason} = AxeRunner.run("file:///nonexistent/path.html")
    end
  end

  defp write_tmp_html(html) do
    path = Path.join(@tmp_dir, "axe_test_#{System.unique_integer([:positive])}.html")
    File.write!(path, html)
    path
  end
end
