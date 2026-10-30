// Upgrade the published Windows application through its real Automatic updates control.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";

assert.equal(process.platform, "win32", "This test requires native Windows/WebView2");
assert.equal(process.env.GITHUB_ACTIONS, "true", "Run only on a disposable GitHub Actions runner");
const fromVersion = "2.7.4";
const targetVersion = "2.7.7";
const baselineSha256 = "6a428f8f6fdc72dda38c399dde71953e0bcadbdb247540f3a6a2a3c7664cdfa1";
const repository = "Aliazadi-1776/WProxy-v2ray";
const output = path.resolve(process.argv[2] || "build/windows-update/test-results");
await mkdir(output, { recursive: true });
const profile = await mkdtemp(path.join(os.tmpdir(), "wproxy-upgrade-"));
const installation = path.join(profile, "installation");
const listener = net.createServer();
await new Promise(resolve => listener.listen(0, "127.0.0.1", resolve));
const port = listener.address().port;
await new Promise(resolve => listener.close(resolve));
const environment = {
  ...process.env,
  APPDATA: path.join(profile, "roaming"),
  LOCALAPPDATA: path.join(profile, "local"),
  WEBVIEW2_USER_DATA_FOLDER: path.join(profile, "webview"),
  WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1`,
};
const cli = path.join(installation, "wproxyctl.exe");
const executable = path.join(installation, "WProxy.exe");
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
const ipc = [];
let socket;
let app;
let sequence = 0;
let installedVersion = "";
const pending = new Map();
function ctl(args, strict = true) {
  const result = spawnSync(cli, args, { env: environment, encoding: "utf8", windowsHide: true, timeout: 10000 });
  if (strict) assert.equal(result.status, 0, result.stderr || result.error?.message || "Command engine failed");
  return result.status === 0 ? result.stdout.trim() : "";
}
async function download(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(120000) });
  assert(response.ok, `${url}: HTTP ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}
function command(method, params = {}) {
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
async function waitFor(expression) {
  for (let attempt = 0; attempt < 120; attempt++) {
    if (await evaluate(expression)) return;
    await delay(250);
  }
  throw new Error(`Timed out waiting for ${expression}`);
}
async function screenshot(name) {
  const { data } = await command("Page.captureScreenshot", { format: "png" });
  await writeFile(path.join(output, name), Buffer.from(data, "base64"));
}
async function launch() {
  app = spawn(executable, [], { env: environment, cwd: installation, stdio: "ignore" });
  let target;
  for (let attempt = 0; attempt < 120; attempt++) {
    assert.equal(app.exitCode, null, `WProxy exited: ${app.exitCode}`);
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      target = (await response.json()).find(item => item.type === "page" && item.webSocketDebuggerUrl);
      if (target) break;
    } catch { /* WebView2 initializes asynchronously. */ }
    await delay(250);
  }
  assert(target, "WebView2 did not expose the installed application");
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
  socket.addEventListener("message", ({ data }) => {
    const message = JSON.parse(data);
    if (message.method === "Runtime.consoleAPICalled") {
      const values = message.params.args.map(arg => arg.value);
      if (values[0] === "WPROXY_UPDATE_TEST_IPC") ipc.push(JSON.parse(values[1]));
    }
    const request = pending.get(message.id);
    if (!request) return;
    clearTimeout(request.timer);
    pending.delete(message.id);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  });
  await command("Runtime.enable");
  await waitFor("document.querySelector('[data-page=settings]') !== null");
  await evaluate("document.querySelector('[data-page=settings]').click()");
  await waitFor("document.querySelector('[data-setting=auto-update]') !== null");
}
function stopApplication() {
  socket?.close();
  const escaped = executable.replaceAll("'", "''");
  // Restart Manager may have relaunched WProxy; restrict cleanup to this isolated installation.
  spawnSync("powershell.exe", ["-NoProfile", "-Command",
    `Get-Process WProxy -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq '${escaped}' } | Stop-Process -Force`,
  ], { encoding: "utf8", windowsHide: true, timeout: 15000 });
}
try {
  const release = JSON.parse((await download(`https://api.github.com/repos/${repository}/releases/latest`)).toString());
  assert.equal(release.tag_name, `v${targetVersion}`, "This pinned regression needs its target to remain the latest release");
  const manifest = (await download(`https://github.com/${repository}/releases/download/v${targetVersion}/SHA256SUMS`)).toString();
  const targetAsset = `WProxy-${targetVersion}-Setup.exe`;
  const expectedTargetHash = manifest.split(/\r?\n/).find(line => line.endsWith(`  ${targetAsset}`))?.split("  ")[0];
  assert.match(expectedTargetHash || "", /^[a-f0-9]{64}$/);
  const baseline = await download(`https://github.com/${repository}/releases/download/v${fromVersion}/WProxy-${fromVersion}-Setup.exe`);
  assert.equal(digest(baseline), baselineSha256, "Published baseline installer SHA256 changed");
  const setup = path.join(profile, `WProxy-${fromVersion}-Setup.exe`);
  await writeFile(setup, baseline);
  const install = spawnSync(setup, ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", `/DIR=${installation}`, `/LOG=${path.join(output, "baseline-setup.log")}`],
    { env: environment, encoding: "utf8", windowsHide: true, timeout: 180000 });
  assert.equal(install.status, 0, install.error?.message || `Baseline Setup failed: ${install.status}`);
  assert.equal(ctl(["--version"]), `WProxy ${fromVersion}`);
  assert.equal(JSON.parse(ctl(["settings", "show", "--json"])).auto_update, false);
  ctl(["node", "add", "trojan://synthetic@example.invalid:443?security=tls#upgrade-fixture", "--name", "Upgrade persistence fixture"]);
  const nodes = JSON.parse(ctl(["node", "list", "--json"]));
  await launch();
  assert(await evaluate(`document.body.textContent.includes('WProxy ${fromVersion}')`));
  assert.equal(await evaluate("document.querySelector('[data-setting=auto-update]').checked"), false);
  await screenshot("before-update.png");
  await evaluate(`(() => {
    const original = window.fetch;
    window.fetch = function(resource, options) {
      const method = String(resource).split('/').pop();
      if ((method === 'run_ctl' || method === 'install_update') && typeof options?.body === 'string') {
        const args = JSON.parse(options.body);
        if (method === 'install_update' || (args.args?.[0] === 'update' && args.args?.[1] === 'download'))
          console.info('WPROXY_UPDATE_TEST_IPC', JSON.stringify({method,args}));
      }
      return original.call(this, resource, options);
    };
    document.querySelector('[data-setting=auto-update]').click();
  })()`);
  await waitFor("document.querySelector('[data-setting=auto-update]').checked");
  await screenshot("automatic-updates-enabled.png");
  // Starting the installed PyInstaller executable during replacement can lock it against Setup.
  // Observe Setup and its uninstall registration; execute the updated CLI only after Setup exits.
  const quoted = value => `'${value.replaceAll("'", "''")}'`;
  const watchSetup = `
    $ErrorActionPreference = 'Stop'
    $trace = ${quoted(path.join(output, "upgrade-processes.jsonl"))}
    $uninstall = 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{B63C9FCB-D1C6-49A0-9C08-463E53762BD0}_is1'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt 240) {
      $processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'WProxy*' -or $_.Name -like 'wproxyctl*' } |
        Select-Object Name,ProcessId,ParentProcessId,ExecutablePath,CommandLine)
      $registrations = @(foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
          $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
          $key = $base.OpenSubKey($uninstall)
          if ($key) {
            [PSCustomObject]@{Hive=$hive.ToString(); View=$view.ToString(); Version=$key.GetValue('DisplayVersion');
              Location=$key.GetValue('InstallLocation'); Uninstall=$key.GetValue('UninstallString')}
            $key.Close()
          }
          $base.Close()
        }
      })
      $locations = @(${quoted(installation)}, (Join-Path ${quoted(environment.LOCALAPPDATA)} 'Programs\\WProxy'),
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\\WProxy')) + @($registrations.Location)
      $files = @(foreach ($location in ($locations | Where-Object { $_ } | Sort-Object -Unique)) {
        Get-Item (Join-Path $location 'wproxyctl.exe') -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTimeUtc
      })
      [PSCustomObject]@{Elapsed=$timer.Elapsed.TotalSeconds; Processes=$processes; Registrations=$registrations; CandidateFiles=$files} |
        ConvertTo-Json -Depth 6 -Compress | Add-Content -Path $trace -Encoding UTF8
      $setups = @($processes | Where-Object { $_.Name -like 'WProxy-${targetVersion}-Setup*' })
      $updated = @($registrations | Where-Object { $_.Version -eq '${targetVersion}' })
      if ($updated.Count -gt 0 -and $setups.Count -eq 0) { exit 0 }
      Start-Sleep -Seconds 1
    }
    throw 'GUI-triggered Setup did not finish registering the target version; see upgrade-processes.jsonl'
  `;
  const waitSetup = await new Promise(resolve => {
    // Keep CDP request observations flowing while Setup closes and replaces the old app.
    const watcher = spawn("powershell.exe", ["-NoProfile", "-Command", watchSetup],
      { env: environment, windowsHide: true, stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    const timer = setTimeout(() => { stderr += "Setup watcher timed out"; watcher.kill(); }, 260000);
    watcher.stderr.on("data", chunk => { stderr += chunk.toString(); });
    watcher.on("error", error => { clearTimeout(timer); resolve({ status: null, stderr: error.message }); });
    watcher.on("close", status => { clearTimeout(timer); resolve({ status, stderr }); });
  });
  assert.equal(waitSetup.status, 0, waitSetup.stderr || waitSetup.error?.message || "Automatic Setup did not finish");
  installedVersion = ctl(["--version"]);
  assert.equal(installedVersion, `WProxy ${targetVersion}`, "The GUI-triggered Setup did not replace the original installed command engine");
  assert.equal(ipc.filter(event => event.method === "run_ctl").length, 1, "Expected exactly one real automatic download request");
  assert.equal(ipc.filter(event => event.method === "install_update").length, 1, "Expected the real native install_update bridge");
  const downloaded = path.join(environment.APPDATA, "WProxy", "updates", targetVersion, targetAsset);
  assert.equal(digest(await readFile(downloaded)), expectedTargetHash, "The GUI update cache differs from the published SHA256SUMS");
  stopApplication();
  await delay(1000);
  await launch();
  assert(await evaluate(`document.body.textContent.includes('WProxy ${targetVersion}')`), "The updated manager still renders the old version");
  assert.equal(await evaluate("document.querySelector('[data-setting=auto-update]').checked"), true);
  assert.equal(JSON.parse(ctl(["settings", "show", "--json"])).auto_update, true);
  assert.deepEqual(JSON.parse(ctl(["node", "list", "--json"])), nodes, "Upgrade lost the existing server configuration");
  await screenshot("after-update.png");
  await writeFile(path.join(output, "update-result.json"), JSON.stringify({
    passed: true, platform: "windows-2022", fromVersion, targetVersion, baselineSha256,
    downloadedUpdateSha256: expectedTargetHash, automaticUpdateCheckboxClicks: 1,
    realDownloadAndInstallBridge: true, installedCommandEngineUpdated: true,
    reopenedManagerUpdated: true, preferenceAndServersPreserved: true, ipc,
    limitations: ["Disposable administrator runner; standard-user UAC is not tested"],
  }, null, 2));
  console.log(`Real Windows automatic upgrade ${fromVersion} -> ${targetVersion}: PASS`);
} catch (error) {
  const failure = { error: String(error), installedVersion, ipc };
  if (socket?.readyState === WebSocket.OPEN) {
    try {
      failure.page = await evaluate("document.body.innerText");
      await screenshot("update-failure.png");
    } catch { /* Setup may already have closed the old application. */ }
  }
  await writeFile(path.join(output, "update-failure.json"), JSON.stringify(failure, null, 2));
  throw error;
} finally {
  stopApplication();
  for (const request of pending.values()) clearTimeout(request.timer);
}
