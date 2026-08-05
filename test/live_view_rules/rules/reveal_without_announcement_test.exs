defmodule Excessibility.LiveViewRules.Rules.RevealWithoutAnnouncementTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules

  @rule_id :reveal_without_announcement

  defp findings(html) do
    LiveViewRules.scan(html, only: [@rule_id]).findings
  end

  describe "flags a hidden reveal target with no announcement" do
    # The issue's banner example: a hidden container carrying its own
    # serialized JS.show command (the push_event("js-exec") idiom).
    test "hidden div with a data-* JS.show command" do
      html =
        ~s(<div id="cap-reached-banner" class="hidden flex" data-show='[["show",{"display":"flex","transition":[[],[],[]]}]]'>Cap reached <button aria-label="Dismiss">x</button></div>)

      assert [finding] = findings(html)
      assert finding.rule == @rule_id
      assert finding.severity == :serious
      assert finding.message =~ "hidden"
      assert finding.help =~ ~s(role="alert")
      assert finding.help =~ ~s(role="status")
    end

    test "hidden div revealed by another element's phx-click JS.show with to:" do
      html = """
      <button phx-click='[["show",{"to":"#banner","display":"flex"}]]'>Show</button>
      <div id="banner" class="hidden">Banner text</div>
      """

      assert [finding] = findings(html)
      assert finding.selector == "div#banner"
    end

    test "JS.toggle also counts as a reveal" do
      html = ~s(<div id="b" class="hidden" data-toggle='[["toggle",{"display":"flex"}]]'>x</div>)
      assert [_] = findings(html)
    end

    test "hidden via inline display:none" do
      html = ~s(<div id="b" style="display: none" data-show='[["show",{}]]'>x</div>)
      assert [_] = findings(html)
    end

    test "hidden via the hidden attribute" do
      html = ~s(<div id="b" hidden data-show='[["show",{}]]'>x</div>)
      assert [_] = findings(html)
    end
  end

  describe "does not flag when an announcement role is present" do
    test "element has role=\"alert\"" do
      html = ~s(<div id="b" class="hidden" role="alert" data-show='[["show",{}]]'>x</div>)
      assert [] = findings(html)
    end

    test "element has role=\"status\"" do
      html = ~s(<div id="b" class="hidden" role="status" data-show='[["show",{}]]'>x</div>)
      assert [] = findings(html)
    end

    test "element has aria-live" do
      html = ~s(<div id="b" class="hidden" aria-live="polite" data-show='[["show",{}]]'>x</div>)
      assert [] = findings(html)
    end

    test "an ancestor is a live region" do
      html = """
      <div aria-live="polite">
        <div id="b" class="hidden" data-show='[["show",{}]]'>x</div>
      </div>
      """

      assert [] = findings(html)
    end

    test "an ancestor has role=\"log\"" do
      html = """
      <div role="log">
        <div id="b" class="hidden" data-show='[["show",{}]]'>x</div>
      </div>
      """

      assert [] = findings(html)
    end
  end

  describe "does not flag dialog reveal targets" do
    test "role=\"dialog\" container" do
      html = ~s(<div id="b" class="hidden" role="dialog" data-show='[["show",{}]]'>x</div>)
      assert [] = findings(html)
    end

    test "aria-modal container" do
      html = ~s(<div id="b" class="hidden" aria-modal="true" data-show='[["show",{}]]'>x</div>)
      assert [] = findings(html)
    end
  end

  describe "does not flag when the element is not a hidden reveal target" do
    test "visible element with a JS.show command" do
      html = ~s(<div id="b" data-show='[["show",{}]]'>x</div>)
      assert [] = findings(html)
    end

    test "hidden element with no reveal mechanism" do
      html = ~s(<div id="b" class="hidden">x</div>)
      assert [] = findings(html)
    end

    test "plain (non-serialized) data attribute value" do
      html = ~s(<div id="b" class="hidden" data-show="true">x</div>)
      assert [] = findings(html)
    end

    test "phx-* op targeting the element is a non-reveal op like hide" do
      html = """
      <button phx-click='[["hide",{"to":"#banner"}]]'>Hide</button>
      <div id="banner" class="hidden">Banner text</div>
      """

      assert [] = findings(html)
    end
  end
end
