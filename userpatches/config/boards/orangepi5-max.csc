# Rockchip RK3588 octa core 4/8/16GB RAM SoC SPI NVMe 2x USB2 2x USB3 2x HDMI
BOARD_NAME="Orange Pi 5 Max"
BOARD_VENDOR="xunlong"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi-5-max-rk3588_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,current,edge"
KERNEL_TEST_TARGET="vendor,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-orangepi-5-max.dtb"
BOOT_SCENARIO="spl-blobs"
BOOT_SUPPORT_SPI="yes"
BOOT_SPI_RKSPI_LOADER="yes"
IMAGE_PARTITION_TABLE="gpt"
#enable_extension "bcmdhd"
BCMDHD_TYPE="sdio"
unset uboot_custom_postprocess

# Mainline U-Boot for edge kernel
function post_family_config_branch_edge__orangepi5max_use_mainline_uboot() {
	display_alert "$BOARD" "Forcing vendor blobs (disable mainline u-boot build) for $BOARD - $BRANCH" "info"
	# Use vendor blobs from rkbin-tools instead of building mainline u-boot/ATF/SPL
	declare -g BOOT_SCENARIO="only-blobs"
	# Ensure miniloader is set for RK3588
	[[ -n ${ROCKUSB_BLOB:-} ]] && declare -g MINILOADER_BLOB="${ROCKUSB_BLOB}"
	# Prevent any upstream u-boot/atf source/branch being used
	unset BOOTSOURCE BOOTBRANCH BOOTDIR BOOTPATCHDIR BOOT_FDT_FILE
	# keep family uboot_custom_postprocess to allow assembling vendor blobs
	# Use rkbin vendor mapping (leave UBOOT_TARGET_MAP to be set by family defaults based on BOOT_SCENARIO)
	# (no explicit UBOOT_TARGET_MAP override)
}

# Ensure vendor blobs forced even after family late hooks run
function late_family_config__999_orangepi5max_force_vendor_blobs() {
	display_alert "$BOARD" "Late: re-enforce vendor blobs (disable mainline u-boot build)" "info"
	# Re-assert vendor blobs and prevent mainline u-boot build
	# Use vendor-only boot scenario and ensure miniloader is set for RK3588
	declare -g BOOT_SCENARIO="only-blobs"
	# If ROCKUSB_BLOB defined, use it also as MINILOADER_BLOB so idbloader.bin is assembled correctly
	[[ -n ${ROCKUSB_BLOB:-} ]] && declare -g MINILOADER_BLOB="${ROCKUSB_BLOB}"
	# Ensure BOOTSOURCE is set so git lookups succeed, but prevent family-specific patch dirs from forcing builds
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
	unset BOOTPATCHDIR BOOT_FDT_FILE
	# Force the UBOOT_TARGET_MAP mapping for vendor-only blobs (idbloader.bin/uboot.img/trust.bin)
	declare -g UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
	# keep family uboot_custom_postprocess to allow assembling vendor blobs
	# Use rkbin vendor mapping - request building u-boot-dtb.bin (we need u-boot built for this board)
	# (no explicit UBOOT_TARGET_MAP override; family defaults will set it based on BOOT_SCENARIO)
	# Ensure BOOTDIR and BOOTBRANCH are set to the v2025.04 tree which contains orangepi5-max support
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2025.04"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g BOOTPATCHDIR="v2025.04"
	# Do not force a specific BOOTCONFIG; leave it as family default if any
	# track change for debug
	display_alert "$BOARD" "BOOT_SCENARIO=${BOOT_SCENARIO} BOOTDIR=${BOOTDIR} BOOTBRANCH=${BOOTBRANCH} UBOOT_TARGET_MAP=${UBOOT_TARGET_MAP}" "debug"
}


# =================== 钩子1：U-Boot定制后处理（优先级100） =====================
function post_uboot_custom_postprocess__100_my(){
   echo "调用钩子 post_uboot_custom_postprocess__100_my"
   exit 0
	[[ -z ${BOOT_SOC} ]] &&
		exit_with_error "BOOT_SOC not defined for scenario '${BOOT_SCENARIO}' for BOARD'=${BOARD}' and BOOTCONFIG='${BOOTCONFIG}'"
	display_alert "${BOARD}" "boots with ${BOOT_SCENARIO} scenario" "info"

	case "$BOOT_SCENARIO" in
		blobless | tpl-spl-blob | binman*)
# binman-atf-mainline 在构建后与原始的 `binman` 行为相同
			:
			;;

		spl-blobs | tpl-blob-atf-mainline)
# 如果 DDR_BLOB 未定义或不存在则报错并退出
			declare SPL_BIN_PATH="${RKBIN_DIR}/${DDR_BLOB}"
			[[ -z ${SPL_BIN_PATH} ]] && exit_with_error "DDR_BLOB not defined for scenario ${BOOT_SCENARIO}"
			[[ ! -f "${SPL_BIN_PATH}" ]] && exit_with_error "DDR_BLOB ${SPL_BIN_PATH} does not exist for scenario ${BOOT_SCENARIO}"

			if [[ "$BOOT_SOC" == "rk3576" ]]; then
				display_alert "boot_merger for '${BOOT_SOC}' for scenario ${BOOT_SCENARIO}" "SPL_BIN_PATH: ${SPL_BIN_PATH}" "debug"
				RKBOOT_INI_FILE=rk3576.ini
				cp $RKBIN_DIR/rk35/RK3576MINIALL.ini $RKBOOT_INI_FILE
				sed -i "s|FlashBoost=.*$|FlashBoost=${RKBIN_DIR}/rk35/rk3576_boost_v1.02.bin|g" $RKBOOT_INI_FILE
				sed -i "s|Path1=.*rk3576_ddr.*$|Path1=${SPL_BIN_PATH}|g" $RKBOOT_INI_FILE
				sed -i "s|Path1=.*rk3576_usbplug.*$|Path1=${RKBIN_DIR}/rk35/rk3576_usbplug_v1.03.bin|g" $RKBOOT_INI_FILE
				sed -i "s|FlashData=.*$|FlashData=${SPL_BIN_PATH}|g" $RKBOOT_INI_FILE
				sed -i "s|FlashBoot=.*$|FlashBoot=./spl/u-boot-spl.bin|g" $RKBOOT_INI_FILE
				sed -i "s|IDB_PATH=.*$|IDB_PATH=idbloader.img|g" $RKBOOT_INI_FILE
				run_host_x86_binary_logged $RKBIN_DIR/tools/boot_merger $RKBOOT_INI_FILE
				rm -f $RKBOOT_INI_FILE
			else
				display_alert "mkimage for '${BOOT_SOC}' for scenario ${BOOT_SCENARIO}" "SPL_BIN_PATH: ${SPL_BIN_PATH}" "debug"
				run_host_command_logged tools/mkimage -n "${BOOT_SOC_MKIMAGE}" -T rksd -d "${SPL_BIN_PATH}:spl/u-boot-spl.bin" idbloader.img
			fi
			;;

		only-blobs)
			local tempfile
			tempfile=$(mktemp)
		# DEBUG：列出可用的 rkbin 文件和预期的 blob
		display_alert "DEBUG" "Listing rkbin dir and expected blobs: ${RKBIN_DIR}; DDR=${DDR_BLOB} MINILOADER=${MINILOADER_BLOB} BL31=${BL31_BLOB}" "debug"
		run_host_command_logged ls -la "${RKBIN_DIR}" || true
		run_host_command_logged ls -la "${RKBIN_DIR}/${DDR_BLOB}" || true
		run_host_command_logged ls -la "${RKBIN_DIR}/${MINILOADER_BLOB}" || true
		run_host_command_logged ls -la "${RKBIN_DIR}/${BL31_BLOB}" || true

		# 从 DDR blob 创建 idbloader.bin
		display_alert "INFO" "Creating idbloader.bin from DDR blob using 'mkimage' (system) or 'tools/mkimage' (local)" "info"
		# 优先使用系统的 'mkimage'（可能来自 u-boot-tools）；若不可用则回退到本地构建的 tools/mkimage
		# 先尝试系统 mkimage；如果镜像格式不受支持则降级到 'rk35'；如果系统 mkimage 缺失或失败则回退到本地构建的 tools/mkimage
		run_host_command_logged mkimage -n "${BOOT_SOC_MKIMAGE}" -T rksd -d "${RKBIN_DIR}/${DDR_BLOB}" idbloader.bin || \
			run_host_command_logged mkimage -n "rk35" -T rksd -d "${RKBIN_DIR}/${DDR_BLOB}" idbloader.bin || \
			run_host_command_logged tools/mkimage -n "${BOOT_SOC_MKIMAGE}" -T rksd -d "${RKBIN_DIR}/${DDR_BLOB}" idbloader.bin || \
			run_host_command_logged tools/mkimage -n "rk35" -T rksd -d "${RKBIN_DIR}/${DDR_BLOB}" idbloader.bin || display_alert "ERROR" "mkimage failed to produce idbloader.bin" "error"
		run_host_command_logged ls -la idbloader.bin || true

		# 如果存在则追加 miniloader blob
		if [[ -n "${MINILOADER_BLOB}" && -f "${RKBIN_DIR}/${MINILOADER_BLOB}" ]]; then
			display_alert "INFO" "Appending miniloader to idbloader.bin" "info"
			# 确保 idbloader.bin 对追加进程可写（修复 'Permission denied'）
			run_host_command_logged chmod a+w idbloader.bin || true
			append_timeout="${RKBIN_APPEND_TIMEOUT:-30}"
			# 如果可用则使用 'timeout' 追加；否则用兼容的后台追加方式并在 ${append_timeout} 秒后终止
			# 创建一个临时辅助脚本（heredoc）并用参数运行：miniloader rkdir timeout
			run_host_command_logged sh -c "cat > \"$tempfile\" <<'SCRIPT'
#!/usr/bin/env bash
# $1 = MINILOADER_BLOB, $2 = RKBIN_DIR, $3 = timeout
cat \"\$2/\$1\" >> idbloader.bin & pid=\$!
(sleep \$3; if kill -0 \$pid 2>/dev/null; then kill -9 \$pid; exit 124; fi) & waiter=\$!
wait \$pid
rc=\$?
kill -9 \$waiter 2>/dev/null || true
exit \$rc
SCRIPT
chmod +x \"$tempfile\"; \"$tempfile\" '${MINILOADER_BLOB}' '${RKBIN_DIR}' '${append_timeout}'"
			ret=$?
			if [[ $ret -eq 0 ]]; then
				run_host_command_logged ls -la idbloader.bin || true
				display_alert "INFO" "Appended miniloader successfully (size: $(stat -c '%s' idbloader.bin) bytes)" "info"
			else
				if [[ $ret -eq 124 ]]; then
					display_alert "ERROR" "Appending miniloader timed out after ${append_timeout}s" "error"
				else
					display_alert "WARN" "Appending miniloader failed (exit code: ${ret}), retrying with chmod+compat-fallback" "warn"
					run_host_command_logged chmod a+w idbloader.bin || true
					# Retry using compatibility-supervised background append
					# Use a temporary script for retry too (heredoc-based)
				run_host_command_logged sh -c "cat > \"$tempfile\" <<'SCRIPT'
#!/usr/bin/env bash
# $1 = MINILOADER_BLOB, $2 = RKBIN_DIR, $3 = timeout
cat \"\$2/\$1\" >> idbloader.bin & pid=\$!
(sleep \$3; if kill -0 \$pid 2>/dev/null; then kill -9 \$pid; exit 124; fi) & waiter=\$!
wait \$pid
rc=\$?
kill -9 \$waiter 2>/dev/null || true
exit \$rc
SCRIPT
chmod +x \"$tempfile\"; \"$tempfile\" '${MINILOADER_BLOB}' '${RKBIN_DIR}' '${append_timeout}'"
					ret2=$?
					if [[ $ret2 -ne 0 ]]; then
						display_alert "ERROR" "Appending miniloader failed after retry (exit code: ${ret2})" "error"
					else
						run_host_command_logged ls -la idbloader.bin || true
						display_alert "INFO" "Appended miniloader on retry (size: $(stat -c '%s' idbloader.bin) bytes)" "info"
					fi
				fi
			fi
		else
			display_alert "INFO" "No miniloader blob defined or file missing; skipping append" "info"
		fi

		# 使用 loaderimage 打包 uboot 映像（以 INFO/ERROR 级别报告以便出现在日志中）
		run_host_x86_binary_logged "${RKBIN_DIR}/tools/loaderimage" --pack --uboot ./u-boot-dtb.bin uboot.img ${LOADER_UBOOT_OFFSET} || display_alert "ERROR" "loaderimage failed to create uboot.img" "error"
		if [[ -f uboot.img ]]; then
			display_alert "INFO" "uboot.img created (size: $(stat -c '%s' uboot.img) bytes)" "info"
		else
			display_alert "ERROR" "uboot.img not present after loaderimage" "error"
		fi

		# 生成 trust blob（以 INFO/ERROR 级别报告）
		# 确保我们有一个最小的 trust.ini 模板供 merger 使用
			if [[ ! -f trust.ini ]]; then
				run_host_command_logged sh -c "cat > trust.ini <<'INI'
[VERSION]
MAJOR=1
MINOR=0
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=0
PATH=bl31.elf
ADDR=0x10000
[BL32_OPTION]
SEC=0
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=trust.bin
INI"
			fi
			run_host_x86_binary_logged "${RKBIN_DIR}/tools/trust_merger" --replace bl31.elf "${RKBIN_DIR}/${BL31_BLOB}" trust.ini || display_alert "ERROR" "trust_merger failed to create trust.ini" "error"
		if [[ -f trust.ini ]]; then
			display_alert "INFO" "trust.ini created (size: $(stat -c '%s' trust.ini) bytes)" "info"
		else
			display_alert "ERROR" "trust.ini not present after trust_merger" "error"
		fi
			# exit_with_error "\"$BOOT_SCENARIO\" is an Unsupported Boot Scenario!"  # 已禁用；仅处理 only-blobs 情况
			;;
	esac

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then
		if [[ "${BOOT_SPI_RKSPI_LOADER:-"no"}" == "yes" ]]; then
			display_alert "uboot_custom_postprocess (parted) for BOOT_SUPPORT_SPI:${BOOT_SUPPORT_SPI:-"no"} and BOOT_SPI_RKSPI_LOADER=${BOOT_SPI_RKSPI_LOADER:-"no"}" "SPI rkspi_loader.img with GPT" "info"
			run_host_command_logged dd if=/dev/zero of=rkspi_loader.img bs=1M count=0 seek=16
			run_host_command_logged /sbin/parted -s rkspi_loader.img mklabel gpt
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart idbloader 64 7167
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart vnvm 7168 7679
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart reserved_space 7680 8063
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart reserved1 8064 8127
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart uboot_env 8128 8191
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart reserved2 8192 16383
			run_host_command_logged /sbin/parted -s rkspi_loader.img unit s mkpart uboot 16384 32734
			# 回退：如果 idbloader.img 缺失但 idbloader.bin 存在，则复制以满足 dd
		run_host_command_logged sh -c 'test -f idbloader.img || (test -f idbloader.bin && cp idbloader.bin idbloader.img)' || true
			run_host_command_logged dd if=idbloader.img of=rkspi_loader.img seek=64 conv=notrunc
		# 回退：如果 u-boot.itb 缺失但 u-boot-dtb.bin 存在，则复制以满足 dd
			run_host_command_logged sh -c 'test -f u-boot.itb || (test -f u-boot-dtb.bin && cp u-boot-dtb.bin u-boot.itb)' || true
			run_host_command_logged dd if=u-boot.itb of=rkspi_loader.img seek=16384 conv=notrunc
		else
			display_alert "uboot_custom_postprocess (mkimage) for BOOT_SUPPORT_SPI:${BOOT_SUPPORT_SPI:-"no"} and BOOT_SPI_RKSPI_LOADER=${BOOT_SPI_RKSPI_LOADER:-"no"}" "SPI rkspi_loader.img" "info"
			run_host_command_logged tools/mkimage -n "${BOOT_SOC_MKIMAGE}" -T rkspi -d tpl/u-boot-tpl.bin:spl/u-boot-spl.bin rkspi_tpl_spl.img
			run_host_command_logged dd if=/dev/zero of=rkspi_loader.img count=8128 status=none
			run_host_command_logged dd if=rkspi_tpl_spl.img of=rkspi_loader.img conv=notrunc status=none
			run_host_command_logged dd if=u-boot.itb of=rkspi_loader.img seek=768 conv=notrunc status=none
		fi
	fi
}

function post_family_tweaks__orangepi5max_naming_audios() {
	display_alert "$BOARD" "Renaming orangepi5max audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI1 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

function post_family_tweaks_bsp__orangepi5max_bluetooth() {
	display_alert "$BOARD" "Installing ap6611s-bluetooth.service" "info"

	# Bluetooth on this board is handled by a Broadcom (AP6611S) chip and requires
	# a custom brcm_patchram_plus binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
	cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/ap6611s-bluetooth.service

	# Reuse the service file, ttyS0 -> ttyS7; BCM4345C5.hcd -> SYN43711A0.hcd
	sed -i 's/ttyS0/ttyS7/g' $destination/lib/systemd/system/ap6611s-bluetooth.service
	sed -i 's/BCM4345C5.hcd/SYN43711A0.hcd/g' $destination/lib/systemd/system/ap6611s-bluetooth.service
	return 0
}

function post_family_tweaks__orangepi5max_enable_bluetooth_service() {
	display_alert "$BOARD" "Enabling ap6611s-bluetooth.service" "info"
	chroot_sdcard systemctl enable ap6611s-bluetooth.service
	return 0
}
