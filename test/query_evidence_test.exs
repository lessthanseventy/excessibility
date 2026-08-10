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
end
