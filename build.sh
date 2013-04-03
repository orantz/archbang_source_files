#!/bin/bash

set -e -u -x

iso_name=archbang-rc
iso_label="ARCHBANG"
iso_version=$(date +%d.%m.%Y)
install_dir=arch
work_dir=work
out_dir=out
arch=$(uname -m)
arch_type=""
verbose=""
pacman_conf=${work_dir}/pacman.conf
script_path=$(readlink -f ${0%/*})

_usage ()
{
    echo "usage ${0} [options]"
    echo
    echo " General options:"
    echo "    -N <iso_name>      Set an iso filename (prefix)"
    echo "                        Default: ${iso_name}"
		echo "    -a <arch>          Set arch of iso"
    echo "                        Default: ${arch}"
    echo "    -V <iso_version>   Set an iso version (in filename)"
    echo "                        Default: ${iso_version}"
    echo "    -L <iso_label>     Set an iso label (disk label)"
    echo "                        Default: ${iso_label}"
    echo "    -D <install_dir>   Set an install_dir (directory inside iso)"
    echo "                        Default: ${install_dir}"
    echo "    -w <work_dir>      Set the working directory"
    echo "                        Default: ${work_dir}"
    echo "    -o <out_dir>       Set the output directory"
    echo "                        Default: ${out_dir}"
    echo "    -v                 Enable verbose output"
    echo "    -h                 This help message"
    exit ${1}
}

# Helper function to run make_*() only one time per architecture.
run_once() {
    if [[ ! -e ${work_dir}/build.${1}_${arch} ]]; then
        $1
        touch ${work_dir}/build.${1}_${arch}
    fi
}

# Setup custom pacman.conf with current cache directories.
make_pacman_conf() {
    local _cache_dirs
    _cache_dirs=($(pacman -v 2>&1 | grep '^Cache Dirs:' | sed 's/Cache Dirs:\s*//g'))
    sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n ${_cache_dirs[@]})|g" ${script_path}/pacman.conf > ${pacman_conf}
		sed -i "s|custompkgs-|custompkgs-${arch}|g" ${pacman_conf}
}

# Base installation, plus needed packages (root-image)
make_basefs() {
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}/${arch}" -C "${pacman_conf}" -D "${install_dir}" init
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}/${arch}" -C "${pacman_conf}" -D "${install_dir}" -p "memtest86+ mkinitcpio-nfs-utils nbd" install
}

# Additional packages (root-image)
make_packages() {
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}/${arch}" -C "${pacman_conf}" -D "${install_dir}" -p "$(grep -h -v ^# ${script_path}/packages)" install
}

# Copy mkinitcpio archiso hooks and build initramfs (root-image)
make_setup_mkinitcpio() {
    local _hook
    for _hook in archiso archiso_shutdown archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs archiso_loop_mnt; do
        cp /usr/lib/initcpio/hooks/${_hook} ${work_dir}/${arch}/root-image/usr/lib/initcpio/hooks
        cp /usr/lib/initcpio/install/${_hook} ${work_dir}/${arch}/root-image/usr/lib/initcpio/install
    done
    cp /usr/lib/initcpio/install/archiso_kms ${work_dir}/${arch}/root-image/usr/lib/initcpio/install
    cp /usr/lib/initcpio/archiso_shutdown ${work_dir}/${arch}/root-image/usr/lib/initcpio
    cp ${script_path}/mkinitcpio.conf ${work_dir}/${arch}/root-image/etc/mkinitcpio-archiso.conf
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}/${arch}" -C "${pacman_conf}" -D "${install_dir}" -r 'mkinitcpio -c /etc/mkinitcpio-archiso.conf -k /boot/vmlinuz-linux -g /boot/archiso.img' run
}

# Customize installation (root-image)
make_customize_root_image() {
    cp -af ${script_path}/root-image ${work_dir}/${arch}
		# this will need work mirrorlist
    patch ${work_dir}/${arch}/root-image/usr/bin/pacman-key < ${script_path}/pacman-key-4.0.3_unattended-keyring-init.patch
		wget -O ${work_dir}/${arch}/root-image/etc/pacman.d/mirrorlist 'https://www.archlinux.org/mirrorlist/?country=all&protocol=http'
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}/${arch}" -C "${pacman_conf}" -D "${install_dir}" -r '/root/customize_root_image.sh' run
    rm ${work_dir}/${arch}/root-image/root/customize_root_image.sh
}

# Prepare kernel/initramfs ${install_dir}/boot/
make_boot() {
    mkdir -p ${work_dir}/iso/${install_dir}/boot/${arch}
    cp ${work_dir}/${arch}/root-image/boot/archiso.img ${work_dir}/iso/${install_dir}/boot/${arch}/archiso.img
    cp ${work_dir}/${arch}/root-image/boot/vmlinuz-linux ${work_dir}/iso/${install_dir}/boot/${arch}/vmlinuz
}

# Add other aditional/extra files to ${install_dir}/boot/
make_boot_extra() {
    cp ${work_dir}/${arch}/root-image/boot/memtest86+/memtest.bin ${work_dir}/iso/${install_dir}/boot/memtest
    cp ${work_dir}/${arch}/root-image/usr/share/licenses/common/GPL2/license.txt ${work_dir}/iso/${install_dir}/boot/memtest.COPYING
}

# Prepare /${install_dir}/boot/syslinux
make_syslinux() {
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux
    for _cfg in ${script_path}/syslinux/*.cfg; do
        sed "s|%ARCHISO_LABEL%|${iso_label}|g;
             s|%INSTALL_DIR%|${install_dir}|g;
						 s|%ARCH%|${arch}|g" ${_cfg} > ${work_dir}/iso/${install_dir}/boot/syslinux/${_cfg##*/}
    done
    cp ${script_path}/syslinux/splash.png ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/${arch}/root-image/usr/lib/syslinux/*.c32 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/${arch}/root-image/usr/lib/syslinux/*.com ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/${arch}/root-image/usr/lib/syslinux/*.0 ${work_dir}/iso/${install_dir}/boot/syslinux
    cp ${work_dir}/${arch}/root-image/usr/lib/syslinux/memdisk ${work_dir}/iso/${install_dir}/boot/syslinux
    mkdir -p ${work_dir}/iso/${install_dir}/boot/syslinux/hdt
    gzip -c -9 ${work_dir}/${arch}/root-image/usr/share/hwdata/pci.ids > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/pciids.gz
    gzip -c -9 ${work_dir}/${arch}/root-image/usr/lib/modules/*-ARCH/modules.alias > ${work_dir}/iso/${install_dir}/boot/syslinux/hdt/modalias.gz
}

# Prepare /isolinux
make_isolinux() {
    mkdir -p ${work_dir}/iso/isolinux
    sed "s|%INSTALL_DIR%|${install_dir}|g" ${script_path}/isolinux/isolinux.cfg > ${work_dir}/iso/isolinux/isolinux.cfg
    cp ${work_dir}/${arch}/root-image/usr/lib/syslinux/isolinux.bin ${work_dir}/iso/isolinux/
    cp ${work_dir}/${arch}/root-image/usr/lib/syslinux/isohdpfx.bin ${work_dir}/iso/isolinux/
}

# Copy aitab
make_aitab() {
    mkdir -p ${work_dir}/iso/${install_dir}
		sed "s|%ARCH%|${arch}|g" ${script_path}/aitab > ${work_dir}/iso/${install_dir}/aitab
    #cp ${script_path}/aitab ${work_dir}/iso/${install_dir}/aitab
}

# Build all filesystem images specified in aitab (.fs.sfs .sfs)
make_prepare() {
    cp -a -l -f ${work_dir}/${arch}/root-image ${work_dir}
#   setarch ${arch} mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" pkglist
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" prepare
    rm -rf ${work_dir}/root-image
    # rm -rf ${work_dir}/${arch}/root-image (if low space, this helps)
}

# Build ISO
make_iso() {
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" checksum
    setarch ${arch} mkarchiso ${verbose} -w "${work_dir}" -D "${install_dir}" -L "${iso_label}" -o "${out_dir}" iso "${iso_name}-${iso_version}-${arch}.iso"
}

# Does what it says...
remove_useless_shortcuts()
{
useless_path="${work_dir}/${arch}/root-image/usr/share/applications"
rm ${useless_path}/avahi* &>/dev/null
rm ${useless_path}/bvnc* &>/dev/null
rm ${useless_path}/bssh* &>/dev/null
rm ${useless_path}/7z* &>/dev/null
rm ${useless_path}/qv4* &>/dev/null
rm ${useless_path}/dconf-editor.desktop &>/dev/null
rm ${work_dir}/${arch}/root-image/etc/xdg/autostart/nm-applet.desktop &>/dev/null
}

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    _usage 1
fi

#if [[ ${arch} != x86_64 ]]; then
#    echo "This script needs to be run on x86_64"
#    _usage 1
#fi

while getopts 'a:N:V:L:D:w:o:vh' arg; do
    case "${arg}" in
				a) arch_type="${OPTARG}" ;;
        N) iso_name="${OPTARG}" ;;
        V) iso_version="${OPTARG}" ;;
        L) iso_label="${OPTARG}" ;;
        D) install_dir="${OPTARG}" ;;
        w) work_dir="${OPTARG}" ;;
        o) out_dir="${OPTARG}" ;;
        v) verbose="-v" ;;
        h) _usage 0 ;;
        *)
           echo "Invalid argument '${arg}'"
           _usage 1
           ;;
    esac
done

build_iso() {
mkdir -p ${work_dir}

run_once make_pacman_conf

# Do all stuff for each root-image
run_once make_basefs
run_once make_packages
run_once make_setup_mkinitcpio
run_once remove_useless_shortcuts
run_once make_customize_root_image
run_once make_boot

# Do all stuff for "iso"
run_once make_boot_extra
run_once make_syslinux
run_once make_isolinux
run_once make_aitab
run_once make_prepare
run_once make_iso
}

[[ ! -z "${arch_type}" ]] && arch=${arch_type}

# Create iso	
build_iso

