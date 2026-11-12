# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

BOARD:=msm89xx
BOARDNAME:=Boards based on Snapdragon 210/410/615 chipsets
FEATURES:=ext4 usb usbgadget gpio fpu rootfs-part boot-part squashfs
SUBTARGETS:=msm8916

KERNEL_PATCHVER:=7.3

define Target/Description
	Build firmware images for various Snapdragon 210/410/615 based devices
endef

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += partx-utils e2fsprogs mkf2fs kmod-fs-f2fs
DEFAULT_PACKAGES += kmod-usb-chipidea kmod-usb-gadget-eth
DEFAULT_PACKAGES += kmod-wcn36xx kmod-rproc-wcnss
DEFAULT_PACKAGES += kmod-rpmsg-wwan-ctrl kmod-bam-dmux kmod-qcom-rproc-modem
DEFAULT_PACKAGES += rmtfs
# Bluetooth over the WCNSS (Pronto/RIVA) core via the SMD transport.
# kmod-btqcomsmd pulls in kmod-bluetooth (BT core + rfcomm/bnep/hidp) and
# kmod-qcom-rproc-wcnss; kmod-btqca is the ROM-patch/NVM helper it needs.
DEFAULT_PACKAGES += kmod-btqcomsmd kmod-btqca
# BlueZ userspace so Bluetooth is usable out of the box: bluetoothd plus
# bluetoothctl / hcitool / hciconfig / btmgmt (bluez-utils) and
# rfcomm / sdptool / bt-agent (bluez-tools). Without these the kernel side
# is there but there is no way to drive it.
DEFAULT_PACKAGES += bluez-daemon bluez-utils bluez-tools

KERNELNAME:=Image

$(eval $(call BuildTarget))
