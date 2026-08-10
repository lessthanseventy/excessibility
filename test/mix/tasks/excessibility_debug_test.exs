defmodule Mix.Tasks.Excessibility.DebugTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Excessibility.Debug, as: DebugTask

  # `run/1` shells out to `mix test`, so we unit-test the `--format digest`
  # output path directly by writing a digest.json fixture to the configured
  # output path and asserting `output_digest/1` reads and prints it verbatim
  # (it must never rebuild the digest).
  @output_dir Path.join(["test", "excessibility"])
  @digest_path Path.join(@output_dir, "digest.json")

  setup do
    File.mkdir_p!(@output_dir)
    File.rm(@digest_path)

    on_exit(fn -> File.rm(@digest_path) end)

    :ok
  end

  test "prints the existing digest.json when present" do
    digest = ~s({\n  "schema": "excessibility.digest/v1",\n  "capture": {\n    "status": "ok"\n  }\n})
    File.write!(@digest_path, digest)

    output = capture_io(fn -> DebugTask.output_digest(%{}) end)

    assert output =~ "excessibility.digest/v1"
    assert output =~ ~s("status": "ok")
  end

  test "explains when no digest.json was produced" do
    output = capture_io(fn -> DebugTask.output_digest(%{}) end)

    assert output =~ "No digest.json was produced"
    assert output =~ "LiveView telemetry"
  end

  describe "plan_env/1 opt -> EXCESSIBILITY_QUERY_PLAN translation" do
    test "absent flags set no env" do
      assert DebugTask.plan_env([]) == []
    end

    test "--plan (boolean) means explain" do
      assert DebugTask.plan_env(plan: true) == [{"EXCESSIBILITY_QUERY_PLAN", "explain"}]
    end

    test "--plan-analyze (boolean) means explain_analyze" do
      assert DebugTask.plan_env(plan_analyze: true) ==
               [{"EXCESSIBILITY_QUERY_PLAN", "explain_analyze"}]
    end

    test "--plan-analyze wins when both are set" do
      assert DebugTask.plan_env(plan: true, plan_analyze: true) ==
               [{"EXCESSIBILITY_QUERY_PLAN", "explain_analyze"}]
    end
  end
end
