# Telemetry Signal-to-Noise Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make telemetry snapshots scannable by filtering noise, computing diffs, and generating timeline views.

**Architecture:** Add four new modules (Filter, Diff, Timeline, Formatter) to process raw telemetry snapshots. TelemetryCapture.write_snapshots/2 pipes through these modules to generate timeline.json. Mix task accepts CLI flags to control filtering.

**Tech Stack:** Elixir 1.13+, Jason for JSON, ExUnit/Mox for testing

---

## Task 1: Add Filter Module - Ecto Metadata Removal

**Files:**
- Create: `lib/telemetry_capture/filter.ex`
- Test: `test/telemetry_capture/filter_test.exs`

**Step 1: Write failing test for Ecto metadata filtering**

Create test file:

```elixir
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
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/filter_test.exs
```

Expected: FAIL with "module Excessibility.TelemetryCapture.Filter is not available"

**Step 3: Create Filter module with Ecto filtering**

Create `lib/telemetry_capture/filter.ex`:

```elixir
defmodule Excessibility.TelemetryCapture.Filter do
  @moduledoc """
  Filters noise from telemetry snapshot assigns.

  Removes Ecto metadata, Phoenix internals, and other noise
  to improve signal-to-noise ratio for debugging.
  """

  @doc """
  Removes Ecto-related metadata from assigns.

  Filters out:
  - `__meta__` fields
  - `NotLoaded` associations
  """
  def filter_ecto_metadata(assigns) when is_map(assigns) do
    assigns
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      cond do
        # Skip __meta__ fields
        key == :__meta__ ->
          acc

        # Skip NotLoaded associations
        is_struct(value) and value.__struct__ == Ecto.Association.NotLoaded ->
          acc

        # Recursively filter maps
        is_map(value) and not is_struct(value) ->
          Map.put(acc, key, filter_ecto_metadata(value))

        # Recursively filter lists
        is_list(value) ->
          Map.put(acc, key, Enum.map(value, &filter_ecto_metadata/1))

        # Keep everything else
        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  def filter_ecto_metadata(value) when is_list(value) do
    Enum.map(value, &filter_ecto_metadata/1)
  end

  def filter_ecto_metadata(value), do: value
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/filter_test.exs
```

Expected: PASS (4 tests)

**Step 5: Run Credo and format**

```bash
mix format
mix credo --strict
```

Expected: No warnings

**Step 6: Commit**

```bash
git add lib/telemetry_capture/filter.ex test/telemetry_capture/filter_test.exs
git commit -m "feat: add Ecto metadata filtering for telemetry snapshots"
```

---

## Task 2: Add Filter Module - Phoenix Internals Removal

**Files:**
- Modify: `lib/telemetry_capture/filter.ex`
- Modify: `test/telemetry_capture/filter_test.exs`

**Step 1: Write failing test for Phoenix internals filtering**

Add to `test/telemetry_capture/filter_test.exs`:

```elixir
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
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/filter_test.exs::FilterTest
```

Expected: FAIL with "undefined function filter_phoenix_internals/1"

**Step 3: Implement Phoenix internals filtering**

Add to `lib/telemetry_capture/filter.ex`:

```elixir
@phoenix_internal_keys [:flash, :__changed__, :__temp__]

@doc """
Removes Phoenix LiveView internal assigns.

Filters out:
- `:flash`, `:__changed__`, `:__temp__`
- Keys starting with underscore (private assigns)
"""
def filter_phoenix_internals(assigns) when is_map(assigns) do
  assigns
  |> Enum.reject(fn {key, _value} ->
    key in @phoenix_internal_keys or starts_with_underscore?(key)
  end)
  |> Map.new()
end

defp starts_with_underscore?(key) when is_atom(key) do
  key
  |> to_string()
  |> String.starts_with?("_")
end

defp starts_with_underscore?(_), do: false
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/filter_test.exs
```

Expected: PASS (7 tests)

**Step 5: Format and check Credo**

```bash
mix format
mix credo --strict
```

Expected: No warnings

**Step 6: Commit**

```bash
git add lib/telemetry_capture/filter.ex test/telemetry_capture/filter_test.exs
git commit -m "feat: add Phoenix internals filtering"
```

---

## Task 3: Add Filter Module - Combined Filtering Pipeline

**Files:**
- Modify: `lib/telemetry_capture/filter.ex`
- Modify: `test/telemetry_capture/filter_test.exs`

**Step 1: Write test for combined filter_assigns/2**

Add to `test/telemetry_capture/filter_test.exs`:

```elixir
describe "filter_assigns/2" do
  test "applies all filters by default" do
    assigns = %{
      user: %{
        id: 123,
        __meta__: "remove",
        posts: %Ecto.Association.NotLoaded{}
      },
      flash: "remove",
      _private: "remove",
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

  test "disables all filtering with filter_ecto: false, filter_phoenix: false" do
    assigns = %{
      user: %{__meta__: "keep"},
      flash: "keep"
    }

    result = Filter.filter_assigns(assigns, filter_ecto: false, filter_phoenix: false)

    assert result == assigns
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/filter_test.exs::"test filter_assigns/2"
```

Expected: FAIL

**Step 3: Implement filter_assigns/2 with options**

Add to `lib/telemetry_capture/filter.ex`:

```elixir
@doc """
Applies all filtering to assigns based on options.

## Options

- `:filter_ecto` - Remove Ecto metadata (default: true)
- `:filter_phoenix` - Remove Phoenix internals (default: true)
"""
def filter_assigns(assigns, opts \\ []) do
  filter_ecto? = Keyword.get(opts, :filter_ecto, true)
  filter_phoenix? = Keyword.get(opts, :filter_phoenix, true)

  assigns
  |> apply_if(filter_ecto?, &filter_ecto_metadata/1)
  |> apply_if(filter_phoenix?, &filter_phoenix_internals/1)
end

defp apply_if(value, true, fun), do: fun.(value)
defp apply_if(value, false, _fun), do: value
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/filter_test.exs
```

Expected: PASS (11 tests)

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture/filter.ex test/telemetry_capture/filter_test.exs
git commit -m "feat: add configurable filter_assigns pipeline"
```

---

## Task 4: Add Diff Module - Basic Diff Detection

**Files:**
- Create: `lib/telemetry_capture/diff.ex`
- Test: `test/telemetry_capture/diff_test.exs`

**Step 1: Write failing test for diff computation**

Create `test/telemetry_capture/diff_test.exs`:

```elixir
defmodule Excessibility.TelemetryCapture.DiffTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Diff

  describe "compute_diff/2" do
    test "returns nil when previous is nil" do
      current = %{user_id: 123}
      result = Diff.compute_diff(current, nil)

      assert result == nil
    end

    test "detects added keys" do
      previous = %{user_id: 123}
      current = %{user_id: 123, cart_items: 1}

      result = Diff.compute_diff(current, previous)

      assert result.added == %{cart_items: 1}
      assert result.changed == %{}
      assert result.removed == []
    end

    test "detects removed keys" do
      previous = %{user_id: 123, temp: "value"}
      current = %{user_id: 123}

      result = Diff.compute_diff(current, previous)

      assert result.added == %{}
      assert result.changed == %{}
      assert result.removed == [:temp]
    end

    test "detects changed values" do
      previous = %{status: :pending, count: 0}
      current = %{status: :complete, count: 5}

      result = Diff.compute_diff(current, previous)

      assert result.added == %{}
      assert result.changed == %{
        status: {:pending, :complete},
        count: {0, 5}
      }
      assert result.removed == []
    end

    test "handles nested maps" do
      previous = %{user: %{id: 1, name: "Old"}}
      current = %{user: %{id: 1, name: "New"}}

      result = Diff.compute_diff(current, previous)

      assert result.changed == %{
        "user.name" => {"Old", "New"}
      }
    end
  end

  describe "extract_changes/1" do
    test "converts diff to simple change map" do
      diff = %{
        added: %{new_field: "value"},
        changed: %{status: {:old, :new}},
        removed: [:temp]
      }

      result = Diff.extract_changes(diff)

      assert result == %{
        "new_field" => {nil, "value"},
        "status" => {:old, :new}
      }
    end

    test "returns nil for nil diff" do
      assert Diff.extract_changes(nil) == nil
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/diff_test.exs
```

Expected: FAIL with module not found

**Step 3: Implement Diff module**

Create `lib/telemetry_capture/diff.ex`:

```elixir
defmodule Excessibility.TelemetryCapture.Diff do
  @moduledoc """
  Computes differences between sequential telemetry snapshots.

  Identifies added, changed, and removed assigns to highlight
  what actually changed between LiveView events.
  """

  @doc """
  Computes the diff between current and previous assigns.

  Returns nil if previous is nil (first snapshot).
  Returns a map with :added, :changed, :removed keys.
  """
  def compute_diff(_current, nil), do: nil

  def compute_diff(current, previous) when is_map(current) and is_map(previous) do
    current_keys = MapSet.new(Map.keys(current))
    previous_keys = MapSet.new(Map.keys(previous))

    added_keys = MapSet.difference(current_keys, previous_keys)
    removed_keys = MapSet.difference(previous_keys, current_keys)
    common_keys = MapSet.intersection(current_keys, previous_keys)

    added =
      added_keys
      |> Enum.map(&{&1, Map.get(current, &1)})
      |> Map.new()

    changed =
      common_keys
      |> Enum.reduce(%{}, fn key, acc ->
        current_val = Map.get(current, key)
        previous_val = Map.get(previous, key)

        if current_val != previous_val do
          detect_nested_changes(to_string(key), current_val, previous_val, acc)
        else
          acc
        end
      end)

    %{
      added: added,
      changed: changed,
      removed: Enum.to_list(removed_keys)
    }
  end

  @doc """
  Extracts changes from a diff into a simple map format.

  Converts added/changed/removed into a flat map of field => {old, new} tuples.
  """
  def extract_changes(nil), do: nil

  def extract_changes(%{added: added, changed: changed, removed: _removed}) do
    added_changes =
      added
      |> Enum.map(fn {key, val} -> {to_string(key), {nil, val}} end)
      |> Map.new()

    Map.merge(added_changes, changed)
  end

  # Private helpers

  defp detect_nested_changes(path, current, previous, acc)
       when is_map(current) and is_map(previous) and not is_struct(current) and
              not is_struct(previous) do
    current
    |> Enum.reduce(acc, fn {key, val}, nested_acc ->
      prev_val = Map.get(previous, key)
      nested_path = "#{path}.#{key}"

      cond do
        prev_val == nil ->
          Map.put(nested_acc, nested_path, {nil, val})

        val != prev_val ->
          detect_nested_changes(nested_path, val, prev_val, nested_acc)

        true ->
          nested_acc
      end
    end)
  end

  defp detect_nested_changes(path, current, previous, acc) do
    Map.put(acc, path, {previous, current})
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/diff_test.exs
```

Expected: PASS (9 tests)

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture/diff.ex test/telemetry_capture/diff_test.exs
git commit -m "feat: add diff computation for telemetry snapshots"
```

---

## Task 5: Add Timeline Module - Key State Extraction

**Files:**
- Create: `lib/telemetry_capture/timeline.ex`
- Test: `test/telemetry_capture/timeline_test.exs`

**Step 1: Write failing test for key state extraction**

Create `test/telemetry_capture/timeline_test.exs`:

```elixir
defmodule Excessibility.TelemetryCapture.TimelineTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Timeline

  describe "extract_key_state/2" do
    test "extracts small primitive values" do
      assigns = %{
        user_id: 123,
        status: :active,
        name: "John",
        large_text: String.duplicate("a", 500)
      }

      result = Timeline.extract_key_state(assigns)

      assert result.user_id == 123
      assert result.status == :active
      assert result.name == "John"
      refute Map.has_key?(result, :large_text)
    end

    test "extracts highlighted fields from config" do
      assigns = %{
        current_user: %{id: 123},
        errors: ["error"],
        other: "ignored"
      }

      result = Timeline.extract_key_state(assigns, [:current_user, :errors])

      assert result.current_user == %{id: 123}
      assert result.errors == ["error"]
      refute Map.has_key?(result, :other)
    end

    test "converts lists to counts" do
      assigns = %{
        products: [%{id: 1}, %{id: 2}, %{id: 3}],
        tags: []
      }

      result = Timeline.extract_key_state(assigns)

      assert result.products_count == 3
      assert result.tags_count == 0
    end

    test "extracts live_action" do
      assigns = %{
        live_action: :edit,
        other: "data"
      }

      result = Timeline.extract_key_state(assigns)

      assert result.live_action == :edit
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/timeline_test.exs
```

Expected: FAIL

**Step 3: Implement Timeline.extract_key_state/2**

Create `lib/telemetry_capture/timeline.ex`:

```elixir
defmodule Excessibility.TelemetryCapture.Timeline do
  @moduledoc """
  Generates timeline data from telemetry snapshots.

  Extracts key state, computes diffs, and formats timeline entries
  for human and AI consumption.
  """

  @default_highlight_fields [:current_user, :live_action, :errors, :form]
  @small_value_threshold 100

  @doc """
  Extracts key state from assigns for timeline display.

  Includes:
  - Highlighted fields (from config)
  - Small primitive values (< #{@small_value_threshold} chars)
  - List counts (products: [3 items] -> products_count: 3)
  - Auto-detected important fields (status, action, etc.)
  """
  def extract_key_state(assigns, highlight_fields \\ @default_highlight_fields) do
    assigns
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      cond do
        # Always include highlighted fields
        key in highlight_fields ->
          Map.put(acc, key, value)

        # Convert lists to counts
        is_list(value) ->
          Map.put(acc, :"#{key}_count", length(value))

        # Include small primitives
        is_small_value?(value) ->
          Map.put(acc, key, value)

        # Skip everything else
        true ->
          acc
      end
    end)
  end

  defp is_small_value?(value) when is_integer(value), do: true
  defp is_small_value?(value) when is_atom(value), do: true
  defp is_small_value?(value) when is_boolean(value), do: true

  defp is_small_value?(value) when is_binary(value) do
    byte_size(value) <= @small_value_threshold
  end

  defp is_small_value?(_), do: false
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/timeline_test.exs
```

Expected: PASS (4 tests)

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture/timeline.ex test/telemetry_capture/timeline_test.exs
git commit -m "feat: add key state extraction for timeline"
```

---

## Task 6: Add Timeline Module - Build Timeline Entries

**Files:**
- Modify: `lib/telemetry_capture/timeline.ex`
- Modify: `test/telemetry_capture/timeline_test.exs`

**Step 1: Write failing test for build_timeline/2**

Add to `test/telemetry_capture/timeline_test.exs`:

```elixir
describe "build_timeline/2" do
  test "builds timeline from snapshots" do
    snapshots = [
      %{
        event_type: "mount",
        assigns: %{user_id: 123, products_count: 0},
        timestamp: ~U[2026-01-25 10:00:00Z],
        view_module: MyApp.Live
      },
      %{
        event_type: "handle_event:add",
        assigns: %{user_id: 123, products_count: 1},
        timestamp: ~U[2026-01-25 10:00:01Z],
        view_module: MyApp.Live
      }
    ]

    result = Timeline.build_timeline(snapshots, "test_name")

    assert result.test == "test_name"
    assert result.duration_ms == 1000
    assert length(result.timeline) == 2

    first = Enum.at(result.timeline, 0)
    assert first.sequence == 1
    assert first.event == "mount"
    assert first.changes == nil

    second = Enum.at(result.timeline, 1)
    assert second.sequence == 2
    assert second.event == "handle_event:add"
    assert second.changes == %{"products_count" => {0, 1}}
    assert second.duration_since_previous_ms == 1000
  end

  test "handles empty snapshots" do
    result = Timeline.build_timeline([], "empty_test")

    assert result.test == "empty_test"
    assert result.timeline == []
    assert result.duration_ms == 0
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/timeline_test.exs::"test build_timeline/2"
```

Expected: FAIL

**Step 3: Implement build_timeline/2**

Add to `lib/telemetry_capture/timeline.ex`:

```elixir
alias Excessibility.TelemetryCapture.{Diff, Filter}

@doc """
Builds a complete timeline from snapshots.

Returns a map with:
- :test - test name
- :duration_ms - total test duration
- :timeline - list of timeline entries
"""
def build_timeline([], test_name) do
  %{
    test: test_name,
    timeline: [],
    duration_ms: 0
  }
end

def build_timeline(snapshots, test_name, opts \\ []) do
  first_timestamp = List.first(snapshots).timestamp
  last_timestamp = List.last(snapshots).timestamp
  duration_ms = DateTime.diff(last_timestamp, first_timestamp, :millisecond)

  timeline =
    snapshots
    |> Enum.with_index(1)
    |> Enum.map(fn {snapshot, index} ->
      previous = if index > 1, do: Enum.at(snapshots, index - 2), else: nil
      build_timeline_entry(snapshot, previous, index, opts)
    end)

  %{
    test: test_name,
    duration_ms: duration_ms,
    timeline: timeline
  }
end

@doc """
Builds a single timeline entry from a snapshot and its predecessor.
"""
def build_timeline_entry(snapshot, previous, sequence, opts \\ []) do
  filtered_assigns = Filter.filter_assigns(snapshot.assigns, opts)
  key_state = extract_key_state(filtered_assigns, opts[:highlight_fields] || @default_highlight_fields)

  previous_assigns =
    if previous do
      Filter.filter_assigns(previous.assigns, opts)
    end

  diff = Diff.compute_diff(filtered_assigns, previous_assigns)
  changes = Diff.extract_changes(diff)

  duration_since_previous =
    if previous do
      DateTime.diff(snapshot.timestamp, previous.timestamp, :millisecond)
    end

  %{
    sequence: sequence,
    event: snapshot.event_type,
    timestamp: snapshot.timestamp,
    view_module: snapshot.view_module,
    key_state: key_state,
    changes: changes,
    duration_since_previous_ms: duration_since_previous
  }
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/timeline_test.exs
```

Expected: PASS (6 tests)

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture/timeline.ex test/telemetry_capture/timeline_test.exs
git commit -m "feat: add timeline building with diffs"
```

---

## Task 7: Add Formatter Module - JSON Output

**Files:**
- Create: `lib/telemetry_capture/formatter.ex`
- Test: `test/telemetry_capture/formatter_test.exs`

**Step 1: Write failing test for JSON formatting**

Create `test/telemetry_capture/formatter_test.exs`:

```elixir
defmodule Excessibility.TelemetryCapture.FormatterTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Formatter

  describe "format_json/1" do
    test "encodes timeline as JSON" do
      timeline = %{
        test: "my_test",
        duration_ms: 500,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{user_id: 123},
            changes: nil
          }
        ]
      }

      result = Formatter.format_json(timeline)

      assert is_binary(result)
      decoded = Jason.decode!(result)
      assert decoded["test"] == "my_test"
      assert decoded["duration_ms"] == 500
      assert length(decoded["timeline"]) == 1
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/formatter_test.exs
```

Expected: FAIL

**Step 3: Implement Formatter.format_json/1**

Create `lib/telemetry_capture/formatter.ex`:

```elixir
defmodule Excessibility.TelemetryCapture.Formatter do
  @moduledoc """
  Formats telemetry timeline data for different output formats.

  Supports:
  - JSON (machine-readable)
  - Markdown (human/AI-readable)
  - Package (directory with multiple files)
  """

  @doc """
  Formats timeline as JSON.
  """
  def format_json(timeline) do
    Jason.encode!(timeline, pretty: true)
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/formatter_test.exs
```

Expected: PASS (1 test)

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture/formatter.ex test/telemetry_capture/formatter_test.exs
git commit -m "feat: add JSON formatter for timeline"
```

---

## Task 8: Add Formatter Module - Markdown Timeline Table

**Files:**
- Modify: `lib/telemetry_capture/formatter.ex`
- Modify: `test/telemetry_capture/formatter_test.exs`

**Step 1: Write failing test for markdown formatting**

Add to `test/telemetry_capture/formatter_test.exs`:

```elixir
describe "format_markdown/2" do
  test "generates markdown with timeline table" do
    timeline = %{
      test: "purchase_flow",
      duration_ms: 850,
      timeline: [
        %{
          sequence: 1,
          event: "mount",
          timestamp: ~U[2026-01-25 10:00:00.000Z],
          key_state: %{user_id: 123, cart_items_count: 0},
          changes: nil,
          duration_since_previous_ms: nil
        },
        %{
          sequence: 2,
          event: "handle_event:add_to_cart",
          timestamp: ~U[2026-01-25 10:00:00.350Z],
          key_state: %{user_id: 123, cart_items_count: 1},
          changes: %{"cart_items_count" => {0, 1}},
          duration_since_previous_ms: 350
        }
      ]
    }

    result = Formatter.format_markdown(timeline, [])

    assert result =~ "# Test Debug Report: purchase_flow"
    assert result =~ "850ms"
    assert result =~ "| # | Time | Event | Key Changes |"
    assert result =~ "| 1 | +0ms | mount |"
    assert result =~ "| 2 | +350ms | handle_event:add_to_cart | cart_items_count: 0→1 |"
  end

  test "generates detailed change sections" do
    timeline = %{
      test: "test",
      duration_ms: 100,
      timeline: [
        %{
          sequence: 1,
          event: "mount",
          timestamp: ~U[2026-01-25 10:00:00Z],
          key_state: %{status: :pending},
          changes: nil,
          duration_since_previous_ms: nil
        },
        %{
          sequence: 2,
          event: "submit",
          timestamp: ~U[2026-01-25 10:00:00.100Z],
          key_state: %{status: :complete},
          changes: %{"status" => {:pending, :complete}},
          duration_since_previous_ms: 100
        }
      ]
    }

    result = Formatter.format_markdown(timeline, [])

    assert result =~ "## Detailed Changes"
    assert result =~ "### Event 2: submit (+100ms)"
    assert result =~ "**State Changes:**"
    assert result =~ "- `status`: :pending → :complete"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture/formatter_test.exs::"test format_markdown/2"
```

Expected: FAIL

**Step 3: Implement format_markdown/2**

Add to `lib/telemetry_capture/formatter.ex`:

```elixir
@doc """
Formats timeline as markdown report.

Includes:
- Summary header
- Timeline table
- Detailed change sections
- Optional full snapshots (if snapshots provided)
"""
def format_markdown(timeline, _snapshots) do
  """
  # Test Debug Report: #{timeline.test}

  **Duration:** #{timeline.duration_ms}ms

  ## Event Timeline

  #{build_timeline_table(timeline.timeline)}

  ## Detailed Changes

  #{build_detailed_changes(timeline.timeline)}
  """
end

defp build_timeline_table(entries) do
  header = "| # | Time | Event | Key Changes |\n|---|------|-------|-------------|"

  rows =
    entries
    |> Enum.map(fn entry ->
      time = "+#{entry.duration_since_previous_ms || 0}ms"
      changes = format_key_changes(entry.changes)
      "| #{entry.sequence} | #{time} | #{entry.event} | #{changes} |"
    end)
    |> Enum.join("\n")

  header <> "\n" <> rows
end

defp format_key_changes(nil), do: ""

defp format_key_changes(changes) when map_size(changes) == 0, do: ""

defp format_key_changes(changes) do
  changes
  |> Enum.take(3)
  |> Enum.map_join(", ", fn {field, {old, new}} ->
    "#{field}: #{inspect(old)}→#{inspect(new)}"
  end)
end

defp build_detailed_changes(entries) do
  entries
  |> Enum.filter(fn entry -> entry.changes != nil and map_size(entry.changes) > 0 end)
  |> Enum.map_join("\n\n---\n\n", &format_detailed_change/1)
end

defp format_detailed_change(entry) do
  """
  ### Event #{entry.sequence}: #{entry.event} (+#{entry.duration_since_previous_ms || 0}ms)

  **State Changes:**
  #{format_change_list(entry.changes)}

  **Key State:**
  ```elixir
  #{inspect(entry.key_state, pretty: true)}
  ```
  """
end

defp format_change_list(changes) do
  changes
  |> Enum.map_join("\n", fn {field, {old, new}} ->
    "- `#{field}`: #{inspect(old)} → #{inspect(new)}"
  end)
end
```

**Step 4: Run tests to verify they pass**

```bash
mix test test/telemetry_capture/formatter_test.exs
```

Expected: PASS (3 tests)

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture/formatter.ex test/telemetry_capture/formatter_test.exs
git commit -m "feat: add markdown formatter with timeline table"
```

---

## Task 9: Integrate Timeline Generation into TelemetryCapture

**Files:**
- Modify: `lib/telemetry_capture.ex`
- Test: `test/telemetry_capture_integration_test.exs`

**Step 1: Write integration test**

Create `test/telemetry_capture_integration_test.exs`:

```elixir
defmodule Excessibility.TelemetryCaptureIntegrationTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  setup do
    # Clean up any existing snapshots
    :ets.whereis(:excessibility_snapshots) != :undefined &&
      :ets.delete_all_objects(:excessibility_snapshots)

    output_path = "test/excessibility"
    File.rm_rf!(output_path)

    :ok
  end

  test "write_snapshots generates timeline.json" do
    # Attach telemetry
    TelemetryCapture.attach()

    # Simulate capturing snapshots
    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :mount, :stop],
      %{duration: 100},
      %{
        socket: %{
          assigns: %{user_id: 123, products: []},
          view: MyApp.Live
        }
      },
      nil
    )

    :timer.sleep(10)

    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: 50},
      %{
        socket: %{
          assigns: %{user_id: 123, products: [%{id: 1}]},
          view: MyApp.Live
        },
        params: %{"event" => "add_product"}
      },
      nil
    )

    # Write snapshots
    TelemetryCapture.write_snapshots("integration_test")

    # Verify timeline.json exists
    timeline_path = "test/excessibility/timeline.json"
    assert File.exists?(timeline_path)

    # Verify timeline content
    timeline = File.read!(timeline_path) |> Jason.decode!()
    assert timeline["test"] == "integration_test"
    assert length(timeline["timeline"]) == 2

    first_event = Enum.at(timeline["timeline"], 0)
    assert first_event["event"] == "mount"
    assert first_event["sequence"] == 1

    second_event = Enum.at(timeline["timeline"], 1)
    assert second_event["event"] == "handle_event:add_product"
    assert second_event["changes"] != nil

    # Cleanup
    TelemetryCapture.detach()
    File.rm_rf!("test/excessibility")
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test test/telemetry_capture_integration_test.exs
```

Expected: FAIL - timeline.json not generated

**Step 3: Modify TelemetryCapture.write_snapshots/1 to generate timeline**

Modify in `lib/telemetry_capture.ex`:

```elixir
alias Excessibility.TelemetryCapture.{Timeline, Formatter}

@doc """
Writes captured snapshots to HTML files and generates timeline.json.
"""
def write_snapshots(test_name) do
  snapshots = get_snapshots()
  IO.puts("💾 Excessibility: Writing #{length(snapshots)} telemetry snapshots for test #{inspect(test_name)}")

  if snapshots != [] do
    output_path =
      Application.get_env(
        :excessibility,
        :excessibility_output_path,
        "test/excessibility"
      )

    snapshots_path = Path.join(output_path, "html_snapshots")
    File.mkdir_p!(snapshots_path)

    # Write HTML snapshots
    snapshots
    |> Enum.with_index(1)
    |> Enum.each(fn {snapshot, index} ->
      filename = "#{sanitize_test_name(test_name)}_telemetry_#{index}_#{sanitize_event_type(snapshot.event_type)}.html"
      path = Path.join(snapshots_path, filename)

      html = build_snapshot_html(snapshot, index, test_name)
      File.write!(path, html)

      Logger.info("Wrote telemetry snapshot: #{filename}")
    end)

    # Generate and write timeline.json
    timeline = Timeline.build_timeline(snapshots, test_name)
    timeline_json = Formatter.format_json(timeline)
    timeline_path = Path.join(output_path, "timeline.json")
    File.write!(timeline_path, timeline_json)

    IO.puts("📊 Excessibility: Wrote timeline.json")
  end
end
```

**Step 4: Run test to verify it passes**

```bash
mix test test/telemetry_capture_integration_test.exs
```

Expected: PASS

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/telemetry_capture.ex test/telemetry_capture_integration_test.exs
git commit -m "feat: integrate timeline.json generation into write_snapshots"
```

---

## Task 10: Add CLI Flags to Mix Task

**Files:**
- Modify: `lib/mix/tasks/excessibility_debug.ex`
- Test: Test manually (Mix tasks are hard to unit test)

**Step 1: Add CLI flag parsing**

Modify the `run/1` function in `lib/mix/tasks/excessibility_debug.ex`:

```elixir
@impl Mix.Task
def run(args) do
  {opts, test_paths, _} =
    OptionParser.parse(args,
      strict: [
        format: :string,
        full: :boolean,
        minimal: :boolean,
        no_filter_ecto: :boolean,
        no_filter_phoenix: :boolean,
        highlight: :string
      ],
      aliases: [f: :format]
    )

  format = Keyword.get(opts, :format, "markdown")
  full_mode = Keyword.get(opts, :full, false)
  minimal_mode = Keyword.get(opts, :minimal, false)

  # Build filter options
  filter_opts =
    cond do
      full_mode ->
        [filter_ecto: false, filter_phoenix: false]

      true ->
        [
          filter_ecto: !Keyword.get(opts, :no_filter_ecto, false),
          filter_phoenix: !Keyword.get(opts, :no_filter_phoenix, false)
        ]
    end

  # Parse highlight fields if provided
  highlight_fields =
    case Keyword.get(opts, :highlight) do
      nil -> nil
      fields_str -> String.split(fields_str, ",") |> Enum.map(&String.to_atom/1)
    end

  if highlight_fields do
    filter_opts = Keyword.put(filter_opts, :highlight_fields, highlight_fields)
  end

  # Store opts in process dictionary for use during formatting
  Process.put(:excessibility_debug_opts, %{
    format: format,
    minimal: minimal_mode,
    filter_opts: filter_opts
  })

  # ... rest of existing run/1 code
end
```

**Step 2: Update output functions to use filter options**

Modify the timeline building in `output_markdown/1`:

```elixir
defp output_markdown(report_data) do
  opts = Process.get(:excessibility_debug_opts, %{})
  filter_opts = Map.get(opts, :filter_opts, [])

  # Read timeline.json if it exists
  timeline_path = Path.join([
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility"),
    "timeline.json"
  ])

  markdown =
    if File.exists?(timeline_path) do
      timeline = File.read!(timeline_path) |> Jason.decode!(keys: :atoms)
      Excessibility.TelemetryCapture.Formatter.format_markdown(timeline, report_data.snapshots)
    else
      build_markdown_report(report_data)
    end

  # Output to stdout
  Mix.shell().info(markdown)

  # Save to file
  output_path =
    Application.get_env(
      :excessibility,
      :excessibility_output_path,
      "test/excessibility"
    )

  latest_path = Path.join(output_path, "latest_debug.md")
  File.mkdir_p!(output_path)
  File.write!(latest_path, markdown)

  Mix.shell().info("\n📋 Report saved to: #{latest_path}")
  Mix.shell().info("💡 Paste the above to Claude, or tell Claude to read #{latest_path}")
end
```

**Step 3: Update moduledoc with new CLI flags**

Update `@moduledoc` in `lib/mix/tasks/excessibility_debug.ex`:

```elixir
@moduledoc """
Run a test and generate a comprehensive debug report with all snapshots.

## Usage

    mix excessibility.debug test/my_test.exs
    mix excessibility.debug test/my_test.exs --format=json
    mix excessibility.debug test/my_test.exs --full
    mix excessibility.debug test/my_test.exs --minimal

## Flags

- `--format=markdown|json|package` - Output format (default: markdown)
- `--full` - Disable all filtering, show complete assigns
- `--minimal` - Timeline only, no detailed snapshots
- `--no-filter-ecto` - Keep Ecto metadata (__meta__, NotLoaded)
- `--no-filter-phoenix` - Keep Phoenix internals (flash, __changed__)
- `--highlight=field1,field2` - Custom fields to highlight in timeline

## Output

The command outputs the report to stdout and also saves it to:
- Markdown: `test/excessibility/latest_debug.md`
- JSON: `test/excessibility/latest_debug.json`
- Timeline: `test/excessibility/timeline.json` (always generated)
- Package: `test/excessibility/debug_packages/[test_name]_[timestamp]/`
"""
```

**Step 4: Test manually**

```bash
# Create a simple test file if needed
mix test test/capture_test.exs

# Test with default flags
mix excessibility.debug test/capture_test.exs

# Test with --full flag
mix excessibility.debug test/capture_test.exs --full

# Test with custom highlight
mix excessibility.debug test/capture_test.exs --highlight=user_id,status
```

Expected: Commands run successfully, timeline.json generated with appropriate filtering

**Step 5: Format and Credo**

```bash
mix format
mix credo --strict
```

Expected: Clean

**Step 6: Commit**

```bash
git add lib/mix/tasks/excessibility_debug.ex
git commit -m "feat: add CLI flags for filtering and format control"
```

---

## Task 11: Run Full Test Suite and Fix Issues

**Step 1: Run all existing tests**

```bash
mix test
```

Expected: May have failures due to changes. Fix any broken tests.

**Step 2: Fix any Credo warnings**

```bash
mix credo --strict
```

Expected: Fix all warnings

**Step 3: Ensure formatting is consistent**

```bash
mix format --check-formatted
```

If check fails:

```bash
mix format
```

**Step 4: Run tests again to confirm**

```bash
mix test
```

Expected: All tests pass

**Step 5: Commit any fixes**

```bash
git add .
git commit -m "fix: resolve test failures and credo warnings"
```

---

## Task 12: Update Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Step 1: Add timeline section to CLAUDE.md**

Add to `CLAUDE.md` in the "Accessibility Testing" section:

```markdown
### Timeline Analysis

The telemetry capture automatically generates `timeline.json` for each test run:

```bash
# Run test with telemetry capture
mix test test/my_live_view_test.exs

# View timeline
cat test/excessibility/timeline.json

# Generate debug report with filtering options
mix excessibility.debug test/my_live_view_test.exs
mix excessibility.debug test/my_live_view_test.exs --full
mix excessibility.debug test/my_live_view_test.exs --highlight=current_user,cart
```

Timeline JSON structure:
- `test` - Test name
- `duration_ms` - Total test duration
- `timeline[]` - Array of events with:
  - `sequence` - Event number
  - `event` - Event type (mount, handle_event:name, etc.)
  - `timestamp` - ISO8601 timestamp
  - `key_state` - Extracted important state
  - `changes` - Diff from previous event

**Filtering Options:**

By default, telemetry snapshots filter out noise:
- Ecto `__meta__` fields and `NotLoaded` associations
- Phoenix internals (`flash`, `__changed__`, `__temp__`)
- Private assigns (starting with `_`)

Use `--full` to disable filtering and see complete assigns.
```

**Step 2: Add entry to README.md**

Add to the README features section:

```markdown
### 🔍 Telemetry Timeline Analysis

Automatically captures LiveView state throughout test execution and generates scannable timeline reports:

- **Smart Filtering** - Removes Ecto metadata, Phoenix internals, and other noise
- **Diff Detection** - Shows what changed between events
- **Multiple Formats** - JSON for automation, Markdown for humans/AI
- **CLI Control** - Override filtering with flags for deep debugging

```bash
mix excessibility.debug test/my_test.exs
```

See [CLAUDE.md](CLAUDE.md) for detailed usage.
```

**Step 3: Commit documentation updates**

```bash
git add README.md CLAUDE.md
git commit -m "docs: add timeline analysis documentation"
```

---

## Task 13: Final Verification

**Step 1: Run complete test suite**

```bash
mix test
```

Expected: All tests pass

**Step 2: Run Credo with strict mode**

```bash
mix credo --strict
```

Expected: No warnings or errors

**Step 3: Verify formatting**

```bash
mix format --check-formatted
```

Expected: All files formatted

**Step 4: Test real-world scenario**

```bash
# Run debug on actual test
mix excessibility.debug test/capture_test.exs

# Verify outputs exist
ls -lh test/excessibility/timeline.json
ls -lh test/excessibility/latest_debug.md

# Check timeline content
cat test/excessibility/timeline.json | head -n 20
```

Expected: Files generated correctly with filtered content

**Step 5: Create final commit if any fixes needed**

```bash
git add .
git commit -m "chore: final verification and cleanup"
```

---

## Completion

**All tasks complete!** The implementation includes:

✅ Filter module with Ecto and Phoenix filtering
✅ Diff module for change detection
✅ Timeline module for key state extraction
✅ Formatter module for JSON and Markdown output
✅ Integration into TelemetryCapture
✅ CLI flags for runtime control
✅ Comprehensive test coverage
✅ Documentation updates

**Quality gates met:**
- All tests passing
- Credo clean
- Code formatted
- New functionality tested

**Next steps:**
- Manual testing with real LiveView tests
- Gather feedback on timeline readability
- Consider additional output formats if needed
