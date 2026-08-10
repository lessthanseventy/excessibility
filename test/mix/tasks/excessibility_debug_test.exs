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

  describe "collect_sample/1 (benchmark sample extraction)" do
    # A decoded timeline map (keys: :atoms, as read from timeline.json). Each
    # sample is one benchmark run's per-(view, callback) and per-fingerprint
    # duration_ms map.
    defp timeline_fixture do
      %{
        test: "PageLiveTest: saves",
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            view_module: "MyAppWeb.PageLive",
            event_duration_ms: 12.0,
            duration_since_previous_ms: nil,
            ecto_queries: []
          },
          %{
            sequence: 2,
            event: "handle_event:save",
            view_module: "MyAppWeb.PageLive",
            event_duration_ms: 30.0,
            duration_since_previous_ms: 40.0,
            ecto_queries: [
              %{fingerprint: "sha256:aaa", duration_ms: 3.0},
              %{fingerprint: "sha256:aaa", duration_ms: 2.0},
              %{fingerprint: "sha256:bbb", duration_ms: 5.0}
            ]
          }
        ]
      }
    end

    test "extracts per-(view, callback) durations keyed by view/callback" do
      sample = DebugTask.collect_sample(timeline_fixture())

      assert sample["MyAppWeb.PageLive/mount"] == 12.0
      assert sample["MyAppWeb.PageLive/handle_event:save"] == 30.0
    end

    test "aggregates per-fingerprint query durations" do
      sample = DebugTask.collect_sample(timeline_fixture())

      # two aaa queries summed, one bbb query
      assert sample["query:sha256:aaa"] == 5.0
      assert sample["query:sha256:bbb"] == 5.0
    end

    test "falls back to duration_since_previous_ms when event_duration_ms is missing" do
      timeline = %{
        timeline: [
          %{event: "render", view_module: "V", duration_since_previous_ms: 7.0, ecto_queries: []}
        ]
      }

      assert DebugTask.collect_sample(timeline)["V/render"] == 7.0
    end

    test "handles an empty/missing timeline gracefully" do
      assert DebugTask.collect_sample(%{}) == %{}
      assert DebugTask.collect_sample(%{timeline: []}) == %{}
    end
  end
end
