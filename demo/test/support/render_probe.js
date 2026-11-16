// Renders each URL with JavaScript off (a snapshot has its scripts stripped)
// and prints, per viewport, what a reader would see: the render mode, the
// visible text, every element's box, and any subresource that failed to load.
//
//   node render_probe.js 1280x800,375x800 URL...

const path = require("node:path");
const { resolvePlaywright } = require(path.join(__dirname, "../../../assets/resolve-playwright"));

const [viewportsArg, ...urls] = process.argv.slice(2);
const { chromium } = resolvePlaywright();

function describe() {
  const label = (el) =>
    el.tagName.toLowerCase() + (el.id && !el.id.startsWith("phx-") ? `#${el.id}` : "") + (el.classList[0] ? `.${el.classList[0]}` : "");

  const elements = [...document.body.querySelectorAll("*")]
    .filter((el) => el.tagName !== "SCRIPT")
    .map((el) => {
      const r = el.getBoundingClientRect();
      return {
        el: label(el),
        text: (el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 40),
        box: [r.x, r.y, r.width, r.height].map(Math.round),
      };
    });

  // biome-ignore lint/performance/useDomNodeTextContent: the rendered text, with whitespace collapsed as the reader sees it, is the point
  return { compat_mode: document.compatMode, text: document.body.innerText, elements };
}

async function probe(context, url) {
  const page = await context.newPage();
  const failed = [];
  page.on("requestfailed", (req) => failed.push(req.url()));
  page.on("response", (res) => res.status() >= 400 && failed.push(`${res.status()} ${res.url()}`));

  await page.goto(url, { waitUntil: "load" });
  // Settled as axe-runner.js settles a page before its scan and screenshot:
  // measured mid-fade, the two sides differ by the animation's progress.
  // addStyleTag waits on a load event that never fires with JavaScript off.
  await page.evaluate(() => {
    const style = document.createElement("style");
    style.textContent =
      "*, *::before, *::after { animation-duration: 0s !important; animation-delay: 0s !important;" +
      " transition-duration: 0s !important; transition-delay: 0s !important; }";
    document.head.append(style);
    for (const animation of document.getAnimations()) animation.finish();
    return document.fonts.ready;
  });
  const result = await page.evaluate(describe);
  await page.close();
  return { url, failed, ...result };
}

(async () => {
  const browser = await chromium.launch();
  const out = {};

  for (const spec of viewportsArg.split(",")) {
    const [width, height] = spec.split("x").map(Number);
    const context = await browser.newContext({
      javaScriptEnabled: false,
      reducedMotion: "reduce",
      viewport: { width, height },
    });
    out[spec] = [];
    for (const url of urls) out[spec].push(await probe(context, url));
    await context.close();
  }

  await browser.close();
  console.log(JSON.stringify(out));
})().catch((err) => {
  console.log(JSON.stringify({ error: err.message }));
  process.exit(1);
});
