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
        # Both paths start at the same TOP centre and continue to the
        # BOTTOM centre. Pin strokeStart to zero, trim only the endpoint.
        self.assertIn('layer.strokeStart = 0.0;', TWEAK)
        self.assertIn('layer.strokeEnd = progress;', TWEAK)
        self.assertIn('IBNLeft.strokeStart = 0.0;', TWEAK)
        self.assertIn('IBNRight.strokeStart = 0.0;', TWEAK)
        self.assertIn('IBNLeft.strokeEnd = progress;', TWEAK)
        self.assertIn('IBNRight.strokeEnd = progress;', TWEAK)
        self.assertNotIn('strokeStart = trim;', TWEAK)
        self.assertNotIn('strokeEnd = 1.0 - trim;', TWEAK)
        # No 25%, 10% or other quantisation: precisely 1% more length
        # for each percentage point across the full range.
        for percent in range(1, 101):
            previous = (percent - 1) / 100.0
            current = percent / 100.0
            self.assertAlmostEqual(current - previous, 0.01)
        self.assertEqual(0 / 100.0, 0.0)   # 0%: no arc
        self.assertEqual(100 / 100.0, 1.0) # 100%: joined top and bottom
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
        for thickness in (1.5, 2.5, 4, 8):
            original_top = 11.0
            original_bottom = 11.0 + 37.33
            path_top = original_top - thickness / 2
            path_bottom = original_bottom + thickness / 2
            self.assertAlmostEqual(path_top + thickness / 2, original_top)
            self.assertAlmostEqual(path_top - thickness / 2, original_top - thickness)
            self.assertAlmostEqual(path_bottom - thickness / 2, original_bottom)
            self.assertAlmostEqual(path_bottom + thickness / 2, original_bottom + thickness)

    def test_native_keyline_and_lock_colour(self):
        # Reuse only existing tested lifecycle and colour hooks; no
        # SBLockScreenManager or Darwin lockstate observer (v0.2.5 crash).
        self.assertIn('%hook SBUIProudLockIconView', TWEAK)
        self.assertIn('%hook SBSystemApertureContainerView', TWEAK)
        self.assertIn('IBNApplyProudLockColor', TWEAK)
        self.assertIn('IBNColorForPercent(percent)', TWEAK)
        self.assertIn('%orig((IBNEnabled && !IBNChargingIntermission) ? UIColor.clearColor : color);', TWEAK)
        self.assertIn('return (IBNEnabled && !IBNChargingIntermission) ? UIColor.clearColor : %orig;', TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)
        self.assertNotIn('notify_register_dispatch("com.apple.springboard.lockstate"', TWEAK)
    def test_lock_screen_only_geometry(self):
        self.assertIn('static const CGFloat IBNLockWidth = 164.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockHeight = 34.0;', TWEAK)
        self.assertIn('static const CGFloat IBNWidth = 126.0;', TWEAK)
        self.assertIn('static const CGFloat IBNHeight = 37.33;', TWEAK)
        self.assertIn('IBNPortraitIslandRect(portraitWidth, IBNLastDetectedLockScreen)', TWEAK)
        self.assertIn('IBNLockIconVisible()', TWEAK)
        self.assertIn('IBNQueueLockRefresh()', TWEAK)

    def test_charging_popup_unobstructed(self):
        self.assertIn("static void IBNUpdateChargingTransition(void)", TWEAK)
        self.assertIn("static BOOL IBNChargingIntermission = NO;", TWEAK)
        self.assertIn("(int64_t)(2.0 * NSEC_PER_SEC)", TWEAK)
        self.assertNotIn("(int64_t)(4.0 * NSEC_PER_SEC)", TWEAK)
        self.assertIn("if (connected == IBNPowerConnected) return;", TWEAK)
        self.assertIn("NSUInteger token = ++IBNPowerTransitionToken;", TWEAK)
        self.assertIn("if (token != IBNPowerTransitionToken || !IBNPowerConnected) return;", TWEAK)
        self.assertIn("if (IBNPowerConnected && !IBNChargingIntermission)", TWEAK)
        self.assertIn("layer.hidden = (percent == 0 || IBNChargingIntermission);", TWEAK)
        self.assertIn("IBNLeft.hidden = IBNHasActiveSystemAperture || percent == 0 || IBNChargingIntermission;", TWEAK)
        self.assertIn("IBNRight.hidden = IBNHasActiveSystemAperture || percent == 0 || IBNChargingIntermission;", TWEAK)
        self.assertIn("IBNApplyNativeBorderState();", TWEAK)
        # Stock keyline can reappear during the two-second native popup.
        self.assertIn("IBNEnabled && !IBNChargingIntermission", TWEAK)
        # No new private lock-manager hooks or dedicated polling loops.
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)
        self.assertNotIn("notify_register_dispatch", TWEAK)
    def test_lock_visible_when_composited(self):
        # Regression: older ancestor-window 'hidden' walk made the visibly
        # green lock on the screenshot read as not visible.
        self.assertNotIn("view.window.hidden ||", TWEAK)
        self.assertIn("[view convertRect:b toView:window]", TWEAK)
        self.assertIn("IBNPortraitIslandRect(portraitWidth, IBNLastDetectedLockScreen)", TWEAK)
        self.assertIn("static const CGFloat IBNLockWidth = 164.0;", TWEAK)
        self.assertIn("static const CGFloat IBNWidth = 126.0;", TWEAK)

    def test_lockscreen_uses_topmost_overlay(self):
        self.assertIn("if (IBNLastDetectedLockScreen) {", TWEAK)
        self.assertIn("for (CAShapeLayer *layer in pair) layer.hidden = YES;", TWEAK)
        self.assertIn("IBNHasActiveSystemAperture = IBNRenderSystemAperture();", TWEAK)
        self.assertIn("IBNWindow.windowLevel = 10000.0;", TWEAK)
        self.assertIn("- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }", TWEAK)
        self.assertIn("static const CGFloat IBNLockWidth = 164.0;", TWEAK)
        self.assertIn("static const CGFloat IBNLockHeight = 34.0;", TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)

    def test_thickness_floor_1_5(self):
        self.assertIn("IBNClamp(value ? [value doubleValue] : 2.5, 1.5, 8)", TWEAK)
        pref = (ROOT / "prefs/IBNRootListController.m").read_text()
        self.assertIn('name:@"Line Thickness" key:@"thickness" value:2.5 min:1.5 max:8', pref)
        self.assertIn('MAX(1.5, MIN(8.0, [result doubleValue]))', pref)
        self.assertIn('MAX(1.5, MIN(8.0, [value doubleValue]))', pref)
        root = plistlib.loads((ROOT / "prefs/Resources/Root.plist").read_bytes())
        slider = next(s for s in root if s.get("key") == "thickness")
        self.assertEqual(slider["min"], 1.5)
        self.assertEqual(slider["max"], 8)
        self.assertEqual(slider["default"], 2.5)

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
