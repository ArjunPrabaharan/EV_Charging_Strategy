/* theme.js — light/dark toggle with persisted preference */
(function () {
  "use strict";

  var KEY = "fyp-dashboard-theme";
  var root = document.documentElement;

  function apply(theme) {
    root.setAttribute("data-theme", theme === "dark" ? "dark" : "light");
  }

  function current() {
    return root.getAttribute("data-theme") === "dark" ? "dark" : "light";
  }

  function init() {
    var saved = null;
    try { saved = localStorage.getItem(KEY); } catch (e) {}
    // Default is light (set in <html>); honour a saved preference only.
    if (saved === "dark" || saved === "light") apply(saved);

    var btn = document.getElementById("theme-toggle");
    if (btn) {
      btn.addEventListener("click", function () {
        var next = current() === "dark" ? "light" : "dark";
        apply(next);
        try { localStorage.setItem(KEY, next); } catch (e) {}
      });
    }
  }

  window.Theme = { init: init };
})();
