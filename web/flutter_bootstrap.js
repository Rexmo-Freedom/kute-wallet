{{flutter_js}}
{{flutter_build_config}}
// Starts Flutter, after making sure the service worker (sw.js) serves this
// same build. BUILD is filled in by `dart run tool/web_pwa_stamp.dart`;
// this file is always fetched from the network when online (sw.js asks with
// cache: 'no-cache', and the host must send Cache-Control: no-cache, see
// tool/web_serve.py), so it is the first thing to know about a new deploy:
//   - no worker yet, or the worker is this build: start now, then ask the
//     network once which build is current (this copy may still have come
//     from the HTTP cache when no worker served it): a newer one while the
//     splash is up reloads onto it; later, it only installs and waits;
//   - the worker is an older build: hold the splash until the new worker
//     has installed, let it take over, reload onto it (at most twice per
//     tab session, and never later than 30 s: then start with what is
//     there, and the new build takes over on the next start);
//   - an unstamped build: remove any worker (no cached code survives).
// window.kuteWebBuild is this build's id (Settings > Advanced shows it).
(() => {
  const BUILD = "__KUTE_BUILD__";
  const STAMPED = !BUILD.startsWith("__");
  const RELOADS_KEY = "kute-sw-reloads";
  const STARTED = Date.now();
  const sw = window.isSecureContext && "serviceWorker" in navigator
    ? navigator.serviceWorker
    : null;
  if (STAMPED) window.kuteWebBuild = BUILD;

  let booted = false;
  const boot = () => {
    if (booted) return;
    booted = true;
    if (STAMPED) console.info("Kute web build " + BUILD);
    if (STAMPED && !(sw && sw.controller)) {
      // No worker in front: the HTTP cache may still hold another build's
      // main.dart.js under the same name. This build's own URL instead.
      for (const build of _flutter.buildConfig.builds || []) {
        for (const key of ["mainJsPath", "mainWasmPath", "jsSupportRuntimePath"]) {
          if (build[key]) build[key] += "?v=" + BUILD;
        }
      }
    }
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
    boot();
    checkForNewBuild();
    keepChecking();
    registering.then(() => {
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
      // Started anyway (30 s): it takes over on the next start, never
      // under the running app.
      if (booted) return;
      if (worker.state === "installed") {
        whenQuiet(() => booted || worker.postMessage("kute-activate"));
      }
      if (worker.state === "redundant") boot(); // install failed: offline?
    };
    worker.addEventListener("statechange", step);
    step();
  };
  // Chrome can wedge a worker switch asked for while the old worker is
  // still answering this page's first burst of requests (tested: a new
  // build already installed and waiting, asked to take over right after
  // the reload, hung until the 30 s fallback). So: once the page has
  // loaded and no new request started between two looks 200 ms apart.
  function whenQuiet(then) {
    let seen = -1;
    const tick = () => {
      const now = performance.getEntriesByType("resource").length;
      if (document.readyState === "complete" && now === seen) then();
      else setTimeout(tick, 200);
      seen = now;
    };
    tick();
  }
  registering.then((reg) => {
    promote(reg.waiting);
    promote(reg.installing);
    reg.addEventListener("updatefound", () => promote(reg.installing));
    if (!reg.installing && !reg.waiting && buildOf(reg.active) === BUILD) {
      if (!reloadOnce()) boot();
    }
  }, boot);
  setTimeout(boot, 30000);

  // Which build the network serves now: the BUILD in a fresh copy of this
  // file (through sw.js, network first). Null offline or unstamped.
  function currentBuild() {
    return fetch("flutter_bootstrap.js", { cache: "no-cache" })
      .then((r) => (r.ok ? r.text() : ""))
      .then((text) => {
        const m = /const BUILD = "([0-9a-f]+)"/.exec(text);
        return m ? m[1] : null;
      }, () => null);
  }

  // This copy may be an older build than the network's (it came from the
  // HTTP cache with no worker in front, or the network was too slow for
  // sw.js). A newer build while the splash is still up (nobody is using
  // the app yet): reload onto it, as a worker switch does. Once the app is
  // in use: install the new worker and let it wait for the next start.
  function checkForNewBuild() {
    return currentBuild().then((latest) => {
      if (!latest) return;
      if (latest === BUILD) {
        try {
          sessionStorage.removeItem(RELOADS_KEY);
        } catch (_) {}
        return;
      }
      const fresh = Date.now() - STARTED < 10000 &&
        document.getElementById("splash");
      if (fresh && reloadOnce()) return;
      sw.register("sw.js?v=" + latest, {
        scope: "./",
        updateViaCache: "none",
      }).catch(() => {});
    });
  }

  // An installed app can stay open for days: look for a new deploy when it
  // comes back to the foreground, at most hourly. A new worker only installs
  // and waits; it takes over on the next start.
  function keepChecking() {
    let last = Date.now();
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState !== "visible") return;
      if (Date.now() - last < 3600 * 1000) return;
      last = Date.now();
      checkForNewBuild();
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
