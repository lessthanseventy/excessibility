// Resolves the Playwright installation shared by axe-runner.js and
// axe-crawl.js. Resolution order:
//
//   1. EXCESSIBILITY_PLAYWRIGHT_PATH (set via `config :excessibility,
//      playwright_path: "..."`) — reuse a host project's installation
//   2. the bundled copy under assets/node_modules
//   3. ambient Node resolution (project node_modules / NODE_PATH)
//
// Failures emit the same {error, message} JSON shape the Elixir side
// already parses, with an actionable command instead of a bare stack.

const path = require("path");

const modulesDir = path.join(__dirname, "node_modules");

function fail(message) {
  console.log(JSON.stringify({ error: "playwright_error", message }));
  process.exit(1);
}

function resolvePlaywright() {
  const override = process.env.EXCESSIBILITY_PLAYWRIGHT_PATH;
  if (override) {
    try {
      return require(override);
    } catch (err) {
      return fail(
        `failed to load playwright from EXCESSIBILITY_PLAYWRIGHT_PATH=${override}: ${err.message}`,
      );
    }
  }

  try {
    return require(path.join(modulesDir, "playwright"));
  } catch {
    // fall through to ambient resolution
  }

  try {
    return require("playwright");
  } catch {
    return fail(
      `playwright not found. Run: cd ${__dirname} && npm install && npx playwright install chromium — ` +
        "or set `config :excessibility, playwright_path: ...` to reuse an existing installation",
    );
  }
}

// Playwright's own launch error says "npx playwright install" without
// saying where to run it; running it in the wrong directory installs
// browsers for the wrong Playwright version and the error repeats.
function launchErrorHint() {
  const override = process.env.EXCESSIBILITY_PLAYWRIGHT_PATH;
  if (override) {
    return `To download browsers for the Playwright at ${override}, run npx playwright install chromium in that project.`;
  }
  return `To download browsers for the bundled Playwright, run: cd ${__dirname} && npx playwright install chromium`;
}

module.exports = { resolvePlaywright, launchErrorHint, modulesDir };
