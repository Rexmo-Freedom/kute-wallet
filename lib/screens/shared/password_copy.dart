/// The words of a web vault made with a password (24 to 27 November 2026;
/// since then every new vault takes the PIN, unlock_secret.dart), English
/// only for now, in one place so they are easy to move into the ARB files
/// later.
library;

abstract final class PasswordCopy {
  static const String wrong = 'Wrong password';
  static const String forgot = 'Forgot your password?';
  static const String settingsTitle = 'App password';
  static const String hint = 'Password';
  static const String show = 'Show password';
  static const String hide = 'Hide password';
  static const String enterCurrent = 'Enter your current password';
  static const String needPassword = 'Enter your password';
  static const String sheetLocked =
      'Too many wrong passwords. Kute is locked for now.';
}
