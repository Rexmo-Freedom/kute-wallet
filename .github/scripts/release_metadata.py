"""Derive immutable release coordinates from reviewed source, never free-form input."""
import json
import os
from pathlib import Path
import re
import subprocess


def parse_version(contents):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+([1-9]\d*)\s*$', contents, re.M)
    if not match:
        raise ValueError('pubspec version must contain a semantic version and positive build number')
    version, build = match.groups()
    if int(build) > 2100000000:
        raise ValueError('Android versionCode exceeds the supported maximum')
    return version, build


if __name__ == '__main__':
    version, build = parse_version(Path('pubspec.yaml').read_text())
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if sha != os.environ['GITHUB_SHA']:
        raise SystemExit('Checkout differs from the reviewed workflow commit')
    metadata = {'version': version, 'build': build, 'tag': f'v{version}+{build}', 'sha': sha}
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in metadata.items():
            output.write(f'{key}={value}\n')
    Path('release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
