#!/usr/bin/env python3
"""
generate_manifest.py — one-off asset/manifest generator for the FYP dashboard.

What it does (run manually, NOT part of the offline runtime):
  1. Recursively scans the original ``Dashboard/`` asset folder.
  2. Copies every image into ``assets/`` under sanitised, URL-safe slugs while
     preserving the numeric ordering encoded in the folder/file names.
  3. Parses the ``Information to be displayed.txt`` / ``if then rule base.txt``
     notes into structured text blocks.
  4. Enriches the scanned tree with authored titles / captions / descriptions
     and per-group display hints (figures | gallery | tabs).
  5. Emits ``manifest.json`` that the dashboard renders entirely at runtime.

Adding or removing a figure only requires re-running this script — the HTML/JS
never reference filenames directly.

Usage:
    python tools/generate_manifest.py
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
ROOT = Path(__file__).resolve().parent.parent          # the project folder
SRC = ROOT / "Dashboard"                                # original assets
ASSETS = ROOT / "assets"                                # sanitised copy
MANIFEST = ROOT / "manifest.json"

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
NOTE_NAMES = {"information to be displayed.txt", "if then rule base.txt"}

# --------------------------------------------------------------------------- #
# Helpers — ordering & slugs
# --------------------------------------------------------------------------- #
_PREFIX_RE = re.compile(r"^\s*(\d+)\s*[-.)]\s*(.*)$")
_NUM_RE = re.compile(r"(\d+)")


def split_prefix(name: str) -> tuple[float, str]:
    """Return (numeric order, remaining title). Missing prefix -> large order."""
    m = _PREFIX_RE.match(name)
    if m:
        return float(m.group(1)), m.group(2).strip()
    return 10_000.0, name.strip()


def natural_key(name: str):
    """Sort key that orders 'bus 2' before 'bus 10'."""
    return [int(t) if t.isdigit() else t.lower() for t in _NUM_RE.split(name)]


def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-") or "item"


def humanize(stem: str) -> str:
    """Filename stem -> readable title (strip numeric prefix, tidy casing)."""
    _, rest = split_prefix(stem)
    rest = rest.replace("_", " ").strip()
    return rest[:1].upper() + rest[1:] if rest else stem


# --------------------------------------------------------------------------- #
# Authored metadata
# --------------------------------------------------------------------------- #
PROJECT = {
    "title": "Intelligent Coordinated EV Charging Strategy",
    "subtitle": "Voltage and Thermal Stability in Weak Distribution Grids with High PV Penetration",
    "author": "Final Year Project · University of Moratuwa",
    "thesis": (
        "A two-layer PSO + Fuzzy controller staggers EV charging across a weak, "
        "high-PV IEEE 33-bus grid — keeping every bus voltage in band and the "
        "transformer under its rating, while delivering essentially the same EV "
        "energy as the uncoordinated baseline."
    ),
}

# Short intro shown at the top of each top-level section, keyed by section order.
SECTION_INTRO = {
    1: "Daily per-unit profiles that drive the simulation: domestic demand and PV "
       "generation (smooth, then with cloud-induced intermittency).",
    2: "How the EV charging population is modelled — sample arrival/departure/SOC "
       "data, the energy-request formula, and resulting station occupancy.",
    3: "The modified IEEE 33-bus radial feeder used as the test system, deliberately "
       "made 'weak' so EV and PV stress is clearly visible.",
    4: "Baseline — every EV charges the moment it plugs in. The evening peak drives "
       "the far-end voltage below limit and overloads the transformer.",
    5: "The proposed strategy — a hierarchical PSO (how many chargers) + Fuzzy "
       "(which EVs) controller that keeps the grid stable while still meeting demand.",
}

# Per-folder display override (keyed by original POSIX relative path of the folder).
# Default is 'figures'; >=8 images auto-promote to 'gallery'.
DISPLAY = {
    "4 - Uncoordinated EV Charging/1 - Voltage profile of 33 buses": "gallery",
    "4 - Uncoordinated EV Charging/3 - EV charging": "tabs",
    "5 - Coordinated EV Charging/2 - PSO layer/3 - PSO Output": "tabs",
    # Fuzzy figures are a heterogeneous narrative (equations + MFs + surface) —
    # keep them as stacked cards so each caption stays visible.
    "5 - Coordinated EV Charging/3 - Fuzzy layer": "figures",
    "5 - Coordinated EV Charging/4 - Results/1 - Voltage profile of each bus": "gallery",
    "5 - Coordinated EV Charging/4 - Results/3 - EV charging Schedule": "tabs",
}

# Authored captions/descriptions keyed by original POSIX relative path of the file.
CAPTIONS = {
    # 1 - Load & PV
    "1 - Domestic load and PV profiles/1- Domestic Load profile.png": {
        "caption": "Per-unit domestic demand across the 24-hour day.",
        "description": "A small overnight base, a modest morning bump around 07:00, and the dominant evening peak near 18:00–19:00 — the window the EV load later collides with.",
    },
    "1 - Domestic load and PV profiles/2 - PV profile without intermitency.png": {
        "caption": "Clear-sky PV generation profile (per unit).",
        "description": "A smooth bell shape rising from ~06:00, peaking at midday, and falling by ~18:00. This is the ideal-day reference before clouds are introduced.",
    },
    "1 - Domestic load and PV profiles/3 - PV profile with intermitency.png": {
        "caption": "PV generation with cloud-induced intermittency.",
        "description": "The same midday envelope, now jagged with rapid dips as passing clouds shade the array. This fast variability is what induces voltage flicker on a weak grid and what the controller's fluctuation term must damp.",
    },
    # 2 - EV profiles & occupancies
    "2 - EV profile and occupancies/1- Sample EV profile data collected.png": {
        "caption": "Sample of the per-EV input data.",
        "description": "Each EV is described by arrival/departure times, arrival and target SOC, battery capacity, and the resulting energy request (kWh). These rows feed the EV_Data spreadsheets used by both scenarios.",
    },
    "2 - EV profile and occupancies/2 - Energy requested equation.png": {
        "caption": "Energy-request formula.",
        "description": "Required energy = (battery capacity ÷ charging efficiency) × (target SOC − arrival SOC) ÷ 100. This sets how much each EV must receive before it departs.",
    },
    "2 - EV profile and occupancies/3 - EV occupancy 1.png": {
        "caption": "EV aggregation occupancy — sample 1.",
        "description": "Number of vehicles present at a station through the day: filling from morning arrivals, a midday dip as some depart, then refilling toward evening.",
    },
    "2 - EV profile and occupancies/4 - EV occupancy 2.png": {
        "caption": "EV aggregation occupancy — sample 2.",
        "description": "A second station's occupancy pattern, showing the stochastic spread of arrivals and departures across the modelled fleet.",
    },
    "2 - EV profile and occupancies/5 - EV occupancy 3.png": {
        "caption": "EV aggregation occupancy — sample 3.",
        "description": "A third occupancy realisation — together these illustrate the time-varying, up-to-40-vehicle population each aggregation must serve.",
    },
    # 3 - Test system
    "3 - Weak distribution grid test system/1 - ieee 33 bus network.png": {
        "caption": "Modified IEEE 33-bus radial distribution feeder.",
        "description": "Single substation (slack) feeding 33 buses radially at 11 kV. Five EV charging aggregations (buses 6, 14, 20, 23, 26) and five 1 MWp PV sites are added to the standard benchmark. Domestic loads are scaled ×2.1 to make the grid 'weak'.",
    },
    # 4 - Uncoordinated loose + loading
    "4 - Uncoordinated EV Charging/Bus 5 and 18 voltage comparison.png": {
        "caption": "Voltage at bus 5 vs bus 18 (uncoordinated).",
        "description": "A near-substation bus (5) stays comfortably in band, while the far-end bus (18) sags hardest at the evening peak — the clearest single view of where the weak grid fails first.",
    },
    "4 - Uncoordinated EV Charging/2 - Transformer and line loading/1 - Transformer loading.png": {
        "caption": "Transformer apparent power vs the 10 MVA rating (uncoordinated).",
        "description": "Loading climbs through the evening and breaches the 10 MVA limit at the peak (shaded overload region) — a thermal violation of the distribution transformer.",
    },
    "4 - Uncoordinated EV Charging/2 - Transformer and line loading/2 - Main feeder line loading.png": {
        "caption": "Main feeder current vs the 525 A ampacity (uncoordinated).",
        "description": "Current on the main feeder during the night peak, checked against the 360 mm² AAAC cable ampacity of 525 A.",
    },
    # 5.1 architecture
    "5 - Coordinated EV Charging/1 - EV Charging Coordination Architecture/Coordination Architecture.png": {
        "caption": "Two-layer coordination architecture (flowchart).",
        "description": "Each 15-minute interval: update EV data, compute energy request and available EVs, run the PSO layer for the charger counts N_opt, then the Fuzzy layer to pick which EVs charge, update SOC, and repeat.",
    },
    # 5.2 PSO
    "5 - Coordinated EV Charging/2 - PSO layer/1 - PSO Architecture.png": {
        "caption": "PSO optimisation loop.",
        "description": "Particles encode the per-station charger counts (0 < Nᵢ < N_avail). Each is scored by a load flow + cost evaluation; local/global bests update until the iteration limit, returning the optimal N_opt vector.",
    },
    "5 - Coordinated EV Charging/2 - PSO layer/2 - PSO depiction graph.png": {
        "caption": "Conceptual depiction of the particle swarm search.",
        "description": "Illustrates how particles move through the decision space toward the cost-minimising charger allocation.",
    },
    # 5.3 fuzzy equations & MFs
    "5 - Coordinated EV Charging/3 - Fuzzy layer/1 - Energy Demand input equation.png": {
        "caption": "Energy Demand input — definition.",
        "description": "The first fuzzy input: remaining energy need, normalised so urgency is comparable across vehicles of different battery sizes.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/2 - Energy Demand membership function.png": {
        "caption": "Energy Demand membership functions (Low / Medium / High).",
        "description": "Shouldered MFs — sigmoid Low and High with a bell-shaped Medium — mapping the normalised energy need onto fuzzy linguistic terms.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/3 - Remaining time input equation.png": {
        "caption": "Remaining Time input — definition.",
        "description": "The second input: intervals left before the EV departs. Less time remaining means greater urgency.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/4 - Remaining time membership function.png": {
        "caption": "Remaining Time membership functions (Low / Medium / High).",
        "description": "Maps time-to-departure onto Low/Medium/High using the same shouldered MF scheme.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/5 - Fairness index input equation.png": {
        "caption": "Fairness Index input — definition.",
        "description": "The third input: how long the EV has already waited since arrival. It prevents starvation of vehicles that keep losing the priority contest.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/6 - Fairness index membership function.png": {
        "caption": "Fairness Index membership functions (Low / Medium / High).",
        "description": "Longer waiting maps toward High, raising an EV's priority over time.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/7 - Priority score membership function.png": {
        "caption": "Priority (output) membership functions.",
        "description": "The Mamdani output. After inference and defuzzification each EV gets a single priority score; the top N_opt(s) at each station are charged this interval.",
    },
    "5 - Coordinated EV Charging/3 - Fuzzy layer/8 - Control surface of energy demand and fairness index vs priopity score.png": {
        "caption": "Fuzzy control surface — Priority vs Energy Demand & Fairness.",
        "description": "The 3-D rule surface: priority rises with both energy demand and accumulated fairness, with the smooth blending produced by the 27-rule Mamdani system.",
    },
    # 5.4 results loading
    "5 - Coordinated EV Charging/4 - Results/2 - Transformer and line loading/1 - Transformer loading.png": {
        "caption": "Transformer loading under coordination vs the 10 MVA rating.",
        "description": "With charging staggered away from the evening peak, transformer loading stays under the 10 MVA limit — the overload of the baseline is removed.",
    },
    "5 - Coordinated EV Charging/4 - Results/2 - Transformer and line loading/2 - Main feeder line loading.png": {
        "caption": "Main feeder current under coordination vs the 525 A ampacity.",
        "description": "Feeder current held within the cable ampacity through the night peak.",
    },
    # 5.5 validation
    "5 - Coordinated EV Charging/5 - Validation/1 - Voltage Profile of bus 18 - Coordinated Vs Uncoordinated.png": {
        "caption": "Bus 18 voltage — coordinated vs uncoordinated.",
        "description": "The critical far-end bus. The uncoordinated case dips to ~0.928 pu in the evening (below the 0.94 limit); coordination holds it at the 0.94 boundary throughout.",
    },
    "5 - Coordinated EV Charging/5 - Validation/2 - Transformer Loading - Coordinated Vs Uncoordinated.png": {
        "caption": "Transformer loading — coordinated vs uncoordinated.",
        "description": "Side-by-side loading. The baseline breaches 10 MVA at the peak; the coordinated trace stays beneath it.",
    },
    "5 - Coordinated EV Charging/5 - Validation/3 - Main feeder current - Coordinated vs Uncoordinated.png": {
        "caption": "Main feeder current — coordinated vs uncoordinated.",
        "description": "Coordination shaves the night-peak feeder current relative to the baseline.",
    },
    "5 - Coordinated EV Charging/5 - Validation/4 - Remaining Total Energy Demand.png": {
        "caption": "Remaining total EV energy demand over the day.",
        "description": "Backlog of undelivered energy across the fleet. Both cases drive demand to (near) zero by departure — coordination meets the same needs, just spread intelligently in time.",
    },
    "5 - Coordinated EV Charging/5 - Validation/5 - Voltage Stability Index Coordinated vs uncoordinated.png": {
        "caption": "Worst-case Voltage Stability Index per bus.",
        "description": "VSI (min) for every bus. The coordinated curve sits above the uncoordinated one across the feeder — notably at the far buses — confirming improved stability margins.",
    },
}


def caption_for(rel_posix: str, stem: str) -> dict:
    """Authored caption if present, else a templated/humanised fallback."""
    if rel_posix in CAPTIONS:
        return CAPTIONS[rel_posix]

    low = rel_posix.lower()
    fname = stem.lower()

    # Per-bus voltage plots (uncoordinated & coordinated galleries)
    m = re.search(r"bus\s*(\d+)", fname)
    if "voltage profile" in low and m:
        bus = int(m.group(1))
        coord = "coordinated" if "coordinated" in low else "uncoordinated"
        extra = ""
        if bus == 18:
            extra = " Bus 18 is the critical far-end bus where the deepest sag occurs."
        elif bus in (1, 2):
            extra = " Near the substation, voltage stays close to nominal."
        return {
            "caption": f"Bus {bus} voltage over 24 hours ({coord}).",
            "description": f"Per-unit voltage trajectory at bus {bus} against the 0.94 pu lower limit.{extra}",
        }

    # PSO per-station output
    if "pso-optimised active chargers" in fname:
        return {
            "caption": humanize(stem) + ".",
            "description": "PSO-chosen number of active chargers at this station each 15-minute interval — high during midday PV (soaking up generation) and curtailed at the evening grid peak.",
        }

    # EV charging schedule grids
    if "charging schedule" in fname or "ev charging schedule" in fname:
        coord = "coordinated" if "coordinated" in low else "uncoordinated"
        note = (
            "Charging is staggered so the grid stays in limits while every EV still finishes."
            if coord == "coordinated"
            else "Every EV charges on arrival, clustering demand into the peak."
        )
        return {
            "caption": humanize(stem) + f" ({coord}).",
            "description": f"Per-EV status grid (absent / charging / connected-not-charging / fully charged) over the day. {note}",
        }

    # #EVs charging
    if "evs charging" in fname or "no. of evs" in fname:
        return {
            "caption": humanize(stem) + ".",
            "description": "Count of simultaneously charging EVs at this station through the day.",
        }

    return {"caption": humanize(stem) + ".", "description": ""}


# --------------------------------------------------------------------------- #
# Note-file parsing
# --------------------------------------------------------------------------- #
def parse_note(path: Path) -> dict:
    """Parse a notes .txt into a structured block."""
    raw = path.read_text(encoding="utf-8", errors="replace").strip()
    name = path.name.lower()

    if name == "if then rule base.txt":
        rules = [ln.strip() for ln in raw.splitlines() if ln.strip()]
        return {"type": "rulebase", "title": "Fuzzy IF–THEN Rule Base", "rules": rules}

    # "Information to be displayed.txt": grouped "key = value" lines.
    # A non-"=" line starts a new headed group (e.g. "Uncoordinated case").
    groups: list[dict] = []
    free: list[str] = []          # heading/prose lines with no following pairs
    cur: dict | None = None
    for ln in raw.splitlines():
        s = ln.strip()
        if not s:
            continue
        if "=" in s:
            k, v = s.split("=", 1)
            if cur is None:
                cur = {"heading": "", "pairs": []}
                groups.append(cur)
            cur["pairs"].append({"label": k.strip(), "value": v.strip()})
        else:
            cur = {"heading": s, "pairs": []}
            groups.append(cur)

    # Drop empty trailing heading-only groups into free prose; keep real ones.
    real_groups = [g for g in groups if g["pairs"]]
    free = [g["heading"] for g in groups if not g["pairs"] and g["heading"]]

    block = {"type": "info", "groups": real_groups, "lines": free}

    # If two groups expose the same metric labels, also emit a comparison table.
    if len(real_groups) == 2:
        a, b = real_groups
        la = [p["label"] for p in a["pairs"]]
        lb = [p["label"] for p in b["pairs"]]
        if la == lb:
            block["comparison"] = {
                "columns": [a["heading"] or "A", b["heading"] or "B"],
                "metrics": [
                    {"label": la[i], "values": [a["pairs"][i]["value"], b["pairs"][i]["value"]]}
                    for i in range(len(la))
                ],
            }
    return block


# --------------------------------------------------------------------------- #
# Tree walk + asset copy
# --------------------------------------------------------------------------- #
copied: list[tuple[Path, Path]] = []


def asset_path(rel_parts: list[str]) -> Path:
    """Map original relative parts -> sanitised assets path (preserving order)."""
    out_parts = []
    for part in rel_parts[:-1]:
        order, title = split_prefix(part)
        prefix = f"{int(order):02d}-" if order < 10_000 else ""
        out_parts.append(prefix + slugify(title))
    stem = Path(rel_parts[-1]).stem
    ext = Path(rel_parts[-1]).suffix.lower()
    order, title = split_prefix(stem)
    prefix = f"{int(order):02d}-" if order < 10_000 else ""
    out_parts.append(prefix + slugify(title) + ext)
    return ASSETS.joinpath(*out_parts)


def rel_src(value: Path) -> str:
    # Browser-relative path from index.html (which lives at project root).
    return "/".join(value.relative_to(ROOT).parts)


def build_node(folder: Path, rel: list[str]) -> dict:
    """Recursively build a manifest node for a folder."""
    rel_posix = "/".join(rel)
    order, title = split_prefix(folder.name)

    figures, children, blocks = [], [], []

    entries = sorted(folder.iterdir(), key=lambda p: (not p.is_dir(), *( (split_prefix(p.name)[0], natural_key(split_prefix(p.name)[1])) )))
    for entry in entries:
        if entry.is_dir():
            children.append(build_node(entry, rel + [entry.name]))
        elif entry.suffix.lower() in IMAGE_EXTS:
            file_rel = rel + [entry.name]
            dst = asset_path(file_rel)
            dst.parent.mkdir(parents=True, exist_ok=True)
            copied.append((entry, dst))
            stem = entry.stem
            meta = caption_for("/".join(file_rel), stem)
            figures.append({
                "src": rel_src(dst),
                "title": humanize(stem),
                "caption": meta.get("caption", ""),
                "description": meta.get("description", ""),
            })
        elif entry.name.lower() in NOTE_NAMES:
            blocks.append(parse_note(entry))

    # Decide display type
    display = DISPLAY.get(rel_posix)
    if not display:
        if children:
            display = "figures"            # parent that holds sub-groups
        elif len(figures) >= 8:
            display = "gallery"
        else:
            display = "figures"

    node = {
        "id": slugify("-".join(rel)) or "root",
        "order": order,
        "title": title,
        "display": display,
        "figures": figures,
        "children": children,
        "blocks": blocks,
    }
    return node


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main() -> None:
    if not SRC.is_dir():
        raise SystemExit(f"Source asset folder not found: {SRC}")

    # Clean previous asset copy for a deterministic rebuild.
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True, exist_ok=True)

    sections = []
    for entry in sorted(SRC.iterdir(), key=lambda p: split_prefix(p.name)[0]):
        if not entry.is_dir():
            continue
        node = build_node(entry, [entry.name])
        node["intro"] = SECTION_INTRO.get(int(node["order"]), "")
        sections.append(node)

    # Copy all queued image files.
    for src_file, dst_file in copied:
        shutil.copy2(src_file, dst_file)

    manifest = {
        "project": PROJECT,
        "generated_from": "Dashboard/",
        "sections": sections,
    }
    payload = json.dumps(manifest, indent=2, ensure_ascii=False)
    MANIFEST.write_text(payload, encoding="utf-8")

    # Also emit a JS global so the dashboard runs by double-clicking index.html
    # (browsers block fetch() of local JSON under the file:// protocol).
    js = "/* AUTO-GENERATED by tools/generate_manifest.py — do not edit. */\n"
    js += "window.DASHBOARD_MANIFEST = " + payload + ";\n"
    (ROOT / "manifest.js").write_text(js, encoding="utf-8")

    n_fig = sum(_count_figures(s) for s in sections)
    print(f"Copied {len(copied)} images into {ASSETS.relative_to(ROOT)}/")
    print(f"Wrote {MANIFEST.name} + manifest.js with {len(sections)} sections, {n_fig} figures.")


def _count_figures(node: dict) -> int:
    return len(node.get("figures", [])) + sum(_count_figures(c) for c in node.get("children", []))


if __name__ == "__main__":
    main()
