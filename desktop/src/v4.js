import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { createDesktopClient } from './v4-client';
import { TelemetryHistory } from './telemetry';
import { subscriptionHealth } from './subscription-health';
const IS_NATIVE = '__TAURI_INTERNALS__' in window;
const client = createDesktopClient(invoke, IS_NATIVE);
const history = new TelemetryHistory();
function readLocal(key, fallback='') { try { return localStorage.getItem(key) || fallback; } catch { return fallback; } }
function writeLocal(key, value) { try { localStorage.setItem(key, value); } catch { toast('Preference kept for this session only', 'i-info'); } }
function favoriteIds() { try { const x=JSON.parse(readLocal('wproxy.v4.favorites','[]')); return new Set(Array.isArray(x)?x.filter(x=>typeof x==='string'):[]); } catch { return new Set(); } }
const favorites = favoriteIds();

"use strict";
/* ============================================================
   WProxy v4 — local desktop interface
   Native actions use the existing bridge; browser actions cannot connect.
   ============================================================ */

const S = {
  page: "dashboard",
  conn: "off",              // off | busy | on
  node: "n2",               // selected node id
  activeNode: null,
  step: -1,
  uptime: 0,
  rx: 0, tx: 0,
  dn: 0, up: 0,
  samples: [],
  view: readLocal("wp.view") || "rows",
  tab: "all",
  q: "", source: "all", engine: "all", sort: "latency", hideDead: false,
  motion: readLocal("wproxy.v4.motion", "on"),
  anims: readLocal("wproxy.v4.animations", "on") !== "off",
  autoUpdate: false,
  rememberAuth: false,
  theme: readLocal("wp.theme") || "dark",
  routing: "all",
  testing: false,
  peak: 0,
  events: [],
  diagnostic: "No connection check has been run in this session.",
  busy: false, verified: false, memory: null, platform: "linux", snapshot: null, updateLabel: "Not checked", error: "",
};

const NODES = [
  { id:"n1", fl:"🇳🇱", name:"Amsterdam · Everyday",  city:"Amsterdam", src:"Cloud subscription", engine:"xray",   proto:"vless",     lat:41,   load:.38, fav:true  },
  { id:"n2", fl:"🇩🇪", name:"Berlin · Low latency",  city:"Berlin",    src:"Cloud subscription", engine:"xray",   proto:"vless",     lat:24,   load:.21, fav:true  },
  { id:"n3", fl:"🇫🇮", name:"Helsinki · Work",       city:"Helsinki",  src:"Personal routes",    engine:"mihomo", proto:"trojan",    lat:57,   load:.52, fav:false },
  { id:"n4", fl:"🇫🇷", name:"Paris · Backup",        city:"Paris",     src:"Cloud subscription", engine:"mihomo", proto:"vmess",     lat:68,   load:.74, fav:false },
  { id:"n5", fl:"🇬🇧", name:"London · Streaming",    city:"London",    src:"Cloud subscription", engine:"xray",   proto:"vless",     lat:49,   load:.61, fav:false },
  { id:"n6", fl:"🇯🇵", name:"Tokyo · Media",         city:"Tokyo",     src:"Personal routes",    engine:"xray",   proto:"shadowsocks", lat:186, load:.44, fav:true  },
  { id:"n7", fl:"🇸🇬", name:"Singapore · Travel",    city:"Singapore", src:"Cloud subscription", engine:"mihomo", proto:"trojan",    lat:214,  load:.33, fav:false },
  { id:"n8", fl:"🇺🇸", name:"Ashburn · Gaming",      city:"Ashburn",   src:"Manual",             engine:"xray",   proto:"vless",     lat:112,  load:.29, fav:false },
  { id:"n9", fl:"🇨🇭", name:"Zürich · Private",      city:"Zürich",    src:"Manual",             engine:"mihomo", proto:"vless",     lat:null, load:.0,  fav:false },
];

const SUBS = [
  { id:"s1", name:"Cloud subscription", count:24, used:412*1e9, total:1024*1e9, expires:"14 Feb 2026", updated:"12 min ago" },
  { id:"s2", name:"Personal routes",    count:6,  used:38*1e9,  total:null,     expires:"No expiry",   updated:"3 h ago"    },
];

const ENGINES = [
  { name:"xray",      version:"1.8.23", ok:true  },
  { name:"mihomo",    version:"1.18.4", ok:true  },
  { name:"sing-box",  version:null,     ok:false },
];

const ROUTING = { domains: [], apps: [] };
const STEPS = ["Checking HTTPS", "Starting tunnel"];
const MODES = {
  all: { label:"All traffic", desc:"Send traffic through the tunnel.", icon:"i-globe" },
  only: { label:"Only selected", desc:"Tunnel only the apps and sites listed below.", icon:"i-split" },
  bypass: { label:"Bypass selected", desc:"Keep listed apps and sites direct; tunnel the rest.", icon:"i-route" },
};
S.routing = "all";
if (IS_NATIVE) { NODES.length=0; SUBS.length=0; ENGINES.length=0; S.node=null; }
else { NODES.forEach(n=>{n.lat=null;n.load=null;}); S.node=NODES[0]?.id; }
/* ------------------------------------------------------------ helpers */
const $  = (s, r=document) => r.querySelector(s);
const $$ = (s, r=document) => Array.from(r.querySelectorAll(s));
const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const clamp = (v,a,b) => Math.min(b, Math.max(a, v));
const node = id => NODES.find(n => n.id === id) || null;

function ic(name, size=16){
  // accepts "shield" or "i-shield" — normalise so both forms resolve
  const n = String(name).replace(/^i-/, "");
  return `<svg viewBox="0 0 24 24" style="width:${size}px;height:${size}px" aria-hidden="true"><use href="#i-${n}"/></svg>`;
}
function bytes(n){
  if(n == null) return "Not reported";
  if (!Number.isFinite(n) || n <= 0) return "0 B";
  const u = ["B","KB","MB","GB","TB"];
  const i = Math.min(u.length-1, Math.floor(Math.log(n)/Math.log(1024)));
  const v = n / Math.pow(1024, i);
  return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${u[i]}`;
}
function rate(n){
  const [v,u] = (() => {
    if (!Number.isFinite(n) || n <= 0) return ["0","B/s"];
    const un = ["B/s","KB/s","MB/s","GB/s"];
    const i = Math.min(un.length-1, Math.floor(Math.log(n)/Math.log(1024)));
    const x = n / Math.pow(1024, i);
    return [x >= 100 || i === 0 ? String(Math.round(x)) : x.toFixed(1), un[i]];
  })();
  return { v, u };
}
function dur(sec){
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s/3600), m = Math.floor(s%3600/60), x = s%60;
  return h ? `${h}:${String(m).padStart(2,"0")}:${String(x).padStart(2,"0")}` : `${m}:${String(x).padStart(2,"0")}`;
}
function latClass(ms){
  if (ms == null) return "n";
  if (ms < 60) return "g";
  if (ms < 150) return "y";
  return "r";
}
function latText(ms){ return ms == null ? "—" : `${ms} ms`; }
function engName(e){ return e === "xray" ? "Xray" : e === "mihomo" ? "Mihomo" : e === "sing-box" ? "sing-box" : e; }
function loadClass(l){ return l > .75 ? "max" : l > .5 ? "hi" : ""; }

function favs(){ return NODES.filter(n => n.fav); }
function bestNode(){
  const m = NODES.filter(n => n.lat != null).sort((a,b) => a.lat - b.lat);
  return m[0] || NODES[0] || null;
}
function routedCount(){ return ROUTING.apps.length + ROUTING.domains.length; }

/* toast */
let toastT = 0;
function toast(msg, iconName="i-check"){
  const el = document.createElement("div");
  el.className = "toast";
  el.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><use href="#${iconName}"/></svg><span>${esc(msg)}</span>`;
  $("#toasts").appendChild(el);
  const id = ++toastT;
  setTimeout(() => {
    el.classList.add("out");
    setTimeout(() => el.remove(), 320);
  }, 2600 + (id % 3) * 120);
}

/* timeline events */
function pushEvent(icon, text, ok=false){
  S.events.unshift({ icon, text, at: Date.now(), ok });
  if (S.events.length > 24) S.events.pop();
}

/* counting number animation */
function countTo(el, from, to, ms=520){
  if (!S.anims || document.body.dataset.motion === "off"){ el.textContent = to; return; }
  const t0 = performance.now();
  const a = parseFloat(from) || 0, b = parseFloat(to) || 0;
  const dec = String(to).includes(".") ? 1 : 0;
  (function tick(t){
    const p = clamp((t - t0) / ms, 0, 1);
    const e = 1 - Math.pow(1 - p, 3);
    el.textContent = (a + (b - a) * e).toFixed(dec);
    if (p < 1) requestAnimationFrame(tick);
    else el.textContent = to;
  })(t0);
}

/* smooth svg path through points */
function smooth(pts){
  if (pts.length < 2) return "";
  let d = `M${pts[0].x.toFixed(1)},${pts[0].y.toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++){
    const p0 = pts[i-1] || pts[i], p1 = pts[i], p2 = pts[i+1], p3 = pts[i+2] || p2;
    const c1x = p1.x + (p2.x - p0.x)/6, c1y = p1.y + (p2.y - p0.y)/6;
    const c2x = p2.x - (p3.x - p1.x)/6, c2y = p2.y - (p3.y - p1.y)/6;
    d += `C${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2.x.toFixed(1)},${p2.y.toFixed(1)}`;
  }
  return d;
}

/* ============================================================
   DASHBOARD
   ============================================================ */
function dialSVG(){
  let ticks = "";
  for (let i = 0; i < 72; i++){
    const a = (i / 72) * Math.PI * 2;
    const long = i % 6 === 0;
    const r1 = long ? 104 : 108, r2 = 114;
    ticks += `<line x1="${(129 + Math.cos(a)*r1).toFixed(1)}" y1="${(129 + Math.sin(a)*r1).toFixed(1)}" x2="${(129 + Math.cos(a)*r2).toFixed(1)}" y2="${(129 + Math.sin(a)*r2).toFixed(1)}" ${long ? 'stroke-width="2"' : ""}/>`;
  }
  return `<svg class="rings" viewBox="0 0 258 258" aria-hidden="true">
    <g class="ticks">${ticks}</g>
    <circle class="halo" cx="129" cy="129" r="120"/>
    <circle class="track" cx="129" cy="129" r="96"/>
    <circle class="prog" id="dialProg" cx="129" cy="129" r="96"/>
  </svg>`;
}

function heroHTML(){
  const n = node(S.node);
  const on = S.conn === "on";
  const busy = Boolean(S.pendingConnection);
  const act = S.activeNode ? node(S.activeNode) : null;
  const shown = on && act ? act : n;

  const eyebrow = on ? (S.verified ? "HTTPS verified" : "Tunnel active") : busy ? "Establishing route" : "Ready to connect";
  const head = on
    ? (act ? act.name : "Connected")
    : busy ? "Hold on a moment"
    : "Your traffic, your route.";

  const coreLbl = busy ? "Working" : on ? "Disconnect" : "Connect";
  const coreSub = on ? `<span class="mono" id="upt">${dur(S.uptime)}</span>`
    : busy ? `<span class="mono">${esc(S.progress || "Please wait…")}</span>`
    : `<span class="mono">Tap the dial</span>`;

  const steps = STEPS.map((_, i) =>
    `<i class="${busy ? (i < S.step ? "done" : i === S.step ? "on" : "") : on ? "done" : ""}"></i>`).join("");

  return `
  <section class="hero">
    <div class="hero-top">
      <div>
        <div class="eyebrow">${ic(on ? "i-shield" : busy ? "i-bolt" : "i-lock", 13)}<span>${eyebrow}</span></div>
        <h2>${esc(head)}</h2>
      </div>
      <span class="mode pill ${on ? "ok" : ""}">${MODES[S.routing].label}</span>
    </div>

    <div class="dial-wrap">
      <button class="dial" id="dial" aria-label="${busy ? "Connection in progress" : on ? "Disconnect" : "Quick connect"}">
        ${dialSVG()}
        <span class="core">
          <span class="core-in">
            <span class="core-ic">${ic(busy ? "i-refresh" : on ? "i-shield" : "i-power", 34)}</span>
            <span class="core-lbl">${coreLbl}</span>
            <span class="core-sub">${coreSub}</span>
          </span>
        </span>
      </button>
    </div>

    <div class="steps ${on || busy ? "" : "hide"}">${steps}</div>

    <div class="path">
      <p class="path-cap">${on
        ? `${S.verified ? "HTTPS check passed" : "HTTPS verification unavailable"} · ${esc(engName(shown ? shown.engine : ""))}`
        : busy ? esc(S.progress || "Waiting for WProxy…")
        : "WProxy validates a route with a real HTTPS request before switching your tunnel."}</p>
    </div>

    ${shown ? `
    <button class="pick" data-open="${shown.id}">
      <span class="fl">${shown.fl}</span>
      <span class="tx">
        <span class="k">${ic(on ? "i-shield" : "i-pin", 10)} ${on ? "Current server" : "Selected server"}</span>
        <span class="v">${esc(shown.name)}</span>
        <span class="m">
          <span>${esc(shown.src)}</span><i style="width:3px;height:3px;border-radius:50%;background:var(--ink-4);display:inline-block"></i>
          <span>${esc(engName(shown.engine))}</span><i style="width:3px;height:3px;border-radius:50%;background:var(--ink-4);display:inline-block"></i>
          <span class="lat ${latClass(shown.lat)}">${latText(shown.lat)}</span>
        </span>
      </span>
      <span class="ch">${ic("i-chev", 16)}</span>
    </button>` : `
    <button class="pick" data-go="servers">
      <span class="fl">＋</span>
      <span class="tx"><span class="k">No server</span><span class="v">Add your first server</span></span>
      <span class="ch">${ic("i-chev", 16)}</span>
    </button>`}

    <div class="hero-act">
      <button class="btn ${on ? "" : "pri"}" id="dial2">${ic(on ? "i-power" : "i-bolt", 16)}${on ? "Disconnect" : busy ? "Connecting…" : "Quick connect"}</button>
    </div>
  </section>`;
}

function chartHTML(){
  const pts = S.samples.slice(-56);
  if (pts.length < 2){
    return `<div class="chart"><div class="chart-empty">${ic("i-gauge", 22)}
      <p>Connect to a server to watch live throughput. The graph starts after two measurements.</p></div></div>`;
  }
  const W = 560, H = 120, P = 10;
  const max = Math.max(1, ...pts.flatMap(p => [p.dn, p.up]));
  const map = key => pts.map((p, i) => ({
    x: P + (i / (pts.length - 1)) * (W - P*2),
    y: H - P - (p[key] / max) * (H - P*2),
  }));
  const dnP = map("dn"), upP = map("up");
  const area = p => `${smooth(p)} L${(W-P).toFixed(1)},${H-P} L${P},${H-P} Z`;
  const last = dnP[dnP.length-1];

  return `<div class="chart">
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img"
         aria-label="Live download and upload throughput over the last ${pts.length} samples">
      <defs>
        <linearGradient id="gdn" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="var(--signal)" stop-opacity=".22"/>
          <stop offset="1" stop-color="var(--signal)" stop-opacity="0"/>
        </linearGradient>
        <linearGradient id="gup" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="var(--teal)" stop-opacity=".16"/>
          <stop offset="1" stop-color="var(--teal)" stop-opacity="0"/>
        </linearGradient>
      </defs>
      <path class="grid" d="M10,30 H550 M10,60 H550 M10,90 H550" vector-effect="non-scaling-stroke"/>
      <path class="ar-up" d="${area(upP)}"/>
      <path class="ar-dn" d="${area(dnP)}"/>
      <path class="ln-up" d="${smooth(upP)}" vector-effect="non-scaling-stroke"/>
      <path class="ln-dn" d="${smooth(dnP)}" vector-effect="non-scaling-stroke"/>
      <circle cx="${last.x.toFixed(1)}" cy="${last.y.toFixed(1)}" r="3.2" fill="var(--signal)"/>
    </svg>
    <div class="chart-legend">
      <b>Download</b><b class="up">Upload</b>
      <span class="rt">${pts.length} samples · peak ${rate(max).v} ${rate(max).u}</span>
    </div>
  </div>`;
}

function trafficHTML(){
  const on = S.conn === "on";
  const d = rate(S.dn), u = rate(S.up);
  const bars = key => {
    const s = S.samples.slice(-10);
    const max = Math.max(1, ...S.samples.slice(-24).map(p => p[key]));
    return (s.length ? s : Array(10).fill({dn:0,up:0}))
      .map(p => `<i style="height:${clamp((p[key]/max)*26, 2, 26).toFixed(1)}px"></i>`).join("");
  };
  return `
  <section class="card glow">
    <div class="card-h">
      <span class="ic">${ic("i-gauge", 16)}</span>
      <div><h3>Session traffic</h3><p>Measured from the active tunnel</p></div>
      <div class="r"><span class="pill ${on ? "ok" : ""}">${on ? "Live" : "Waiting"}</span></div>
    </div>
    <div class="card-b">
      <div class="rates">
        <div class="rate dn">
          <span class="hd">${ic("i-down", 12)}Download</span>
          <div class="val"><span id="dnVal">${d.v}</span><span class="unit">${d.u}</span></div>
          <div class="tot">${bytes(S.rx)} received</div>
          <div class="bars">${bars("dn")}</div>
        </div>
        <div class="rate up">
          <span class="hd">${ic("i-up", 12)}Upload</span>
          <div class="val"><span id="upVal">${u.v}</span><span class="unit">${u.u}</span></div>
          <div class="tot">${bytes(S.tx)} sent</div>
          <div class="bars">${bars("up")}</div>
        </div>
      </div>
      ${chartHTML()}
    </div>
  </section>`;
}

function statsHTML(){
  const on = S.conn === "on";
  const act = S.activeNode ? node(S.activeNode) : null;
  return `<div class="tiles" style="margin-top:14px">
    <div class="tile">
      <span class="k">${ic("i-clock", 12)}Uptime</span>
      <div class="v" id="tUptime">${on ? dur(S.uptime) : "—"}</div>
      <div class="d">${on ? "since this session began" : "no tunnel active"}</div>
    </div>
    <div class="tile">
      <span class="k">${ic("i-database", 12)}Session data</span>
      <div class="v" id="tData">${bytes(S.rx + S.tx)}</div>
      <div class="d" id="tDataSub">${bytes(S.rx)} in · ${bytes(S.tx)} out</div>
    </div>
    <div class="tile">
      <span class="k">${ic("i-trend", 12)}Peak speed</span>
      <div class="v" id="tPeak">${(() => { const r = rate(S.peak); return `${r.v}<span style="font-size:12px;color:var(--ink-4)"> ${r.u}</span>`; })()}</div>
      <div class="d" id="tPeakSub">${S.samples.length} samples recorded</div>
    </div>
    <div class="tile">
      <span class="k">${ic("i-activity", 12)}Core memory</span>
      <div class="v">${bytes(S.memory)}</div>
      <div class="d">${act ? esc(engName(act.engine)) : "no core active"}</div>
    </div>
  </div>`;
}

/* ---- identity / exposure ---- */
function identityHTML(){
  const current = node(S.activeNode);
  const rows = [
    ['i-shield','Connection',S.conn==='on'?(S.verified?'HTTPS verified':'Tunnel active'):'Disconnected'],
    ['i-cpu','Engine',current?engName(current.engine):'—'],
    ['i-key','Protocol',current?current.proto.toUpperCase():'—'],
    ['i-clock','Session',S.conn==='on'?dur(S.uptime):'—'],
    ['i-app','Core memory',bytes(S.memory)],
  ];
  return `<section class="card ident"><div class="card-h"><span class="ic">${ic('i-shield')}</span><div><h3>Connection details</h3><p>${IS_NATIVE?'Reported by your installed core':'Design preview · synthetic library'}</p></div></div><div class="card-b">${rows.map(([icon,k,v])=>`<div class="irow"><span class="ii">${ic(icon,14)}</span><span class="it"><span class="k">${k}</span><span class="v" data-session-field="${k}">${esc(v)}</span></span></div>`).join('')}</div></section>`;
}
function protectHTML(){
  return `<section class="card"><div class="card-h"><span class="ic">${ic('i-route')}</span><div><h3>Traffic policy</h3><p>${MODES[S.routing].label}</p></div></div><div class="card-b"><p class="policy-description">${esc(MODES[S.routing].desc)}</p><div class="policy-counts"><span>${ROUTING.apps.length} applications</span><span>${ROUTING.domains.length} sites</span></div><button class="btn sm ghost" data-go="routing">${ic('i-route',14)}Manage routing</button></div></section>`;
}

/* ---- favorites ---- */
function favCardHTML(){
  const f = favs();
  return `
  <section class="card glow">
    <div class="card-h">
      <span class="ic">${ic("i-star", 16)}</span>
      <div><h3>Favorites</h3><p>Pinned for one-tap access</p></div>
      <div class="r"><button class="btn sm ghost" data-go="servers">${ic("i-globe", 13)}All servers</button></div>
    </div>
    <div class="card-b">
      ${f.length ? `<div class="rows">${f.map((n, i) => `
        <div class="row ${S.activeNode === n.id ? "active" : ""}" style="animation-delay:${i*45}ms">
          <span class="fl">${n.fl}</span>
          <span class="nm">
            <b>${esc(n.name)}</b>
            <span class="meta">
              <span>${ic("i-cpu", 11)}${esc(engName(n.engine))}</span><i></i>
              <span>${ic("i-key", 11)}${esc(n.proto.toUpperCase())}</span>
            </span>
          </span>
          <span class="lat-col">
            <span class="mono lat ${latClass(n.lat)}">${latText(n.lat)}</span>
            <span class="cap">${ic("i-gauge", 10)}latency</span>
          </span>
          <span class="acts">
            <button class="btn sm ${S.activeNode === n.id ? "" : "pri"} hov" data-connect="${n.id}">
              ${ic(S.activeNode === n.id ? "i-shield" : "i-bolt", 13)}${S.activeNode === n.id ? "Active" : "Connect"}</button>
            <button class="icbtn" style="width:30px;height:30px" data-open="${n.id}" aria-label="Details">${ic("i-chev", 14)}</button>
          </span>
        </div>`).join("")}</div>`
      : `<div class="empty" style="padding:30px 18px">
          <span class="eic">${ic("i-star", 23)}</span>
          <b>No favorites yet</b>
          <p>Star a server and it shows up here for one-tap access.</p>
          <div class="ea"><button class="btn sm" data-go="servers">${ic("i-globe", 13)}Browse servers</button></div>
        </div>`}
    </div>
  </section>`;
}

/* ---- latency leaderboard ---- */
function leaderHTML(){
  const on = S.conn === "on";
  const list = NODES.filter(n => n.lat != null).sort((a,b) => a.lat - b.lat).slice(0, 5);
  const max = Math.max(1, ...list.map(n => n.lat));
  return `
  <section class="card glow">
    <div class="card-h">
      <span class="ic">${ic("i-bolt", 16)}</span>
      <div><h3>Fastest routes</h3><p>Ranked by measured round trip</p></div>
      <div class="r"><button class="btn sm ghost" id="testAll">${ic("i-gauge", 13)}Test all</button></div>
    </div>
    <div class="card-b" style="padding:10px 6px">
      ${list.length ? `<div class="lead">${list.map((n, i) => `
        <button class="lrow ${S.activeNode === n.id ? "is-active" : ""}" data-connect="${n.id}" style="animation:riseIn .45s var(--ease-out) ${i*50}ms both">
          <span class="bg" style="width:${(100 - (n.lat / max) * 62).toFixed(0)}%"></span>
          <span class="rk">${i + 1}</span>
          <span class="fl">${n.fl}</span>
          <span class="nm"><b>${esc(n.name)}</b>
            <span>${ic("i-layers", 11)}${esc(n.src)} ${ic("i-activity", 11)}${esc(n.proto.toUpperCase())}</span></span>
          <span class="ms"><span class="mono lat ${latClass(n.lat)}">${n.lat}</span><span>ms</span></span>
        </button>`).join("")}</div>
        <div class="note ok" style="margin:12px 12px 4px">${ic("i-shield", 15)}
          <span>${on ? "Switching re-runs the HTTPS health check before your tunnel changes."
                     : "Quick Connect checks proxy startup, TLS and a live HTTPS response first."}</span></div>`
      : `<div class="empty" style="padding:26px 14px">
          <span class="eic">${ic("i-gauge", 23)}</span><b>Nothing measured yet</b>
          <p>Run a latency test to rank your servers.</p>
          <div class="ea"><button class="btn sm pri" id="testAll">${ic("i-gauge", 13)}Test latency</button></div>
        </div>`}
    </div>
  </section>`;
}

/* ---- event timeline ---- */
function relTime(at){
  const s = Math.max(0, (Date.now() - at) / 1000);
  if (s < 45) return "just now";
  if (s < 3600) return `${Math.round(s/60)} min ago`;
  if (s < 86400) return `${Math.round(s/3600)} h ago`;
  return `${Math.round(s/86400)} d ago`;
}
function eventsHTML(){
  return `
  <section class="card glow">
    <div class="card-h">
      <span class="ic">${ic("i-history", 16)}</span>
      <div><h3>Recent activity</h3><p>What WProxy did on this device</p></div>
      <div class="r"><span class="pill">${S.events.length} entries</span></div>
    </div>
    <div class="card-b" style="padding:8px 0">
      <div class="tl">
        ${S.events.slice(0, 7).map((e, i) => `
          <div class="trow ${e.ok ? "ok" : ""}" style="animation-delay:${i*45}ms">
            <span class="ti">${ic(e.icon, 13)}</span>
            <span class="tt"><b>${esc(e.text)}</b><span>${relTime(e.at)}</span></span>
          </div>`).join("")}
      </div>
    </div>
  </section>`;
}

/* ---- page ---- */
function pageDashboard(){
  const on = S.conn === "on";
  return `<div class="stagger">
    <div class="dsec">
      <div class="sec-h first">
        <span class="si">${ic("i-shield", 13)}</span><h2>Connection</h2>
        <span class="n" id="secConn">${on ? `${S.verified ? "verified" : "active"} · ${dur(S.uptime)}` : S.conn === "busy" ? "establishing…" : "direct — nothing tunnelled"}</span>
      </div>
      <div class="grid-hero">
        ${heroHTML()}
        <div class="vcol">
          ${identityHTML()}
          ${protectHTML()}
        </div>
      </div>
    </div>

    <div class="dsec">
      <div class="sec-h">
        <span class="si">${ic("i-activity", 13)}</span><h2>Activity</h2>
        <span class="n">${on ? "live from the tunnel" : "waiting for a connection"}</span>
      </div>
      ${trafficHTML()}
      ${statsHTML()}
    </div>

    <div class="dsec">
      <div class="sec-h">
        <span class="si">${ic("i-globe", 13)}</span><h2>Your routes</h2>
        <span class="n">${NODES.length} servers · ${favs().length} favorites</span>
        <div class="act" style="display:flex;gap:8px">
          <button class="btn sm ghost" id="addServer">${ic("i-plus", 13)}Add server</button>
        </div>
      </div>
      <div class="two">
        ${favCardHTML()}
        ${leaderHTML()}
      </div>
    </div>

  </div>`;
}

/* ============================================================
   SERVERS
   ============================================================ */
function filtered(){
  const q = S.q.trim().toLowerCase();
  let out = NODES.filter(n => {
    if (S.tab === "fav" && !n.fav) return false;
    if (S.source !== "all" && n.src !== S.source) return false;
    if (S.engine !== "all" && n.engine !== S.engine) return false;
    if (S.hideDead && n.tested && n.lat == null) return false;
    if (!q) return true;
    return [n.name, n.src, n.engine, n.proto, n.city].some(v => String(v).toLowerCase().includes(q));
  });
  if (S.sort === "name") out.sort((a,b) => a.name.localeCompare(b.name));
  if (S.sort === "latency") out.sort((a,b) => (a.lat ?? 1e9) - (b.lat ?? 1e9));
  if (S.sort === "load") out.sort((a,b) => a.load - b.load);
  return out;
}

const isNarrow = () => window.matchMedia("(max-width:700px)").matches;

function rowHTML(n, i){
  const active = S.activeNode === n.id;
  const grid = S.view === "grid" && !isNarrow();
  const narrow = isNarrow();
  const metaItems = narrow
    ? [`${ic("i-pin", 11)}${esc(n.city)}`,
       `${ic("i-gauge", 11)}<b class="lat ${latClass(n.lat)}">${latText(n.lat)}</b>`,
       ...(n.fav ? [`<b class="favmark">${ic("i-star-f", 11)}</b>`] : [])]
    : [`${ic("i-pin", 11)}${esc(n.city)}`, `${ic("i-layers", 11)}${esc(n.src)}`,
       `${ic("i-cpu", 11)}${esc(engName(n.engine))}`, `${ic("i-key", 11)}${esc(n.proto.toUpperCase())}`];
  const head = `
    <span class="fl">${n.fl}</span>
    <span class="nm">
      <b>${esc(n.name)}</b>
      <span class="meta">${metaItems.map(m => `<span>${m}</span>`).join("<i></i>")}</span>
    </span>`;
  const load = "";
  const lat = narrow ? "" : `<span class="lat-col"><span class="mono lat ${latClass(n.lat)}">${latText(n.lat)}</span>
    <span class="cap">${ic(n.lat == null ? "i-alert" : "i-gauge", 10)}${n.lat == null ? "no reply" : "latency"}</span></span>`;
  const acts = `
    <span class="acts">
      ${narrow ? "" : `<button class="icbtn hov" style="width:30px;height:30px;color:${n.fav ? "var(--warn)" : "var(--ink-4)"}" data-fav="${n.id}"
        aria-label="${n.fav ? "Remove from favorites" : "Add to favorites"}">${ic(n.fav ? "i-star-f" : "i-star", 14)}</button>`}
      <button class="btn sm ${active ? "" : "pri"}" data-connect="${n.id}">
        ${ic(active ? "i-shield" : S.conn === "on" ? "i-swap" : "i-bolt", 13)}${active ? "Active" : S.conn === "on" ? "Switch" : "Connect"}</button>
      ${narrow ? "" : `<button class="icbtn" style="width:30px;height:30px" data-open="${n.id}" aria-label="Details">${ic("i-chev", 14)}</button>`}
    </span>`;

  return grid
    ? `<article class="row ${active ? "active" : ""}" style="animation-delay:${Math.min(i,12)*35}ms">
        <div class="top">${head}</div>${load}<div style="display:flex;align-items:center;gap:10px">${lat}${acts}</div>
       </article>`
    : `<article class="row ${active ? "active" : ""}" ${narrow ? `data-open="${n.id}"` : ""} style="animation-delay:${Math.min(i,14)*32}ms">
        ${head}${load}${lat}${acts}
       </article>`;
}

function pageServers(){
  const list = filtered();
  const sources = Array.from(new Set(NODES.map(n => n.src)));
  const engines = Array.from(new Set(NODES.map(n => n.engine)));
  const dirty = S.q || S.source !== "all" || S.engine !== "all" || S.hideDead || S.tab !== "all";

  return `<div class="stagger">
    <div class="filters">
      <div class="segs">
        <button data-tab="all" aria-pressed="${S.tab === "all"}">All servers <span class="count">${NODES.length}</span></button>
        <button data-tab="fav" aria-pressed="${S.tab === "fav"}">${ic("i-star", 13)}Favorites <span class="count">${favs().length}</span></button>
      </div>
      <div class="field grow">${ic("i-search", 15)}
        <input class="inp" id="q" placeholder="Search name, provider, protocol…" value="${esc(S.q)}" autocomplete="off">
      </div>
      <div class="field sel">${ic("i-layers", 15)}
      <select class="inp" id="fSource" aria-label="Source">
        <option value="all" ${S.source === "all" ? "selected" : ""}>All sources</option>
        ${sources.map(s => `<option value="${esc(s)}" ${S.source === s ? "selected" : ""}>${esc(s)}</option>`).join("")}
      </select></div>
      <div class="field sel">${ic("i-cpu", 15)}
      <select class="inp" id="fEngine" aria-label="Engine">
        <option value="all" ${S.engine === "all" ? "selected" : ""}>All engines</option>
        ${engines.map(e => `<option value="${esc(e)}" ${S.engine === e ? "selected" : ""}>${esc(engName(e))}</option>`).join("")}
      </select></div>
      <div class="field sel">${ic("i-sort", 15)}
      <select class="inp" id="fSort" aria-label="Sort by">
        <option value="latency" ${S.sort === "latency" ? "selected" : ""}>Lowest latency</option>
        <option value="name" ${S.sort === "name" ? "selected" : ""}>Name A–Z</option>
      </select></div>
      <label class="check"><input type="checkbox" id="fDead" ${S.hideDead ? "checked" : ""}>${ic("i-ban", 13)}Hide timed out</label>
      <div class="segs" style="margin-left:auto">
        <button data-view="rows" aria-pressed="${S.view === "rows"}" aria-label="List view">${ic("i-rows", 14)}</button>
        <button data-view="grid" aria-pressed="${S.view === "grid"}" aria-label="Grid view">${ic("i-cards", 14)}</button>
      </div>
      <button class="btn sm ghost" id="testAll">${ic("i-gauge", 13)}Test latency</button>
      <button class="btn sm pri" id="addServer">${ic("i-plus", 13)}Add server</button>
      ${dirty ? `<button class="btn sm ghost" id="clearF">${ic("i-x", 13)}Clear filters</button>` : ""}
    </div>

    <div class="sec-h" style="margin-top:4px">
      <span class="si">${ic(S.tab === "fav" ? "i-star" : "i-server", 13)}</span>
      <h2>${S.tab === "fav" ? "Favorite servers" : "Available servers"}</h2>
      <span class="n">${list.length} of ${NODES.length} shown</span>
      ${S.conn === "on" && S.activeNode ? `<span class="act pill ok">${ic("i-shield", 12)}Active: ${esc(node(S.activeNode)?.city || S.snapshot?.status.name || 'Active tunnel')}</span>` : ""}
    </div>

    ${list.length
      ? `<div class="rows ${S.view === "grid" && !isNarrow() ? "grid" : ""}">${list.map(rowHTML).join("")}</div>
         <p style="margin-top:14px;font-size:11.5px;color:var(--ink-4);text-align:center">
           Latency is the server's own response time. HTTPS health is re-checked on every Quick Connect.</p>`
      : `<div class="empty">
          <span class="eic">${ic("i-search", 23)}</span>
          <b>${NODES.length ? "No matching servers" : "No servers yet"}</b>
          <p>${NODES.length ? "Try a different search term, or reset the filters you have applied." : "Add a connection link or a subscription to start your library."}</p>
          <div class="ea">${NODES.length ? `<button class="btn sm" id="clearF2">${ic("i-x", 13)}Reset filters</button>` : `<button class="btn sm pri" id="addServer">${ic("i-plus",13)}Add server</button><button class="btn sm" data-go="subs">Add subscription</button>`}</div>
         </div>`}
  </div>`;
}

/* ============================================================
   SUBSCRIPTIONS
   ============================================================ */
function pageSubs(){
  return `<div class="stagger">
    <div class="sec-h" style="margin-top:0">
      <span class="si">${ic("i-layers", 13)}</span><h2>Your subscriptions</h2>
      <span class="n">${SUBS.length} lists · ${SUBS.reduce((a,s) => a + s.count, 0)} servers</span>
      <div class="act" style="display:flex;gap:8px">
        <button class="btn sm ghost" id="updAll">${ic("i-refresh", 13)}Update all</button>
        <button class="btn sm pri" id="addSub">${ic("i-plus", 13)}Add</button>
      </div>
    </div>
    <p style="font-size:12.5px;color:var(--ink-3);margin:-6px 0 16px;max-width:620px">
      Remote lists refresh in the background. Their URLs stay in local storage and are never shown in the interface.</p>

    <div class="subs">
      ${SUBS.map(s => {
        const pct = s.total ? clamp(s.used / s.total * 100, 0, 100) : null;
        return `<article class="sub">
          <div class="sh">
            <span class="ic">${ic("i-link", 17)}</span>
            <div class="t">
              <b>${esc(s.name)}</b>
              <span>${ic("i-server", 11)}${s.count} servers ${ic("i-calendar", 11)}${esc(s.expires)}</span>
            </div>
            <span class="pill ${pct != null && pct > 85 ? "wn" : "tl"}">${pct != null ? `${Math.round(pct)}%` : "Not reported"}</span>
          </div>
          <div class="meter">
            <div class="mh">
              <span>${ic("i-database", 11)}<b>${bytes(s.used)}</b> used</span>
              <span>${s.total ? `of ${bytes(s.total)}` : "no quota reported"}</span>
            </div>
            <div class="trk"><b class="${pct != null && pct > 85 ? "wn" : ""}" data-w="${pct == null ? 0 : pct}"></b></div>
          </div>
          <div class="sf">
            <span class="when" style="display:inline-flex;align-items:center;gap:5px">${ic("i-clock", 11)}${esc(s.updated)}</span>
            <button class="btn sm ghost" data-upd="${s.id}">${ic("i-refresh", 13)}Update</button>
            <button class="icbtn" style="width:30px;height:30px" data-del-sub="${s.id}" aria-label="Remove subscription">${ic("i-trash", 14)}</button>
          </div>
        </article>`;
      }).join("")}
    </div>

    <div class="sec-h"><span class="si">${ic("i-plus", 13)}</span><h2>Add a subscription</h2></div>
    <section class="card">
      <div class="card-b">
        <div class="two" style="gap:14px">
          <div>
            <label class="lbl" for="subName">Display name <em>— optional</em></label>
            <input class="inp" id="subName" placeholder="Use the name your provider shows">
          </div>
          <div>
            <label class="lbl" for="subUrl">Subscription URL</label>
            <input class="inp" id="subUrl" placeholder="https://…" spellcheck="false">
          </div>
        </div>
        <div class="note" style="margin-top:14px">${ic("i-lock", 15)}
          <span>The URL is stored locally and used only to refresh the list. WProxy picks a compatible engine per server.</span></div>
        <div style="display:flex;gap:9px;margin-top:15px">
          <button class="btn pri" id="saveSub">${ic("i-plus", 15)}Add subscription</button>
          <button class="btn ghost" id="openAdd">${ic("i-link", 15)}Paste a single link</button>
        </div>
      </div>
    </section>
  </div>`;
}

/* ============================================================
   ROUTING
   ============================================================ */
function pageRouting(){
  return `<div class="stagger">
    <div class="sec-h" style="margin-top:0"><span class="si">${ic("i-route", 13)}</span><h2>Routing policy</h2>
      <span class="n">${routedCount()} items applied</span></div>

    <div class="route-modes">
      ${Object.entries(MODES).map(([k, m]) => `
        <button class="rm" data-mode="${k}" aria-pressed="${S.routing === k}">
          <span class="tick"></span>
          <span class="rmi">${ic(m.icon, 16)}</span>
          <b>${m.label}</b><p>${m.desc}</p>
        </button>`).join("")}
    </div>

    <div class="two">
      <section class="card glow">
        <div class="card-h">
          <span class="ic">${ic("i-globe", 16)}</span>
          <div><h3>Sites</h3><p>Hostnames, wildcards or URLs</p></div>
          <div class="r"><span class="pill">${ROUTING.domains.length}</span></div>
        </div>
        <div class="card-b">
          ${ROUTING.domains.length
            ? `<div class="chiprow">${ROUTING.domains.map((d, i) => `
                <span class="chip" style="animation-delay:${i*40}ms">${ic("i-link", 13)}${esc(d)}
                  <button class="x" data-del-dom="${esc(d)}" aria-label="Remove ${esc(d)}">${ic("i-x", 11)}</button></span>`).join("")}</div>`
            : `<p style="font-size:12.5px;color:var(--ink-3)">No sites added. Everything follows the mode above.</p>`}
          <div class="filters" style="margin:15px 0 0">
            <div class="field grow">${ic("i-search", 15)}
              <input class="inp" id="domIn" placeholder="example.com or *.example.com" spellcheck="false"></div>
            <button class="btn sm pri" id="domAdd">${ic("i-plus", 13)}Add site</button>
          </div>
        </div>
      </section>

      <section class="card glow">
        <div class="card-h">
          <span class="ic">${ic("i-app", 16)}</span>
          <div><h3>Applications</h3><p>Matched by real executable path</p></div>
          <div class="r"><span class="pill">${ROUTING.apps.length}</span></div>
        </div>
        <div class="card-b">
          ${ROUTING.apps.length
            ? `<div class="rows">${ROUTING.apps.map((a, i) => `
                <div class="row" style="animation-delay:${i*40}ms;padding:10px 12px">
                  <span class="nm" style="display:flex;align-items:center;gap:11px">
                    <span style="display:grid;place-items:center;width:30px;height:30px;flex:none;border-radius:9px;border:1px solid var(--line);background:var(--panel-3);color:var(--ink-3)">${ic("i-app", 15)}</span>
                    <span style="min-width:0">
                      <b>${esc(a.name)}</b>
                      <span class="meta"><span class="mono" style="font-size:10.5px">${esc(a.path)}</span></span>
                    </span>
                  </span>
                  <span class="acts">
                    
                    <button class="icbtn" style="width:30px;height:30px" data-del-app="${esc(a.path)}" aria-label="Remove ${esc(a.name)}">${ic("i-trash", 14)}</button>
                  </span>
                </div>`).join("")}</div>`
            : `<p style="font-size:12.5px;color:var(--ink-3)">No applications added yet.</p>`}
          <div style="display:flex;gap:9px;margin-top:15px">
            <button class="btn sm pri" id="appAdd">${ic("i-app", 13)}Choose application</button>
            <button class="btn sm ghost" id="appBrowse">Browse executable…</button>
          </div>
        </div>
      </section>
    </div>

    <div class="note" style="max-width:none">${ic("i-info", 15)}
      <span>In <strong>${MODES[S.routing].label.toLowerCase()}</strong>, ${S.routing === "only"
        ? "only the listed apps and sites are tunnelled — everything else goes out directly."
        : S.routing === "all" ? "the lists above are kept but every connection is tunnelled anyway."
        : "listed apps and sites stay direct; all other traffic uses the tunnel."}</span></div>
  </div>`;
}

/* ============================================================
   SETTINGS
   ============================================================ */
function pageSettings(){
  const act = S.activeNode ? node(S.activeNode) : null;
  return `<div class="stagger">
    <div class="sec-h" style="margin-top:0"><span class="si">${ic("i-sliders", 13)}</span><h2>Appearance & behaviour</h2></div>
    <div class="sets">
      <div class="set">
        <span class="ic">${ic("i-sun", 17)}</span>
        <div class="tx"><b>Theme</b><p>Pick a look or follow your operating system.</p></div>
        <div class="ctl segs">
          <button data-set-theme="system" aria-pressed="${S.theme === "system"}">System</button>
          <button data-set-theme="light" aria-pressed="${S.theme === "light"}">Light</button>
          <button data-set-theme="dark" aria-pressed="${S.theme === "dark"}">Dark</button>
        </div>
      </div>
      <div class="set">
        <span class="ic">${ic("i-play", 17)}</span>
        <div class="tx"><b>Interface animations</b><p>Page transitions, the connection dial and live graphs. Reduced-motion settings always win.</p></div>
        <div class="ctl"><span class="sw" role="switch" tabindex="0" id="swAnims" aria-checked="${S.anims}" aria-label="Interface animations"></span></div>
      </div>
      <div class="set">
        <span class="ic">${ic("i-update", 17)}</span>
        <div class="tx"><b>Automatic updates</b><p>Check verified GitHub releases and install them in the background.</p></div>
        <div class="ctl"><span class="sw" role="switch" tabindex="0" id="swUpd" aria-checked="${S.autoUpdate}" aria-label="Automatic updates"></span></div>
      </div>
      ${S.platform === 'linux' ? `<div class="set">
        <span class="ic">${ic("i-lock", 17)}</span>
        <div class="tx"><b>Ask for permission once</b><p>Your first connection remembers approval for WProxy. Turn this off to revoke it.</p></div>
        <div class="ctl"><span class="sw" role="switch" tabindex="0" id="swAuth" aria-checked="${S.rememberAuth}" aria-label="Remember permission"></span></div>
      </div>` : ''}
      <div class="set">
        <span class="ic">${ic("i-refresh", 17)}</span>
        <div class="tx"><b>Check for updates</b><p>${esc(S.updateLabel)}</p></div>
        <div class="ctl"><button class="btn sm" id="chkUpd">${ic("i-refresh", 13)}Check now</button></div>
      </div>
    </div>

    <div class="sec-h"><span class="si">${ic("i-cpu", 13)}</span><h2>System readiness</h2>
      <span class="n">${ENGINES.filter(e => e.ok).length} of ${ENGINES.length} engines installed</span></div>
    <section class="card">
      <div class="card-b">
        <div class="engines">
          ${ENGINES.map(e => `
            <div class="eng ${e.ok ? "ok" : ""}">
              <span class="av">${e.name.slice(0,1).toUpperCase()}</span>
              <div class="t"><b>${esc(engName(e.name))}</b><span>${e.version ? `v${e.version}` : "not installed"}</span></div>
              <span class="st pill ${e.ok ? "ok" : "dg"}">${e.ok ? "Ready" : "Missing"}</span>
            </div>`).join("")}
        </div>
        <div class="note ok" style="margin-top:15px">${ic("i-shield", 15)}
          <span>WProxy validates a route with a real HTTPS request before Quick Connect changes your tunnel.</span></div>
        <div style="display:flex;gap:9px;margin-top:14px;flex-wrap:wrap">
          <button class="btn" id="healthBtn">${ic("i-gauge", 15)}Check connection health</button>
          <button class="btn ghost" data-go="routing">${ic("i-route", 15)}Review routing</button>
        </div>
      </div>
    </section>

    <div class="sec-h"><span class="si">${ic("i-activity", 13)}</span><h2>Diagnostics</h2></div>
    <div class="tiles">
      <div class="tile">
        <span class="k">${ic("i-shield", 12)}Active session</span>
        <div class="v" style="font-family:var(--ff);font-size:15px;font-weight:600">${S.conn === "on" ? esc(act ? act.city : "Private tunnel") : "Direct connection"}</div>
        <div class="d">${S.conn === "on" ? `${esc(engName(act ? act.engine : "xray"))} · ${dur(S.uptime)}` : "No tunnel active"}</div>
      </div>
      <div class="tile">
        <span class="k">${ic("i-route", 12)}Policy</span>
        <div class="v" style="font-family:var(--ff);font-size:15px;font-weight:600">${MODES[S.routing].label}</div>
        <div class="d">${routedCount()} applied items</div>
      </div>
      <div class="tile">
        <span class="k">${ic("i-gauge", 12)}Session traffic</span>
        <div class="v">${bytes(S.rx + S.tx)}</div>
        <div class="d">${bytes(S.rx)} in · ${bytes(S.tx)} out</div>
      </div>
      <div class="tile">
        <span class="k">${ic("i-app", 12)}Platform</span>
        <div class="v" style="font-family:var(--ff);font-size:15px;font-weight:600">${esc(S.platform)}</div>
        <div class="d">${S.platform === "windows" ? "Tauri desktop · Wintun" : "Tauri desktop · NetworkManager"}</div>
      </div>
    </div>
    <div class="note" style="max-width:none;margin-top:12px">${ic("i-info", 15)}
      <span><strong>Last diagnostic.</strong> ${esc(S.diagnostic)}</span></div>
    <p style="text-align:center;font-size:11.5px;color:var(--ink-4);margin-top:26px">
      WProxy 2.8.4 · ${IS_NATIVE ? (S.platform === 'windows' ? 'Windows' : 'Linux') : "design preview · connections require the installed app"}</p>
  </div>`;
}

/* ============================================================
   RENDER
   ============================================================ */
const PAGES = {
  dashboard: { title:"Dashboard",     sub:"Session overview",   render:pageDashboard },
  servers:   { title:"Servers",       sub:"Your library",       render:pageServers  },
  subs:      { title:"Subscriptions", sub:"Remote lists",       render:pageSubs     },
  routing:   { title:"Routing",       sub:"Traffic policy",     render:pageRouting  },
  settings:  { title:"Settings",      sub:"Preferences",        render:pageSettings },
};

function syncChrome(){
  const p = PAGES[S.page];
  $("#pageTitle").textContent = p.title;
  $("#pageSub").textContent = p.sub;
  document.title = `WProxy — ${p.title}`;
  $("#navServers").textContent = NODES.length;
  $("#navSubs").textContent = SUBS.length;
  $("#navRouting").textContent = routedCount();
  $$("#nav a, #tabbar a").forEach(a => {
    if (a.dataset.page === S.page) a.setAttribute("aria-current", "page");
    else a.removeAttribute("aria-current");
  });
  const act = S.activeNode ? node(S.activeNode) : null;
  $("#rsName").textContent = S.conn === "on" ? (act ? act.city : "Connected")
    : S.conn === "busy" ? "Connecting…" : "Not connected";
  $("#rsMeta").textContent = S.conn === "on" ? dur(S.uptime) : S.conn === "busy" ? "Checking" : "Direct";
  $("#railState").title = $("#rsName").textContent;
}

let renderToken = 0;
function render(animate=true){
  const my = ++renderToken;
  const page = $("#page");
  saveDrafts();
  page.innerHTML = PAGES[S.page].render();
  page.classList.remove("enter");
  if (animate && S.anims) { void page.offsetWidth; page.classList.add("enter"); }
  syncChrome();
  afterRender();
  restoreDrafts();
  updateBusyControls();
  return my;
}

/* things that need the DOM to exist */
function afterRender(){
  // dial ring
  updateConnectionAppearance();
  // meters animate from 0
  $$(".meter .trk b").forEach(b => {
    const w = b.dataset.w;
    requestAnimationFrame(() => { b.style.width = `${w}%`; });
  });
  // spotlight follow
  $$(".card.glow").forEach(c => {
    c.addEventListener("pointermove", e => {
      const r = c.getBoundingClientRect();
      c.style.setProperty("--mx", `${e.clientX - r.left}px`);
      c.style.setProperty("--my", `${e.clientY - r.top}px`);
    });
  });
}

const CIRC = 2 * Math.PI * 96;
function paintDial(){
  const p = $("#dialProg");
  if (!p) return;
  let frac = 0;
  if (S.conn === "on") frac = 1;
  else if (S.conn === "busy") frac = (S.step + 1) / (STEPS.length + 1);
  else frac = 0.04;
  p.style.strokeDashoffset = String(CIRC * (1 - frac));
}

/* ============================================================
   NAVIGATION
   ============================================================ */
function go(p){
  if (!PAGES[p]) return;
  const same = S.page === p;
  S.page = p;
  render(!same);
  $("#scroll").scrollTop = 0;
}

/* Native data and actions use the existing CLI/Tauri contract. */
const drafts = new Map();
let focusDraft = null;
let statusPending = false;
let automaticUpdateStarted = false;
let updateInProgress = false;
function saveDrafts(){
  const active=document.activeElement;
  focusDraft=active?.matches('#page input, #page textarea')?{id:active.id,start:active.selectionStart,end:active.selectionEnd}:null;
  $$('#page input[id]:not([type=checkbox]), #page textarea[id]').forEach(el=>drafts.set(el.id,el.value));
}
function restoreDrafts(){
  for(const [id,value] of drafts){const el=document.getElementById(id);if(el && el.closest('#page') && el.id!=='q')el.value=value;}
  if(focusDraft){const el=document.getElementById(focusDraft.id);if(el){el.focus({preventScroll:true});if(el.setSelectionRange&&focusDraft.start!=null)el.setSelectionRange(focusDraft.start,focusDraft.end);}}
}
function clearDraft(id){drafts.delete(id);const el=document.getElementById(id);if(el)el.value='';}
function updateBusyControls(){
  const selectors='[data-connect], [data-disconnect], [data-mode], [data-del-dom], [data-del-app], [data-del-sub], [data-remove-node], [data-upd], #dial, #dial2, #testAll, #saveNode, #saveSub, #domAdd, #appAdd, #appBrowse, #updAll, #healthBtn, #chkUpd, #swUpd, #swAuth';
  $$(selectors).forEach(el=>{
    const blocked=S.busy || (updateInProgress&&['chkUpd','swUpd'].includes(el.id));
    if(el.tagName==='BUTTON')el.disabled=blocked || (!NODES.length&&['dial','dial2','testAll','healthBtn'].includes(el.id)) || (el.hasAttribute('data-remove-node')&&el.dataset.removeNode===S.activeNode);
    else el.setAttribute('aria-disabled',String(blocked));
  });
  $('#page').setAttribute('aria-busy',String(S.busy));
}
function applyStatus(value){
  const oldNode=S.activeNode;
  const sample=history.sample(value,performance.now());
  S.activeNode=value.active?(value.node_id ?? null):null;
  if(S.activeNode)S.node=S.activeNode;
  S.conn=value.active?'on':'off';
  S.verified=value.verified===true;
  S.uptime=value.connected_seconds||0;
  S.rx=value.rx_bytes??null;S.tx=value.tx_bytes??null;
  S.memory=value.core_memory_bytes??null;
  S.dn=sample.download;S.up=sample.upload;
  S.samples=history.points.map(p=>({dn:p.download,up:p.upload}));
  if(oldNode!==S.activeNode||!value.active)S.peak=0;
  S.peak=Math.max(S.peak,S.dn);
  updateConnectionAppearance();
}
function updateConnectionAppearance(){
  document.body.dataset.conn=S.pendingConnection&&S.conn!=='on'?'busy':S.conn;
  document.body.dataset.pending=String(Boolean(S.pendingConnection));
  const label=$('#dial .core-lbl');
  if(label)label.textContent=S.pendingConnection?'Working':S.conn==='on'?'Disconnect':'Connect';
  const detail=$('#dial .core-sub');
  if(detail)detail.textContent=S.pendingConnection?S.progress||'Please wait…':S.conn==='on'?dur(S.uptime):'Tap the dial';
  const button=$('#dial');
  if(button)button.setAttribute('aria-label',S.pendingConnection?'Connection in progress':S.conn==='on'?'Disconnect':'Quick connect');
  const secondary=$('#dial2');
  if(secondary)secondary.textContent=S.pendingConnection?S.progress||'Please wait…':S.conn==='on'?'Disconnect':'Quick connect';
  const eyebrow=$('.hero-top .eyebrow span');
  if(eyebrow)eyebrow.textContent=S.pendingConnection?S.progress||'Connecting…':S.conn==='on'?S.verified?'HTTPS verified':'Tunnel active':'Ready to connect';
  const active=node(S.activeNode);
  const heading=$('.hero-top h2');
  if(heading)heading.textContent=S.conn==='on'?(active?.name||S.snapshot?.status.name||'Connected'):S.pendingConnection?'Hold on a moment':'Your traffic, your route.';
  const icon=$('#dial .core-ic');
  const iconName=S.pendingConnection?'refresh':S.conn==='on'?'shield':'power';
  if(icon&&icon.dataset.icon!==iconName){icon.innerHTML=ic(iconName,34);icon.dataset.icon=iconName;}
  const caption=$('.path-cap');
  if(caption)caption.textContent=S.conn==='on'?`${S.verified?'HTTPS check passed':'HTTPS verification unavailable'} · ${engName(active?.engine||S.snapshot?.status.engine||'Core')}`:S.pendingConnection?S.progress||'Waiting for WProxy…':'WProxy validates a route with a real HTTPS request before switching your tunnel.';
  const section=$('#secConn');
  if(section)section.textContent=S.pendingConnection?'establishing…':S.conn==='on'?`${S.verified?'verified':'active'} · ${dur(S.uptime)}`:'direct — nothing tunnelled';
  const fields={'Session':S.conn==='on'?dur(S.uptime):'—','Core memory':bytes(S.memory)};
  for(const [key,value] of Object.entries(fields)){
    const field=$(`[data-session-field="${key}"]`);if(field)field.textContent=value;
  }
  $('.steps')?.classList.toggle('hide',S.conn!=='on'&&!S.pendingConnection);
  $$('.steps i').forEach((step,i)=>{
    step.classList.toggle('done',S.conn==='on'&&!S.pendingConnection||Boolean(S.pendingConnection)&&i<S.step);
    step.classList.toggle('on',Boolean(S.pendingConnection)&&i===S.step);
  });
  paintDial();
}
function snapshotViewKey(snap){
  const value=snap.status;
  return JSON.stringify({platform:snap.platform,nodes:snap.nodes,subscriptions:snap.subscriptions,
    routing:snap.routing,preferences:snap.preferences,cores:snap.cores,
    status:{active:value.active===true,node_id:value.active?(value.node_id??null):null,verified:value.verified===true,name:value.name??null,engine:value.engine??null,protocol:value.protocol??null}});
}
let snapshotPending=null;
let lastSnapshotRead=0;
async function refreshSnapshot(forceRender=false){
  if(snapshotPending){await snapshotPending;if(!forceRender)return;}
  snapshotPending=readSnapshot(forceRender);
  try{return await snapshotPending;}finally{snapshotPending=null;}
}
async function readSnapshot(forceRender=false){
  const snap=await client.read();
  const viewKey=snapshotViewKey(snap);
  const unchanged=!forceRender&&S.viewKey===viewKey&&!S.error;
  const pings=new Map(NODES.filter(n=>n.tested).map(n=>[n.id,n.lat]));
  const oldSelected=S.node;
  NODES.splice(0,NODES.length,...snap.nodes.map(n=>({
    ...n,fl:n.name.match(/[\u{1F1E6}-\u{1F1FF}]{2}/u)?.[0]||'↗',city:n.name,
    src:n.source_name||'Manual',engine:n.engine||'unknown',proto:n.protocol||'unknown',
    lat:pings.get(n.id)??null,tested:pings.has(n.id),fav:favorites.has(n.id),load:null,
  })));
  SUBS.splice(0,SUBS.length,...snap.subscriptions.map(sub=>{
    const health=subscriptionHealth(sub);
    return {...sub,count:sub.node_count,used:health.usedBytes,total:health.totalBytes,
      expires:health.expiryLabel||'Expiry not reported',updated:health.updatedLabel};
  }));
  ENGINES.splice(0,ENGINES.length,...snap.cores.map(core=>({name:core.engine,version:core.version,ok:core.available})));
  S.platform=snap.platform;S.snapshot=snap;S.error='';
  S.autoUpdate=snap.preferences.auto_update;S.rememberAuth=snap.preferences.remember_authorization;
  S.routing=snap.routing.mode;
  ROUTING.domains=snap.routing.domains;
  ROUTING.apps=snap.routing.apps.map(path=>({name:path.split(/[\\/]/).pop()||path,path}));
  applyStatus(snap.status);
  if(!S.activeNode)S.node=NODES.some(n=>n.id===oldSelected)?oldSelected:NODES[0]?.id||null;
  S.viewKey=viewKey;lastSnapshotRead=performance.now();
  if(!unchanged)render(false);
  else {updateLiveDom();updateConnectionAppearance();updateBusyControls();}
  if(S.autoUpdate&&!automaticUpdateStarted){automaticUpdateStarted=true;window.setTimeout(()=>checkUpdates(true),1000);}
}
function showSnapshotError(error){
  S.error=String(error?.message||error);
  $('#page').innerHTML=`<div class="empty" role="alert"><span class="eic">${ic('i-alert',24)}</span><b>Could not read WProxy</b><p>${esc(S.error)}</p><button class="btn" id="retrySnapshot">Try again</button></div>`;
}
async function pollStatus(){
  if(!IS_NATIVE||S.busy||statusPending||document.hidden||!S.snapshot)return;
  statusPending=true;
  try{
    const status=await client.status();
    const changed=(status.active===true)!==(S.conn==='on')||(status.active?(status.node_id??null):null)!==S.activeNode||(status.verified===true)!==S.verified;
    const prevD=S.dn,prevU=S.up;applyStatus(status);S.snapshot.status=status;
    S.viewKey=snapshotViewKey(S.snapshot);
    if(changed)render(false);
    else updateLiveDom(prevD,prevU);
  }catch{S.diagnostic='Live status is temporarily unavailable. Refresh to retry.';}
  finally{statusPending=false;}
}
function updateLiveDom(prevD=S.dn,prevU=S.up){
  if(S.page==='dashboard'){
    paintLive(prevD,prevU);
    const uptime=$('#upt');if(uptime)uptime.textContent=dur(S.uptime);
    const tile=$('#tUptime');if(tile)tile.textContent=dur(S.uptime);
  }
  syncChrome();
}
function handleWindowFocus(){
  if(!S.busy&&performance.now()-lastSnapshotRead>10000)refreshSnapshot().catch(showSnapshotError);
}
async function runAction(label,callback){
  if(S.busy)return;
  if(!IS_NATIVE){toast('Design preview: use the installed WProxy app for this action.','i-info');return;}
  S.busy=true;updateBusyControls();
  try{await callback();await refreshSnapshot(true);toast(label);}
  catch(error){await refreshSnapshot(true).catch(showSnapshotError);toast(String(error?.message||error),'i-alert');}
  finally{S.busy=false;S.pendingConnection=false;S.progress='';updateConnectionAppearance();updateBusyControls();}
}
function connect(id){
  return runAction('Connection ready',async()=>{
    if(!S.snapshot)throw new Error('Refresh the server library first.');
    S.node=id;S.pendingConnection=true;S.progress='Connecting…';S.step=1;updateConnectionAppearance();
    await client.connect(id,S.snapshot);
  });
}
function quickConnect(){
  return runAction('Connection ready',async()=>{
    if(!S.snapshot)throw new Error('Refresh the server library first.');
    S.pendingConnection=true;S.progress='Verifying HTTPS…';S.step=0;updateConnectionAppearance();
    const best=await client.quickConnect(S.snapshot);
    const n=node(best.id);if(n){n.lat=best.latency_ms;n.tested=true;}
  });
}
function disconnect(){return runAction('Disconnected',()=>client.disconnect());}
function toggleConn(){if(S.busy)return;return S.conn==='on'?disconnect():quickConnect();}
function testAll(){
  return runAction('Latency test complete',async()=>{
    const results=await client.ping();
    for(const row of results){const n=node(row.id);if(n){n.lat=row.latency_ms;n.tested=true;}}
  });
}
function testNode(id){return runAction('Server test complete',async()=>{for(const row of await client.ping(id)){const n=node(row.id);if(n){n.lat=row.latency_ms;n.tested=true;}}});}
async function changeRouting(args){await client.route(args,S.snapshot);}
async function chooseApplication(browse=false){
  if(!IS_NATIVE){toast('Application selection is available in the installed app.','i-info');return;}
  if(browse){const path=await open({multiple:false,directory:false,title:'Choose an application executable'});if(typeof path==='string')return runAction('Application added',()=>changeRouting(['app','add',path]));return;}
  openModal({icon:'i-app',title:'Choose application',desc:'Select the actual running or installed executable.',body:'<p role="status">Loading applications…</p>',foot:'<button class="btn ghost" data-close>Cancel</button>'});
  try{
    const apps=await client.call('list_applications');
    $('#modalBody').innerHTML='<label class="lbl" for="appSearch">Find application</label><input class="inp" id="appSearch" placeholder="Name or executable"><div class="application-results">'+apps.map(a=>`<button class="app-option" data-add-app="${esc(a.path)}">${ic('i-app',16)}<span><b>${esc(a.name)}</b><small>${esc(a.path)}${a.running?' · running':''}</small></span></button>`).join('')+'</div>';
    $('#appSearch').focus();
  }catch(error){closeLayer();toast(String(error?.message||error),'i-alert');}
}
async function checkUpdates(automatic=false){
  if(!IS_NATIVE||S.busy||updateInProgress)return;
  updateInProgress=true;
  updateBusyControls();
  S.updateLabel='Checking releases…';if(S.page==='settings')render(false);
  try{
    const result=await client.ctl(['update',automatic?'download':'check','--json',...(automatic?['--platform',S.platform]:[]),'--timeout',automatic?'30':'15']);
    if(!result.update_available){S.updateLabel='Up to date';if(!automatic)toast('Up to date');}
    else if(automatic&&result.path){await client.call('install_update',{path:result.path});S.updateLabel='Installed. Reopen WProxy';toast('Update installed. Reopen WProxy.');}
    else{S.updateLabel=`Version ${result.latest_version} available`;confirmModal({title:'Install update?',desc:`Download the verified release ${esc(result.latest_version)} and install it?`,confirmLabel:'Install',icon:'i-update',onConfirm:()=>runAction('Update installed. Reopen WProxy.',async()=>{const next=await client.ctl(['update','download','--json','--platform',S.platform,'--timeout','30']);if(next.path)await client.call('install_update',{path:next.path});})});}
  }catch(error){S.updateLabel='Update check failed';toast(String(error?.message||error),'i-alert');}
  finally{updateInProgress=false;updateBusyControls();}
  if(S.page==='settings')render(false);
}

function paintLive(prevD, prevU){
  const d = rate(S.dn), u = rate(S.up), pd = rate(prevD), pu = rate(prevU);
  const dv = $("#dnVal"), uv = $("#upVal");
  if (dv){
    const unit = dv.nextElementSibling;
    if (unit && unit.textContent !== d.u){ unit.textContent = d.u; dv.textContent = d.v; }
    else countTo(dv, pd.u === d.u ? pd.v : d.v, d.v, 420);
  }
  if (uv){
    const unit = uv.nextElementSibling;
    if (unit && unit.textContent !== u.u){ unit.textContent = u.u; uv.textContent = u.v; }
    else countTo(uv, pu.u === u.u ? pu.v : u.v, u.v, 420);
  }
  // totals
  const tots = $$(".rate .tot");
  if (tots[0]) tots[0].textContent = `${bytes(S.rx)} received`;
  if (tots[1]) tots[1].textContent = `${bytes(S.tx)} sent`;
  // bars
  ["dn","up"].forEach((key, idx) => {
    const host = $$(".rate .bars")[idx];
    if (!host) return;
    const s = S.samples.slice(-10);
    const max = Math.max(1, ...S.samples.slice(-24).map(p => p[key]));
    const bars = $$("i", host);
    s.forEach((p, i) => { if (bars[i]) bars[i].style.height = `${clamp((p[key]/max)*26, 2, 26).toFixed(1)}px`; });
  });
  // live stat tiles
  const td = $("#tData");     if (td) td.textContent = bytes(S.rx + S.tx);
  const tds = $("#tDataSub"); if (tds) tds.textContent = `${bytes(S.rx)} in · ${bytes(S.tx)} out`;
  const tp = $("#tPeak");
  if (tp){ const r = rate(S.peak); tp.innerHTML = `${r.v}<span style="font-size:12px;color:var(--ink-4)"> ${r.u}</span>`; }
  const tps = $("#tPeakSub"); if (tps) tps.textContent = `${S.samples.length} samples recorded`;
  // chart (replace svg markup only)
  const chart = $(".chart");
  if (chart){
    const next = document.createElement("div");
    next.innerHTML = chartHTML();
    chart.replaceWith(next.firstElementChild);
  }
}


/* ============================================================
   OVERLAYS
   ============================================================ */
let openLayer = null, lastFocus = null;

function showScrim(on){ $("#scrim").classList.toggle("show", on); }
function closeLayer(){
  if (!openLayer) return;
  openLayer.classList.remove("show");
  showScrim(false);
  openLayer = null;
  document.querySelector('.shell').inert=false;
  document.querySelector('#tabbar').inert=false;
  if (lastFocus && lastFocus.isConnected) lastFocus.focus();
}
function openOverlay(el){
  if (openLayer && openLayer !== el) openLayer.classList.remove("show");
  lastFocus = document.activeElement;
  openLayer = el;
  showScrim(true);
  el.classList.add("show");
  document.querySelector('.shell').inert=true;
  document.querySelector('#tabbar').inert=true;
  const first=el.querySelector('input,textarea,button:not(:disabled),[tabindex="0"]');
  if(first)first.focus({preventScroll:true});
}

/* --- server detail sheet --- */
function openDetail(id){
  const n = node(id);
  if (!n) return;
  const active = S.activeNode === n.id;
  const sub = SUBS.find(s => s.name === n.src);
  $("#sheetBody").innerHTML = `
    <div class="detail-hero">
      <div class="fl">${n.fl}</div>
      <h3>${esc(n.name)}</h3>
      <p>${esc(n.src)}</p>
      <span class="lat mono ${latClass(n.lat)}">${latText(n.lat)} endpoint latency</span>
    </div>
    <div class="note ${active ? "ok" : ""}" style="margin-top:15px">${ic(active ? "i-shield" : "i-info", 15)}
      <span>${active
        ? (S.conn === "on" ? `<strong>Active tunnel.</strong> ${S.verified ? "HTTPS check passed on this route." : "HTTPS verification is not reported."}` : "<strong>Selected.</strong> Not connected right now.")
        : "Saved in your library. Connect here, or keep it as a favorite for later."}</span></div>
    <div class="kv">
      <div>${ic("i-gauge", 13)}Server response</div><div class="lat ${latClass(n.lat)}">${latText(n.lat)}</div>
      <div>${ic("i-key", 13)}Protocol</div><div>${esc(n.proto.toUpperCase())}</div>
      <div>${ic("i-cpu", 13)}Connection engine</div><div>${esc(engName(n.engine))}</div>
      <div>${ic("i-info", 13)}Engine version</div><div>${esc((ENGINES.find(e => e.name === n.engine) || {}).version || "not reported")}</div>
      
      <div>${ic("i-layers", 13)}Source</div><div>${esc(n.src)}</div>
    </div>
    ${sub ? `
    <div class="sec-h" style="margin:20px 0 10px"><span class="si">${ic("i-layers", 13)}</span><h2 style="font-size:13px">From this subscription</h2></div>
    <button class="pick" style="margin-top:0" data-go="subs">
      <span class="fl" style="font-size:19px">${ic("i-layers", 19)}</span>
      <span class="tx"><span class="v" style="font-size:13.5px">${esc(sub.name)}</span>
      <span class="m"><span>${sub.count} servers · ${bytes(sub.used)} used</span></span></span>
      <span class="ch">${ic("i-arrow", 15)}</span>
    </button>` : ""}
    <div class="note" style="margin-top:15px">${ic("i-info", 15)}
      <span>Latency is measured at the server endpoint. It is not a throughput test.</span></div>`;

  $("#sheetFoot").innerHTML = `
    <button class="btn ghost" data-test-node="${n.id}">${ic("i-gauge",15)}Test</button>
    <button class="btn danger" data-remove-node="${n.id}" ${S.activeNode === n.id ? "disabled" : ""}>${ic("i-trash",15)}Remove</button>
    <button class="btn ghost" data-fav="${n.id}" style="flex:0 0 auto;color:${n.fav ? "var(--warn)" : "var(--ink-2)"}">
      ${ic(n.fav ? "i-star-f" : "i-star", 15)}${n.fav ? "Favorited" : "Favorite"}</button>
    <button class="btn ${active && S.conn === "on" ? "danger" : "pri"}" data-${active && S.conn === "on" ? "disconnect" : "connect"}="${n.id}">
      ${ic(active && S.conn === "on" ? "i-power" : "i-bolt", 15)}${active && S.conn === "on" ? "Disconnect" : S.conn === "on" ? "Switch here" : "Connect"}</button>`;
  openOverlay($("#sheet"));
}

/* --- modal builder --- */
function openModal({ icon="i-info", title, desc, body="", foot }){
  $("#modalHead").innerHTML = `
    <span class="ic">${ic(icon, 18)}</span>
    <div class="t"><h3>${esc(title)}</h3>${desc ? `<p>${desc}</p>` : ""}</div>
    <button class="icbtn" data-close aria-label="Close">${ic("i-x", 16)}</button>`;
  $("#modalBody").innerHTML = body;
  $("#modalFoot").innerHTML = foot;
  openOverlay($("#modal"));
  const f = $("#modalBody input, #modalBody textarea");
  if (f) setTimeout(() => f.focus(), 260);
}

function addServerModal(){
  openModal({
    icon:"i-link", title:"Add a server",
    desc:"Paste a proxy link, or a sing-box, Xray or Clash configuration.",
    body:`
      <label class="lbl" for="nName">Display name <em>— optional</em></label>
      <input class="inp" id="nName" placeholder="🇮🇸 Reykjavík · Night shift">
      <label class="lbl" for="nCfg" style="margin-top:14px">Connection link or configuration</label>
      <textarea class="inp" id="nCfg" placeholder="vless://… &#10;or paste a full JSON configuration" spellcheck="false"></textarea>
      <div class="note" style="margin-top:13px">${ic("i-lock", 15)}
        <span>Your original configuration is kept locally. WProxy selects a compatible engine automatically.</span></div>`,
    foot:`<button class="btn ghost" data-close>Cancel</button>
          <button class="btn ghost" id="impFile">Import file…</button>
          <button class="btn pri" id="saveNode">${ic("i-plus", 15)}Save server</button>`,
  });
}

function confirmModal({ title, desc, confirmLabel, onConfirm, icon="i-trash" }){
  openModal({ icon, title, desc, body:"", foot:
    `<button class="btn ghost" data-close>Keep it</button>
     <button class="btn danger" id="confirmYes">${confirmLabel}</button>` });
  $("#confirmYes").onclick = () => { closeLayer(); Promise.resolve(onConfirm()).catch(error=>toast(String(error?.message||error),'i-alert')); };
}

/* ============================================================
   COMMAND PALETTE
   ============================================================ */
let palSel = 0, palItems = [];

function palBuild(q=""){
  const t = q.trim().toLowerCase();
  const groups = [];

  const actions = [
    { icon:"i-bolt",    title: S.conn === "on" ? "Disconnect" : "Quick connect", sub:"Toggle the tunnel", run:toggleConn, keys:"connect disconnect tunnel power" },
    { icon:"i-gauge",   title:"Test latency on every server", sub:"Measure round trip", run:testAll, keys:"latency ping speed test" },
    { icon:"i-plus",    title:"Add a server", sub:"Paste a link or configuration", run:addServerModal, keys:"add new link import" },
    { icon:"i-sun",     title:"Switch theme", sub:`Currently ${document.documentElement.dataset.theme}`, run:() => setTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark"), keys:"theme dark light appearance" },
    { icon:"i-play",    title: S.motion === "paused" ? "Resume motion" : "Pause motion", sub:"Background animations", run:toggleMotion, keys:"motion animation pause" },
  ];
  const pages = Object.entries(PAGES).map(([k, p]) => ({
    icon: { dashboard:"i-grid", servers:"i-globe", subs:"i-layers", routing:"i-route", settings:"i-cog" }[k],
    title: p.title, sub: p.sub, run: () => go(k), keys: `${p.title} ${p.sub}`,
  }));
  const servers = NODES.map(n => ({
    icon:"i-globe", title:`${n.fl} ${n.name}`, sub:`${n.src} · ${engName(n.engine)} · ${latText(n.lat)}`,
    run: () => openDetail(n.id), keys:`${n.name} ${n.city} ${n.src} ${n.engine} ${n.proto}`,
  }));

  const match = arr => arr.filter(x => !t || `${x.title} ${x.sub} ${x.keys}`.toLowerCase().includes(t));
  const a = match(actions), p = match(pages), s = match(servers);
  if (a.length) groups.push(["Actions", a]);
  if (p.length) groups.push(["Pages", p]);
  if (s.length) groups.push(["Servers", s]);

  palItems = groups.flatMap(g => g[1]);
  palSel = clamp(palSel, 0, Math.max(0, palItems.length - 1));

  let idx = 0;
  $("#palList").innerHTML = groups.length ? groups.map(([name, items]) => `
    <div class="pal-g">${name}</div>
    ${items.map(it => {
      const i = idx++;
      return `<button class="pal-o" data-pal="${i}" data-sel="${i === palSel ? 1 : 0}">
        <span class="ic">${ic(it.icon, 14)}</span>
        <span class="t"><b>${esc(it.title)}</b><span>${esc(it.sub)}</span></span>
        <span class="go">Open</span></button>`;
    }).join("")}`).join("")
    : `<div class="empty" style="padding:34px 20px">
        <span class="eic">${ic("i-search", 22)}</span><b>No matches</b>
        <p>Try a server name, provider, protocol or page.</p></div>`;
  $("#palCount").textContent = palItems.length ? `${palItems.length} result${palItems.length === 1 ? "" : "s"}` : "";
  const sel = $(`[data-pal="${palSel}"]`);
  if (sel) sel.scrollIntoView({ block:"nearest" });
}

function palOpen(){
  $("#palInput").value = ""; palSel = 0; palBuild("");
  openOverlay($("#pal"));
  setTimeout(() => $("#palInput").focus(), 120);
}
function palRun(i){
  const it = palItems[i];
  if (!it) return;
  closeLayer();
  setTimeout(it.run, 140);
}

/* ============================================================
   THEME + MOTION
   ============================================================ */
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
reducedMotion.addEventListener("change",()=>applyAnims());
const mqDark = window.matchMedia("(prefers-color-scheme: dark)");
function applyTheme(){
  const t = S.theme === "system" ? (mqDark.matches ? "dark" : "light") : S.theme;
  document.documentElement.dataset.theme = t;
  const u = $("#themeBtn use");
  if (u) u.setAttribute("href", t === "dark" ? "#i-sun" : "#i-moon");
}
function setTheme(t){
  S.theme = t;
  writeLocal("wp.theme", t);
  applyTheme();
  if (S.page === "settings") render(false);
}
mqDark.addEventListener("change", () => { if (S.theme === "system") applyTheme(); });

function toggleMotion(){
  S.motion = S.motion === "paused" ? "on" : "paused";
  document.body.dataset.motion = !S.anims || reducedMotion.matches ? "off" : document.hidden ? "paused" : S.motion;
  const b = $("#motionBtn");
  b.querySelector("use").setAttribute("href", S.motion === "paused" ? "#i-play" : "#i-pause");
  b.querySelector(".t").textContent = S.motion === "paused" ? "Resume motion" : "Pause motion";
  writeLocal("wproxy.v4.motion",S.motion);
  toast(S.motion === "paused" ? "Background motion paused" : "Motion resumed", "i-play");
}
function applyAnims(){
  document.body.dataset.motion = !S.anims || reducedMotion.matches ? "off" : document.hidden ? "paused" : S.motion;
}

/* re-render when crossing the mobile breakpoint so layouts swap cleanly */
let wasNarrow = isNarrow();
let rzT = 0;
window.addEventListener("resize", () => {
  clearTimeout(rzT);
  rzT = setTimeout(() => {
    const now = isNarrow();
    if (now !== wasNarrow){ wasNarrow = now; render(false); }
  }, 140);
});

/* pause ambient motion when the window is hidden */
document.addEventListener("visibilitychange", () => {
  if (document.hidden) document.body.dataset.motion = "paused";
  else applyAnims();
});

/* ============================================================
   EVENTS
   ============================================================ */
document.addEventListener('click', async e=>{
  const t=e.target instanceof Element?e.target:null;if(!t)return;
  const disabled=t.closest('[disabled],[aria-disabled="true"]');if(disabled)return;
  const nav=t.closest('[data-page]');if(nav){e.preventDefault();go(nav.dataset.page);return;}
  const goEl=t.closest('[data-go]');if(goEl){closeLayer();go(goEl.dataset.go);return;}
  if(t.closest('[data-close]')||t===$('#scrim')){closeLayer();return;}
  const con=t.closest('[data-connect]');if(con){closeLayer();return connect(con.dataset.connect);}
  if(t.closest('[data-disconnect]')){closeLayer();return disconnect();}
  if(t.closest('#dial'))return toggleConn();
  if(t.closest('#dial2'))return S.conn==='on'?disconnect():quickConnect();
  const f=t.closest('[data-fav]');if(f){const n=node(f.dataset.fav);if(!n)return;n.fav=!n.fav;if(n.fav)favorites.add(n.id);else favorites.delete(n.id);writeLocal('wproxy.v4.favorites',JSON.stringify([...favorites]));if(openLayer===$('#sheet'))openDetail(n.id);render(false);return;}
  const detail=t.closest('[data-open]');if(detail){openDetail(detail.dataset.open);return;}
  const tab=t.closest('[data-tab]');if(tab){S.tab=tab.dataset.tab;render(false);return;}
  const view=t.closest('[data-view]');if(view){S.view=view.dataset.view;writeLocal('wp.view',S.view);render(false);return;}
  const mode=t.closest('[data-mode]');if(mode)return runAction('Routing applied',()=>changeRouting(['mode',mode.dataset.mode]));
  const theme=t.closest('[data-set-theme]');if(theme){setTheme(theme.dataset.setTheme);return;}
  const pal=t.closest('[data-pal]');if(pal){palRun(Number(pal.dataset.pal));return;}
  const domain=t.closest('[data-del-dom]');if(domain)return runAction('Site removed',()=>changeRouting(['domain','remove',domain.dataset.delDom]));
  const app=t.closest('[data-del-app]');if(app)return runAction('Application removed',()=>changeRouting(['app','remove',app.dataset.delApp]));
  const addApp=t.closest('[data-add-app]');if(addApp){closeLayer();return runAction('Application added',()=>changeRouting(['app','add',addApp.dataset.addApp]));}
  const removal=t.closest('[data-del-sub],[data-remove-node]');
  if(removal){
    const kind=removal.dataset.delSub?'sub':'node';const id=removal.dataset.delSub||removal.dataset.removeNode;
    const item=(kind==='sub'?SUBS:NODES).find(x=>x.id===id);if(!item)return;
    confirmModal({title:`Remove ${kind==='sub'?'subscription':'server'}?`,desc:`<strong>${esc(item.name)}</strong> will be removed.${kind==='sub'?' Its imported servers will also be removed.':''}`,confirmLabel:'Remove',onConfirm:()=>runAction('Removed from library',()=>client.remove(kind,id,S.snapshot))});return;
  }
  const update=t.closest('[data-upd]');if(update)return runAction('Subscription refreshed',async()=>{await client.call('run_ctl',{args:['sub','update',update.dataset.upd]});await client.sync(S.platform);});
  const test=t.closest('[data-test-node]');if(test)return testNode(test.dataset.testNode);
  const sw=t.closest('.sw');if(sw){
    const enabled=sw.getAttribute('aria-checked')!=='true';
    if(sw.id==='swAnims'){S.anims=enabled;writeLocal('wproxy.v4.animations',enabled?'on':'off');applyAnims();sw.setAttribute('aria-checked',String(enabled));return;}
    if(sw.id==='swUpd'){automaticUpdateStarted=true;await runAction(enabled?'Automatic updates enabled':'Automatic updates disabled',()=>client.call('run_ctl',{args:['settings','set','auto_update',String(enabled)]}));if(enabled&&S.autoUpdate)await checkUpdates(true);return;}
    if(sw.id==='swAuth')return runAction('Permission preference saved',async()=>{if(S.platform==='linux')await client.call('set_linux_authorization',{enable:enabled});await client.call('run_ctl',{args:['settings','set','remember_authorization',String(enabled)]});});
  }
  if(t.closest('#testAll'))return testAll();
  if(t.closest('#addServer,#openAdd'))return addServerModal();
  if(t.closest('#addSub')){$('#subName')?.scrollIntoView({block:'center',behavior:'smooth'});$('#subName')?.focus({preventScroll:true});return;}
  if(t.closest('#palBtn'))return palOpen();
  if(t.closest('#themeBtn'))return setTheme(document.documentElement.dataset.theme==='dark'?'light':'dark');
  if(t.closest('#motionBtn'))return toggleMotion();
  if(t.closest('#refreshBtn,#retrySnapshot'))return IS_NATIVE?refreshSnapshot().catch(showSnapshotError):render(false);
  if(t.closest('#updAll'))return runAction('Subscriptions refreshed',async()=>{await client.call('run_ctl',{args:['sub','update']});await client.sync(S.platform);});
  if(t.closest('#chkUpd'))return checkUpdates(false);
  if(t.closest('#healthBtn'))return runAction('HTTPS health check passed',async()=>{const best=await client.ctl(['node','best','--verify','--json','--timeout','3']);if(best.verified!==true)throw new Error('HTTPS verification did not pass.');S.diagnostic=`HTTPS check passed in ${best.latency_ms} ms`;});
  if(t.closest('#saveNode')){
    const name=$('#nName')?.value.trim();const text=$('#nCfg')?.value.trim();if(!text){toast('Paste a connection link or configuration.','i-info');return;}
    return runAction('Server saved',async()=>{await client.call('import_config',{text,name:name||null});await client.sync(S.platform);closeLayer();S.page='servers';});
  }
  if(t.closest('#impFile')){
    if(!IS_NATIVE){toast('File import requires the installed app.','i-info');return;}
    try{const file=await open({multiple:false,directory:false,title:'Import a connection configuration'});if(typeof file==='string')await runAction('Configuration imported',async()=>{await client.call('run_ctl',{args:['node','import',file]});await client.sync(S.platform);closeLayer();S.page='servers';});}
    catch(error){toast(String(error?.message||error),'i-alert');}return;
  }
  if(t.closest('#saveSub')){const name=$('#subName')?.value||'';const url=$('#subUrl')?.value.trim();if(!url){toast('Enter a subscription URL.','i-info');return;}return runAction('Subscription added',async()=>{await client.addSubscription(url,name,S.platform);clearDraft('subName');clearDraft('subUrl');});}
  if(t.closest('#domAdd')){const domain=$('#domIn')?.value.trim();if(!domain)return;return runAction('Site added',async()=>{await changeRouting(['domain','add',domain]);clearDraft('domIn');});}
  if(t.closest('#appAdd,#appBrowse')){try{await chooseApplication(Boolean(t.closest('#appBrowse')));}catch(error){toast(String(error?.message||error),'i-alert');}return;}
  if(t.closest('#clearF,#clearF2')){S.q='';S.source='all';S.engine='all';S.hideDead=false;S.tab='all';render(false);}
});
document.addEventListener('keydown',e=>{
  if((e.key==='Enter'||e.key===' ')&&e.target instanceof Element&&e.target.matches('.sw,[data-page]')){e.preventDefault();e.target.click();}
  if(e.key==='Tab'&&openLayer){
    const elements=$$('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select,[tabindex="0"]',openLayer).filter(el=>el.getClientRects().length);
    if(!elements.length)return;
    if(e.shiftKey&&document.activeElement===elements[0]){e.preventDefault();elements.at(-1).focus();}
    if(!e.shiftKey&&document.activeElement===elements.at(-1)){e.preventDefault();elements[0].focus();}
  }
});
document.addEventListener('input',e=>{if(e.target.id==='appSearch'){const q=e.target.value.toLowerCase();$$('.app-option').forEach(el=>el.hidden=!el.textContent.toLowerCase().includes(q));}});

/* inputs */
document.addEventListener("input", e => {
  const t = e.target;
  if (t.id === "q"){
    S.q = t.value;
    const sel = t.selectionStart;
    render(false);
    const q = $("#q"); if (q){ q.focus(); q.setSelectionRange(sel, sel); }
  }
  if (t.id === "palInput"){ palSel = 0; palBuild(t.value); }
});
document.addEventListener("change", e => {
  const t = e.target;
  if (t.id === "fSource"){ S.source = t.value; render(false); }
  if (t.id === "fEngine"){ S.engine = t.value; render(false); }
  if (t.id === "fSort"){ S.sort = t.value; render(false); }
  if (t.id === "fDead"){ S.hideDead = t.checked; render(false); }
});
document.addEventListener("keydown", e => {
  if (e.key === "Enter" && e.target.id === "domIn"){ e.preventDefault(); $("#domAdd").click(); }
});

/* global keys */
document.addEventListener("keydown", e => {
  const mod = e.metaKey || e.ctrlKey;
  if (mod && e.key.toLowerCase() === "k"){ e.preventDefault(); openLayer === $("#pal") ? closeLayer() : palOpen(); return; }
  if (e.key === "Escape"){ if (openLayer) { e.preventDefault(); closeLayer(); } return; }

  if (openLayer === $("#pal")){
    if (e.key === "ArrowDown"){ e.preventDefault(); palSel = clamp(palSel + 1, 0, palItems.length - 1); palBuild($("#palInput").value); }
    if (e.key === "ArrowUp"){ e.preventDefault(); palSel = clamp(palSel - 1, 0, palItems.length - 1); palBuild($("#palInput").value); }
    if (e.key === "Enter"){ e.preventDefault(); palRun(palSel); }
    return;
  }
  if (openLayer) return;
  if (e.target.matches("input, textarea, select")) return;

  if (mod && e.key.toLowerCase() === "d"){ e.preventDefault(); toggleConn(); return; }
  const n = Number(e.key);
  if (n >= 1 && n <= 5){ go(Object.keys(PAGES)[n-1]); }
});

/* ============================================================
   BOOT
   ============================================================ */
applyTheme();
applyAnims();
$$('#nav a,#tabbar a').forEach(a=>{a.tabIndex=0;a.setAttribute('role','button');a.setAttribute('aria-label',a.textContent.trim());});
if(!IS_NATIVE){const label=document.createElement('span');label.className='preview-label';label.textContent='Design preview';$('#pageSub').after(label);}
$("#kbdHint").textContent = /Mac|iPhone|iPad/i.test(navigator.platform || navigator.userAgent) ? "⌘ K" : "Ctrl K";
if (IS_NATIVE) {
  $('#page').innerHTML='<div class="empty" role="status"><b>Loading WProxy…</b><p>Reading your local server library.</p></div>';
  refreshSnapshot().catch(showSnapshotError);
  window.setInterval(pollStatus,3500);
  window.addEventListener('focus',handleWindowFocus);
} else render(false);
setTimeout(() => $('.mark')?.classList.remove('boot'), 900);
