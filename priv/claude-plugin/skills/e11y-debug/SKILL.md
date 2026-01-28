---
name: e11y-debug
description: Use when debugging LiveView issues - timeline analysis shows state at each event, snapshots show rendered HTML, analyzers suggest root causes
---

# Excessibility Debug - Timeline & State Analysis

Debug LiveView issues by inspecting state evolution and rendered HTML.

## Tools

- **Timeline** - Shows state at mount, handle_event, render
- **Snapshots** - Captured HTML at specific moments
- **Analyzers** - Memory, hypothesis, code pointers

## Four-Phase Debug Process

### Phase 1: Capture with Snapshots

Add temporary `html_snapshot(view)` calls around the problem area:

```elixir
test "debugging problematic feature" do
  {:ok, view, _html} = live(conn, "/page")

  html_snapshot(view)  # before the problem

  view |> element("button") |> render_click()

  html_snapshot(view)  # after - what changed?
end
```

Run with telemetry capture:

```bash
mix excessibility.debug test/failing_test.exs
```

### Phase 2: Analyze Timeline

Read `test/excessibility/timeline.json`:

```json
{
  "test": "test debugging problematic feature",
  "duration_ms": 142,
  "timeline": [
    {
      "sequence": 1,
      "event": "mount",
      "timestamp": "2024-01-15T10:30:00Z",
      "memory_size": 1024,
      "key_state": {"user": null, "items": []},
      "changes": {}
    },
    {
      "sequence": 2,
      "event": "handle_event:click",
      "timestamp": "2024-01-15T10:30:00.050Z",
      "memory_size": 4096,
      "key_state": {"user": null, "items": ["a", "b", "c"]},
      "changes": {"items": "changed"}
    }
  ]
}
```

Look for:
- Assigns at each event
- What changed between renders
- Unexpected state

### Phase 3: Inspect Snapshots

Read captured HTML files in `test/excessibility/html_snapshots/`:

```bash
# List all snapshots
ls test/excessibility/html_snapshots/

# Open in browser
open test/excessibility/html_snapshots/MyModule_42.html
```

Check for:
- Missing elements
- Wrong content
- Incorrect attributes
- Compare before/after

### Phase 4: Fix

1. Use hypothesis analyzer for root cause suggestions
2. Add test for the specific issue
3. Implement fix
4. Verify with `mix excessibility`
5. Remove temporary snapshots

## Commands

```bash
# Basic debug run
mix excessibility.debug test/my_test.exs

# With specific analyzers
mix excessibility.debug test/my_test.exs --analyze=memory,hypothesis

# Verbose output (detailed stats)
mix excessibility.debug test/my_test.exs --verbose

# Full assigns (no filtering)
mix excessibility.debug test/my_test.exs --full

# Highlight specific assigns
mix excessibility.debug test/my_test.exs --highlight=user,cart,items
```

## Available Analyzers

| Analyzer | What it finds |
|----------|--------------|
| `memory` | Memory bloat, leaks (default, enabled) |
| `hypothesis` | Suggested root causes |
| `code_pointer` | Source locations for issues |
| `accessibility_correlation` | State changes affecting a11y |

## Accessibility Debugging

For Pa11y/WCAG issues specifically:

```bash
mix excessibility.debug test/file.exs --analyze=accessibility_correlation
```

This correlates:
- State changes with a11y violations
- Which events caused accessible name loss
- Missing ARIA attributes after state changes

## Reading the Timeline

### Memory Growth

```json
{
  "sequence": 5,
  "event": "handle_event:load_more",
  "memory_size": 102400,  // 100KB - growing!
  "key_state": {"items": "[1000 items]"}
}
```

**Red flag**: Memory growing across events suggests unbounded list accumulation.

### State Changes

```json
{
  "changes": {
    "user": "changed",        // user assign was modified
    "form": "added",          // new assign appeared
    "error_message": "removed" // assign was deleted
  }
}
```

### Event Flow

Normal flow: `mount` → `handle_params` → `handle_event:*` → `render`

Suspicious patterns:
- Many `render` events without `handle_event` (component re-rendering)
- `handle_event` without state change (noop handlers)
- Missing `handle_params` after navigation

## Debugging Patterns

### State Not Updating

1. Check timeline for handle_event
2. Look at `changes` - is the assign modified?
3. If no change, the handler might not be updating socket

```elixir
# Problem: No change in timeline
def handle_event("click", _params, socket) do
  # Forgot to assign!
  {:noreply, socket}
end

# Fix: Assign the change
def handle_event("click", _params, socket) do
  {:noreply, assign(socket, :clicked, true)}
end
```

### Wrong Content Rendered

1. Snapshot shows wrong HTML
2. Check timeline state at that point
3. State correct but HTML wrong? Check template
4. State wrong? Trace back through events

### Memory Leak

1. Run with `--analyze=memory`
2. Check for growing `memory_size` across events
3. Look for lists that accumulate
4. Use `--highlight=suspects` to focus on likely culprits

## Integration with superpowers

This skill works well with:
- **systematic-debugging** - Four-phase framework for root cause
- **root-cause-tracing** - Trace back through call stack
- **e11y-tdd** - Fix with TDD after finding cause
