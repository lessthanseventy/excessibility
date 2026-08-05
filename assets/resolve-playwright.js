// Resolves the node modules shared by axe-runner.js and axe-crawl.js
// (playwright and @axe-core/playwright). Resolution order:
//
//   1. EXCESSIBILITY_PLAYWRIGHT_PATH (set via `config :excessibility,
//      playwright_path: "..."`) — reuse a host project's Playwright
//   2. EXCESSIBILITY_NODE_MODULES_PATH (set via `config :excessibility,
//      node_modules_path: "..."`) — reuse a host node_modules directory
//      for every module, not just Playwright
//   3. the bundled copy under assets/node_modules
//   4. ambient Node resolution (project node_modules / NODE_PATH)
//
// Failures emit the same {error, message} JSON shape the Elixir side
// already parses, with an actionable command instead of a bare stack.

const path = require("path");

const modulesDir = path.join(__dirname, "node_modules");

function fail(message) {
  console.log(JSON.stringify({ error: "playwright_error", message }));
  process.exit(1);
}

// An explicitly configured node_modules override is intent, so a miss
// there is an error rather than a silent fall-through to the bundled
// copy — otherwise a typo'd path quietly changes which axe version runs.
function resolveModule(name, notFoundHint) {
  const segments = name.split("/");

  const override = process.env.EXCESSIBILITY_NODE_MODULES_PATH;
  if (override) {
    try {
      return require(path.join(override, ...segments));
    } catch (err) {
      return fail(`failed to load ${name} from EXCESSIBILITY_NODE_MODULES_PATH=${override}: ${err.message}`);
    }
  }

  try {
    return require(path.join(modulesDir, ...segments));
  } catch {
    // fall through to ambient resolution
  }

  try {
    return require(name);
  } catch {
    return fail(notFoundHint);
  }
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

  return resolveModule(
    "playwright",
    `playwright not found. Run: cd ${__dirname} && npm install && npx playwright install chromium — ` +
      "or set `config :excessibility, playwright_path: ...` (or `node_modules_path: ...`) to reuse an existing installation",
  );
}

function resolveAxeBuilder() {
  const mod = resolveModule(
    "@axe-core/playwright",
    `@axe-core/playwright not found. Run: cd ${__dirname} && npm install — ` +
      "or set `config :excessibility, node_modules_path: ...` to reuse a host node_modules that provides it",
  );
  return mod.AxeBuilder;
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

module.exports = { resolvePlaywright, resolveAxeBuilder, resolveModule, launchErrorHint, modulesDir };
