// Called by flutter_native_splash when the first frame is up (moved out
// of index.html so the Content-Security-Policy needs no inline script).
function removeSplashFromWeb() {
  document.getElementById("splash")?.remove();
  document.getElementById("splash-branding")?.remove();
  document.body.style.background = "transparent";
}
