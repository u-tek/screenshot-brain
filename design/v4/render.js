// Renders each mockup at iPhone size: node render.js home triage ...
const { chromium } = require("playwright");
const path = require("path");
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 393, height: 852 }, deviceScaleFactor: 2 });
  for (const name of process.argv.slice(2)) {
    await page.goto("file://" + path.join(__dirname, name + ".html"));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    const errors = await page.evaluate(() => window.__errors || []);
    await page.screenshot({ path: path.join(__dirname, "out", name + ".png") });
    console.log("rendered", name, errors.length ? errors : "");
  }
  await browser.close();
})();
