{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {
    // CanvasKit from this origin (build/web/canvaskit/), not the gstatic
    // CDN: the Content-Security-Policy runs no script from another origin.
    canvasKitBaseUrl: "canvaskit/",
  },
});
