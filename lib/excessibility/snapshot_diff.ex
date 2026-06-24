defmodule Excessibility.SnapshotDiff do
  @moduledoc """
  Cross-snapshot diffing: compare two HTML snapshots of the same view and
  report the regions whose rendered content changed.

  This is a capability no single-snapshot tool (axe-core included) can
  provide: by comparing a *before* and *after* of the same template it can
  detect that visible content changed. The first consumer is the
  accessibility check in `live_region_findings/3` — LiveView patches the
  DOM without a page load, so content that updates outside an `aria-live`
  region (or `role="alert"|"status"|"log"`, or `<output>`) is never
  announced to screen-reader users (WCAG 2.1 SC 4.1.3, Status Messages).

  `diff/3` itself is content-agnostic and returns the structural delta, so
  it doubles as a general-purpose semantic DOM diff for other callers.

  ## Diff strategy

  Both snapshots are parsed and walked in parallel from `<body>` down,
  matching element children positionally by tag. The change is localized
  to the **deepest element whose subtree text differs but whose children
  still line up** — i.e. the smallest stable container that owns the
  change. When the child structure itself diverges (rows added/removed,
  tags differ), that parent is reported as the changed region. Text is
  whitespace-normalized, so reflow/indentation differences are ignored.
  """

  alias Excessibility.LiveViewRules.Rule

  @live_roles ~w(alert status log)

  @typedoc "A single changed region produced by `diff/3`."
  @type region :: %{
          change: :changed,
          selector: String.t(),
          tag: String.t(),
          old_text: String.t(),
          new_text: String.t(),
          announced: boolean(),
          element: String.t()
        }

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Diff two HTML snapshots and return the list of changed regions.

  Each region is the deepest stable container whose normalized text
  content differs between `old_html` and `new_html`. Returns `[]` when the
  documents are content-equivalent (whitespace aside) or either fails to
  parse.
  """
  @spec diff(String.t(), String.t(), keyword()) :: [region()]
  def diff(old_html, new_html, _opts \\ []) when is_binary(old_html) and is_binary(new_html) do
    with {:ok, old_tree} <- Floki.parse_document(old_html),
         {:ok, new_tree} <- Floki.parse_document(new_html) do
      regions(root_node(old_tree), root_node(new_tree), [])
    else
      _ -> []
    end
  end

  @doc """
  Return accessibility findings for content that changed outside any live
  region, in the `Excessibility.LiveViewRules.Rule.finding/0` shape.

  A change is considered *announced* (and therefore not flagged) when the
  changed region or any of its ancestors is an `aria-live` region (a value
  other than `"off"`), carries `role="alert"|"status"|"log"`, or is an
  `<output>` element.
  """
  @spec live_region_findings(String.t(), String.t(), keyword()) :: [Rule.finding()]
  def live_region_findings(old_html, new_html, opts \\ []) do
    old_html
    |> diff(new_html, opts)
    |> Enum.reject(& &1.announced)
    |> Enum.map(&build_finding/1)
  end

  @doc """
  Run `live_region_findings/3` over each consecutive pair in a list of
  snapshots captured for the same test, and concatenate the findings.
  """
  @spec scan_sequence([String.t()], keyword()) :: [Rule.finding()]
  def scan_sequence(snapshots, opts \\ []) when is_list(snapshots) do
    snapshots
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [old, new] -> live_region_findings(old, new, opts) end)
  end

  # ── Diff walk ──────────────────────────────────────────────────────

  defp regions(old_node, new_node, ancestors) do
    if text(old_node) == text(new_node),
      do: [],
      else: diff_changed(old_node, new_node, ancestors)
  end

  defp diff_changed(old_node, new_node, ancestors) do
    old_children = element_children(old_node)
    new_children = element_children(new_node)

    if old_children != [] and matchable?(old_children, new_children),
      do: localize(old_node, new_node, ancestors, old_children, new_children),
      else: [region(old_node, new_node, ancestors)]
  end

  # Recurse into the matched children; if none of them changed, the change
  # lives in this node's own text nodes, so report this node itself.
  defp localize(old_node, new_node, ancestors, old_children, new_children) do
    child_ancestors = [new_node | ancestors]

    deeper =
      old_children
      |> Enum.zip(new_children)
      |> Enum.flat_map(fn {o, n} -> regions(o, n, child_ancestors) end)

    if deeper == [], do: [region(old_node, new_node, ancestors)], else: deeper
  end

  defp region(old_node, new_node, ancestors) do
    {tag, _attrs, _children} = new_node

    %{
      change: :changed,
      selector: selector(new_node),
      tag: tag,
      old_text: old_node |> text() |> String.slice(0, 300),
      new_text: new_node |> text() |> String.slice(0, 300),
      announced: Enum.any?([new_node | ancestors], &live_region?/1),
      element: new_node |> Floki.raw_html() |> String.slice(0, 300)
    }
  end

  # ── Findings ───────────────────────────────────────────────────────

  defp build_finding(region) do
    %{
      rule: :content_change_without_live_region,
      severity: :moderate,
      message:
        "<#{region.tag}> content changed between snapshots but is not inside an " <>
          "aria-live region. Screen readers will not announce the update.",
      element: region.element,
      selector: region.selector,
      help:
        "Wrap dynamically-updated content in a container with aria-live=\"polite\" " <>
          "(or role=\"status\"/\"alert\"/\"log\", or use <output>) so assistive " <>
          "technology announces changes made via LiveView patches.",
      help_url: "https://www.w3.org/WAI/WCAG21/Understanding/status-messages.html"
    }
  end

  # ── HTML helpers ───────────────────────────────────────────────────

  defp root_node(tree) do
    case Floki.find(tree, "body") do
      [body | _] -> body
      [] -> {"#root", [], tree}
    end
  end

  defp text(node) do
    node
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp element_children({_tag, _attrs, children}), do: Enum.filter(children, &element?/1)
  defp element_children(_), do: []

  defp element?({tag, _attrs, _children}) when is_binary(tag), do: true
  defp element?(_), do: false

  # Children "line up" when there is the same number of element children
  # and they are the same tags in the same order.
  defp matchable?(old_children, new_children) do
    length(old_children) == length(new_children) and
      old_children
      |> Enum.zip(new_children)
      |> Enum.all?(fn {{ot, _, _}, {nt, _, _}} -> ot == nt end)
  end

  defp live_region?({tag, attrs, _children}) do
    tag == "output" or live_role?(attrs) or live_aria?(attrs)
  end

  defp live_region?(_), do: false

  defp live_role?(attrs) do
    case find_attr(attrs, "role") do
      nil -> false
      role -> String.downcase(role) in @live_roles
    end
  end

  defp live_aria?(attrs) do
    case find_attr(attrs, "aria-live") do
      nil -> false
      value -> String.downcase(value) not in ["", "off"]
    end
  end

  defp selector({tag, attrs, _children}) do
    cond do
      id = find_attr(attrs, "id") -> "#{tag}##{id}"
      class = attrs |> find_attr("class") |> first_class() -> "#{tag}.#{class}"
      true -> tag
    end
  end

  defp first_class(nil), do: nil

  defp first_class(class_str) do
    class_str |> String.split(~r/\s+/, trim: true) |> List.first()
  end

  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, v} -> v
      _ -> nil
    end)
  end
end
