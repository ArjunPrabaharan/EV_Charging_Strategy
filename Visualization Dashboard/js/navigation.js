/* navigation.js — builds the sidebar and tracks the active section/panel */
(function () {
  "use strict";

  var HOME = "__home__";
  var root, handlers, itemsById = {};

  function elem(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function numPrefix(n) { return Number.isFinite(n) && n < 10000 ? n : null; }

  function build(manifest, h) {
    handlers = h;
    root = document.getElementById("nav");
    root.innerHTML = "";
    itemsById = {};

    addItem({ id: HOME, order: 0, title: "Overview", panels: [] }, "⌂");

    manifest.sections.forEach(function (s) {
      addItem(s, String(numPrefix(s.order) != null ? numPrefix(s.order) : "•"),
        window.Render.panelsOf(s));
    });
  }

  function addItem(view, badge, panels) {
    panels = panels || [];
    var item = elem("div", "nav__item");
    item.dataset.id = view.id;

    var link = elem("button", "nav__link");
    link.type = "button";
    link.appendChild(elem("span", "nav__num", badge));
    link.appendChild(elem("span", "nav__label", view.title));
    link.addEventListener("click", function () { handlers.onSection(view.id); });
    item.appendChild(link);

    if (panels.length) {
      var sub = elem("div", "nav__sub");
      panels.forEach(function (pn) {
        var sl = elem("button", "nav__sublink", pn.label);
        sl.type = "button";
        sl.dataset.panel = pn.id;
        sl.addEventListener("click", function () { handlers.onPanel(view.id, pn.id); });
        sub.appendChild(sl);
      });
      item.appendChild(sub);
    }

    root.appendChild(item);
    itemsById[view.id] = item;
  }

  function setActiveSection(id) {
    Object.keys(itemsById).forEach(function (key) {
      var it = itemsById[key];
      var on = key === id;
      it.classList.toggle("is-active", on);
      it.classList.toggle("is-open", on);
    });
    var active = itemsById[id];
    if (active) active.scrollIntoView({ block: "nearest" });
  }

  function setActivePanel(panelId) {
    root.querySelectorAll(".nav__sublink").forEach(function (sl) {
      sl.classList.toggle("is-active", sl.dataset.panel === panelId);
    });
  }

  window.Navigation = {
    HOME: HOME,
    build: build,
    setActiveSection: setActiveSection,
    setActivePanel: setActivePanel,
  };
})();
