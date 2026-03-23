// Multi-page accessibility crawl
// Usage: node axe-crawl.js <url> [--screenshots-dir dir] [--disable-rules rule1,rule2]
//
// Navigates a careers site through 3 stages:
//   1. Careers landing page
//   2. First job listing found
//   3. Application page (apply button click)
//
// Outputs JSON with axe results for each stage reached.

const path = require("path");
const modulesDir = path.join(__dirname, "node_modules");
const { chromium } = require(path.join(modulesDir, "playwright"));
const { AxeBuilder } = require(path.join(modulesDir, "@axe-core", "playwright"));

// ── Heuristic selectors ────────────────────────────────────

// Patterns to find a clickable job listing from a careers page
const JOB_LINK_SELECTORS = [
  // Common job card patterns
  'a[href*="/job/"]',
  'a[href*="/jobs/"]',
  'a[href*="/position/"]',
  'a[href*="/requisition/"]',
  'a[href*="/posting/"]',
  'a[href*="/career/"]',
  'a[href*="jobId="]',
  'a[href*="job_id="]',
  'a[href*="requisitionId"]',
  // Job list items
  '[class*="job-card"] a',
  '[class*="jobCard"] a',
  '[class*="job-listing"] a',
  '[class*="jobListing"] a',
  '[class*="job-result"] a',
  '[class*="JobResult"] a',
  '[class*="search-result"] a',
  '[class*="SearchResult"] a',
  '[data-testid*="job"] a',
  // Table/list patterns
  'table.jobs a',
  '.job-list a',
  '.jobs-list a',
  '.results-list a',
  'li[class*="job"] a',
  // Generic but common
  'a[class*="job-title"]',
  'a[class*="jobTitle"]',
  'a[class*="job-link"]',
  'h3 a[href]', // job titles are often h3 links
];

// Patterns for "search jobs" input to trigger a listing first
const SEARCH_SELECTORS = [
  'input[placeholder*="Search" i]',
  'input[placeholder*="job" i]',
  'input[aria-label*="Search" i]',
  'input[aria-label*="job" i]',
  'input[name*="keyword" i]',
  'input[name*="search" i]',
  'input[id*="search" i]',
  '#search-keyword',
  '#keyword',
];

// Patterns to find an "Apply" button on a job listing page
const APPLY_SELECTORS = [
  'a[href*="apply" i]',
  'button:has-text("Apply")',
  'a:has-text("Apply Now")',
  'a:has-text("Apply now")',
  'a:has-text("Apply for this job")',
  'a:has-text("Apply for this position")',
  'button:has-text("Apply Now")',
  'button:has-text("Apply now")',
  'button:has-text("Apply for this")',
  '[class*="apply" i] a',
  '[class*="apply" i] button',
  '[data-testid*="apply" i]',
  '#apply-button',
  '.apply-btn',
  '.apply-button',
];

// ── Main ───────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const url = args[0];
  if (!url) {
    console.error(JSON.stringify({ error: "Usage: node axe-crawl.js <url> [--screenshots-dir dir] [--disable-rules rule1,rule2]" }));
    process.exit(1);
  }

  let screenshotsDir = null;
  let disableRules = [];

  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--screenshots-dir" && args[i + 1]) screenshotsDir = args[++i];
    else if (args[i] === "--disable-rules" && args[i + 1]) disableRules = args[++i].split(",");
  }

  const browser = await chromium.launch();
  const context = await browser.newContext({
    userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    viewport: { width: 1280, height: 720 },
    locale: "en-US",
  });
  const page = await context.newPage();

  const output = {
    start_url: url,
    timestamp: new Date().toISOString(),
    stages: [],
  };

  try {
    // ── Stage 1: Careers landing page ──────────────────────
    await navigateAndWait(page, url);
    const stage1 = await runAxeStage(page, "careers_landing", disableRules, screenshotsDir);
    output.stages.push(stage1);

    // ── Stage 2: Find and click a job listing ──────────────
    const jobLink = await findAndClick(page, JOB_LINK_SELECTORS, SEARCH_SELECTORS);

    if (jobLink) {
      await waitForContent(page);
      const stage2 = await runAxeStage(page, "job_listing", disableRules, screenshotsDir);
      stage2.clicked = jobLink;
      output.stages.push(stage2);

      // ── Stage 3: Find and click Apply ────────────────────
      const applyLink = await findApplyButton(page);

      if (applyLink) {
        // Some apply buttons open new tabs — handle both cases
        const [newPage] = await Promise.all([
          context.waitForEvent("page", { timeout: 5000 }).catch(() => null),
          clickElement(page, applyLink),
        ]);

        const activePage = newPage || page;
        if (newPage) await newPage.waitForLoadState("load", { timeout: 15000 }).catch(() => {});
        await waitForContent(activePage);

        const stage3 = await runAxeStage(activePage, "apply_page", disableRules, screenshotsDir);
        stage3.clicked = applyLink.description;
        stage3.new_tab = !!newPage;
        output.stages.push(stage3);
      } else {
        output.stages.push({
          name: "apply_page",
          status: "not_found",
          note: "Could not find an Apply button on the job listing page",
        });
      }
    } else {
      output.stages.push({
        name: "job_listing",
        status: "not_found",
        note: "Could not find a job listing link on the careers page",
      });
      output.stages.push({
        name: "apply_page",
        status: "skipped",
        note: "Skipped — no job listing found",
      });
    }

    console.log(JSON.stringify(output));
  } catch (err) {
    output.error = err.message;
    output.stages.push({ name: "error", error: err.message });
    console.log(JSON.stringify(output));
    process.exit(1);
  } finally {
    await browser.close();
  }
}

// ── Helpers ────────────────────────────────────────────────

async function navigateAndWait(page, url) {
  await page.goto(url, { waitUntil: "load", timeout: 30000 });
  await waitForContent(page);
}

async function waitForContent(page, maxWait = 8000) {
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    const bodyText = await page.evaluate(() => document.body?.innerText?.trim() || "").catch(() => "");
    if (bodyText.length > 50) return;
    await new Promise((r) => setTimeout(r, 500));
  }
}

async function runAxeStage(page, stageName, disableRules, screenshotsDir) {
  let builder = new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]);
  if (disableRules.length > 0) builder = builder.disableRules(disableRules);

  const results = await builder.analyze();

  if (screenshotsDir) {
    const fs = require("fs");
    if (!fs.existsSync(screenshotsDir)) fs.mkdirSync(screenshotsDir, { recursive: true });
    await page.screenshot({
      path: path.join(screenshotsDir, `${stageName}.png`),
      fullPage: true,
    });
  }

  const violations = results.violations || [];
  const byImpact = {};
  for (const v of violations) {
    byImpact[v.impact] = (byImpact[v.impact] || 0) + 1;
  }

  return {
    name: stageName,
    status: "checked",
    url: page.url(),
    violations_count: violations.length,
    by_impact: {
      critical: byImpact.critical || 0,
      serious: byImpact.serious || 0,
      moderate: byImpact.moderate || 0,
      minor: byImpact.minor || 0,
    },
    violations: violations.map((v) => ({
      id: v.id,
      impact: v.impact,
      description: v.description,
      help_url: v.helpUrl,
      nodes_count: (v.nodes || []).length,
      nodes: (v.nodes || []).slice(0, 3).map((n) => ({
        html: (n.html || "").slice(0, 200),
        target: n.target,
        failure_summary: n.failureSummary,
      })),
    })),
    passes_count: (results.passes || []).length,
  };
}

async function findAndClick(page, linkSelectors, searchSelectors) {
  // First try: look for job links directly on the page
  for (const selector of linkSelectors) {
    try {
      const link = await page.$(selector);
      if (link) {
        const isVisible = await link.isVisible().catch(() => false);
        if (!isVisible) continue;

        const text = await link.innerText().catch(() => "");
        const href = await link.getAttribute("href").catch(() => "");

        await link.click({ timeout: 5000 });
        await page.waitForLoadState("load", { timeout: 15000 }).catch(() => {});

        return { selector, text: text.trim().slice(0, 100), href };
      }
    } catch {
      continue;
    }
  }

  // Second try: search for jobs to trigger a listing
  for (const selector of searchSelectors) {
    try {
      const input = await page.$(selector);
      if (input) {
        const isVisible = await input.isVisible().catch(() => false);
        if (!isVisible) continue;

        await input.click();
        await input.fill("");
        // Submit empty search to get all jobs
        await input.press("Enter");
        await page.waitForLoadState("load", { timeout: 10000 }).catch(() => {});
        await waitForContent(page, 5000);

        // Now try job links again
        for (const linkSel of linkSelectors) {
          try {
            const link = await page.$(linkSel);
            if (link) {
              const isVisible = await link.isVisible().catch(() => false);
              if (!isVisible) continue;

              const text = await link.innerText().catch(() => "");
              const href = await link.getAttribute("href").catch(() => "");

              await link.click({ timeout: 5000 });
              await page.waitForLoadState("load", { timeout: 15000 }).catch(() => {});

              return { selector: `search → ${linkSel}`, text: text.trim().slice(0, 100), href };
            }
          } catch {
            continue;
          }
        }
      }
    } catch {
      continue;
    }
  }

  return null;
}

async function findApplyButton(page) {
  for (const selector of APPLY_SELECTORS) {
    try {
      const el = await page.$(selector);
      if (el) {
        const isVisible = await el.isVisible().catch(() => false);
        if (!isVisible) continue;

        const text = await el.innerText().catch(() => "");
        return { element: el, selector, description: text.trim().slice(0, 100) };
      }
    } catch {
      continue;
    }
  }
  return null;
}

async function clickElement(page, target) {
  try {
    await target.element.click({ timeout: 5000 });
    await page.waitForLoadState("load", { timeout: 15000 }).catch(() => {});
  } catch {
    // Click may have navigated or opened new tab — that's fine
  }
}

main();
