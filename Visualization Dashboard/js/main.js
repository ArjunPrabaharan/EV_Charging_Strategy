/* main.js — bootstrap: wires manifest, navigation, rendering, pager, keyboard */
(function () {
  "use strict";

  var manifest = window.DASHBOARD_MANIFEST;
  var stage, pagerLabel, prevBtn, nextBtn, topbarTitle;

  var order = [];        // ordered view ids: HOME, sec1..sec5
  var sections = {};     // id -> section node
  var cache = {};        // id -> { el, panels }
  var current = null;
  var spy = null;        // IntersectionObserver for the active page

  function byId(id) { return document.getElementById(id); }

  function viewTitle(id) {
    if (id === window.Navigation.HOME) return "Overview";
    var s = sections[id];
    return s ? s.title : "";
  }

  function buildView(id) {
    if (cache[id]) return cache[id];
    var built = id === window.Navigation.HOME
      ? window.Render.overview(manifest, function (sid) { go(sid); })
      : window.Render.sectionPage(sections[id]);
    cache[id] = built;
    return built;
  }

  function setupSpy(panels) {
    if (spy) { spy.disconnect(); spy = null; }
    if (!panels || !panels.length) return;
    spy = new IntersectionObserver(function (entries) {
      // Pick the entry nearest the top that is intersecting.
      var best = null;
      entries.forEach(function (e) {
        if (e.isIntersecting && (!best || e.boundingClientRect.top < best.boundingClientRect.top)) {
          best = e;
        }
      });
      if (best) highlightPanel(best.target.id);
    }, { root: stage, rootMargin: "-10% 0px -70% 0px", threshold: 0 });

    panels.forEach(function (pid) {
      var elp = byId(pid);
      if (elp) spy.observe(elp);
    });
  }

  function highlightPanel(panelId) {
    window.Navigation.setActivePanel(panelId);
    var subnav = stage.querySelector(".subnav");
    if (subnav) {
      subnav.querySelectorAll(".subnav__btn").forEach(function (b) {
        b.classList.toggle("is-active", b.dataset.target === panelId);
      });
    }
  }

  function go(id, panelId) {
    if (!order.indexOf) return;
    if (order.indexOf(id) === -1) id = window.Navigation.HOME;
    current = id;

    var built = buildView(id);
    // Stop particle canvas from overview before swapping content.
    var prev = stage.firstElementChild;
    if (prev && typeof prev._destroyParticles === "function") {
      prev._destroyParticles();
    }
    stage.innerHTML = "";
    stage.appendChild(built.el);
    stage.scrollTop = 0;

    // Re-trigger entrance animation (restart even for cached nodes).
    built.el.classList.remove("page-entered");
    void built.el.offsetWidth; // force reflow
    built.el.classList.add("page-entered");

    // Lock scrolling on the overview (no-scroll static page).
    stage.style.overflowY = (id === window.Navigation.HOME) ? "hidden" : "";

    window.Navigation.setActiveSection(id);
    topbarTitle.textContent = viewTitle(id);
    updatePager();
    setupSpy(built.panels);
    closeNav();

    if (panelId) {
      var target = byId(panelId);
      if (target) {
        // let layout settle, then scroll within the stage
        requestAnimationFrame(function () {
          target.scrollIntoView({ behavior: "smooth", block: "start" });
          highlightPanel(panelId);
        });
      }
    } else if (built.panels.length) {
      highlightPanel(built.panels[0]);
    }
  }

  function updatePager() {
    var i = order.indexOf(current);
    prevBtn.disabled = i <= 0;
    nextBtn.disabled = i >= order.length - 1;
    pagerLabel.textContent = (i + 1) + " / " + order.length + " · " + viewTitle(current);
  }

  function stepView(d) {
    var i = order.indexOf(current);
    var j = i + d;
    if (j >= 0 && j < order.length) go(order[j]);
  }

  // ---- mobile nav drawer ----
  function openNav() { document.body.classList.add("nav-open"); byId("nav-scrim").hidden = false; }
  function closeNav() { document.body.classList.remove("nav-open"); byId("nav-scrim").hidden = true; }

  function init() {
    if (!manifest) {
      document.getElementById("stage").innerHTML =
        '<div class="section-page"><h1>Manifest not loaded</h1>' +
        '<p>Run <code>python tools/generate_manifest.py</code> to generate ' +
        '<code>manifest.js</code>, then reload.</p></div>';
      return;
    }

    stage = byId("stage");
    pagerLabel = byId("pager-label");
    prevBtn = byId("prev-btn");
    nextBtn = byId("next-btn");
    topbarTitle = byId("topbar-title");

    // Index sections + ordered view list.
    order = [window.Navigation.HOME];
    manifest.sections.forEach(function (s) { sections[s.id] = s; order.push(s.id); });

    window.Theme.init();
    window.Lightbox.init();
    window.Navigation.build(manifest, {
      onSection: function (id) { go(id); },
      onPanel: function (id, panelId) { go(id, panelId); },
    });

    prevBtn.addEventListener("click", function () { stepView(-1); });
    nextBtn.addEventListener("click", function () { stepView(1); });
    byId("menu-toggle").addEventListener("click", openNav);
    byId("nav-scrim").addEventListener("click", closeNav);

    // Global arrow-key paging (ignored while the lightbox or a field is focused).
    document.addEventListener("keydown", function (e) {
      if (window.Lightbox.isOpen()) return;
      var t = e.target;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
      if (e.key === "ArrowRight") { stepView(1); }
      else if (e.key === "ArrowLeft") { stepView(-1); }
    });

    // Open from hash if present, else the overview.
    var startId = (location.hash || "").replace(/^#/, "");
    go(order.indexOf(startId) !== -1 ? startId : window.Navigation.HOME);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
