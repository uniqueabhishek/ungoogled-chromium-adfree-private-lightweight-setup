// Helper for Set-Search-Engine.ps1. Connects to a headless Chromium on the given debugging port,
// uses the browser's own Settings code to make the "google.com" engine the default, then closes the browser.
//   node make-google-default.mjs <port>
// Exit code 0 = Google is now the default.
const port = process.argv[2];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let ver;
for (let i = 0; i < 60 && !ver; i++) {
  try { ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); } catch { await sleep(500); }
}
if (!ver) { console.log('browser did not start'); process.exit(2); }

const ws = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let seq = 0;
const pending = new Map();
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}, sessionId) =>
  new Promise((r) => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params, sessionId })); });

const { result: { targetId } } = await send('Target.createTarget', { url: 'chrome://settings/searchEngines' });
const { result: { sessionId } } = await send('Target.attachToTarget', { targetId, flatten: true });
await sleep(2500);

// setDefaultSearchEngine(id, ChoiceMadeLocation.kSearchSettings = 1, saveGuestChoice = null)
const expression = `new Promise((res) => import('chrome://resources/js/cr.js').then(async (m) => {
  const all = (l) => [...l.actives, ...l.defaults, ...l.others];
  const google = all(await m.sendWithPromise('getSearchEnginesList')).find((e) => e.keyword === 'google.com');
  if (!google) return res('no google.com engine in this profile');
  if (!google.default) chrome.send('setDefaultSearchEngine', [google.id, 1, null]);
  await new Promise((r) => setTimeout(r, 1500));
  res(all(await m.sendWithPromise('getSearchEnginesList')).filter((e) => e.default).map((e) => e.keyword).join());
}, (e) => res('error ' + e)))`;
const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
const result = r.result?.result?.value ?? JSON.stringify(r);

await send('Browser.close');
ws.close();
console.log(result === 'google.com' ? 'Google is default' : `FAILED: ${result}`);
process.exit(result === 'google.com' ? 0 : 1);
