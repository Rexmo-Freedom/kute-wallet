// Haptics in Safari on iPhone and iPad (founder, 27 November 2026: "if
// possible haptics on iOS web also").
//
// Safari has no navigator.vibrate, so every haptic the app asks for (taps,
// selections, confirmations: Flutter's HapticFeedback, which the web engine
// sends to navigator.vibrate) did nothing there. Since iOS 18 Safari gives
// one haptic tick when a native switch (<input type="checkbox" switch>)
// flips, also when its label is clicked from script during a tap. So on a
// browser with no navigator.vibrate that knows the switch control, this
// file provides navigator.vibrate: each call flips a hidden switch once (a
// long one, 30 ms or more, twice). Android and desktop browsers keep their
// own navigator.vibrate; a Safari too old for the switch is left alone.
//
// Nothing is shown, read or sent; the hidden label lives only for the
// click. Loaded before Flutter (index.html) so the engine finds
// navigator.vibrate when it looks.
(function () {
  "use strict";
  try {
    if (typeof navigator === "undefined" || "vibrate" in navigator) return;
    var ua = navigator.userAgent || "";
    var apple =
      /iPhone|iPad|iPod/.test(ua) ||
      (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
    if (!apple) return;
    var probe = document.createElement("input");
    probe.type = "checkbox";
    if (!("switch" in probe)) return;

    var tick = function () {
      try {
        var label = document.createElement("label");
        label.setAttribute("aria-hidden", "true");
        label.style.display = "none";
        var input = document.createElement("input");
        input.type = "checkbox";
        input.setAttribute("switch", "");
        label.appendChild(input);
        document.head.appendChild(label);
        label.click();
        document.head.removeChild(label);
      } catch (_) {}
    };

    var vibrate = function (pattern) {
      var ms = Array.isArray(pattern) ? pattern[0] : pattern;
      tick();
      if (typeof ms === "number" && ms >= 30) setTimeout(tick, 70);
      return true;
    };
    try {
      Object.defineProperty(navigator, "vibrate", {
        value: vibrate,
        configurable: true,
        writable: true,
      });
    } catch (_) {
      navigator.vibrate = vibrate;
    }
  } catch (_) {}
})();
