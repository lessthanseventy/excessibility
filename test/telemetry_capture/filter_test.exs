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

  describe "filter_phoenix_internals/1" do
    test "removes flash" do
      assigns = %{
        flash: %{"info" => "Success"},
        user_id: 123
      }

      result = Filter.filter_phoenix_internals(assigns)

      refute Map.has_key?(result, :flash)
      assert result.user_id == 123
    end

    test "removes __changed__ and __temp__" do
      assigns = %{
        __changed__: %{user: true},
        __temp__: %{},
        data: "keep"
      }

      result = Filter.filter_phoenix_internals(assigns)

      refute Map.has_key?(result, :__changed__)
      refute Map.has_key?(result, :__temp__)
      assert result.data == "keep"
    end

    test "removes private assigns starting with underscore" do
      assigns = %{
        _private: "remove",
        _internal_state: "remove",
        public: "keep",
        __special__: "remove"
      }

      result = Filter.filter_phoenix_internals(assigns)

      refute Map.has_key?(result, :_private)
      refute Map.has_key?(result, :_internal_state)
      refute Map.has_key?(result, :__special__)
      assert result.public == "keep"
    end
  end

  describe "filter_functions/1" do
    test "removes function values from top-level keys" do
      callback = fn -> :ok end
      handler = fn x -> x + 1 end

      assigns = %{
        on_click: callback,
        user_id: 123,
        transform: handler,
        name: "John"
      }

      result = Filter.filter_functions(assigns)

      refute Map.has_key?(result, :on_click)
      refute Map.has_key?(result, :transform)
      assert result.user_id == 123
      assert result.name == "John"
    end

    test "recursively filters functions from nested maps" do
      callback = fn -> :ok end

      assigns = %{
        user: %{
          id: 123,
          callback: callback,
          settings: %{
            handler: fn x -> x end,
            theme: "dark"
          }
        },
        count: 5
      }

      result = Filter.filter_functions(assigns)

      assert result.user.id == 123
      assert result.user.settings.theme == "dark"
      assert result.count == 5
      refute Map.has_key?(result.user, :callback)
      refute Map.has_key?(result.user.settings, :handler)
    end

    test "recursively filters functions from lists" do
      callback = fn -> :ok end

      assigns = %{
        items: [
          %{id: 1, handler: callback, name: "Item 1"},
          %{id: 2, handler: callback, name: "Item 2"}
        ]
      }

      result = Filter.filter_functions(assigns)

      assert length(result.items) == 2
      assert Enum.at(result.items, 0).id == 1
      assert Enum.at(result.items, 0).name == "Item 1"
      refute Map.has_key?(Enum.at(result.items, 0), :handler)
      refute Map.has_key?(Enum.at(result.items, 1), :handler)
    end

    test "preserves structs (doesn't recurse into them)" do
      # Structs might have functions as implementation details
      # We skip them entirely, only filtering regular maps
      date = ~D[2024-01-01]

      assigns = %{
        created_at: date,
        callback: fn -> :ok end
      }

      result = Filter.filter_functions(assigns)

      assert result.created_at == date
      refute Map.has_key?(result, :callback)
    end

    test "preserves non-function data unchanged" do
      assigns = %{
        simple: "value",
        number: 42,
        list: [1, 2, 3],
        nested: %{a: 1, b: 2},
        atom: :ok,
        boolean: true
      }

      result = Filter.filter_functions(assigns)

      assert result == assigns
    end
  end

  describe "filter_assigns/2" do
    test "applies all filters by default" do
      callback = fn -> :ok end

      assigns = %{
        user: %{
          id: 123,
          __meta__: "remove",
          posts: %Ecto.Association.NotLoaded{}
        },
        flash: "remove",
        _private: "remove",
        on_click: callback,
        data: "keep"
      }

      result = Filter.filter_assigns(assigns)

      assert result == %{
               user: %{id: 123},
               data: "keep"
             }
    end

    test "respects filter_ecto: false option" do
      assigns = %{
        user: %{id: 123, __meta__: "keep"},
        flash: "remove"
      }

      result = Filter.filter_assigns(assigns, filter_ecto: false)

      assert result.user.__meta__ == "keep"
      refute Map.has_key?(result, :flash)
    end

    test "respects filter_phoenix: false option" do
      assigns = %{
        user: %{id: 123, __meta__: "remove"},
        flash: "keep"
      }

      result = Filter.filter_assigns(assigns, filter_phoenix: false)

      refute Map.has_key?(result.user, :__meta__)
      assert result.flash == "keep"
    end

    test "respects filter_functions: false option" do
      callback = fn -> :ok end

      assigns = %{
        user: %{id: 123, __meta__: "remove"},
        on_click: callback
      }

      result = Filter.filter_assigns(assigns, filter_functions: false)

      refute Map.has_key?(result.user, :__meta__)
      assert result.on_click == callback
    end

    test "disables all filtering with all options false" do
      callback = fn -> :ok end

      assigns = %{
        user: %{__meta__: "keep"},
        flash: "keep",
        on_click: callback
      }

      result =
        Filter.filter_assigns(assigns, filter_ecto: false, filter_phoenix: false, filter_functions: false)

      assert result == assigns
    end
  end
end
