defmodule Mix.Tasks.Excessibility.CheckTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility.Check

  setup do
    on_exit(fn ->
      Application.delete_env(:excessibility, :axe_runner_path)
    end)

    :ok
  end

  describe "no URL provided" do
    test "raises error when no URL provided" do
      assert_raise Mix.Error, ~r/Usage:/, fn ->
        Check.run([])
      end
    end
  end

  describe "accessible HTML" do
    setup :setup_passing_mock

    test "shows success message for accessible page" do
      output =
        capture_io(fn ->
          Check.run(["https://example.com"])
        end)

      assert output =~ "Checking https://example.com..."
      assert output =~ "No accessibility violations found for https://example.com"
    end
  end

  describe "violations detected" do
    setup :setup_failing_mock

    test "detects violations and shows them in output" do
      output =
        capture_io(fn ->
          catch_exit(Check.run(["https://example.com"]))
        end)

      assert output =~ "Found 1 violation(s) for https://example.com"
      assert output =~ "[CRITICAL]"
      assert output =~ "image-alt"
      assert output =~ "Images must have alternative text"
      assert output =~ "Help: https://dequeuniversity.com/rules/axe/4.11/image-alt"
      assert output =~ "2 element(s) affected"
    end

    test "exits with shutdown 1 when violations found" do
      capture_io(fn ->
        assert catch_exit(Check.run(["https://example.com"])) == {:shutdown, 1}
      end)
    end
  end

  describe "axe-runner error" do
    setup :setup_error_mock

    test "shows error and exits with shutdown 1" do
      output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            assert catch_exit(Check.run(["https://example.com"])) == {:shutdown, 1}
          end)
        end)

      assert output =~ "Error:"
    end
  end

  # --- Mock Helpers ---

  defp setup_passing_mock(_context) do
    mock_path = create_mock_script("""
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
    mock_path = create_mock_script("""
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
    mock_path = create_mock_script("""
    #!/usr/bin/env node
    process.stderr.write("Something went wrong");
    process.exit(1);
    """)

    Application.put_env(:excessibility, :axe_runner_path, mock_path)

    on_exit(fn -> File.rm_rf!(Path.dirname(mock_path)) end)
    :ok
  end

  defp create_mock_script(content) do
    dir = Path.join(System.tmp_dir!(), "mock_axe_check_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "axe-runner.js")
    File.write!(path, content)
    File.chmod!(path, 0o755)
    path
  end
end
