#!/bin/bash

#
# Ubuntu specific functions
#
# originally written by Florian Wicke and David Mayr
# (c) 2007-2015, Hetzner Online GmbH
#
# changed and extended by Thore Bödecker, 2015-10-05
#


# setup_network_config "$ETH" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    CONFIGFILE="$FOLD/hdd/etc/network/interfaces"
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE='/dev/null'
    fi
    echo "### $COMPANY - installimage" > "$UDEVFILE"
    echo "# device: $1" >> "$UDEVFILE"
    printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$2" "$1" >> "$UDEVFILE"

    {
        echo "### $COMPANY - installimage"
        echo '# Loopback device:'
        echo 'auto lo'
        echo 'iface lo inet loopback'
        echo '' >> "$CONFIGFILE"
        if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
          echo "# device: $1"
          echo "auto  $1"
          echo "iface $1 inet static"
          echo "  address   $3"
          echo "  netmask   $5"
          echo "  gateway   $6"
          if ! is_private_ip "$3"; then
            echo '  # default route to access subnet'
            echo "  up route add -net $7 netmask $5 gw $6 $1"
          fi
        fi

        if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
          debug "setting up ipv6 networking $8/$9 via ${10}"
          echo ''
          echo "iface $1 inet6 static"
          echo "  address $8"
          echo "  netmask $9"
          echo "  gateway ${10}"
        fi

        # set duplex speed
        if ! isNegotiated && ! isVServer; then
          echo '  # force full-duplex for ports without auto-neg'
          echo "  post-up mii-tool -F 100baseTx-FD $1"
        fi
    } > "$CONFIGFILE "

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    MDADMCONF="/etc/mdadm/mdadm.conf"
    execute_chroot_command "/usr/share/mdadm/mkconf > $MDADMCONF"; EXITCODE=$?
    # Enable mdadm
    sed -i "s/AUTOCHECK=false/AUTOCHECK=true # modified by installimage/" \
        "$FOLD/hdd/etc/default/mdadm"
    sed -i "s/AUTOSTART=false/AUTOSTART=true # modified by installimage/" \
        "$FOLD/hdd/etc/default/mdadm"
    sed -i "s/START_DAEMON=false/START_DAEMON=true # modified by installimage/" \
        "$FOLD/hdd/etc/default/mdadm"
    if [ -f "$FOLD/hdd/etc/initramfs-tools/conf.d/mdadm" ]; then
      sed -i "s/BOOT_DEGRADED=false/BOOT_DEGRADED=true # modified by installimage/" \
        "$FOLD/hdd/etc/initramfs-tools/conf.d/mdadm"
    fi

    return $EXITCODE
  fi
}


# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ -n "$1" ]; then
    shopt -s extglob
    for file in "$FOLD/hdd/boot/initrd.img-"!(*.bak|*.gz); do
      VERSION="${file##*/}"
      VERSION="${VERSION#*-}"
    done
    shopt -u extglob
    echo "Kernel Version found: $VERSION" | debugoutput

    if [ "$IMG_VERSION" -ge 1204 ]; then
      # blacklist i915 driver due to many bugs and stability issues
      # required for Ubuntu 12.10 because of a kernel bug
      local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-hetzner.conf"
      {
        echo "### $COMPANY - installimage"
        echo '### silence any onboard speaker'
        echo 'blacklist pcspkr'
        echo '### i915 driver blacklisted due to various bugs'
        echo '### especially in combination with nomodeset'
        echo 'blacklist i915'
        echo 'blacklist i915_bdw'
        echo 'install i915 /bin/true'
        echo '### mei driver blacklisted due to serious bugs'
        echo 'blacklist mei'
        echo 'blacklist mei_me'
      } > "$blacklist_conf"
    fi

    sed -i "s/do_bootloader = yes/do_bootloader = no/" "$FOLD/hdd/etc/kernel-img.conf"
    execute_chroot_command "update-initramfs -u -k $VERSION"; declare -i EXITCODE="$?"
    sed -i "s/do_bootloader = no/do_bootloader = yes/" "$FOLD/hdd/etc/kernel-img.conf"

    return "$EXITCODE"
  fi
}

setup_cpufreq() {
  if [ -n "$1" ]; then
    LOADCPUFREQCONF="$FOLD/hdd/etc/default/loadcpufreq"
    CPUFREQCONF="$FOLD/hdd/etc/default/cpufrequtils"
    echo "### $COMPANY - installimage" > "$CPUFREQCONF"
    echo '# cpu frequency scaling' >> "$CPUFREQCONF"
    if isVServer; then
      echo 'ENABLE="false"' > "$LOADCPUFREQCONF"
      echo 'ENABLE="false"' >> "$CPUFREQCONF"
    else
      {
          echo 'ENABLE="true"'
          printf 'GOVERNOR="%s"' "$1"
          echo 'MAX_SPEED="0"'
          echo 'MIN_SPEED="0"'
      } >> "$CPUFREQCONF"
    fi

    return 0
  fi
}

# this is just to generate an error and should never be reached
# because we dropped support for lilo on ubuntu since 12.04
generate_config_lilo() {
  if [ -n "$1" ]; then
    return 1
  fi
}

# this is just to generate an error and should never be reached
# because we dropped support for lilo on ubuntu since 12.04
write_lilo() {
  if [ -n "$1" ]; then
    return 1
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {

  ubuntu_grub_fix
  execute_chroot_command "cd /boot; [ -e boot ] && rm -rf boot; ln -s . boot >> /dev/null 2>&1"

  # set linux_default in grub
  local grub_linux_default="nomodeset"
  if isVServer; then
     grub_linux_default="${grub_linux_default} elevator=noop"
  else
     if [ "$IMG_VERSION" -eq 1404 ]; then
       grub_linux_default="${grub_linux_default} intel_pstate=enable"
     fi
  fi

  # H8SGL need workaround for iommu
  if dmidecode -s baseboard-product-name | grep -q -i h8sgl && [ "$IMG_VERSION" -ge 1404 ] ; then
    grub_linux_default="${grub_linux_default} iommu=noaperture"
  fi

  execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_HIDDEN_TIMEOUT=.*/GRUB_HIDDEN_TIMEOUT=5/" -e "s/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=false/"'
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"'"${grub_linux_default}"'\"/"'
  execute_chroot_command 'echo -e "\n# only use text mode - other modes may scramble screen\nGRUB_GFXPAYLOAD_LINUX=\"text\"\n" >>/etc/default/grub'

  # create /run/lock if it didn't exist because it is needed by grub-mkconfig
  execute_chroot_command "mkdir -p /run/lock"

  execute_chroot_command "grub-mkconfig -o /boot/grub/grub.cfg 2>&1"

  # only install grub2 in mbr of all other drives if we use swraid
  for ((i=1; i<="$COUNT_DRIVES"; i++)); do
    if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
      local disk
      disk="$(eval echo "\$DRIVE"$i)"
      execute_chroot_command "grub-install --no-floppy --recheck $disk 2>&1"
    fi
  done

  uuid_bugfix

  PARTNUM=$(echo "$SYSTEMBOOTDEVICE" | rev | cut -c1)
  if [ "$SWRAID" = "0" ]; then
    PARTNUM="$((PARTNUM - 1))"
  fi
  return 0
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
  randomize_mdadm_checkarray_cronjob_time
  return 0
}

randomize_mdadm_checkarray_cronjob_time() {
  if [ -e "$FOLD/hdd/etc/cron.d/mdadm" ] && [ -a "$(grep checkarray "$FOLD/hdd/etc/cron.d/mdadm")" ]; then
    declare -i hour minute day
    hour="$(((RANDOM % 4) + 1))"
    minute="$(((RANDOM % 59) + 1))"
    day="$(((RANDOM % 28) + 1))"
    debug "# Randomizing cronjob run time for mdadm checkarray: day $day @ $hour:$minute"

    sed -i \
      -e "s|^57 0 \* \* 0 |$minute $hour $day \* \* |" \
      -e 's| && \[ \$\(date +\\%d\) -le 7 \]||' \
      "$FOLD/hdd/etc/cron.d/mdadm"
  else
    debug '# No /etc/cron.d/mdadm found to randomize cronjob run time'
  fi
}

ubuntu_grub_fix() {
  local mapper="$FOLD/hdd/dev/mapper"
  local tempfile="$FOLD/hdd/tmp/mapper.tmp"

<<<<<<< HEAD
  ls -l $mapper > $tempfile
  grep -v "total" $tempfile | grep -v "crw" | while read line; do
    local volgroup=$(echo $line | cut -d " " -f9)
    local dmdevice=$(echo $line | cut -d "/" -f2)
=======
  ls -l "$mapper" > "$tempfile"
  grep -v "total" "$tempfile" | grep -v "crw" | while read -r line; do
    local dmdevice volgroup
    volgroup="$(echo "$line" | cut -d " " -f9)"
    dmdevice="$(echo "$line" | cut -d "/" -f2)"
>>>>>>> 15d53fb... fix ubuntu.sh with shellcheck

    rm "$mapper/$volgroup"
    cp -R "$FOLD/hdd/dev/$dmdevice" "$mapper/$volgroup"
  done
  rm "$tempfile"
}

