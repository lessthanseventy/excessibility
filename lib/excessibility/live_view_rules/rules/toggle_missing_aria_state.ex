defmodule Excessibility.LiveViewRules.Rules.ToggleMissingAriaState do
  @moduledoc """
  Flags elements that use `Phoenix.LiveView.JS.toggle/show/hide` in
  `phx-click` but do not expose the expand/collapse state to assistive
  technology.

  LiveView's `JS` commands serialize to a JSON array in the rendered
  HTML: `phx-click="[[\\"toggle\\",{\\"to\\":\\"#menu\\"}]]"`. This rule
  parses that JSON, detects toggle/show/hide operations, and verifies
  that the trigger element carries `aria-expanded`. Missing
  `aria-controls` is reported in the same finding when the toggle
  target is known.

  ## What's flagged

  Elements whose `phx-click` contains a `toggle`, `show`, or `hide`
  operation, and that are missing `aria-expanded`. `aria-haspopup` is
  not required (not every toggle is a menu or listbox).

  ## Fix

      <!-- Bad -->
      <div phx-click={JS.toggle(to: "#menu")}>
        Open menu
      </div>

      <!-- Good -->
      <button
        type="button"
        phx-click={JS.toggle(to: "#menu")}
        aria-expanded="false"
        aria-controls="menu"
      >
        Open menu
      </button>
  """

  @behaviour Excessibility.LiveViewRules.Rule

  @toggle_ops ~w(toggle show hide)

  @impl true
  def id, do: :toggle_missing_aria_state

  @impl true
  def default_enabled?, do: true

  @impl true
  def check(tree, _opts) do
    tree
    |> Floki.find("[phx-click]")
    |> Enum.flat_map(&maybe_finding/1)
  end

  # ── Implementation ────────────────────────────────────────────────

  defp maybe_finding({_tag, attrs, _children} = element) do
    with value when is_binary(value) <- find_attr(attrs, "phx-click"),
         {:ok, targets} <- toggle_targets(value) do
      if has_attr?(attrs, "aria-expanded") do
        []
      else
        [build_finding(element, targets)]
      end
    else
      _ -> []
    end
  end

  defp toggle_targets(value) do
    case Jason.decode(value) do
      {:ok, ops} when is_list(ops) ->
        targets = extract_toggle_targets(ops)
        if targets == [], do: :not_a_toggle, else: {:ok, targets}

      _ ->
        :not_a_toggle
    end
  end

  defp extract_toggle_targets(ops) do
    Enum.flat_map(ops, fn
      [op, %{"to" => target}] when op in @toggle_ops -> [target]
      [op, _params] when op in @toggle_ops -> [nil]
      _ -> []
    end)
  end

  defp build_finding({tag, attrs, _children} = element, targets) do
    %{
      rule: id(),
      severity: :serious,
      message: message(tag, targets),
      element: element |> Floki.raw_html() |> String.slice(0, 300),
      selector: build_selector(tag, attrs),
      help:
        "Add `aria-expanded` to the trigger (toggle its value in your " <>
          "event handler). Also set `aria-controls` to the target id, and " <>
          "`aria-haspopup` if the target is a menu, listbox, or dialog.",
      help_url: "https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/"
    }
  end

  defp message(tag, targets) do
    target_hint =
      targets
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> ""
        [t | _] -> " (toggles #{t})"
      end

    "<#{tag}> uses JS.toggle/show/hide#{target_hint} but has no aria-expanded. " <>
      "Screen readers cannot tell whether the target is open or closed."
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
