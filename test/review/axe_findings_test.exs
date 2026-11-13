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

  describe "two renders of the same code" do
    defp render(csrf, session, root, id, uuid, seq, body_class) do
      """
      <!--
      Excessibility Snapshot
      Timestamp: 2026-11-12T10:00:#{seq}Z
      Assigns: %{id: #{id}}
      -->
      <html><head><meta name="csrf-token" content="#{csrf}"></head><body class="#{body_class}">
      <div id="phx-#{root}" data-phx-main data-phx-session="#{session}" data-phx-static="#{session}x">
        <div data-phx-id="m1-phx-#{root}" data-phx-parent-id="phx-#{root}">
          <form><input type="hidden" name="_csrf_token" value="#{csrf}"><a data-csrf="#{csrf}" href="/orders/#{id}">Go</a></form>
          <article data-test-id="product-card-#{id}" id="faq-article-#{uuid}" phx-value-id="#{id}">
            <label for="quantity#{id}">Quantity for product #{id}</label>
            <input id="quantity#{id}" name="items[#{id}][quantity]" type="text" value="#{seq}">
            <p aria-describedby="faq-article-#{uuid}">email-#{seq}@example.com</p>
          </article>
        </div>
      </div>
      </body></html>
      """
    end

    defp baseline_render(body_class \\ "text-neutral-900") do
      render("tokA", "sessA", "F1a_x-Q", 2_741_595, "0ad113de-7c1e-4f0a-9b1d-3f2a6c5e8d90", 568, body_class)
    end

    defp current_render(body_class \\ "text-neutral-900") do
      render("tokB", "sessB", "G2b-y_R", 2_741_611, "f3b9c2a1-1d2e-4a3b-8c4d-5e6f7a8b9c0d", 400, body_class)
    end

    test "per-render tokens and test-data ids do not trigger a scan" do
      change = Review.review_pair("product", baseline_render(), current_render())

      assert change.tier == :auto
      assert change.warnings == []
    end

    test "a class-only change is still scanned" do
      expect(Excessibility.ScannerMock, :scan, 2, fn _url, _opts -> {:ok, %{violations: []}} end)

      Review.review_pair("product", baseline_render(), current_render("text-neutral-400"))
    end
  end
end
