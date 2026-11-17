"""Source contract checks runnable on Windows; does not replace compilation/hardware tests."""
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FW = (ROOT / 'CotoveleiraESP32-Serial.ino').read_text(encoding='utf-8')
APP = (ROOT / 'Cotoveleira/Services/Bluetooth/BluetoothManager.swift').read_text(encoding='utf-8')
FEEDBACK = (ROOT / 'Cotoveleira/Services/WorkoutFeedback.swift').read_text(encoding='utf-8')

class IntegrationContract(unittest.TestCase):
    def test_uuids_match(self):
        pattern = r'4F1B000[1-7]-274C-4F4D-8D63-7A7F0C010001'
        self.assertEqual(set(re.findall(pattern, FW)), set(re.findall(pattern, APP)))
        self.assertEqual(len(set(re.findall(pattern, FW))), 7)

    def test_hardware_and_power_gates(self):
        for token in ['PIN_FLEX = 34', 'PIN_BAT = 35', 'Serial.begin(115200)',
                      'if (powered) processFlex(now)', 'powered && diagnostics && connected',
                      'powered ? 5000UL : 60000UL', 'flexStraight = 2570', 'flexBent = 570']:
            self.assertIn(token, FW)
        self.assertNotRegex(FW.lower(), r'oled|buzzer|ledc|ssd1306|u8g2')

    def test_packet_sizes_and_filters(self):
        self.assertIn('bytes.count == 18', APP)
        self.assertIn('bytes.count == 7', FEEDBACK)
        self.assertIn('event.sequence &- sequence', FEEDBACK)
        for token in ['int samples[40]', 'i = 10; i < 30', '0.15f', '>= 30',
                      'FLEX_ESTENDIDO_ESTAVEL_MS = 100', 'FLEX_DOBRA_MIN_MS = 350',
                      'FLEX_INTERVALO_MIN_MS = 1000']:
            self.assertIn(token, FW)

    def test_correct_event_and_unchanged_wire_layout(self):
        emitter = FW.split('void emitEvent(uint8_t type, uint8_t reason) {', 1)[1].split('\n}', 1)[0]
        self.assertIn('uint8_t p[] = {1, type, reason, uint8_t(eventSeq), uint8_t(eventSeq >> 8), uint8_t(eventSeq >> 16), uint8_t(eventSeq >> 24)};', emitter)
        correct = FW.split('void repetitionCorrect(uint32_t now) {', 1)[1].split('\n}', 1)[0]
        self.assertEqual(correct.count('emitEvent(5, 0);'), 1)
        self.assertLess(correct.index('emitEvent(5, 0);'), correct.index('if (repetitions >= targetReps)'))
        self.assertIn('emitEvent(2, 0);', correct)
        self.assertIn('emitEvent(4, 0);', correct)
        self.assertIn('(1...5).contains(bytes[1])', FEEDBACK)
        self.assertIn('case Self.eventID:', APP)
        self.assertIn('didUpdateNotificationStateFor', APP)

    def test_metadata(self):
        info = plistlib.loads((ROOT / 'Cotoveleira/Resources/Info.plist').read_bytes())
        self.assertIn('bluetooth-central', info['UIBackgroundModes'])
        self.assertTrue(info['NSSupportsLiveActivities'])
        widget = plistlib.loads((ROOT / 'WorkoutWidget/Info.plist').read_bytes())
        self.assertEqual(widget['NSExtension']['NSExtensionPointIdentifier'], 'com.apple.widgetkit-extension')
        for metadata in (info, widget):
            self.assertEqual(metadata['CFBundleVersion'], '$(CURRENT_PROJECT_VERSION)')
            self.assertEqual(metadata['CFBundleShortVersionString'], '$(MARKETING_VERSION)')
        self.assertEqual(widget['CFBundlePackageType'], 'XPC!')
        self.assertEqual(widget['CFBundleExecutable'], '$(EXECUTABLE_NAME)')
        self.assertEqual(widget['CFBundleIdentifier'], '$(PRODUCT_BUNDLE_IDENTIFIER)')
        project = (ROOT / 'project.yml').read_text(encoding='utf-8')
        self.assertEqual(re.findall(r"CURRENT_PROJECT_VERSION: '([^']+)'", project), ['3'])
        self.assertEqual(re.findall(r"MARKETING_VERSION: '([^']+)'", project), ['1.0.0'])

if __name__ == '__main__':
    unittest.main()
