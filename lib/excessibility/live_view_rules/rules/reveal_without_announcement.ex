defmodule Excessibility.LiveViewRules.Rules.RevealWithoutAnnouncement do
  @moduledoc """
  Flags initially hidden containers that are revealed from the server
  without exposing that reveal to assistive technology.

  A common LiveView pattern un-hides a container without any page
  navigation or focus change — e.g. `push_event(socket, "js-exec", %{to:
  "#cap-reached-banner", attr: "data-show"})` executing a `JS.show`
  command stored on the element, or a sibling `phx-click={JS.show(to:
  "#banner")}`. Visually the banner appears; for a screen-reader user
  nothing happens, because at rest the element is hidden and carries no
  `role="alert"` / `role="status"` / `aria-live`. axe-core cannot catch
  this — the element is hidden when it scans.

  ## What's flagged

  An element for which **all** of the following hold:

    1. It is initially hidden — a `hidden` class, inline `display:none`,
       or the `hidden` attribute.
    2. It is a reveal target, detectable statically as either a `data-*`
       attribute on the element whose value is a serialized
       `JS.show`/`JS.toggle` command (the `js-exec` idiom), or another
       element's `phx-*` attribute carrying a `show`/`toggle` op whose
       `to` targets this element's id.
    3. It exposes no announcement — no `role="alert"`, `role="status"`,
       `role="log"`, no `aria-live`, and no ancestor providing one.

  Reveal targets that are dialogs (`role="dialog"` / `aria-modal`) are
  skipped: dialogs have their own correct focus-management pattern.

  ## Fix

      <!-- Bad -->
      <div id="banner" class="hidden" data-show={JS.show(display: "flex")}>
        You've reached your cap.
      </div>

      <!-- Good: informational transition -->
      <div id="banner" class="hidden" role="status" data-show={JS.show(display: "flex")}>
        You've reached your cap.
      </div>
  """

  @behaviour Excessibility.LiveViewRules.Rule

  @reveal_ops ~w(show toggle)
  @live_region_roles ~w(alert status log)
  @dialog_roles ~w(dialog alertdialog)

  @impl true
  def id, do: :reveal_without_announcement

  @impl true
  def default_enabled?, do: true

  @impl true
  def check(tree, _opts) do
    reveal_ids = collect_phx_reveal_targets(tree)
    walk(tree, false, reveal_ids)
  end

  # ── Implementation ────────────────────────────────────────────────

  # Walk the tree depth-first, tracking whether an ancestor is already a
  # live region so a reveal that lands inside one is not double-flagged.
  defp walk(nodes, in_live_region?, reveal_ids) when is_list(nodes),
    do: Enum.flat_map(nodes, &walk(&1, in_live_region?, reveal_ids))

  defp walk({_tag, attrs, children} = element, in_live_region?, reveal_ids) do
    findings = maybe_finding(element, in_live_region?, reveal_ids)
    child_in_live_region? = in_live_region? or live_region?(attrs)
    findings ++ walk(children, child_in_live_region?, reveal_ids)
  end

  # Text/comment nodes have no children to recurse into.
  defp walk(_node, _in_live_region?, _reveal_ids), do: []

  defp maybe_finding({_tag, attrs, _children} = element, in_live_region?, reveal_ids) do
    cond do
      not hidden?(attrs) -> []
      not reveal_target?(attrs, reveal_ids) -> []
      dialog_target?(attrs) -> []
      live_region?(attrs) -> []
      in_live_region? -> []
      true -> [build_finding(element)]
    end
  end

  # Collect ids targeted by a show/toggle op in any element's phx-*
  # attribute — the "another element reveals me" case.
  defp collect_phx_reveal_targets(tree) do
    tree
    |> all_elements()
    |> Enum.flat_map(fn {_tag, attrs, _children} ->
      Enum.flat_map(attrs, fn
        {"phx-" <> _, value} -> reveal_targets(value)
        _ -> []
      end)
    end)
    |> MapSet.new()
  end

  defp all_elements(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &all_elements/1)

  defp all_elements({_tag, _attrs, children} = element) when is_list(children), do: [element | all_elements(children)]

  defp all_elements(_node), do: []

  # Ids from `[["show"|"toggle",{"to":"#id",...}]]` serialized JS commands.
  defp reveal_targets(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, ops} when is_list(ops) ->
        Enum.flat_map(ops, fn
          [op, %{"to" => "#" <> id}] when op in @reveal_ops -> [id]
          _ -> []
        end)

      _ ->
        []
    end
  end

  defp reveal_targets(_value), do: []

  defp reveal_target?(attrs, reveal_ids) do
    data_reveal?(attrs) or targeted_by_phx?(attrs, reveal_ids)
  end

  # A data-* attribute holding a serialized JS.show/toggle command is the
  # `js-exec` idiom: the element reveals itself. No `to` is required.
  defp data_reveal?(attrs) do
    Enum.any?(attrs, fn
      {"data-" <> _, value} -> serialized_reveal?(value)
      _ -> false
    end)
  end

  defp targeted_by_phx?(attrs, reveal_ids) do
    case find_attr(attrs, "id") do
      nil -> false
      id -> MapSet.member?(reveal_ids, id)
    end
  end

  defp serialized_reveal?(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, ops} when is_list(ops) ->
        Enum.any?(ops, fn
          [op | _rest] when op in @reveal_ops -> true
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp serialized_reveal?(_value), do: false

  defp hidden?(attrs) do
    hidden_class?(attrs) or hidden_style?(attrs) or has_attr?(attrs, "hidden")
  end

  defp hidden_class?(attrs) do
    (find_attr(attrs, "class") || "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.member?("hidden")
  end

  defp hidden_style?(attrs) do
    (find_attr(attrs, "style") || "")
    |> String.replace(" ", "")
    |> String.contains?("display:none")
  end

  defp live_region?(attrs) do
    has_attr?(attrs, "aria-live") or role_in?(attrs, @live_region_roles)
  end

  defp dialog_target?(attrs) do
    role_in?(attrs, @dialog_roles) or has_attr?(attrs, "aria-modal")
  end

  defp role_in?(attrs, roles) do
    case find_attr(attrs, "role") do
      nil -> false
      role -> role in roles
    end
  end

  defp build_finding({tag, attrs, _children} = element) do
    %{
      rule: id(),
      severity: :serious,
      message:
        "<#{tag}> is initially hidden and revealed from the server, but exposes no " <>
          "announcement to assistive technology. Screen-reader users are never told it appeared.",
      element: element |> Floki.raw_html() |> String.slice(0, 300),
      selector: build_selector(tag, attrs),
      help:
        ~s(Add role="alert" for blocking or error states, or role="status" ) <>
          ~s{(equivalently aria-live="polite") for informational transitions, so the reveal } <>
          ~s(is announced. Also consider placing focus on the revealed content.),
      help_url: "https://www.w3.org/WAI/ARIA/apg/practices/live-regions/"
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
