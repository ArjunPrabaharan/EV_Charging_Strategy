/* render.js — turns manifest nodes into DOM. Data-driven, recursive. */
(function () {
  "use strict";

  // ---- tiny DOM helpers ----
  function elem(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function frag() { return document.createDocumentFragment(); }

  function numPrefix(n) { return Number.isFinite(n) && n < 10000 ? n : null; }

  // ---- figure card + grid ----
  function figureCard(fig, lbItems, idx) {
    var card = elem("figure", "figure");

    var frame = elem("div", "figure__frame");
    var img = elem("img");
    img.src = fig.src;
    img.alt = fig.title || "";
    img.loading = "lazy";
    frame.appendChild(img);
    var badge = elem("span", "zoom-badge", "⤢ View");
    frame.appendChild(badge);
    frame.addEventListener("click", function () { window.Lightbox.open(lbItems, idx); });

    var body = elem("div", "figure__body");
    if (fig.caption) body.appendChild(elem("p", "figure__caption", fig.caption));
    if (fig.description) body.appendChild(elem("p", "figure__desc", fig.description));

    card.appendChild(frame);
    if (fig.caption || fig.description) card.appendChild(body);
    return card;
  }

  function figureGrid(figures) {
    var lbItems = figures.map(function (f) {
      return { src: f.src, title: f.title, caption: f.caption || f.description || "" };
    });
    var n = figures.length;
    var cls = "fig-grid" + (n === 2 ? " fig-grid--2" : n > 2 ? " fig-grid--auto" : "");
    var grid = elem("div", cls);
    figures.forEach(function (f, i) { grid.appendChild(figureCard(f, lbItems, i)); });
    return grid;
  }

  // ---- text blocks: info / spec / comparison / rulebase ----
  function deltaCell(uStr, cStr) {
    var u = parseFloat(String(uStr).replace(/[^0-9.\-]/g, ""));
    var c = parseFloat(String(cStr).replace(/[^0-9.\-]/g, ""));
    if (!isFinite(u) || !isFinite(c) || u === 0) return elem("td", "delta", "—");
    var pct = ((c - u) / u) * 100;
    var down = pct < 0;
    var td = elem("td", "delta " + (down ? "delta--down" : "delta--up"));
    td.textContent = (down ? "▼ " : "▲ ") + Math.abs(pct).toFixed(1) + "%";
    return td;
  }

  function comparisonTable(cmp) {
    var table = elem("table", "compare");
    var cap = elem("caption", null, "Uncoordinated vs Coordinated");
    table.appendChild(cap);

    var thead = elem("thead");
    var hr = elem("tr");
    hr.appendChild(elem("th", null, "Metric"));
    hr.appendChild(elem("th", null, cmp.columns[0]));
    hr.appendChild(elem("th", null, cmp.columns[1]));
    hr.appendChild(elem("th", null, "Change"));
    thead.appendChild(hr);
    table.appendChild(thead);

    var tbody = elem("tbody");
    cmp.metrics.forEach(function (m) {
      var tr = elem("tr");
      tr.appendChild(elem("th", null, m.label));
      tr.appendChild(elem("td", null, m.values[0]));
      var cTd = elem("td", "col-coord", m.values[1]);
      tr.appendChild(cTd);
      tr.appendChild(deltaCell(m.values[0], m.values[1]));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    return table;
  }

  function specBlock(block) {
    var box = frag();
    (block.groups || []).forEach(function (g) {
      if (g.heading) box.appendChild(elem("p", "spec__heading", g.heading));
      var grid = elem("div", "spec");
      g.pairs.forEach(function (p) {
        var item = elem("div", "spec__item");
        item.appendChild(elem("span", "spec__label", p.label));
        item.appendChild(elem("span", "spec__value", p.value));
        grid.appendChild(item);
      });
      box.appendChild(grid);
    });
    if (block.lines && block.lines.length) {
      var ul = elem("ul", "spec__lines");
      block.lines.forEach(function (ln) { ul.appendChild(elem("li", null, ln)); });
      box.appendChild(ul);
    }
    return box;
  }

  function infoBlock(block) {
    if (block.comparison) return comparisonTable(block.comparison);
    return specBlock(block);
  }

  function ruleBlock(block) {
    var wrap = elem("div", "group");
    var content = elem("ol", "rulebase");
    block.rules.forEach(function (r) { content.appendChild(elem("li", null, r)); });
    return window.Gallery.collapsible(
      block.title + " (" + block.rules.length + " rules)", content, { collapsed: false });
  }

  function renderBlocks(blocks) {
    var box = frag();
    (blocks || []).forEach(function (b) {
      if (b.type === "rulebase") box.appendChild(ruleBlock(b));
      else box.appendChild(infoBlock(b));
    });
    return box;
  }

  // ---- node body (no own title) ----
  function tabLabel(fig) {
    var m = /Station\s*\d+[^)]*\)?/i.exec(fig.title);
    if (m) return m[0].replace(/\s*-\s*/g, " · ");
    return fig.title;
  }

  function tabsFromNode(node) {
    var entries;
    if (node.children && node.children.length) {
      entries = node.children.map(function (c) {
        return { label: c.title, build: function () { return bodyOf(c); } };
      });
    } else {
      entries = node.figures.map(function (f) {
        return { label: tabLabel(f), build: function () { return figureGrid([f]); } };
      });
    }
    return window.Tabs.build(entries);
  }

  function bodyOf(node) {
    var box = elem("div", "node-body");

    if (node.display === "gallery" && node.figures.length) {
      var note = elem("p", "gallery-note", "Click any thumbnail to open it full-screen (zoom & arrow-key navigation).");
      var inner = frag();
      inner.appendChild(note);
      inner.appendChild(window.Gallery.grid(node.figures));
      var wrapped = elem("div");
      wrapped.appendChild(inner);
      box.appendChild(window.Gallery.collapsible(
        "All " + node.figures.length + " figures", wrapped, { collapsed: false }));
    } else if (node.display === "tabs") {
      box.appendChild(tabsFromNode(node));
    } else if (node.figures.length) {
      box.appendChild(figureGrid(node.figures));
    }

    if (node.blocks && node.blocks.length) box.appendChild(renderBlocks(node.blocks));

    // Nested sub-groups (e.g. PSO layer -> PSO Output) for non-tab parents.
    if (node.display !== "tabs" && node.children && node.children.length) {
      node.children.forEach(function (c) { box.appendChild(group(c)); });
    }
    return box;
  }

  // ---- titled group (nested, not a top panel) ----
  function group(node) {
    var wrap = elem("section", "group");
    wrap.appendChild(elem("h4", "group__title", node.title));
    wrap.appendChild(bodyOf(node));
    return wrap;
  }

  // ---- top-level panel within a section page ----
  function panel(node, id, label) {
    var p = elem("section", "panel");
    p.id = id;
    p.dataset.panel = id;
    p.appendChild(elem("h2", "panel__title", label));
    p.appendChild(bodyOf(node));
    return p;
  }

  function loosePanel(section, id) {
    var p = elem("section", "panel");
    p.id = id;
    p.dataset.panel = id;
    p.appendChild(elem("h2", "panel__title", "Summary"));
    if (section.figures.length) p.appendChild(figureGrid(section.figures));
    if (section.blocks.length) p.appendChild(renderBlocks(section.blocks));
    return p;
  }

  // Panel id/label list for a section (shared with the sidebar).
  function panelsOf(section) {
    var ps = (section.children || []).map(function (c) {
      return { id: section.id + "--" + c.id, label: c.title };
    });
    if ((section.figures.length || section.blocks.length) && ps.length) {
      ps.push({ id: section.id + "--summary", label: "Summary" });
    }
    return ps;
  }

  // ---- section page ----
  function sectionPage(section) {
    var page = elem("div", "section-page");

    var head = elem("div", "section-head");
    var ord = numPrefix(section.order);
    head.appendChild(elem("span", "section-head__eyebrow", ord ? "Section " + ord : "Overview"));
    head.appendChild(elem("h1", "section-head__title", section.title));
    if (section.intro) head.appendChild(elem("p", "section-head__intro", section.intro));
    page.appendChild(head);

    // Build the panel list.
    var panels = [];
    (section.children || []).forEach(function (c) {
      panels.push({ id: section.id + "--" + c.id, label: c.title, node: c });
    });
    var hasLoose = (section.figures.length || section.blocks.length);
    if (hasLoose && panels.length) {
      panels.push({ id: section.id + "--summary", label: "Summary", loose: true });
    }

    if (!panels.length) {
      // Sections 1-3: flat content, no sub-nav.
      page.appendChild(bodyOf(section));
      return { el: page, panels: [] };
    }

    // Sticky sub-nav.
    if (panels.length > 1) {
      var sub = elem("nav", "subnav");
      sub.setAttribute("aria-label", "Within-section navigation");
      panels.forEach(function (pn, i) {
        var b = elem("button", "subnav__btn" + (i === 0 ? " is-active" : ""), pn.label);
        b.type = "button";
        b.dataset.target = pn.id;
        b.addEventListener("click", function () {
          var t = document.getElementById(pn.id);
          if (t) t.scrollIntoView({ behavior: "smooth", block: "start" });
        });
        sub.appendChild(b);
      });
      page.appendChild(sub);
    }

    panels.forEach(function (pn) {
      page.appendChild(pn.loose ? loosePanel(section, pn.id) : panel(pn.node, pn.id, pn.label));
    });

    return { el: page, panels: panels.map(function (p) { return p.id; }) };
  }

  // ---- stat counter: counts from 0 → final value ----
  function animateStat(numEl, dir, abs) {
    var dur = 1350;
    var start = null;
    function tick(ts) {
      if (!start) start = ts;
      var prog = Math.min((ts - start) / dur, 1);
      prog = 1 - Math.pow(1 - prog, 3);
      numEl.textContent = dir + (abs * prog).toFixed(1) + "%";
      if (prog < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  // ---- particle constellation (canvas) ----
  function startParticles(canvas) {
    var ctx = canvas.getContext("2d");
    var raf = null;
    var W = 0, H = 0, pts = [];
    var LINK = 145, DOT_A = 0.52, LINE_A = 0.20;
    var COL = "96,165,250";

    function init() {
      W = canvas.width  = canvas.offsetWidth  || canvas.parentNode.offsetWidth;
      H = canvas.height = canvas.offsetHeight || canvas.parentNode.offsetHeight;
      var N = Math.max(40, Math.floor((W * H) / 13000));
      pts = [];
      for (var i = 0; i < N; i++) {
        pts.push({
          x:  Math.random() * W,
          y:  Math.random() * H,
          vx: (Math.random() - 0.5) * 0.32,
          vy: (Math.random() - 0.5) * 0.32,
          r:  0.9 + Math.random() * 1.1
        });
      }
    }

    function draw() {
      ctx.clearRect(0, 0, W, H);
      var n = pts.length;
      for (var i = 0; i < n; i++) {
        var a = pts[i];
        for (var j = i + 1; j < n; j++) {
          var b = pts[j];
          var dx = a.x - b.x, dy = a.y - b.y;
          var d2 = dx * dx + dy * dy;
          if (d2 < LINK * LINK) {
            var d = Math.sqrt(d2);
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.strokeStyle = "rgba(" + COL + "," + (LINE_A * (1 - d / LINK)) + ")";
            ctx.lineWidth = 0.8;
            ctx.stroke();
          }
        }
      }
      for (var i = 0; i < n; i++) {
        var p = pts[i];
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, 6.2832);
        ctx.fillStyle = "rgba(" + COL + "," + DOT_A + ")";
        ctx.fill();
        p.x += p.vx; p.y += p.vy;
        if (p.x < -2) p.x = W + 2;
        if (p.x > W + 2) p.x = -2;
        if (p.y < -2) p.y = H + 2;
        if (p.y > H + 2) p.y = -2;
      }
      raf = requestAnimationFrame(draw);
    }

    function start() {
      if (!canvas.offsetWidth) { requestAnimationFrame(start); return; }
      init();
      draw();
    }
    requestAnimationFrame(start);

    return function destroy() {
      if (raf) { cancelAnimationFrame(raf); raf = null; }
    };
  }

  // ---- overview / home — cinematic full-bleed ----
  function overview(manifest, onNavigate) {
    var p = manifest.project || {};
    var page = elem("div", "section-page overview-page");

    // ---- 1. Background layer ----------------------------------------
    var bg = elem("div", "ov-bg");

    function bgImg(url, cls) {
      var d = elem("div", "ov-bg__img " + cls);
      var img = document.createElement("img");
      img.src = url; img.alt = ""; img.loading = "eager"; img.decoding = "async";
      d.appendChild(img);
      return d;
    }
    // EV charger — right side, dominant
    bg.appendChild(bgImg(
      "https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=1800&q=80&fit=crop&auto=format",
      "ov-bg__img--1"
    ));
    // Power pylons / grid — full, atmospheric
    bg.appendChild(bgImg(
      "https://images.unsplash.com/photo-1473341304170-971dccb5ac1e?w=1400&q=65&fit=crop&auto=format",
      "ov-bg__img--2"
    ));
    // Solar panels — bottom-left accent
    bg.appendChild(bgImg(
      "https://images.unsplash.com/photo-1509391366360-2e959784a276?w=1200&q=65&fit=crop&auto=format",
      "ov-bg__img--3"
    ));

    var canvas = document.createElement("canvas");
    canvas.className = "ov-particles";
    bg.appendChild(canvas);

    bg.appendChild(elem("div", "ov-bg__overlay"));
    page.appendChild(bg);

    // ---- 2. Colour orbs ----------------------------------------
    page.appendChild(elem("div", "ov-orb ov-orb--1"));
    page.appendChild(elem("div", "ov-orb ov-orb--2"));

    // ---- 3. Content ----------------------------------------
    var content = elem("div", "ov-content");

    // Glass card
    var glass = elem("div", "ov-glass");

    var ey = elem("div", "ov-eyebrow");
    ey.appendChild(elem("span", "ov-eyebrow__text",
      "Final Year Project · University of Moratuwa · 2026"));
    glass.appendChild(ey);

    glass.appendChild(elem("h1", "ov-title",
      p.title || "Intelligent Coordinated EV Charging Strategy"));

    if (p.subtitle) glass.appendChild(elem("p", "ov-subtitle", p.subtitle));
    glass.appendChild(elem("div", "ov-divider"));

    var cmp = findComparison(manifest.sections);
    if (cmp) {
      var friendlyLabel = {
        "Total Charging Cost": "Charging Cost",
        "Total Energy Lost": "Network Losses"
      };
      var stats = elem("div", "ov-stats");
      cmp.metrics.forEach(function (m) {
        if (/energy consumption/i.test(m.label)) return;
        var u = parseFloat(String(m.values[0]).replace(/[^0-9.\-]/g, ""));
        var c = parseFloat(String(m.values[1]).replace(/[^0-9.\-]/g, ""));
        var pct = (isFinite(u) && u) ? ((c - u) / u) * 100 : 0;
        var card = elem("div", "ov-stat");
        var numEl = elem("div", "ov-stat__num", (pct <= 0 ? "▼ " : "▲ ") + "0.0%");
        card.appendChild(numEl);
        (function (el, dir, abs) {
          setTimeout(function () { animateStat(el, dir, abs); }, 620 + stats.children.length * 140);
        })(numEl, pct <= 0 ? "▼ " : "▲ ", Math.abs(pct));
        card.appendChild(elem("div", "ov-stat__label", friendlyLabel[m.label] || shortLabel(m.label)));
        card.appendChild(elem("div", "ov-stat__unit", "vs uncoordinated baseline"));
        stats.appendChild(card);
      });
      glass.appendChild(stats);
    }

    if (p.thesis) glass.appendChild(elem("blockquote", "ov-thesis", p.thesis));

    var cta = elem("p", "ov-cta");
    cta.innerHTML = "Navigate via the sidebar or press&nbsp;<kbd>→</kbd>&nbsp;to begin";
    glass.appendChild(cta);

    content.appendChild(glass);

    // Right: ambient spec chips
    var ambient = elem("div", "ov-ambient");
    [
      { label: "IEEE 33-Bus",     sub: "Radial Distribution Network" },
      { label: "11 kV · 10 MVA", sub: "Weak Grid · ×2.1 Load Scale" },
      { label: "5 PV Sites",     sub: "22.3 MWp Combined" },
      { label: "5 × 40 EVs",    sub: "11 kW Charger per EV" },
      { label: "PSO + Fuzzy",   sub: "Two-Layer Controller" },
      { label: "96 Intervals",   sub: "15-min Time Resolution" }
    ].forEach(function (s, i) {
      var chip = elem("div", "ov-chip");
      chip.style.animationDelay = (0.82 + i * 0.10) + "s";
      chip.appendChild(elem("div", "ov-chip__label", s.label));
      chip.appendChild(elem("div", "ov-chip__sub", s.sub));
      ambient.appendChild(chip);
    });
    // Problem statement image card
    var probWrap = elem("div", "ov-problem");
    var probImg = document.createElement("img");
    probImg.src = "assets/problem-image.png";
    probImg.alt = "Problem Statement";
    probImg.loading = "eager";
    probImg.decoding = "async";
    probWrap.appendChild(probImg);
    var probLabel = elem("div", "ov-problem__label", "Problem Statement");
    probWrap.appendChild(probLabel);
    var probHint = elem("div", "ov-problem__hint", "⤢ click to expand");
    probWrap.appendChild(probHint);
    probWrap.addEventListener("click", function () {
      window.Lightbox.open([{
        src: "assets/problem-image.png",
        title: "Problem Statement",
        caption: "Research motivation — voltage and thermal instability in weak distribution grids with high PV penetration and uncoordinated EV charging."
      }], 0);
    });

    // Right column: chips above, problem image below — both centred
    var right = elem("div", "ov-right");
    right.appendChild(ambient);
    right.appendChild(probWrap);
    content.appendChild(right);
    page.appendChild(content);

    // ---- 4. Start particles after mount ----------------------------------------
    var _destroy = null;
    requestAnimationFrame(function () {
      _destroy = startParticles(canvas);
    });
    page._destroyParticles = function () { if (_destroy) _destroy(); };

    return { el: page, panels: [] };
  }

  function shortLabel(label) {
    return label.replace(/^Total\s+/i, "").replace(/EV Energy Consumption/i, "Energy")
      .replace(/Charging Cost/i, "Cost").replace(/Energy Lost/i, "Energy lost");
  }

  function findComparison(sections) {
    for (var i = 0; i < sections.length; i++) {
      var found = scan(sections[i]);
      if (found) return found;
    }
    return null;
    function scan(node) {
      var b = (node.blocks || []).find(function (x) { return x.comparison; });
      if (b) return b.comparison;
      for (var j = 0; j < (node.children || []).length; j++) {
        var r = scan(node.children[j]);
        if (r) return r;
      }
      return null;
    }
  }

  window.Render = { sectionPage: sectionPage, overview: overview, panelsOf: panelsOf };
})();
