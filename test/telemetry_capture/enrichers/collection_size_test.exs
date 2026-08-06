defmodule Excessibility.TelemetryCapture.Enrichers.CollectionSizeTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.CollectionSize

  describe "name/0" do
    test "returns :collection_size" do
      assert CollectionSize.name() == :collection_size
    end
  end

  describe "enrich/2" do
    test "returns map with collection size fields" do
      assigns = %{products: [1, 2, 3]}

      result = CollectionSize.enrich(assigns, [])

      assert is_map(result)
      assert Map.has_key?(result, :list_sizes)
      assert Map.has_key?(result, :max_list_size)
      assert Map.has_key?(result, :total_list_items)
    end

    test "stops at opaque library structs instead of counting their internals (issue #142)" do
      # A Phoenix form's changeset carries Ecto machinery (types, mappings,
      # validations) and schema timestamps carry microsecond tuples — none of
      # which is actionable app state. The traversal must treat these as leaves.
      changeset = %Ecto.Changeset{
        data: %{},
        changes: %{items: [%{id: 1}]},
        types: %{name: :string, code: {:parameterized, :enum, %{mappings: [a: 1, b: 2]}}},
        valid?: true
      }

      assigns = %{
        order_form: %{source: changeset},
        created_at: ~U[2024-01-01 12:00:00.123456Z],
        products: [1, 2, 3]
      }

      result = CollectionSize.enrich(assigns, [])

      keys = Enum.map(Map.keys(result.list_sizes), &to_string/1)

      # Without a stop, the changeset's own list fields (constraints, errors,
      # empty_values, changes.items) all leak in as `order_form.source.*`.
      refute Enum.any?(keys, &(&1 =~ "source")),
             "expected no changeset internals in list_sizes, got: #{inspect(keys)}"

      # Real app lists are still tracked.
      assert result.list_sizes[:products] == 3
    end

    test "counts lists at top level" do
      assigns = %{
        products: [1, 2, 3],
        users: [1, 2],
        tags: [1, 2, 3, 4, 5]
      }

      result = CollectionSize.enrich(assigns, [])

      assert result.list_sizes == %{
               products: 3,
               users: 2,
               tags: 5
             }

      assert result.max_list_size == 5
      assert result.total_list_items == 10
    end

    test "counts lists in nested structures" do
      assigns = %{
        user: %{
          posts: [1, 2, 3],
          comments: [1, 2]
        }
      }

      result = CollectionSize.enrich(assigns, [])

      assert result.list_sizes == %{
               "user.posts": 3,
               "user.comments": 2
             }

      assert result.max_list_size == 3
      assert result.total_list_items == 5
    end

    test "handles deeply nested lists" do
      assigns = %{
        data: %{
          level1: %{
            level2: %{
              items: [1, 2, 3, 4]
            }
          }
        }
      }

      result = CollectionSize.enrich(assigns, [])

      assert result.list_sizes == %{"data.level1.level2.items": 4}
      assert result.max_list_size == 4
      assert result.total_list_items == 4
    end

    test "handles lists within lists" do
      assigns = %{
        matrix: [
          [1, 2],
          [3, 4, 5]
        ]
      }

      result = CollectionSize.enrich(assigns, [])

      # Should count the outer list and nested lists
      assert result.list_sizes[:matrix] == 2
      assert Map.has_key?(result.list_sizes, :"matrix[0]")
      assert result.list_sizes[:"matrix[0]"] == 2
      assert result.list_sizes[:"matrix[1]"] == 3
      assert result.max_list_size == 3
    end

    test "handles empty lists" do
      assigns = %{
        products: [],
        users: [1, 2]
      }

      result = CollectionSize.enrich(assigns, [])

      assert result.list_sizes == %{
               products: 0,
               users: 2
             }

      assert result.max_list_size == 2
      assert result.total_list_items == 2
    end

    test "handles empty assigns" do
      result = CollectionSize.enrich(%{}, [])

      assert result.list_sizes == %{}
      assert result.max_list_size == 0
      assert result.total_list_items == 0
    end

    test "ignores non-list values" do
      assigns = %{
        name: "Alice",
        count: 5,
        products: [1, 2, 3]
      }

      result = CollectionSize.enrich(assigns, [])

      assert result.list_sizes == %{products: 3}
      assert result.max_list_size == 3
      assert result.total_list_items == 3
    end

    test "handles structs with lists" do
      assigns = %{
        user: %{
          __struct__: User,
          id: 1,
          posts: [1, 2, 3]
        }
      }

      result = CollectionSize.enrich(assigns, [])

      assert result.list_sizes == %{"user.posts": 3}
      assert result.max_list_size == 3
    end

    test "uses atom keys for paths" do
      assigns = %{
        cart: %{
          items: [1, 2]
        }
      }

      result = CollectionSize.enrich(assigns, [])

      # Keys should be atoms for efficiency
      assert is_atom(:"cart.items")
      assert Map.has_key?(result.list_sizes, :"cart.items")
    end
  end
end
