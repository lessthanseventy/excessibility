defmodule Excessibility.Review.BehavioralCrossViewTest do
  @moduledoc """
  Regression for issue #142: behavioral analyzers must not raise serious
  findings on a healthy journey timeline that interleaves several
  LiveViews. The fixture is the numbers-only 12-event timeline from the
  issue (a MarketplaceLive.Index journey with UserLoginLive mounts
  interleaved), which previously produced 5 :serious findings purely from
  cross-view adjacency and small-sample ratios.
  """
  use ExUnit.Case, async: true

  alias Excessibility.Review.Behavioral
  alias Excessibility.TelemetryCapture.Analyzers.DataGrowth
  alias Excessibility.TelemetryCapture.Analyzers.Memory
  alias Excessibility.TelemetryCapture.Analyzers.Performance
  alias Excessibility.TelemetryCapture.Analyzers.RenderEfficiency

  @fixture Path.join([__DIR__, "..", "support", "fixtures", "timeline_cross_view.json"])

  setup do
    timeline = @fixture |> File.read!() |> Jason.decode!(keys: :atoms)
    {:ok, timeline: timeline}
  end

  test "memory: no findings from cross-view adjacency (finding #1)", %{timeline: timeline} do
    result = Memory.analyze(timeline, [])

    assert result.findings == [],
           "expected no memory findings, got: #{inspect(result.findings)}"
  end

  test "data_growth: 0 -> 1 across views is not flagged (finding #2)", %{timeline: timeline} do
    result = DataGrowth.analyze(timeline, [])

    assert result.findings == [],
           "expected no data_growth findings, got: #{inspect(result.findings)}"
  end

  test "performance: 40ms first mount is not slow/bottleneck (finding #3)", %{timeline: timeline} do
    result = Performance.analyze(timeline, [])

    assert Enum.all?(result.findings, &(&1.severity != :critical)),
           "expected no critical performance findings, got: #{inspect(result.findings)}"
  end

  test "render_efficiency: 2 of 4 renders wasted is below sample floor (finding #4)", %{timeline: timeline} do
    result = RenderEfficiency.analyze(timeline, [])

    assert result.findings == [],
           "expected no render_efficiency findings, got: #{inspect(result.findings)}"
  end

  test "behavioral: healthy timeline yields zero serious findings", %{timeline: timeline} do
    analyzers = [Memory, DataGrowth, Performance, RenderEfficiency]
    findings = Behavioral.findings(timeline, analyzers: analyzers)

    serious = Enum.filter(findings, &(&1.severity == :serious))

    assert serious == [], "expected no serious behavioral findings, got: #{inspect(serious)}"
  end
end
