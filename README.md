# Dynamic Island Battery Notch

## Experimental v0.2.13 — restore native Lock Screen lines; 3-second charging pause

Restore the **exact v0.2.11 drawing implementation**: the Lock Screen uses the system-aperture window's arc layers again. v0.2.12 hid those native layers in favour of a separate overlay that turned out not to be visible above the Lock Screen, removing the green outline. This release removes that regression. The working wide Lock Screen profile, transparent original white border, lock icon synced to battery/charging colour, two mirrored progress arcs, 1.5–8pt line thickness slider and rendering in apps are all retained.

On a fresh charging connection, both battery arcs disappear immediately for **3 seconds** (not 2 or 4) to avoid obscuring iOS's charging popup. They return in the selected custom Charging Colour; unplugging restores the normal colour immediately. No new private Lock Screen hooks or drawing paths have been introduced.

## Experimental v0.2.11 — line thickness minimum

The **Line Thickness** slider now starts at **1.5 pt** (fully left), can increase to **8 pt**, and defaults to **2.5 pt**. Existing saved values below 1.5 are clamped in both Settings and the drawing code. No change to Lock Screen alignment or colouring, and no additional hooks. Includes v0.2.10's native charge-popup wait and Lock Screen detection changes.

## Experimental v0.2.10 — Lock Screen alignment detection and charging popup

Corrects the Lock Screen-only size decision: `SBUIProudLockIconView` is already mounted and coloured successfully in v0.2.9, but its secure hosting-window ancestor could report hidden, causing v0.2.9 to choose the Home Screen-sized outline. v0.2.10 examines the lock view's own attachment and on-screen bounds instead, without adding any private lock-manager hook. The locked geometry remains 164 × 34 pt, offset slightly left; Home Screen/apps remain 126 × 37.33 pt.

**On a new charging connection:** immediately hide both arcs entirely for 4 seconds, temporarily restore iOS's original keyline for the native charging popup, then hide the stock keyline again and show the battery arcs in the separately selected Charging Colour. Unplugging restores normal colours and cancels the pending timer. No changes were made to the other Dynamic Island tweak. On-device testing is still needed.

## Experimental v0.2.9 — Lock Screen native outline / lock colour

Built from the original v0.2.4 source. On the Lock Screen only, battery arcs use a wider 164 × 34 pt fixed profile, offset 3 pt left; the resting 126 × 37.33 pt Island profile is unchanged for Home Screen and apps. Detects the existing visible `SBUIProudLockIconView` rather than calling `SBLockScreenManager` (which caused SpringBoard Safe Mode in v0.2.5). Retains the same working SpringBoard rendering hooks and top-connected battery progression.

Reuses the native `SBSystemApertureContainerView` key-line colour hooks and lock-icon filter principles from `551UK/Dynamic-Island-LS-Color-16`, **without modifying that repository**. While enabled, the native outside outline uses `UIColor.clearColor` (the battery arcs remain visible). The Lock Screen padlock uses the SAME colour as the battery arcs, including charging colour and manual colour selection; disabling restores the native key-line tint and original lock appearance.

**Before installing, disable or uninstall Dynamic Island LS Color 16** — both tweaks hook the same native border and padlock and could conflict if enabled simultaneously. This version does NOT include the previously requested four-second charging delay; it is intentionally isolated for stability testing. The earlier v0.2.4 release remains unchanged and available for rollback. This is experimental and must be tested on-device.

A dedicated iPhone 14 Pro Max (iPhone15,3) Dopamine rootless tweak for iOS 16.3.

The floating transparent SpringBoard overlay draws two symmetric battery-progress outlines around the resting Dynamic Island. Each line becomes exactly 1% shorter for every one percent of battery capacity lost, splitting at the bottom and staying connected at the top. The lines are visible on the Lock Screen, Home Screen, and inside apps; do not intercept touch. Red 0–20%, yellow 21–60%, green 61–100%. Settings offers enable toggle, automatic/manual colour, fixed alignment and adjustable line thickness.

Version 0.2.4 keeps both outline arcs connected at the top-centre of the Dynamic Island and shortens them only from the bottom upward as the battery falls, continuously by 1% per battery percent. At 100% the top and bottom are both closed; at 0% the arcs vanish. Automatic/manual outline and charging colours and the outward line thickness adjustment remain unchanged.

Version 0.2.3 corrects line thickness visibility on the physical panel by drawing the extra width outward from the Island edge rather than inside the hardware cutout, without changing alignment. Screenshot pixels inside the cutout are not visible on the display.

Version 0.2.2 locks alignment, retains normal auto/manual colours, adds a separately selectable charging colour, and leaves one clear Line Thickness slider. v0.2.1 fixed the blank Settings page and places arcs on the system aperture window for foreground apps, retaining a separate overlay as a fallback.

This is an experimental build; the physical Island outline and secure overlay must be checked on-device. It is entirely separate from the Dynamic Island colour project.

Build: `make clean package FINALPACKAGE=1` with Theos and the iOS 16+ SDK. GitHub Actions builds and publishes the rootless `.deb` automatically on new commits.

Install in Sileo, then respring. Disable other Island outline tweaks during testing.
