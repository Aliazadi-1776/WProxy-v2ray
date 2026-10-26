import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import "./styles.css";

type Page = "servers" | "subscriptions" | "add" | "routing" | "settings";
type Platform = "windows" | "linux";
type RoutingMode = "all" | "bypass" | "only";

interface CliOutput {
  stdout: string;
  stderr: string;
  code: number;
}

interface NodeRecord {
  id: string;
  name: string;
  source: string | null;
  source_name: string;
}

interface Subscription {
  id: string;
  name: string;
  remaining_human: string | null;
  updated_at: number | null;
  node_count: number;
}

interface TunnelStatus {
  active: boolean;
  verified?: boolean;
  name: string | null;
  node_id: string | null;
}

interface RoutingPolicy {
  version: number;
  mode: RoutingMode;
  domains: string[];
  apps: string[];
}

interface Preferences {
  auto_update: boolean;
}

interface PingResult {
  id: string;
  name: string;
  latency_ms: number | null;
}

interface UpdateStatus {
  current_version: string;
  latest_version: string;
  update_available: boolean;
}

const isTauri = "__TAURI_INTERNALS__" in window;
const applicationRoot = document.querySelector<HTMLDivElement>("#app");
if (!applicationRoot) throw new Error("WProxy application root is missing");
const app: HTMLDivElement = applicationRoot;
let automaticUpdateStarted = false;

const state = {
  page: "servers" as Page,
  platform: "linux" as Platform,
  nodes: [] as NodeRecord[],
  subscriptions: [] as Subscription[],
  status: { active: false, name: null, node_id: null } as TunnelStatus,
  routing: { version: 1, mode: "all", domains: [], apps: [] } as RoutingPolicy,
  preferences: { auto_update: false } as Preferences,
  pings: new Map<string, number | null>(),
  selectedNode: null as string | null,
  selectedDomain: null as string | null,
  selectedApp: null as string | null,
  selectedSubscription: null as string | null,
  busy: false,
  loading: true,
  error: "",
  updateLabel: "Ready",
};

const icons = {
  servers: '<path d="M4 5.5h16v5H4zM4 13.5h16v5H4z"/><path d="M7 8h.01M7 16h.01"/>',
  subscriptions: '<path d="M5 6h14M5 12h14M5 18h9"/>',
  add: '<path d="M12 5v14M5 12h14"/>',
  routing: '<circle cx="12" cy="12" r="8"/><path d="M4 12h16M12 4a12 12 0 0 1 0 16M12 4a12 12 0 0 0 0 16"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>',
  bolt: '<path d="m13 2-8 12h7l-1 8 8-12h-7z"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13"/>',
  gauge: '<path d="M5 19a9 9 0 1 1 14 0"/><path d="m12 13 4-4"/>',
  chevron: '<path d="m9 18 6-6-6-6"/>',
  shield: '<path d="M12 3 5 6v5c0 4.5 2.8 7.7 7 10 4.2-2.3 7-5.5 7-10V6z"/><path d="m9.5 12 1.7 1.7 3.8-4"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.1.1l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1"/><path d="M14 11a5 5 0 0 0-7.1-.1l-2 2A5 5 0 0 0 12 20l1.1-1.1"/>',
  app: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M8 4v5"/>',
  update: '<path d="M20 12a8 8 0 1 1-2.3-5.7L20 8"/><path d="M20 3v5h-5"/>',
  x: '<path d="m6 6 12 12M18 6 6 18"/>',
} as const;

function icon(name: keyof typeof icons, size = 18): string {
  return `<svg aria-hidden="true" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${icons[name]}</svg>`;
}

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;",
  })[character] ?? character);
}

function parseJson<T>(output: CliOutput): T {
  try {
    return JSON.parse(output.stdout) as T;
  } catch {
    throw new Error("WProxy returned data the app could not read.");
  }
}

async function ctl<T>(args: string[]): Promise<T> {
  const output = await invoke<CliOutput>("run_ctl", { args });
  return parseJson<T>(output);
}

function demoSnapshot(): void {
  state.platform = "windows";
  state.nodes = [
    { id: "19a2c0d1a7bb31f0", name: "🇩🇪 Berlin · Low latency", source: null, source_name: "Manual" },
    { id: "a4b8fd9ae231c201", name: "🇫🇮 Helsinki · Work", source: "sub-1", source_name: "Cloud subscription" },
    { id: "bd70f2051d103c62", name: "🇯🇵 Tokyo · Media", source: "sub-1", source_name: "Cloud subscription" },
  ];
  state.subscriptions = [
    { id: "sub-1", name: "Cloud subscription", remaining_human: "82.4 GiB", updated_at: Date.now() / 1000, node_count: 2 },
  ];
  state.routing = { version: 1, mode: "bypass", domains: ["internal.example.com"], apps: ["C:/Program Files/Firefox/firefox.exe"] };
  state.preferences = { auto_update: true };
  state.pings = new Map([["19a2c0d1a7bb31f0", 42], ["a4b8fd9ae231c201", 68], ["bd70f2051d103c62", 121]]);
}

async function loadSnapshot(silent = false): Promise<void> {
  if (!silent) state.loading = true;
  state.error = "";
  try {
    if (!isTauri) {
      demoSnapshot();
    } else {
      state.platform = await invoke<Platform>("platform");
      const [nodes, subscriptions, status, routing, preferences] = await Promise.all([
        ctl<NodeRecord[]>(["node", "list", "--json"]),
        ctl<Subscription[]>(["sub", "list", "--json"]),
        invoke<CliOutput>("tunnel_status").then(parseJson<TunnelStatus>),
        ctl<RoutingPolicy>(["routing", "show", "--json"]),
        ctl<Preferences>(["settings", "show", "--json"]),
      ]);
      state.nodes = nodes;
      state.subscriptions = subscriptions;
      state.status = status;
      state.routing = routing;
      state.preferences = preferences;
      if (state.selectedNode && !nodes.some((node) => node.id === state.selectedNode)) state.selectedNode = null;
    }
  } catch (error) {
    state.error = errorMessage(error);
  } finally {
    state.loading = false;
    render();
    if (isTauri && state.preferences.auto_update && !automaticUpdateStarted) {
      automaticUpdateStarted = true;
      window.setTimeout(() => void runAutomaticUpdate(), 800);
    }
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error || "Something went wrong.");
}

function navItem(page: Page, label: string, iconName: keyof typeof icons): string {
  const active = state.page === page;
  return `<button class="nav-item${active ? " is-active" : ""}" data-page="${page}" aria-current="${active ? "page" : "false"}">
    <span class="nav-icon">${icon(iconName, 17)}</span><span>${label}</span>
  </button>`;
}

function connectionPill(): string {
  const connected = state.status.active;
  return `<div class="connection-pill ${connected ? "is-online" : ""}">
    <span class="connection-pulse"></span>
    <span><strong>${connected ? "Connected" : "Disconnected"}</strong><small>${connected ? escapeHtml(state.status.name || "Private tunnel") : `${state.platform === "windows" ? "Windows TUN" : "NetworkManager"} ready`}</small></span>
  </div>`;
}

function renderShell(content: string): void {
  app.innerHTML = `<div class="app-shell">
    <aside class="sidebar">
      <div class="brand">
        <div class="brand-mark" aria-hidden="true">W</div>
        <div><strong>WProxy</strong><span>Private routing</span></div>
      </div>
      <nav class="navigation" aria-label="Main navigation">
        ${navItem("servers", "Servers", "servers")}
        ${navItem("subscriptions", "Subscriptions", "subscriptions")}
        ${navItem("add", "Add connection", "add")}
        ${navItem("routing", "Split routing", "routing")}
      </nav>
      <div class="sidebar-footer">
        <button class="nav-item${state.page === "settings" ? " is-active" : ""}" data-page="settings">
          <span class="nav-icon">${icon("settings", 17)}</span><span>Settings</span>
        </button>
        <div class="version-row"><span>WProxy 2.7.0</span><span>${state.platform === "windows" ? "Windows" : "Linux"}</span></div>
      </div>
    </aside>
    <section class="workspace">
      <header class="topbar">
        <div class="page-heading"><h1>${pageTitle()}</h1><p>${pageSubtitle()}</p></div>
        <div class="topbar-actions">
          <button class="icon-button" data-action="refresh" title="Refresh" aria-label="Refresh">${icon("refresh")}</button>
          ${connectionPill()}
        </div>
      </header>
      <main class="content" id="content">${content}</main>
      <div class="toast-region" aria-live="polite" aria-atomic="true"></div>
    </section>
  </div>`;
}

function pageTitle(): string {
  return ({ servers: "Servers", subscriptions: "Subscriptions", add: "Add connection", routing: "Split routing", settings: "Settings" })[state.page];
}

function pageSubtitle(): string {
  return ({
    servers: "Choose a server or let WProxy find the fastest route.",
    subscriptions: "Keep remote server lists current in one place.",
    add: "Paste a V2Ray-compatible link. It stays on this device.",
    routing: state.platform === "linux" ? "Keep Linux app and site routing under control." : "Route Windows applications and sites exactly where you want.",
    settings: "Updates, permissions, and platform details.",
  })[state.page];
}

function loadingView(): string {
  return `<div class="skeleton-stack" aria-label="Loading">
    <div class="skeleton skeleton-hero"></div>
    <div class="skeleton skeleton-row"></div>
    <div class="skeleton skeleton-row"></div>
    <div class="skeleton skeleton-row short"></div>
  </div>`;
}

function errorView(): string {
  return `<section class="empty-state error-state">
    <div class="empty-icon">${icon("x", 22)}</div>
    <h2>WProxy could not load</h2><p>${escapeHtml(state.error)}</p>
    <button class="button primary" data-action="refresh">Try again</button>
  </section>`;
}

function serverHero(): string {
  const connected = state.status.active;
  return `<section class="connection-hero ${connected ? "is-online" : ""}">
    <div class="hero-symbol">${icon(connected ? "shield" : "bolt", 25)}</div>
    <div class="hero-copy">
      <span class="eyebrow">${connected ? "SECURE TUNNEL" : "READY TO CONNECT"}</span>
      <h2>${connected ? escapeHtml(state.status.name || "Connected") : "Your connection is private when you need it"}</h2>
      <p>${connected ? "Traffic is moving through the selected WProxy server." : "Quick connect tests your servers and chooses the lowest latency."}</p>
    </div>
    <button class="button ${connected ? "danger-quiet" : "primary"} hero-action" data-action="${connected ? "disconnect" : "quick-connect"}" ${state.busy || (!connected && !state.nodes.length) ? "disabled" : ""}>
      ${connected ? "Disconnect" : `${icon("bolt", 16)} Quick connect`}
    </button>
  </section>`;
}

function latencyFor(node: NodeRecord): string {
  if (!state.pings.has(node.id)) return "Not tested";
  const latency = state.pings.get(node.id);
  return latency === null ? "Timed out" : `${latency} ms`;
}

function serverRow(node: NodeRecord, index: number): string {
  const active = state.status.active && state.status.node_id === node.id;
  const selected = state.selectedNode === node.id;
  const latency = state.pings.get(node.id);
  const quality = latency == null ? "unknown" : latency < 90 ? "good" : latency < 180 ? "medium" : "slow";
  const avatar = node.name.match(/[\p{L}\p{N}]/u)?.[0]?.toUpperCase() || String(index + 1);
  return `<article class="server-row${active ? " is-connected" : ""}${selected ? " is-selected" : ""}" data-select-node="${node.id}" tabindex="0">
    <div class="server-avatar">${escapeHtml(avatar)}</div>
    <div class="server-identity"><strong>${escapeHtml(node.name)}</strong><span>${escapeHtml(node.source_name || "Manual")}</span></div>
    <div class="latency ${quality}"><span class="latency-dot"></span>${latencyFor(node)}</div>
    <div class="row-actions">
      ${active ? '<span class="active-label">Active</span>' : `<button class="button small secondary" data-action="connect" data-node="${node.id}" ${state.busy ? "disabled" : ""}>Connect</button>`}
      <button class="icon-button subtle" data-action="remove-node" data-node="${node.id}" title="Remove server" aria-label="Remove ${escapeHtml(node.name)}">${icon("trash", 17)}</button>
    </div>
  </article>`;
}

function serversPage(): string {
  if (!state.nodes.length) {
    return `${serverHero()}<section class="empty-state">
      <div class="empty-icon">${icon("servers", 24)}</div><h2>No servers yet</h2>
      <p>Add a connection link or import a subscription to get started.</p>
      <div class="button-row"><button class="button primary" data-page="add">Add connection</button><button class="button secondary" data-page="subscriptions">Add subscription</button></div>
    </section>`;
  }
  return `${serverHero()}
    <section class="section-block">
      <div class="section-toolbar">
        <div><h2>Available servers</h2><p>${state.nodes.length} configured</p></div>
        <div class="button-row compact">
          <button class="button secondary" data-action="ping" ${state.busy ? "disabled" : ""}>${icon("gauge", 16)} Test latency</button>
          <button class="button primary" data-page="add">${icon("add", 16)} Add server</button>
        </div>
      </div>
      <div class="server-list">${state.nodes.map(serverRow).join("")}</div>
    </section>`;
}

function subscriptionsPage(): string {
  const rows = state.subscriptions.map((subscription) => `<article class="subscription-card${state.selectedSubscription === subscription.id ? " is-selected" : ""}" data-select-sub="${subscription.id}">
    <div class="subscription-icon">${icon("link", 20)}</div>
    <div class="subscription-copy"><strong>${escapeHtml(subscription.name)}</strong><span>${subscription.node_count} servers${subscription.remaining_human ? ` · ${escapeHtml(subscription.remaining_human)} left` : ""}</span></div>
    <div class="row-actions">
      <button class="button small secondary" data-action="update-sub" data-sub="${subscription.id}">Update</button>
      <button class="icon-button subtle" data-action="remove-sub" data-sub="${subscription.id}" aria-label="Remove subscription">${icon("trash", 17)}</button>
    </div>
  </article>`).join("");
  return `<section class="section-block constrained">
    <div class="section-toolbar"><div><h2>Your subscriptions</h2><p>Remote lists update without exposing their URLs in the interface.</p></div>
      ${state.subscriptions.length ? '<button class="button secondary" data-action="update-all">Update all</button>' : ""}
    </div>
    ${rows ? `<div class="card-list">${rows}</div>` : '<div class="empty-inline">No subscriptions added yet.</div>'}
    <form class="form-card" id="subscription-form">
      <div class="form-heading"><h3>Add a subscription</h3><p>Use the name shown by your provider, or choose your own.</p></div>
      <label><span>Name <em>optional</em></span><input name="name" autocomplete="off" placeholder="Work servers" /></label>
      <label><span>Subscription URL</span><input name="url" type="url" required autocomplete="off" placeholder="https://example.com/subscription" /></label>
      <div class="form-actions"><button class="button primary" type="submit">Add subscription</button></div>
    </form>
  </section>`;
}

function addPage(): string {
  return `<section class="add-layout">
    <form class="form-card prominent" id="node-form">
      <div class="form-heading"><span class="form-icon">${icon("link", 22)}</span><div><h2>Add a server</h2><p>Supports VLESS, VMess, Trojan and Shadowsocks links.</p></div></div>
      <label><span>Display name <em>optional</em></span><input name="name" autocomplete="off" placeholder="Berlin · Work" /></label>
      <label><span>Connection link</span><textarea name="uri" required spellcheck="false" rows="5" placeholder="vless://, vmess://, trojan:// or ss://"></textarea></label>
      <div class="privacy-note">${icon("shield", 17)} The link is stored locally and is never sent to WProxy.</div>
      <div class="form-actions"><button class="button secondary" type="reset">Clear</button><button class="button primary" type="submit">Save server</button></div>
    </form>
    <aside class="help-card"><span class="eyebrow">QUICK START</span><h3>Have a subscription instead?</h3><p>Importing a subscription keeps every server grouped and lets you refresh them together.</p><button class="text-button" data-page="subscriptions">Open subscriptions ${icon("chevron", 15)}</button></aside>
  </section>`;
}

function selectedClass(value: string, selected: string | null): string {
  return value === selected ? " is-selected" : "";
}

function routingPage(): string {
  const modes: Array<[RoutingMode, string, string]> = [
    ["all", "All traffic", "Use VPN for everything"],
    ["bypass", "Bypass selected", "Selected items stay direct"],
    ["only", "Only selected", "Everything else stays direct"],
  ];
  const domains = state.routing.domains.map((domain) => `<button class="route-item${selectedClass(domain, state.selectedDomain)}" data-select-domain="${escapeHtml(domain)}"><span>${icon("link", 16)} ${escapeHtml(domain)}</span>${icon("chevron", 15)}</button>`).join("");
  const apps = state.routing.apps.map((application) => `<button class="route-item${selectedClass(application, state.selectedApp)}" data-select-app="${escapeHtml(application)}"><span>${icon("app", 16)} <bdi>${escapeHtml(application)}</bdi></span>${icon("chevron", 15)}</button>`).join("");
  return `<section class="routing-layout">
    <div class="mode-grid" role="radiogroup" aria-label="Routing mode">
      ${modes.map(([mode, title, description]) => `<button class="mode-card${state.routing.mode === mode ? " is-active" : ""}" data-action="routing-mode" data-mode="${mode}" role="radio" aria-checked="${state.routing.mode === mode}"><span class="mode-radio"></span><strong>${title}</strong><small>${description}</small></button>`).join("")}
    </div>
    <div class="routing-columns">
      <section class="route-card">
        <div class="route-card-head"><div><h2>Sites</h2><p>Hostnames or URLs</p></div><span class="count-badge">${state.routing.domains.length}</span></div>
        <div class="route-list">${domains || '<div class="empty-list">No sites added</div>'}</div>
        <form class="inline-form" id="domain-form"><input name="domain" required autocomplete="off" placeholder="example.com" /><button class="button primary" type="submit">Add site</button><button class="icon-button subtle" type="button" data-action="remove-domain" aria-label="Remove selected site" ${state.selectedDomain ? "" : "disabled"}>${icon("trash", 17)}</button></form>
      </section>
      <section class="route-card">
        <div class="route-card-head"><div><h2>Applications</h2><p>Exact executable paths</p></div><span class="count-badge">${state.routing.apps.length}</span></div>
        <div class="route-list">${apps || '<div class="empty-list">No applications added</div>'}</div>
        <div class="inline-form"><button class="button primary grow" data-action="choose-app">${icon("app", 16)} Choose application</button><button class="icon-button subtle" data-action="remove-app" aria-label="Remove selected application" ${state.selectedApp ? "" : "disabled"}>${icon("trash", 17)}</button></div>
      </section>
    </div>
    <p class="routing-footnote">${state.platform === "linux" ? "Changes are synced with NetworkManager. Reconnect if the current tunnel was already active." : "Executable paths are matched by Xray on the next connection."}</p>
  </section>`;
}

function settingsPage(): string {
  return `<section class="settings-layout constrained">
    <div class="settings-card">
      <div class="setting-row"><div class="setting-icon">${icon("update", 20)}</div><div class="setting-copy"><strong>Automatic updates</strong><span>Check verified GitHub releases and install them automatically.</span></div><label class="switch"><input type="checkbox" data-setting="auto-update" ${state.preferences.auto_update ? "checked" : ""}/><span></span></label></div>
      <div class="setting-row"><div class="setting-icon">${icon("refresh", 20)}</div><div class="setting-copy"><strong>Check for updates</strong><span>Installed version: 2.7.0</span></div><button class="button secondary" data-action="check-update">Check now</button></div>
      ${state.platform === "linux" ? `<div class="setting-row"><div class="setting-icon">${icon("shield", 20)}</div><div class="setting-copy"><strong>Remember administrator approval</strong><span>Authorize only WProxy connect, disconnect, sync and verified update actions.</span></div><button class="button secondary" data-action="linux-authorize">Authorize</button></div>` : ""}
    </div>
    <div class="about-card"><div class="brand-mark large">W</div><div><h2>WProxy 2.7.0</h2><p>${state.platform === "windows" ? "Tauri desktop · Windows TUN" : "Tauri desktop · NetworkManager"}</p></div><span class="status-chip">${escapeHtml(state.updateLabel)}</span></div>
  </section>`;
}

function render(): void {
  if (state.loading) return renderShell(loadingView());
  if (state.error) return renderShell(errorView());
  const content = ({ servers: serversPage, subscriptions: subscriptionsPage, add: addPage, routing: routingPage, settings: settingsPage })[state.page]();
  renderShell(content);
}

function toast(message: string, kind: "success" | "error" = "success"): void {
  const region = document.querySelector<HTMLDivElement>(".toast-region");
  if (!region) return;
  const element = document.createElement("div");
  element.className = `toast ${kind}`;
  element.innerHTML = `<span>${kind === "success" ? icon("shield", 17) : icon("x", 17)}</span><p>${escapeHtml(message)}</p>`;
  region.append(element);
  requestAnimationFrame(() => element.classList.add("show"));
  window.setTimeout(() => {
    element.classList.remove("show");
    window.setTimeout(() => element.remove(), 180);
  }, 3400);
}

async function action(label: string, callback: () => Promise<void>): Promise<void> {
  if (state.busy) return;
  state.busy = true;
  render();
  let failure = "";
  try {
    await callback();
  } catch (error) {
    failure = errorMessage(error);
  } finally {
    state.busy = false;
    await loadSnapshot(true);
  }
  toast(failure || label, failure ? "error" : "success");
}

async function connect(nodeId: string): Promise<void> {
  if (!isTauri) {
    const node = state.nodes.find((item) => item.id === nodeId);
    state.status = { active: true, verified: true, name: node?.name ?? "Demo server", node_id: nodeId };
    return;
  }
  await invoke<CliOutput>("tunnel", { action: "up", nodeId });
}

async function quickConnect(): Promise<void> {
  if (!isTauri) return connect(state.nodes[0]?.id ?? "");
  const best = await ctl<PingResult>(["node", "best", "--json", "--timeout", "2"]);
  state.pings.set(best.id, best.latency_ms);
  await connect(best.id);
}

async function disconnect(): Promise<void> {
  if (!isTauri) {
    state.status = { active: false, name: null, node_id: null };
    return;
  }
  await invoke<CliOutput>("tunnel", { action: "down", nodeId: null });
}

async function pingAll(): Promise<void> {
  if (!isTauri) return;
  const rows = await ctl<PingResult[]>(["node", "ping", "--all", "--json", "--timeout", "2"]);
  state.pings = new Map(rows.map((row) => [row.id, row.latency_ms]));
}

async function routeChanged(): Promise<void> {
  if (isTauri && state.platform === "linux" && state.status.active) await invoke<CliOutput>("sync_linux");
}

app.addEventListener("click", async (event) => {
  const target = (event.target as HTMLElement).closest<HTMLElement>("button, [data-select-node], [data-select-domain], [data-select-app], [data-select-sub]");
  if (!target) return;
  const page = target.dataset.page as Page | undefined;
  if (page) {
    state.page = page;
    render();
    return;
  }
  if (target.dataset.selectNode) { state.selectedNode = target.dataset.selectNode; render(); return; }
  if (target.dataset.selectDomain) { state.selectedDomain = target.dataset.selectDomain; render(); return; }
  if (target.dataset.selectApp) { state.selectedApp = target.dataset.selectApp; render(); return; }
  if (target.dataset.selectSub) { state.selectedSubscription = target.dataset.selectSub; render(); return; }

  const command = target.dataset.action;
  if (!command) return;
  if (command === "refresh") return void loadSnapshot();
  if (command === "connect" && target.dataset.node) return void action("Connected", () => connect(target.dataset.node!));
  if (command === "quick-connect") return void action("Connected to the fastest server", quickConnect);
  if (command === "disconnect") return void action("Disconnected", disconnect);
  if (command === "ping") return void action("Latency test complete", pingAll);
  if (command === "remove-node" && target.dataset.node) return void action("Server removed", async () => {
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["node", "remove", target.dataset.node!] });
    else state.nodes = state.nodes.filter((node) => node.id !== target.dataset.node);
  });
  if (command === "update-sub" && target.dataset.sub) return void action("Subscription updated", async () => {
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["sub", "update", target.dataset.sub!] });
  });
  if (command === "update-all") return void action("Subscriptions updated", async () => {
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["sub", "update"] });
  });
  if (command === "remove-sub" && target.dataset.sub) return void action("Subscription removed", async () => {
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["sub", "remove", target.dataset.sub!] });
    else state.subscriptions = state.subscriptions.filter((item) => item.id !== target.dataset.sub);
  });
  if (command === "routing-mode" && target.dataset.mode) return void action("Routing mode changed", async () => {
    const mode = target.dataset.mode as RoutingMode;
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["routing", "mode", mode] });
    else state.routing.mode = mode;
    await routeChanged();
  });
  if (command === "remove-domain" && state.selectedDomain) return void action("Site removed", async () => {
    const value = state.selectedDomain!;
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["routing", "domain", "remove", value] });
    else state.routing.domains = state.routing.domains.filter((item) => item !== value);
    state.selectedDomain = null;
    await routeChanged();
  });
  if (command === "choose-app") return void chooseApplication();
  if (command === "remove-app" && state.selectedApp) return void action("Application removed", async () => {
    const value = state.selectedApp!;
    if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["routing", "app", "remove", value] });
    else state.routing.apps = state.routing.apps.filter((item) => item !== value);
    state.selectedApp = null;
    await routeChanged();
  });
  if (command === "check-update") return void checkUpdate();
  if (command === "linux-authorize") return void action("Administrator approval remembered", async () => {
    if (isTauri) await invoke<CliOutput>("set_linux_authorization", { enable: true });
  });
});

async function chooseApplication(): Promise<void> {
  try {
    const path = isTauri
      ? await open({ multiple: false, directory: false, title: "Choose an application" })
      : state.platform === "windows" ? "C:/Program Files/Spotify/Spotify.exe" : "/usr/bin/firefox";
    if (typeof path !== "string") return;
    await action("Application added", async () => {
      if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["routing", "app", "add", path] });
      else if (!state.routing.apps.includes(path)) state.routing.apps.push(path);
      await routeChanged();
    });
  } catch (error) {
    toast(errorMessage(error), "error");
  }
}

async function checkUpdate(): Promise<void> {
  await action("Update check complete", async () => {
    if (!isTauri) return;
    const update = await ctl<UpdateStatus>(["update", "check", "--json", "--timeout", "15"]);
    if (!update.update_available) {
      state.updateLabel = "Up to date";
      return;
    }
    state.updateLabel = `v${update.latest_version} available`;
    const proceed = window.confirm(`WProxy ${update.latest_version} is available. Download and install it now?`);
    if (!proceed) return;
    const result = await ctl<{ path?: string; update_available: boolean }>(["update", "download", "--json", "--platform", state.platform, "--timeout", "30"]);
    if (result.path) {
      state.updateLabel = "Installing update";
      await invoke<CliOutput>("install_update", { path: result.path });
    }
  });
}

async function runAutomaticUpdate(): Promise<void> {
  try {
    const result = await ctl<{ path?: string; latest_version: string; update_available: boolean }>([
      "update", "download", "--json", "--platform", state.platform, "--timeout", "30",
    ]);
    if (!result.update_available || !result.path) {
      state.updateLabel = "Up to date";
      if (state.page === "settings") render();
      return;
    }
    state.updateLabel = `Installing v${result.latest_version}`;
    if (state.page === "settings") render();
    await invoke<CliOutput>("install_update", { path: result.path });
    toast(`WProxy ${result.latest_version} update started`);
  } catch (error) {
    state.updateLabel = "Update check failed";
    if (state.page === "settings") render();
    console.warn("Automatic update failed", error);
  }
}

app.addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.target as HTMLFormElement;
  const data = new FormData(form);
  if (form.id === "node-form") {
    const uri = String(data.get("uri") || "").trim();
    const name = String(data.get("name") || "").trim();
    if (!uri) return;
    await action("Server saved", async () => {
      if (isTauri) {
        const args = ["node", "add", uri];
        if (name) args.push("--name", name);
        await invoke<CliOutput>("run_ctl", { args });
      } else {
        state.nodes.push({ id: crypto.randomUUID().replaceAll("-", "").slice(0, 16), name: name || "New server", source: null, source_name: "Manual" });
      }
      state.page = "servers";
    });
  }
  if (form.id === "subscription-form") {
    const url = String(data.get("url") || "").trim();
    const name = String(data.get("name") || "").trim();
    if (!url) return;
    await action("Subscription added", async () => {
      if (isTauri) {
        const args = ["sub", "add", url];
        if (name) args.push("--name", name);
        await invoke<CliOutput>("run_ctl", { args });
        await invoke<CliOutput>("run_ctl", { args: ["sub", "update"] });
      }
    });
  }
  if (form.id === "domain-form") {
    const domain = String(data.get("domain") || "").trim();
    if (!domain) return;
    await action("Site added", async () => {
      if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["routing", "domain", "add", domain] });
      else if (!state.routing.domains.includes(domain)) state.routing.domains.push(domain);
      await routeChanged();
    });
  }
});

app.addEventListener("change", async (event) => {
  const input = event.target as HTMLInputElement;
  if (input.dataset.setting === "auto-update") {
    const enabled = input.checked;
    await action(enabled ? "Automatic updates enabled" : "Automatic updates disabled", async () => {
      if (isTauri) await invoke<CliOutput>("run_ctl", { args: ["settings", "set", "auto_update", String(enabled)] });
      else state.preferences.auto_update = enabled;
    });
  }
});

void loadSnapshot();
