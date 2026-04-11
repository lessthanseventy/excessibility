defmodule Excessibility.LiveViewRules.Rules.PhxClickOnNonInteractiveTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules
  alias Excessibility.LiveViewRules.Rules.PhxClickOnNonInteractive

  @rule_id :phx_click_on_non_interactive

  defp findings(html) do
    LiveViewRules.scan(html, only: [@rule_id]).findings
  end

  describe "flags non-interactive elements" do
    test "<li phx-click>" do
      html = ~s(<ul><li phx-click="pick" id="item-1">Item</li></ul>)
      assert [finding] = findings(html)
      assert finding.rule == @rule_id
      assert finding.severity == :serious
      assert finding.selector == "li#item-1"
      assert finding.message =~ "phx-click"
      assert finding.element =~ "<li"
    end

    test "<div phx-click>" do
      html = ~s(<div phx-click="toggle" class="btn">Click me</div>)
      assert [finding] = findings(html)
      assert finding.selector == "div.btn"
    end

    test "<span phx-click>" do
      html = ~s(<span phx-click="select">word</span>)
      assert [%{selector: "span"}] = findings(html)
    end

    test "<tr phx-click>" do
      html = ~s(<table><tr phx-click="row"><td>r</td></tr></table>)
      assert [%{selector: "tr"}] = findings(html)
    end

    test "phx-click-away on non-interactive element" do
      html = ~s(<div phx-click-away="close">Panel</div>)
      assert [finding] = findings(html)
      assert finding.message =~ "phx-click-away"
    end
  end

  describe "allows natively interactive elements" do
    test "<button phx-click>" do
      html = ~s(<button type="button" phx-click="save">Save</button>)
      assert [] = findings(html)
    end

    test "<a phx-click>" do
      html = ~s(<a href="#" phx-click="go">Go</a>)
      assert [] = findings(html)
    end

    test "<input phx-click>" do
      html = ~s(<input type="checkbox" phx-click="toggle" />)
      assert [] = findings(html)
    end

    test "<select phx-click>" do
      html = ~s(<select phx-click="open"><option>a</option></select>)
      assert [] = findings(html)
    end

    test "<summary phx-click>" do
      html = ~s(<details><summary phx-click="expand">More</summary></details>)
      assert [] = findings(html)
    end
  end

  describe "allows non-native elements with interactive affordances" do
    test "div with tabindex" do
      html = ~s(<div phx-click="pick" tabindex="0">Pick</div>)
      assert [] = findings(html)
    end

    test "div with role=button" do
      html = ~s(<div phx-click="pick" role="button">Pick</div>)
      assert [] = findings(html)
    end

    test "li with role=option" do
      html = ~s(<ul role="listbox"><li phx-click="pick" role="option">Pick</li></ul>)
      assert [] = findings(html)
    end

    test "div with role=menuitem" do
      html = ~s(<div phx-click="pick" role="menuitem">Pick</div>)
      assert [] = findings(html)
    end
  end

  describe "multiple findings" do
    test "reports one finding per offending element" do
      html = """
      <ul>
        <li phx-click="a">A</li>
        <li phx-click="b">B</li>
        <li><button phx-click="c">C</button></li>
      </ul>
      """

      assert [_a, _b] = findings(html)
    end
  end

  describe "rule metadata" do
    test "id/0 returns the expected atom" do
      assert PhxClickOnNonInteractive.id() == @rule_id
    end

    test "default_enabled?/0 is true" do
      assert PhxClickOnNonInteractive.default_enabled?() == true
    end
  end
end
