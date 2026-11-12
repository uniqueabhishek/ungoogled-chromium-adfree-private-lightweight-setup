import puppeteer from 'puppeteer-core';
import { spawn, execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(DIR, 'results');
fs.mkdirSync(OUT, { recursive: true });
const BROWSERS = {
  chrome: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  ungoogled: `${process.env.LOCALAPPDATA}\\Chromium\\Application\\chrome.exe`,
};
const QUICK = process.env.QUICK === '1';
const ORDER = (process.env.ORDER || 'chrome,ungoogled,ungoogled,chrome').split(',');
const IDLE_SECS = QUICK ? 20 : 180;
const SITES = [
  'https://en.wikipedia.org/wiki/India',
  'https://www.youtube.com/',
  'https://www.amazon.in/',
  'https://www.reddit.com/r/technology/',
  'https://github.com/trending',
  'https://www.bbc.com/news',
  'https://www.ndtv.com/',
  'https://stackoverflow.com/questions',
];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const MB = (b) => Math.round(b / 1048576);

class Sampler {
  constructor(udd) {
    this.last = new Map();
    this.samples = [];
    this.lastProcs = [];
    this.ps = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(DIR, 'sampler.ps1'), udd]);
    let buf = '';
    this.ps.stdout.on('data', (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (line) this.onLine(line);
      }
    });
  }
  onLine(line) {
    let o;
    try { o = JSON.parse(line); } catch { return; }
    let procs = o.procs || [];
    if (!Array.isArray(procs)) procs = [procs];
    // a failed WMI query also returns nothing; only trust "no processes" when it repeats
    if (procs.length === 0 && this.samples.length && this.samples.at(-1).n > 0 && !this.emptyOnce) { this.emptyOnce = true; return; }
    this.emptyOnce = false;
    let ws = 0, priv = 0;
    for (const p of procs) { this.last.set(p.pid, { cpu: p.cpu, type: p.type }); ws += p.ws; priv += p.priv; }
    this.lastProcs = procs;
    this.samples.push({ t: Date.now(), ws, priv, n: procs.length, cpu: this.totalCpu() });
  }
  totalCpu() { let s = 0; for (const v of this.last.values()) s += v.cpu; return s; }
  async fresh() {
    const n = this.samples.length;
    while (this.samples.length === n) await sleep(50);
    return { t: Date.now(), cpu: this.totalCpu(), idx: this.samples.length };
  }
  window(m, end) {
    const ss = this.samples.slice(m.idx - 1, end.idx).filter((s) => s.n > 0);
    const secs = (end.t - m.t) / 1000;
    const cpuSec = end.cpu - m.cpu;
    return {
      secs: +secs.toFixed(1),
      cpuSec: +cpuSec.toFixed(2),
      avgCorePct: +((cpuSec / secs) * 100).toFixed(1),
      peakRamMB: MB(Math.max(...ss.map((s) => s.priv))),
      avgRamMB: MB(ss.reduce((a, s) => a + s.priv, 0) / ss.length),
      peakWorkingSetMB: MB(Math.max(...ss.map((s) => s.ws))),
      maxProcs: Math.max(...ss.map((s) => s.n)),
    };
  }
  ramByType() {
    const m = {};
    for (const p of this.lastProcs) m[p.type] = (m[p.type] || 0) + p.priv;
    return Object.fromEntries(Object.entries(m).map(([k, v]) => [k, MB(v)]));
  }
  stop() { this.ps.kill(); }
}

async function waitCdp(port, timeout = 30000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    try { const r = await fetch(`http://127.0.0.1:${port}/json/version`); if (r.ok) return await r.json(); } catch {}
    await sleep(25);
  }
  throw new Error('CDP timeout');
}

async function startBrowser(name, udd, port, extra = []) {
  const sampler = new Sampler(udd);
  await sleep(1500);
  const args = [
    `--user-data-dir=${udd}`, `--remote-debugging-port=${port}`, '--no-first-run', '--no-default-browser-check',
    '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-timer-throttling',
    '--autoplay-policy=no-user-gesture-required', '--window-size=1280,800', '--window-position=40,40', ...extra,
  ];
  const t0 = performance.now();
  const tWall = Date.now();
  const proc = spawn(BROWSERS[name], args, { stdio: 'ignore' });
  const ver = await waitCdp(port);
  const cdpMs = performance.now() - t0;
  const browser = await puppeteer.connect({ browserURL: `http://127.0.0.1:${port}`, defaultViewport: null, protocolTimeout: 900000 });
  let page;
  for (let i = 0; i < 400 && !page; i++) { page = (await browser.pages())[0]; if (!page) await sleep(25); }
  await page.waitForFunction(() => document.readyState === 'complete', { timeout: 30000, polling: 25 }).catch(() => {});
  const readyMs = performance.now() - t0;
  return { sampler, proc, browser, page, tWall, ver, startup: { cdpMs: Math.round(cdpMs), firstPageReadyMs: Math.round(readyMs), startUrl: page.url() } };
}

async function stopBrowser(b) {
  try { await b.browser.close(); } catch {}
  for (let i = 0; i < 200 && b.proc.exitCode === null; i++) await sleep(100);
  for (let i = 0; i < 60; i++) { await b.sampler.fresh(); if (b.sampler.lastProcs.length === 0) break; }
  if (b.sampler.lastProcs.length) { try { execSync(`taskkill /T /F /PID ${b.proc.pid}`); } catch {} }
  b.sampler.stop();
}

function parseNetlog(file) {
  let txt;
  try { txt = fs.readFileSync(file, 'utf8').trim(); } catch (e) { return { error: e.message }; }
  let j;
  try { j = JSON.parse(txt); } catch {
    txt = txt.replace(/,\s*$/, '');
    if (!txt.endsWith(']}')) txt += ']}';
    try { j = JSON.parse(txt); } catch (e) { return { error: e.message }; }
  }
  const types = Object.fromEntries(Object.entries(j.constants.logEventTypes).map(([k, v]) => [v, k]));
  const reqHosts = {}, seenHosts = new Set();
  let requests = 0, bytesIn = 0, bytesOut = 0;
  const norm = (h) => String(h).replace(/^[a-z]+:\/\//, '').replace(/[:\/].*$/, '').replace(/^\[|\]$/g, '');
  const local = (h) => !h || /^(localhost|127\.|::1|0\.0\.0\.0)/.test(h);
  for (const e of j.events || []) {
    const t = types[e.type];
    const p = e.params || {};
    if (t === 'URL_REQUEST_START_JOB' && p.url) {
      try { const h = new URL(p.url).hostname; if (!local(h)) { requests++; reqHosts[h] = (reqHosts[h] || 0) + 1; } } catch {}
    }
    for (const k of ['host', 'server_id']) if (typeof p[k] === 'string') { const h = norm(p[k]); if (!local(h) && /[a-z]/i.test(h)) seenHosts.add(h); }
    if (typeof p.byte_count === 'number') {
      if (/BYTES_RECEIVED|PACKET_RECEIVED/.test(t)) bytesIn += p.byte_count;
      else if (/BYTES_SENT|PACKET_SENT/.test(t)) bytesOut += p.byte_count;
    }
  }
  for (const h of Object.keys(reqHosts)) seenHosts.add(h);
  const all = [...seenHosts].sort();
  return {
    requests, reqHosts, allHosts: all,
    googleHosts: all.filter((h) => /google|gstatic|gvt\d|googleapis|youtube|ytimg|doubleclick|1e100/.test(h)),
    bytesIn, bytesOut,
  };
}

function dirSize(d) {
  let s = 0;
  try { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); s += e.isDirectory() ? dirSize(p) : (() => { try { return fs.statSync(p).size; } catch { return 0; } })(); } } catch {}
  return s;
}

async function testGraphics(b) {
  const p = await b.browser.newPage();
  await p.bringToFront();
  await p.goto(pathToFileURL(path.join(DIR, 'gfx.html')).href, { waitUntil: 'load' });
  await sleep(3000);
  const gpu = await p.evaluate(() => window.gpu);
  const m = await b.sampler.fresh();
  await p.evaluate(() => window.startTest());
  await sleep(QUICK ? 5000 : 30000);
  const r = await p.evaluate(() => window.stopTest());
  const end = await b.sampler.fresh();
  await p.close();
  return { gpu, fps: +(r.frames / r.secs).toFixed(1), ...b.sampler.window(m, end) };
}

async function testSpeedometer(b) {
  const p = await b.browser.newPage();
  await p.bringToFront();
  await p.goto('https://browserbench.org/Speedometer3.1/?startAutomatically=true', { waitUntil: 'load', timeout: 60000 });
  const m = await b.sampler.fresh();
  const t0 = Date.now();
  await p.waitForFunction(() => { const e = document.querySelector('#result-number'); return e && !isNaN(parseFloat(e.textContent)); }, { timeout: 900000, polling: 2000 });
  const end = await b.sampler.fresh();
  const score = await p.evaluate(() => ({ score: parseFloat(document.querySelector('#result-number').textContent), confidence: document.querySelector('#confidence-number')?.textContent?.trim() }));
  await p.close();
  return { ...score, runSecs: Math.round((Date.now() - t0) / 1000), ...b.sampler.window(m, end) };
}

async function testTabs(b) {
  const sites = QUICK ? SITES.slice(0, 2) : SITES;
  const m = await b.sampler.fresh();
  const pages = [], loads = {};
  for (const url of sites) {
    const p = await b.browser.newPage();
    pages.push(p);
    const t0 = performance.now();
    try { await p.goto(url, { waitUntil: 'load', timeout: 45000 }); loads[url] = Math.round(performance.now() - t0); }
    catch { loads[url] = 'timeout(45s)'; }
  }
  const loadEnd = await b.sampler.fresh();
  await sleep(QUICK ? 5000 : 30000);
  const settleEnd = await b.sampler.fresh();
  const ramByType = b.sampler.ramByType();
  const totalLoadMs = Object.values(loads).reduce((a, v) => a + (typeof v === 'number' ? v : 45000), 0);
  for (const p of pages) await p.close().catch(() => {});
  return { loads, totalLoadMs, loading: b.sampler.window(m, loadEnd), settled30s: b.sampler.window(loadEnd, settleEnd), ramByType };
}

async function testVideo(b) {
  const p = await b.browser.newPage();
  await p.bringToFront();
  await p.goto('https://www.youtube.com/watch?v=aqz-KE-bpKQ', { waitUntil: 'load', timeout: 60000 });
  await p.waitForSelector('video', { timeout: 30000 });
  await p.evaluate(() => { const v = document.querySelector('video'); v.muted = true; v.play(); });
  await sleep(8000);
  const q = () => p.evaluate(() => { const v = document.querySelector('video'); const k = v.getVideoPlaybackQuality(); return { t: v.currentTime, dropped: k.droppedVideoFrames, total: k.totalVideoFrames, w: v.videoWidth, h: v.videoHeight, ad: !!document.querySelector('.ad-showing') }; });
  const q0 = await q();
  const m = await b.sampler.fresh();
  await sleep(QUICK ? 10000 : 60000);
  const end = await b.sampler.fresh();
  const q1 = await q();
  await p.close();
  return { resolution: `${q1.w}x${q1.h}`, secondsPlayed: +(q1.t - q0.t).toFixed(1), framesShown: q1.total - q0.total, framesDropped: q1.dropped - q0.dropped, adSeen: q0.ad || q1.ad, ...b.sampler.window(m, end) };
}

const resultsFile = path.join(OUT, QUICK ? 'results-quick.json' : 'results.json');
const results = [];
for (let r = 0; r < ORDER.length; r++) {
  const name = ORDER[r];
  const udd = path.join(DIR, 'profiles', `${name}-r${r}`);
  fs.rmSync(udd, { recursive: true, force: true });
  const res = { round: r, browser: name };
  log(`=== round ${r}: ${name}`);

  // Session A: cold start on a brand-new profile, then sit idle on the start page while logging all network traffic
  const netlog = path.join(OUT, `netlog-${name}-r${r}.json`);
  const A = await startBrowser(name, udd, 9300 + r, [`--log-net-log=${netlog}`, '--net-log-capture-mode=Default']);
  res.version = A.ver.Browser;
  res.coldStart = A.startup;
  log('cold start', A.startup);
  while (Date.now() - A.tWall < 30000) await sleep(200);
  const m30 = await A.sampler.fresh();
  res.startupBurst30s = { cpuSec: +m30.cpu.toFixed(2), ramMB: MB(A.sampler.samples.at(-1).priv) };
  while (Date.now() - A.tWall < IDLE_SECS * 1000) await sleep(500);
  const mIdle = await A.sampler.fresh();
  res.idle = A.sampler.window(m30, mIdle);
  res.idle.ramByType = A.sampler.ramByType();
  log('idle', res.idle);
  await stopBrowser(A);
  res.network = parseNetlog(netlog);
  log('network', { requests: res.network.requests, hosts: res.network.allHosts.length, google: res.network.googleHosts.length });
  await sleep(5000);

  // Session B: warm start on the same profile, then the workload tests
  const B = await startBrowser(name, udd, 9400 + r);
  res.warmStart = B.startup;
  log('warm start', B.startup);
  await sleep(5000);
  try { res.graphics = await testGraphics(B); log('graphics', res.graphics); } catch (e) { res.graphics = { error: e.message }; log('graphics ERR', e.message); }
  if (!QUICK) { try { res.speedometer = await testSpeedometer(B); log('speedometer', res.speedometer); } catch (e) { res.speedometer = { error: e.message }; log('speedo ERR', e.message); } }
  try { res.tabs = await testTabs(B); log('tabs', res.tabs); } catch (e) { res.tabs = { error: e.message }; log('tabs ERR', e.message); }
  try { res.video = await testVideo(B); log('video', res.video); } catch (e) { res.video = { error: e.message }; log('video ERR', e.message); }
  await stopBrowser(B);
  res.profileSizeMB = MB(dirSize(udd));
  results.push(res);
  fs.writeFileSync(resultsFile, JSON.stringify(results, null, 2));
  log('round done; profile MB', res.profileSizeMB);
  if (r < ORDER.length - 1) await sleep(QUICK ? 3000 : 30000);
}
log('ALL DONE');
