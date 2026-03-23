# Excessibility Skills Available

When working with Phoenix LiveView in this project, you have access to specialized accessibility testing skills.

## When to Use Excessibility Skills

**Check for these patterns at the start of each conversation:**

1. **Implementing Phoenix LiveView features** (forms, modals, dynamic content)
   → Use `/e11y-tdd` skill
   - Guides TDD with `html_snapshot()` for state inspection
   - Integrates axe-core accessibility checks
   - Shows you exactly what's rendered at each step

2. **Debugging LiveView test failures or state issues**
   → Use `/e11y-debug` skill
   - Analyzes timeline.json showing state evolution
   - Correlates state changes with behavior
   - Uses MCP tools to inspect snapshots and timeline

3. **Fixing axe-core or WCAG accessibility violations**
   → Use `/e11y-fix` skill
   - Reference guide for common Phoenix/LiveView a11y patterns
   - Maps axe-core violations to specific fixes

## Detection Rules

**If the user's request involves ANY of these, use the appropriate skill:**
- Implementing LiveView forms, buttons, modals, dynamic UI
- Debugging test failures in LiveView tests
- Understanding what HTML is being rendered
- Fixing accessibility violations
- axe-core errors or WCAG compliance

**The skills are not optional when these patterns match** - they provide specialized workflows that prevent common mistakes and give you visibility into actual rendered HTML and LiveView state.

## MCP Tools Available

You also have MCP tools for direct access:
- `a11y_check` - Run axe-core on snapshots or URLs
- `debug` - Run tests with telemetry capture
- `get_timeline` - Read state evolution timeline
- `get_snapshots` - List/read HTML snapshots
- `generate_test` - Generate test code with html_snapshot() calls

Use skills for guided workflows, MCP tools for direct inspection.
