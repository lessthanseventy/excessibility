defmodule Excessibility.LiveViewRules.Rules.ClickAwayWithoutEscape do
  @moduledoc """
  Flags elements that use `phx-click-away` for dismissal but provide no
  keyboard equivalent, leaving keyboard and screen-reader users unable
  to close the overlay.

  ## What's flagged

  An element with `phx-click-away` that is not:

    * carrying a `phx-window-keydown` or `phx-keydown` handler paired
      with `phx-key="Escape"` on the same element
    * a dialog (`role="dialog"` or `role="alertdialog"`), which is
      assumed to manage its own focus and Escape handling

  ## Fix

      <!-- Bad -->
      <div id="menu" phx-click-away={JS.hide(to: "#menu")}>
        ...
      </div>

      <!-- Good -->
      <div
        id="menu"
        phx-click-away={JS.hide(to: "#menu")}
        phx-window-keydown={JS.hide(to: "#menu")}
        phx-key="Escape"
      >
        ...
      </div>
  """

  @behaviour Excessibility.LiveViewRules.Rule

  @dialog_roles ~w(dialog alertdialog)

  @impl true
  def id, do: :click_away_without_escape

  @impl true
  def default_enabled?, do: true

  @impl true
  def check(tree, _opts) do
    tree
    |> Floki.find("[phx-click-away]")
    |> Enum.reject(&has_escape_handling?/1)
    |> Enum.map(&build_finding/1)
  end

  # ── Implementation ────────────────────────────────────────────────

  defp has_escape_handling?({_tag, attrs, _children}) do
    dialog?(attrs) or escape_keydown?(attrs)
  end

  defp dialog?(attrs) do
    case find_attr(attrs, "role") do
      nil -> false
      role -> role in @dialog_roles
    end
  end

  defp escape_keydown?(attrs) do
    has_keydown? = has_attr?(attrs, "phx-keydown") or has_attr?(attrs, "phx-window-keydown")
    escape_key? = find_attr(attrs, "phx-key") == "Escape"
    has_keydown? and escape_key?
  end

  defp build_finding({tag, attrs, _children} = element) do
    %{
      rule: id(),
      severity: :serious,
      message: build_message(tag, attrs),
      element: element |> Floki.raw_html() |> String.slice(0, 300),
      selector: build_selector(tag, attrs),
      help:
        "Add `phx-window-keydown` (or `phx-keydown`) with `phx-key=\"Escape\"` " <>
          "on the same element, pointing at the same JS command. For modal " <>
          "dialogs, use `role=\"dialog\"` with proper focus management.",
      help_url: "https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/"
    }
  end

  # A keydown handler is present but phx-key is "escape"/"ESCAPE"/etc. rather
  # than the exact DOM value "Escape", so Escape dismissal silently never
  # fires. Common, hard-to-spot pitfall — call it out specifically (#110).
  defp build_message(tag, attrs) do
    if miscased_escape?(attrs) do
      key = find_attr(attrs, "phx-key")

      "<#{tag}> has a keydown handler with phx-key=\"#{key}\", but phx-key is matched " <>
        "literally against KeyboardEvent.key — it must be capitalized as \"Escape\". " <>
        "As written, Escape dismissal silently never fires."
    else
      "<#{tag}> uses phx-click-away for dismissal but has no keyboard equivalent. " <>
        "Keyboard and screen-reader users cannot close this overlay. Add phx-window-keydown " <>
        "with phx-key=\"Escape\" (must match KeyboardEvent.key exactly — capitalized)."
    end
  end

  defp miscased_escape?(attrs) do
    has_keydown? = has_attr?(attrs, "phx-keydown") or has_attr?(attrs, "phx-window-keydown")
    key = find_attr(attrs, "phx-key")

    has_keydown? and is_binary(key) and String.downcase(key) == "escape" and key != "Escape"
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
