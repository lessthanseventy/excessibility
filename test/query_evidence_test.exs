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

  test "shapes/1 attaches the representative's plan when present" do
    plan = %{fingerprint: "sha256:plan", nodes: ["Seq Scan"], relations: ["categories"]}

    with_plan = fn -> Map.put(q(:select, "categories", "sha256:aaa"), :plan, plan) end

    [shape] = QueryEvidence.shapes([with_plan.(), with_plan.()])
    assert shape.plan == plan
  end

  test "shapes/1 omits the :plan key entirely when the representative has no plan" do
    [shape] = QueryEvidence.shapes([q(:select, "categories", "sha256:aaa")])
    refute Map.has_key?(shape, :plan)
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
