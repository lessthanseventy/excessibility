# MCP Elicitation + Auto-Check Design

## Summary

Add MCP elicitation support to the Excessibility MCP server and create an automated accessibility/performance checking workflow that Claude runs without being asked. The installer sets up CLAUDE.md instructions (replacing the `.claude_docs` approach) so Claude automatically calls a `check_work` tool after modifying code, with threshold-based elicitation to keep the user in control of triage.

## Motivation

Excessibility can check accessibility, detect bad LiveView patterns, and analyze performance — but users have to remember to invoke these tools. By adding auto-check instructions to CLAUDE.md and using MCP elicitation for smart triage, the library becomes a copilot that watches your back rather than a set of tools you have to remember to call.

## Design

### 1. Installer — CLAUDE.md Instead of .claude_docs

**Changes:**
- Replace `maybe_create_claude_docs()` with `maybe_setup_claude_md()` in `Mix.Tasks.Excessibility.Install`
- Delete `Mix.Tasks.Excessibility.SetupClaudeDocs` (`lib/mix/tasks/excessibility_setup_claude_docs.ex`)
- Remove all `.claude_docs` references from the installer
- Remove `claude_docs_content/0` from install.ex

**New behavior:**
- Appends an `## Excessibility` section to the project's `CLAUDE.md` (creates the file if missing)
- Idempotent — checks for existing Excessibility section before appending

**CLAUDE.md content includes:**
- Auto-check instruction: "After modifying any LiveView, controller, or template code, run the `check_work` MCP tool with the relevant test file before reporting work as complete. Fix critical violations before moving on."
- When to use timeline analysis: "When working on performance-sensitive code or investigating LiveView state issues, pass `include_perf: true` to `check_work`."
- Pointers to skills: `/e11y-tdd`, `/e11y-debug`, `/e11y-fix`
- Brief note that hooks can be configured for additional automation (details in README)

### 2. MCP Elicitation Support

**Protocol:**
- Server declares `"elicitation"` capability during initialize handshake
- Protocol version stays `2024-11-05` (elicitation is an optional capability)
- Add handler for elicitation responses from the client

**Execution model:**
- Pass an `elicit` callback function to tools via opts
- The callback writes an elicitation request directly to stdout and reads the response directly from stdin
- Safe because during a pending tool call, the MCP client only sends back the elicitation response

```elixir
# In call_tool:
elicit_fn = fn message, schema ->
  request_id = generate_request_id()
  send_elicitation_request(request_id, message, schema)
  receive_elicitation_response(request_id)
end

tool_module.execute(args, elicit: elicit_fn)
```

**New module: `Excessibility.MCP.Elicitation`**
- `build_request/3` — formats the JSON-RPC elicitation request with message + JSON Schema for the form
- `send_and_receive/1` — writes to stdout, reads from stdin, parses response
- `callback/0` — returns a closure tools can call

**Backward compatibility:**
- Tool behavior unchanged — `execute/2` still returns `{:ok, result} | {:error, string}`
- Tools that want elicitation call `opts[:elicit]` when needed
- Tools that don't use elicitation are unaffected
- If elicitation isn't supported by the client, `opts[:elicit]` is nil — tools fall back to returning full results

### 3. Threshold-Based Elicitation in `a11y_check`

**When to elicit vs. just return:**
- **0 violations** — return silently, no elicitation
- **Minor only** (no critical/serious) — return the full list, no elicitation. Claude auto-fixes these.
- **Critical/serious violations present** — elicit for user triage

**Elicitation form:**
```
Found 2 critical and 5 minor accessibility violations.

Critical:
- color-contrast: 2 elements have insufficient contrast ratio
- aria-required-attr: Required ARIA attributes missing

( ) Fix all violations now
( ) Fix critical only, note minor for later
( ) Show full details (return everything to Claude)
( ) Skip — I'll handle this separately
```

**Return value based on user choice:**
- "Fix all" / "Fix critical only" — returns scoped violation list
- "Show full details" — returns full blob (current behavior)
- "Skip" — returns note that user declined, Claude doesn't try to fix

**Fallback:** If elicitation not available (nil callback), returns everything like today.

### 4. New `check_work` Composite Tool

**Purpose:** Single tool Claude calls automatically (per CLAUDE.md) after modifying code.

**Input schema:**
```json
{
  "test_file": "test/my_app_web/live/page_live_test.exs",
  "include_perf": false
}
```

- `test_file` — required, the test file covering the modified code
- `include_perf` — optional, defaults to false. Set to true for perf-sensitive work.

**Execution flow:**
1. Run `mix test <test_file>` — if tests fail, return failure immediately
2. Run `a11y_check` on resulting snapshots
3. If `include_perf`: run `mix excessibility.debug <test_file>`, analyze timeline
4. Combine results, apply threshold logic:
   - All clean → return "No issues found" (no elicitation)
   - Minor a11y only → return violations for Claude to fix silently
   - Critical a11y and/or perf concerns → elicit with combined triage form

**Combined elicitation form (when triggered):**
```
A11y: 2 critical, 3 minor violations
Perf: N+1 query pattern detected in UserList

( ) Fix a11y critical + perf issues now
( ) Fix a11y only
( ) Show full details
( ) Skip
```

### 5. README Updates

**Changes:**
- Remove outdated MCP tool references (old tool names like `check_route`, `explain_issue`, `suggest_fixes`, `analyze_timeline`, `list_analyzers`)
- Remove `.claude_docs` references
- Add Claude Code integration section covering:
  - What the installer sets up (MCP server, skills plugin, CLAUDE.md instructions)
  - The auto-check flow: Claude runs `check_work` after code changes, elicitation handles triage
  - Optional hooks for additional automation with a concrete post-edit hook example
- Keep core snapshot workflow docs, mix task reference, installation steps unchanged

## Files to Create

- `lib/excessibility/mcp/elicitation.ex` — Elicitation protocol support
- `lib/excessibility/mcp/tools/check_work.ex` — Composite check tool
- `test/mcp/elicitation_test.exs` — Elicitation unit tests
- `test/mcp/tools/check_work_test.exs` — Check work tool tests

## Files to Modify

- `lib/excessibility/mcp/server.ex` — Add elicitation capability, wire elicit callback into tool calls
- `lib/excessibility/mcp/tools/a11y_check.ex` — Add threshold-based elicitation
- `lib/mix/tasks/install.ex` — Replace `.claude_docs` with CLAUDE.md, remove `claude_docs_content/0`
- `README.md` — Update MCP/Claude Code sections

## Files to Delete

- `lib/mix/tasks/excessibility_setup_claude_docs.ex`
