defmodule Excessibility.TelemetryCapture.Enrichers.QueryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.Query

  describe "name/0" do
    test "returns :query" do
      assert Query.name() == :query
    end
  end

  describe "enrich/2" do
    test "returns map with query counts" do
      assigns = %{
        users: [
          %{__struct__: User, id: 1, name: "Alice"},
          %{__struct__: User, id: 2, name: "Bob"}
        ]
      }

      result = Query.enrich(assigns, [])

      assert is_map(result)
      assert Map.has_key?(result, :query_records_loaded)
      assert Map.has_key?(result, :query_not_loaded_count)
    end

    test "counts Ecto records" do
      assigns = %{
        users: [
          %{__struct__: User, id: 1},
          %{__struct__: User, id: 2}
        ],
        products: [
          %{__struct__: Product, id: 1}
        ]
      }

      result = Query.enrich(assigns, [])
      assert result.query_records_loaded == 3
    end

    test "counts NotLoaded associations" do
      assigns = %{
        user: %{
          __struct__: User,
          id: 1,
          posts: %Ecto.Association.NotLoaded{},
          comments: %Ecto.Association.NotLoaded{}
        }
      }

      result = Query.enrich(assigns, [])
      assert result.query_not_loaded_count == 2
    end

    test "handles nested structures" do
      assigns = %{
        user: %{
          __struct__: User,
          id: 1,
          profile: %{
            __struct__: Profile,
            id: 1,
            avatar: %Ecto.Association.NotLoaded{}
          }
        }
      }

      result = Query.enrich(assigns, [])
      assert result.query_records_loaded == 2
      assert result.query_not_loaded_count == 1
    end

    test "handles empty assigns" do
      result = Query.enrich(%{}, [])
      assert result.query_records_loaded == 0
      assert result.query_not_loaded_count == 0
    end

    test "ignores non-Ecto values" do
      assigns = %{
        name: "test",
        count: 5,
        items: [1, 2, 3]
      }

      result = Query.enrich(assigns, [])
      assert result.query_records_loaded == 0
      assert result.query_not_loaded_count == 0
    end
  end
end
