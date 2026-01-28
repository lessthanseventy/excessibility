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
- Memory leaks (3+ consecutive increases above median delta)

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

Built-in enrichers and analyzers are auto-discovered at compile time from `lib/telemetry_capture/enrichers/` and `lib/telemetry_capture/analyzers/`.

Users can also register custom plugins in their own applications via config.

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

2. **Register via config:**

```elixir
# config/test.exs
config :excessibility,
  custom_enrichers: [MyApp.Enrichers.Query]
```

3. **Write tests:**

```elixir
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

2. **Register via config:**

```elixir
# config/test.exs
config :excessibility,
  custom_analyzers: [MyApp.Analyzers.StateMachine]
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
