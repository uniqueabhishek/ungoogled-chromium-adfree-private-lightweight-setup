# Ungoogled Chromium — Complete Setup Guide

This guide explains every change the setup makes to Ungoogled Chromium on Windows, and how to do each one by hand. The result is fast, quiet and ad-free, with search in the address bar, and optionally your Chrome data moved across.

- **Tested with:** Ungoogled Chromium 155 (installed with winget), October 2026
- **Works on:** Windows 10 / 11. `install.ps1` and `uninstall.ps1` run in the built-in Windows PowerShell; the scripts in `extras/` need **PowerShell 7** (`pwsh`).

---

## Contents

1. [Quick start (the short way)](#1-quick-start-the-short-way)
2. [Why Ungoogled Chromium](#2-why-ungoogled-chromium)
3. [Install and automatic updates](#3-install-and-automatic-updates)
4. [Ad blocking, three layers](#4-ad-blocking-three-layers)
5. [Installing extensions from the Chrome Web Store](#5-installing-extensions-from-the-chrome-web-store)
6. [Search in the address bar](#6-search-in-the-address-bar)
7. [New tab page shortcuts](#7-new-tab-page-shortcuts)
8. [Moving profiles over from Google Chrome](#8-moving-profiles-over-from-google-chrome)
9. [Passwords, with Bitwarden](#9-passwords-with-bitwarden)
10. [Extensions to reinstall](#10-extensions-to-reinstall)
11. [What does not work, and why](#11-what-does-not-work-and-why)
12. [Troubleshooting](#12-troubleshooting)
13. [Files in this folder](#13-files-in-this-folder)
14. [Undoing changes](#14-undoing-changes)

---

## 1. Quick start (the short way)

The script does everything that can be automated. The rest is about 2 minutes of clicking.

1. **Close Ungoogled Chromium** if it is already installed. Also close its icon near the clock.
2. **Open PowerShell** (Start → type *PowerShell*) and run:
   ```powershell
   irm https://raw.githubusercontent.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup/main/install.ps1 | iex
   ```
3. **The script does these steps:**
   - Installs Ungoogled Chromium with winget, if it is missing.
   - Makes Google, with live suggestions, the search engine for new profiles.
   - Adds a scheduled task that keeps the browser updated.
   - Turns on AdGuard ad-blocking DNS.
   - Turns on the flag that lets extensions install from the Chrome Web Store.
   - Sets policies: search suggestions, HTTPS first, page preloading, and uBlock Origin Lite's "Complete" mode with the extra filter lists.
   - Downloads the "Chromium Web Store" helper extension.
   - Opens the browser on the uBlock Origin Lite install page.
4. **Then do these clicks by hand** (each one is explained in detail further down):
   - [ ] Click **Add extension** for uBlock Origin Lite → [section 4.1](#41-layer-1--ublock-origin-lite-blocks-ads-on-the-page)
   - [ ] Load the **Chromium Web Store** folder with **Load unpacked** → [section 5](#5-installing-extensions-from-the-chrome-web-store)
   - [ ] Pin uBlock Origin Lite and turn on **Allow User Scripts** → [section 4.2](#42-ublock-origin-lite-settings-the-important-part)
   - [ ] *(Optional, only when moving from Chrome)* import profiles and passwords → [sections 8](#8-moving-profiles-over-from-google-chrome) and [9](#9-passwords-with-bitwarden)

> **Tip:** the script is safe to run again. It backs up every browser file it changes as `<file>.before-setup-<date>`.

---

## 2. Why Ungoogled Chromium

Ungoogled Chromium is Google Chrome's engine with every Google service removed. Websites look and work exactly the same. What disappears is Google sign-in, sync, Safe Browsing calls, the AI model running in the background, and constant "phone home" traffic.

A side-by-side test was run on a mid-range Windows 11 laptop (16 GB RAM). It used 4 rounds, a fresh profile each time, and the same steps in both browsers. The full report is in [benchmark/REPORT.md](../benchmark/REPORT.md).

| Test | Google Chrome | Ungoogled Chromium |
|---|---|---|
| CPU used in the first 30 s after start | 12.9 CPU-seconds | **4.7** (63% less) |
| Start-up time (cold / warm) | 2.2 s / 1.5 s | **1.2 s / 1.0 s** |
| Idle CPU | 1.7% of one core | **0.95%** |
| Idle RAM | 251 MB | **210 MB** |
| Background traffic, 3 min, nobody touching it | 54 requests to 18 Google servers, ~28.5 MB | **0 requests, 0 bytes** |
| 8 real websites open: peak RAM | 4.2 GB | **2.9 GB** |
| 8 real websites open: number of processes | 91–130 | **44–51** |
| Profile size on disk | ~245 MB | **~87 MB** |
| Speedometer, graphics, YouTube playback | about the same | about the same |

**In short:** heavy work (scripts, video) costs the same in both browsers. Ungoogled wastes much less in the background and sends nothing to Google.

---

## 3. Install and automatic updates

### 3.1 Install

Ungoogled Chromium is installed for the current user only, in `%LOCALAPPDATA%\Chromium\Application`. No admin rights are needed.

```powershell
winget install --id eloston.ungoogled-chromium -e
```

### 3.2 Automatic updates

Ungoogled Chromium has **no built-in updater**. Chrome's updater is a Google service, so it is removed. A new browser version comes out about every 4 weeks, and staying current matters for security.

**What was set up:**

- **An update script** at `%LOCALAPPDATA%\Chromium\update-chromium.ps1`. It runs:
  ```powershell
  winget upgrade --id eloston.ungoogled-chromium -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
  ```
  It writes what happened to `winget-upgrade.log` in the same folder, and puts the Google search default for new profiles (`initial_preferences`) back if an update removed it.
- **A scheduled task called "Update Ungoogled Chromium"** runs that script:
  - every **Wednesday at 1 pm**
  - at every **Windows sign-in**
  - It runs hidden with Windows PowerShell. If the PC was off at 1 pm, it runs the next time it can.

`install.ps1` creates both of these. To check or update by hand:

```powershell
Get-ScheduledTask -TaskName 'Update Ungoogled Chromium'      # is the task there?
Get-Content "$env:LOCALAPPDATA\Chromium\winget-upgrade.log" -Tail 20   # what did it do?
winget upgrade --id eloston.ungoogled-chromium -e             # update right now
```

> **Note:** an update installs while the browser is closed. If it was open, the new version is used from the next start.

---

## 4. Ad blocking, three layers

This is the favourite part of the setup: **no ads on websites or YouTube**, for free, with no change to the browser's code.

**Why not the classic uBlock Origin?** Chromium 139 and later removed support for the old extension format (Manifest V2) it needs. Bringing it back would mean rebuilding the browser from source: about 100 GB of disk and 6–12 hours, repeated every 4 weeks. Not worth it. The three layers below get about 95% of the same result.

| Layer | What it does | How it is set |
|---|---|---|
| **1. uBlock Origin Lite** in "Complete" mode | Blocks ads, trackers and clutter inside pages, including YouTube | Extension + settings |
| **2. AdGuard DNS** inside the browser | Stops ad and tracker domains from loading at all; uses no CPU | One browser setting |
| **3. Chromium Web Store** | Blocks nothing itself; keeps uBlock Origin Lite and other extensions updated | Extension |

### 4.1 Layer 1 — uBlock Origin Lite (blocks ads on the page)

**First, the install flag.** This must be on, otherwise the browser cannot install anything from the store.

1. Open `chrome://flags/#extension-mime-request-handling`.
2. Set **"Handling of extension MIME type requests"** to **Always prompt for install**.
3. Click **Relaunch**.

(`install.ps1` already sets this flag.)

**Then install uBlock Origin Lite.** Paste this into the address bar and click **Add extension**. Change `155.0` to your browser's main version number (see `chrome://version`):

```
https://clients2.google.com/service/update2/crx?response=redirect&prodversion=155.0&acceptformat=crx2,crx3&x=id%3Dddkjiahejlhfcafbddmgiahcphecmpfh%26uc
```

Once the Chromium Web Store helper is installed ([section 5](#5-installing-extensions-from-the-chrome-web-store)), you can instead open its store page and click **Add to Chromium**:
https://chromewebstore.google.com/detail/ddkjiahejlhfcafbddmgiahcphecmpfh

### 4.2 uBlock Origin Lite settings (the important part)

Without these settings, uBlock Origin Lite only runs in its basic mode and misses a lot.

> **`install.ps1` sets B and C for you** through a browser policy (`HKCU\Software\Policies\Chromium\3rdparty\extensions\ddkjiahejlhfcafbddmgiahcphecmpfh\policy`), which uBlock Origin Lite reads as its "managed" settings. Only part A is left to click. The tables below show what it sets, or how to do it by hand.

**A. On the extension's details page** (`chrome://extensions` → uBlock Origin Lite → **Details**):

| Switch | Set to | Why |
|---|---|---|
| **Pin to toolbar** | On | Lets you turn blocking down for one site in one click |
| **Allow User Scripts** | On | Lets it use extra blocking tricks on hard sites such as YouTube. The warning is generic browser text; this extension is from the original uBlock Origin developer |
| **Allow in Incognito** | On | Otherwise ads come back in Incognito windows |
| Allow access to file URLs, Collect errors | Leave off | No effect on ad blocking |

**B. In the extension's options** (click **Extension options** on the same page, or the uBlock icon → ⚙):

1. **Settings tab → Default filtering mode → Complete** (the rightmost option).
2. Leave the **Behavior** boxes as they are. Untick **Developer mode** unless you write your own filters.

**C. Filter lists tab.** Tick these on top of the defaults:

| Section | Tick | Notes |
|---|---|---|
| **Ads** | The list inside (click **>** to open it) | Biggest boost against ads |
| **Privacy** | Both lists | One strips tracking codes from links; one blocks sites probing your home network |
| **Malware and security** | All of them | Usually on by default |
| **Annoyances** | Cookie Notices, Notifications, Other Annoyances, Overlay Notices | Removes cookie banners and pop-ups |
| **Regions** | Your own country | Local ad networks. The script picks it from the country set in Windows (Settings → Time & language → Region) |

**Leave unticked:**

- **AI / Social / Chat widgets.** These hide useful things such as a site's support chat and Share buttons.
- **Miscellaneous / Experimental.** These can break sites.

**Test it:** open a site that had ads, or YouTube, and press **Ctrl + Shift + R**. You should see **no ads**.

### 4.3 Layer 2 — AdGuard ad-blocking DNS

The browser looks up website names through AdGuard's free encrypted DNS. AdGuard refuses to look up known ad and tracker domains, so those never load. Only this browser is affected, not the rest of Windows.

**By hand:**

1. Open `chrome://settings/security`.
2. Turn on **Use secure DNS**.
3. Choose **Custom** (or "Add custom DNS service provider") and paste:
   ```
   https://dns.adguard-dns.com/dns-query
   ```

**By script:** `install.ps1` writes this into the browser's `Local State` file, with the browser closed:

```json
"dns_over_https": { "mode": "secure", "templates": "https://dns.adguard-dns.com/dns-query" }
```

- **Privacy note:** AdGuard sees which website names you look up, not the pages themselves.
- **If a site won't load:** this layer is the usual cause. Turn off **Use secure DNS** for a moment to check.

### 4.4 Layer 3 — Chromium Web Store

See [section 5](#5-installing-extensions-from-the-chrome-web-store). It also tells you when uBlock Origin Lite has an update.

### 4.5 When a site breaks

- **Page looks broken or a button doesn't work:** click the uBlock icon and drag its slider down to **Basic**, or off, **for that site only**.
- **Page doesn't load at all:** turn off **Use secure DNS** (layer 2) at `chrome://settings/security`. If that fixes it, turn it back on afterwards.

---

## 5. Installing extensions from the Chrome Web Store

Out of the box, Ungoogled Chromium cannot install from the Chrome Web Store. The "Add to Chrome" button is missing, and installed extensions never update. The free open-source helper **Chromium Web Store** ([github.com/NeverDecaf/chromium-web-store](https://github.com/NeverDecaf/chromium-web-store)) brings back the **Add to Chromium** button and automatic updates.

**Dragging the `.crx` file onto the extensions page fails** in Ungoogled Chromium. Load it unpacked instead:

1. **Get the files.** Either:
   - **Let the script do it:** `install.ps1` downloads the latest release and unpacks it to
     `%LOCALAPPDATA%\Chromium\Unpacked Extensions\Chromium Web Store`, or
   - **By hand:** download `Chromium.Web.Store.crx` from the project's **Releases** page. Make the folder above, and extract the `.crx` into it with `tar -xf Chromium.Web.Store.crx -C "<folder>"`. A `.crx` is a zip file with a small header, and Windows' `tar` reads it fine.
2. Open `chrome://extensions`.
3. Turn on **Developer mode** (top right).
4. Click **Load unpacked** (top left). A Windows folder window opens.
5. **Click the path bar at the top of that window**, paste the folder path, press **Enter**, then click **Select Folder**.

   > **Common mistake:** pasting the path into the *browser's* address bar. That only shows the files as a web page and installs nothing.
6. **Chromium Web Store** now appears in the list.

- **Don't move or delete that folder.** The extension runs from it.
- **Developer mode stays on.** That is normal for an unpacked extension; at most you will sometimes see a reminder banner.

After this, any Chrome Web Store page shows **Add to Chromium**.

---

## 6. Search in the address bar

Ungoogled Chromium starts with the search engine set to **"No Search"**. The address bar then only accepts web addresses, with no searching and no suggestions. **There is no built-in Google entry**: slot 1 of the built-in list is "No Search". A Google entry added by hand in Settings never gets live suggestions.

**New profiles (what `install.ps1` does):** it places an `initial_preferences` file next to `chrome.exe`. The browser reads it whenever a profile is created, and that profile starts with Google, with live suggestions, as its default. A copy is kept at `%LOCALAPPDATA%\Chromium\initial_preferences`; the update task puts it back if an update removes it.

**Profiles that already existed** before the install keep their engine. For those, use the scripts below.

**A. Search engine and shortcuts:** run `extras\Set-Search-Engine.ps1` (needs PowerShell 7, `uv` and `node`). It closes the browser, then for each profile it:

1. Adds **Google** with live suggestions and makes it the default.
2. Adds the shortcuts `yt`, `gh` and `maps`. Typing `yt cats` searches YouTube directly.
3. Adds `@bookmarks`, `@history` and `@tabs` where they are missing.
4. Reopens the browser with all tabs restored.

Backups are saved as `<file>.before-search-<date>` in each profile folder.

**B. Suggestions, HTTPS and preloading:** `install.ps1` sets these as browser policies, which apply to all profiles:

- **Autocomplete searches and URLs** is on.
- **Typed addresses go to `https://` first.** The browser warns only for public sites that have no HTTPS.
- **Likely pages are preloaded**, so typed addresses open faster.

Because of these policies, the browser menu shows "Managed by your organization". `uninstall.ps1` removes them.

**Why not a policy for the search engine?** Chromium blocks the search engine and site-search policies (`DefaultSearchProvider*`, `SiteSearchSettings`) on PCs that are not joined to a company domain. Each profile's search list is also protected by an encrypted checksum. `extras/set_search_engine.py` explains how the script handles both for existing profiles.

**Check it:**

- Type `weather` in the address bar. Google suggestions should appear as you type.
- Type `yt cats` and press Enter. YouTube search results should open.

**Address bar tips:**

- **Ctrl+Enter** turns `amazon` into `www.amazon.com`.
- **Shift+Delete** removes a bad suggestion from the dropdown.
- **Tab to search:** after you visit a site once (YouTube, Amazon…), type its name and press **Tab** to search inside it. This needs `chrome://flags/#disable-search-engine-collection` left at **Disabled** (the default).
- `chrome://flags/#omnibox-autocomplete-filtering` must stay at **Default**. Any other value hides history or search suggestions.

**What will never come back:** Google Lens, AI Mode, Gemini and the Google account cards in the address bar. These are Google services, which this browser removes.

---

## 7. New tab page shortcuts

The round shortcut tiles on the new tab page can be **seen** in Ungoogled Chromium, but the **"Add shortcut" button is hidden**. The browser only shows Chrome's full new tab page when the search engine is Google. Ungoogled also deliberately breaks that Google check, so the button can stay hidden even with Google selected. A profile can hold at most **10** shortcuts; at 10, even real Chrome hides the button.

**Fix: the `extras\Edit-Shortcuts.ps1` script** (PowerShell 7). It edits the shortcut list directly. Close the browser before adding or removing.

```powershell
# List every profile and its shortcuts (safe while the browser is open)
.\extras\Edit-Shortcuts.ps1

# Add a shortcut to a profile (use the name shown in the profile picker, or the folder name)
.\extras\Edit-Shortcuts.ps1 -Profile "abc@gmail.com" -Add GitHub -Url https://github.com/

# Remove one by its title or address
.\extras\Edit-Shortcuts.ps1 -Profile "Profile 6" -Remove GitHub
```

- Before every change it saves `Preferences.before-shortcuts` in that profile's folder.
- **To remove a tile by hand:** hover over it on the new tab page → **⋮ → Remove**.
- **Need more than 10?** A new-tab extension such as **LiteDial** (up to 30 tiles) replaces the page entirely. You set your tiles up again inside it.

---

## 8. Moving profiles over from Google Chrome

Skip this section on a PC that never had Chrome.

### 8.1 What comes across and what doesn't

| Comes across | Does not come across |
|---|---|
| Bookmarks and their icons | Website logins (sign in once per site; Chrome locks its cookies) |
| Full history and typed-address suggestions | Saved passwords → use Bitwarden, [section 9](#9-passwords-with-bitwarden) |
| New tab shortcuts | Chrome settings and site permissions (each profile starts with this setup's settings instead) |
| Open tabs | Saved addresses and payment cards |
| Profile names and avatars | Extensions (reinstall them, [section 10](#10-extensions-to-reinstall)) |
| | Google account sign-in, sync, and the Google profile photo ([section 11](#11-what-does-not-work-and-why)) |

### 8.2 Import every Chrome profile in one go

1. **Run the install command first** ([section 1](#1-quick-start-the-short-way)).
2. **Close both Google Chrome and Ungoogled Chromium**, including their icons near the clock.
3. Paste this into PowerShell:
   ```powershell
   irm https://raw.githubusercontent.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup/main/import-chrome.ps1 | iex
   ```

**What it does:**

- **Finds every Chrome profile folder** (`Default`, `Profile 1`, `Profile 2`, …). It reads the folders themselves, not only Chrome's own profile list, which can miss profiles.
- **Makes a matching Ungoogled Chromium profile with Google search.** Google can only be set on a brand-new profile at the browser's first start, so for each missing profile the script starts the browser once, hidden, and moves the new profile into place. A profile that already exists (for example the one you set up with the install) keeps its settings and extensions, and Chrome's data is added to it.
- **Copies the data**, skipping caches, extension folders and the files Chrome locks to itself (passwords, cookies).
- **Names each profile after its Google address** (for example `abc@gmail.com`), or its Chrome name, and keeps the avatar.
- **Opens a profile picker** at start-up when there is more than one profile.
- **Never deletes anything.** Chrome is not touched. Anything it replaces in Ungoogled Chromium is moved to `User Data\Backup before import <date>`.
- **Extensions are per profile.** In each profile that was new, add uBlock Origin Lite once with the link the script prints at the end. Load Chromium Web Store there too if you want "Add to Chromium" in that profile ([section 5](#5-installing-extensions-from-the-chrome-web-store)).

**It takes a few minutes** for large profiles. A log is saved to `%TEMP%\ungoogled-chromium-import-log.txt`.
### 8.3 Bookmarks only (lighter alternative)

If you only want bookmarks, not whole profiles:

- **By clicking:** in Chrome open `chrome://bookmarks` → **⋮ → Export bookmarks**. In Ungoogled Chromium, open the same page → **⋮ → Import bookmarks**.
- **By copying files** (both browsers closed): copy `Bookmarks` and `Favicons` from
  `%LOCALAPPDATA%\Google\Chrome\User Data\Default\` to `%LOCALAPPDATA%\Chromium\User Data\Default\`.
  **Copy `Favicons` too.** Without it, the bookmarks show no icons until each site is opened once.

### 8.4 Removing a duplicate profile

If two imported profiles have the same Google address, remove one safely (browser closed):

- Take it out of the `profile.info_cache` / `profiles_order` lists in `%LOCALAPPDATA%\Chromium\User Data\Local State`.
- Rename its folder to `Profile N.removed` instead of deleting it.

Simpler: open the profile picker, click **⋮** on the profile → **Delete**. That one really deletes it, so be sure first.

### 8.5 Opening a specific profile directly

Each profile can be opened straight from a shortcut or the terminal:

```powershell
& "$env:LOCALAPPDATA\Chromium\Application\chrome.exe" --profile-directory="Profile 6"
```

- **Make a desktop shortcut:** right-click the Chromium shortcut → **Properties** → add `--profile-directory="Profile 6"` at the end of **Target**.
- **Pinned taskbar icons left over from Chrome** still open **Google Chrome**, not Chromium. Re-pin from Chromium.
- **Clicking a profile that is already open** just brings its window forward.

---

## 9. Passwords, with Bitwarden

**Recommendation: use Bitwarden, not the browser's own password manager.**

- **Ungoogled Chromium has no sync.** Its built-in passwords stay on this PC only: no phone, and no backup if the drive dies.
- **Bitwarden** is free, open source, and syncs across your phone, other PCs and every browser.
- **Copying Chrome's password file does not work.** Chrome locks it to itself, so passwords have to go through an export.

**Steps:**

1. **Export from Google, not from Chrome.** Open **passwords.google.com**, signed in to the account. Click the **⚙ gear → Export passwords → Export**, and enter your Google password when asked. This gets everything saved in the Google account. Exporting from inside Chrome (`chrome://password-manager/settings`) can come out empty for an account that syncs its passwords.
2. **Import into Bitwarden:** go to vault.bitwarden.com → **Tools → Import data**, choose the format **Chrome (csv)**, and upload the file.
3. **Repeat** for every Google account / Chrome profile that has passwords.
4. **Install the Bitwarden extension** in Ungoogled Chromium:
   https://chromewebstore.google.com/detail/nngceckbapebfimnlniiiahkandclblb
5. **Turn off the browser's own password saving** in every profile, so two pop-ups don't fight each other. Open `chrome://password-manager/settings` and turn off **Offer to save passwords** and **Sign in automatically**.
6. **Delete the exported CSV files and empty the Recycle Bin.** They hold every password in plain text.

**If Bitwarden rejects the file,** one bad row is usually the cause, such as a very long note or an odd URL. Fix or delete that row and import again.

**Without Bitwarden:** use the same export, then `chrome://password-manager/settings` → **Import passwords** in each profile. Keep the CSV backup somewhere encrypted, since nothing syncs.

---

## 10. Extensions to reinstall

Extensions copied from Chrome get switched off by Ungoogled Chromium, because Chrome installed them, not Chromium. Reinstall them from the store once Chromium Web Store is in ([section 5](#5-installing-extensions-from-the-chrome-web-store)).

Open `chrome://extensions` in **Google Chrome** to see your list, then in Ungoogled Chromium search the Chrome Web Store for each one and click **Add to Chromium**. **Install Bitwarden first** (or your password manager).

**Skip** the Google / McAfee add-ons Chrome installs by itself (Google Docs Offline and similar). They are useless here.

---

## 11. What does not work, and why

| Feature | Status | Workaround |
|---|---|---|
| **Google sign-in to the browser, sync** | Removed from the code; Google only allows official Chrome to use sync | Sign in to Google *websites* (Gmail, YouTube, Drive) as normal. That works. Use Bitwarden for passwords |
| **Google profile photo on profiles** | The browser deletes it on every start when no Google account is linked | Profile icon → **Customise** → pick a distinct icon and colour per profile |
| **Lens, AI Mode, Gemini in the address bar** | Google services, removed | None |
| **DRM video** (Netflix, Prime, some paid course videos) — error *"Unsupported keySystem or supportedConfigurations"* | Needs Google's **Widevine** component, which Ungoogled leaves out | Open that video in Google Chrome or Edge. Widevine can be copied over from Chrome, but it is closed-source Google code, doesn't update itself, and many DRM sites refuse unofficial browsers anyway. Not done in this setup |
| **Classic uBlock Origin** | Old extension format no longer supported since Chromium 139 | uBlock Origin Lite + AdGuard DNS ([section 4](#4-ad-blocking-three-layers)) |
| **Automatic browser updates** | No Google updater | The scheduled winget task ([section 3.2](#32-automatic-updates)) |

---

## 12. Troubleshooting

| Problem | Fix |
|---|---|
| **A site won't load at all** | Turn off **Use secure DNS** at `chrome://settings/security`. If that fixes it, AdGuard was blocking something the site needs |
| **A site looks broken** | uBlock icon → drag the slider to **Basic** for that site |
| **Ads are back** | Check uBlock Origin Lite is switched **on** at `chrome://extensions`, and its mode is still **Complete** |
| **No "Add to Chromium" button on the Web Store** | Chromium Web Store isn't loaded, or its folder was moved. Load it again ([section 5](#5-installing-extensions-from-the-chrome-web-store)) |
| **Extension install does nothing** | Check the flag `chrome://flags/#extension-mime-request-handling` is **Always prompt for install** |
| **Address bar doesn't search / no suggestions** | The profile existed before the install: run `extras\Set-Search-Engine.ps1` ([section 6](#6-search-in-the-address-bar)). Check `chrome://policy` lists `SearchSuggestEnabled`; if not, run `install.ps1` again |
| **"Managed by your organization" in the menu** | Expected: it comes from the policies the setup applies. `uninstall.ps1` removes them |
| **No "Add shortcut" on the new tab page** | Use `extras\Edit-Shortcuts.ps1` ([section 7](#7-new-tab-page-shortcuts)) |
| **A script says "Close Ungoogled Chromium first"** | Close every window *and* the icon near the clock. The browser saves its settings on exit and would overwrite the script's changes |
| **Browser is an old version** | `winget upgrade --id eloston.ungoogled-chromium -e`, then check the update task ([section 3.2](#32-automatic-updates)) |
| **Bookmarks have no icons** | Open each site once, or copy the `Favicons` file over ([section 8.3](#83-bookmarks-only-lighter-alternative)) |

**Useful pages:**

- `chrome://version` shows the version and the command line.
- `chrome://flags` lists the experimental switches.
- `chrome://extensions` lists the extensions.
- `chrome://settings/security` holds the secure DNS setting.
- `chrome://settings/searchEngines` holds the search engine setting.

---

## 13. Files in this repo

| File | What it is |
|---|---|
| `install.ps1` | One-shot setup: install, Google search for new profiles, updates, AdGuard DNS, extension flag, policies (suggestions, HTTPS first, preloading, uBlock Origin Lite settings), Chromium Web Store download |
| `uninstall.ps1` | Undoes `install.ps1`; keeps profiles and the browser |
| `docs/GUIDE.md` | This guide |
| `extras/Set-Search-Engine.ps1` (+ `set_search_engine.py`, `make-google-default.mjs`) | Google with suggestions as the default, plus yt / gh / maps shortcuts, in every **existing** profile |
| `import-chrome.ps1` | Copies every Chrome profile into Ungoogled Chromium, with Google search, named by Google address |
| `extras/Edit-Shortcuts.ps1` | Lists / adds / removes new tab page shortcuts per profile |
| `benchmark/` | Chrome vs Ungoogled test: `REPORT.md` (results) and `bench.mjs` (re-run with `node bench.mjs` after `pnpm install`) |

**Browser locations on disk:**

| What | Where |
|---|---|
| Browser program | `%LOCALAPPDATA%\Chromium\Application\chrome.exe` |
| Profiles and settings | `%LOCALAPPDATA%\Chromium\User Data\` |
| Global settings (DNS, flags, profile list) | `%LOCALAPPDATA%\Chromium\User Data\Local State` |
| Per-profile settings | `%LOCALAPPDATA%\Chromium\User Data\<Default or Profile N>\Preferences` |
| Chromium Web Store extension | `%LOCALAPPDATA%\Chromium\Unpacked Extensions\Chromium Web Store\` |
| Update script and log | `%LOCALAPPDATA%\Chromium\update-chromium.ps1`, `winget-upgrade.log` |
| Google default for new profiles | `%LOCALAPPDATA%\Chromium\Application\initial_preferences` (copy in `%LOCALAPPDATA%\Chromium\`) |
| Browser policies | Registry: `HKEY_CURRENT_USER\Software\Policies\Chromium` (see them at `chrome://policy`) |

---

## 14. Undoing changes

Nothing in this setup deletes data; every script keeps a backup.

**All at once:** `uninstall.ps1` removes the policies, the update task, the Google default for new profiles, AdGuard DNS and the extension flag:

```powershell
irm https://raw.githubusercontent.com/uniqueabhishek/ungoogled-chromium-adfree-private-lightweight-setup/main/uninstall.ps1 | iex
```

**One at a time:**

| Change | How to undo |
|---|---|
| AdGuard DNS | `chrome://settings/security` → turn off **Use secure DNS**, or restore `Local State.before-setup-<date>` (browser closed) |
| Extension install flag | `chrome://flags` → **Reset all** |
| uBlock Origin Lite / Chromium Web Store | `chrome://extensions` → **Remove** |
| Policies (suggestions, HTTPS first, preloading, uBlock settings) | Delete the values under `HKEY_CURRENT_USER\Software\Policies\Chromium` in Registry Editor, or run `uninstall.ps1` |
| Search engine | Change it in `chrome://settings/searchEngines`. Backups from `Set-Search-Engine.ps1`: `<file>.before-search-<date>` in each profile folder |
| New tab shortcuts | Restore `Preferences.before-shortcuts` in that profile's folder (browser closed) |
| Profile import | Delete the imported `Default` / `Profile N` folders and rename the `*.before-import-<date>` ones back |
| Update task | `Unregister-ScheduledTask -TaskName 'Update Ungoogled Chromium'` |
| The whole browser | `winget uninstall --id eloston.ungoogled-chromium`, then delete `%LOCALAPPDATA%\Chromium` if you want the profiles gone too |
