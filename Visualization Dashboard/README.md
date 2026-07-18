# Visualization Dashboard

An interactive, offline dashboard for the project
**"Intelligent Coordinated EV Charging Strategy for Voltage and Thermal Stability
in Weak Distribution Networks with High PV Penetration."**

It is a guided visual walkthrough of the results — the network model, the load,
PV and EV profiles, and the full coordinated-vs-uncoordinated comparison. It is
built with **plain HTML, CSS, and vanilla JavaScript** (no frameworks, no build
step), and every figure, caption, and result number is driven by a generated
`manifest.json`, so it runs entirely offline in any modern browser.

---

## Opening the dashboard

**Option A — double-click (simplest).**
Open `index.html` directly in a browser. The data is loaded from `manifest.js`
(a JavaScript global), so it works under the `file://` protocol with no server.

**Option B — local static server (recommended).**
A server avoids any browser quirks and matches how it was tested:

```bash
# from this folder
python -m http.server 8000
# then visit http://127.0.0.1:8000/index.html
```

Tested at **1366×768** and up; it collapses to a slide-out menu on narrow windows.

---

## Using it during a presentation

- **Sidebar** — jump to any of the numbered sections (Overview → 1 → 2 → 3 → 4 → 5).
  Sections 4 and 5 expand to their sub-items.
- **Prev / Next** buttons or the **← / →** arrow keys move between sections.
- **Sub-nav pills** (top of sections 4 & 5) jump within a section.
- **Tabs** switch between the five charging stations / PSO outputs.
- **Galleries** (the 33 per-bus voltage plots, etc.) are collapsible thumbnail grids.
- **Click any figure** to open the **lightbox**: arrow keys / on-screen arrows to
  page through, mouse-wheel or **+ / −** to zoom, drag to pan, double-click to
  toggle zoom, **Esc** to close.
- **Theme** toggle (bottom-left) switches light/dark and remembers your choice.

---

## Project layout

```
index.html              Lean entry point
css/
  theme.css             Design tokens + light/dark themes
  layout.css            App shell (sidebar, stage, pager)
  components.css        Cards, tabs, galleries, tables, lightbox
js/
  theme.js              Light/dark toggle + persistence
  lightbox.js           Full-screen viewer (zoom / pan / keyboard)
  tabs.js               Reusable tab component
  gallery.js            Thumbnail grid + collapsible
  render.js             Data-driven section / figure / table renderers
  navigation.js         Sidebar build + active tracking
  main.js               Bootstrap (wires manifest, nav, pager, keys)
assets/                 Sanitised copy of the Dashboard figures
manifest.json           Canonical asset/section/caption tree
manifest.js             Same data as a JS global (for file:// use)
tools/
  generate_manifest.py  Regenerates assets/ + manifest from Dashboard/
Dashboard/              Original exported figures + notes (source of truth)
```

---

## Regenerating the manifest (when assets change)

The dashboard never hardcodes filenames. If you add, remove, or rename figures
in `Dashboard/`, regenerate everything in one step:

```bash
python tools/generate_manifest.py
```

This **rebuilds `assets/`** (a sanitised, URL-safe copy of `Dashboard/` with the
numeric ordering preserved), parses the `Information to be displayed.txt` /
`if then rule base.txt` notes into structured blocks, applies the authored
captions, and writes both `manifest.json` and `manifest.js`. No HTML/JS edits
are needed.

**Authoring captions/descriptions:** edit the `CAPTIONS`, `SECTION_INTRO`, and
`DISPLAY` dictionaries near the top of `tools/generate_manifest.py`, keyed by each
file's path relative to `Dashboard/`. Figures without an explicit caption fall
back to a templated one (e.g. per-bus voltage plots, station schedules).

Requires Python 3.8+ (standard library only).

---

## Presentation flow

| # | Section | Highlights |
|---|---------|-----------|
| 0 | Overview | Title, thesis, headline improvement vs baseline |
| 1 | Domestic load & PV profiles | Daily demand + PV (with/without intermittency) |
| 2 | EV profiles & occupancies | Sample data, energy-request formula, occupancy |
| 3 | Weak grid test system | IEEE 33-bus diagram + system spec sheet |
| 4 | Uncoordinated EV charging | 33-bus voltages, loading, station schedules, totals |
| 5 | Coordinated EV charging | Architecture → PSO → Fuzzy → Results → **Validation** |

The **Validation** panel (5.5) is the climax: coordinated-vs-uncoordinated figures
plus a comparison table showing essentially the same EV energy delivered while
**charging cost drops ~11.7%** and **energy losses ~11.6%**, with the bus-18
voltage sag and transformer overload removed.
