defmodule Excessibility.LiveViewRules.Rules.ToggleMissingAriaStateTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules

  @rule_id :toggle_missing_aria_state

  defp findings(html) do
    LiveViewRules.scan(html, only: [@rule_id]).findings
  end

  # JS.toggle/show/hide serialize to a JSON array in the HTML attribute.
  defp js(op, target \\ "#menu"), do: ~s([["#{op}",{"to":"#{target}"}]])

  describe "flags missing aria-expanded" do
    test "div with JS.toggle and no ARIA" do
      html = ~s(<div phx-click='#{js("toggle")}'>Open</div>)
      assert [finding] = findings(html)
      assert finding.rule == @rule_id
      assert finding.severity == :serious
      assert finding.message =~ "aria-expanded"
      assert finding.message =~ "#menu"
    end

    test "button with JS.show and no ARIA" do
      html = ~s(<button phx-click='#{js("show")}'>Show</button>)
      assert [_] = findings(html)
    end

    test "div that toggles AND hides (mixed ops) and no ARIA" do
      html = ~s(<div phx-click='[["toggle",{"to":"#menu"}],["hide",{"to":"#other"}]]'>Open</div>)
      assert [_] = findings(html)
    end
  end

  describe "does not flag dismissers" do
    # A hide-only action is a dismiss, not a disclosure toggle. aria-expanded
    # belongs on the control that *shows* the target, not on a close button —
    # its value would be permanently wrong here. See issue #110.
    test "hide-only close button" do
      html = ~s(<button phx-click='#{js("hide", "#disconnected")}' aria-label="close">x</button>)
      assert [] = findings(html)
    end

    test "hide-only with a push op (flash clear pattern)" do
      html =
        ~s(<button phx-click='[["push",{"event":"lv:clear-flash"}],["hide",{"to":"#flash"}]]'>x</button>)

      assert [] = findings(html)
    end

    # A toggle whose target is the element's own ancestor container is closing
    # the container it lives in (e.g. a menu item that dismisses its menu), not
    # a disclosure toggler. The owning toggler lives outside the container.
    test "menu item toggling its own ancestor container" do
      html = """
      <div id="filter-menu-product" role="menu">
        <button phx-click='#{js("toggle", "#filter-menu-product")}'>Select product</button>
      </div>
      """

      assert [] = findings(html)
    end
  end

  describe "still flags real togglers" do
    # A toggler that opens a target it is NOT inside (e.g. a hamburger button)
    # must still expose aria-expanded.
    test "opener toggling a sibling container" do
      html = """
      <button phx-click='#{js("toggle", "#menu")}'>Menu</button>
      <div id="menu" role="menu">...</div>
      """

      assert [_] = findings(html)
    end
  end

  describe "allows elements with aria-expanded" do
    test "div with toggle + aria-expanded" do
      html = ~s(<div phx-click='#{js("toggle")}' aria-expanded="false">Open</div>)
      assert [] = findings(html)
    end

    test "button with toggle + aria-expanded + aria-controls" do
      html = ~s(<button phx-click='#{js("toggle")}' aria-expanded="false" aria-controls="menu">Open</button>)
      assert [] = findings(html)
    end
  end

  describe "does not flag non-toggle phx-click" do
    test "plain string phx-click value" do
      html = ~s(<button phx-click="save">Save</button>)
      assert [] = findings(html)
    end

    test "JSON phx-click with a non-toggle op like push" do
      html = ~s(<button phx-click='[["push",{"event":"save"}]]'>Save</button>)
      assert [] = findings(html)
    end
  end

  describe "multiple elements" do
    test "reports one finding per offending element" do
      html = """
      <div phx-click='#{js("toggle", "#m1")}'>A</div>
      <div phx-click='#{js("toggle", "#m2")}'>B</div>
      <div phx-click='#{js("toggle", "#m3")}' aria-expanded="false">C</div>
      """

      assert [_a, _b] = findings(html)
    end
  end
end
