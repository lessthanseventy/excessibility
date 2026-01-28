---
name: e11y-tdd
description: Use when implementing Phoenix LiveView features - TDD with html_snapshot for state inspection and Pa11y for accessibility. Sprinkle snapshots to see what's rendered, delete when done.
---

# Excessibility TDD - Build with Inspection

Build Phoenix LiveView features with full visibility into rendered HTML and state.

## Core Powers

- **`html_snapshot(view)`** - Capture HTML at any point (sprinkle liberally while building)
- **Pa11y checks** - Ensure accessibility (WCAG compliance)
- **Timeline analysis** - See state evolution across events

## The e11y-TDD Cycle

```
1. EXPLORE   - Add html_snapshot(view) calls to see what's rendered
2. RED       - Write test with snapshot at key moment
3. GREEN     - Implement feature, use snapshots to debug
4. CHECK     - Run `mix excessibility` for Pa11y/a11y validation
5. CLEAN     - Remove temporary snapshots, keep essential ones
```

## Snapshot Strategies

### Temporary Snapshots (for building/debugging)

Sprinkle these while building. Delete when feature works.

```elixir
test "building new feature" do
  {:ok, view, _html} = live(conn, "/page")

  # Sprinkle these to see what's happening
  html_snapshot(view)  # <- see initial state

  view |> element("button") |> render_click()
  html_snapshot(view)  # <- see after click

  view |> form("#my-form") |> render_submit(%{name: "test"})
  html_snapshot(view)  # <- see after submit

  # Delete these when feature works
end
```

### Permanent Snapshots (for regression testing)

Keep these - Pa11y will check them on every run.

```elixir
test "feature works and is accessible" do
  {:ok, view, _html} = live(conn, "/page")
  view |> element("button") |> render_click()

  # Keep this - Pa11y will check it on every run
  html_snapshot(view)
end
```

## When to Use

- **Building any LiveView feature** - snapshots show you what's rendered
- **Debugging state issues** - sprinkle snapshots, inspect, delete
- **Accessibility compliance** - Pa11y catches WCAG violations
- **Form implementations** - see validation errors, field states
- **Modals/dialogs** - verify focus management, aria attributes
- **Dynamic content** - check aria-live regions render correctly

## Commands

```bash
# Run tests (generates snapshots)
mix test test/my_live_view_test.exs

# Check accessibility on all snapshots
mix excessibility

# Run specific test then check its snapshots
mix excessibility test/my_live_view_test.exs

# Debug with timeline analysis
mix excessibility.debug test/my_live_view_test.exs
```

## Reading Snapshots

After running tests, check:

```
test/excessibility/
  html_snapshots/           # HTML files from html_snapshot() calls
    MyApp_PageTest_42.html  # Module_Line.html naming
  timeline.json             # State evolution (if using debug)
```

Open HTML files in browser to see exactly what was rendered.

## Common Patterns

### Form with Validation

```elixir
test "form shows validation errors accessibly" do
  {:ok, view, _html} = live(conn, "/register")

  # Submit empty form
  view |> form("#register-form") |> render_submit(%{})

  # Snapshot captures error state - Pa11y will check:
  # - Error messages are associated with inputs (aria-describedby)
  # - Required fields are marked (aria-required)
  # - Invalid fields have aria-invalid
  html_snapshot(view)
end
```

### Modal/Dialog

```elixir
test "modal is accessible" do
  {:ok, view, _html} = live(conn, "/page")

  # Open modal
  view |> element("#open-modal") |> render_click()

  # Snapshot captures modal state - Pa11y will check:
  # - role="dialog" or aria-modal
  # - aria-labelledby for title
  # - Focus trapped inside modal
  html_snapshot(view)
end
```

### Loading States

```elixir
test "loading state is accessible" do
  {:ok, view, _html} = live(conn, "/dashboard")

  # Trigger async load
  view |> element("#refresh") |> render_click()

  # Snapshot during loading - Pa11y will check:
  # - aria-busy on loading container
  # - Loading indicator has appropriate role
  html_snapshot(view)
end
```

## Debugging Tips

1. **Too much output?** Use named snapshots:
   ```elixir
   html_snapshot(view, name: "after_click")
   html_snapshot(view, name: "with_errors")
   ```

2. **Need to see assigns/state?** Use debug mode:
   ```bash
   mix excessibility.debug test/my_test.exs
   ```

3. **Pa11y error unclear?** Check the snapshot HTML directly:
   ```bash
   open test/excessibility/html_snapshots/MyModule_42.html
   ```

4. **Multiple snapshots per test?** They're numbered:
   ```
   MyModule_42_1.html
   MyModule_42_2.html
   ```

## Integration with superpowers

This skill works well with:
- **test-driven-development** - TDD discipline for implementation
- **systematic-debugging** - When Pa11y errors are unclear
- **verification-before-completion** - Verify Pa11y passes before claiming done
