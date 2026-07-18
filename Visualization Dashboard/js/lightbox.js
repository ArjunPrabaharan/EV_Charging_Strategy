/* lightbox.js — fullscreen figure viewer with zoom, pan, keyboard nav */
(function () {
  "use strict";

  var items = [];      // [{ src, title, caption }]
  var index = 0;
  var scale = 1, tx = 0, ty = 0;
  var panning = false, startX = 0, startY = 0;
  var MIN = 1, MAX = 6, STEP = 0.35;

  var el = {};

  function q(id) { return document.getElementById(id); }

  function resetTransform() {
    scale = 1; tx = 0; ty = 0;
    applyTransform();
  }

  function applyTransform() {
    el.img.style.transform =
      "translate(" + tx + "px," + ty + "px) scale(" + scale + ")";
    el.stage.style.cursor = scale > 1 ? (panning ? "grabbing" : "grab") : "default";
  }

  function zoom(delta, cx, cy) {
    var prev = scale;
    scale = Math.min(MAX, Math.max(MIN, scale + delta));
    if (scale === prev) return;
    if (scale === 1) { tx = 0; ty = 0; }
    applyTransform();
  }

  function show() {
    var it = items[index];
    if (!it) return;
    el.img.src = it.src;
    el.img.alt = it.title || "";
    el.title.textContent = it.title || "";
    el.caption.textContent = it.caption || "";
    resetTransform();
    var multi = items.length > 1;
    el.prev.style.display = multi ? "" : "none";
    el.next.style.display = multi ? "" : "none";
  }

  function open(list, i) {
    items = list || [];
    index = i || 0;
    el.box.classList.add("is-open");
    el.box.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    show();
  }

  function close() {
    el.box.classList.remove("is-open");
    el.box.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    el.img.src = "";
  }

  function step(d) {
    if (!items.length) return;
    index = (index + d + items.length) % items.length;
    show();
  }

  function isOpen() { return el.box.classList.contains("is-open"); }

  function init() {
    el.box = q("lightbox");
    el.img = q("lightbox-img");
    el.stage = q("lightbox-stage");
    el.title = q("lightbox-title");
    el.caption = q("lightbox-caption");
    el.prev = el.box.querySelector('[data-lb="prev"]');
    el.next = el.box.querySelector('[data-lb="next"]');

    el.box.addEventListener("click", function (e) {
      var act = e.target.getAttribute && e.target.getAttribute("data-lb");
      if (act === "close") return close();
      if (act === "prev") return step(-1);
      if (act === "next") return step(1);
      if (act === "zoom-in") return zoom(STEP);
      if (act === "zoom-out") return zoom(-STEP);
      if (act === "zoom-reset") return resetTransform();
      // Click on the dim backdrop (the stage area, not the image) closes.
      if (e.target === el.box || e.target === el.stage) close();
    });

    // Wheel zoom
    el.stage.addEventListener("wheel", function (e) {
      e.preventDefault();
      zoom(e.deltaY < 0 ? STEP : -STEP);
    }, { passive: false });

    // Double-click toggles zoom
    el.stage.addEventListener("dblclick", function () {
      if (scale > 1) resetTransform(); else zoom(1.5);
    });

    // Drag to pan
    el.stage.addEventListener("mousedown", function (e) {
      if (scale <= 1) return;
      panning = true; startX = e.clientX - tx; startY = e.clientY - ty;
      el.stage.classList.add("is-panning");
      e.preventDefault();
    });
    window.addEventListener("mousemove", function (e) {
      if (!panning) return;
      tx = e.clientX - startX; ty = e.clientY - startY;
      applyTransform();
    });
    window.addEventListener("mouseup", function () {
      panning = false; el.stage.classList.remove("is-panning"); applyTransform();
    });

    // Keyboard
    document.addEventListener("keydown", function (e) {
      if (!isOpen()) return;
      switch (e.key) {
        case "Escape": close(); break;
        case "ArrowLeft": step(-1); break;
        case "ArrowRight": step(1); break;
        case "+": case "=": zoom(STEP); break;
        case "-": case "_": zoom(-STEP); break;
        case "0": resetTransform(); break;
      }
    });
  }

  window.Lightbox = { init: init, open: open, isOpen: isOpen };
})();
