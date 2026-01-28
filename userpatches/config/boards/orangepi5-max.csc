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
