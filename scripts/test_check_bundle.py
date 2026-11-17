"""Regression fixtures only: these are not compiled or installable applications."""
import contextlib
import io
import pathlib
import plistlib
import tempfile
import unittest
import zipfile

from check_bundle import check_path


class BundleValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.app = self.root / 'Payload/CotoveleiraInteligente.app'
        self.widget = self.app / 'PlugIns/WorkoutWidget.appex'
        for bundle, identifier, kind in (
            (self.app, 'br.edu.tcc.cotoveleira', 'APPL'),
            (self.widget, 'br.edu.tcc.cotoveleira.activity', 'XPC!'),
        ):
            bundle.mkdir(parents=True, exist_ok=True)
            info = dict(CFBundleIdentifier=identifier, CFBundleExecutable='Fixture',
                        CFBundleName='Fixture', CFBundlePackageType=kind,
                        CFBundleVersion='3', CFBundleShortVersionString='1.0.0',
                        MinimumOSVersion='18.0', CFBundleSupportedPlatforms=['iPhoneOS'])
            if kind == 'APPL':
                info.update(UILaunchScreen={}, NSBluetoothAlwaysUsageDescription='Bluetooth',
                            UIBackgroundModes=['bluetooth-central'], NSSupportsLiveActivities=True)
            else:
                info['NSExtension'] = {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}
            (bundle / 'Info.plist').write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            (bundle / 'Fixture').write_bytes(b'fixture, not Mach-O')

    def change_widget(self, key, value):
        path = self.widget / 'Info.plist'
        info = plistlib.loads(path.read_bytes())
        if value is None:
            del info[key]
        else:
            info[key] = value
        path.write_bytes(plistlib.dumps(info))

    def validate(self, path):
        with contextlib.redirect_stdout(io.StringIO()):
            check_path(path)

    def package(self):
        ipa = self.root / 'fixture.ipa'
        with zipfile.ZipFile(ipa, 'w') as archive:
            for path in self.app.rglob('*'):
                if path.is_file():
                    archive.write(path, path.relative_to(self.root).as_posix())
        return ipa

    def test_valid_app_and_ipa_metadata(self):
        self.validate(self.app)
        self.validate(self.package())

    def test_missing_widget_build_reproduces_original_failure(self):
        self.change_widget('CFBundleVersion', None)
        for path in (self.app, self.package()):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
                self.validate(path)

    def test_invalid_or_unresolved_versions(self):
        for value in ('', '$(CURRENT_PROJECT_VERSION)', 'abc', 3):
            with self.subTest(value=value):
                self.change_widget('CFBundleVersion', value)
                with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
                    self.validate(self.app)

    def test_versions_must_match(self):
        for key, value in (('CFBundleVersion', '4'), ('CFBundleShortVersionString', '1.0.1')):
            with self.subTest(key=key):
                self.change_widget(key, value)
                with self.assertRaisesRegex(ValueError, 'differs from containing app'):
                    self.validate(self.app)
                self.change_widget(key, '3' if key == 'CFBundleVersion' else '1.0.0')

    def test_missing_extension(self):
        self.widget.rename(self.widget.with_suffix('.removed'))
        with self.assertRaisesRegex(ValueError, 'Missing embedded WorkoutWidget'):
            self.validate(self.app)

    def test_missing_executable(self):
        (self.widget / 'Fixture').unlink()
        with self.assertRaisesRegex(ValueError, 'missing executable'):
            self.validate(self.app)

    def test_invalid_identifier(self):
        self.change_widget('CFBundleIdentifier', 'other.widget')
        with self.assertRaisesRegex(ValueError, 'identifier must be prefixed'):
            self.validate(self.app)

    def test_wrong_ipa_structure(self):
        ipa = self.root / 'wrong.ipa'
        with zipfile.ZipFile(ipa, 'w') as archive:
            archive.writestr('Wrong/Info.plist', b'wrong')
        with self.assertRaisesRegex(ValueError, 'Payload'):
            self.validate(ipa)


if __name__ == '__main__':
    unittest.main()
