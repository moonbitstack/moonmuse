// Render scripts/og.html to site/og.png, the image a feed shows when the page is shared.
//
//     node scripts/og.mjs
//
// Twice the density, so the card stays sharp on a retina screen; the layout itself is 1200 by
// 630, which is the size every feed expects.
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const port = 9600 + Math.floor(Math.random() * 300);
const chrome = spawn(
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  [
    "--headless=new",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${join(root, "_build", "og-profile")}`,
    "--disable-gpu",
    "--hide-scrollbars",
    "about:blank",
  ],
  { stdio: "ignore" },
);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function page() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const found = list.find(t => t.type === "page");
      if (found) return found.webSocketDebuggerUrl;
    } catch (e) {}
    await sleep(150);
  }
  throw new Error("devtools did not answer");
}

const socket = new WebSocket(await page());
await new Promise(r => socket.addEventListener("open", r));
let id = 0;
const pending = new Map();
socket.addEventListener("message", e => {
  const message = JSON.parse(e.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
  }
});
const send = (method, params = {}) => {
  const messageId = ++id;
  socket.send(JSON.stringify({ id: messageId, method, params }));
  return new Promise((resolve, reject) => pending.set(messageId, { resolve, reject }));
};

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", {
  width: 1200,
  height: 630,
  deviceScaleFactor: 2,
  mobile: false,
});
await send("Page.navigate", { url: pathToFileURL(join(root, "scripts", "og.html")).href });
// The card is set in two web fonts, so the shot waits for them rather than for a fixed delay:
// a card in the fallback face is a card of the wrong design.
await sleep(200);
await send("Runtime.evaluate", { expression: "document.fonts.ready", awaitPromise: true });
const loaded = await send("Runtime.evaluate", {
  expression: "document.fonts.check('700 92px Caveat') + ' ' + getComputedStyle(document.querySelector('h1')).fontFamily",
  returnByValue: true,
});
console.log("caveat:", loaded.result.value);
await sleep(250);
const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
writeFileSync(join(root, "site", "og.png"), Buffer.from(shot.data, "base64"));
socket.close();
chrome.kill();
console.log("wrote site/og.png");
process.exit(0);
