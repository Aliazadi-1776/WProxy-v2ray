// Exercise the installed Tauri/WebView2 application and real command bridge.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";

assert.equal(process.platform, "win32", "This test requires native Windows/WebView2");
const [installation, outputDirectory] = process.argv.slice(2);
assert(installation && outputDirectory, "usage: node windows-desktop-smoke.mjs INSTALLATION OUTPUT");
await mkdir(outputDirectory, { recursive: true });
const profile = await mkdtemp(path.join(os.tmpdir(), "wproxy-ui-test-"));
const listener = net.createServer();
await new Promise((resolve) => listener.listen(0, "127.0.0.1", resolve));
const port = listener.address().port;
await new Promise((resolve) => listener.close(resolve));
const environment = {
  ...process.env,
  APPDATA: path.join(profile, "roaming"),
  LOCALAPPDATA: path.join(profile, "local"),
  WEBVIEW2_USER_DATA_FOLDER: path.join(profile, "webview"),
  WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1`,
};
const cli = path.join(installation, "wproxyctl.exe");
function ctl(args) {
  const result = spawnSync(cli, args, { env: environment, encoding: "utf8", windowsHide: true, timeout: 30000 });
  assert.equal(result.status, 0, result.stderr || result.error?.message || "Command engine failed");
  return result.stdout;
}
const fixtureName = "CI Windows · Berlin";
const tunnelUri = process.env.WPROXY_TEST_URI;
if (tunnelUri) assert.equal(process.env.GITHUB_ACTIONS, "true", "UI route changes require a disposable Actions runner");
ctl(["node", "add", tunnelUri || "trojan://synthetic@example.invalid:443?security=tls#CI", "--name", fixtureName]);
const app = spawn(path.join(installation, "WProxy.exe"), [], { env: environment, cwd: installation, stdio: "ignore" });
const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
let socket;
let sequence = 0;
let recovery;
let uiTunnel = null;
const cancel = path.join(profile, "cancel-ui-watchdog");
const pending = new Map();
async function command(method, params = {}) {
  const id = ++sequence;
  const result = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timer });
  });
  socket.send(JSON.stringify({ id, method, params }));
  return result;
}
async function evaluate(expression) {
  const value = await command("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  assert(!value.exceptionDetails, JSON.stringify(value.exceptionDetails));
  return value.result.value;
}
async function waitFor(expression, label, attempts = 60) {
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (await evaluate(expression)) return;
    await delay(250);
  }
  throw new Error(`Timed out waiting for ${label}`);
}
async function screenshot(name) {
  const { data } = await command("Page.captureScreenshot", { format: "png" });
  await writeFile(path.join(outputDirectory, name), Buffer.from(data, "base64"));
}
async function assertLayout() {
  const layout = await evaluate(`(() => {
    const sidebar = document.querySelector('.sidebar').getBoundingClientRect();
    const content = document.querySelector('#content').getBoundingClientRect();
    const buttons = [...document.querySelectorAll('#content button')].filter(b => !b.disabled);
    return { width: innerWidth, sidebar: sidebar.width, content: content.width,
      overflow: document.documentElement.scrollWidth > innerWidth + 1,
      clipped: buttons.filter(b => { const r=b.getBoundingClientRect(); return r.width < 20 || r.right > innerWidth + 1 || r.left < sidebar.right - 1; }).map(b => b.textContent) };
  })()`);
  assert(layout.sidebar >= 130 && layout.content >= 500, JSON.stringify(layout));
  assert.equal(layout.overflow, false, JSON.stringify(layout));
  assert.deepEqual(layout.clipped, [], JSON.stringify(layout));
  return layout.width;
}
try {
  let target;
  for (let attempt = 0; attempt < 120; attempt++) {
    assert(app.exitCode === null, `Installed desktop exited: ${app.exitCode}`);
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      target = (await response.json()).find((item) => item.type === "page" && item.webSocketDebuggerUrl);
      if (target) break;
    } catch { /* WebView2 initializes asynchronously. */ }
    await delay(250);
  }
  assert(target, "Installed WebView2 did not expose a page for inspection");
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.addEventListener("open", resolve, { once: true }); socket.addEventListener("error", reject, { once: true }); });
  socket.addEventListener("message", ({ data }) => {
    const message = JSON.parse(data);
    const request = pending.get(message.id);
    if (!request) return;
    clearTimeout(request.timer);
    pending.delete(message.id);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  });
  await waitFor("document.querySelector('.server-row') !== null", "the real server list");
  assert.equal(await evaluate("window.__TAURI_INTERNALS__.invoke('platform')"), "windows");
  const bridge = await evaluate("window.__TAURI_INTERNALS__.invoke('run_ctl', {args:['node','list','--json']})");
  assert.equal(JSON.parse(bridge.stdout)[0].name, fixtureName);
  assert(await evaluate(`document.querySelector('.server-row').textContent.includes(${JSON.stringify(fixtureName)})`));
  const defaultWidth = await assertLayout();
  await screenshot("windows-servers-default.png");

  if (tunnelUri) {
    assert(process.env.WPROXY_TEST_PYTHON && process.env.WPROXY_TEST_WATCHDOG, "The native UI connection test requires the independent watchdog");
    recovery = spawn(process.env.WPROXY_TEST_PYTHON, [
      process.env.WPROXY_TEST_WATCHDOG, installation, outputDirectory, "--watchdog", cancel,
    ], { env: environment, detached: true, windowsHide: true, stdio: "ignore" });
    recovery.unref();
    for (let attempt = 0; attempt < 100; attempt++) {
      assert.equal(recovery.exitCode, null, "UI network recovery watchdog exited before it was armed");
      if (existsSync(`${cancel}.armed`)) break;
      await delay(50);
    }
    assert(existsSync(`${cancel}.armed`), "UI network recovery watchdog did not arm");
    await evaluate("document.querySelector('[data-action=connect]').click()");
    await waitFor("document.querySelector('.server-row.is-connected') !== null", "a connection through the real Rust elevation bridge", 360);
    const connected = JSON.parse(ctl(["windows", "status", "--json"]));
    assert(connected.active && connected.verified, JSON.stringify(connected));
    assert(await evaluate("document.querySelector('.connection-hero.is-online') !== null"));
    await screenshot("windows-connected-through-ui.png");
    await evaluate("document.querySelector('[data-action=disconnect]').click()");
    await waitFor("document.querySelector('.server-row.is-connected') === null", "Disconnect through the real Rust elevation bridge", 120);
    assert.equal(JSON.parse(ctl(["windows", "status", "--json"])).active, false);
    await writeFile(cancel, "disconnected");
    uiTunnel = { connected: true, verified: true, disconnected: true, rustElevationBridge: true };
  }

  await evaluate("document.querySelector('[data-page=add]').click()");
  await waitFor("document.querySelector('#node-form') !== null", "Add connection");
  await evaluate(`(() => {
    const form=document.querySelector('#node-form');
    form.elements.name.value='CI added through native UI';
    form.elements.uri.value='trojan://synthetic@example.invalid:444?security=tls#CI-added';
    form.requestSubmit();
  })()`);
  await waitFor("document.querySelectorAll('.server-row').length === 2", "a server saved through the UI bridge");
  const saved = JSON.parse(ctl(["node", "list", "--json"]));
  assert(saved.some((node) => node.name === "CI added through native UI"), "UI save did not persist through the frozen CLI");
  const added = saved.find((node) => node.name === "CI added through native UI");
  await evaluate(`document.querySelector('[data-action=remove-node][data-node="${added.id}"]').click()`);
  await waitFor("document.querySelectorAll('.server-row').length === 1", "server removal");
  assert.equal(JSON.parse(ctl(["node", "list", "--json"])).length, 1);

  await evaluate("document.querySelector('[data-page=routing]').click()");
  await waitFor("document.querySelector('[data-action=choose-app]') !== null", "native application picker action");
  await assertLayout();
  await screenshot("windows-routing-default.png");
  await command("Emulation.setDeviceMetricsOverride", { width: 960, height: 640, deviceScaleFactor: 1, mobile: false });
  await assertLayout();
  await screenshot("windows-routing-minimum.png");
  await evaluate("document.querySelector('[data-page=settings]').click()");
  assert(await evaluate("document.querySelector('#content').textContent.includes('Automatic updates')"));
  await screenshot("windows-settings.png");
  await writeFile(path.join(outputDirectory, "desktop-result.json"), JSON.stringify({
    platform: "windows", installed: true, rendered: true, bridge: true,
    addAndRemovePersisted: true, widths: [defaultWidth, 960], screenshots: tunnelUri ? 5 : 4,
    uiTunnel,
  }, null, 2));
  console.log("Installed native Windows UI: PASS (rendered assets, Tauri bridge, persisted add/remove, routing layout, screenshots)");
} catch (error) {
  if (socket?.readyState === WebSocket.OPEN) {
    try {
      await screenshot("windows-ui-failure.png");
      await writeFile(path.join(outputDirectory, "desktop-failure.json"), JSON.stringify({
        error: String(error),
        page: await evaluate("({url:location.href,text:document.body.innerText})"),
      }, null, 2));
    } catch { /* Preserve the original failure if WebView2 also crashed. */ }
  }
  throw error;
} finally {
  let recoveryError;
  if (recovery) {
    try {
      ctl(["windows", "down"]);
      await writeFile(cancel, "disconnected");
    } catch (error) {
      recoveryError = error; // Leave the independent watchdog armed if cleanup failed.
    }
  }
  socket?.close();
  for (const request of pending.values()) clearTimeout(request.timer);
  spawnSync("taskkill", ["/PID", String(app.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
  if (recoveryError) throw recoveryError;
}
