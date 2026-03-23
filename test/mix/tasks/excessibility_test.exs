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
      Application.delete_env(:excessibility, :axe_runner_path)
      Application.delete_env(:excessibility, :axe_disable_rules)
    end)

    :ok
  end

  describe "no snapshots" do
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
    setup :setup_passing_mock

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

  describe "axe-core violations" do
    setup :setup_failing_mock

    test "reports violations with impact level and help URL" do
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          catch_exit(Excessibility.run([]))
        end)

      assert output =~ "### Issues Found"
      assert output =~ "**test.html**"
      assert output =~ "[CRITICAL]"
      assert output =~ "image-alt"
      assert output =~ "Images must have alternative text"
      assert output =~ "https://dequeuniversity.com/rules/axe/4.11/image-alt"
      assert output =~ "2 element(s) affected"
    end

    test "exits with shutdown 1 when violations found" do
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      capture_io(fn ->
        assert catch_exit(Excessibility.run([])) == {:shutdown, 1}
      end)
    end

    test "shows count of files with issues vs passed" do
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          catch_exit(Excessibility.run([]))
        end)

      assert output =~ "1 file(s) with issues, 0 passed"
    end
  end

  describe "axe-core runner error" do
    setup :setup_error_mock

    test "reports error when axe-runner fails" do
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          catch_exit(Excessibility.run([]))
        end)

      assert output =~ "### Issues Found"
      assert output =~ "Error:"
    end
  end

  describe "disable rules config" do
    setup :setup_passing_mock

    test "runs successfully with axe_disable_rules configured" do
      Application.put_env(:excessibility, :axe_disable_rules, ["color-contrast", "image-alt"])
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          Excessibility.run([])
        end)

      assert output =~ "passed accessibility checks"
    end

    test "runs successfully without axe_disable_rules configured" do
      File.write!(Path.join(@snapshot_dir, "test.html"), "<html></html>")

      output =
        capture_io(fn ->
          Excessibility.run([])
        end)

      assert output =~ "passed accessibility checks"
    end
  end

  # --- Mock Helpers ---

  defp setup_passing_mock(_context) do
    mock_path =
      create_mock_script("""
      #!/usr/bin/env node
      const result = JSON.stringify({violations: [], passes: [{id: "test"}], incomplete: []});
      process.stdout.write(result);
      process.exit(0);
      """)

    Application.put_env(:excessibility, :axe_runner_path, mock_path)

    on_exit(fn -> File.rm_rf!(Path.dirname(mock_path)) end)
    :ok
  end

  defp setup_failing_mock(_context) do
    mock_path =
      create_mock_script("""
      #!/usr/bin/env node
      const result = JSON.stringify({
        violations: [
          {
            id: "image-alt",
            impact: "critical",
            description: "Images must have alternative text",
            helpUrl: "https://dequeuniversity.com/rules/axe/4.11/image-alt",
            nodes: [{html: "<img src='a.png'>"}, {html: "<img src='b.png'>"}]
          }
        ],
        passes: [],
        incomplete: []
      });
      process.stdout.write(result);
      process.exit(0);
      """)

    Application.put_env(:excessibility, :axe_runner_path, mock_path)

    on_exit(fn -> File.rm_rf!(Path.dirname(mock_path)) end)
    :ok
  end

  defp setup_error_mock(_context) do
    mock_path =
      create_mock_script("""
      #!/usr/bin/env node
      process.stderr.write("Something went wrong");
      process.exit(1);
      """)

    Application.put_env(:excessibility, :axe_runner_path, mock_path)

    on_exit(fn -> File.rm_rf!(Path.dirname(mock_path)) end)
    :ok
  end

  defp create_mock_script(content) do
    dir = Path.join(System.tmp_dir!(), "mock_axe_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "axe-runner.js")
    File.write!(path, content)
    File.chmod!(path, 0o755)
    path
  end
end
