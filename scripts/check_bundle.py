"""Validate built iPhone .app or IPA metadata; does not verify code signatures."""
import argparse
import pathlib
import plistlib
import re
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bundle_info(bundle, package_type):
    with (bundle / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleName',
                'CFBundleVersion', 'CFBundleShortVersionString'):
        value = info.get(key)
        require(isinstance(value, str) and value.strip() and '$' not in value,
                f'{bundle}: missing, invalid or unresolved {key}')
    require(re.fullmatch(r'[1-9][0-9]{0,3}(?:\.[0-9]{1,2}){0,2}', info['CFBundleVersion']),
            f'{bundle}: invalid CFBundleVersion')
    require(re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', info['CFBundleShortVersionString']),
            f'{bundle}: invalid CFBundleShortVersionString')
    require(info.get('CFBundlePackageType') == package_type,
            f'{bundle}: expected package type {package_type}')
    executable = info['CFBundleExecutable']
    require('/' not in executable and '\\' not in executable and executable not in ('.', '..'),
            f'{bundle}: invalid executable name')
    require((bundle / executable).is_file(), f'{bundle}: missing executable {executable}')
    require(info.get('MinimumOSVersion') == '18.0', f'{bundle}: unexpected deployment target')
    require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'],
            f'{bundle}: expected iPhoneOS device build')
    return info


def check_app(bundle):
    info = bundle_info(bundle, 'APPL')
    require('UILaunchScreen' in info or info.get('UILaunchStoryboardName'),
            'Missing native launch configuration')
    require(info.get('NSBluetoothAlwaysUsageDescription'), 'Missing Bluetooth permission description')
    require('bluetooth-central' in info.get('UIBackgroundModes', []), 'Missing BLE background mode')
    require(info.get('NSSupportsLiveActivities') is True, 'Missing Live Activities support')
    plugins = bundle / 'PlugIns'
    require(plugins.is_dir(), 'Missing embedded PlugIns directory')
    extensions = sorted((p for p in plugins.iterdir() if p.name.endswith('.appex')), key=lambda p: p.name)
    require(any(p.name == 'WorkoutWidget.appex' for p in extensions), 'Missing embedded WorkoutWidget.appex')
    for extension in extensions:
        widget = bundle_info(extension, 'XPC!')
        require(widget['CFBundleIdentifier'].startswith(info['CFBundleIdentifier'] + '.'),
                f'{extension}: identifier must be prefixed by app identifier')
        for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
            require(widget[key] == info[key], f'{extension}: {key} differs from containing app')
        if extension.name == 'WorkoutWidget.appex':
            require(widget.get('NSExtension', {}).get('NSExtensionPointIdentifier') ==
                    'com.apple.widgetkit-extension', 'Invalid WidgetKit extension point')
    print(f'App and {len(extensions)} extension(s): version {info["CFBundleShortVersionString"]}, '
          f'build {info["CFBundleVersion"]}; metadata, executable presence and embedding verified')
    print('Code signatures/provisioning and installation NOT verified; unsigned IPA requires re-signing.')


def check_path(path):
    if path.is_dir():
        check_app(path)
        return
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP entries')
        require(all(not n.startswith('/') and '\\' not in n and
                    '..' not in pathlib.PurePosixPath(n).parts for n in names), 'Unsafe ZIP path')
        require(archive.testzip() is None, 'Corrupt ZIP entry')
        payload = zipfile.Path(archive) / 'Payload'
        require(payload.is_dir(), 'Missing top-level Payload directory')
        apps = [p for p in payload.iterdir() if p.name.endswith('.app') and p.is_dir()]
        require(len(apps) == 1, 'Expected exactly one Payload/*.app')
        check_app(apps[0])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=pathlib.Path, help='Built .app directory or .ipa file')
    args = parser.parse_args()
    try:
        check_path(args.bundle)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Bundle validation failed: {error}\n')
