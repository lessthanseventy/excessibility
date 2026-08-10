defmodule Excessibility.QueryPlanTest do
  use ExUnit.Case, async: true

  alias Excessibility.QueryPlan

  # Postgres EXPLAIN (FORMAT JSON) returns a one-element array whose object has a "Plan" key.
  defp nested_plan(top_extra \\ %{}, leaf_extra \\ %{}) do
    [
      %{
        "Plan" =>
          Map.merge(
            %{
              "Node Type" => "Nested Loop",
              "Plan Rows" => 100,
              "Plans" => [
                %{"Node Type" => "Seq Scan", "Relation Name" => "categories", "Plan Rows" => 10},
                Map.merge(
                  %{"Node Type" => "Index Scan", "Relation Name" => "products", "Plan Rows" => 1},
                  leaf_extra
                )
              ]
            },
            top_extra
          )
      }
    ]
  end

  describe "summarize/1 structure" do
    test "collects nodes, relations, estimated rows from the nested example" do
      s = QueryPlan.summarize(nested_plan())

      assert s.nodes == [
               "Nested Loop",
               "Seq Scan on categories",
               "Index Scan on products"
             ]

      assert s.relations == ["categories", "products"]
      assert s.estimated_rows == 100
    end

    test "mode is :explain when no actual rows present" do
      s = QueryPlan.summarize(nested_plan())
      assert s.mode == :explain
      assert s.actual_rows == nil
      assert s.loops == nil
      assert s.estimate_error == nil
    end

    test "mode is :explain_analyze and populates actual data when actual rows present" do
      s =
        QueryPlan.summarize(
          nested_plan(
            %{"Actual Rows" => 80, "Actual Loops" => 1},
            %{"Actual Rows" => 3, "Actual Loops" => 10}
          )
        )

      assert s.mode == :explain_analyze
      assert s.actual_rows == 80
      assert s.loops == 1
      # |80 - 100| / max(100,1) = 0.2
      assert_in_delta s.estimate_error, 0.2, 0.0001
    end
  end

  describe "fingerprint" do
    test "is stable across differing row estimates and costs" do
      a = QueryPlan.summarize(nested_plan(%{"Plan Rows" => 100, "Total Cost" => 5.0}))
      b = QueryPlan.summarize(nested_plan(%{"Plan Rows" => 999_999, "Total Cost" => 9_999.9}))

      assert a.fingerprint =~ ~r/^sha256:[0-9a-f]{16}$/
      assert a.fingerprint == b.fingerprint
    end

    test "differs for different node structures" do
      other =
        QueryPlan.summarize([
          %{
            "Plan" => %{
              "Node Type" => "Hash Join",
              "Plan Rows" => 100,
              "Plans" => [
                %{"Node Type" => "Seq Scan", "Relation Name" => "categories", "Plan Rows" => 10}
              ]
            }
          }
        ])

      assert QueryPlan.summarize(nested_plan()).fingerprint != other.fingerprint
    end
  end

  describe "tolerance" do
    test "accepts a bare %{\"Plan\" => ...} map without the list wrapper" do
      [%{"Plan" => plan}] = nested_plan()
      s = QueryPlan.summarize(%{"Plan" => plan})
      assert s.estimated_rows == 100
      assert s.relations == ["categories", "products"]
    end

    test "returns nil for unparseable input without raising" do
      assert QueryPlan.summarize(nil) == nil
      assert QueryPlan.summarize(%{}) == nil
      assert QueryPlan.summarize("garbage") == nil
      assert QueryPlan.summarize([]) == nil
      assert QueryPlan.summarize([%{}]) == nil
    end
  end

  # A root that returns one row but scans thousands beneath it — the primary
  # reason to capture plans rather than trust the query count (issue #157).
  defp small_root_big_child(child_extra \\ %{}) do
    [
      %{
        "Plan" => %{
          "Node Type" => "Nested Loop",
          "Plan Rows" => 1,
          "Plans" => [
            %{"Node Type" => "Index Scan", "Relation Name" => "parents", "Plan Rows" => 1},
            Map.merge(
              %{"Node Type" => "Seq Scan", "Relation Name" => "children", "Plan Rows" => 50},
              child_extra
            )
          ]
        }
      }
    ]
  end

  describe "node_rows (child-node evidence)" do
    test "preserves child estimated rows for plain EXPLAIN" do
      s = QueryPlan.summarize(small_root_big_child())

      child = Enum.find(s.node_rows, &(&1.relation == "children"))
      assert child.node == "Seq Scan"
      assert child.depth == 1
      assert child.estimated_rows == 50
      # No ANALYZE data present, so actual/loops/rows_touched stay nil.
      assert child.actual_rows == nil
      assert child.loops == nil
      assert child.rows_touched == nil
      assert child.estimate_error == nil
    end

    test "preserves child actual rows, loops and rows_touched only under ANALYZE" do
      s =
        QueryPlan.summarize(small_root_big_child(%{"Actual Rows" => 10_000, "Actual Loops" => 1}))

      child = Enum.find(s.node_rows, &(&1.relation == "children"))
      assert child.estimated_rows == 50
      assert child.actual_rows == 10_000
      assert child.loops == 1
      assert child.rows_touched == 10_000
      # |10000 - 50| / max(50, 1) = 199.0
      assert_in_delta child.estimate_error, 199.0, 0.0001
    end

    test "rows_touched multiplies actual rows by loop count" do
      s =
        QueryPlan.summarize(small_root_big_child(%{"Actual Rows" => 3, "Actual Loops" => 100}))

      child = Enum.find(s.node_rows, &(&1.relation == "children"))
      assert child.rows_touched == 300
    end

    test "node_rows is a bounded, deterministic, value-free DFS list" do
      s = QueryPlan.summarize(small_root_big_child())

      assert Enum.map(s.node_rows, & &1.node) == ["Nested Loop", "Index Scan", "Seq Scan"]
      assert Enum.map(s.node_rows, & &1.depth) == [0, 1, 1]

      # Only allowlisted, value-free keys per node.
      for node <- s.node_rows do
        assert node |> Map.keys() |> Enum.sort() ==
                 [
                   :actual_rows,
                   :depth,
                   :estimate_error,
                   :estimated_rows,
                   :loops,
                   :node,
                   :relation,
                   :rows_touched
                 ]
      end
    end
  end

  describe "value-free" do
    test "summary exposes only the allowlisted keys" do
      s = QueryPlan.summarize(nested_plan())

      assert s |> Map.keys() |> Enum.sort() ==
               [
                 :actual_rows,
                 :estimate_error,
                 :estimated_rows,
                 :fingerprint,
                 :loops,
                 :mode,
                 :node_rows,
                 :nodes,
                 :relations
               ]
    end

    test "encodes to json cleanly" do
      json = Jason.encode!(QueryPlan.summarize(nested_plan()))
      assert json =~ "Nested Loop"
      assert json =~ "categories"
    end
  end
end
