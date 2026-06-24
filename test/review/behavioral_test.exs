defmodule Excessibility.Review.BehavioralTest do
  use ExUnit.Case, async: true

  alias Excessibility.Review.Behavioral

  # A stand-in analyzer so the test doesn't depend on a realistic timeline.
  defmodule StubAnalyzer do
    @moduledoc false
    @behaviour Excessibility.TelemetryCapture.Analyzer

    @impl true
    def name, do: :stub

    @impl true
    def default_enabled?, do: false

    @impl true
    def analyze(_timeline, _opts) do
      %{
        findings: [
          %{severity: :critical, message: "N+1 query in orders list", events: [3], metadata: %{}},
          %{severity: :info, message: "assign :cart never changes", events: [1], metadata: %{}}
        ],
        stats: %{}
      }
    end
  end

  test "runs the given analyzers and normalizes their findings" do
    findings = Behavioral.findings(%{timeline: []}, analyzers: [StubAnalyzer])

    assert [critical, info] = findings
    assert critical.rule == :stub
    assert critical.source == :telemetry
    # analyzer :critical maps to the review :serious scale
    assert critical.severity == :serious
    assert critical.message =~ "N+1"
    assert critical.events == [3]
    # analyzer :info maps to :minor
    assert info.severity == :minor
  end

  test "returns an empty list when no analyzers produce findings" do
    defmodule QuietAnalyzer do
      @moduledoc false
      @behaviour Excessibility.TelemetryCapture.Analyzer

      @impl true
      def name, do: :quiet
      @impl true
      def default_enabled?, do: false
      @impl true
      def analyze(_timeline, _opts), do: %{findings: [], stats: %{}}
    end

    assert Behavioral.findings(%{}, analyzers: [QuietAnalyzer]) == []
  end
end
