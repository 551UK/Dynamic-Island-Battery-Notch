"""Final release regression tests; manual device behavior already confirmed."""
import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TWEAK = (ROOT / "Tweak.xm").read_text()
GEOMETRY = (ROOT / "IBNGeometry.m").read_text()
HEADER = (ROOT / "IBNGeometry.h").read_text()
PREFS = (ROOT / "prefs/IBNRootListController.m").read_text()
MAKEFILE = (ROOT / "Makefile").read_text()
CONTROL = (ROOT / "control").read_text()
WORKFLOW = (ROOT / ".github/workflows/build.yml").read_text()

class FinalReleaseTests(unittest.TestCase):
    def test_release_version_and_package_id(self):
        self.assertIn("Version: 0.3.0", CONTROL)
        self.assertIn("Package: com.551.islandbatterynotch", CONTROL)
        self.assertIn("Name: Dynamic Island Battery Notch", CONTROL)
        info = plistlib.loads((ROOT / "prefs/Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "0.3.0")
        self.assertIn('test "$(dpkg-deb -f "$deb" Version)" = "0.3.0"', WORKFLOW)
        self.assertIn('gh release view v0.3.0', WORKFLOW)

    def test_remove_diagnostics_from_source_and_settings(self):
        self.assertFalse((ROOT / "IBNDiagnostics.m").exists())
        self.assertFalse((ROOT / "IBNDiagnostics.h").exists())
        self.assertFalse((ROOT / "DIAGNOSTICS.md").exists())
        for source in (TWEAK, GEOMETRY, HEADER, PREFS, MAKEFILE, CONTROL):
            for forbidden in ("IBNDiag", "diag.start", "diag.stop", 
                              "Start Diagnostic", "Stop Diagnostic",
                              "Share Diagnostic", "DYNAMIC ISLAND DIAGNOSTICS"):
                self.assertNotIn(forbidden, source)

    def test_native_autofit_always_enabled(self):
        self.assertIn("IslandBatteryNotch_FILES = Tweak.xm IBNGeometry.m", MAKEFILE)
        self.assertIn("IBNGeometryConfigure(^{ IBNRefresh(); });", TWEAK)
        self.assertIn("IBNGeometryExpandedRect(aperture, window)", TWEAK)
        self.assertIn("if (!CGRectIsNull(candidate)) rect = candidate;", TWEAK)
        self.assertIn("IBNGeometryApertureDidLayout(self)", TWEAK)
        self.assertIn("if (self.window && !CGRectEqualToRect(before, self.frame))", TWEAK)
        self.assertIn("void IBNGeometryConfigure(dispatch_block_t refresh);", HEADER)
        for source in (TWEAK, GEOMETRY, HEADER, PREFS):
            for forbidden in ("IBNAutoFitExpanded", "autoFitExpanded",
                              "AUTOMATIC ISLAND RESIZE", "Auto Resize All Island States"):
                self.assertNotIn(forbidden, source)

    def test_geometry_tracks_real_capsule_and_animation(self):
        for needle in ("SBSystemApertureContainerView",
                       "[aperture convertRect:aperture.bounds toView:window]",
                       "aperture.layer.presentationLayer",
                       "IBNGeometryModelRect(aperture, aperture.window)",
                       "CGRectGetWidth(rect) < 145.0",
                       "displayLinkWithTarget:",
                       "IBNGeometryLinkUntil = now + 1.5"):
            self.assertIn(needle, GEOMETRY)
        self.assertNotIn("IBNGeometryDescribe", GEOMETRY)

    def test_no_manual_recording_call_delays(self):
        for forbidden in ("CallKit", "IBNCallActive", "IBNRecordingExpanded",
                          "IBNCountdownExpanded", "IBNRecordingStopIntermission",
                          "IBNChargingIntermission", "IBNRecordingWidth",
                          "IBNActiveRecordingWidth", "dispatch_after(",
                          "%group IBNCountdownHooks", "ReplayKit"):
            self.assertNotIn(forbidden, TWEAK)
        self.assertNotIn("CallKit", MAKEFILE)
        self.assertIn("layer.hidden = (percent == 0);", TWEAK)
        self.assertIn("IBNLeft.hidden = IBNHasActiveSystemAperture || percent == 0;", TWEAK)
        self.assertIn("IBNRight.hidden = IBNHasActiveSystemAperture || percent == 0;", TWEAK)

    def test_known_good_fallback_and_lock_screen(self):
        self.assertIn("static const CGFloat IBNWidth = 126.0;", TWEAK)
        self.assertIn("static const CGFloat IBNLockWidth = 164.0;", TWEAK)
        self.assertIn("static const CGFloat IBNLockHeight = 34.0;", TWEAK)
        self.assertIn("return IBNLastDetectedLockScreen;", TWEAK)
        self.assertIn("IBNLockIconVisible()", TWEAK)
        self.assertIn("IBNApplyAllLockColors()", TWEAK)

    def test_battery_percentage_and_colours(self):
        for needle in ("lround(IBNClamp(device.batteryLevel, 0, 1) * 100)",
                       "layer.strokeStart = 0.0;", "layer.strokeEnd = progress;",
                       "IBNLeft.strokeEnd = progress;", "IBNRight.strokeEnd = progress;",
                       "if (percent <= 20)", "if (percent <= 60)"):
            self.assertIn(needle, TWEAK)
        for i in range(1, 101):
            self.assertAlmostEqual(i/100-(i-1)/100, 0.01)

    def test_charging_configuration_preserved(self):
        for needle in ('IBNRead(@"chargingThickness")', 'IBNRead(@"chargingColor")',
                       'IBNRead(@"pulseCharging")', "IBNUpdatePowerState();",
                       "IBNUpdateChargingPulse(layer);", "fade.duration = 1.1;"):
            self.assertIn(needle, TWEAK)
        for needle in ("Charging Colour", "Pulsing Charging",
                       "Charging Line Thickness", "Line Thickness"):
            self.assertIn(needle, PREFS)

    def test_settings_and_icon_remain(self):
        for needle in ("Enabled", "Automatic battery colours", 
                       "Manual Outline Colour", "Charging Colour",
                       "Pulsing Charging", "Line Thickness",
                       "Made by 551UK", "Project on GitHub",
                       "UIColorPickerViewController"):
            self.assertIn(needle, PREFS)
        self.assertIn("export THEOS_PACKAGE_SCHEME = rootless", MAKEFILE)
        self.assertIn("arm64 arm64e", MAKEFILE)
        self.assertIn('"iPhone15,3"', TWEAK)

    def test_release_and_branch_cleanup_after_verification(self):
        self.assertLess(WORKFLOW.index("Verify built package"),
                        WORKFLOW.index("Publish current DEB"))
        self.assertLess(WORKFLOW.index("Publish current DEB"),
                        WORKFLOW.index("Remove obsolete releases, tags and branches"))
        self.assertIn("gh release delete", WORKFLOW)
        self.assertIn("git/refs/heads/", WORKFLOW)

if __name__ == "__main__":
    unittest.main()
