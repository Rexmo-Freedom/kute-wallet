"""Fail closed on missing artifacts, invalid signatures or an unexpected signer."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def normalized_fingerprint(value):
    result = value.replace(':', '').strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', result):
        raise ValueError('ANDROID_SIGNING_CERT_SHA256 must be a SHA-256 certificate fingerprint')
    return result


def check_fingerprint(actual, expected):
    if normalized_fingerprint(actual) != normalized_fingerprint(expected):
        raise ValueError('Artifact signer does not match the approved release certificate')


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        # Never print full command lines or signing-tool diagnostics containing credentials.
        raise ValueError(f'{Path(args[0]).name} verification failed')
    return result.stdout


def verify_apk(path, expected, metadata):
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
    output = run(str(tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(path))
    fingerprints = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (\w+)$', output, re.M)
    if len(fingerprints) != 1:
        raise ValueError('APK must have exactly one approved current signer')
    check_fingerprint(fingerprints[0], expected)
    badging = run(str(tools / 'aapt2'), 'dump', 'badging', str(path))
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != ('com.kutewallet.app', metadata['build'], metadata['version']):
        raise ValueError('APK package/version differs from the reviewed release')
    if 'application-debuggable' in badging:
        raise ValueError('Refusing to distribute a debuggable APK')


def package():
    expected = normalized_fingerprint(os.environ['ANDROID_SIGNING_CERT_SHA256'])
    metadata = json.loads(Path('release-metadata.json').read_text())
    source = Path('build/app/outputs/flutter-apk/app-release.apk')
    if not source.is_file() or source.stat().st_size == 0:
        raise ValueError('Missing release APK')
    verify_apk(source, expected, metadata)
    dest = Path('release')
    dest.mkdir(exist_ok=False)
    metadata['signing_certificate_sha256'] = expected
    name = f"kute-{metadata['version']}+{metadata['build']}.apk"
    shutil.copyfile(source, dest / name)
    metadata['artifacts'] = [name]
    (dest / 'release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    files = sorted(dest.iterdir())
    checksums = []
    for path in files:
        digest = hashlib.sha256()
        with path.open('rb') as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b''):
                digest.update(chunk)
        checksums.append(f'{digest.hexdigest()}  {path.name}\n')
    (dest / 'SHA256SUMS').write_text(''.join(checksums))


if __name__ == '__main__':
    try:
        package()
    except (ValueError, KeyError, IndexError) as error:
        raise SystemExit(str(error)) from None
