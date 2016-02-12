#!/bin/bash

#
# OpenSUSE specific functions
#
# originally written by Florian Wicke and David Mayr
# (c) 2007-2015, Hetzner Online GmbH
#
# changed and extended by Thore Bödecker, 2015-10-05
# changed and extended by Tim Meusel
# changed and extended by Silvio Knizek
#


# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    # good we have a device and a MAC

    SUSEVERSION="$(grep VERSION $FOLD/hdd/etc/SuSE-release | cut -d ' '  -f3 | sed -e 's/\.//')"
    debug "# Version: ${SUSEVERSION}"

    ROUTEFILE="$FOLD/hdd/etc/sysconfig/network/routes"
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE="/dev/null"
    fi
    # Delete network udev rules
#    rm $FOLD/hdd/etc/udev/rules.d/*-persistent-net.rules 2>&1 | debugoutput

    echo "### $COMPANY - installimage" > $UDEVFILE
    echo "# device: $1" >> $UDEVFILE
    printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", KERNEL=="eth*", NAME="%s"\n' "$2" "$1" >> "$UDEVFILE"

    # remove any other existing config files
    for i in $(find "$FOLD/hdd/etc/sysconfig/network/" -name "*-eth*"); do rm -rf "$i" >>/dev/null 2>&1; done

    CONFIGFILE="$FOLD/hdd/etc/sysconfig/network/ifcfg-$1"

    echo "### $COMPANY - installimage" > "$CONFIGFILE"
    echo "# device: $1" >> "$CONFIGFILE"
    echo "BOOTPROTO='static'" >> "$CONFIGFILE"
    echo "MTU=''" >> "$CONFIGFILE"
    echo "STARTMODE='auto'" >> "$CONFIGFILE"
    echo "UNIQUE=''" >> "$CONFIGFILE"
    echo "USERCONTROL='no'" >> "$CONFIGFILE"

    if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
      echo "REMOTE_IPADDR=''" >> "$CONFIGFILE"
      echo "BROADCAST='$4'" >> "$CONFIGFILE"
      echo "IPADDR='$3'" >> "$CONFIGFILE"
      echo "NETMASK='$5'" >> "$CONFIGFILE"
      echo "NETWORK='$7'" >> "$CONFIGFILE"

      echo "$7 $6 $5 $1" > "$ROUTEFILE"
      echo "$6 - 255.255.255.255 $1" >> "$ROUTEFILE"
      echo "default $6 - -" >> "$ROUTEFILE"
    fi

    if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      if [ -n "$3" ]; then
      # add v6 addr as an alias, if we have a v4 addr
        echo "IPADDR_0='$8/$9'" >> "$CONFIGFILE"
      else
        echo "IPADDR='$8/$9'" >> "$CONFIGFILE"
      fi
      echo "default ${10} - $1" >> "$ROUTEFILE"
    fi

    if ! isNegotiated && ! isVServer; then
      echo 'ETHTOOL_OPTIONS="speed 100 duplex full autoneg off"' >> "$CONFIGFILE"
    fi

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ "$1" ]; then
    MDADMCONF="/etc/mdadm.conf"
    echo "DEVICES /dev/[hs]d*" > "$FOLD/hdd$MDADMCONF"
    echo "MAILADDR root" >> "$FOLD/hdd$MDADMCONF"
    if [ "$SUSEVERSION" -ge 132 ] ; then
      echo >> "$FOLD/hdd$MDADMCONF"
    fi
#    if [ "$SUSEVERSION" = "11.0" -o "$SUSEVERSION" = "11.2" -o "$SUSEVERSION" = "11.3" -o "$SUSEVERSION" = "11.4" -o "$SUSEVERSION" = "12.1"  -o "$SUSEVERSION" = "12.2" ]; then
    if [ "$SUSEVERSION" -ge 110 ]; then
      # Suse 11.2 argues about failing opening of /dev/md/<number>, so do a --examine instead of --details
      execute_chroot_command "mdadm --examine --scan >> $MDADMCONF"; declare -i EXITCODE=$?
    else
      execute_chroot_command "mdadm --detail --scan >> $MDADMCONF"; declare -i EXITCODE=$?
    fi
    return $EXITCODE
  fi
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ -n "$1" ]; then

    # opensuse 13.2 uses dracut for generating initrd
    if [ "$SUSEVERSION" -lt 132 ] ; then
      KERNELCONF="$FOLD/hdd/etc/sysconfig/kernel"

      sed -i "$KERNELCONF" -e 's/INITRD_MODULES=.*/INITRD_MODULES=""/'

      #do not load kms and nouveau modules during boot
      if [ "$SUSEVERSION" -ge 113 ]; then
        sed -i "$KERNELCONF" -e 's/^NO_KMS_IN_INITRD=.*/NO_KMS_IN_INIRD="yes"/'
      fi
    fi

    local blacklist_conf="$FOLD/hdd/etc/modprobe.d/99-local.conf"
    echo "### $COMPANY - installimage" > "$blacklist_conf"
    echo '### silence any onboard speaker' >> "$blacklist_conf"
    echo 'blacklist pcspkr' >> "$blacklist_conf"
    echo 'blacklist snd_pcsp' >> "$blacklist_conf"
    echo '### i915 driver blacklisted due to various bugs' >> "$blacklist_conf"
    echo '### especially in combination with nomodeset' >> "$blacklist_conf"
    echo 'blacklist i915' >> "$blacklist_conf"
    echo '### mei driver blacklisted due to serious bugs' >> "$blacklist_conf"
    echo 'blacklist mei' >> "$blacklist_conf" >> "$blacklist_conf"
    echo 'blacklist mei-me' >> "$blacklist_conf">> "$blacklist_conf"

    local dracut_feature=''
    local dracut_modules=''
    if [ "$SWRAID" = "1" ]; then
       dracut_feature="$dracut_feature mdraid"
       dracut_modules="$dracut_modules raid0 raid1 raid10 raid456"
    fi
    [ "$LVM" = "1" ] && dracut_feature="$dracut_feature lvm"


    # change the if contruct to test
    if [ "$SUSEVERSION" -ge 112 ]; then
      # mkinitrd doesn't have the switch -t anymore as of 11.2 and uses /dev/shm if it is writeable
      if [ "$SUSEVERSION" -ge 121 ]; then
        # run without updating bootloader as this would fail because of missing
        # or at this point still wrong device.map.
        # A device.map is temp. generated by grub2-install in 12.2
        mkinitcmd="mkinitrd -B"
        if [ "$SUSEVERSION" -ge 132 ]; then
          [ -n "$dracut_feature" ] && mkinitcmd="$mkinitcmd -f '$dracut_feature'"
          [ -n "$dracut_modules" ] && mkinitcmd="$mkinitcmd -m '$dracut_modules'"
          execute_chroot_command "$mkinitcmd"; declare -i EXITCODE=$?
        else
          execute_chroot_command "$mkinitcmd"; declare -i EXITCODE=$?
        fi
      else
        execute_chroot_command "mkinitrd"; declare -i EXITCODE=$?
      fi
    else
      execute_chroot_command "mkinitrd -t /tmp"; declare -i EXITCODE=$?
    fi
    return "$EXITCODE"
  fi
}

setup_cpufreq() {
  if [ -n "$1" ]; then
     # openSuSE defaults to the ondemand governor, so we don't need to set this at all
     # http://doc.opensuse.org/documentation/html/openSUSE/opensuse-tuning/cha.tuning.power.html
     # check release notes of furture releases carefully, if this has changed!

#    CPUFREQCONF="$FOLD/hdd/etc/init.d/boot.local"
#    echo -e "### $COMPANY - installimage" > $CPUFREQCONF 2>>$DEBUGFILE
#    echo -e "# cpu frequency scaling" >> $CPUFREQCONF 2>>$DEBUGFILE
#    echo -e "cpufreq-set -g $1 -r >> /dev/null 2>&1" >> $CPUFREQCONF 2>>$DEBUGFILE

    return 0
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  [ -n "$1" ] || return

  declare -i EXITCODE=0

  if [ "$SUSEVERSION" -lt 122 ]; then
    DMAPFILE="$FOLD/hdd/boot/grub/device.map"
  else
    # even though grub2-mkconfig will generate a device.map on the fly, the
    # yast perl bootloader script, will use the fscking device.map, as well as
    # mkinitrd (which also uses the perl bootloader script) if the -B option is
    # not passed
    DMAPFILE="$FOLD/hdd/boot/grub2/device.map"
  fi
  [ -f "$DMAPFILE" ] && rm "$DMAPFILE"
  local -i i=0
  for ((i=1; i<="$COUNT_DRIVES"; i++)); do
    local j="$((i - 1))"
    local disk="$(eval echo "\$DRIVE"$i)"
    echo "(hd$j) $disk" >> "$DMAPFILE"
  done
  cat "$DMAPFILE" >> "$DEBUGFILE"

  if [ "$SUSEVERSION" -lt 122 ]; then
    BFILE="$FOLD/hdd/boot/grub/menu.lst"

    echo '#' > "$BFILE" 2>> "$DEBUGFILE"
    echo "# $COMPANY - installimage" >> "$BFILE" 2>> "$DEBUGFILE"
    echo '# GRUB bootloader configuration file' >> "$BFILE" 2>> "$DEBUGFILE"
    echo '#' >> "$BFILE" 2>> "$DEBUGFILE"
    echo >> "$BFILE" 2>> "$DEBUGFILE"

    PARTNUM=$(echo "$SYSTEMBOOTDEVICE" | rev | cut -c1)

    if [ "$SWRAID" = "0" ]; then
      PARTNUM="$((PARTNUM - 1))"
    fi

    echo 'timeout 5' >> "$BFILE" 2>> "$DEBUGFILE"
    echo 'default 0' >> "$BFILE" 2>> "$DEBUGFILE"
    echo >> "$BFILE" 2>> "$DEBUGFILE"
    echo 'title Linux (openSUSE)' >> "$BFILE" 2>> "$DEBUGFILE"
    echo "root (hd0,$PARTNUM)" >> "$BFILE" 2>> "$DEBUGFILE"
    echo "kernel /boot/vmlinuz-$1 root=$SYSTEMROOTDEVICE vga=0x317" >> "$BFILE" 2>> "$DEBUGFILE"

    if [ -f "$FOLD/hdd/boot/initrd-$1" ]; then
      echo "initrd /boot/initrd-$1" >> "$BFILE" 2>> "$DEBUGFILE"
    fi
    echo >> "$BFILE" 2>> "$DEBUGFILE"

  else
    local grub_linux_default="nomodeset"
    # set net.ifnames=0 to avoid predictable interface names for opensuse 13.2
    if [ "$SUSEVERSION" -ge 132 ] ; then
      grub_linux_default="${grub_linux_default} net.ifnames=0 quiet systemd.show_status=1"
    fi
    # set elevator to noop for vserver
    if isVServer; then
      grub_linux_default="${grub_linux_default} elevater=noop"
    fi
    # H8SGL need workaround for iommu
    if [ -n "$(dmidecode -s baseboard-product-name | grep -i h8sgl)" -a $IMG_VERSION -ge 131 ] ; then
      grub_linux_default="${grub_linux_default} iommu=noaperture"
    fi

    execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_HIDDEN_TIMEOUT=.*/#GRUB_HIDDEN_TIMEOUT=5/" -e "s/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/#GRUB_HIDDEN_TIMEOUT_QUIET=false/"'
    execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"'"${grub_linux_default}"'\"/"'

    execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_TERMINAL=.*/GRUB_TERMINAL=console/"'

    [ -e $FOLD/hdd/boot/grub2/grub.cfg ] && rm "$FOLD/hdd/boot/grub2/grub.cfg"
    execute_chroot_command "grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1"

    # the opensuse mkinitrd uses this file to determine where to write the bootloader...
    GRUBINSTALLDEV_FILE="$FOLD/hdd/etc/default/grub_installdevice"
    [ -f "$GRUBINSTALLDEV_FILE" ] && rm "$GRUBINSTALLDEV_FILE"
    for ((i=1; i<="$COUNT_DRIVES"; i++)); do
      local disk="$(eval echo "\$DRIVE"$i)"
      echo "$disk" >> "$GRUBINSTALLDEV_FILE"
    done
    echo "generic_mbr" >> "$GRUBINSTALLDEV_FILE"
  fi

  return "$EXITCODE"
}

#
# write_grub
#
# Write the GRUB bootloader into the MBR
#
write_grub() {
  # grub1 for all before OpenSuSE 12.2
  if [ "$SUSEVERSION" -lt 122 ]; then
    execute_chroot_command "rm -rf /etc/lilo.conf"

    for ((i=1; i<="$COUNT_DRIVES"; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ $i -eq 1 ] ;  then
        local disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "echo -e \"device (hd0) $disk\nroot (hd0,$PARTNUM)\nsetup (hd0)\nquit\" | grub --batch >> /dev/null 2>&1"
      fi
    done
  else
    # only install grub2 in mbr of all other drives if we use swraid
    for ((i=1; i<="$COUNT_DRIVES"; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
        local disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "grub2-install --no-floppy --recheck $disk 2>&1" declare -i EXITCODE="$?"
      fi
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
  return 0
}

