function extension_finish_config__install_kernel_headers_for_bcmdhd_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping bcmdhd dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with bcmdhd dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_bcmdhd_dkms_package() {

	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	[[ -z $BCMDHD_TYPE ]] && return 0
	user="sfqr0414"
	api_url="https://api.github.com/repos/${user}/bcmdhd-dkms/releases/latest"
	latest_version=$(curl -s "${api_url}" | jq -r '.tag_name')
	bcmdhd_pcie_url="https://github.com/${user}/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-pcie-dkms_${latest_version}_all.deb"
	bcmdhd_sdio_url="https://github.com/${user}/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-sdio-dkms_${latest_version}_all.deb"
	bcmdhd_usb_url="https://github.com/${user}/bcmdhd-dkms/releases/download/${latest_version}/bcmdhd-usb-dkms_${latest_version}_all.deb"
	if [[ "${GITHUB_MIRROR}" == "ghproxy" ]]; then
		ghproxy_header="https://ghfast.top/"
		bcmdhd_pcie_url=${ghproxy_header}${bcmdhd_pcie_url}
		bcmdhd_sdio_url=${ghproxy_header}${bcmdhd_sdio_url}
		bcmdhd_usb_url=${ghproxy_header}${bcmdhd_usb_url}
	fi
	case "${BCMDHD_TYPE}" in
		"pcie")
			bcmdhd_dkms_file_name=bcmdhd-pcie-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${bcmdhd_pcie_url} -P /tmp"
			;;
		"sdio")
			bcmdhd_dkms_file_name=bcmdhd-sdio-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${bcmdhd_sdio_url} -P /tmp"
			;;
		"usb")
			bcmdhd_dkms_file_name=bcmdhd-usb-dkms_${latest_version}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${bcmdhd_usb_url} -P /tmp"
			;;
		*)
			return 0
			;;
	esac
	display_alert "Install bcmdhd packages, will build kernel module in chroot" "${EXTENSION}" "info"
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/bcmdhd*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install /tmp/${bcmdhd_dkms_file_name}
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/bcmdhd*.deb"
}
function post_customize_image__create_bcmdhd_firmware_softlink() {
    display_alert "Fixing bcmdhd firmware softlinks" "CustomHook" "info"

    read -r -d '' CMD <<-'EOF'
        FIRMWARE_DIR="/usr/lib/firmware/ap6275p"
        if [ -d "$FIRMWARE_DIR" ]; then
            cd "$FIRMWARE_DIR" || exit 1
            for file in config.txt nvram_ap6275p.txt nvram.txt fw_bcmdhd.bin; do
                if [ -e "$file" ]; then
                    mv "$file" "${file}.bak" 2>/dev/null
                fi
            done
            ln -sf config_syn43711a0.txt config.txt
            ln -sf fw_syn43711a0_sdio.bin fw_bcmdhd.bin
            ln -sf nvram_AP6275P.txt nvram_ap6275p.txt
            ln -sf nvram_ap6611s.txt nvram.txt
        fi
EOF

    chroot_sdcard "$CMD"
}

function post_customize_image__300_optimize_ssh_reduce_lantency() {
    display_alert "Optimizing SSH configuration" "CustomHook" "info"

    read -r -d '' CMD <<-'EOF'
        SSHD_CONFIG="/etc/ssh/sshd_config"
        if [ -f "$SSHD_CONFIG" ]; then
            sed -i \
              -e 's/^#*\s*UseDNS\s*.*/UseDNS no/' \
              -e 's/^#*\s*GSSAPIAuthentication\s*.*/GSSAPIAuthentication no/' \
              "$SSHD_CONFIG"
            grep -q "^GSSAPIAuthentication" "$SSHD_CONFIG" || echo "GSSAPIAuthentication no" >> "$SSHD_CONFIG"
            grep -q "^UseDNS" "$SSHD_CONFIG" || echo "UseDNS no" >> "$SSHD_CONFIG"
        fi
        systemctl --no-reload enable orangepi5-usb2-init.service >/dev/null 2>&1
EOF

    chroot_sdcard "$CMD"
}
