#!/bin/bash

#
# Archlinux specific functions
#
# (c) 2013-2016, Hetzner Online GmbH
#

# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    # good we have a device and a MAC
    CONFIGFILE="$FOLD/hdd/etc/systemd/network/50-$C_SHORT.network"
    UDEVFILE="$FOLD/hdd/etc/udev/rules.d/80-net-setup-link.rules"

    {
      echo "### $COMPANY - installimage"
      echo "# device: $1"
      printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$2" "$1"
    } > "$UDEVFILE"

    {
      echo "### $COMPANY - installimage"
      echo "# device: $1"
      echo "[Match]"
      echo "MACAddress=$2"
      echo ""
    } > "$CONFIGFILE"


    # setup addresses
    # $9 is the subnet mask parsed from /proc/cmdline
    if [ -n "$8" ] && [ -n "${10}" ]; then
      debug "setting up ipv6 networking $8/128 via ${10}"
      {
        echo "[Address]"
        echo "Address=${8}/128"
        echo ""
      } >> "$CONFIGFILE"
    fi

    # $5 is the subnet mask in long format. e.g.: 255.255.255.0
    if [ -n "$3" ] && [ -n "$4" ] && [ -n "$6" ] && [ -n "$7" ]; then
      debug "setting up ipv4 networking $3/32 via $6"
      {
        echo "[Address]"
        echo "Address=$3/32"
        echo "Peer=$6/32"
        echo ""
      } >> "$CONFIGFILE"

    fi

    # setup network section with gateways
    debug "setting up ipv4/ipv6 gateways"
    echo "[Network]" >> "$CONFIGFILE"
    if [ -n "$6" ]; then
      echo "Gateway=${6}" >> "$CONFIGFILE"
    fi

    if [ -n "${10}" ]; then
      echo "Gateway=${10}" >> "$CONFIGFILE"
    fi

    execute_chroot_command "systemctl enable systemd-networkd.service"

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    local mdadmconf="/etc/mdadm.conf"
    {
      echo "DEVICE partitions"
      echo "MAILADDR root"
    } > "$FOLD/hdd$mdadmconf"
    execute_chroot_command "mdadm --examine --scan >> $mdadmconf"; declare -i EXITCODE=$?
    return "$EXITCODE"
  fi
}


# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ -n "$1" ]; then
    local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-$C_SHORT.conf"
    {
      echo "### $COMPANY - installimage"
      echo "### silence any onboard speaker"
      echo "blacklist pcspkr"
      echo "blacklist snd_pcsp"
      echo "### i915 driver blacklisted due to various bugs"
      echo "### especially in combination with nomodeset"
      echo "blacklist i915"
      echo "### mei driver blacklisted due to serious bugs"
      echo "blacklist mei"
      echo "blacklist mei-me"
    } > "$blacklist_conf"

    execute_chroot_command 'sed -i /etc/mkinitcpio.conf -e "s/^HOOKS=.*/HOOKS=\"base systemd autodetect keyboard sd-vconsole modconf block mdadm_udev sd-lvm2 filesystems fsck\"/"'
    execute_chroot_command "mkinitcpio -p linux"; EXITCODE=$?

    return "$EXITCODE"
  fi
}

setup_cpufreq() {
  if [ -n "$1" ]; then
    if ! isVServer; then
      local cpufreqconf=''
      cpufreqconf="$FOLD/hdd/etc/default/cpupower"
      sed -i -e "s/#governor=.*/governor'$1'/" "$cpufreqconf"
      execute_chroot_command "systemctl enable cpupower"
    fi

    return 0
  fi
}

#
# generate_config_grub
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  EXITCODE=0
  execute_chroot_command "rm -rf /boot/grub; mkdir -p /boot/grub/ >> /dev/null 2>&1"
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"nomodeset\"/"'
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^#GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT=console/"'

  execute_chroot_command "grub-mkconfig -o /boot/grub/grub.cfg 2>&1"

  execute_chroot_command "grub-install --no-floppy --recheck $DRIVE1 2>&1";
  declare -i EXITCODE=$?

  # only install grub2 in mbr of all other drives if we use swraid
  if [ "$SWRAID" = "1" ] ;  then
    local i=2
    while [ "$(eval echo "\$DRIVE"$i)" ]; do
      local targetdrive; targetdrive="$(eval echo "\$DRIVE$i")"
      execute_chroot_command "grub-install --no-floppy --recheck $targetdrive 2>&1"
      declare -i EXITCODE=$?
      let i=i+1
    done
fi
  uuid_bugfix

  return "$EXITCODE"
}


#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {

  execute_chroot_command "pacman-key --init"
  execute_chroot_command "pacman-key --populate archlinux"
  execute_chroot_command "systemctl enable sshd"
  execute_chroot_command "systemctl enable haveged"
  execute_chroot_command "systemctl enable systemd-timesyncd"

  return 0
}

# validate image with detached signature
validate_image() {
  # no detached sign found
  return 2
}

# extract image file to hdd
extract_image() {
  mkdir -p "$FOLD/hdd/var/lib/pacman"
  mkdir -p "$FOLD/hdd/var/cache/pacman/pkg"
  LANG=C pacman \
    --noconfirm \
    --root "$FOLD/hdd" \
    --dbpath "$FOLD/hdd/var/lib/pacman" \
    --cachedir "$FOLD/hdd/var/cache/pacman/pkg" \
    -Syyu base btrfs-progs cpupower findutils gptfdisk grub haveged openssh vim wget ca-certificates ca-certificates-utils pacman-mirrorlist 2>&1 | debugoutput
  declare -i EXITCODE=$?

  if [ "$EXITCODE" -eq "0" ]; then
    cp -r "$FOLD/fstab" "$FOLD/hdd/etc/fstab" 2>&1 | debugoutput

    #timezone - we are in Germany
    execute_chroot_command "ln -s /usr/share/timezone/Europe/Berlin /etc/localtime"
    {
      echo "en_US.UTF-8 UTF-8"
      echo "de_DE.UTF-8 UTF-8"
    } > "$FOLD/hdd/etc/locale.gen"
    execute_chroot_command "locale-gen"

    {
      echo "LANG=en_US.UTF-8"
      echo "LC_MESSAGES=C"
    } > "$FOLD/hdd/etc/locale.conf"

    {
      echo "KEYMAP=de"
      echo "FONT=LatArCyrHeb-16"
    } > "$FOLD/hdd/etc/vconsole.conf"

    return 0
  else
    return 1
  fi
}
# vim: ai:ts=2:sw=2:et
