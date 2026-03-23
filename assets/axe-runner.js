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

  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    if (waitFor) await page.waitForSelector(waitFor, { timeout: 10000 });

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

main();
