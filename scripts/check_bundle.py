"""Fail CI if XcodeGen strips the metadata needed for native screen sizing/BLE."""
import pathlib
import plistlib
import sys

bundle = pathlib.Path(sys.argv[1])
with (bundle / 'Info.plist').open('rb') as source:
    info = plistlib.load(source)
assert 'UILaunchScreen' in info or info.get('UILaunchStoryboardName'), 'Missing native launch configuration'
assert info.get('NSBluetoothAlwaysUsageDescription'), 'Missing Bluetooth permission description'
assert str(info['CFBundleVersion']) == '2', 'Wrong build version'
assert info['MinimumOSVersion'] == '18.0', 'Unexpected deployment target'
print('Native launch configuration, Bluetooth permission and build version verified')
