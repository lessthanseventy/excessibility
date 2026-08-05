defmodule Excessibility.Review.AxeFindingsTest do
  # Not async: swaps the global :scanner_mod between the Mox mock and the
  # default stub.
  use ExUnit.Case

  import Mox

  alias Excessibility.Review

  setup :verify_on_exit!

  setup do
    Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerMock)
    on_exit(fn -> Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerStub) end)
    :ok
  end

  @baseline ~s(<div><button data-test-id="review-button">Review Order</button></div>)
  @current ~s(<div><button data-test-id="review-button"> </button></div>)

  # Answers scans by reading the temp file the review wrote, so each side
  # of the pair can get its own report regardless of scan order.
  defp expect_scans(reports_by_marker) do
    expect(Excessibility.ScannerMock, :scan, map_size(reports_by_marker), fn "file://" <> path, _opts ->
      html = File.read!(path)

      {_marker, report} =
        Enum.find(reports_by_marker, fn {marker, _report} -> String.contains?(html, marker) end)

      {:ok, report}
    end)
  end

  defp button_name_violation(nodes) do
    %{
      id: "button-name",
      impact: :critical,
      description: "Ensures buttons have discernible text",
      help: "Buttons must have discernible text",
      help_url: "https://dequeuniversity.com/rules/axe/4.11/button-name",
      tags: ["wcag2a"],
      nodes: nodes
    }
  end

  defp axe_node(target) do
    %{target: [target], html: "<button> </button>", failure_summary: "Fix any of the following..."}
  end

  test "a newly introduced critical axe violation is :block" do
    expect_scans(%{
      "Review Order" => %{violations: []},
      ~s(> </button>) => %{violations: [button_name_violation([axe_node("button")])]}
    })

    change = Review.review_pair("offer_detail.html", @baseline, @current)

    assert Enum.any?(
             change.findings,
             &(&1.rule == "button-name" and &1.severity == :critical and &1.selector == "button")
           )

    assert change.tier == :block
  end

  test "a pre-existing axe violation is not re-flagged (finding-delta)" do
    violation = [button_name_violation([axe_node("button")])]

    expect_scans(%{
      "Review Order" => %{violations: violation},
      ~s(> </button>) => %{violations: violation}
    })

    change = Review.review_pair("offer_detail.html", @baseline, @current)

    refute Enum.any?(change.findings, &(&1.rule == "button-name"))
  end

  test "a second node of a pre-existing violation counts as new (per-node delta)" do
    expect_scans(%{
      "Review Order" => %{violations: [button_name_violation([axe_node("button")])]},
      ~s(> </button>) => %{violations: [button_name_violation([axe_node("button"), axe_node("button")])]}
    })

    change = Review.review_pair("offer_detail.html", @baseline, @current)

    assert Enum.count(change.findings, &(&1.rule == "button-name")) == 1
    assert change.tier == :block
  end

  test "a scan failure surfaces a report-level warning instead of findings" do
    expect(Excessibility.ScannerMock, :scan, 2, fn _url, _opts ->
      {:error, {:playwright_error, "chromium not found"}}
    end)

    report = Review.review_pairs([{"offer_detail.html", @baseline, @current}])

    assert [warning] = report.warnings
    assert warning =~ "axe scan failed"
    assert warning =~ "chromium not found"

    refute Enum.any?(Enum.flat_map(report.changes, & &1.findings), &(&1.rule == "button-name"))
  end

  test "axe: false skips scanning entirely" do
    change = Review.review_pair("offer_detail.html", @baseline, @current, axe: false)

    assert change.warnings == []
    refute Enum.any?(change.findings, &(&1.rule == "button-name"))
  end

  test "identical snapshots are not scanned" do
    change = Review.review_pair("offer_detail.html", @baseline, @baseline)

    assert change.tier == :auto
    assert change.warnings == []
  end
end
