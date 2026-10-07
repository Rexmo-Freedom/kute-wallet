"""Create build configuration without ever overwriting a developer's files."""
import json
import os
from pathlib import Path
import sys

APP_ID = 'com.kutewallet.app'
FILES = ('.env', 'lib/firebase_options.dart', 'android/app/google-services.json')


def configurations(mode):
    if mode == 'fixture':
        return (
            'BACKEND=https://backend.invalid\nAPP_STORE_ID=0\n',
            "import 'package:firebase_core/firebase_core.dart';\n"
            'class DefaultFirebaseOptions {\n'
            '  static const currentPlatform = FirebaseOptions(\n'
            "    apiKey: 'ci-placeholder-not-a-real-api-key',\n"
            "    appId: '1:123456789:android:0000000000000000',\n"
            "    messagingSenderId: '123456789',\n"
            "    projectId: 'kute-ci-placeholder',\n"
            '  );\n}\n',
            json.dumps({
                'project_info': {'project_number': '123456789', 'project_id': 'kute-ci-placeholder'},
                'client': [{
                    'client_info': {'mobilesdk_app_id': '1:123456789:android:0000000000000000',
                                    'android_client_info': {'package_name': APP_ID}},
                    'api_key': [{'current_key': 'ci-placeholder-not-a-real-api-key'}],
                }],
                'configuration_version': '1',
            }),
        )
    if mode != 'release':
        raise ValueError('Expected fixture or release')
    names = ('ENV_FILE', 'FIREBASE_OPTIONS', 'GOOGLE_SERVICES_JSON')
    values = tuple(os.environ.get(name, '').strip() for name in names)
    if not all(values):
        raise ValueError('Release requires ENV_FILE, FIREBASE_OPTIONS, GOOGLE_SERVICES_JSON')
    if 'class DefaultFirebaseOptions' not in values[1]:
        raise ValueError('FIREBASE_OPTIONS does not declare DefaultFirebaseOptions')
    config = json.loads(values[2])
    if not any(c.get('client_info', {}).get('android_client_info', {}).get('package_name') == APP_ID
               for c in config.get('client', [])):
        raise ValueError('Firebase configuration has the wrong Android application ID')
    return values


def write_configuration(root, mode):
    values = configurations(mode)
    paths = [root / name for name in FILES]
    if any(path.exists() or path.is_symlink() for path in paths):
        raise ValueError('Refusing to overwrite existing configuration; use a clean checkout')
    for path, value in zip(paths, values):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('x') as file:
            file.write(value + '\n')
        path.chmod(0o600)


if __name__ == '__main__':
    try:
        write_configuration(Path.cwd(), sys.argv[1])
    except (ValueError, IndexError, json.JSONDecodeError) as error:
        raise SystemExit(str(error)) from None
