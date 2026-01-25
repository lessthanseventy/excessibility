# Telemetry Signal-to-Noise Improvements

**Date:** 2026-01-25
**Issue:** #42
**Goal:** Make telemetry snapshots scannable and useful for AI/human debugging

## Problem

Current telemetry snapshots are comprehensive but noisy:
- 81KB per handle_event snapshot (~2000 lines)
- Full Ecto structs with `__meta__`, `NotLoaded` associations
- Repeated unchanged data across events
- Hard to find what actually changed

## Solution: Comprehensive + Configurable

Generate filtered, scannable output by default with CLI overrides for deep dives.

## Architecture

### Three-Layer Configuration
1. **Smart Defaults** - Claude-optimized filtering (hardcoded)
2. **Application Config** - Project-specific overrides (optional)
3. **Runtime CLI Flags** - Ad-hoc control

Hierarchy: CLI > App Config > Defaults

### Data Structures

**Timeline JSON:**
```json
{
  "test": "prohibits purchase when out of stock",
  "duration_ms": 850,
  "timeline": [
    {
      "sequence": 1,
      "event": "mount",
      "timestamp": "2026-01-25T10:20:27.324Z",
      "view_module": "MyApp.MarketplaceLive.Index",
      "key_state": {
        "current_user_id": 691586,
        "products_count": 2,
        "cart_items": 0
      },
      "changes": null,
      "snapshot_file": "test_1_mount.html"
    },
    {
      "sequence": 5,
      "event": "handle_event:submit_order",
      "changes": {
        "order.status": [null, "processing"],
        "cart_items": [2, 1]
      }
    }
  ]
}
```

### Filtering Pipeline

```
Raw Assigns
  ↓
filter_ecto_metadata()      # Remove __meta__, NotLoaded
  ↓
filter_phoenix_internals()  # Remove flash, __changed__
  ↓
extract_key_state()         # Pull highlighted fields + small values
  ↓
compute_diff(previous)      # Find changes
  ↓
Timeline Entry
```

### Output Formats

**Markdown** (default):
- Timeline table with key changes
- Detailed change sections per event
- Collapsible full snapshots
- Optimized for Claude scanning

**JSON** (--format=json):
- Structured timeline data
- Machine-parseable

**Package** (--format=package):
- timeline.json
- MANIFEST.md
- snapshots/*.html
- diff_report.md

### CLI Flags

```bash
# Presets
mix excessibility.debug test.exs              # Smart defaults
mix excessibility.debug test.exs --full       # No filtering
mix excessibility.debug test.exs --minimal    # Timeline only

# Format
mix excessibility.debug test.exs --format=json
mix excessibility.debug test.exs --format=package

# Specific toggles
--no-filter-ecto
--no-filter-phoenix
--highlight=current_user,cart,order
```

## Implementation Modules

**New Modules:**
1. `Excessibility.TelemetryCapture.Filter` - Filtering logic
2. `Excessibility.TelemetryCapture.Diff` - Diff computation
3. `Excessibility.TelemetryCapture.Timeline` - Timeline generation
4. `Excessibility.TelemetryCapture.Formatter` - Output formatting

**Modified:**
- `TelemetryCapture.write_snapshots/2` - Generate timeline.json
- `Mix.Tasks.Excessibility.Debug` - Use new formatters, accept flags

## Smart Defaults

**Filtering:**
- Remove `__meta__`, `NotLoaded` associations
- Remove Phoenix internals (flash, __changed__, __temp__)
- Remove private assigns (starting with _)
- Truncate large binaries (>1KB)

**Highlighting:**
- `:current_user`, `:live_action`, `:errors`, `:form`
- Auto-detect: small values, counts, status fields

**Edge Cases:**
- Empty assigns → `(empty)`
- Large nested structures → `products: [12 items]`
- Binary data → `<<binary, 1234 bytes>>`
- No changes → `(unchanged)`

## Quality Gates

- All tests passing
- Credo clean
- Code formatted (mix format)
- New functionality tested
