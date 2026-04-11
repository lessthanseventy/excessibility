defmodule Excessibility.LiveViewRules.Rules.HiddenFormControlWithoutAriaTest do
  use ExUnit.Case, async: true

  alias Excessibility.LiveViewRules

  @rule_id :hidden_form_control_without_aria

  defp findings(html) do
    LiveViewRules.scan(html, only: [@rule_id]).findings
  end

  describe "flags hidden checkboxes/radios without ARIA on wrapper" do
    test "hidden checkbox inside plain label" do
      html = """
      <label for="c1" class="chip">
        <input type="checkbox" id="c1" class="hidden" name="color[]" value="red" checked />
        Red
      </label>
      """

      assert [finding] = findings(html)
      assert finding.rule == @rule_id
      assert finding.severity == :moderate
      assert finding.message =~ "checkbox"
    end

    test "hidden radio with sr-only class" do
      html = """
      <label for="r1">
        <input type="radio" id="r1" class="sr-only" name="size" value="s" />
        Small
      </label>
      """

      assert [_] = findings(html)
    end

    test "hidden checkbox with no label at all" do
      html = ~s(<input type="checkbox" class="hidden" name="x" value="1" />)
      assert [_] = findings(html)
    end
  end

  describe "allows hidden inputs whose wrapper has ARIA state" do
    test "label with role=checkbox + aria-checked" do
      html = """
      <label for="c1" role="checkbox" aria-checked="true">
        <input type="checkbox" id="c1" class="hidden" name="color[]" value="red" checked />
        Red
      </label>
      """

      assert [] = findings(html)
    end

    test "label with role=radio" do
      html = """
      <label for="r1" role="radio" aria-checked="false">
        <input type="radio" id="r1" class="sr-only" name="size" value="s" />
        Small
      </label>
      """

      assert [] = findings(html)
    end

    test "label with aria-pressed" do
      html = """
      <label for="c1" aria-pressed="true">
        <input type="checkbox" id="c1" class="hidden" name="t" value="1" />
        Toggle
      </label>
      """

      assert [] = findings(html)
    end
  end

  describe "does not flag non-hidden or non-toggle inputs" do
    test "visible checkbox" do
      html = ~s(<input type="checkbox" name="x" />)
      assert [] = findings(html)
    end

    test "hidden text input (not a toggle)" do
      html = ~s(<input type="text" name="x" class="hidden" value="secret" />)
      assert [] = findings(html)
    end

    test "non-interactive hidden div with class hidden" do
      html = ~s(<div class="hidden">not an input</div>)
      assert [] = findings(html)
    end
  end
end
