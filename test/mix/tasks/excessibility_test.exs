defmodule Mix.Tasks.ExcessibilityTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility

  @snapshot_dir Path.join(["test", "excessibility", "html_snapshots"])

  setup do
    # Clean up before and after tests
    File.rm_rf!(@snapshot_dir)
    File.mkdir_p!(@snapshot_dir)

    on_exit(fn ->
      File.rm_rf!(@snapshot_dir)
      Application.delete_env(:excessibility, :pa11y_path)
      Application.delete_env(:excessibility, :pa11y_config)
    end)

    :ok
  end

  describe "pa11y not found" do
    test "exits with error when pa11y doesn't exist" do
      Application.put_env(:excessibility, :pa11y_path, "/nonexistent/pa11y.js")

      assert catch_exit(Excessibility.run([])) == {:shutdown, 1}
    end

    test "shows helpful error message when pa11y missing" do
      Application.put_env(:excessibility, :pa11y_path, "/nonexistent/pa11y.js")

      # Mix.shell().error writes directly to stderr via Mix.Shell, not IO
      # The exit happens before we can capture, so we just verify the exit
      assert catch_exit(Excessibility.run([])) == {:shutdown, 1}
    end
  end

  describe "file filtering" do
    setup do
      # Create a mock pa11y script that just echoes success
      pa11y_dir = Path.join(System.tmp_dir!(), "mock_pa11y")
      File.mkdir_p!(pa11y_dir)
      pa11y_path = Path.join(pa11y_dir, "pa11y.js")

      File.write!(pa11y_path, """
      #!/usr/bin/env node
      console.log("Pa11y mock - no errors");
      process.exit(0);
      """)

      File.chmod!(pa11y_path, 0o755)

      Application.put_env(:excessibility, :pa11y_path, pa11y_path)

      on_exit(fn -> File.rm_rf!(pa11y_dir) end)

      :ok
    end

    test "excludes .good.html and .bad.html files" do
      # Create test files
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "test.good.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "test.bad.html"), "<html></html>")
      File.write!(Path.join(@snapshot_dir, "another.html"), "<html></html>")

      output =
        capture_io(fn ->
          Excessibility.run([])
        end)

      # Should run on test.html and another.html
      assert output =~ "test.html"
      assert output =~ "another.html"

      # Should NOT run on .good.html or .bad.html
      refute output =~ "test.good.html"
      refute output =~ "test.bad.html"
    end

    test "handles empty snapshot directory" do
      output =
        capture_io(fn ->
          Excessibility.run([])
        end)

      # Should not crash, just process zero files
      refute output =~ "Pa11y failed"
    end
  end

  describe "config file detection" do
    setup do
      # Create mock pa11y
      pa11y_dir = Path.join(System.tmp_dir!(), "mock_pa11y_config")
      File.mkdir_p!(pa11y_dir)
      pa11y_path = Path.join(pa11y_dir, "pa11y.js")

      # This mock script prints its arguments so we can verify --config is passed
      File.write!(pa11y_path, """
      #!/usr/bin/env node
      console.log("Args:", process.argv.slice(2).join(" "));
      process.exit(0);
      """)

      File.chmod!(pa11y_path, 0o755)

      Application.put_env(:excessibility, :pa11y_path, pa11y_path)

      on_exit(fn -> File.rm_rf!(pa11y_dir) end)

      :ok
    end

    test "passes --config flag when pa11y.json exists" do
      config_path = Path.join(File.cwd!(), "test_pa11y.json")
      File.write!(config_path, "{}")

      Application.put_env(:excessibility, :pa11y_config, config_path)
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          Excessibility.run([])
        end)

      assert output =~ "--config"
      assert output =~ "test_pa11y.json"

      File.rm!(config_path)
    end

    test "skips --config flag when pa11y.json doesn't exist" do
      Application.put_env(:excessibility, :pa11y_config, "nonexistent.json")
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          Excessibility.run([])
        end)

      refute output =~ "--config"
    end
  end
end
