defmodule Excessibility.QueryEvidenceTest do
  use ExUnit.Case, async: true

  alias Excessibility.QueryEvidence

  defp q(op, source, fp), do: %{operation: op, source: source, fingerprint: fp, normalized: "n"}

  test "shapes/1 groups by fingerprint with complete counts, no truncation" do
    queries = [
      q(:select, "categories", "sha256:aaa"),
      q(:select, "categories", "sha256:aaa"),
      q(:select, "products", "sha256:bbb")
    ]

    shapes = QueryEvidence.shapes(queries)
    assert length(shapes) == 2
    aaa = Enum.find(shapes, &(&1.fingerprint == "sha256:aaa"))
    assert aaa.count == 2
    assert aaa.source == "categories"
  end

  test "repeated/2 flags fingerprints at/over min_repetitions with share" do
    queries =
      List.duplicate(q(:select, "categories", "sha256:aaa"), 10) ++
        [q(:select, "products", "sha256:bbb"), q(:insert, "orders", "sha256:ccc")]

    [rep] = QueryEvidence.repeated(queries, min_repetitions: 3)
    assert rep.fingerprint == "sha256:aaa"
    assert rep.repetitions == 10
    assert_in_delta rep.share, 10 / 12, 0.001
    assert rep.severity == :advisory
  end

  test "select?/1 tolerates string operations from reloaded json (issue #151)" do
    assert QueryEvidence.select?(%{operation: "select"})
    assert QueryEvidence.select?(%{operation: :select})
  end

  test "shapes/1 attaches the plan variant set when present" do
    plan = %{fingerprint: "sha256:plan", nodes: ["Seq Scan"], relations: ["categories"]}

    with_plan = fn -> Map.put(q(:select, "categories", "sha256:aaa"), :plan, plan) end

    [shape] = QueryEvidence.shapes([with_plan.(), with_plan.()])
    assert shape.plans == [plan]
    assert shape.variants_omitted == 0
    refute Map.has_key?(shape, :plan)
  end

  test "shapes/1 preserves every distinct structural plan variant under one fingerprint (#173)" do
    heavy = %{fingerprint: "sha256:A", nodes: ["Seq Scan"], relations: ["a"], node_rows: []}
    light = %{fingerprint: "sha256:B", nodes: ["Index Scan"], relations: ["b"], node_rows: []}

    # Same SQL fingerprint, two DISTINCT plan structures across the journey.
    [shape] =
      QueryEvidence.shapes([
        Map.put(q(:select, "t", "sha256:aaa"), :plan, heavy),
        Map.put(q(:select, "t", "sha256:aaa"), :plan, light)
      ])

    assert Enum.map(shape.plans, & &1.fingerprint) == ["sha256:A", "sha256:B"]
    assert shape.variants_omitted == 0
  end

  test "shapes/1 bounds the variant set and reports variants_omitted" do
    variants =
      for i <- 0..19 do
        plan = %{fingerprint: "sha256:v#{String.pad_leading(Integer.to_string(i), 2, "0")}", node_rows: []}
        Map.put(q(:select, "t", "sha256:aaa"), :plan, plan)
      end

    [shape] = QueryEvidence.shapes(variants)

    assert length(shape.plans) == 8
    assert shape.variants_omitted == 12
  end

  test "shapes/1 omits the :plans key entirely when no occurrence has a plan" do
    [shape] = QueryEvidence.shapes([q(:select, "categories", "sha256:aaa")])
    refute Map.has_key?(shape, :plans)
    refute Map.has_key?(shape, :variants_omitted)
  end

  test "shapes/1 aggregates plan row work across every occurrence, not just the first (#167)" do
    node = fn touched ->
      %{
        node: "Seq Scan",
        relation: "children",
        depth: 0,
        estimated_rows: 1,
        actual_rows: touched,
        loops: 1,
        rows_touched: touched,
        estimate_error: 0.0
      }
    end

    plan = fn touched ->
      %{fingerprint: "sha256:plan", nodes: ["Seq Scan"], relations: ["children"], node_rows: [node.(touched)]}
    end

    # First occurrence is cheap (rows_touched = 1); a later occurrence of the
    # SAME fingerprint scans 10_000. The emitted shape must carry the max.
    first = Map.put(q(:select, "children", "sha256:aaa"), :plan, plan.(1))
    later = Map.put(q(:select, "children", "sha256:aaa"), :plan, plan.(10_000))

    [shape] = QueryEvidence.shapes([first, later])

    assert shape.count == 2
    assert [variant] = shape.plans
    assert [child] = variant.node_rows
    assert child.rows_touched == 10_000
  end

  test "tolerates query maps missing :fingerprint (reloaded pre-feature timeline)" do
    # old-shape records: raw :query, string operation, NO :fingerprint key
    old = fn q -> %{operation: "select", source: "categories", query: q} end

    queries = [
      old.("SELECT * FROM categories WHERE id = $1"),
      old.("SELECT * FROM categories WHERE id = $1"),
      old.("SELECT * FROM categories WHERE id = $1")
    ]

    [rep] = QueryEvidence.repeated(queries, min_repetitions: 3)
    assert rep.repetitions == 3
    assert rep.fingerprint =~ ~r/^sha256:/
    # distinct old queries do NOT collapse together:
    mixed = [
      old.("SELECT * FROM a WHERE id = $1"),
      old.("SELECT * FROM b WHERE id = $1"),
      old.("SELECT * FROM a WHERE id = $1")
    ]

    # only 'a' repeats twice
    assert mixed |> QueryEvidence.repeated(min_repetitions: 2) |> length() == 1
    # two distinct shapes
    assert length(QueryEvidence.shapes(mixed)) == 2
  end
end
