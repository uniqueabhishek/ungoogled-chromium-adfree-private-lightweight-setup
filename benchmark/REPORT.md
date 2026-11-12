# Chrome vs Ungoogled Chromium — benchmark report (2026-10-22)

**Machine:** a mid-range Windows 11 laptop (4-core Intel CPU, 16 GB RAM), on AC power, Balanced plan.
**Browsers:** Google Chrome 143.0.7499.110 and Ungoogled Chromium 153.0.8010.52.
**Method:** 4 rounds in A-B-B-A order (Chrome, Ungoogled, Ungoogled, Chrome). Every round starts with a brand-new profile. CPU time and private RAM are summed across all of that browser's processes and sampled about once a second. Network traffic comes from Chrome's own NetLog (`--log-net-log`). Re-run it on your own PC with `node bench.mjs` (after `pnpm install`).

Values below are the averages of the two rounds for each browser.

| Test | Chrome | Ungoogled | Difference |
|---|---|---|---|
| Startup CPU burst (first 30 s) | 12.9 CPU-s | 4.7 CPU-s | Ungoogled 63% less |
| Cold start to first page ready | 2.2 s (1.2 / 3.2) | 1.2 s | Ungoogled faster |
| Warm start | 1.5 s | 1.0 s | Ungoogled faster |
| Idle CPU (150 s, start page open) | 1.7% of one core | 0.95% of one core | Ungoogled ~45% less |
| Idle RAM (average) | 251 MB | 210 MB | Ungoogled 16% less |
| Background network in the first 3 min (no user action) | ~54 requests, 18 Google hosts, ~28.5 MB downloaded | 0 requests, 0 bytes | Ungoogled sends nothing |
| Speedometer 3.1 (higher is better) | 8.05 (7.2 / 8.9) | 8.70 (8.56 / 8.83) | Ungoogled +8% (Chrome varied a lot between rounds) |
| Canvas graphics stress, 30 s | 40 fps, 31 CPU-s | 40 fps, 30 CPU-s | Tie |
| 8 real sites in tabs: peak RAM | 4.2 GB | 2.9 GB | Ungoogled ~30% less |
| 8 real sites in tabs: process count | 91–130 | 44–51 | Chrome about 2x more |
| 8 tabs left open, CPU over 30 s | 159% of one core | 153% of one core | About the same |
| YouTube video, 60 s | ~26% of one core, 0 frames dropped | ~25–30% of one core, ≤4 frames dropped | Tie |
| Profile size on disk after the tests | 241–246 MB | 86–87 MB | Ungoogled ~65% smaller |

## Google hosts Chrome contacted while idle
accounts.google.com, android.clients.google.com, chromewebstore.googleapis.com, clients2.google.com, clients2.googleusercontent.com, clientservices.googleapis.com, mtalk.google.com, ogads-pa.clients6.google.com, optimizationguide-pa.googleapis.com, play.google.com, redirector.gvt1.com, *.gvt1.com (component downloads), safebrowsingohttpgateway.googleapis.com, update.googleapis.com, www.google.com, www.googleapis.com, www.gstatic.com, beacons.gcp.gvt2.com

Chrome also runs an `OnDeviceModelService` process (about 134 MB, Google's on-device AI). Ungoogled does not have it.

## Caveats
- **Versions differ:** the installed Chrome is stuck on 143 because this PC has no Google updater service. Ungoogled is on 153. Part of the speed difference may come from the newer engine.
- **Fresh profiles were used:** a real Chrome profile that is signed in and syncing, with extensions, will produce more background traffic than measured here.
- **Background load:** the user's own Chrome was running during all rounds. This added the same background load to both browsers.
- **Noisy sites:** ndtv.com timed out in 3 of 4 rounds, so the tab load times are noisy and were left out of the table.
