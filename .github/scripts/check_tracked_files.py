"""Reject generated build output, local configuration and signing material in Git."""
from pathlib import PurePosixPath
import subprocess


def blocked(name):
    path = PurePosixPath(name)
    generated = {'.dart_tool', '.gradle', '.idea', '.claude', 'node_modules', 'coverage', 'build'}
    private_names = {'.env', 'key.properties', 'google-services.json', 'GoogleService-Info.plist',
                     'firebase_options.dart', '.DS_Store'}
    return (bool(generated.intersection(path.parts)) or path.name in private_names
            or path.suffix.lower() in {'.jks', '.keystore', '.p12', '.pfx', '.apk', '.aab', '.ipa'})


if __name__ == '__main__':
    files = subprocess.check_output(['git', 'ls-files', '-z'], text=True).split('\0')
    failures = sorted(name for name in files if name and blocked(name))
    if failures:
        raise SystemExit('Remove tracked local/generated/private artifacts:\n' + '\n'.join(failures))
