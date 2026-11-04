# Spotify6 - riff (SecondTrack/riff) ported to the iPhone 3GS (iOS 6.1.6, armv7). Theos, installed as a user-app IPA.
# Deployment target 5.0: one binary for iOS 5 and 6 (iOS-6-only APIs are checked at runtime, see music/App/MMCompat.h).
TARGET := iphone:clang:9.3:5.0
ARCHS  := armv7
PACKAGE_FORMAT := ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Spotify6

Spotify6_FILES  = $(wildcard music/App/*.m) $(wildcard music/UI/*.m) $(wildcard music/Spot/*.m) $(wildcard music/Spot/*.c)
Spotify6_FRAMEWORKS = UIKit CoreGraphics Foundation QuartzCore AVFoundation AudioToolbox Security MediaPlayer SystemConfiguration
MBED = $(THEOS_PROJECT_DIR)/vendor/mbedtls/out/ios
# ARM mode avoids startup crashes from Thumb Objective-C IMPs linked with current Apple ld on iOS 6.
Spotify6_CFLAGS  = -fobjc-arc -marm -O2 -Wall -Werror \
	-Werror=unguarded-availability -Werror=partial-availability -Wno-deprecated-module-dot-map \
	-Imusic/App -Imusic/UI -Imusic/Spot -Ivendor/stb -I$(MBED)/include -include $(MBED)/include/mbedtls_ios6_predef.h -include music/App/MMCompat.h \
	-DTHEOS_LEAN_AND_MEAN   # Theos' Prefix.pch must not import Foundation before MMCompat.h (see there)
# -flat_namespace: the 9.3 SDK binds e.g. NSObject to libobjc, but on iOS 5 it lives in CoreFoundation -> dyld "Symbol not found".
# Flat lookup searches all loaded libraries, so the same binary resolves on iOS 5 and 6.
Spotify6_LDFLAGS  = -L$(MBED)/lib -lmbedtls -lmbedx509 -lmbedcrypto -ObjC -Wl,-flat_namespace
Spotify6_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/ent.plist

ifneq ($(MAKECMDGOALS),clean)
ifeq ($(wildcard $(MBED)/lib/libmbedtls.a),)
$(error build mbedTLS first: vendor/mbedtls/build.sh)
endif
endif

include $(THEOS_MAKE_PATH)/application.mk
