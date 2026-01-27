defmodule Excessibility.TelemetryCapture.Enrichers.StateTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.State

  describe "name/0" do
    test "returns :state" do
      assert State.name() == :state
    end
  end

  describe "enrich/2" do
    test "returns map with state metadata" do
      assigns = %{user_id: 123, products: []}

      result = State.enrich(assigns, [])

      assert is_map(result)
      assert Map.has_key?(result, :state_keys)
      assert Map.has_key?(result, :state_key_count)
      assert Map.has_key?(result, :state_max_depth)
    end

    test "tracks assign keys" do
      assigns = %{
        user_id: 123,
        products: [],
        current_user: %{name: "Alice"}
      }

      result = State.enrich(assigns, [])

      assert :user_id in result.state_keys
      assert :products in result.state_keys
      assert :current_user in result.state_keys
      assert length(result.state_keys) == 3
    end

    test "counts total keys" do
      assigns = %{
        user_id: 123,
        products: [],
        settings: %{theme: "dark"}
      }

      result = State.enrich(assigns, [])
      assert result.state_key_count == 3
    end

    test "calculates max nesting depth" do
      assigns = %{
        user: %{
          profile: %{
            settings: %{
              theme: "dark"
            }
          }
        }
      }

      result = State.enrich(assigns, [])
      assert result.state_max_depth == 4
    end

    test "handles flat structure" do
      assigns = %{
        a: 1,
        b: 2,
        c: 3
      }

      result = State.enrich(assigns, [])
      assert result.state_max_depth == 1
    end

    test "handles empty assigns" do
      result = State.enrich(%{}, [])

      assert result.state_keys == []
      assert result.state_key_count == 0
      assert result.state_max_depth == 0
    end

    test "ignores Ecto __meta__ in depth calculation" do
      assigns = %{
        user: %{
          __struct__: User,
          __meta__: %{},
          id: 1,
          profile: %{
            bio: "text"
          }
        }
      }

      result = State.enrich(assigns, [])

      # Should count: assigns -> user -> profile = 3 levels
      # __meta__ and __struct__ should be ignored, primitives don't add depth
      assert result.state_max_depth == 3
    end

    test "handles lists in depth calculation" do
      assigns = %{
        users: [
          %{id: 1, posts: [%{title: "A"}]}
        ]
      }

      result = State.enrich(assigns, [])

      # assigns -> users list -> item map -> posts list -> item map = 5 levels
      # Primitives don't add to depth
      assert result.state_max_depth == 5
    end
  end
end
