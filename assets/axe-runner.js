// Runs axe-core against a URL via Playwright and emits a structured JSON
// report to stdout. On failure, emits {error: <code>, message: <str>, ...}
// to stdout and exits 1. The Elixir Excessibility.Scanner module parses
// both shapes.

const { resolvePlaywright, resolveAxeBuilder, launchErrorHint } = require("./resolve-playwright");
const { chromium } = resolvePlaywright();
const AxeBuilder = resolveAxeBuilder();

const USAGE =
  "Usage: node axe-runner.js <url> " +
  "[--screenshot path] [--wait-for selector] [--wait-until load|domcontentloaded|networkidle] " +
  "[--disable-rules r1,r2] [--tags t1,t2] [--timeout ms] [--viewport WxH] " +
  "[--viewports WxH,WxH,...] [--check-clipping] [--clipping-ratio 0.9] [--user-agent ua]";

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
    viewports: null,
    checkClipping: false,
    clippingRatio: 0.9,
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
      case "--viewports": {
        if (next) {
          const parsed = next
            .split(",")
            .map((spec) => spec.split("x").map((s) => parseInt(s, 10)))
            .filter(([w, h]) => w > 0 && h > 0)
            .map(([w, h]) => ({ width: w, height: h }));
          if (parsed.length > 0) opts.viewports = parsed;
        }
        i++;
        break;
      }
      case "--check-clipping":
        opts.checkClipping = true;
        break;
      case "--clipping-ratio": {
        const ratio = parseFloat(next);
        if (!Number.isNaN(ratio) && ratio > 0 && ratio <= 1) opts.clippingRatio = ratio;
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
  // The flag only feeds the wait predicate below. Chromium also fires this
  // error event when the sheet loaded fine but a nested @import failed, so
  // it cannot be used to decide whether the stylesheet itself is missing —
  // the failed network requests are the authoritative signal for that.
  await page.addInitScript(() => {
    window.addEventListener(
      "error",
      (e) => {
        const t = e.target;
        if (t && t.tagName === "LINK" && (t.rel || "").includes("stylesheet")) {
          t.__excessibilityFailed = true;
        }
      },
      true,
    );
  });

  const failedStylesheetRequests = [];
  page.on("requestfailed", (request) => {
    if (request.resourceType() === "stylesheet") failedStylesheetRequests.push(request.url());
  });
  return failedStylesheetRequests;
}

async function waitForStylesheets(page, warnings, failedStylesheetRequests, maxWait = 10000) {
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

  // link.sheet cannot classify failures: under file:// Chromium attaches a
  // non-null empty CSSStyleSheet to a <link> whose file is missing. The
  // network view discriminates instead — a failed stylesheet request whose
  // URL matches a <link> href is that link failing; any other failed
  // stylesheet request is a nested @import. The null-sheet list is still
  // unioned in for sheets that downloaded but failed to parse, where no
  // request fails.
  const { linkHrefs, nullSheetHrefs } = await page
    .evaluate(() => {
      const links = [...document.querySelectorAll('link[rel~="stylesheet"]')];
      return {
        linkHrefs: links.map((l) => l.href),
        nullSheetHrefs: links.filter((l) => !l.sheet).map((l) => l.href),
      };
    })
    .catch(() => ({ linkHrefs: [], nullSheetHrefs: [] }));

  const linkHrefSet = new Set(linkHrefs);
  const failedLinks = new Set(nullSheetHrefs);
  const failedImports = new Set();
  for (const url of new Set(failedStylesheetRequests)) {
    if (linkHrefSet.has(url)) {
      failedLinks.add(url);
    } else {
      failedImports.add(url);
    }
  }

  for (const href of failedLinks) {
    warnings.push(`stylesheet failed to load: ${href} — contrast/layout findings are invalid until it exists`);
  }
  // Styling is degraded, not absent — fallback fonts change text metrics.
  for (const url of failedImports) {
    warnings.push(`stylesheet import failed: ${url} — text metrics may differ from production`);
  }

  await page.evaluate(() => document.fonts && document.fonts.ready).catch(() => {});
}

// axe has no rule for "this control is in the DOM but mostly outside the
// visible area" — the actual user-facing failure of WCAG 1.4.10 Reflow.
// Measures interactive elements' horizontal visibility and page-level
// horizontal overflow at the current viewport width.
async function measureClipping(page, ratioThreshold) {
  return page
    .evaluate((threshold) => {
      const selectors = ["a", "button", "input", "select", "textarea", "[phx-click]", '[role="button"]'];
      const innerW = window.innerWidth;

      const cssPath = (el) => {
        const tag = el.tagName.toLowerCase();
        if (el.id) return `${tag}#${el.id}`;
        const cls = (el.getAttribute("class") || "").trim().split(/\s+/)[0];
        return cls ? `${tag}.${cls}` : tag;
      };

      const clipped = [...document.querySelectorAll(selectors.join(","))]
        .map((el) => {
          const r = el.getBoundingClientRect();
          if (r.width === 0) return null; // hidden or unrendered
          const visible = Math.max(0, Math.min(r.right, innerW) - Math.max(r.left, 0));
          const ratio = visible / r.width;
          if (ratio >= threshold) return null;
          return {
            selector: cssPath(el),
            width: Math.round(r.width),
            visible: Math.round(visible),
            ratio: Math.round(ratio * 100) / 100,
            html: el.outerHTML.slice(0, 200),
          };
        })
        .filter(Boolean);

      // documentElement.scrollWidth misses overflow from absolutely
      // positioned boxes, which body.scrollWidth does report.
      const scrollW = Math.max(
        document.documentElement.scrollWidth,
        document.body ? document.body.scrollWidth : 0,
      );

      return {
        page_overflow: scrollW > innerW,
        clipped,
      };
    }, ratioThreshold)
    .catch(() => null);
}

function viewportScreenshotPath(basePath, vp) {
  const suffix = `${vp.width}x${vp.height}`;
  return /\.png$/i.test(basePath) ? basePath.replace(/\.png$/i, `.${suffix}.png`) : `${basePath}.${suffix}.png`;
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
  const {
    url,
    screenshotPath,
    waitFor,
    waitUntil,
    disableRules,
    tags,
    timeout,
    viewport,
    viewports,
    checkClipping,
    clippingRatio,
    userAgent,
  } = opts;

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
    viewport: viewports ? viewports[0] : viewport,
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

    const failedStylesheetRequests = await installStylesheetTracker(page);

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

    await waitForStylesheets(page, warnings, failedStylesheetRequests);

    const runAxe = async () => {
      let builder = new AxeBuilder({ page }).withTags(tags);
      if (disableRules.length > 0) builder = builder.disableRules(disableRules);
      return builder.analyze();
    };

    const takeScreenshot = async (screenshotFile) => {
      try {
        await page.screenshot({ path: screenshotFile, fullPage: true });
      } catch {
        // screenshot failure is non-fatal
      }
    };

    const baseOutput = () => ({
      final_url: page.url(),
      timestamp: new Date().toISOString(),
      duration_ms: Date.now() - startTime,
      warnings,
    });

    if (viewports) {
      const perViewport = [];
      let axeVersion = null;

      for (const vp of viewports) {
        await page.setViewportSize(vp);

        let results;
        try {
          results = await runAxe();
        } catch (err) {
          emitError("playwright_error", `axe-core analyze failed at ${vp.width}x${vp.height}: ${err.message}`);
          await closeQuietly(browser);
          process.exit(1);
        }

        if (screenshotPath) await takeScreenshot(viewportScreenshotPath(screenshotPath, vp));

        const clipping = checkClipping ? await measureClipping(page, clippingRatio) : null;

        axeVersion = (results && results.testEngine && results.testEngine.version) || axeVersion;
        perViewport.push({
          viewport: `${vp.width}x${vp.height}`,
          violations: results.violations || [],
          incomplete: results.incomplete || [],
          passes_count: (results.passes || []).length,
          inapplicable_count: (results.inapplicable || []).length,
          ...(clipping ? { clipping } : {}),
        });
      }

      console.log(
        JSON.stringify({
          ...baseOutput(),
          engine: { axe_version: axeVersion, chromium_version: chromiumVersion },
          results: perViewport,
        }),
      );
      await closeQuietly(browser);
      return;
    }

    let results;
    try {
      results = await runAxe();
    } catch (err) {
      emitError("playwright_error", `axe-core analyze failed: ${err.message}`);
      await closeQuietly(browser);
      process.exit(1);
    }

    if (screenshotPath) await takeScreenshot(screenshotPath);

    const clipping = checkClipping ? await measureClipping(page, clippingRatio) : null;

    const output = {
      ...baseOutput(),
      engine: {
        axe_version: results && results.testEngine ? results.testEngine.version || null : null,
        chromium_version: chromiumVersion,
      },
      violations: results.violations || [],
      incomplete: results.incomplete || [],
      passes_count: (results.passes || []).length,
      inapplicable_count: (results.inapplicable || []).length,
      ...(clipping ? { clipping } : {}),
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
