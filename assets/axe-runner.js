// Runs axe-core against a URL via Playwright and emits a structured JSON
// report to stdout. On failure, emits {error: <code>, message: <str>, ...}
// to stdout and exits 1. The Elixir Excessibility.Scanner module parses
// both shapes.

const path = require("path");
const { resolvePlaywright, launchErrorHint, modulesDir } = require("./resolve-playwright");
const { chromium } = resolvePlaywright();
const { AxeBuilder } = require(path.join(modulesDir, "@axe-core", "playwright"));

const USAGE =
  "Usage: node axe-runner.js <url> " +
  "[--screenshot path] [--wait-for selector] [--wait-until load|domcontentloaded|networkidle] " +
  "[--disable-rules r1,r2] [--tags t1,t2] [--timeout ms] [--viewport WxH] [--user-agent ua]";

const DEFAULT_UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

function emitError(code, message, extra = {}) {
  console.log(JSON.stringify({ error: code, message: message || "", ...extra }));
}

async function closeQuietly(browser) {
  try {
    if (browser) await browser.close();
  } catch {
    // nothing useful we can do
  }
}

function parseArgs(argv) {
  const url = argv[0];
  const opts = {
    url,
    screenshotPath: null,
    waitFor: null,
    waitUntil: null,
    disableRules: [],
    tags: ["wcag2a", "wcag2aa"],
    timeout: 30000,
    viewport: { width: 1280, height: 720 },
    userAgent: null,
  };

  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case "--screenshot":
        opts.screenshotPath = next;
        i++;
        break;
      case "--wait-for":
        opts.waitFor = next;
        i++;
        break;
      case "--wait-until":
        opts.waitUntil = next;
        i++;
        break;
      case "--disable-rules":
        opts.disableRules = next ? next.split(",").filter(Boolean) : [];
        i++;
        break;
      case "--tags":
        opts.tags = next ? next.split(",").filter(Boolean) : opts.tags;
        i++;
        break;
      case "--timeout": {
        const n = parseInt(next, 10);
        if (!Number.isNaN(n) && n > 0) opts.timeout = n;
        i++;
        break;
      }
      case "--viewport": {
        if (next) {
          const [w, h] = next.split("x").map((s) => parseInt(s, 10));
          if (w > 0 && h > 0) opts.viewport = { width: w, height: h };
        }
        i++;
        break;
      }
      case "--user-agent":
        opts.userAgent = next;
        i++;
        break;
    }
  }

  return opts;
}

// domcontentloaded/load do not guarantee linked stylesheets are applied,
// and axe results are invalid on unstyled markup (contrast rules see no
// colors, hidden containers are visible). Wait until every linked
// stylesheet has either loaded or errored, then report failures so
// callers know styled-dependent findings can't be trusted.
async function installStylesheetTracker(page) {
  await page.addInitScript(() => {
    window.__excessibilityFailedStylesheets = [];
    window.addEventListener(
      "error",
      (e) => {
        const t = e.target;
        if (t && t.tagName === "LINK" && (t.rel || "").includes("stylesheet")) {
          t.__excessibilityFailed = true;
          window.__excessibilityFailedStylesheets.push(t.href);
        }
      },
      true,
    );
  });
}

async function waitForStylesheets(page, warnings, maxWait = 10000) {
  const hasLinks = await page
    .evaluate(() => document.querySelectorAll('link[rel~="stylesheet"]').length > 0)
    .catch(() => false);
  if (!hasLinks) return;

  await page
    .waitForFunction(
      () => {
        const links = [...document.querySelectorAll('link[rel~="stylesheet"]')];
        return links.every((l) => l.sheet || l.__excessibilityFailed);
      },
      null,
      { timeout: maxWait },
    )
    .catch(() => {
      warnings.push(
        `stylesheets did not finish loading within ${maxWait}ms — contrast/layout findings may be invalid`,
      );
    });

  const failed = await page.evaluate(() => window.__excessibilityFailedStylesheets || []).catch(() => []);
  for (const href of failed) {
    warnings.push(`stylesheet failed to load: ${href} — contrast/layout findings are invalid until it exists`);
  }

  await page.evaluate(() => document.fonts && document.fonts.ready).catch(() => {});
}

async function waitForContent(page, maxWait = 8000) {
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    const bodyText = await page
      .evaluate(() => (document.body && document.body.innerText ? document.body.innerText.trim() : ""))
      .catch(() => "");
    if (bodyText.length > 50) return;
    await new Promise((r) => setTimeout(r, 500));
  }
}

async function main() {
  const argv = process.argv.slice(2);
  if (!argv[0]) {
    emitError("invalid_args", USAGE);
    process.exit(1);
  }

  const opts = parseArgs(argv);
  const { url, screenshotPath, waitFor, waitUntil, disableRules, tags, timeout, viewport, userAgent } = opts;

  const isFileUrl = url.startsWith("file://");
  const startTime = Date.now();

  let browser;
  try {
    browser = await chromium.launch();
  } catch (err) {
    emitError("playwright_error", `failed to launch chromium: ${err.message}\n${launchErrorHint()}`);
    process.exit(1);
  }

  const chromiumVersion = browser.version();

  const contextOptions = {
    viewport,
    locale: "en-US",
  };
  if (!isFileUrl) {
    contextOptions.userAgent = userAgent || DEFAULT_UA;
  } else if (userAgent) {
    contextOptions.userAgent = userAgent;
  }

  let context;
  let page;
  try {
    context = await browser.newContext(contextOptions);
    page = await context.newPage();
  } catch (err) {
    emitError("playwright_error", `failed to create browser context: ${err.message}`);
    await closeQuietly(browser);
    process.exit(1);
  }

  const warnings = [];

  try {
    const effectiveWaitUntil = waitUntil || "load";

    await installStylesheetTracker(page);

    let response;
    try {
      response = await page.goto(url, { waitUntil: effectiveWaitUntil, timeout });
    } catch (err) {
      if (err.name === "TimeoutError") {
        emitError("timeout", err.message);
      } else {
        emitError("navigation_failed", err.message);
      }
      await closeQuietly(browser);
      process.exit(1);
    }

    if (response && !isFileUrl) {
      const status = response.status();
      if (status >= 400) {
        emitError("http_error", `HTTP ${status}`, { status });
        await closeQuietly(browser);
        process.exit(1);
      }
    }

    if (waitFor) {
      try {
        await page.waitForSelector(waitFor, { timeout: Math.min(timeout, 10000) });
      } catch (err) {
        if (err.name === "TimeoutError") {
          emitError("timeout", `wait_for '${waitFor}' timed out`);
        } else {
          emitError("playwright_error", err.message);
        }
        await closeQuietly(browser);
        process.exit(1);
      }
    } else if (!isFileUrl) {
      await waitForContent(page);
    }

    await waitForStylesheets(page, warnings);

    let builder = new AxeBuilder({ page }).withTags(tags);
    if (disableRules.length > 0) builder = builder.disableRules(disableRules);

    let results;
    try {
      results = await builder.analyze();
    } catch (err) {
      emitError("playwright_error", `axe-core analyze failed: ${err.message}`);
      await closeQuietly(browser);
      process.exit(1);
    }

    if (screenshotPath) {
      try {
        await page.screenshot({ path: screenshotPath, fullPage: true });
      } catch {
        // screenshot failure is non-fatal
      }
    }

    const output = {
      final_url: page.url(),
      timestamp: new Date().toISOString(),
      duration_ms: Date.now() - startTime,
      engine: {
        axe_version: results && results.testEngine ? results.testEngine.version || null : null,
        chromium_version: chromiumVersion,
      },
      violations: results.violations || [],
      incomplete: results.incomplete || [],
      passes_count: (results.passes || []).length,
      inapplicable_count: (results.inapplicable || []).length,
      warnings,
    };

    console.log(JSON.stringify(output));
    await closeQuietly(browser);
  } catch (err) {
    emitError("playwright_error", err.message);
    await closeQuietly(browser);
    process.exit(1);
  }
}

main();
