/// The words of the laptop browser's password lock (unlock_secret.dart),
/// English only for now, in one place so they are easy to move into the
/// ARB files later.
library;

abstract final class PasswordCopy {
  static const String create = 'Create a password';
  static const String confirm = 'Confirm your password';
  static const String enter = 'Enter your password';
  static const String rule = 'At least 10 characters';
  static const String mismatch = "Passwords don't match";
  static const String wrong = 'Wrong password';
  static const String forgot = 'Forgot your password?';
  static const String settingsTitle = 'App password';
  static const String settingsSubtitle = 'Change your password';
  static const String hint = 'Password';
  static const String show = 'Show password';
  static const String hide = 'Hide password';
  static const String enterCurrent = 'Enter your current password';
  static const String createNew = 'Create a new password';
  static const String updated = 'Password updated';
  static const String setPassword = 'Set password';
  static const String typeAgain = 'Type your password again';
  static const String needPassword = 'Enter your password';
  static const String sheetLocked =
      'Too many wrong passwords. Kute is locked for now.';
  static const String saveFailed =
      "Couldn't save your password. Please try again.";

  /// The one-time upgrade of a PIN vault in a laptop browser.
  static const String upgradeNotice =
      'This browser now locks with a password instead of the PIN.';
}
