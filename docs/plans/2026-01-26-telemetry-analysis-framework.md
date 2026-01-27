# Telemetry Analysis Framework Design

**Date:** 2026-01-26
**Status:** Approved
**Scope:** Add extensible enrichment and analysis capabilities to telemetry capture system

---

## Overview

Extend the existing telemetry capture system with a modular plugin architecture for:
- **Enrichers**: Add computed data to timeline events (memory size, query counts, etc.)
- **Analyzers**: Detect patterns across complete timelines (memory leaks, N+1 queries, state machines, etc.)

This design focuses on building the framework + one complete example of each (Memory enricher + Memory analyzer) to prove the architecture.

---

## Architecture

### Two Plugin Types

**Enrichers** run during timeline building to add computed data to each event:
- Input: Single event's assigns
- Output: Map of additional fields (e.g., `%{memory_size: 45000}`)
- Execution: Called by `Timeline.build_timeline_entry` for each event
- Data persistence: Results saved in `timeline.json`
- Discovery: Auto-discovered via behaviour, all run automatically

**Analyzers** run after timeline completion to detect patterns:
- Input: Complete timeline with all events
- Output: Structured findings (warnings, stats, recommendations)
- Execution: Called by `mix excessibility.debug` after timeline generation
- Data persistence: Results added to markdown report
- Discovery: Registered but selectively enabled via CLI flags

### Data Flow

```
Telemetry events → Timeline building → Enrichers add data → timeline.json
                                                           ↓
                                    CLI invokes Analyzers → Structured results
                                                           ↓
                                    Formatter → Markdown report
```

---

## Behaviour Definitions

### Enricher Behaviour

```elixir
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
  """

  @callback enrich(assigns :: map(), opts :: keyword()) :: map()
  @callback name() :: atom()
end
```

### Analyzer Behaviour

```elixir
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
  """

  @callback analyze(timeline :: map(), opts :: keyword()) :: analysis_result()
  @callback name() :: atom()
  @callback default_enabled?() :: boolean()

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

---

## Initial Implementation: Memory Enricher

### Memory Enricher

**File:** `lib/telemetry_capture/enrichers/memory.ex`

Adds `:memory_size` (bytes) to each timeline event by serializing assigns.

```elixir
defmodule Excessibility.TelemetryCapture.Enrichers.Memory do
  @behaviour Excessibility.TelemetryCapture.Enricher

  @moduledoc """
  Enriches timeline events with memory size information.

  Calculates the byte size of assigns at each event by serializing
  to binary term format. This gives a proxy for memory usage.
  """

  def name, do: :memory

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

**Key decisions:**
- Uses `:erlang.term_to_binary()` for size calculation (standard Erlang approach)
- Returns size in bytes (easier to work with programmatically)
- Simple, fast, no external dependencies (~microseconds per event)
- Always runs automatically (cheap operation)

**Added to timeline.json:**
```json
{
  "sequence": 3,
  "event": "handle_event:filter",
  "memory_size": 45000,
  "key_state": {...}
}
```

---

## Initial Implementation: Memory Analyzer

### Memory Analyzer

**File:** `lib/telemetry_capture/analyzers/memory.ex`

Detects memory bloat and leaks using adaptive thresholds based on timeline statistics.

**Algorithm:**
1. Extract all memory sizes from timeline events
2. Calculate baseline statistics:
   - Mean, median, standard deviation
   - Median delta (change between consecutive events)
3. Detect outliers:
   - **Warning**: Growth > 3x median delta between events
   - **Critical**: Growth > 10x median delta OR absolute size > mean + 2 std deviations
4. Detect leaks: 3+ consecutive events with increasing memory

**Why adaptive thresholds?**
- Works for both small tests (KB range) and large ones (MB range)
- Learns what's "normal" for each specific test
- Avoids false positives from expected data loading

**Output structure:**
```elixir
%{
  findings: [
    %{
      severity: :warning,
      message: "Memory grew 5.2x between events (45 KB → 234 KB)",
      events: [3, 4],
      metadata: %{growth_multiplier: 5.2, delta_bytes: 189000}
    },
    %{
      severity: :critical,
      message: "Possible memory leak: 3 consecutive increases",
      events: [5, 6, 7],
      metadata: %{sizes: [234000, 456000, 890000]}
    }
  ],
  stats: %{
    min: 2300,
    max: 890000,
    avg: 145000,
    median_delta: 12000
  }
}
```

**Markdown output (no issues):**
```markdown
## Memory Analysis ✅
No issues detected. Memory range: 2.3 KB → 45 KB
```

**Markdown output (with issues):**
```markdown
## Memory Analysis
⚠️  Memory grew 5.2x between events 3-4 (45 KB → 234 KB)
🔴 Possible memory leak: consecutive growth in events 5, 6, 7 (234 KB → 456 KB → 890 KB)

Memory range: 2.3 KB → 890 KB (avg: 145 KB)
```

---

## Integration Points

### Timeline Integration

**Modify:** `lib/telemetry_capture/timeline.ex`

Add enricher execution to `build_timeline_entry/4`:

```elixir
def build_timeline_entry(snapshot, previous, sequence, opts \\ []) do
  filtered_assigns = Filter.filter_assigns(snapshot.assigns, opts)

  # Existing logic
  key_state = extract_key_state(filtered_assigns, ...)
  diff = Diff.compute_diff(filtered_assigns, previous_assigns)
  changes = Diff.extract_changes(diff)

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
  |> Map.merge(enrichments)  # Add enriched data
end

defp run_enrichers(assigns, opts) do
  enrichers = Registry.discover_enrichers()

  Enum.reduce(enrichers, %{}, fn enricher, acc ->
    Map.merge(acc, enricher.enrich(assigns, opts))
  end)
end
```

### Analyzer Integration

**Modify:** `lib/mix/tasks/excessibility_debug.ex`

Add analyzer invocation after timeline generation:

```elixir
def run(args) do
  # Parse new flags
  {opts, test_paths, _} = OptionParser.parse(args,
    strict: [
      # ... existing flags ...
      analyze: :string,
      no_analyze: :boolean,
      verbose: :boolean
    ]
  )

  # ... existing test execution ...

  # NEW: Run analyzers
  timeline = load_timeline()
  analyzer_names = parse_analyzer_selection(opts)
  analysis_results = run_analyzers(timeline, analyzer_names, opts)

  # Generate report with analysis results
  output_markdown(report_data, analysis_results)
end

defp parse_analyzer_selection(opts) do
  cond do
    Keyword.get(opts, :no_analyze) -> []
    analyze = Keyword.get(opts, :analyze) ->
      case analyze do
        "all" -> Registry.get_all_analyzers()
        names_str ->
          names_str
          |> String.split(",")
          |> Enum.map(&String.to_atom/1)
      end
    true -> Registry.get_default_analyzers()
  end
end

defp run_analyzers(timeline, analyzer_names, opts) do
  analyzer_names
  |> Enum.map(&Registry.get_analyzer/1)
  |> Enum.map(fn analyzer ->
    {analyzer.name(), analyzer.analyze(timeline, opts)}
  end)
  |> Map.new()
end
```

### Registry Module

**New file:** `lib/telemetry_capture/registry.ex`

Handles discovery and registration of enrichers and analyzers:

```elixir
defmodule Excessibility.TelemetryCapture.Registry do
  @moduledoc """
  Registry for enrichers and analyzers.

  Provides auto-discovery and lookup functionality.
  """

  # Hard-coded for initial implementation
  # Future: Could use compile-time discovery via @behaviour inspection
  @enrichers [
    Excessibility.TelemetryCapture.Enrichers.Memory
  ]

  @analyzers [
    Excessibility.TelemetryCapture.Analyzers.Memory
  ]

  def discover_enrichers, do: @enrichers

  def discover_analyzers, do: @analyzers

  def get_default_analyzers do
    @analyzers
    |> Enum.filter(& &1.default_enabled?())
  end

  def get_all_analyzers, do: @analyzers

  def get_analyzer(name) do
    Enum.find(@analyzers, fn analyzer ->
      analyzer.name() == name
    end)
  end
end
```

### Formatter Integration

**Modify:** `lib/telemetry_capture/formatter.ex`

Add function to format analysis results to markdown:

```elixir
def format_analysis_results(analysis_results, opts \\ []) do
  verbose? = Keyword.get(opts, :verbose, false)

  analysis_results
  |> Enum.map(fn {name, result} ->
    format_analyzer_section(name, result, verbose?)
  end)
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
  basic = "## #{title} Analysis ✅\n#{format_summary_stats(stats)}"

  if verbose? do
    basic <> "\n\n" <> format_detailed_stats(stats)
  else
    basic
  end
end

defp format_findings_section(title, findings, stats) do
  """
  ## #{title} Analysis
  #{format_findings(findings)}

  #{format_summary_stats(stats)}
  """
end
```

---

## CLI Interface

### New Flags

```bash
# Run with default analyzers (currently: memory)
mix excessibility.debug test/my_test.exs

# Run specific analyzers only
mix excessibility.debug test/my_test.exs --analyze=memory

# Run multiple analyzers (future when more exist)
mix excessibility.debug test/my_test.exs --analyze=memory,state

# Run all available analyzers
mix excessibility.debug test/my_test.exs --analyze=all

# Skip all analyzers (just show timeline)
mix excessibility.debug test/my_test.exs --no-analyze

# Verbose output (detailed stats even when healthy)
mix excessibility.debug test/my_test.exs --verbose
```

### Help Text Update

```
## Analysis Options

  --analyze=NAMES       Run specific analyzers (comma-separated)
                        Available: memory
                        Default: memory
  --analyze=all         Run all available analyzers
  --no-analyze          Skip analysis, show timeline only
  --verbose             Show detailed stats even when no issues found
```

---

## File Structure

### New Files

```
lib/telemetry_capture/
  enricher.ex                    # Behaviour definition
  analyzer.ex                    # Behaviour definition
  registry.ex                    # Discovery and registration

  enrichers/
    memory.ex                    # Memory size enricher

  analyzers/
    memory.ex                    # Memory bloat/leak analyzer

test/telemetry_capture/
  enrichers/
    memory_test.exs

  analyzers/
    memory_test.exs

  registry_test.exs
```

### Modified Files

```
lib/telemetry_capture/timeline.ex           # Add enricher integration
lib/mix/tasks/excessibility_debug.ex        # Add analyzer invocation
lib/telemetry_capture/formatter.ex          # Add analysis formatting
```

---

## Testing Strategy

### Enricher Tests

Test that enrichers:
- Return correct data shape (map with expected keys)
- Handle edge cases (empty assigns, nil values, large data)
- Are performant (benchmark with large assigns)

### Analyzer Tests

Test that analyzers:
- Detect known patterns (create timelines with deliberate issues)
- Return correct finding severity levels
- Handle edge cases (single event, all events same size, etc.)
- Calculate statistics correctly

### Integration Tests

Test that:
- Enrichments appear in generated timeline.json
- CLI flags correctly enable/disable analyzers
- Analysis results appear in markdown output
- Verbose mode shows detailed stats

---

## Future Extensions

This framework enables adding:

**Additional Enrichers:**
- Query enricher (count Ecto records, detect NotLoaded)
- State enricher (extract state fields like :status, :mode)
- Permission enricher (track current_user, roles)

**Additional Analyzers:**
- N+1 analyzer (detect query explosions)
- State machine analyzer (visualize transitions, detect cycles)
- Permission analyzer (detect escalation bugs)
- PII scanner (detect leaked sensitive data)
- Mermaid generator (create flow diagrams)
- Flaky test analyzer (compare multiple runs)

**Enhancement Ideas:**
- Configurable analyzer thresholds
- Custom analyzer plugins via Mix config
- Export analysis results to JSON for tooling
- Interactive HTML reports with charts

---

## Success Criteria

The implementation is successful when:

1. ✅ Memory enricher adds `memory_size` to all timeline events
2. ✅ Memory analyzer detects 10x memory growth with adaptive thresholds
3. ✅ Memory analyzer detects memory leaks (3+ consecutive increases)
4. ✅ CLI flags (`--analyze`, `--no-analyze`, `--verbose`) work correctly
5. ✅ Analysis results appear in markdown output with appropriate formatting
6. ✅ No issues with healthy timelines show brief confirmation message
7. ✅ Framework enables adding new enrichers/analyzers without modifying core code
8. ✅ All tests pass, code coverage maintained
9. ✅ Documentation explains how to create custom enrichers/analyzers

---

## Non-Goals (Out of Scope)

- Implementing additional analyzers beyond memory (future work)
- Real-time analysis during test runs (analyzers run after)
- Web UI or interactive visualizations (CLI only for now)
- Configuration file for analyzer settings (hardcoded thresholds initially)
- Distributed analyzer plugins (compiled into app for now)
