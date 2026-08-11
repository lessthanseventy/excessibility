defmodule Excessibility.QueryEvidence do
  @moduledoc """
  Fingerprint-based query grouping shared by the `ecto_query_analysis` analyzer
  (which wraps it in severity) and `Excessibility.Digest` (which emits it raw).
  Tolerates string values from reloaded `timeline.json` (issue #151).
  """

  @default_min_repetitions 3

  # Upper bound on the number of distinct structural plan variants kept per query
  # fingerprint. A parameterized query can pick different plans by selectivity, so
  # one SQL fingerprint legitimately carries several structures; the cap keeps the
  # public digest bounded while `variants_omitted` records any truncation (#173).
  @max_plan_variants 8

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

  # A query fingerprint can fire many times, and occurrences can differ two ways:
  # a *later* occurrence of one structure can do more row work than the first
  # (issue #167), and a parameterized query can pick a *different* structure by
  # selectivity (issue #173). So we keep the bounded **set** of distinct plan
  # variants — the heaviest instance of each structure — rather than one
  # representative. `:plans`/`:variants_omitted` are attached only when at least
  # one occurrence carried a plan; the common no-plan case keeps a clean shape.
  defp put_aggregated_plan(shape, pairs) do
    plans = pairs |> Enum.map(fn {q, _i} -> Map.get(q, :plan) end) |> Enum.reject(&is_nil/1)

    case Excessibility.QueryPlan.aggregate_variants(plans) do
      [] ->
        shape

      variants ->
        shape
        |> Map.put(:plans, Enum.take(variants, @max_plan_variants))
        |> Map.put(:variants_omitted, max(length(variants) - @max_plan_variants, 0))
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
