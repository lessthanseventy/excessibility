defmodule Excessibility.TelemetryCapture.FilterTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Filter

  describe "filter_ecto_metadata/1" do
    test "removes __meta__ fields from maps" do
      assigns = %{
        user: %{
          id: 123,
          name: "John",
          __meta__: %Ecto.Schema.Metadata{state: :loaded}
        },
        count: 5
      }

      result = Filter.filter_ecto_metadata(assigns)

      assert result.user == %{id: 123, name: "John"}
      assert result.count == 5
      refute Map.has_key?(result.user, :__meta__)
    end

    test "removes NotLoaded associations" do
      assigns = %{
        user: %{
          id: 123,
          posts: %Ecto.Association.NotLoaded{
            __field__: :posts,
            __owner__: User
          }
        }
      }

      result = Filter.filter_ecto_metadata(assigns)

      refute Map.has_key?(result.user, :posts)
    end

    test "handles nested structures" do
      assigns = %{
        users: [
          %{id: 1, __meta__: "remove"},
          %{id: 2, __meta__: "remove"}
        ]
      }

      result = Filter.filter_ecto_metadata(assigns)

      assert length(result.users) == 2
      refute Map.has_key?(Enum.at(result.users, 0), :__meta__)
      refute Map.has_key?(Enum.at(result.users, 1), :__meta__)
    end

    test "preserves non-Ecto data unchanged" do
      assigns = %{
        simple: "value",
        number: 42,
        list: [1, 2, 3],
        nested: %{a: 1, b: 2}
      }

      result = Filter.filter_ecto_metadata(assigns)

      assert result == assigns
    end
  end
end
