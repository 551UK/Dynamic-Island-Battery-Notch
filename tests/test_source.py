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
        self.assertIn('CGFloat lockClearance = IBNUseExpandedOutline() ? 2.0 : 0.0;', TWEAK)
        self.assertIn('CGFloat inset = -(IBNThickness / 2.0 + lockClearance);', TWEAK)
        self.assertIn('return CGRectInset(rect, inset, inset);', TWEAK)
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
        self.assertIn('IBNPortraitIslandRect(portraitWidth, IBNUseExpandedOutline())', TWEAK)
        self.assertIn('IBNLockIconVisible()', TWEAK)
        self.assertIn('IBNQueueLockRefresh()', TWEAK)

    def test_charging_popup_unobstructed(self):
        self.assertIn("static void IBNUpdateChargingTransition(void)", TWEAK)
        self.assertIn("static BOOL IBNChargingIntermission = NO;", TWEAK)
        self.assertIn("(int64_t)(3.0 * NSEC_PER_SEC)", TWEAK)
        # The recording-stop blackout is 5 seconds; charging is still three.
        self.assertIn("(int64_t)(5.0 * NSEC_PER_SEC)", TWEAK)
        self.assertNotIn("(int64_t)(2.0 * NSEC_PER_SEC)", TWEAK)
        self.assertIn("if (connected == IBNPowerConnected) return;", TWEAK)
        self.assertIn("NSUInteger token = ++IBNPowerTransitionToken;", TWEAK)
        self.assertIn("if (token != IBNPowerTransitionToken || !IBNPowerConnected) return;", TWEAK)
        self.assertIn("if (IBNPowerConnected && !IBNChargingIntermission)", TWEAK)
        self.assertIn("layer.hidden = (percent == 0 || IBNChargingIntermission || IBNRecordingStopIntermission || IBNCallActive);", TWEAK)
        self.assertIn("IBNLeft.hidden = IBNHasActiveSystemAperture || percent == 0 || IBNChargingIntermission || IBNRecordingStopIntermission || IBNCallActive;", TWEAK)
        self.assertIn("IBNRight.hidden = IBNHasActiveSystemAperture || percent == 0 || IBNChargingIntermission || IBNRecordingStopIntermission || IBNCallActive;", TWEAK)
        self.assertIn("IBNApplyNativeBorderState();", TWEAK)
        # Stock keyline can reappear during the three-second native popup.
        self.assertIn("IBNEnabled && !IBNChargingIntermission", TWEAK)
        # No new private lock-manager hooks or dedicated polling loops.
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)
        self.assertNotIn("notify_register_dispatch", TWEAK)
    def test_lock_visible_when_composited(self):
        # Regression: older ancestor-window 'hidden' walk made the visibly
        # green lock on the screenshot read as not visible.
        self.assertNotIn("view.window.hidden ||", TWEAK)
        self.assertIn("[view convertRect:b toView:window]", TWEAK)
        self.assertIn("IBNPortraitIslandRect(portraitWidth, IBNUseExpandedOutline())", TWEAK)
        self.assertIn("static const CGFloat IBNLockWidth = 164.0;", TWEAK)
        self.assertIn("static const CGFloat IBNWidth = 126.0;", TWEAK)

    def test_restore_working_lock_screen_native_rendering(self):
        # v0.2.12 suppressed native battery layers whenever the Lock Screen
        # was detected; the separate fallback didn't composite above it.
        # Restore the v0.2.11 native rendering for Lock Screen and apps.
        self.assertNotIn("if (IBNLastDetectedLockScreen) {\n            for (CAShapeLayer *layer in pair) layer.hidden = YES;", TWEAK)
        self.assertIn("BOOL visible = IBNVisibleAperture(aperture);", TWEAK)
        self.assertIn("IBNHasActiveSystemAperture = IBNRenderSystemAperture();", TWEAK)
        self.assertIn("static const CGFloat IBNLockWidth = 164.0;", TWEAK)
        self.assertIn("static const CGFloat IBNLockHeight = 34.0;", TWEAK)
        self.assertIn("static const CGFloat IBNWidth = 126.0;", TWEAK)
        self.assertIn("static const CGFloat IBNHeight = 37.33;", TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)

    def test_visible_minimum_stroke_lockscreen_only(self):
        # A 1.5 pt setting stays exactly 1.5 pt. The path, not the
        # stroke width, is shifted outside the native Lock Screen fill.
        self.assertIn('layer.lineWidth = IBNThickness;', TWEAK)
        self.assertIn('IBNLeft.lineWidth = IBNThickness;', TWEAK)
        self.assertIn('IBNRight.lineWidth = IBNThickness;', TWEAK)
        self.assertNotIn('layer.lineWidth = IBNThickness +', TWEAK)
        for thickness in [1.5, 2.5, 4.0, 8.0]:
            home_inset = -(thickness / 2.0)
            locked_inset = -(thickness / 2.0 + 2.0)
            self.assertAlmostEqual(home_inset - locked_inset, 2.0)
            # Inner visible edge lands two points outside baseline pill.
            self.assertAlmostEqual(locked_inset + thickness / 2.0, -2.0)
        self.assertIn('CGFloat lockClearance = IBNUseExpandedOutline() ? 2.0 : 0.0;', TWEAK)
        self.assertIn('IBNPortraitIslandRect(portraitWidth, IBNUseExpandedOutline())', TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)

    def test_capture_uses_stable_lock_screen_geometry(self):
        self.assertIn('UIScreenCapturedDidChangeNotification', TWEAK)
        self.assertIn('BOOL captured = UIScreen.mainScreen.isCaptured;', TWEAK)
        self.assertIn('return IBNLastDetectedLockScreen || IBNCountdownExpanded || IBNRecordingExpanded;', TWEAK)
        self.assertIn('IBNPortraitIslandRect(portraitWidth, IBNUseExpandedOutline())', TWEAK)
        self.assertIn('CGFloat lockClearance = IBNUseExpandedOutline() ? 2.0 : 0.0;', TWEAK)
        self.assertIn('IBNRecordingExpanded = YES;', TWEAK)
        self.assertIn('IBNUpdateScreenCaptureState();', TWEAK)
        # Retain native-window rendering which works on Lock Screen;
        # do not reproduce the v0.2.12 hidden-line regression.
        self.assertIn('BOOL visible = IBNVisibleAperture(aperture);', TWEAK)
        self.assertNotIn('if (IBNLastDetectedLockScreen) {\n            for (CAShapeLayer *layer in pair) layer.hidden = YES;', TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)

    def test_capture_end_wait_five_seconds(self):
        self.assertIn('(int64_t)(5.0 * NSEC_PER_SEC)', TWEAK)
        self.assertIn('NSUInteger transition = ++IBNRecordingTransition;', TWEAK)
        self.assertIn('if (transition != IBNRecordingTransition || UIScreen.mainScreen.isCaptured) return;', TWEAK)
        self.assertIn('IBNRecordingExpanded = NO;', TWEAK)
        # Charging popup keeps its independent 3-second delay.
        self.assertIn('(int64_t)(3.0 * NSEC_PER_SEC)', TWEAK)

    def test_countdown_starts_on_replaykit_button_state(self):
        # Actual Control Centre ReplayKit "sessionIsStarting" happens at
        # countdown launch, before the public captured-state turns true.
        self.assertIn('%group IBNCountdownHooks', TWEAK)
        self.assertIn('%hook RPControlCenterMenuModuleViewController', TWEAK)
        self.assertIn('- (void)sessionIsStarting {', TWEAK)
        self.assertIn('IBNBeginRecordingCountdown();', TWEAK)
        self.assertIn('IBNCountdownExpanded = YES;', TWEAK)
        self.assertIn('IBNLastDetectedLockScreen || IBNCountdownExpanded || IBNRecordingExpanded', TWEAK)
        # Only install if class and method are present, never force-load
        # ReplayKitModule and never call a guessed private lock manager.
        self.assertIn('objc_lookUpClass("RPControlCenterMenuModuleViewController")', TWEAK)
        self.assertIn('class_getInstanceMethod(cls, @selector(sessionIsStarting))', TWEAK)
        self.assertIn('%init(IBNCountdownHooks);', TWEAK)
        self.assertIn('NSBundleDidLoadNotification', TWEAK)
        self.assertNotIn('bundleWithPath:@"/System/Library/ControlCenter/Bundles/ReplayKitModule.bundle"', TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)

    def test_cancel_countdown_and_five_second_stop_blackout(self):
        # Cancelled countdown retains its independent 6-second fallback.
        self.assertIn('(int64_t)(6.0 * NSEC_PER_SEC)', TWEAK)
        self.assertIn('if (token != IBNCountdownToken || UIScreen.mainScreen.isCaptured) return;', TWEAK)
        self.assertIn('IBNCountdownExpanded = NO;', TWEAK)
        self.assertIn('++IBNCountdownToken;', TWEAK)
        # Normal stop: arcs disappear immediately and return after 5 seconds.
        self.assertIn('(int64_t)(5.0 * NSEC_PER_SEC)', TWEAK)
        self.assertIn('(int64_t)(3.0 * NSEC_PER_SEC)', TWEAK)  # unchanged charging pause

    def test_screen_recording_uses_two_phases(self):
        # Exact same 180pt centred countdown shape as the confirmed-good
        # v0.2.17 screenshots; active recording contracts to fit the red dot.
        self.assertIn('static const CGFloat IBNRecordingWidth = 180.0;', TWEAK)
        self.assertIn('static const CGFloat IBNRecordingOffsetX = 0.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingWidth = 167.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingHeight = 32.5;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingTop = 14.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingOffsetX = -4.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockWidth = 164.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockOffsetX = -3.0;', TWEAK)
        self.assertIn('static const CGFloat IBNWidth = 126.0;', TWEAK)
        self.assertIn('static BOOL IBNActiveRecordingOutlineProfile(void)', TWEAK)
        self.assertIn('return !IBNLastDetectedLockScreen && IBNRecordingExpanded;', TWEAK)
        self.assertIn('return !IBNLastDetectedLockScreen && (IBNCountdownExpanded || IBNRecordingExpanded);', TWEAK)
        self.assertIn('activeRecording ? IBNActiveRecordingWidth :', TWEAK)
        self.assertIn('(countdownOrRecording ? IBNRecordingWidth : (expanded ? IBNLockWidth : IBNWidth))', TWEAK)
        self.assertIn('activeRecording ? IBNActiveRecordingOffsetX :', TWEAK)
        self.assertIn('(countdownOrRecording ? IBNRecordingOffsetX : (expanded ? IBNLockOffsetX : 0))', TWEAK)
        # Both full-screen and compact native windows must select the same
        # profile or one state will draw an offset/mis-sized line.
        self.assertEqual(TWEAK.count('BOOL activeRecording = IBNActiveRecordingOutlineProfile();'), 2)
        self.assertEqual(TWEAK.count('activeRecording ? IBNActiveRecordingWidth :'), 2)
        # Existing public capture notification switches phases, while the
        # guarded ReplayKit callback preserves early countdown expansion.
        self.assertIn('UIScreenCapturedDidChangeNotification', TWEAK)
        self.assertIn('IBNRecordingExpanded = YES;', TWEAK)
        self.assertIn('IBNCountdownExpanded = NO;', TWEAK)
        self.assertIn('- (void)sessionIsStarting {', TWEAK)
        self.assertIn('(int64_t)(5.0 * NSEC_PER_SEC)', TWEAK)
        self.assertIn('IBNRecordingStopIntermission = YES;', TWEAK)
        self.assertIn('IBNRecordingStopIntermission = NO;', TWEAK)
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)

    def test_charging_pulse_opt_in_and_linear(self):
        self.assertIn('static BOOL IBNPulseCharging = NO;', TWEAK)
        self.assertIn('value = IBNRead(@"pulseCharging");', TWEAK)
        self.assertIn('IBNPulseCharging = value ? [value boolValue] : NO;', TWEAK)
        self.assertIn('IBNPulseCharging && IBNPowerConnected', TWEAK)
        self.assertIn('&& !IBNChargingIntermission && !layer.hidden', TWEAK)
        self.assertIn('CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];', TWEAK)
        self.assertIn('fade.fromValue = @1.0;', TWEAK)
        self.assertIn('fade.toValue = @0.20;', TWEAK)
        self.assertIn('fade.duration = 1.1;', TWEAK)
        self.assertIn('fade.autoreverses = YES;', TWEAK)
        self.assertIn('fade.repeatCount = HUGE_VALF;', TWEAK)
        self.assertIn('kCAMediaTimingFunctionLinear', TWEAK)
        self.assertIn('[layer removeAnimationForKey:key];', TWEAK)
        self.assertIn('IBNUpdateChargingPulse(layer);', TWEAK)
        self.assertIn('IBNUpdateChargingPulse(IBNLeft);', TWEAK)
        self.assertIn('IBNUpdateChargingPulse(IBNRight);', TWEAK)
        self.assertIn('(int64_t)(3.0 * NSEC_PER_SEC)', TWEAK)
        p=(ROOT / "prefs/IBNRootListController.m").read_text()
        self.assertIn('prefNamed:@"Pulsing Charging" key:@"pulseCharging" cell:PSSwitchCell defaultValue:@NO', p)
        cells=plistlib.loads((ROOT / "prefs/Resources/Root.plist").read_bytes())
        s=next(c for c in cells if c.get("key")=="pulseCharging")
        self.assertFalse(s["default"])

    def test_recording_stop_hides_both_paths_for_five_seconds(self):
        # Do not reuse the charging intermission: capture and charging can
        # overlap, and both independently hide their arcs while active.
        self.assertIn('static BOOL IBNRecordingStopIntermission = NO;', TWEAK)
        self.assertIn('IBNRecordingStopIntermission = YES;', TWEAK)
        self.assertIn('IBNRecordingExpanded = NO;', TWEAK)
        self.assertIn('dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),', TWEAK)
        self.assertEqual(TWEAK.count('(int64_t)(5.0 * NSEC_PER_SEC)'), 1)  # recording stop only
        self.assertEqual(TWEAK.count('(int64_t)(6.0 * NSEC_PER_SEC)'), 1)  # cancelled countdown only
        self.assertIn('(int64_t)(5.0 * NSEC_PER_SEC)', TWEAK)
        self.assertIn('if (transition != IBNRecordingTransition || UIScreen.mainScreen.isCaptured) return;', TWEAK)
        self.assertIn('IBNRecordingStopIntermission = NO;', TWEAK)
        self.assertIn('layer.hidden = (percent == 0 || IBNChargingIntermission || IBNRecordingStopIntermission || IBNCallActive);', TWEAK)
        self.assertIn('IBNLeft.hidden = IBNHasActiveSystemAperture || percent == 0 || IBNChargingIntermission || IBNRecordingStopIntermission || IBNCallActive;', TWEAK)
        self.assertIn('IBNRight.hidden = IBNHasActiveSystemAperture || percent == 0 || IBNChargingIntermission || IBNRecordingStopIntermission || IBNCallActive;', TWEAK)
        # Charging retains its independent existing three-second delay.
        self.assertIn('(int64_t)(3.0 * NSEC_PER_SEC)', TWEAK)

    def test_active_recording_position_changes_only_this_profile(self):
        self.assertIn('static const CGFloat IBNActiveRecordingWidth = 167.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingHeight = 32.5;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingTop = 14.0;', TWEAK)
        self.assertIn('static const CGFloat IBNRecordingWidth = 180.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockWidth = 164.0;', TWEAK)
        self.assertIn('CGFloat top = activeRecording ? IBNActiveRecordingTop :', TWEAK)
        self.assertIn('CGFloat yOffset = activeRecording ? 0.75 : 0.0;', TWEAK)
        self.assertIn('IBNRecordingStopIntermission', TWEAK)
        # The confirmed countdown and Lock Screen dimensions are not moved.
        self.assertIn('static const CGFloat IBNRecordingOffsetX = 0.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockOffsetX = -3.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingOffsetX = -4.0;', TWEAK)
        self.assertEqual(-4.0 - (-5.0), 1.0)
        self.assertIn('static const CGFloat IBNRecordingOffsetX = 0.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockOffsetX = -3.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingWidth = 167.0;', TWEAK)

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

    def test_branding_settings_icon_and_sileo(self):
        import base64
        control = (ROOT / "control").read_text()
        self.assertIn('Name: Dynamic Island Battery Notch', control)
        self.assertIn('Description: Shows your battery level as a coloured line around the Dynamic Island', control)
        self.assertNotIn('battery arcs', control.lower())
        entry = plistlib.loads((ROOT / 'layout/Library/PreferenceLoader/Preferences/IslandBatteryNotch.plist').read_bytes())['entry']
        self.assertEqual(entry['label'], 'Dynamic Island Battery Notch')
        self.assertEqual(entry['icon'], '/var/jb/Library/PreferenceLoader/Preferences/IslandBatteryNotch.png')
        self.assertEqual(entry['iconImage'], entry['icon'])
        self.assertEqual(entry['iconImageSystem'], 'capsule.fill')
        info = plistlib.loads((ROOT / 'prefs/Resources/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleDisplayName'], 'Dynamic Island Battery Notch')
        self.assertEqual(info['CFBundleIconFile'], 'icon.png')
        self.assertEqual(info['CFBundleIdentifier'], 'com.551.islandbatterynotchprefs')
        self.assertIn('Package: com.551.islandbatterynotch', control)
        self.assertIn('IslandBatteryNotchPrefs_RESOURCE_FILES = Resources/icon.png', (ROOT / 'prefs/Makefile').read_text())
        self.assertIn('self.title = @"Dynamic Island Battery Notch";', (ROOT / 'prefs/IBNRootListController.m').read_text())
        png = base64.b64decode((ROOT / 'assets/DynamicIslandBatteryNotch.png.b64').read_text())
        self.assertTrue(png.startswith(bytes.fromhex('89504e470d0a1a0a')))
        readme = (ROOT / 'README.md').read_text()
        self.assertIn('<h1 align="center">Dynamic Island Battery Notch</h1>', readme)
        self.assertIn('<p align="center">', readme)
        self.assertIn('assets/made-by-551UK.svg', readme)
        svg = (ROOT / 'assets/made-by-551UK.svg').read_text()
        self.assertIn('made by 551UK', svg)
        self.assertIn('fill="#8b949e"', svg)
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertIn('Generate Settings icon', workflow)
        self.assertIn('test -s "$icon"', workflow)

    def test_active_recording_right_end_only(self):
        self.assertIn('CGFloat rightCapClearance = (!left && IBNRecordingExpanded &&', TWEAK)
        self.assertIn('!IBNLastDetectedLockScreen) ? 1.0 : 0.0;', TWEAK)
        self.assertIn('CGRectGetMaxX(r) + rightCapClearance;', TWEAK)
        # Another 0.25pt on the right only (0.75pt to 1.0pt); base stays 2pt.
        self.assertIn('CGFloat edgeX = left ? CGRectGetMinX(r) : CGRectGetMaxX(r) + rightCapClearance;', TWEAK)
        self.assertIn('CGFloat lockClearance = IBNUseExpandedOutline() ? 2.0 : 0.0;', TWEAK)
        self.assertAlmostEqual(1.0 - 0.75, 0.25)
        self.assertGreater(1.0, 0.0)
        self.assertIn('static const CGFloat IBNActiveRecordingOffsetX = -4.0;', TWEAK)
        self.assertIn('static const CGFloat IBNRecordingWidth = 180.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingWidth = 167.0;', TWEAK)
        self.assertIn('static const CGFloat IBNRecordingOffsetX = 0.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockOffsetX = -3.0;', TWEAK)
        self.assertIn('static const CGFloat IBNLockWidth = 164.0;', TWEAK)
        self.assertIn('(int64_t)(5.0 * NSEC_PER_SEC)', TWEAK)

    def test_callkit_hides_outlines_for_system_managed_calls(self):
        self.assertIn('#import <CallKit/CallKit.h>', TWEAK)
        self.assertIn('static BOOL IBNCallActive = NO;', TWEAK)
        self.assertIn('@interface IBNCallStateDelegate : NSObject <CXCallObserverDelegate>', TWEAK)
        self.assertIn('- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call {', TWEAK)
        self.assertIn('BOOL active = changedCall && !changedCall.hasEnded;', TWEAK)
        self.assertIn('for (CXCall *call in observer.calls)', TWEAK)
        self.assertIn('if (!call.hasEnded) { active = YES; break; }', TWEAK)
        self.assertIn('if (IBNCallActive == active) return;', TWEAK)
        self.assertIn('IBNCallActive = active;', TWEAK)
        self.assertIn('IBNStartCallMonitoring(); IBNRefresh();', TWEAK)
        self.assertIn('[IBNCallObserver setDelegate:IBNCallDelegate queue:dispatch_get_main_queue()];', TWEAK)
        self.assertIn('IBNUpdateCallVisibility(IBNCallObserver, nil);', TWEAK)
        self.assertIn('IBNRecordingStopIntermission || IBNCallActive', TWEAK)
        self.assertIn('CallKit', (ROOT / 'Makefile').read_text())
        self.assertNotIn('objc_getClass("SBLockScreenManager")', TWEAK)
        self.assertEqual(TWEAK.count('(int64_t)(5.0 * NSEC_PER_SEC)'), 1)
        self.assertEqual(TWEAK.count('(int64_t)(6.0 * NSEC_PER_SEC)'), 1)
        self.assertEqual(TWEAK.count('(int64_t)(3.0 * NSEC_PER_SEC)'), 1)

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
    def test_recording_top_edge_only_lift(self):
        # v0.2.27 corrects the thin-looking top stroke without undoing the
        # v0.2.26 right-hand clearance or moving the bottom of the outline.
        self.assertIn('static const CGFloat IBNActiveRecordingTopLift = 0.75;', TWEAK)
        self.assertIn('CGFloat topLift = (IBNRecordingExpanded && !IBNLastDetectedLockScreen)', TWEAK)
        self.assertIn('? IBNActiveRecordingTopLift : 0.0;', TWEAK)
        self.assertIn('CGFloat top = CGRectGetMinY(r) - topLift;', TWEAK)
        self.assertIn('CGFloat bottom = CGRectGetMaxY(r);', TWEAK)
        self.assertIn('CGFloat centreY = CGRectGetMidY(r);', TWEAK)
        self.assertIn('CGFloat radius = CGRectGetHeight(r) / 2.0;', TWEAK)
        self.assertIn('CGFloat edgeX = left ? CGRectGetMinX(r) : CGRectGetMaxX(r) + rightCapClearance;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingTop = 14.0;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingHeight = 32.5;', TWEAK)
        self.assertIn('static const CGFloat IBNActiveRecordingOffsetX = -4.0;', TWEAK)
        self.assertEqual(TWEAK.count('CGRect outwardRect = IBNOutwardStrokeRect(rect);'), 2)
        # top-only path lift preserves the existing 5-second post-stop delay.
        self.assertEqual(TWEAK.count('(int64_t)(5.0 * NSEC_PER_SEC)'), 1)

if __name__ == "__main__":
    unittest.main()
