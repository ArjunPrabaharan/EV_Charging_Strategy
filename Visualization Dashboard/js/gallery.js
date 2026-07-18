/* gallery.js — thumbnail grid + collapsible wrapper */
(function () {
  "use strict";

  /**
   * Thumbnail grid. Clicking a thumb opens the lightbox over `figures`.
   * @param {Array} figures  [{src,title,caption,description}]
   */
  function grid(figures) {
    var g = document.createElement("div");
    g.className = "gallery";

    var lbItems = figures.map(function (f) {
      return { src: f.src, title: f.title, caption: f.caption || f.description || "" };
    });

    figures.forEach(function (f, i) {
      var t = document.createElement("button");
      t.className = "thumb";
      t.type = "button";
      t.title = f.caption || f.title;

      var img = document.createElement("img");
      img.src = f.src;
      img.alt = f.title || "";
      img.loading = "lazy";

      var label = document.createElement("div");
      label.className = "thumb__label";
      label.textContent = f.title;

      t.appendChild(img);
      t.appendChild(label);
      t.addEventListener("click", function () { window.Lightbox.open(lbItems, i); });
      g.appendChild(t);
    });

    return g;
  }

  /**
   * Collapsible container. Open by default unless opts.collapsed.
   */
  function collapsible(title, contentNode, opts) {
    opts = opts || {};
    var wrap = document.createElement("div");
    wrap.className = "collapsible" + (opts.collapsed ? "" : " is-open");

    var head = document.createElement("button");
    head.className = "collapsible__head";
    head.type = "button";
    head.innerHTML =
      '<span>' + escapeHtml(title) + '</span>' +
      '<span class="collapsible__chev">▸</span>';

    var body = document.createElement("div");
    body.className = "collapsible__body";
    body.appendChild(contentNode);

    head.addEventListener("click", function () { wrap.classList.toggle("is-open"); });

    wrap.appendChild(head);
    wrap.appendChild(body);
    return wrap;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  window.Gallery = { grid: grid, collapsible: collapsible };
})();
