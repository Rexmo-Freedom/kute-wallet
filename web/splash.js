// Called by flutter_native_splash when the first frame is up (moved out
// of index.html so the Content-Security-Policy needs no inline script).
function removeSplashFromWeb() {
  document.getElementById("splash")?.remove();
  document.getElementById("splash-branding")?.remove();
  // The body keeps a colour: iOS 26 Safari paints its bars from it, and a
  // transparent body gives black bars in dark mode. The app sets its own
  // edge colour on it (lib/platform/web_edge_colors_web.dart).
}
