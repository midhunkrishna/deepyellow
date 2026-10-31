/* Shared behaviour: the ledger bar tracks how much of the page has been read; copy buttons. No network, no storage. */
(function () {
  "use strict";

  /** Updates the ledger bar's read segment and percentage from the scroll position. */
  function updateLedger() {
    var read = document.querySelector(".ledger .read");
    var pct = document.querySelector(".ledger [data-pct]");
    if (!read) return;
    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;
    var share = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 1;
    read.style.width = (share * 92).toFixed(1) + "%";
    if (pct) pct.textContent = Math.round(share * 100) + "%";
  }

  /** Wires every [data-copy] button to copy the text of the code element in the same box. */
  function wireCopy() {
    document.querySelectorAll("button[data-copy]").forEach(function (button) {
      var source = button.parentElement.querySelector("code");
      if (!source || !navigator.clipboard) { button.hidden = true; return; }
      button.addEventListener("click", function () {
        navigator.clipboard.writeText(source.textContent.trim()).then(function () {
          button.textContent = "Copied";
          window.setTimeout(function () { button.textContent = "Copy"; }, 1600);
        }, function () { button.textContent = "Select and copy"; });
      });
    });
  }

  window.addEventListener("scroll", updateLedger, { passive: true });
  window.addEventListener("resize", updateLedger);
  updateLedger();
  wireCopy();
})();
