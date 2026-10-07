"""Safety regressions for configuration and release verification."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from configure import FILES, configurations, write_configuration
from release_metadata import parse_version
from verify_android import check_fingerprint, normalized_fingerprint, package, verify_apk

CERT = 'ab' * 32


class ConfigurationTests(unittest.TestCase):
    def test_fixture_needs_no_secrets_and_matches_android_package(self):
        with patch.dict(os.environ, {}, clear=True), tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_configuration(root, 'fixture')
            self.assertIn('DefaultFirebaseOptions', (root / FILES[1]).read_text())
            self.assertEqual('com.kutewallet.app', json.loads((root / FILES[2]).read_text())[
                'client'][0]['client_info']['android_client_info']['package_name'])
            self.assertEqual(0o600, (root / FILES[0]).stat().st_mode & 0o777)

    def test_existing_developer_file_is_preserved_without_partial_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / FILES[1]).write_text('keep local config')
            with self.assertRaises(ValueError):
                write_configuration(root, 'fixture')
            self.assertEqual('keep local config', (root / FILES[1]).read_text())
            self.assertFalse((root / '.env').exists())

    def test_release_rejects_empty_settings(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
            configurations('release')

    def test_release_rejects_wrong_application(self):
        settings = dict(zip(('ENV_FILE', 'FIREBASE_OPTIONS', 'GOOGLE_SERVICES_JSON'), configurations('fixture')))
        settings['GOOGLE_SERVICES_JSON'] = settings['GOOGLE_SERVICES_JSON'].replace('com.kutewallet.app', 'other.app')
        with patch.dict(os.environ, settings), self.assertRaises(ValueError):
            configurations('release')


class VersionTests(unittest.TestCase):
    def test_build_number_is_required(self):
        for value in ('version: 1.2.3', 'version: 1.2.3+0', 'version: 1.2.3+9999999999', 'version: $(whoami)+1'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse_version(value)

    def test_version_and_build_are_preserved(self):
        self.assertEqual(('2.0.4', '77'), parse_version('name: kute\nversion: 2.0.4+77\n'))


class SigningTests(unittest.TestCase):
    def test_fingerprint_is_exact_and_normalized(self):
        self.assertEqual(CERT, normalized_fingerprint(':'.join(['AB'] * 32)))
        check_fingerprint(CERT, CERT)
        with self.assertRaises(ValueError):
            check_fingerprint(CERT, 'cd' * 32)
        with self.assertRaises(ValueError):
            normalized_fingerprint('')

    @patch.dict(os.environ, {'ANDROID_HOME': '/sdk'})
    def test_apk_rejects_wrong_signer_and_debug_build(self):
        metadata = {'version': '2.0.4', 'build': '77'}
        with patch('verify_android.run', return_value='Signer #1 certificate SHA-256 digest: ' + 'cd' * 32):
            with self.assertRaises(ValueError):
                verify_apk(Path('app.apk'), CERT, metadata)
        with patch('verify_android.run') as command:
            command.side_effect = [f'Signer #1 certificate SHA-256 digest: {CERT}',
                                   "package: name='com.kutewallet.app' versionCode='77' versionName='2.0.4'\napplication-debuggable"]
            with self.assertRaises(ValueError):
                verify_apk(Path('app.apk'), CERT, metadata)

    def test_missing_apk_does_not_package_a_release(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'ANDROID_SIGNING_CERT_SHA256': CERT}):
            try:
                os.chdir(directory)
                Path('release-metadata.json').write_text(json.dumps({'version': '2.0.4', 'build': '77'}))
                with self.assertRaises(ValueError):
                    package()
                self.assertFalse(Path('release').exists())
            finally:
                os.chdir(previous)

    def test_verified_apk_and_source_metadata_have_matching_checksums(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'ANDROID_SIGNING_CERT_SHA256': CERT}):
            try:
                os.chdir(directory)
                Path('release-metadata.json').write_text(json.dumps({'version': '2.0.4', 'build': '77', 'sha': 'a' * 40}))
                apk = Path('build/app/outputs/flutter-apk/app-release.apk')
                apk.parent.mkdir(parents=True)
                apk.write_bytes(b'verified fixture bytes')
                with patch('verify_android.verify_apk') as verify:
                    package()
                verify.assert_called_once()
                for entry in Path('release/SHA256SUMS').read_text().splitlines():
                    digest, name = entry.split('  ')
                    self.assertEqual(digest, hashlib.sha256((Path('release') / name).read_bytes()).hexdigest())
                metadata = json.loads(Path('release/release-metadata.json').read_text())
                self.assertEqual(['kute-2.0.4+77.apk'], metadata['artifacts'])
                self.assertEqual(CERT, metadata['signing_certificate_sha256'])
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
