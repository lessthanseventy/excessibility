const path = require("path");
const modulesDir = path.join(__dirname, "node_modules");
const { chromium } = require(path.join(modulesDir, "playwright"));
const { AxeBuilder } = require(path.join(modulesDir, "@axe-core", "playwright"));

async function main() {
  const args = process.argv.slice(2);
  const url = args[0];
  if (!url) {
    console.error(JSON.stringify({ error: "Usage: node axe-runner.js <url> [--screenshot path] [--wait-for selector] [--disable-rules rule1,rule2]" }));
    process.exit(1);
  }

  let screenshotPath = null;
  let waitFor = null;
  let disableRules = [];

  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--screenshot" && args[i + 1]) screenshotPath = args[++i];
    else if (args[i] === "--wait-for" && args[i + 1]) waitFor = args[++i];
    else if (args[i] === "--disable-rules" && args[i + 1]) disableRules = args[++i].split(",");
  }

  const isFileUrl = url.startsWith("file://");

  const browser = await chromium.launch();
  const context = await browser.newContext({
    // Look like a real browser for remote URLs
    ...(!isFileUrl && {
      userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
      viewport: { width: 1280, height: 720 },
      locale: "en-US",
    }),
  });
  const page = await context.newPage();

  try {
    // file:// URLs just need DOM; remote URLs wait for load event then we poll for content
    const waitUntil = isFileUrl ? "domcontentloaded" : "load";
    await page.goto(url, { waitUntil, timeout: 30000 });

    if (waitFor) {
      await page.waitForSelector(waitFor, { timeout: 10000 });
    } else if (!isFileUrl) {
      // For SPAs: if body looks empty after load, give it more time
      await waitForContent(page);
    }

    let builder = new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]);
    if (disableRules.length > 0) builder = builder.disableRules(disableRules);

    const results = await builder.analyze();

    if (screenshotPath) await page.screenshot({ path: screenshotPath, fullPage: true });

    console.log(JSON.stringify(results));
  } catch (err) {
    console.error(JSON.stringify({ error: err.message }));
    process.exit(1);
  } finally {
    await browser.close();
  }
}

// Wait for SPA content to render — checks that body has meaningful content
async function waitForContent(page, maxWait = 8000) {
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    const bodyText = await page.evaluate(() => document.body?.innerText?.trim() || "");
    // If body has more than a few chars of text, content has rendered
    if (bodyText.length > 50) return;
    await new Promise((r) => setTimeout(r, 500));
  }
  // Timed out waiting for content — run axe anyway on whatever's there
}

main();
