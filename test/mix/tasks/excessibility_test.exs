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
    test "exits with error when pa11y doesn't exist and snapshots exist" do
      Application.put_env(:excessibility, :pa11y_path, "/nonexistent/pa11y.js")
      # Need at least one snapshot to trigger pa11y check
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      assert catch_exit(Excessibility.run([])) == {:shutdown, 1}
    end

    test "shows helpful message when no snapshots exist" do
      output =
        capture_io(fn ->
          catch_exit(Excessibility.run([]))
        end)

      assert output =~ "No snapshots found"
      assert output =~ "mix test"
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

      # Should report checking 2 snapshots (test.html and another.html)
      assert output =~ "Checking 2 snapshot(s)"
      assert output =~ "passed accessibility checks"
    end

    test "handles empty snapshot directory" do
      output =
        capture_io(fn ->
          catch_exit(Excessibility.run([]))
        end)

      # Should show helpful message about no snapshots
      assert output =~ "No snapshots found"
    end
  end

  describe "config file detection" do
    setup do
      # Create mock pa11y
      pa11y_dir = Path.join(System.tmp_dir!(), "mock_pa11y_config")
      File.mkdir_p!(pa11y_dir)
      pa11y_path = Path.join(pa11y_dir, "pa11y.js")

      # This mock script prints its arguments and exits with 1 so output is shown
      File.write!(pa11y_path, """
      #!/usr/bin/env node
      console.log("Args:", process.argv.slice(2).join(" "));
      process.exit(1);
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
          catch_exit(Excessibility.run([]))
        end)

      # The mock pa11y prints Args: which includes --config
      assert output =~ "--config"
      assert output =~ "test_pa11y.json"

      File.rm!(config_path)
    end

    test "skips --config flag when pa11y.json doesn't exist" do
      Application.put_env(:excessibility, :pa11y_config, "nonexistent.json")
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          catch_exit(Excessibility.run([]))
        end)

      refute output =~ "--config"
    end
  end
end
