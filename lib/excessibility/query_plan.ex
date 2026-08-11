defmodule Excessibility.QueryPlan do
  @moduledoc """
  Summarizes a decoded Postgres `EXPLAIN (FORMAT JSON)` result into a value-free
  plan digest — node types, relation names and row *estimates* only, never any
  row data.

  The plan `fingerprint` hashes ONLY the structural tree (node types + relation
  names in traversal order), so it is stable across runs regardless of cost or
  row-count variance. This is what lets `mix excessibility.digest.compare` flag a
  plan change under stable SQL.

  Tolerant by construction: it accepts both the raw list-wrapped Postgres form
  (`[%{"Plan" => ...}]`) and an already-unwrapped `%{"Plan" => ...}` map, and
  returns `nil` on anything unparseable rather than raising.
  """

  @doc """
  Turn a decoded `EXPLAIN (FORMAT JSON)` result into a value-free plan summary.

  Returns `nil` for any input that does not contain a parseable `"Plan"` root.
  """
  @spec summarize(term()) :: map() | nil
  def summarize([%{"Plan" => plan} | _]) when is_map(plan), do: summarize_plan(plan)
  def summarize(%{"Plan" => plan}) when is_map(plan), do: summarize_plan(plan)
  def summarize(_), do: nil

  # Upper bound on every emitted structural array (`nodes` and `node_rows`, which
  # share the same depth-first node sequence). Real EXPLAIN trees are far smaller;
  # the cap is a safety valve so a pathological plan cannot bloat the digest.
  # Truncation is deterministic (first N in depth-first order) and the number of
  # dropped nodes is surfaced as `nodes_omitted` so truncation is never silent
  # (issue #167). The structural fingerprint always hashes the *full* tree, so a
  # truncated summary still groups and compares stably.
  @max_nodes 100

  @doc """
  Aggregate the plan summaries of every occurrence of one query fingerprint into
  a single, bounded, value-free summary.

  A query fingerprint can fire many times in one journey; each occurrence carries
  its own plan summary, and a *later* occurrence can do far more row work than the
  first (issue #167). Selecting only the first occurrence's plan discards that
  magnitude before comparison ever runs, so aggregation keeps the **maximum**
  comparable row work per structural node path: estimated/actual rows, loops and
  `rows_touched` are maxed position-by-position across occurrences that share a
  plan structural fingerprint. `max/2` is commutative, so the result is
  independent of occurrence order.

  When occurrences carry different plan *structures* (e.g. the planner flipped to
  a different plan), they are grouped by structural fingerprint, each group is
  aggregated, and the group doing the most total row work is chosen as the
  deterministic representative (ties broken by fingerprint). Returns `nil` for an
  empty list and the sole summary unchanged for a single (or all-identical)
  occurrence.
  """
  @spec aggregate([map()]) :: map() | nil
  def aggregate([]), do: nil
  def aggregate([summary]), do: summary

  def aggregate(summaries) when is_list(summaries) do
    case Enum.uniq(summaries) do
      [only] -> only
      _ -> do_aggregate(summaries)
    end
  rescue
    # Aggregation must never break digest emission; fall back to the first plan.
    _ -> List.first(summaries)
  end

  defp do_aggregate(summaries) do
    summaries
    |> Enum.group_by(&Map.get(&1, :fingerprint))
    |> Enum.map(fn {_fp, group} ->
      Enum.reduce(group, fn summary, acc -> merge_summary(acc, summary) end)
    end)
    |> Enum.max_by(&{total_rows_touched(&1), to_string(Map.get(&1, :fingerprint))})
  end

  # Merge two summaries sharing a structural fingerprint by keeping the max
  # comparable row work per field and per structural node position. All other
  # (structural) fields are identical, so `a` is kept for them.
  defp merge_summary(a, b) do
    Map.merge(a, %{
      mode: merge_mode(Map.get(a, :mode), Map.get(b, :mode)),
      estimated_rows: max_num(Map.get(a, :estimated_rows), Map.get(b, :estimated_rows)),
      actual_rows: max_num(Map.get(a, :actual_rows), Map.get(b, :actual_rows)),
      loops: max_num(Map.get(a, :loops), Map.get(b, :loops)),
      estimate_error: max_num(Map.get(a, :estimate_error), Map.get(b, :estimate_error)),
      node_rows: merge_node_rows(Map.get(a, :node_rows, []), Map.get(b, :node_rows, [])),
      nodes_omitted: max(Map.get(a, :nodes_omitted, 0), Map.get(b, :nodes_omitted, 0))
    })
  end

  # Same structural fingerprint ⇒ identical depth-first node sequence and length,
  # so zipping by position is a stable node identity.
  defp merge_node_rows(as, bs), do: Enum.zip_with(as, bs, &merge_node/2)

  defp merge_node(a, b) do
    Map.merge(a, %{
      estimated_rows: max_num(Map.get(a, :estimated_rows), Map.get(b, :estimated_rows)),
      actual_rows: max_num(Map.get(a, :actual_rows), Map.get(b, :actual_rows)),
      loops: max_num(Map.get(a, :loops), Map.get(b, :loops)),
      rows_touched: max_num(Map.get(a, :rows_touched), Map.get(b, :rows_touched)),
      estimate_error: max_num(Map.get(a, :estimate_error), Map.get(b, :estimate_error))
    })
  end

  defp merge_mode(a, b), do: if(analyze_mode?(a) or analyze_mode?(b), do: :explain_analyze, else: :explain)
  defp analyze_mode?(mode), do: mode in [:explain_analyze, "explain_analyze"]

  # Total comparable row work, used only to pick a deterministic representative
  # when occurrences carry different plan structures. Falls back to estimated
  # rows for plain EXPLAIN (no actuals), so representative selection is stable.
  defp total_rows_touched(summary) do
    summary
    |> Map.get(:node_rows, [])
    |> Enum.reduce(0, fn node, acc ->
      acc + (num(Map.get(node, :rows_touched)) || num(Map.get(node, :estimated_rows)) || 0)
    end)
  end

  defp num(n) when is_number(n), do: n
  defp num(_), do: nil

  defp max_num(a, b) do
    cond do
      is_number(a) and is_number(b) -> max(a, b)
      is_number(a) -> a
      is_number(b) -> b
      true -> nil
    end
  end

  defp summarize_plan(plan) do
    tree = walk(plan)
    total = length(tree)
    nodes = tree |> Enum.take(@max_nodes) |> Enum.map(&node_label/1)

    # `relations` is bounded by the same @max_nodes contract as `nodes`: a
    # pathological or partition-heavy plan can carry many distinct relations, so
    # the sorted unique set is capped and the drop count surfaced as
    # `relations_omitted` — no unbounded structural array without visible
    # omission metadata (issue #174).
    all_relations = tree |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
    relations = Enum.take(all_relations, @max_nodes)

    estimated = plan["Plan Rows"]
    actual = plan["Actual Rows"]

    %{
      mode: if(analyze?(plan), do: :explain_analyze, else: :explain),
      fingerprint: fingerprint(tree),
      nodes: nodes,
      nodes_omitted: max(total - @max_nodes, 0),
      relations: relations,
      relations_omitted: max(length(all_relations) - @max_nodes, 0),
      estimated_rows: estimated,
      actual_rows: actual,
      loops: plan["Actual Loops"],
      estimate_error: estimate_error(estimated, actual),
      node_rows: node_rows(plan)
    }
  rescue
    _ -> nil
  end

  # Bounded, deterministic, value-free per-node numeric evidence in depth-first
  # order. Estimated rows are always kept (plain EXPLAIN); actual rows, loops
  # and rows_touched are only present when the node carries ANALYZE data. This
  # is what preserves a large child scan beneath a one-row root — a magnitude
  # the structural fingerprint alone discards (issue #157). Bounded by the same
  # @max_nodes / `nodes_omitted` contract as the `nodes` label list.
  defp node_rows(plan) do
    plan
    |> walk_node_rows(0)
    |> Enum.take(@max_nodes)
  end

  defp walk_node_rows(%{"Node Type" => type} = node, depth) do
    estimated = node["Plan Rows"]
    actual = node["Actual Rows"]
    loops = node["Actual Loops"]

    entry = %{
      node: type,
      relation: node["Relation Name"],
      depth: depth,
      estimated_rows: estimated,
      actual_rows: actual,
      loops: loops,
      rows_touched: rows_touched(actual, loops),
      estimate_error: estimate_error(estimated, actual)
    }

    children =
      node |> Map.get("Plans", []) |> List.wrap() |> Enum.flat_map(&walk_node_rows(&1, depth + 1))

    [entry | children]
  end

  defp walk_node_rows(_, _), do: []

  # A node executed inside a loop touches `Actual Rows` (Postgres reports the
  # per-loop average) once per loop, so total work is rows × loops. Without
  # ANALYZE there are no actuals, so rows_touched is unmeasured (nil).
  defp rows_touched(actual, loops) when is_number(actual) and is_number(loops), do: round(actual * loops)

  defp rows_touched(actual, nil) when is_number(actual), do: actual
  defp rows_touched(_, _), do: nil

  # Depth-first walk collecting {node_type, relation_name} tuples in traversal order.
  defp walk(%{"Node Type" => type} = plan) do
    relation = plan["Relation Name"]
    children = plan |> Map.get("Plans", []) |> List.wrap() |> Enum.flat_map(&walk/1)
    [{type, relation} | children]
  end

  defp walk(_), do: []

  defp node_label({type, nil}), do: type
  defp node_label({type, relation}), do: "#{type} on #{relation}"

  # Any node carrying actual-row data means this was EXPLAIN ANALYZE.
  defp analyze?(plan) do
    plan
    |> walk_maps()
    |> Enum.any?(&Map.has_key?(&1, "Actual Rows"))
  end

  defp walk_maps(%{} = plan) do
    children = plan |> Map.get("Plans", []) |> List.wrap() |> Enum.flat_map(&walk_maps/1)
    [plan | children]
  end

  defp walk_maps(_), do: []

  defp estimate_error(estimated, actual) when is_number(estimated) and is_number(actual) do
    abs(actual - estimated) / max(estimated, 1)
  end

  defp estimate_error(_, _), do: nil

  # Hash the structural tree only (node type + relation, in traversal order),
  # matching the "sha256:<16hex>" shape used by Excessibility.SQLFingerprint.
  defp fingerprint(tree) do
    structural =
      Enum.map_join(tree, "\n", fn {type, relation} -> "#{type}|#{relation}" end)

    hash =
      :sha256
      |> :crypto.hash(structural)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "sha256:" <> hash
  end
end
