# Dynamic Island Battery Notch

A dedicated iPhone 14 Pro Max (iPhone15,3) Dopamine rootless tweak for iOS 16.3.

The floating transparent SpringBoard overlay draws two symmetric battery-progress outlines around the resting Dynamic Island. Each line becomes exactly 1% shorter for every one percent of battery capacity lost. The lines are visible on the Lock Screen, Home Screen, and inside apps; do not intercept touch. Red 0–20%, yellow 21–60%, green 61–100%. Settings offers enable toggle, automatic/manual colour, fixed alignment and adjustable line thickness.

Version 0.2.2 locks alignment, retains normal auto/manual colours, adds a separately selectable charging colour, and leaves one clear Line Thickness slider. v0.2.1 fixed the blank Settings page and places arcs on the system aperture window for foreground apps, retaining a separate overlay as a fallback.

This is an experimental build; the physical Island outline and secure overlay must be checked on-device. It is entirely separate from the Dynamic Island colour project.

Build: `make clean package FINALPACKAGE=1` with Theos and the iOS 16+ SDK. GitHub Actions builds and publishes the rootless `.deb` automatically on new commits.

Install in Sileo, then respring. Disable other Island outline tweaks during testing.
