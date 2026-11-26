/// Whether this browser can run a WebAuthn sign-in silently: "immediate"
/// mediation (`PublicKeyCredential.getClientCapabilities().immediateGet`),
/// the same probe as the Breez web provider's `supportsImmediateMediation`.
/// Without it a sign-in always shows the browser's sheet, even with no
/// passkey saved ("You don't have any passkeys saved for this website").
/// False off the web (the phones have their own quiet mode).
library;

import 'webauthn_immediate_native.dart'
    if (dart.library.js_interop) 'webauthn_immediate_web.dart' as impl;

Future<bool> webauthnImmediateMediation() => impl.immediateMediation();
