/* tabs.js — reusable tabbed component */
(function () {
  "use strict";

  var seq = 0;

  /**
   * Build a tab group.
   * @param {Array<{label:string, build:function():Node}>} entries
   * @returns {HTMLElement}
   */
  function build(entries) {
    var wrap = document.createElement("div");
    wrap.className = "tabs";

    var list = document.createElement("div");
    list.className = "tabs__list";
    list.setAttribute("role", "tablist");

    var panels = document.createElement("div");
    panels.className = "tabs__panels";

    entries.forEach(function (entry, i) {
      var id = "tab-" + (++seq);

      var btn = document.createElement("button");
      btn.className = "tabs__tab";
      btn.type = "button";
      btn.textContent = entry.label;
      btn.setAttribute("role", "tab");
      btn.setAttribute("aria-controls", id);

      var panel = document.createElement("div");
      panel.className = "tabs__panel";
      panel.id = id;
      panel.setAttribute("role", "tabpanel");
      panel.appendChild(entry.build());

      if (i === 0) { btn.classList.add("is-active"); btn.setAttribute("aria-selected", "true"); }
      else { panel.hidden = true; }

      btn.addEventListener("click", function () {
        list.querySelectorAll(".tabs__tab").forEach(function (b) {
          b.classList.remove("is-active"); b.removeAttribute("aria-selected");
        });
        panels.querySelectorAll(".tabs__panel").forEach(function (p) { p.hidden = true; });
        btn.classList.add("is-active");
        btn.setAttribute("aria-selected", "true");
        panel.hidden = false;
      });

      list.appendChild(btn);
      panels.appendChild(panel);
    });

    wrap.appendChild(list);
    wrap.appendChild(panels);
    return wrap;
  }

  window.Tabs = { build: build };
})();
