{{flutter_js}}
{{flutter_build_config}}
// Starts Flutter, after making sure the service worker (sw.js) serves this
// same build. BUILD is filled in by `dart run tool/web_pwa_stamp.dart`;
// this file is always fetched from the network when online (sw.js and the
// host's Cache-Control: no-cache), so it is the first thing to know about a
// new deploy:
//   - no worker yet, or the worker is this build: start now;
//   - the worker is an older build: hold the splash until the new worker
//     has installed, let it take over, reload onto it (at most twice per
//     tab session, and never later than 30 s: then start with what is
//     there, and the new build takes over on the next start);
//   - an unstamped build: remove any worker (no cached code survives).
(() => {
  const BUILD = "__KUTE_BUILD__";
  const STAMPED = !BUILD.startsWith("__");
  const RELOADS_KEY = "kute-sw-reloads";
  const sw = window.isSecureContext && "serviceWorker" in navigator
    ? navigator.serviceWorker
    : null;

  let booted = false;
  const boot = () => {
    if (booted) return;
    booted = true;
    _flutter.loader.load({
      config: {
        // CanvasKit from this origin (build/web/canvaskit/), not the gstatic
        // CDN: the Content-Security-Policy runs no script from another origin.
        canvasKitBaseUrl: "canvaskit/",
      },
    });
  };

  // Reloads unless this tab already reloaded twice for a worker switch (a
  // broken deploy must not loop). False when it did not reload.
  const reloadOnce = () => {
    let count = 99;
    try {
      count = Number(sessionStorage.getItem(RELOADS_KEY) || 0);
      sessionStorage.setItem(RELOADS_KEY, String(count + 1));
    } catch (_) {}
    if (count >= 2) return false;
    location.reload();
    return true;
  };

  if (!sw) {
    boot();
    return;
  }

  const controller = sw.controller;
  if (!STAMPED) {
    // No worker and no cached shell may outlive an unstamped deploy.
    const cleared = sw.getRegistrations()
      .then((regs) => Promise.all(regs.map((r) => r.unregister())))
      .then(() => caches.keys())
      .then((names) => Promise.all(names
        .filter((n) => n.startsWith("kute-shell-"))
        .map((n) => caches.delete(n))));
    if (!controller) {
      boot();
      cleared.catch(() => {});
      return;
    }
    cleared.then(() => reloadOnce() || boot(), boot);
    return;
  }

  const buildOf = (worker) =>
    worker ? new URL(worker.scriptURL).searchParams.get("v") : null;
  const registering = sw.register("sw.js?v=" + BUILD, {
    scope: "./",
    updateViaCache: "none",
  });

  if (!controller || buildOf(controller) === BUILD) {
    try {
      sessionStorage.removeItem(RELOADS_KEY);
    } catch (_) {}
    boot();
    registering.then((reg) => {
      keepChecking(reg);
      if (!controller) cacheWhatLoaded();
    }, () => {});
    return;
  }

  // The worker serving this page is an older build.
  sw.addEventListener("controllerchange", () => {
    if (!booted && !reloadOnce()) boot();
  });
  const promote = (worker) => {
    if (!worker || buildOf(worker) !== BUILD) return;
    const step = () => {
      if (worker.state === "installed") worker.postMessage("kute-activate");
      if (worker.state === "redundant") boot(); // install failed: offline?
    };
    worker.addEventListener("statechange", step);
    step();
  };
  registering.then((reg) => {
    promote(reg.waiting);
    promote(reg.installing);
    reg.addEventListener("updatefound", () => promote(reg.installing));
    if (!reg.installing && !reg.waiting && buildOf(reg.active) === BUILD) {
      if (!reloadOnce()) boot();
    }
  }, boot);
  setTimeout(boot, 30000);

  // An installed app can stay open for days: look for a new deploy when it
  // comes back to the foreground, at most hourly. A new worker only installs
  // and waits; it takes over on the next start.
  function keepChecking(reg) {
    let last = Date.now();
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState !== "visible") return;
      if (Date.now() - last < 3600 * 1000) return;
      last = Date.now();
      reg.update().catch(() => {});
    });
  }

  // First visit: the page loaded before the worker existed. Once it is
  // running, hand it the shell files this page used (it keeps only shell
  // paths of this origin) so the next start works offline.
  function cacheWhatLoaded() {
    sw.ready.then((reg) => {
      setTimeout(() => {
        const urls = performance
          .getEntriesByType("resource")
          .map((e) => e.name)
          .filter((u) => u.startsWith(location.origin + "/"));
        if (reg.active) reg.active.postMessage({ kute: "used", urls });
      }, 20000);
    });
  }
})();
