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
  def check(tree, _opts), do: collect(tree, [])

  # ── Implementation ────────────────────────────────────────────────

  # Walk the tree depth-first, tracking the ids of the current element's
  # ancestors so a toggle that targets its own container can be recognized
  # as a dismisser rather than a disclosure toggler.
  defp collect(nodes, ancestor_ids) when is_list(nodes), do: Enum.flat_map(nodes, &collect(&1, ancestor_ids))

  defp collect({_tag, attrs, children} = element, ancestor_ids) do
    findings = maybe_finding(element, ancestor_ids)

    child_ancestors =
      case find_attr(attrs, "id") do
        nil -> ancestor_ids
        id -> [id | ancestor_ids]
      end

    findings ++ collect(children, child_ancestors)
  end

  # Text/comment nodes have no children to recurse into.
  defp collect(_node, _ancestor_ids), do: []

  defp maybe_finding({_tag, attrs, _children} = element, ancestor_ids) do
    with value when is_binary(value) <- find_attr(attrs, "phx-click"),
         {:ok, ops} <- toggle_ops(value) do
      cond do
        has_attr?(attrs, "aria-expanded") -> []
        # Hide-only is a dismiss, not a disclosure toggle — aria-expanded
        # would be permanently wrong on a close button.
        dismiss_only?(ops) -> []
        # Toggling an ancestor container means closing the thing you live
        # inside (e.g. a menu item that dismisses its own menu).
        closes_own_container?(ops, ancestor_ids) -> []
        true -> [build_finding(element, op_targets(ops))]
      end
    else
      _ -> []
    end
  end

  defp toggle_ops(value) do
    case Jason.decode(value) do
      {:ok, ops} when is_list(ops) ->
        extracted = extract_ops(ops)
        if extracted == [], do: :not_a_toggle, else: {:ok, extracted}

      _ ->
        :not_a_toggle
    end
  end

  defp extract_ops(ops) do
    Enum.flat_map(ops, fn
      [op, %{"to" => target}] when op in @toggle_ops -> [{op, target}]
      [op, _params] when op in @toggle_ops -> [{op, nil}]
      _ -> []
    end)
  end

  defp dismiss_only?(ops), do: Enum.all?(ops, fn {op, _target} -> op == "hide" end)

  defp closes_own_container?(ops, ancestor_ids) do
    Enum.any?(ops, fn
      {_op, "#" <> id} -> id in ancestor_ids
      _ -> false
    end)
  end

  defp op_targets(ops), do: Enum.map(ops, fn {_op, target} -> target end)

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
