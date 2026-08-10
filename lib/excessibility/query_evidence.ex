defmodule Excessibility.QueryEvidence do
  @moduledoc """
  Fingerprint-based query grouping shared by the `ecto_query_analysis` analyzer
  (which wraps it in severity) and `Excessibility.Digest` (which emits it raw).
  Tolerates string values from reloaded `timeline.json` (issue #151).
  """

  @default_min_repetitions 3

  def shapes(queries) do
    queries
    |> Enum.with_index(1)
    |> Enum.group_by(fn {q, _i} -> fingerprint_of(q) end)
    |> Enum.map(fn {fp, pairs} ->
      {first, _} = hd(pairs)

      put_aggregated_plan(
        %{
          fingerprint: fp,
          operation: to_string(first.operation),
          source: to_string(first.source),
          normalized: Map.get(first, :normalized, ""),
          count: length(pairs),
          sequences: Enum.map(pairs, fn {_q, i} -> i end)
        },
        pairs
      )
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def repeated(queries, opts \\ []) do
    min = Keyword.get(opts, :min_repetitions, @default_min_repetitions)
    total = max(length(queries), 1)

    queries
    |> Enum.filter(&select?/1)
    |> Enum.group_by(&fingerprint_of/1)
    |> Enum.filter(fn {_fp, group} -> length(group) >= min end)
    |> Enum.map(fn {fp, group} ->
      first = hd(group)

      %{
        fingerprint: fp,
        source: to_string(first.source),
        operation: to_string(first.operation),
        repetitions: length(group),
        share: length(group) / total,
        cardinality: nil,
        severity: :advisory
      }
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def select?(%{operation: op}), do: to_string(op) == "select"
  def select?(_), do: false

  # A query fingerprint can fire many times, and a *later* occurrence can do far
  # more row work than the first, so aggregate the plan across **every**
  # occurrence rather than trusting the first (issue #167). Aggregation keeps the
  # max comparable row work per structural node path and is order-independent.
  # Only attach `:plan` when at least one occurrence carried a non-nil plan — the
  # common no-plan case keeps a clean shape with no `:plan` key at all.
  defp put_aggregated_plan(shape, pairs) do
    plans = pairs |> Enum.map(fn {q, _i} -> Map.get(q, :plan) end) |> Enum.reject(&is_nil/1)

    case Excessibility.QueryPlan.aggregate(plans) do
      nil -> shape
      plan -> Map.put(shape, :plan, plan)
    end
  end

  # Reloaded pre-feature `timeline.json` records lack a `:fingerprint` key but
  # still carry the raw `:query` (or `:source`), so recompute a stable
  # fingerprint on the fly to keep distinct old queries distinct (issue #154).
  defp fingerprint_of(q) do
    Map.get(q, :fingerprint) ||
      Excessibility.SQLFingerprint.fingerprint(Map.get(q, :query, Map.get(q, :source, "")))
  end
end
