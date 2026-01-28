defmodule Excessibility.TelemetryCapture.Enrichers.ComponentTreeTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.ComponentTree

  describe "name/0" do
    test "returns :component_tree" do
      assert ComponentTree.name() == :component_tree
    end
  end

  describe "enrich/2" do
    test "returns zero values when no components present" do
      assigns = %{user: "test", count: 5}
      result = ComponentTree.enrich(assigns, [])

      assert result == %{
               component_count: 0,
               component_ids: [],
               stateful_components: 0,
               component_depth: 0
             }
    end

    test "detects CID in assigns (myself pattern)" do
      # Phoenix.LiveComponent.CID is the struct type for component IDs
      cid = %Phoenix.LiveComponent.CID{cid: 1}
      assigns = %{myself: cid, items: []}
      result = ComponentTree.enrich(assigns, [])

      assert result.component_count == 1
      assert 1 in result.component_ids
      assert result.stateful_components == 1
    end

    test "detects multiple CIDs" do
      cid1 = %Phoenix.LiveComponent.CID{cid: 1}
      cid2 = %Phoenix.LiveComponent.CID{cid: 2}
      assigns = %{component_a: cid1, component_b: cid2}
      result = ComponentTree.enrich(assigns, [])

      assert result.component_count == 2
      assert 1 in result.component_ids
      assert 2 in result.component_ids
    end

    test "finds CIDs nested in maps" do
      cid = %Phoenix.LiveComponent.CID{cid: 42}

      assigns = %{
        user: %{
          profile: %{
            component: cid
          }
        }
      }

      result = ComponentTree.enrich(assigns, [])

      assert result.component_count == 1
      assert 42 in result.component_ids
      assert result.component_depth == 3
    end

    test "finds CIDs in lists" do
      cids = [
        %Phoenix.LiveComponent.CID{cid: 1},
        %Phoenix.LiveComponent.CID{cid: 2},
        %Phoenix.LiveComponent.CID{cid: 3}
      ]

      assigns = %{components: cids}
      result = ComponentTree.enrich(assigns, [])

      assert result.component_count == 3
      assert result.component_ids == [1, 2, 3]
    end

    test "calculates component depth" do
      cid = %Phoenix.LiveComponent.CID{cid: 1}

      assigns = %{
        level1: %{
          level2: %{
            level3: cid
          }
        }
      }

      result = ComponentTree.enrich(assigns, [])

      assert result.component_depth == 3
    end

    test "handles deeply nested structures" do
      cid = %Phoenix.LiveComponent.CID{cid: 99}

      assigns = %{
        a: %{
          b: [
            %{c: %{d: cid}}
          ]
        }
      }

      result = ComponentTree.enrich(assigns, [])

      assert result.component_count == 1
      assert 99 in result.component_ids
    end

    test "ignores other structs" do
      assigns = %{
        date: ~D[2024-01-01],
        time: ~T[12:00:00],
        name: "test"
      }

      result = ComponentTree.enrich(assigns, [])

      assert result.component_count == 0
      assert result.component_ids == []
    end
  end
end
