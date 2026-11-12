# SPDX-License-Identifier: GPL-2.0-only

define KernelPackage/qcom-rproc
  SUBMENU:=$(OTHER_MENU)
  TITLE:=Qualcomm remoteproc support
  DEPENDS:=@TARGET_msm89xx
  KCONFIG:=\
    CONFIG_QCOM_MDT_LOADER \
    CONFIG_QCOM_RPROC_COMMON \
    CONFIG_QCOM_PIL_INFO
  FILES:=\
    $(LINUX_DIR)/drivers/soc/qcom/mdt_loader.ko \
    $(LINUX_DIR)/drivers/remoteproc/qcom_common.ko \
    $(LINUX_DIR)/drivers/remoteproc/qcom_pil_info.ko
  AUTOLOAD:=$(call AutoProbe,mdt_loader qcom_common qcom_pil_info)
endef

define KernelPackage/qcom-rproc/description
Support for loading remoteprocs in some Qualcomm chipsets
endef

$(eval $(call KernelPackage,qcom-rproc))

define KernelPackage/qcom-rproc-wcnss
  SUBMENU:=$(OTHER_MENU)
  TITLE:=Qualcomm WCNSS remoteproc support
  DEPENDS:=@TARGET_msm89xx +kmod-qcom-rproc
  KCONFIG:=\
    CONFIG_QCOM_WCNSS_PIL \
    CONFIG_QCOM_WCNSS_CTRL
  FILES:=\
    $(LINUX_DIR)/drivers/remoteproc/qcom_wcnss_pil.ko \
    $(LINUX_DIR)/drivers/soc/qcom/wcnss_ctrl.ko
  AUTOLOAD:=$(call AutoProbe,qcom_wcnss_pil wcnss_ctrl)
endef

define KernelPackage/qcom-rproc-wcnss/description
Firmware loading and control for the WCNSS remoteproc
endef

$(eval $(call KernelPackage,qcom-rproc-wcnss))

define KernelPackage/qcom-rproc-modem
  SUBMENU:=$(OTHER_MENU)
  TITLE:=Qualcomm modem remoteproc support
  DEPENDS:=@TARGET_msm89xx +kmod-qcom-rproc +kmod-wwan
  KCONFIG:=\
    CONFIG_QCOM_Q6V5_COMMON \
    CONFIG_QCOM_Q6V5_MSS
  FILES:=\
    $(LINUX_DIR)/drivers/remoteproc/qcom_q6v5.ko \
    $(LINUX_DIR)/drivers/remoteproc/qcom_q6v5_mss.ko
  AUTOLOAD:=$(call AutoProbe,qcom_q6v5 qcom_q6v5_mss)
endef

define KernelPackage/qcom-rproc-modem/description
Firmware loading and control for the modem remoteproc.
endef

$(eval $(call KernelPackage,qcom-rproc-modem))

# ---------------------------------------------------------------
# Bluetooth over the WCNSS (Pronto/RIVA) core
# ---------------------------------------------------------------
# 上游 package/kernel/linux/modules/bluetooth.mk 只有 bluetooth / hci-uart /
# btusb / btbcm / btmtk…，没有 btqca 和 btqcomsmd 的打包定义。所以
# CONFIG_BT_QCOMSMD=m 编出来的 btqcomsmd.ko 没有任何包引用它，不会进固件
# （这也是 =y 编进内核之外唯一正确的做法：自己定义 kmod 包）。
#
# 前提：WCNSS 自身要先起来 —— remoteproc 加载 wcnss.mdt 后才会创建
# "qcom,wcnss-bt" platform device，btqcomsmd 才有得 bind。DTS 里
# msm8916.dtsi 的 wcnss_bt 节点默认 enabled，各机型无需改。

define KernelPackage/btqca
  SUBMENU:=$(BLUETOOTH_MENU)
  TITLE:=Qualcomm Bluetooth firmware helper
  DEPENDS:=@TARGET_msm89xx +kmod-bluetooth
  KCONFIG:=CONFIG_BT_QCA
  FILES:=$(LINUX_DIR)/drivers/bluetooth/btqca.ko
endef

define KernelPackage/btqca/description
  Qualcomm Bluetooth helper routines (ROM patch / NVM download, BD address).

  Provides qca_set_bdaddr_rome(), used by the btqcomsmd SMD transport.
  Deliberately NOT autoloaded: it has no platform driver of its own and is
  loaded as a dependency of kmod-btqcomsmd.
endef

$(eval $(call KernelPackage,btqca))

define KernelPackage/btqcomsmd
  SUBMENU:=$(BLUETOOTH_MENU)
  TITLE:=Qualcomm SMD based HCI support
  DEPENDS:=@TARGET_msm89xx +kmod-bluetooth +kmod-btqca +kmod-qcom-rproc-wcnss
  KCONFIG:=CONFIG_BT_QCOMSMD
  FILES:=$(LINUX_DIR)/drivers/bluetooth/btqcomsmd.ko
  AUTOLOAD:=$(call AutoProbe,btqca btqcomsmd)
endef

define KernelPackage/btqcomsmd/description
  HCI over Qualcomm SMD, bridging Bluetooth onto the shared-memory
  channels of the WCNSS (Pronto/RIVA) core.

  Binds to the "qcom,wcnss-bt" platform device created when the WCNSS
  remoteproc boots, so the WCNSS firmware (wcnss.mdt) must be present.
endef

$(eval $(call KernelPackage,btqcomsmd))
