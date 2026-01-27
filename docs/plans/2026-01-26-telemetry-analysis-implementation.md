# Telemetry Analysis Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build extensible enrichment and analysis system for telemetry capture with Memory enricher and analyzer as proof-of-concept.

**Architecture:** Two-layer plugin system - Enrichers add computed data during timeline building (memory size, query counts), Analyzers detect patterns after timeline completion (bloat, leaks, state machines). Both use behaviours for extensibility.

**Tech Stack:** Elixir, ExUnit, Jason (JSON), existing telemetry capture infrastructure

---

## Task 1: Create Enricher Behaviour

**Files:**
- Create: `lib/telemetry_capture/enricher.ex`
- Test: `test/telemetry_capture/enricher_test.exs`

**Step 1: Write the behaviour test**

```elixir
# test/telemetry_capture/enricher_test.exs
defmodule Excessibility.TelemetryCapture.EnricherTest do
  use ExUnit.Case, async: true

  # Test implementation of enricher
  defmodule TestEnricher do
    @behaviour Excessibility.TelemetryCapture.Enricher

    def name, do: :test

    def enrich(assigns, _opts) do
      %{test_field: Map.get(assigns, :value, 0) * 2}
    end
  end

  describe "enricher behaviour" do
    test "implements required callbacks" do
      assert function_exported?(TestEnricher, :name, 0)
      assert function_exported?(TestEnricher, :enrich, 2)
    end

    test "enrich returns map" do
      result = TestEnricher.enrich(%{value: 5}, [])
      assert is_map(result)
      assert result.test_field == 10
    end

    test "name returns atom" do
      assert TestEnricher.name() == :test
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd /home/andrew/projects/excessibility/.worktrees/telemetry-analysis && mix test test/telemetry_capture/enricher_test.exs`

Expected: FAIL with "module Excessibility.TelemetryCapture.Enricher is not available"

**Step 3: Write minimal behaviour implementation**

```elixir
# lib/telemetry_capture/enricher.ex
defmodule Excessibility.TelemetryCapture.Enricher do
  @moduledoc """
  Behaviour for timeline event enrichers.

  Enrichers add computed data to timeline events during timeline building.
  All enrichers run automatically for every event.

  ## Example

      defmodule MyApp.CustomEnricher do
        @behaviour Excessibility.TelemetryCapture.Enricher

        def name, do: :custom

        def enrich(assigns, _opts) do
          %{custom_field: compute_value(assigns)}
        end
      end

  ## Callbacks

  - `name/0` - Returns atom identifier for this enricher
  - `enrich/2` - Takes assigns and options, returns map of fields to add to timeline event
  """

  @callback name() :: atom()
  @callback enrich(assigns :: map(), opts :: keyword()) :: map()
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/enricher_test.exs`

Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add lib/telemetry_capture/enricher.ex test/telemetry_capture/enricher_test.exs
git commit -m "feat: add Enricher behaviour for timeline event enrichment

Defines behaviour for enrichers that add computed data to timeline events.
Enrichers run automatically during timeline building.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Create Analyzer Behaviour

**Files:**
- Create: `lib/telemetry_capture/analyzer.ex`
- Test: `test/telemetry_capture/analyzer_test.exs`

**Step 1: Write the behaviour test**

```elixir
# test/telemetry_capture/analyzer_test.exs
defmodule Excessibility.TelemetryCapture.AnalyzerTest do
  use ExUnit.Case, async: true

  # Test implementation of analyzer
  defmodule TestAnalyzer do
    @behaviour Excessibility.TelemetryCapture.Analyzer

    def name, do: :test
    def default_enabled?, do: true

    def analyze(timeline, _opts) do
      event_count = length(timeline.timeline)

      %{
        findings: if(event_count > 5, do: [
          %{
            severity: :warning,
            message: "Many events detected",
            events: [1, 2, 3],
            metadata: %{count: event_count}
          }
        ], else: []),
        stats: %{event_count: event_count}
      }
    end
  end

  describe "analyzer behaviour" do
    test "implements required callbacks" do
      assert function_exported?(TestAnalyzer, :name, 0)
      assert function_exported?(TestAnalyzer, :default_enabled?, 0)
      assert function_exported?(TestAnalyzer, :analyze, 2)
    end

    test "analyze returns correct structure" do
      timeline = %{timeline: [1, 2, 3]}
      result = TestAnalyzer.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
      assert is_list(result.findings)
      assert is_map(result.stats)
    end

    test "findings have required fields" do
      timeline = %{timeline: [1, 2, 3, 4, 5, 6]}
      result = TestAnalyzer.analyze(timeline, [])

      [finding | _] = result.findings
      assert finding.severity in [:info, :warning, :critical]
      assert is_binary(finding.message)
      assert is_list(finding.events)
      assert is_map(finding.metadata)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/telemetry_capture/analyzer_test.exs`

Expected: FAIL with "module Excessibility.TelemetryCapture.Analyzer is not available"

**Step 3: Write minimal behaviour implementation**

```elixir
# lib/telemetry_capture/analyzer.ex
defmodule Excessibility.TelemetryCapture.Analyzer do
  @moduledoc """
  Behaviour for timeline analyzers.

  Analyzers detect patterns across complete timelines and return structured findings.
  Analyzers are selectively enabled via CLI flags.

  ## Example

      defmodule MyApp.CustomAnalyzer do
        @behaviour Excessibility.TelemetryCapture.Analyzer

        def name, do: :custom
        def default_enabled?, do: false

        def analyze(timeline, _opts) do
          %{
            findings: [...],
            stats: %{...}
          }
        end
      end

  ## Callbacks

  - `name/0` - Returns atom identifier for this analyzer
  - `default_enabled?/0` - Whether analyzer runs by default without explicit flag
  - `analyze/2` - Takes complete timeline and options, returns analysis results

  ## Types

  Analysis results contain:
  - `:findings` - List of issues found (warnings, errors, info)
  - `:stats` - Summary statistics for the analysis
  """

  @callback name() :: atom()
  @callback default_enabled?() :: boolean()
  @callback analyze(timeline :: map(), opts :: keyword()) :: analysis_result()

  @type analysis_result :: %{
          findings: [finding()],
          stats: map()
        }

  @type finding :: %{
          severity: :info | :warning | :critical,
          message: String.t(),
          events: [integer()],
          metadata: map()
        }
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/analyzer_test.exs`

Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add lib/telemetry_capture/analyzer.ex test/telemetry_capture/analyzer_test.exs
git commit -m "feat: add Analyzer behaviour for timeline pattern detection

Defines behaviour for analyzers that detect patterns across complete timelines.
Analyzers are selectively enabled via CLI flags.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Create Registry Module

**Files:**
- Create: `lib/telemetry_capture/registry.ex`
- Test: `test/telemetry_capture/registry_test.exs`

**Step 1: Write the registry test**

```elixir
# test/telemetry_capture/registry_test.exs
defmodule Excessibility.TelemetryCapture.RegistryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Registry

  describe "discover_enrichers/0" do
    test "returns list of enricher modules" do
      enrichers = Registry.discover_enrichers()
      assert is_list(enrichers)
    end
  end

  describe "discover_analyzers/0" do
    test "returns list of analyzer modules" do
      analyzers = Registry.discover_analyzers()
      assert is_list(analyzers)
    end
  end

  describe "get_default_analyzers/0" do
    test "returns only analyzers with default_enabled? = true" do
      defaults = Registry.get_default_analyzers()
      assert is_list(defaults)

      # All returned analyzers should have default_enabled? = true
      Enum.each(defaults, fn analyzer ->
        assert analyzer.default_enabled?() == true
      end)
    end
  end

  describe "get_all_analyzers/0" do
    test "returns all registered analyzers" do
      all = Registry.get_all_analyzers()
      defaults = Registry.get_default_analyzers()

      # All defaults should be in the complete list
      assert Enum.all?(defaults, &(&1 in all))
    end
  end

  describe "get_analyzer/1" do
    test "returns nil for unknown analyzer" do
      assert Registry.get_analyzer(:nonexistent) == nil
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/telemetry_capture/registry_test.exs`

Expected: FAIL with "module Excessibility.TelemetryCapture.Registry is not available"

**Step 3: Write minimal registry implementation**

```elixir
# lib/telemetry_capture/registry.ex
defmodule Excessibility.TelemetryCapture.Registry do
  @moduledoc """
  Registry for enrichers and analyzers.

  Provides auto-discovery and lookup functionality for telemetry
  analysis plugins.

  ## Usage

      # Get all enrichers (run automatically)
      Registry.discover_enrichers()

      # Get analyzers that run by default
      Registry.get_default_analyzers()

      # Get specific analyzer by name
      Registry.get_analyzer(:memory)
  """

  # Hard-coded for initial implementation
  # Future: Could use compile-time discovery via @behaviour inspection
  @enrichers []

  @analyzers []

  @doc """
  Returns all registered enrichers.

  Enrichers run automatically during timeline building.
  """
  def discover_enrichers, do: @enrichers

  @doc """
  Returns all registered analyzers.
  """
  def discover_analyzers, do: @analyzers

  @doc """
  Returns analyzers that are enabled by default.

  These run unless explicitly disabled via --no-analyze flag.
  """
  def get_default_analyzers do
    @analyzers
    |> Enum.filter(& &1.default_enabled?())
  end

  @doc """
  Returns all analyzers regardless of default_enabled? status.
  """
  def get_all_analyzers, do: @analyzers

  @doc """
  Finds analyzer by name.

  Returns nil if not found.
  """
  def get_analyzer(name) do
    Enum.find(@analyzers, fn analyzer ->
      analyzer.name() == name
    end)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/registry_test.exs`

Expected: PASS (5 tests)

**Step 5: Commit**

```bash
git add lib/telemetry_capture/registry.ex test/telemetry_capture/registry_test.exs
git commit -m "feat: add Registry for enricher and analyzer discovery

Provides centralized registration and lookup for analysis plugins.
Currently empty, will be populated with Memory enricher/analyzer.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Create Memory Enricher

**Files:**
- Create: `lib/telemetry_capture/enrichers/memory.ex`
- Test: `test/telemetry_capture/enrichers/memory_test.exs`

**Step 1: Write the enricher test**

```elixir
# test/telemetry_capture/enrichers/memory_test.exs
defmodule Excessibility.TelemetryCapture.Enrichers.MemoryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.Memory

  describe "name/0" do
    test "returns :memory" do
      assert Memory.name() == :memory
    end
  end

  describe "enrich/2" do
    test "returns map with memory_size key" do
      assigns = %{user: "test", count: 5}
      result = Memory.enrich(assigns, [])

      assert is_map(result)
      assert Map.has_key?(result, :memory_size)
      assert is_integer(result.memory_size)
      assert result.memory_size > 0
    end

    test "calculates size for empty assigns" do
      result = Memory.enrich(%{}, [])
      assert result.memory_size > 0
    end

    test "size increases with more data" do
      small = Memory.enrich(%{a: 1}, [])
      large = Memory.enrich(%{a: 1, b: 2, c: 3, d: 4, e: 5}, [])

      assert large.memory_size > small.memory_size
    end

    test "size increases with larger values" do
      small = Memory.enrich(%{text: "hi"}, [])
      large = Memory.enrich(%{text: String.duplicate("x", 1000)}, [])

      assert large.memory_size > small.memory_size
    end

    test "handles nested maps" do
      assigns = %{
        user: %{name: "Alice", age: 30},
        items: [1, 2, 3]
      }

      result = Memory.enrich(assigns, [])
      assert result.memory_size > 0
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/telemetry_capture/enrichers/memory_test.exs`

Expected: FAIL with "module Excessibility.TelemetryCapture.Enrichers.Memory is not available"

**Step 3: Create directory and write implementation**

```bash
mkdir -p lib/telemetry_capture/enrichers
mkdir -p test/telemetry_capture/enrichers
```

```elixir
# lib/telemetry_capture/enrichers/memory.ex
defmodule Excessibility.TelemetryCapture.Enrichers.Memory do
  @behaviour Excessibility.TelemetryCapture.Enricher

  @moduledoc """
  Enriches timeline events with memory size information.

  Calculates the byte size of assigns at each event by serializing
  to binary term format. This gives a proxy for memory usage.

  ## Usage

  Runs automatically during timeline building. Adds `:memory_size`
  field (in bytes) to each timeline event.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:filter",
        memory_size: 45000,
        key_state: %{...}
      }
  """

  @doc """
  Returns the enricher name.
  """
  def name, do: :memory

  @doc """
  Enriches assigns with memory size.

  Serializes assigns to binary format and returns byte size.
  This provides a proxy for memory usage at this event.
  """
  def enrich(assigns, _opts) do
    size = calculate_size(assigns)
    %{memory_size: size}
  end

  defp calculate_size(assigns) do
    assigns
    |> :erlang.term_to_binary()
    |> byte_size()
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/enrichers/memory_test.exs`

Expected: PASS (6 tests)

**Step 5: Register enricher in Registry**

```elixir
# lib/telemetry_capture/registry.ex
# Update @enrichers line:
@enrichers [
  Excessibility.TelemetryCapture.Enrichers.Memory
]
```

**Step 6: Run registry tests to verify**

Run: `mix test test/telemetry_capture/registry_test.exs`

Expected: PASS (5 tests)

**Step 7: Commit**

```bash
git add lib/telemetry_capture/enrichers/memory.ex test/telemetry_capture/enrichers/memory_test.exs lib/telemetry_capture/registry.ex
git commit -m "feat: add Memory enricher for timeline events

Calculates memory size of assigns at each event using term_to_binary.
Registered in Registry for automatic execution during timeline building.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Create Memory Analyzer

**Files:**
- Create: `lib/telemetry_capture/analyzers/memory.ex`
- Test: `test/telemetry_capture/analyzers/memory_test.exs`

**Step 1: Write analyzer tests**

```elixir
# test/telemetry_capture/analyzers/memory_test.exs
defmodule Excessibility.TelemetryCapture.Analyzers.MemoryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.Memory

  describe "name/0" do
    test "returns :memory" do
      assert Memory.name() == :memory
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert Memory.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      timeline = build_timeline([1000, 2000, 3000])
      result = Memory.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
      assert is_list(result.findings)
    end

    test "calculates stats correctly" do
      timeline = build_timeline([1000, 2000, 3000, 4000])
      result = Memory.analyze(timeline, [])

      assert result.stats.min == 1000
      assert result.stats.max == 4000
      assert result.stats.avg == 2500
    end

    test "detects no issues in healthy timeline" do
      timeline = build_timeline([1000, 1100, 1200, 1300])
      result = Memory.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "detects large growth between events" do
      # 10x growth from event 1 to 2
      timeline = build_timeline([1000, 10_000, 11_000])
      result = Memory.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &(&1.severity in [:warning, :critical]))
      assert Enum.any?(result.findings, &String.contains?(&1.message, "grew"))
    end

    test "detects memory leak pattern" do
      # 3+ consecutive increases
      timeline = build_timeline([1000, 2000, 4000, 8000, 16_000])
      result = Memory.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &String.contains?(&1.message, "leak"))
    end

    test "handles single event timeline" do
      timeline = build_timeline([1000])
      result = Memory.analyze(timeline, [])

      assert Enum.empty?(result.findings)
      assert result.stats.min == 1000
      assert result.stats.max == 1000
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}
      result = Memory.analyze(timeline, [])

      assert Enum.empty?(result.findings)
      assert result.stats == %{}
    end
  end

  # Helper to build test timeline
  defp build_timeline(memory_sizes) do
    timeline_entries =
      Enum.with_index(memory_sizes, 1)
      |> Enum.map(fn {size, seq} ->
        %{
          sequence: seq,
          event: "test_event",
          memory_size: size
        }
      end)

    %{timeline: timeline_entries}
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/telemetry_capture/analyzers/memory_test.exs`

Expected: FAIL with "module Excessibility.TelemetryCapture.Analyzers.Memory is not available"

**Step 3: Create directory and write implementation**

```bash
mkdir -p lib/telemetry_capture/analyzers
mkdir -p test/telemetry_capture/analyzers
```

```elixir
# lib/telemetry_capture/analyzers/memory.ex
defmodule Excessibility.TelemetryCapture.Analyzers.Memory do
  @behaviour Excessibility.TelemetryCapture.Analyzer

  @moduledoc """
  Analyzes memory usage patterns across timeline events.

  Detects:
  - Memory bloat (large growth between events)
  - Memory leaks (3+ consecutive increases)

  Uses adaptive thresholds based on timeline statistics to avoid
  false positives and work across different test sizes.

  ## Algorithm

  1. Calculate baseline stats (mean, median, std deviation)
  2. Calculate median delta between events
  3. Detect outliers:
     - Warning: Growth > 3x median delta
     - Critical: Growth > 10x median delta OR size > mean + 2σ
  4. Detect leaks: 3+ consecutive increases

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :warning,
            message: "Memory grew 5.2x between events (45 KB → 234 KB)",
            events: [3, 4],
            metadata: %{growth_multiplier: 5.2, delta_bytes: 189000}
          }
        ],
        stats: %{min: 2300, max: 890000, avg: 145000, median_delta: 12000}
      }
  """

  def name, do: :memory
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    memory_sizes = extract_memory_sizes(timeline)

    stats = calculate_stats(memory_sizes)
    findings = detect_issues(timeline, stats)

    %{
      findings: findings,
      stats: stats
    }
  end

  defp extract_memory_sizes(timeline) do
    Enum.map(timeline, & &1.memory_size)
  end

  defp calculate_stats([]), do: %{}

  defp calculate_stats(sizes) do
    sorted = Enum.sort(sizes)
    count = length(sizes)

    min = List.first(sorted)
    max = List.last(sorted)
    avg = Enum.sum(sizes) / count

    median = calculate_median(sorted)
    std_dev = calculate_std_dev(sizes, avg)

    deltas = calculate_deltas(sizes)
    median_delta = if Enum.empty?(deltas), do: 0, else: calculate_median(Enum.sort(deltas))

    %{
      min: min,
      max: max,
      avg: round(avg),
      median: median,
      std_dev: round(std_dev),
      median_delta: median_delta
    }
  end

  defp calculate_median(sorted_list) do
    count = length(sorted_list)
    mid = div(count, 2)

    if rem(count, 2) == 0 do
      (Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid)) / 2
    else
      Enum.at(sorted_list, mid)
    end
    |> round()
  end

  defp calculate_std_dev(values, mean) do
    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp calculate_deltas(sizes) do
    sizes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> abs(b - a) end)
  end

  defp detect_issues(timeline, stats) when map_size(stats) == 0, do: []

  defp detect_issues(timeline, stats) do
    bloat_findings = detect_bloat(timeline, stats)
    leak_findings = detect_leaks(timeline)

    bloat_findings ++ leak_findings
  end

  defp detect_bloat(timeline, stats) do
    timeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev, curr] ->
      delta = curr.memory_size - prev.memory_size

      cond do
        # Critical: 10x median delta or > mean + 2σ
        delta > stats.median_delta * 10 or curr.memory_size > stats.avg + 2 * stats.std_dev ->
          multiplier = if prev.memory_size > 0, do: delta / prev.memory_size, else: 0

          [
            %{
              severity: :critical,
              message:
                "Memory grew #{format_multiplier(multiplier)}x between events (#{format_bytes(prev.memory_size)} → #{format_bytes(curr.memory_size)})",
              events: [prev.sequence, curr.sequence],
              metadata: %{growth_multiplier: Float.round(multiplier, 1), delta_bytes: delta}
            }
          ]

        # Warning: 3x median delta
        delta > stats.median_delta * 3 ->
          multiplier = if prev.memory_size > 0, do: delta / prev.memory_size, else: 0

          [
            %{
              severity: :warning,
              message:
                "Memory grew #{format_multiplier(multiplier)}x between events (#{format_bytes(prev.memory_size)} → #{format_bytes(curr.memory_size)})",
              events: [prev.sequence, curr.sequence],
              metadata: %{growth_multiplier: Float.round(multiplier, 1), delta_bytes: delta}
            }
          ]

        true ->
          []
      end
    end)
  end

  defp detect_leaks(timeline) do
    timeline
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.flat_map(fn chunk ->
      if consecutive_increases?(chunk) do
        sequences = Enum.map(chunk, & &1.sequence)
        sizes = Enum.map(chunk, & &1.memory_size)

        [
          %{
            severity: :critical,
            message:
              "Possible memory leak: consecutive growth in events #{Enum.join(sequences, ", ")} (#{Enum.map_join(sizes, " → ", &format_bytes/1)})",
            events: sequences,
            metadata: %{sizes: sizes}
          }
        ]
      else
        []
      end
    end)
  end

  defp consecutive_increases?([a, b, c]) do
    a.memory_size < b.memory_size and b.memory_size < c.memory_size
  end

  defp format_multiplier(mult) when mult >= 1, do: Float.round(mult, 1)
  defp format_multiplier(mult), do: Float.round(mult, 2)

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/analyzers/memory_test.exs`

Expected: PASS (9 tests)

**Step 5: Register analyzer in Registry**

```elixir
# lib/telemetry_capture/registry.ex
# Update @analyzers line:
@analyzers [
  Excessibility.TelemetryCapture.Analyzers.Memory
]
```

**Step 6: Run registry tests to verify**

Run: `mix test test/telemetry_capture/registry_test.exs`

Expected: PASS (5 tests) - now get_default_analyzers returns Memory

**Step 7: Commit**

```bash
git add lib/telemetry_capture/analyzers/memory.ex test/telemetry_capture/analyzers/memory_test.exs lib/telemetry_capture/registry.ex
git commit -m "feat: add Memory analyzer for detecting bloat and leaks

Detects memory bloat (3x+ growth) and leaks (consecutive increases)
using adaptive thresholds. Registered as default analyzer in Registry.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Integrate Enrichers into Timeline

**Files:**
- Modify: `lib/telemetry_capture/timeline.ex`
- Test: `test/telemetry_capture/timeline_test.exs`

**Step 1: Write integration test**

Add to existing `test/telemetry_capture/timeline_test.exs`:

```elixir
describe "enricher integration" do
  test "build_timeline_entry includes enriched data" do
    snapshot = %{
      event_type: "mount",
      assigns: %{user: "test", count: 5},
      timestamp: ~U[2024-01-01 00:00:00Z],
      view_module: TestModule
    }

    entry = Timeline.build_timeline_entry(snapshot, nil, 1, [])

    # Should have memory_size from Memory enricher
    assert Map.has_key?(entry, :memory_size)
    assert is_integer(entry.memory_size)
    assert entry.memory_size > 0
  end

  test "enrichments are merged with timeline entry" do
    snapshot = %{
      event_type: "handle_event:click",
      assigns: %{data: "value"},
      timestamp: ~U[2024-01-01 00:00:01Z],
      view_module: TestModule
    }

    entry = Timeline.build_timeline_entry(snapshot, nil, 2, [])

    # Original fields still present
    assert entry.sequence == 2
    assert entry.event == "handle_event:click"
    assert entry.view_module == TestModule

    # Enriched field added
    assert Map.has_key?(entry, :memory_size)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/telemetry_capture/timeline_test.exs`

Expected: FAIL - enriched data not present in timeline entry

**Step 3: Add enricher integration to Timeline**

```elixir
# lib/telemetry_capture/timeline.ex
# Add alias at top of file
alias Excessibility.TelemetryCapture.Registry

# Modify build_timeline_entry function (around line 94)
def build_timeline_entry(snapshot, previous, sequence, opts \\ []) do
  filtered_assigns = Filter.filter_assigns(snapshot.assigns, opts)

  key_state =
    extract_key_state(filtered_assigns, opts[:highlight_fields] || @default_highlight_fields)

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

  # NEW: Run enrichers
  enrichments = run_enrichers(filtered_assigns, opts)

  %{
    sequence: sequence,
    event: snapshot.event_type,
    timestamp: snapshot.timestamp,
    view_module: snapshot.view_module,
    key_state: key_state,
    changes: changes,
    duration_since_previous_ms: duration_since_previous
  }
  |> Map.merge(enrichments)
end

# NEW: Add helper function
defp run_enrichers(assigns, opts) do
  enrichers = Registry.discover_enrichers()

  Enum.reduce(enrichers, %{}, fn enricher, acc ->
    enrichment = enricher.enrich(assigns, opts)
    Map.merge(acc, enrichment)
  end)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/timeline_test.exs`

Expected: PASS (all tests including new enricher integration tests)

**Step 5: Commit**

```bash
git add lib/telemetry_capture/timeline.ex test/telemetry_capture/timeline_test.exs
git commit -m "feat: integrate enrichers into timeline building

Timeline.build_timeline_entry now runs all registered enrichers
and merges their results into timeline events.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Add Formatter Support for Analysis Results

**Files:**
- Modify: `lib/telemetry_capture/formatter.ex`
- Test: `test/telemetry_capture/formatter_test.exs`

**Step 1: Write formatter tests**

Add to existing `test/telemetry_capture/formatter_test.exs`:

```elixir
describe "format_analysis_results/2" do
  test "formats empty results" do
    result = Formatter.format_analysis_results(%{}, [])
    assert result == ""
  end

  test "formats healthy analyzer result" do
    results = %{
      memory: %{
        findings: [],
        stats: %{min: 1000, max: 5000, avg: 3000}
      }
    }

    output = Formatter.format_analysis_results(results, [])

    assert output =~ "## Memory Analysis ✅"
    assert output =~ "1000"
    assert output =~ "5000"
  end

  test "formats analyzer with findings" do
    results = %{
      memory: %{
        findings: [
          %{
            severity: :warning,
            message: "Memory grew 5x",
            events: [1, 2],
            metadata: %{}
          }
        ],
        stats: %{min: 1000, max: 10_000}
      }
    }

    output = Formatter.format_analysis_results(results, [])

    assert output =~ "## Memory Analysis"
    refute output =~ "✅"
    assert output =~ "⚠️"
    assert output =~ "Memory grew 5x"
  end

  test "formats critical findings" do
    results = %{
      memory: %{
        findings: [
          %{
            severity: :critical,
            message: "Memory leak detected",
            events: [1, 2, 3],
            metadata: %{}
          }
        ],
        stats: %{}
      }
    }

    output = Formatter.format_analysis_results(results, [])

    assert output =~ "🔴"
    assert output =~ "Memory leak detected"
  end

  test "verbose mode shows detailed stats" do
    results = %{
      memory: %{
        findings: [],
        stats: %{min: 1000, max: 5000, avg: 3000, median: 2500}
      }
    }

    brief = Formatter.format_analysis_results(results, verbose: false)
    verbose = Formatter.format_analysis_results(results, verbose: true)

    assert String.length(verbose) > String.length(brief)
    assert verbose =~ "median"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/telemetry_capture/formatter_test.exs`

Expected: FAIL - format_analysis_results/2 not defined

**Step 3: Implement formatter functions**

```elixir
# lib/telemetry_capture/formatter.ex
# Add new functions to the module

@doc """
Formats analysis results as markdown.

Takes map of analyzer_name => %{findings: [...], stats: %{...}}
and produces formatted markdown sections.

## Options

- `:verbose` - Include detailed stats even when no issues found (default: false)
"""
def format_analysis_results(analysis_results, opts \\ []) when map_size(analysis_results) == 0 do
  ""
end

def format_analysis_results(analysis_results, opts) do
  verbose? = Keyword.get(opts, :verbose, false)

  analysis_results
  |> Enum.map(fn {name, result} ->
    format_analyzer_section(name, result, verbose?)
  end)
  |> Enum.reject(&(&1 == ""))
  |> Enum.join("\n\n")
end

defp format_analyzer_section(name, %{findings: findings, stats: stats}, verbose?) do
  title = name |> to_string() |> String.capitalize()

  if Enum.empty?(findings) do
    format_healthy_section(title, stats, verbose?)
  else
    format_findings_section(title, findings, stats)
  end
end

defp format_healthy_section(title, stats, verbose?) do
  summary = format_summary_stats(stats)

  basic = "## #{title} Analysis ✅\n#{summary}"

  if verbose? and map_size(stats) > 0 do
    basic <> "\n\n" <> format_detailed_stats(stats)
  else
    basic
  end
end

defp format_findings_section(title, findings, stats) do
  findings_text = format_findings(findings)
  summary = if map_size(stats) > 0, do: "\n\n#{format_summary_stats(stats)}", else: ""

  "## #{title} Analysis\n#{findings_text}#{summary}"
end

defp format_findings(findings) do
  Enum.map_join(findings, "\n", fn finding ->
    emoji =
      case finding.severity do
        :critical -> "🔴"
        :warning -> "⚠️"
        :info -> "ℹ️"
      end

    "#{emoji} #{finding.message}"
  end)
end

defp format_summary_stats(stats) when map_size(stats) == 0, do: ""

defp format_summary_stats(stats) do
  parts = []

  parts =
    if stats[:min] && stats[:max] do
      ["Memory range: #{format_bytes(stats.min)} → #{format_bytes(stats.max)}" | parts]
    else
      parts
    end

  parts =
    if stats[:avg] do
      last = List.first(parts, "")
      updated = last <> " (avg: #{format_bytes(stats.avg)})"
      [updated | List.delete(parts, last)]
    else
      parts
    end

  Enum.join(parts, "\n")
end

defp format_detailed_stats(stats) do
  [
    "**Detailed Statistics:**",
    "- Min: #{format_bytes(stats[:min] || 0)}",
    "- Max: #{format_bytes(stats[:max] || 0)}",
    "- Average: #{format_bytes(stats[:avg] || 0)}",
    if(stats[:median], do: "- Median: #{format_bytes(stats.median)}", else: nil),
    if(stats[:std_dev], do: "- Std Dev: #{format_bytes(stats.std_dev)}", else: nil),
    if(stats[:median_delta], do: "- Median Delta: #{format_bytes(stats.median_delta)}", else: nil)
  ]
  |> Enum.reject(&is_nil/1)
  |> Enum.join("\n")
end

defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
```

**Step 4: Run test to verify it passes**

Run: `mix test test/telemetry_capture/formatter_test.exs`

Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/telemetry_capture/formatter.ex test/telemetry_capture/formatter_test.exs
git commit -m "feat: add analysis results formatting to Formatter

Supports formatting analyzer findings and stats as markdown with
emoji indicators for severity levels and verbose mode for details.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Integrate Analyzers into Debug Task

**Files:**
- Modify: `lib/mix/tasks/excessibility_debug.ex`

**Step 1: Add analyzer integration code**

Find the `run/1` function and modify:

```elixir
# lib/mix/tasks/excessibility_debug.ex

# Update the @moduledoc to document new flags:
@moduledoc """
...existing docs...

## Analysis Options

  --analyze=NAMES       Run specific analyzers (comma-separated)
                        Available: memory
                        Default: memory
  --analyze=all         Run all available analyzers
  --no-analyze          Skip analysis, show timeline only
  --verbose             Show detailed stats even when no issues found
"""

# Update OptionParser.parse in run/1 to add new flags:
def run(args) do
  {opts, test_paths, _} =
    OptionParser.parse(args,
      strict: [
        format: :string,
        full: :boolean,
        minimal: :boolean,
        no_filter_ecto: :boolean,
        no_filter_phoenix: :boolean,
        highlight: :string,
        analyze: :string,          # NEW
        no_analyze: :boolean,       # NEW
        verbose: :boolean           # NEW
      ],
      aliases: [f: :format]
    )

  # ... existing code ...
end

# Add new helper functions after output_package/1:

defp parse_analyzer_selection(opts) do
  alias Excessibility.TelemetryCapture.Registry

  cond do
    Keyword.get(opts, :no_analyze) ->
      []

    analyze = Keyword.get(opts, :analyze) ->
      case analyze do
        "all" ->
          Registry.get_all_analyzers() |> Enum.map(& &1.name())

        names_str ->
          names_str
          |> String.split(",")
          |> Enum.map(&String.to_atom/1)
      end

    true ->
      Registry.get_default_analyzers() |> Enum.map(& &1.name())
  end
end

defp run_analyzers(timeline, analyzer_names, opts) do
  alias Excessibility.TelemetryCapture.Registry

  analyzer_names
  |> Enum.map(&Registry.get_analyzer/1)
  |> Enum.reject(&is_nil/1)
  |> Enum.map(fn analyzer ->
    {analyzer.name(), analyzer.analyze(timeline, opts)}
  end)
  |> Map.new()
end

# Modify output_markdown/1 to include analysis:
defp output_markdown(report_data) do
  output_path =
    Application.get_env(
      :excessibility,
      :excessibility_output_path,
      "test/excessibility"
    )

  timeline_path = Path.join(output_path, "timeline.json")

  # NEW: Get opts from process dictionary
  debug_opts = Process.get(:excessibility_debug_opts, %{})
  opts = Map.get(debug_opts, :filter_opts, [])

  # NEW: Run analyzers if timeline exists
  {markdown, analysis_results} =
    if File.exists?(timeline_path) do
      timeline = timeline_path |> File.read!() |> Jason.decode!(keys: :atoms)

      # Run analyzers
      analyzer_names = parse_analyzer_selection(opts)
      analysis_results = run_analyzers(timeline, analyzer_names, opts)

      # Build markdown with analysis
      base_markdown = Formatter.format_markdown(timeline, report_data.snapshots)
      analysis_markdown = Formatter.format_analysis_results(analysis_results, opts)

      combined =
        if analysis_markdown != "" do
          base_markdown <> "\n\n---\n\n# Analysis Results\n\n" <> analysis_markdown
        else
          base_markdown
        end

      {combined, analysis_results}
    else
      {build_markdown_report(report_data), %{}}
    end

  # Output to stdout
  Mix.shell().info(markdown)

  # Save to file
  latest_path = Path.join(output_path, "latest_debug.md")
  File.mkdir_p!(output_path)
  File.write!(latest_path, markdown)

  Mix.shell().info("\n📋 Report saved to: #{latest_path}")
  Mix.shell().info("💡 Paste the above to Claude, or tell Claude to read #{latest_path}")
end
```

**Step 2: Run mix compile to verify no syntax errors**

Run: `mix compile`

Expected: SUCCESS (no warnings or errors)

**Step 3: Test manually with a real test file**

Create a simple test file for manual testing:

```elixir
# test/analyzer_integration_test.exs
defmodule AnalyzerIntegrationTest do
  use ExUnit.Case

  # This test is just for manual verification of analyzer integration
  # Run with: mix excessibility.debug test/analyzer_integration_test.exs
  test "placeholder for manual analyzer testing" do
    assert true
  end
end
```

Run: `mix excessibility.debug test/analyzer_integration_test.exs`

Expected: Debug output with "Analysis Results" section (even if empty due to no telemetry)

**Step 4: Commit**

```bash
git add lib/mix/tasks/excessibility_debug.ex
git commit -m "feat: integrate analyzers into debug task

Adds --analyze, --no-analyze, and --verbose flags to debug task.
Analyzers run after timeline generation and results appear in
markdown output under 'Analysis Results' section.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Integration Testing

**Files:**
- Create: `test/integration/telemetry_analysis_test.exs`

**Step 1: Write end-to-end integration test**

```elixir
# test/integration/telemetry_analysis_test.exs
defmodule Integration.TelemetryAnalysisTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.{Timeline, Registry}
  alias Excessibility.TelemetryCapture.Formatter

  describe "end-to-end telemetry analysis flow" do
    test "enrichers add data to timeline events" do
      snapshots = [
        build_snapshot("mount", %{user: "alice"}),
        build_snapshot("handle_event:click", %{user: "alice", data: String.duplicate("x", 1000)})
      ]

      timeline = Timeline.build_timeline(snapshots, "test", [])

      # Verify enrichments are present
      assert Enum.all?(timeline.timeline, &Map.has_key?(&1, :memory_size))

      # Second event should have larger memory
      [event1, event2] = timeline.timeline
      assert event2.memory_size > event1.memory_size
    end

    test "analyzers detect issues in timeline" do
      # Create timeline with deliberate memory bloat
      snapshots =
        Enum.map(1..5, fn i ->
          size = if i == 3, do: 10_000, else: 100
          assigns = %{data: String.duplicate("x", size)}
          build_snapshot("event_#{i}", assigns)
        end)

      timeline = Timeline.build_timeline(snapshots, "test", [])

      # Run memory analyzer
      memory_analyzer = Registry.get_analyzer(:memory)
      result = memory_analyzer.analyze(timeline, [])

      # Should detect the bloat at event 3
      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &String.contains?(&1.message, "grew"))
    end

    test "formatter produces markdown from analysis results" do
      results = %{
        memory: %{
          findings: [
            %{
              severity: :warning,
              message: "Memory grew 10x",
              events: [1, 2],
              metadata: %{}
            }
          ],
          stats: %{min: 100, max: 1000, avg: 550}
        }
      }

      markdown = Formatter.format_analysis_results(results, [])

      assert markdown =~ "## Memory Analysis"
      assert markdown =~ "⚠️"
      assert markdown =~ "Memory grew 10x"
      assert markdown =~ "100 B"
      assert markdown =~ "1000 B"
    end

    test "complete flow: snapshots -> timeline -> analysis -> markdown" do
      # Build snapshots with memory leak pattern
      snapshots =
        [100, 200, 400, 800, 1600]
        |> Enum.with_index(1)
        |> Enum.map(fn {size, i} ->
          build_snapshot("event_#{i}", %{data: String.duplicate("x", size)})
        end)

      # Build timeline (enrichers run automatically)
      timeline = Timeline.build_timeline(snapshots, "leak_test", [])

      # Run analyzers
      analyzers = Registry.get_default_analyzers()

      analysis_results =
        analyzers
        |> Enum.map(fn analyzer ->
          {analyzer.name(), analyzer.analyze(timeline, [])}
        end)
        |> Map.new()

      # Format results
      markdown = Formatter.format_analysis_results(analysis_results, [])

      # Verify leak detected
      assert markdown =~ "Memory Analysis"
      assert markdown =~ "leak"
      assert markdown =~ "🔴"
    end
  end

  defp build_snapshot(event_type, assigns) do
    %{
      event_type: event_type,
      assigns: assigns,
      timestamp: DateTime.utc_now(),
      view_module: TestModule
    }
  end
end
```

**Step 2: Create integration test directory**

```bash
mkdir -p test/integration
```

**Step 3: Run integration tests**

Run: `mix test test/integration/telemetry_analysis_test.exs`

Expected: PASS (4 tests)

**Step 4: Run full test suite**

Run: `mix test`

Expected: ALL PASS

**Step 5: Commit**

```bash
git add test/integration/telemetry_analysis_test.exs
git commit -m "test: add integration tests for telemetry analysis

Tests complete flow from snapshots through enrichment, analysis,
and markdown formatting. Verifies memory leak detection works E2E.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 10: Documentation and Polish

**Files:**
- Update: `CLAUDE.md`
- Create: `docs/telemetry-analysis.md`

**Step 1: Document new features in CLAUDE.md**

Add to the "Timeline Analysis" section:

```markdown
### Timeline Analysis

The telemetry capture automatically generates `timeline.json` for each test run:

```bash
# Run test with telemetry capture
mix test test/my_live_view_test.exs

# View timeline
cat test/excessibility/timeline.json

# Generate debug report with analysis
mix excessibility.debug test/my_live_view_test.exs

# Run specific analyzers
mix excessibility.debug test/my_live_view_test.exs --analyze=memory

# Skip analysis
mix excessibility.debug test/my_live_view_test.exs --no-analyze

# Verbose output
mix excessibility.debug test/my_live_view_test.exs --verbose
```

**Available Analyzers:**

- `memory` - Detects memory bloat and leaks using adaptive thresholds (enabled by default)

**Timeline Enrichments:**

Timeline events are automatically enriched with:
- `memory_size` - Byte size of assigns at each event

**Creating Custom Enrichers:**

```elixir
defmodule MyApp.CustomEnricher do
  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :custom

  def enrich(assigns, _opts) do
    %{custom_field: compute_value(assigns)}
  end
end

# Register in Registry
# lib/telemetry_capture/registry.ex
@enrichers [
  Excessibility.TelemetryCapture.Enrichers.Memory,
  MyApp.CustomEnricher
]
```

**Creating Custom Analyzers:**

```elixir
defmodule MyApp.CustomAnalyzer do
  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :custom
  def default_enabled?, do: false

  def analyze(timeline, _opts) do
    %{
      findings: [...],
      stats: %{...}
    }
  end
end

# Register in Registry
# lib/telemetry_capture/registry.ex
@analyzers [
  Excessibility.TelemetryCapture.Analyzers.Memory,
  MyApp.CustomAnalyzer
]
```
```

**Step 2: Create comprehensive documentation**

```markdown
# docs/telemetry-analysis.md
# Telemetry Analysis Framework

The telemetry analysis framework provides extensible enrichment and pattern detection for LiveView test snapshots.

## Architecture

The framework has two plugin types:

### Enrichers

**Purpose:** Add computed data to timeline events during timeline building.

**When they run:** Automatically for every event during `Timeline.build_timeline`.

**Output:** Map of fields to merge into timeline event (e.g., `%{memory_size: 45000}`).

**Example:**
```elixir
defmodule MyEnricher do
  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :my_enricher

  def enrich(assigns, _opts) do
    %{my_field: compute_value(assigns)}
  end
end
```

### Analyzers

**Purpose:** Detect patterns across complete timelines.

**When they run:** After timeline completion, invoked by `mix excessibility.debug`.

**Output:** Map with `:findings` (list of issues) and `:stats` (summary data).

**Example:**
```elixir
defmodule MyAnalyzer do
  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :my_analyzer
  def default_enabled?, do: true

  def analyze(timeline, _opts) do
    %{
      findings: detect_issues(timeline),
      stats: calculate_stats(timeline)
    }
  end
end
```

## Built-in Plugins

### Memory Enricher

Adds `memory_size` (bytes) to each timeline event by serializing assigns.

**Algorithm:** Uses `:erlang.term_to_binary()` to calculate byte size.

**Output:**
```json
{
  "sequence": 3,
  "event": "handle_event:filter",
  "memory_size": 45000
}
```

### Memory Analyzer

Detects memory bloat and leaks using adaptive thresholds.

**Detects:**
- Large growth between events (>3x median delta = warning, >10x = critical)
- Memory leaks (3+ consecutive increases)

**Adaptive thresholds:**
- Calculates baseline stats (mean, median, std dev) from timeline
- Thresholds adapt to test size (works for KB and MB ranges)
- Avoids false positives from expected data loading

**Example output:**
```markdown
## Memory Analysis
⚠️  Memory grew 5.2x between events 3-4 (45 KB → 234 KB)
🔴 Possible memory leak: consecutive growth in events 5, 6, 7

Memory range: 2.3 KB → 890 KB (avg: 145 KB)
```

## CLI Usage

### Basic Analysis

```bash
# Run with default analyzers (currently: memory)
mix excessibility.debug test/my_test.exs
```

### Selective Analysis

```bash
# Run specific analyzer
mix excessibility.debug test/my_test.exs --analyze=memory

# Run all analyzers
mix excessibility.debug test/my_test.exs --analyze=all

# Skip analysis
mix excessibility.debug test/my_test.exs --no-analyze
```

### Verbose Output

```bash
# Show detailed stats even when no issues found
mix excessibility.debug test/my_test.exs --verbose
```

## Extending the Framework

### Creating a Custom Enricher

1. **Implement the behaviour:**

```elixir
# lib/my_app/enrichers/query.ex
defmodule MyApp.Enrichers.Query do
  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :query

  def enrich(assigns, _opts) do
    query_count = count_ecto_records(assigns)
    %{query_count: query_count}
  end

  defp count_ecto_records(assigns) do
    # Implementation...
  end
end
```

2. **Register in Registry:**

```elixir
# lib/telemetry_capture/registry.ex
@enrichers [
  Excessibility.TelemetryCapture.Enrichers.Memory,
  MyApp.Enrichers.Query  # Add your enricher
]
```

3. **Write tests:**

```elixir
# test/my_app/enrichers/query_test.exs
test "counts Ecto records" do
  assigns = %{users: [%User{}, %User{}]}
  result = MyApp.Enrichers.Query.enrich(assigns, [])

  assert result.query_count == 2
end
```

### Creating a Custom Analyzer

1. **Implement the behaviour:**

```elixir
# lib/my_app/analyzers/state_machine.ex
defmodule MyApp.Analyzers.StateMachine do
  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :state_machine
  def default_enabled?, do: false

  def analyze(timeline, _opts) do
    transitions = detect_transitions(timeline)

    %{
      findings: find_issues(transitions),
      stats: %{transition_count: length(transitions)}
    }
  end
end
```

2. **Register in Registry:**

```elixir
# lib/telemetry_capture/registry.ex
@analyzers [
  Excessibility.TelemetryCapture.Analyzers.Memory,
  MyApp.Analyzers.StateMachine  # Add your analyzer
]
```

3. **Write tests:**

```elixir
test "detects state transitions" do
  timeline = build_timeline_with_states()
  result = MyApp.Analyzers.StateMachine.analyze(timeline, [])

  assert result.stats.transition_count > 0
end
```

## Future Extensions

The framework is designed to support:

**Additional Enrichers:**
- Query counting (Ecto record counts, NotLoaded detection)
- State extraction (status, mode, step fields)
- Permission tracking (current_user, roles)

**Additional Analyzers:**
- N+1 query detection
- State machine visualization
- Permission escalation detection
- PII leak scanning
- Mermaid diagram generation

See design document for detailed roadmap.
```

**Step 3: Run linter**

Run: `mix credo`

Expected: No issues (or only low-priority suggestions)

**Step 4: Run formatter**

Run: `mix format`

Expected: All files formatted

**Step 5: Commit**

```bash
git add CLAUDE.md docs/telemetry-analysis.md
git commit -m "docs: document telemetry analysis framework

Adds comprehensive documentation for enrichers and analyzers including
usage examples, extension guide, and CLI reference.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 11: Final Verification

**Step 1: Run full test suite**

Run: `mix test`

Expected: ALL PASS

**Step 2: Run linter**

Run: `mix credo`

Expected: No issues

**Step 3: Verify enrichments in timeline.json**

Create a test LiveView test (or use existing) and verify timeline.json contains memory_size:

```bash
mix test test/live_view_test.exs
cat test/excessibility/timeline.json | grep memory_size
```

Expected: Timeline events have `"memory_size": <number>` fields

**Step 4: Verify analyzer output**

```bash
mix excessibility.debug test/live_view_test.exs
```

Expected: Output includes "## Memory Analysis" section

**Step 5: Test CLI flags**

```bash
# Test --analyze flag
mix excessibility.debug test/live_view_test.exs --analyze=memory

# Test --no-analyze flag
mix excessibility.debug test/live_view_test.exs --no-analyze

# Test --verbose flag
mix excessibility.debug test/live_view_test.exs --verbose
```

Expected: All flags work as documented

**Step 6: Final commit**

```bash
git add .
git commit -m "chore: final verification and cleanup

All tests passing, linter clean, documentation complete.
Framework ready for use and extension.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Success Criteria Checklist

Verify all criteria from design document:

- [ ] Memory enricher adds `memory_size` to all timeline events
- [ ] Memory analyzer detects 10x memory growth with adaptive thresholds
- [ ] Memory analyzer detects memory leaks (3+ consecutive increases)
- [ ] CLI flags (`--analyze`, `--no-analyze`, `--verbose`) work correctly
- [ ] Analysis results appear in markdown output with appropriate formatting
- [ ] No issues with healthy timelines show brief confirmation message
- [ ] Framework enables adding new enrichers/analyzers without modifying core code
- [ ] All tests pass, code coverage maintained
- [ ] Documentation explains how to create custom enrichers/analyzers

---

## Implementation Notes

**Dependencies:**
- No new external dependencies required
- Uses existing: Jason (JSON), ExUnit (testing), Mix (tasks)

**Testing strategy:**
- Unit tests for each module (enrichers, analyzers, registry, formatter)
- Integration tests for end-to-end flow
- Manual verification with real tests

**DRY principles:**
- Behaviours eliminate duplication in plugin implementations
- Registry centralizes discovery logic
- Formatter handles all markdown generation

**YAGNI principles:**
- Hard-coded registry (no complex discovery yet)
- Simple adaptive thresholds (no configuration needed)
- Single enricher and analyzer (more added as needed)

**TDD workflow:**
- Test first for every component
- Red-green-refactor cycle throughout
- Integration tests verify end-to-end functionality
