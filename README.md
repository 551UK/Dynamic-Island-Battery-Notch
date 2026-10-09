# Dynamic Island Battery Notch

A dedicated iPhone 14 Pro Max (iPhone15,3) Dopamine rootless tweak for iOS 16.3.

The floating transparent SpringBoard overlay draws two symmetric battery-progress outlines around the resting Dynamic Island. Each line becomes exactly 1% shorter for every one percent of battery capacity lost, splitting at the bottom and staying connected at the top. The lines are visible on the Lock Screen, Home Screen, and inside apps; do not intercept touch. Red 0–20%, yellow 21–60%, green 61–100%. Settings offers enable toggle, automatic/manual colour, fixed alignment and adjustable line thickness.

## v0.2.6 safety rollback

**Do not use v0.2.5:** It was reported to put SpringBoard in Safe Mode on the Lock Screen. v0.2.6 removes its unverified private lock-screen manager calls and expanded lock-screen drawing profile, restoring v0.2.4 rendering (including the bottom-up battery split, outward thickness, and colour settings). This is a safety rollback, not a new Lock Screen border-alignment fix. A crash log is needed before reintroducing it.

Version 0.2.4 keeps both outline arcs connected at the top-centre of the Dynamic Island and shortens them only from the bottom upward as the battery falls, continuously by 1% per battery percent. At 100% the top and bottom are both closed; at 0% the arcs vanish. Automatic/manual outline and charging colours and the outward line thickness adjustment remain unchanged.

Version 0.2.3 corrects line thickness visibility on the physical panel by drawing the extra width outward from the Island edge rather than inside the hardware cutout, without changing alignment. Screenshot pixels inside the cutout are not visible on the display.

Version 0.2.2 locks alignment, retains normal auto/manual colours, adds a separately selectable charging colour, and leaves one clear Line Thickness slider. v0.2.1 fixed the blank Settings page and places arcs on the system aperture window for foreground apps, retaining a separate overlay as a fallback.

This is an experimental build; the physical Island outline and secure overlay must be checked on-device. It is entirely separate from the Dynamic Island colour project.

Build: `make clean package FINALPACKAGE=1` with Theos and the iOS 16+ SDK. GitHub Actions builds and publishes the rootless `.deb` automatically on new commits.

Install in Sileo, then respring. Disable other Island outline tweaks during testing.
