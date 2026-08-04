export ARCHS := arm64 arm64e
export TARGET := iphone:clang:16.5:13.0

INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := Icon110
Icon110_FILES := Tweak.xm IconShadow.xm
Icon110_CFLAGS := -fobjc-arc
Icon110_FRAMEWORKS := UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

