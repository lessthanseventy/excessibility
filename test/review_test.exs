defmodule Excessibility.ReviewTest do
  use ExUnit.Case, async: true

  alias Excessibility.Review

  defmodule CriticalStubAnalyzer do
    @moduledoc false
    @behaviour Excessibility.TelemetryCapture.Analyzer

    @impl true
    def name, do: :stub
    @impl true
    def default_enabled?, do: false
    @impl true
    def analyze(_timeline, _opts) do
      %{findings: [%{severity: :critical, message: "N+1 query in orders", events: [], metadata: %{}}], stats: %{}}
    end
  end

  @table_two ~s(<table><tbody><tr><td>Request A</td></tr><tr><td>Request B</td></tr></tbody></table>)
  @table_one ~s(<table><tbody><tr><td>Request A</td></tr></tbody></table>)

  describe "review_pair/4 — tiering a single view's change" do
    test "identical snapshots produce no change and tier :auto" do
      change = Review.review_pair("home", "<div>hi</div>", "<div>hi</div>")

      assert change.view == "home"
      assert change.regions == []
      assert change.findings == []
      assert change.tier == :auto
    end

    test "content changed outside a live region is :review with the changed region" do
      change = Review.review_pair("orders", @table_two, @table_one)

      assert change.region_count == 1
      assert Enum.any?(change.findings, &(&1.rule == :content_change_without_live_region))
      assert change.tier == :review
    end

    test "a newly introduced serious rule violation is :block" do
      baseline = ~s(<div>Save</div>)
      current = ~s(<div phx-click="save">Save</div>)

      change = Review.review_pair("editor", baseline, current)

      assert Enum.any?(change.findings, &(&1.rule == :phx_click_on_non_interactive))
      assert change.tier == :block
    end

    test "a pre-existing rule violation is not counted as new (finding-delta)" do
      # The phx-click violation exists in BOTH snapshots; only the text inside
      # a live region changed, so there is nothing newly wrong.
      baseline = ~s(<div role="status"><span phx-click="a">old</span></div>)
      current = ~s(<div role="status"><span phx-click="a">new</span></div>)

      change = Review.review_pair("widget", baseline, current)

      assert change.findings == []
      assert change.region_count == 1
      assert change.tier == :auto
    end

    test "a change inside a live region with no new findings is :auto" do
      baseline = ~s(<div aria-live="polite"><p>0 results</p></div>)
      current = ~s(<div aria-live="polite"><p>1 result</p></div>)

      change = Review.review_pair("search", baseline, current)

      assert change.findings == []
      assert change.region_count == 1
      assert change.tier == :auto
    end
  end

  describe "review_pairs/2 — aggregating across views" do
    test "keeps only views that actually changed and summarizes tiers" do
      pairs = [
        {"unchanged", "<div>x</div>", "<div>x</div>"},
        {"orders", @table_two, @table_one},
        {"editor", "<div>Save</div>", ~s(<div phx-click="save">Save</div>)}
      ]

      report = Review.review_pairs(pairs)

      views = Enum.map(report.changes, & &1.view)
      refute "unchanged" in views
      assert "orders" in views
      assert "editor" in views
      assert report.summary.block == 1
      assert report.summary.review == 1
    end
  end

  describe "behavioral findings from a timeline" do
    test "are attached to the change and escalate the tier" do
      change =
        Review.review_pair("orders", "<div>x</div>", "<div>x</div>",
          timeline: %{},
          analyzers: [CriticalStubAnalyzer]
        )

      # No DOM change, but a critical behavioral finding makes it :block.
      assert change.region_count == 0
      assert change.findings == []
      assert [%{source: :telemetry, severity: :serious}] = change.behavioral
      assert change.tier == :block
    end

    test "review/1 computes them once at the report level" do
      report = Review.review(timeline: %{}, analyzers: [CriticalStubAnalyzer])

      assert [%{rule: :stub}] = report.behavioral
    end
  end
end
