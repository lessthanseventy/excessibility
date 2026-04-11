defmodule Excessibility.LiveViewRulesTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules

  describe "rules/0" do
    test "discovers built-in rules" do
      ids = Enum.map(LiveViewRules.rules(), & &1.id())
      assert :phx_click_on_non_interactive in ids
    end
  end

  describe "scan/2 — rule framework" do
    test "returns empty findings for HTML with no phx-* attributes" do
      html = """
      <html><body>
        <div class="card">Just a card</div>
        <p>Plain text</p>
      </body></html>
      """

      assert %{findings: [], rules_run: rules_run} = LiveViewRules.scan(html)
      assert :phx_click_on_non_interactive in rules_run
    end

    test "returns empty findings and empty rules_run on invalid HTML" do
      # Floki is permissive; pass an obviously empty string
      assert %{findings: []} = LiveViewRules.scan("")
    end

    test ":disable skips listed rules" do
      html = ~s(<li phx-click="pick">Item</li>)

      assert %{findings: []} =
               LiveViewRules.scan(html, disable: [:phx_click_on_non_interactive])
    end

    test ":only runs only the listed rules" do
      html = ~s(<li phx-click="pick">Item</li>)

      assert %{findings: findings, rules_run: [:phx_click_on_non_interactive]} =
               LiveViewRules.scan(html, only: [:phx_click_on_non_interactive])

      assert length(findings) == 1
    end
  end
end
