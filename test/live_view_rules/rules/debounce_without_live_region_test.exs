defmodule Excessibility.LiveViewRules.Rules.DebounceWithoutLiveRegionTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules

  @rule_id :debounce_without_live_region

  defp findings(html) do
    LiveViewRules.scan(html, only: [@rule_id]).findings
  end

  describe "flags debounced inputs when no live region exists" do
    test "search input without any aria-live anywhere" do
      html = """
      <html><body>
        <input type="search" name="q" phx-debounce="200" />
        <table><tbody><tr><td>Result</td></tr></tbody></table>
      </body></html>
      """

      assert [finding] = findings(html)
      assert finding.rule == @rule_id
      assert finding.severity == :moderate
      assert finding.message =~ "aria-live"
    end

    test "input with phx-debounce blur" do
      html = ~s(<input type="text" name="q" phx-debounce="blur" />)
      assert [_] = findings(html)
    end
  end

  describe "does not flag when a live region exists" do
    test "page with aria-live=polite container" do
      html = """
      <input type="search" name="q" phx-debounce="200" />
      <div aria-live="polite"><table><tbody><tr><td>Result</td></tr></tbody></table></div>
      """

      assert [] = findings(html)
    end

    test "page with role=status container" do
      html = """
      <input type="search" name="q" phx-debounce="200" />
      <div role="status">Results</div>
      """

      assert [] = findings(html)
    end

    test "page with role=alert container" do
      html = """
      <input type="search" name="q" phx-debounce="200" />
      <div role="alert">Updated</div>
      """

      assert [] = findings(html)
    end
  end

  describe "does not flag inputs without phx-debounce" do
    test "plain input" do
      html = ~s(<input type="search" name="q" />)
      assert [] = findings(html)
    end
  end
end
