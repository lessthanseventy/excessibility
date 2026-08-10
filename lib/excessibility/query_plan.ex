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

  defp summarize_plan(plan) do
    tree = walk(plan)
    nodes = Enum.map(tree, &node_label/1)
    relations = tree |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

    estimated = plan["Plan Rows"]
    actual = plan["Actual Rows"]

    %{
      mode: if(analyze?(plan), do: :explain_analyze, else: :explain),
      fingerprint: fingerprint(tree),
      nodes: nodes,
      relations: relations,
      estimated_rows: estimated,
      actual_rows: actual,
      loops: plan["Actual Loops"],
      estimate_error: estimate_error(estimated, actual)
    }
  rescue
    _ -> nil
  end

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
