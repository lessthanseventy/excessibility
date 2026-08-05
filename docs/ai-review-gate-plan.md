# Plan: Excessibility AI-Change Review Gate

**Status:** draft for review · **Date:** 2026-06-23

## The one question this plan exists to answer

> Can a judge, fed excessibility's *observed runtime behavior* of a PR (not its diff), assign a merge-risk tier that correlates with what actually broke in production?

If yes → you can auto-merge the safe pile and the PR backlog dissolves. That is the company. Everything below is scaffolding to get a trustworthy answer cheaply. **Do not build the gate before the eval says the judge is trustworthy.**

## Thesis in one paragraph

Excessibility already is a change-verification engine — capture real rendered/behavioral state → baseline → run a findings engine → emit severity. It's aimed at the *inner loop* ("agent, did you break a11y while editing"). This plan raises the same engine to the *outer loop* ("here's a PR from main, should it merge?"). At that altitude the ~20 analyzers stop being 20 debugging features and collapse into **one verdict**. a11y stays the OSS wedge; the judge + eval + hosted gate are the commercial core.

## What we reuse vs. what's new

| Capability | Status | Module |
|---|---|---|
| Capture rendered HTML per test source | ✅ built | `Excessibility.Source`, `Excessibility.Snapshot`, `html_snapshot/2` |
| Capture behavioral timeline (assigns, ecto, render, state machine) | ✅ built | `Excessibility.TelemetryCapture`, `mix excessibility.debug` |
| Findings engine (pluggable, topo-sorted, severity) | ✅ built | `Excessibility.TelemetryCapture.Analyzer` (~20 analyzers) |
| Severity classification + triage loop | ✅ built (inner loop) | `Excessibility.MCP.Tools.CheckWork` |
| Baseline + diff workflow | ⚠️ byte-equality only | `Mix.Tasks.Excessibility.Compare` |
| Agent-facing surface | ✅ built | `Excessibility.MCP.*` |
| **Two-ref (base/head) capture harness** | 🔨 new | `Excessibility.Review.Capture` |
| **Cross-run finding delta** | 🔨 new | `Excessibility.Review.FindingDelta` |
| **Semantic DOM diff (replace byte-equality)** | 🔨 new | `Excessibility.Review.DomDiff` |
| **The judge (Opus, structured verdict)** | 🔨 new — the differentiator | `Excessibility.Review.Judge` |
| **`mix excessibility.review` task** | 🔨 new | `Mix.Tasks.Excessibility.Review` |
| **Eval harness** | 🔨 new — the go/no-go gate | `Mix.Tasks.Excessibility.Eval` |
| Gate integration (GH check / merge queue) | 🔨 thin, last | output adapters |

## Component design

### 1. `Excessibility.Review.Capture` — two-ref capture
- Resolve `{base_ref, head_ref}` (default `main` / `HEAD`).
- For each ref: check out in a **git worktree** (don't dirty the working tree), run the suite under telemetry capture (`EXCESSIBILITY_TELEMETRY_CAPTURE=true`, reuse `excessibility.debug` machinery), collect `timeline.json` + HTML snapshots.
- Namespace outputs: `test/excessibility/review/{short_sha}/{timelines,snapshots}/`.
- **v0:** run the whole suite (correctness over speed). **Later:** map changed files → affected LiveView/controller tests and run only those; cache base captures keyed by SHA (base rarely changes between PRs).

### 2. `Excessibility.Review.FindingDelta` — what got worse
- Run all analyzers over base timelines and head timelines.
- Give each finding a **stable fingerprint**: `{analyzer_name, rule_key, code_pointer || test_name, route}`. (May require adding a `:key` to the `finding` shape in the `Analyzer` behaviour — small, backward-compatible.)
- Output: `new` (on head, not base = regression), `resolved`, `worsened` (severity bump). Only `new`/`worsened` flow to the judge.

### 3. `Excessibility.Review.DomDiff` — semantic, not byte
- Current `Compare` does `baseline_html != snapshot_html` → noisy (CSRF tokens, timestamps, nonces, random ids trip every run).
- Normalize then structurally diff with **Floki** (already a dep): strip volatile attrs, compare DOM trees, emit per-route structured diff (added/removed/changed nodes). Feeds the judge a clean "what changed in the rendered output," and de-noises the existing `compare` task as a bonus.

### 4. `Excessibility.Review.Judge` — the differentiated layer
Primary input is **observed behavior**, not the code diff — that's the moat (everyone else judges the diff).

Evidence bundle:
- changed files (`git diff --name-only base..head`)
- finding-delta (new/worsened, structured)
- semantic DOM diff per affected route
- a11y violation delta
- the code diff for changed files (bounded; **secondary** context)

Forced structured output (JSON-schema tool call), model `claude-opus-4-8`:
```
%{
  tier:        :auto | :review | :block,
  blast_radius: String.t(),
  risks:       [%{severity, area, evidence_ref, explanation}],
  evidence:    [evidence_ref],
  confidence:  float
}
```
Judge framing: "You decide whether a Phoenix/LiveView PR can auto-merge given a strong test + painless-rollback safety net. Bias toward `:auto` when there are no new behavioral findings and DOM changes are cosmetic. Reserve `:block` for new criticals in money / auth / data-migration paths. Ground every risk in supplied evidence." The strong existing safety net (tests, flags, cheap rollback) is *explicitly* why the bar for `:auto` can be low — encode that.

### 5. `Mix.Tasks.Excessibility.Review`
```
mix excessibility.review --base main --head HEAD \
    --format json|text|github --fail-on block|review
```
Flow: resolve refs → `Capture` both → `FindingDelta` → `DomDiff` → `Judge` → write `test/excessibility/review/verdict.json` → exit code from tier (`--fail-on`). Also expose as an MCP tool (sibling of `CheckWork`) so agents can self-gate before opening a PR.

### 6. `Mix.Tasks.Excessibility.Eval` — the go/no-go gate
- **Dataset:** last N merged PRs from the work repo. Per PR: `base = merge-base`, `head = PR head`.
- **Ground truth label** (`broke` vs `clean`): revert commits referencing the SHA, "fix/hotfix" follow-ups touching the same files within ~48h, post-merge CI failures, linked incidents. **v0:** start with ~20–30 PRs Andrew hand-labels from memory — don't over-engineer labeling first.
- **Score:** confusion matrix of predicted `{auto,review,block}` × actual `{clean,broke}`. The metric that matters most: **false-auto rate** (auto-merged something that broke — the only dangerous error). Secondary: **over-block rate** (friction). Tune thresholds so false-auto ≈ 0 while the auto-rate is still high enough to actually drain the pile.
- This task's output *is* the investment decision.

### 7. Gate integration (thin, last)
Output adapter emitting a GitHub Check Run / status from `verdict.json`, consumable by GitHub merge queue / policy-bot / gitStream. Deliberately dumb — the gate mechanics are commodity; the verdict is the product.

## Phasing

- **M0 — spike (~a weekend):** working-tree-vs-`main`, single judge call, no worktrees/delta polish. Run against 10 hand-labeled PRs. Answer only: *is the judge directionally right?* Kill or continue here.
- **M1:** real two-ref worktree capture + `FindingDelta` + `DomDiff`.
- **M2:** `Eval` harness + scoring on ~50 PRs; tune tier thresholds.
- **M3:** GH Check integration; pilot auto-merge on `:auto` greens in one low-risk repo.

## Open questions / risks

- **Capture cost:** full suite ×2 per PR. Mitigate with affected-test selection + SHA-keyed base cache. (Defer past M0.)
- **Non-UI PRs:** pure context/backend changes have no DOM; judge leans on ecto/state findings + test-delta + code diff. Blast-radius signal is weaker there — flag explicitly, maybe a separate calibration.
- **Flaky captures** → false deltas. Mitigate via normalization; consider multi-run for the timeline if noisy.
- **Finding-fingerprint stability** across refs (renames, line shifts) — `code_pointer` + test name should be robust to line shifts; verify.
- **Judge trust:** if the eval says it's not trustworthy enough to auto-merge, the fallback product is *advisory risk labels + routing* (still valuable, lower ceiling). The eval tells us which company we're in.

## Existing open issues — already pieces of this gate

The three open issues (all owner-authored) are not a separate backlog; they slot directly into this plan.

- **#104 — cross-snapshot diffing (aria-live).** This *is* the `DomDiff` component (#3). Filed 2026-03-31, already framed as "no other a11y tool does cross-snapshot analysis." The same "diff two rendered states, classify significant regions" primitive that catches a missing `aria-live` is what the **judge** needs to know what a PR changed in rendered output. **Shared foundation between the a11y lane and the governance lane** — build it once, generically, serve both.
- **#110 — LiveView rule scoping / false positives.** 57 of 58 violations were noise (rules firing on dismiss buttons / dialogs). This is a **hard dependency, on the critical path** — a judge built on noisy findings produces noisy verdicts, and a wedge that cries wolf loses the trust that gets it installed. Finding signal-quality is prerequisite to a trustworthy gate. Do this before/with M1.
- **#111 — `journey/3` macro (interaction videos for design review).** Not a video feature — a **second governance lane**: human *functional/design* signoff, parallel to the judge's *risk* signoff. Has demonstrated pull (a designer asking, a working ~45-min pilot, "design review on every UI PR"). Doesn't depend on the judge being trustworthy, so it's the **warmer, lower-risk wedge** that installs the capture spine on every UI PR and earns the PR-gate habit.

### Reframe: one gate, three lanes, one spine

| Lane | Answers | Status | Feeds on |
|---|---|---|---|
| **Risk verdict** (Judge) | auto / review / block | big vision, unproven (needs eval) | telemetry findings + DomDiff |
| **Design signoff** (#111) | does the flow work/look right | proven pull, working pilot | live-Playwright journey video |
| **A11y delta** (wedge) | did accessibility regress | built; needs #110 + #104 | snapshots + DomDiff |

### Two capture backends, one verdict (architectural seam to design deliberately)
- **Telemetry-timeline capture** (`Phoenix.LiveViewTest` + `EXCESSIBILITY_TELEMETRY_CAPTURE`) — cheap, deterministic, feeds the risk judge and analyzers.
- **Live-Playwright capture** (#111 Option A, real server) — high-fidelity, feeds human-facing journeys.
These are different code paths feeding one gate. Design the seam now so they don't drift into two libraries.

### Suggested sequencing given the issues
Lead with **#111** (warm wedge, proven buyer, no judge-trust dependency) to get the spine adopted and the PR-gate habit formed → land **#110 + #104** as signal-quality + shared-diff groundwork → bring the **risk judge** in on rails the design-review lane already laid. Design review is the trojan horse; the risk gate is the platform.

## OSS vs. commercial (open-core)

- **OSS (the wedge / install vector):** capture, analyzers, a11y, `compare`, MCP tools.
- **Commercial:** the judge + calibration, the eval/scoring, the hosted cross-PR fleet dashboard, auto-merge orchestration.
