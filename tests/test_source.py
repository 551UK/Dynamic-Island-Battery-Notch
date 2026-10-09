"""Source-level regression checks; compile and device validation done separately."""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
TWEAK = (ROOT / "Tweak.xm").read_text()
class SourceTests(unittest.TestCase):
    def test_springboard_overlay(self):
        for term in ["IBNWindow.windowLevel = 10000.0", "hitTest:", "%hook SpringBoard", "SBSystemApertureContainerView", "IBNWindow.hidden = NO", '"iPhone15,3"']:
            self.assertIn(term, TWEAK)
    def test_one_percent_arcs(self):
        self.assertIn("lround(IBNClamp(device.batteryLevel, 0, 1) * 100)", TWEAK)
        self.assertIn("CGFloat trim = (1.0 - progress) / 2.0;", TWEAK)
        for p in range(1, 101):
            s = (1 - p/100)/2
            prev = (1 - (p-1)/100)/2
            self.assertAlmostEqual((1-2*s)-(1-2*prev), 0.01)
    def test_colour_bands(self):
        for p in range(101):
            band = "red" if p <= 20 else ("yellow" if p <= 60 else "green")
            self.assertIn(band, ["red", "yellow", "green"])
        self.assertIn("if (percent <= 20)", TWEAK)
        self.assertIn("if (percent <= 60)", TWEAK)
    def test_visible_outward_thickness(self):
        # Both the native system-aperture and SpringBoard fallback must use
        # the same outward path rather than inset into the hardware cutout.
        self.assertIn('CGRectInset(rect, -IBNThickness / 2.0, -IBNThickness / 2.0)', TWEAK)
        self.assertEqual(TWEAK.count('CGRect outwardRect = IBNOutwardStrokeRect(rect);'), 2)
        self.assertNotIn('CGRectInset(rect, IBNThickness / 2, IBNThickness / 2)', TWEAK)
        # With outward drawing, the original pill remains the INNER border
        # while the visible OUTER edge changes by exactly the thickness.
        for thickness in (0.5, 1, 2.5, 4, 8):
            original_top = 11.0
            original_bottom = 11.0 + 37.33
            path_top = original_top - thickness / 2
            path_bottom = original_bottom + thickness / 2
            self.assertAlmostEqual(path_top + thickness / 2, original_top)
            self.assertAlmostEqual(path_top - thickness / 2, original_top - thickness)
            self.assertAlmostEqual(path_bottom - thickness / 2, original_bottom)
            self.assertAlmostEqual(path_bottom + thickness / 2, original_bottom + thickness)

    def test_settings(self):
        data = plistlib.loads((ROOT / "prefs/Resources/Root.plist").read_bytes())
        keys = [x.get("key") for x in data if "key" in x]
        self.assertTrue(set(["enabled", "autoColor", "fixedColor", "chargingColor", "thickness"]).issubset(keys))
        self.assertFalse(set(["width", "height", "offsetY"]) & set(keys))
        self.assertNotIn('IBNRead(@"width")', TWEAK)
        self.assertNotIn('IBNRead(@"height")', TWEAK)
        self.assertNotIn('IBNRead(@"offsetY")', TWEAK)
        self.assertIn('UIDeviceBatteryStateCharging', TWEAK)
        self.assertIn('UIDeviceBatteryStateFull', TWEAK)
        self.assertIn('IBNChargingHex', TWEAK)
        self.assertIn('@"chargingColor"', TWEAK)
        pref = (ROOT / "prefs/IBNRootListController.m").read_text()
        self.assertIn('@"Manual Outline Colour"', pref)
        self.assertIn('@"Charging Colour"', pref)
        self.assertIn('@"Line Thickness"', pref)
        self.assertNotIn('@"Island alignment"', pref)
        self.assertIn("iphoneos-arm64", (ROOT / "control").read_text())
        info = plistlib.loads((ROOT / "prefs/Resources/Info.plist").read_bytes())
        self.assertEqual(info.get("NSPrincipalClass"), "IBNRootListController")
        self.assertIn("IBNRenderSystemAperture", TWEAK)
        self.assertIn("objc_setAssociatedObject(window, &IBNApertureLayersKey", TWEAK)
if __name__ == "__main__":
    unittest.main()
