export TARGET = iphone:clang:16.5:16.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IslandBatteryNotch
IslandBatteryNotch_FILES = Tweak.xm
IslandBatteryNotch_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter
IslandBatteryNotch_FRAMEWORKS = UIKit Foundation QuartzCore CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
