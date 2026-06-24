defmodule Excessibility.LiveViewRules.Rules.PhxClickOnNonInteractive do
  @moduledoc """
  Flags `phx-click` and `phx-click-away` placed on elements that are not
  natively keyboard-accessible.

  axe-core cannot catch this because it doesn't understand Phoenix event
  attributes. The result is a visually clickable element that is
  unreachable by keyboard users — no focus, no Enter/Space handling, no
  assistive-tech affordances.

  `phx-click-away` is **not** flagged here: it fires when the user clicks
  *elsewhere*, so the element is never an activation target and does not need
  to be keyboard-focusable. Keyboard dismissal of click-away overlays is
  covered by `click_away_without_escape`.

  ## What's flagged

  Any element carrying `phx-click` that is **not**:

    * a natively interactive element (`<a>`, `<button>`, `<input>`,
      `<select>`, `<textarea>`, `<summary>`, `<details>`)
    * an element with a `tabindex` attribute
    * an element with an interactive `role` attribute (`button`, `link`,
      `option`, `menuitem`, `tab`, `checkbox`, `radio`, `switch`, etc.)

  ## Fix

  Prefer a real `<button type="button">` or `<a href="...">`. If the
  design requires a non-semantic tag, add `tabindex="0"`, an appropriate
  `role`, and keyboard event handlers (Enter/Space).

      <!-- Bad -->
      <li phx-click="select">Item</li>

      <!-- Good -->
      <li><button type="button" phx-click="select">Item</button></li>
  """

  @behaviour Excessibility.LiveViewRules.Rule

  @interactive_tags ~w(a button input select textarea summary details)

  @interactive_roles ~w(
    button link option menuitem tab checkbox radio switch
    menuitemcheckbox menuitemradio combobox textbox searchbox spinbutton
    slider treeitem
  )

  @impl true
  def id, do: :phx_click_on_non_interactive

  @impl true
  def default_enabled?, do: true

  @impl true
  def check(tree, _opts) do
    tree
    |> Floki.find("[phx-click]")
    |> Enum.reject(&interactive?/1)
    |> Enum.map(&build_finding/1)
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp interactive?({tag, _attrs, _children}) when tag in @interactive_tags, do: true

  defp interactive?({_tag, attrs, _children}) do
    Enum.any?(attrs, fn
      {"tabindex", _} -> true
      {"role", role} -> role in @interactive_roles
      _ -> false
    end)
  end

  defp interactive?(_), do: false

  defp build_finding({tag, attrs, _children} = element) do
    %{
      rule: id(),
      severity: :serious,
      message:
        "<#{tag}> has phx-click but is not keyboard-accessible. " <>
          "Use <button>/<a>, or add tabindex=\"0\" with an interactive role and keyboard handlers.",
      element: element |> Floki.raw_html() |> String.slice(0, 300),
      selector: build_selector(tag, attrs),
      help:
        "Place phx-click on a natively interactive element (<button>, <a>, <input>), " <>
          "or make the element focusable (tabindex=\"0\") with a proper role and keyboard event handlers.",
      help_url: "https://www.w3.org/WAI/ARIA/apg/patterns/button/"
    }
  end

  defp build_selector(tag, attrs) do
    id = find_attr(attrs, "id")
    first_class = attrs |> find_attr("class") |> first_class()

    cond do
      id -> "#{tag}##{id}"
      first_class -> "#{tag}.#{first_class}"
      true -> tag
    end
  end

  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, v} -> v
      _ -> nil
    end)
  end

  defp first_class(nil), do: nil

  defp first_class(class_str) do
    class_str
    |> String.split(~r/\s+/, trim: true)
    |> List.first()
  end
end
