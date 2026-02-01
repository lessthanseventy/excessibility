defmodule Excessibility.MCP.SubprocessTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Subprocess

  describe "run/3" do
    test "runs simple command and returns output" do
      {output, exit_code} = Subprocess.run("echo", ["hello"])
      assert output == "hello\n"
      assert exit_code == 0
    end

    test "returns non-zero exit code on failure" do
      {_output, exit_code} = Subprocess.run("sh", ["-c", "exit 42"])
      assert exit_code == 42
    end

    test "respects cd option" do
      {output, 0} = Subprocess.run("pwd", [], cd: "/tmp")
      assert String.trim(output) == "/tmp"
    end

    test "captures stderr when stderr_to_stdout is true" do
      {output, _} = Subprocess.run("sh", ["-c", "echo error >&2"], stderr_to_stdout: true)
      assert output =~ "error"
    end

    test "passes environment variables" do
      {output, 0} = Subprocess.run("sh", ["-c", "echo $MY_VAR"], env: [{"MY_VAR", "test_value"}])
      assert String.trim(output) == "test_value"
    end
  end

  describe "timeout handling" do
    test "completes fast commands within timeout" do
      {output, 0} = Subprocess.run("echo", ["fast"], timeout: 5000)
      assert output == "fast\n"
    end

    test "times out slow commands" do
      start = System.monotonic_time(:millisecond)
      {output, exit_code} = Subprocess.run("sleep", ["10"], timeout: 100)
      elapsed = System.monotonic_time(:millisecond) - start

      assert output =~ "timed out"
      assert exit_code == 124
      # Should timeout in roughly 100ms, not 10 seconds
      assert elapsed < 500
    end

    test "kills subprocess on timeout" do
      # Create a unique marker file
      marker = "/tmp/subprocess_test_#{:rand.uniform(1_000_000)}"

      # Run a command that creates a file after 2 seconds
      {_output, 124} =
        Subprocess.run(
          "sh",
          ["-c", "sleep 2 && touch #{marker}"],
          timeout: 100
        )

      # Wait a bit to ensure the subprocess would have created the file if still running
      Process.sleep(3000)

      # File should NOT exist because subprocess was killed
      refute File.exists?(marker)
    after
      # Cleanup
      File.rm("/tmp/subprocess_test_*")
    end

    test "no timeout when timeout is nil" do
      {output, 0} = Subprocess.run("echo", ["no timeout"], timeout: nil)
      assert output == "no timeout\n"
    end
  end

  describe "mix command integration" do
    test "can run mix commands with timeout" do
      # This tests that mix doesn't hang waiting for input
      {output, _exit_code} =
        Subprocess.run(
          "mix",
          ["--version"],
          timeout: 10_000,
          stderr_to_stdout: true
        )

      assert output =~ "Mix"
    end

    @tag :slow
    test "times out hanging mix commands" do
      # Simulate a mix command that hangs (compile deps that don't exist)
      {output, exit_code} =
        Subprocess.run(
          "sh",
          ["-c", "sleep 30"],
          timeout: 500,
          stderr_to_stdout: true
        )

      assert output =~ "timed out"
      assert exit_code == 124
    end
  end
end
