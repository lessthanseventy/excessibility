defmodule Excessibility.LiveViewRules.Rules.ClickAwayWithoutEscapeTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules

  @rule_id :click_away_without_escape

  defp findings(html) do
    LiveViewRules.scan(html, only: [@rule_id]).findings
  end

  describe "flags missing keyboard dismissal" do
    test "div with only phx-click-away" do
      html = ~s(<div id="menu" phx-click-away="close">Panel</div>)
      assert [finding] = findings(html)
      assert finding.rule == @rule_id
      assert finding.severity == :serious
      assert finding.selector == "div#menu"
    end

    test "keydown present but phx-key is not Escape" do
      html = ~s(<div phx-click-away="close" phx-window-keydown="close" phx-key="Enter">Panel</div>)
      assert [_] = findings(html)
    end

    test "phx-key=Escape without keydown handler (invalid pairing)" do
      html = ~s(<div phx-click-away="close" phx-key="Escape">Panel</div>)
      assert [_] = findings(html)
    end
  end

  describe "allows elements with Escape handling" do
    test "phx-window-keydown + phx-key=Escape" do
      html = ~s(<div phx-click-away="close" phx-window-keydown="close" phx-key="Escape">Panel</div>)
      assert [] = findings(html)
    end

    test "phx-keydown + phx-key=Escape" do
      html = ~s(<div phx-click-away="close" phx-keydown="close" phx-key="Escape">Panel</div>)
      assert [] = findings(html)
    end
  end

  describe "allows dialog roles" do
    test "role=dialog" do
      html = ~s(<div phx-click-away="close" role="dialog">Modal</div>)
      assert [] = findings(html)
    end

    test "role=alertdialog" do
      html = ~s(<div phx-click-away="close" role="alertdialog">Alert</div>)
      assert [] = findings(html)
    end
  end

  describe "does not flag elements without phx-click-away" do
    test "plain div" do
      html = ~s(<div>Plain</div>)
      assert [] = findings(html)
    end
  end
end
