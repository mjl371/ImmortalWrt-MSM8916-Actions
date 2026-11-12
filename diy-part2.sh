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
# 关掉 ruby 的 YJIT —— 它会把 rust host 工具链拽进构建
# ============================================================
# 依赖链：luci-app-openclash -> +ruby -> aarch64 上 RUBY_ENABLE_YJIT 默认 y
#         -> lang/ruby 的 PKG_BUILD_DEPENDS 里有 RUBY_ENABLE_YJIT:rust/host
# 而 immortalwrt/packages(openwrt-25.12) 的 rust 1.96.0 打包脚本写死
#   --set=llvm.download-ci-llvm=true
# 会去 Rust CI 下预编译 LLVM，1.96.0 的 CI 产物已过期 -> 404
#   ERROR: failed to download llvm from ci
#   ERROR: package/feeds/packages/rust [host] failed to build.
# YJIT 只是 Ruby 的 JIT 加速，openclash 的 ruby 脚本用不到；关掉还省 30~60 分钟。
if [ -f .config ]; then
	YJIT_OFF=0
	if grep -q '^CONFIG_RUBY_ENABLE_YJIT=' .config; then
		sed -i 's/^CONFIG_RUBY_ENABLE_YJIT=.*/# CONFIG_RUBY_ENABLE_YJIT is not set/' .config
		YJIT_OFF=1
	elif ! grep -q '^# CONFIG_RUBY_ENABLE_YJIT is not set$' .config; then
		# 基线 config 里没有这个符号：显式写一条 n，defconfig 时不会被默认值 y 覆盖
		echo '# CONFIG_RUBY_ENABLE_YJIT is not set' >> .config
		YJIT_OFF=1
	fi
	echo "ruby YJIT: 已关闭（本次不再需要 rust host 工具链），$YJIT_OFF"
	grep -n 'RUBY_ENABLE_YJIT' .config || true
else
	echo "::warning::没有 .config，跳过 YJIT 处理"
fi


# ============================================================
# Qualcomm MSM8916 WCN3620 Bluetooth support
# ============================================================
# 正式的定义已经写进仓库里的 target 文件，这里只做兜底和自检：
#   - scripts/msm89xx/target/linux/msm89xx/modules.mk  : kmod-btqca / kmod-btqcomsmd
#   - scripts/msm89xx/target/linux/msm89xx/Makefile    : DEFAULT_PACKAGES
#   - scripts/msm89xx/target/linux/msm89xx/config-6.12 : BT_QCOMSMD=m / BT_QCA=m
#   - scripts/msm89xx/target/linux/msm89xx/config-7.3  : 同上（config-6.12 缺
#     CONFIG_SQUASHFS，diy-part1 会用 config-7.3 当基底补全，后者的值说了算）
#
# 为什么必须是 =m 而不是 =y：目标里自己定义了 KernelPackage/btqcomsmd，
# 它的 FILES 指向 btqcomsmd.ko。如果 BT_QCOMSMD=y 编进内核就不会产生 .ko，
# 该 kmod 包会因缺文件构建失败。同理 btqca 必须是 =m。
KP="${KERNEL_PATCHVER:-6.12}"
KERNEL_CONFIG="target/linux/msm89xx/config-$KP"

if [ ! -f "$KERNEL_CONFIG" ]; then
	echo "::error::Target kernel config not found: $KERNEL_CONFIG"
	ls target/linux/msm89xx/config-* 2>/dev/null || true
	exit 1
fi

# 只修正 BT_QCOMSMD / BT_QCA 的值，不再新增无关的 y。
# 补全逻辑（diy-part1 里 config-7.3 覆盖）可能把它改回 not set，这里兜底。
set_kernel_option() {
	local option="$1"
	local value="$2"

	if grep -q "^# ${option} is not set$" "$KERNEL_CONFIG"; then
		sed -i "s|^# ${option} is not set$|${option}=${value}|" "$KERNEL_CONFIG"
	elif grep -q "^${option}=" "$KERNEL_CONFIG"; then
		sed -i "s|^${option}=.*|${option}=${value}|" "$KERNEL_CONFIG"
	else
		echo "${option}=${value}" >> "$KERNEL_CONFIG"
	fi
}

# btqcomsmd 的 Kconfig 依赖 RPMSG 和 QCOM_WCNSS_CTRL，两者在 target 里本来就是 y
set_kernel_option CONFIG_BT y
set_kernel_option CONFIG_RPMSG y
set_kernel_option CONFIG_QCOM_WCNSS_CTRL y
set_kernel_option CONFIG_BT_QCA m
set_kernel_option CONFIG_BT_QCOMSMD m
# DTS 侧不用改：msm8916.dtsi 里 wcnss_ctrl 下的
#   wcnss_bt: bluetooth { compatible = "qcom,wcnss-bt"; };
# 没有 status 属性，默认就是 enabled。

echo "Qualcomm Bluetooth kernel options in $KERNEL_CONFIG:"
grep -E '^CONFIG_(BT|BT_QCA|RPMSG|QCOM_WCNSS_CTRL|QCOM_SMD_RPM|BT_QCOMSMD)=' "$KERNEL_CONFIG" || true

BT_OK=1
grep -q '^CONFIG_BT_QCOMSMD=m$' "$KERNEL_CONFIG" || { echo "::error::CONFIG_BT_QCOMSMD 不是 m"; BT_OK=0; }
grep -q '^CONFIG_BT_QCA=m$' "$KERNEL_CONFIG" || { echo "::error::CONFIG_BT_QCA 不是 m"; BT_OK=0; }
grep -q 'KernelPackage/btqcomsmd' target/linux/msm89xx/modules.mk \
	|| { echo "::error::modules.mk 里没有 KernelPackage/btqcomsmd"; BT_OK=0; }
grep -q 'KernelPackage/btqca' target/linux/msm89xx/modules.mk \
	|| { echo "::error::modules.mk 里没有 KernelPackage/btqca"; BT_OK=0; }
[ "$BT_OK" = "1" ] && echo "OK: 蓝牙 kmod 包与内核配置就位（btqca/btqcomsmd = m）"


# ============================================================
# BlueZ 用户态：内核侧有了还得能驱动
# ============================================================
# target Makefile 的 DEFAULT_PACKAGES 已经把 bluez-daemon/bluez-utils/bluez-tools
# 列进去了，但 config/*.config 这些基线配置里显式写着
#   "# CONFIG_PACKAGE_bluez-xxx is not set"
# 显式 n 的优先级高于 DEFAULT_PACKAGES，defconfig 会原样保留，结果固件里只有
# kmod 没有 userspace（hci0 起得来，但没有 bluetoothctl 可用）。这里强制打开，
# 依赖（bluez-libs / bluez-utils-extra / glib2 / dbus / libreadline…）由
# make defconfig 按 DEPENDS 自动补齐。
if [ -f .config ]; then
	for pkg in bluez-daemon bluez-utils bluez-tools; do
		if grep -q "^# CONFIG_PACKAGE_${pkg} is not set$" .config; then
			sed -i "s|^# CONFIG_PACKAGE_${pkg} is not set$|CONFIG_PACKAGE_${pkg}=y|" .config
			echo "bluez: ${pkg} -> y"
		elif ! grep -q "^CONFIG_PACKAGE_${pkg}=" .config; then
			echo "CONFIG_PACKAGE_${pkg}=y" >> .config
			echo "bluez: ${pkg} -> y (追加)"
		fi
	done
	echo "bluez 相关配置："
	grep -E "^(# )?CONFIG_PACKAGE_bluez" .config | head -8 || true
else
	echo "::warning::没有 .config，跳过 bluez 处理"
fi



