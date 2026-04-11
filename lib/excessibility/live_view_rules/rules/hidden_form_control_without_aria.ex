defmodule Excessibility.LiveViewRules.Rules.HiddenFormControlWithoutAria do
  @moduledoc """
  Flags visually hidden `<input type="checkbox">` / `<input type="radio">`
  elements used as the programmatic backing for custom UI, when the
  visual replacement does not communicate checked state via ARIA.

  ## What's flagged

  An `<input type="checkbox|radio">` whose `class` attribute contains
  `hidden` or `sr-only`, whose enclosing `<label>` ancestor (if any)
  does not carry `aria-checked`, `aria-pressed`, `role="checkbox"`, or
  `role="radio"`. If no `<label>` wraps the input, the input is flagged
  because screen readers will see an unlabeled, hidden control.

  This rule is deliberately conservative; the issue tracker notes this
  pattern is "harder to detect reliably."

  ## Fix

      <!-- Bad -->
      <label class="chip">
        <input type="checkbox" class="hidden" name="color[]" value="red" checked />
        Red
      </label>

      <!-- Good -->
      <label class="chip" role="checkbox" aria-checked="true">
        <input type="checkbox" class="hidden" name="color[]" value="red" checked />
        Red
      </label>
  """

  @behaviour Excessibility.LiveViewRules.Rule

  @hidden_classes ~w(hidden sr-only)
  @ok_roles ~w(checkbox radio switch)

  @impl true
  def id, do: :hidden_form_control_without_aria

  @impl true
  def default_enabled?, do: true

  @impl true
  def check(tree, _opts) do
    tree
    |> Floki.find("input")
    |> Enum.filter(&hidden_toggle?/1)
    |> Enum.flat_map(&maybe_finding(&1, tree))
  end

  # ── Implementation ────────────────────────────────────────────────

  defp hidden_toggle?({"input", attrs, _children}) do
    type = find_attr(attrs, "type")
    classes = find_attr(attrs, "class") || ""

    type in ["checkbox", "radio"] and
      Enum.any?(String.split(classes, ~r/\s+/, trim: true), &(&1 in @hidden_classes))
  end

  defp hidden_toggle?(_), do: false

  defp maybe_finding({_tag, attrs, _children} = element, tree) do
    input_id = find_attr(attrs, "id")
    wrapping = wrapping_label(tree, input_id)

    if wrapping_has_aria?(wrapping) do
      []
    else
      [build_finding(element, attrs, input_id)]
    end
  end

  # Look for a <label> that either contains this input or has for=<id>.
  defp wrapping_label(tree, nil), do: find_parent_label(tree)

  defp wrapping_label(tree, input_id) do
    case Floki.find(tree, "label[for=\"#{input_id}\"]") do
      [label | _] -> label
      [] -> find_parent_label(tree)
    end
  end

  # Fallback: check every <label> in the tree that contains a hidden
  # input. Floki doesn't give us parent pointers, so we approximate by
  # looking at each label's descendants.
  defp find_parent_label(tree) do
    tree
    |> Floki.find("label")
    |> Enum.find(fn label ->
      Enum.any?(Floki.find(label, "input"), &hidden_toggle?/1)
    end)
  end

  defp wrapping_has_aria?(nil), do: false

  defp wrapping_has_aria?({_tag, attrs, _children}) do
    has_attr?(attrs, "aria-checked") or
      has_attr?(attrs, "aria-pressed") or
      role_is_ok?(attrs)
  end

  defp role_is_ok?(attrs) do
    case find_attr(attrs, "role") do
      nil -> false
      role -> role in @ok_roles
    end
  end

  defp build_finding({tag, _attrs, _children} = element, attrs, input_id) do
    target =
      case input_id do
        nil -> "(unnamed)"
        id -> "##{id}"
      end

    %{
      rule: id(),
      severity: :moderate,
      message:
        "<#{tag} type=\"#{find_attr(attrs, "type")}\"> #{target} is visually hidden but its " <>
          "visual replacement does not expose checked state via aria-checked/aria-pressed " <>
          "or role=\"checkbox\"/\"radio\". Screen-reader users won't know the control is toggled.",
      element: element |> Floki.raw_html() |> String.slice(0, 300),
      selector: build_selector(tag, attrs),
      help:
        "Either stop hiding the native input (use `opacity: 0` + absolute " <>
          "positioning with focusability intact) OR add `role=\"checkbox\"` " <>
          "and `aria-checked` to the visual wrapper and sync them with the hidden input.",
      help_url: "https://www.w3.org/WAI/ARIA/apg/patterns/checkbox/"
    }
  end

  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, v} -> v
      _ -> nil
    end)
  end

  defp has_attr?(attrs, name) do
    Enum.any?(attrs, fn {n, _} -> n == name end)
  end

  defp build_selector(tag, attrs) do
    case find_attr(attrs, "id") do
      nil -> tag
      id -> "#{tag}##{id}"
    end
  end
end
