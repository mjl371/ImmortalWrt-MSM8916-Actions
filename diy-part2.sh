#!/bin/bash
#

# Modify default IP
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# eth0
sed -i "s/ucidef_set_interface_lan 'eth0'/ucidef_set_interface_lan 'br-lan'/" package/base-files/files/etc/board.d/99-default_network

# Modify default theme
sed -i 's/luci-theme-material/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 老分支没有这些 feature 伪包（定义在 package/kernel/linux/modules/*.mk 里，
# 例如 master 的 input.mk 有 define Package/input-support，25.12 没有）。
# 但 feeds 里的包是按 master 写的，例如 openstick 的 rmtfs：
#   DEPENDS:=+input-support +libudev-zero +libqrtr +qrtr-ns
# 镜像组装阶段 apk 就会报 "input-support (no such package)"。
# 这里逐个子分支判断：树里没有 Package/<name> 定义，就把依赖从 Makefile 里去掉。
for feat in audio-support video-support input-support dvb-support scanner-support accel-support; do
	if grep -rqs "Package/$feat" package/ 2>/dev/null; then
		continue
	fi
	hits=$(grep -rl --include=Makefile "+$feat" feeds package 2>/dev/null || true)
	[ -n "$hits" ] || continue
	for mk in $hits; do
		sed -i "s/ *+$feat//g" "$mk"
		echo "feeds: $mk 去掉本分支不存在的依赖 +$feat"
	done
done

# DbusSmsForwardCPlus
git clone https://github.com/lkiuyu/DbusSmsForwardCPlus package/DbusSmsForwardCPlus

# 北大源
cp -r "$GITHUB_WORKSPACE/scripts/files-8916" "$GITHUB_WORKSPACE/openwrt/files"
ls -R "$GITHUB_WORKSPACE/openwrt/files"

# 固件里的软件源按源码版本生成（原来写死 pku 镜像的 snapshots，从 tag 编出来也指向快照，不对）：
#   v25.12.2      -> https://downloads.immortalwrt.org/releases/25.12.2
#   openwrt-25.12 -> https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT
#   v24.10.6      -> https://downloads.immortalwrt.org/releases/24.10.6
#   openwrt-24.10 -> https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT
#   master        -> https://downloads.immortalwrt.org/snapshots
# 只写 aarch64_generic 的 5 个通用源：本 target（msm89xx/msm8916）上游没有发布，
# releases/*/targets/msm89xx/msm8916/packages 是 404；而 armsr/armv8 的 target 源是给
# armsr 设备的，其 kmod 装到 msm8916 上会直接坏，所以一律不写。
case "${REPO_BRANCH:-master}" in
v[0-9]*) VROOT="https://downloads.immortalwrt.org/releases/${REPO_BRANCH#v}" ;;
openwrt-*) VROOT="https://downloads.immortalwrt.org/releases/${REPO_BRANCH#openwrt-}-SNAPSHOT" ;;
*) VROOT="https://downloads.immortalwrt.org/snapshots" ;;
esac
echo "软件源根: $VROOT"
FEED_LIST="base luci packages routing telephony"

mkdir -p files/etc/apk/repositories.d
{
	echo "# 自动生成，跟随构建版本 ${REPO_BRANCH}；自定义源写 customfeeds.list"
	for f in $FEED_LIST; do echo "$VROOT/packages/aarch64_generic/$f/packages.adb"; done
} > files/etc/apk/repositories.d/distfeeds.list

mkdir -p files/etc/opkg
{
	for f in $FEED_LIST; do echo "src/gz immortalwrt_$f $VROOT/packages/aarch64_generic/$f"; done
} > files/etc/opkg/distfeeds.conf

echo "--- distfeeds.list ---"; cat files/etc/apk/repositories.d/distfeeds.list
echo "--- distfeeds.conf ---"; cat files/etc/opkg/distfeeds.conf


# 压制 GCC 14 类型错误
pwd
ls package/libs/libnftnl/Makefile
sed -i '/^TARGET_CFLAGS += \$(FPIC)/a TARGET_CFLAGS += -Wno-error=incompatible-pointer-types' package/libs/libnftnl/Makefile

# 验证
grep -n "Wno-error=incompatible-pointer-types" package/libs/libnftnl/Makefile && echo "✓ 修复已应用" || echo "✗ 修复失败"

[ -f include/toplevel.mk ] || cd "$GITHUB_WORKSPACE/openwrt" || exit 1
patch -p1 --fuzz=2 <<'EOF'
--- a/include/image.mk
+++ b/include/image.mk
@@ -192,7 +192,6 @@
   -Wno-unit_address_vs_reg \
   -Wno-avoid_unnecessary_addr_size \
   -Wno-alias_paths \
-  -Wno-graph_child_address \
   -Wno-simple_bus_reg
 
 DTC_FLAGS += $(DTC_WARN_FLAGS)
EOF
grep -q 'graph_child_address' include/image.mk && echo "FAIL: image.mk 未修复" || echo "OK: image.mk DTC 参数已修复"


FW4_SRC=$GITHUB_WORKSPACE/scripts/msm89xx/package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
FW4_PATCH=package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
FW4_VER=$(sed -n 's/^PKG_SOURCE_VERSION:=//p' package/network/config/firewall4/Makefile)
echo "firewall4 pin: ${FW4_VER:-unknown}"

if [ "$FW4_VER" = "bac1d656e09b48e542f860844fe91cbba82abae2" ]; then
	if cp -f "$FW4_SRC" "$FW4_PATCH"; then
		echo "firewall4: local fullcone patch applied"
	else
		echo "::error::firewall4: local patch missing at $FW4_SRC"
	fi
else
	rm -f "$FW4_PATCH"
	git checkout -- package/network/config/firewall4
	echo "firewall4: pin changed, upstream patch restored"
fi

if grep -q "zone.dflags.helper = false;" "$FW4_PATCH" 2>/dev/null; then
	echo "firewall4 patch verify: OK"
else
	echo "::warning::firewall4 patch verify: failed"
fi


# ============================================================
# Qualcomm MSM8916 WCN3620 Bluetooth support
# ============================================================

KERNEL_CONFIG="target/linux/generic/config-6.12"

if [ ! -f "$KERNEL_CONFIG" ]; then
    echo "ERROR: Kernel config not found: $KERNEL_CONFIG"
    find target/linux -name 'config-6.12' -print
    exit 1
fi

enable_kernel_option() {
    local option="$1"
    local value="$2"

    sed -i "/^# ${option} is not set$/d" "$KERNEL_CONFIG"
    sed -i "/^${option}=/d" "$KERNEL_CONFIG"
    echo "${option}=${value}" >> "$KERNEL_CONFIG"
}

enable_kernel_option CONFIG_BT y
enable_kernel_option CONFIG_RPMSG y
enable_kernel_option CONFIG_QCOM_WCNSS_CTRL y
enable_kernel_option CONFIG_BT_QCOMSMD m

echo "Qualcomm Bluetooth kernel options added:"
grep -E 'CONFIG_(BT|RPMSG|QCOM_WCNSS_CTRL|BT_QCOMSMD)=' "$KERNEL_CONFIG"



