#!/bin/bash

#
# CentOS specific functions
#
# (c) 2008-2016, Hetzner Online GmbH
#

# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    # good we have a device and a MAC
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE="/dev/null"
    fi
    {
      echo "### $COMPANY - installimage"
      echo "# device: $1"
      printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", KERNEL=="eth*", NAME="%s"\n' "$2" "$1"
    } > "$UDEVFILE"
    local upper_mac="${2^^*}"

    NETWORKFILE="$FOLD/hdd/etc/sysconfig/network"
    {
      echo "### $COMPANY - installimage"
      echo "# general networking"
      echo "NETWORKING=yes"
    } > "$NETWORKFILE"

    CONFIGFILE="$FOLD/hdd/etc/sysconfig/network-scripts/ifcfg-$1"
    ROUTEFILE="$FOLD/hdd/etc/sysconfig/network-scripts/route-$1"

    echo "### $COMPANY - installimage" > "$CONFIGFILE" 2>> "$DEBUGFILE"
    echo "#" >> "$CONFIGFILE" 2>> "$DEBUGFILE"
    if ! is_private_ip "$3"; then
      {
        echo "# Note for customers who want to create bridged networking for virtualisation:"
        echo "# Gateway is set in separate file"
        echo "# Do not forget to change interface in file route-$1 and rename this file"
      } >> "$CONFIGFILE" 2>> "$DEBUGFILE"
    fi
    {
      echo "#"
      echo "# device: $1"
      echo "DEVICE=$1"
      echo "BOOTPROTO=none"
      echo "ONBOOT=yes"
    } >> "$CONFIGFILE" 2>> "$DEBUGFILE"
    if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
      echo "HWADDR=$upper_mac" >> "$CONFIGFILE" 2>> "$DEBUGFILE"
      echo "IPADDR=$3" >> "$CONFIGFILE" 2>> "$DEBUGFILE"
      if is_private_ip "$3"; then
        echo "NETMASK=$5" >> "$CONFIGFILE" 2>> "$DEBUGFILE"
        echo "GATEWAY=$6" >> "$CONFIGFILE" 2>> "$DEBUGFILE"
      else
        echo "NETMASK=255.255.255.255" >> "$CONFIGFILE" 2>> "$DEBUGFILE"
        echo "SCOPE=\"peer $6\"" >> "$CONFIGFILE" 2>> "$DEBUGFILE"

        {
          echo "### $COMPANY - installimage"
          echo "# routing for eth0"
          echo "ADDRESS0=0.0.0.0"
          echo "NETMASK0=0.0.0.0"
          echo "GATEWAY0=$6"
        } > "$ROUTEFILE" 2>> "$DEBUGFILE"
      fi
    fi

    if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      {
        echo "NETWORKING_IPV6=yes"
        echo "IPV6INIT=yes"
        echo "IPV6ADDR=$8/$9"
        echo "IPV6_DEFAULTGW=${10}"
        echo "IPV6_DEFAULTDEV=$1"
      } >> "$NETWORKFILE" 2>> "$DEBUGFILE"
    fi

    # set duplex/speed
    if ! isNegotiated && ! isVServer; then
      echo 'ETHTOOL_OPTS="speed 100 duplex full autoneg off"' >> "$CONFIGFILE" 2>> "$DEBUGFILE"
    fi

    # remove all hardware info from image (CentOS 5)
    if [ -f "$FOLD/hdd/etc/sysconfig/hwconf" ]; then
      echo "" > "$FOLD/hdd/etc/sysconfig/hwconf"
    fi

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    MDADMCONF="/etc/mdadm.conf"
    echo "DEVICES /dev/[hs]d*" > "$FOLD/hdd$MDADMCONF"
    echo "MAILADDR root" >> "$FOLD/hdd$MDADMCONF"
    execute_chroot_command "mdadm --examine --scan >> $MDADMCONF"; declare -i EXITCODE=$?
    return "$EXITCODE"
  fi
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ "$1" ]; then

    # pick the latest kernel
    for file in "$FOLD/hdd/boot/vmlinuz-"*; do VERSION="${file#*-}"; done

    if [ "$IMG_VERSION" -lt 60 ] ; then
      declare -r MODULESFILE="$FOLD/hdd/etc/modprobe.conf"
      # previously we added an alias for eth0 based on the niclist (static
      # pci-id->driver mapping) of the old rescue. But the new rescue mdev/udev
      # So we only add aliases for the controller
      {
        echo "### $COMPANY - installimage"
        echo "# load all modules"
        echo ""
        echo "# hdds"
      } > "$MODULESFILE" 2>> "$DEBUGFILE"

      HDDDEV=""
      for hddmodule in $MODULES; do
        if [ "$hddmodule" != "powernow-k8" ] && [ "$hddmodule" != "via82cxxx" ] && [ "$hddmodule" != "atiixp" ]; then
          echo "alias scsi_hostadapter$HDDDEV $hddmodule" >> "$MODULESFILE" 2>> "$DEBUGFILE"
          HDDDEV="$((HDDDEV + 1))"
        fi
      done
      echo "" >> "$MODULESFILE" 2>> "$DEBUGFILE"
    elif [ "$IMG_VERSION" -ge 60 ] ; then
      # blacklist some kernel modules due to bugs and/or stability issues or annoyance
      local -r blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-hetzner.conf"
      {
        echo "### $COMPANY - installimage"
        echo "### silence any onboard speaker"
        echo "blacklist pcspkr"
        echo "### i915 driver blacklisted due to various bugs"
        echo "### especially in combination with nomodeset"
        echo "blacklist i915"
      } > "$blacklist_conf"
    fi

    if [ "$IMG_VERSION" -ge 70 ] ; then
      declare -r DRACUTFILE="$FOLD/hdd/etc/dracut.conf.d/hetzner.conf"
      {
        echo 'add_dracutmodules+="mdraid lvm"'
        echo 'add_drivers+="raid1 raid10 raid0 raid456"'
        echo 'mdadmconf="yes"'
        echo 'lvmconf="yes"'
        echo 'hostonly="no"'
        echo 'early_microcode="no"'
      } >> "$DRACUTFILE"
    fi

    if [ "$IMG_VERSION" -ge 70 ] ; then
      execute_chroot_command "/sbin/dracut -f --kver $VERSION"; declare -i EXITCODE=$?
    else
      if [ "$IMG_VERSION" -ge 60 ] ; then
        execute_chroot_command "/sbin/new-kernel-pkg --mkinitrd --dracut --depmod --install $VERSION"; declare -i EXITCODE="$?"
      else
        execute_chroot_command "/sbin/new-kernel-pkg --package kernel --mkinitrd --depmod --install $VERSION"; declare -i EXITCODE="$?"
      fi
    fi
    return "$EXITCODE"
  fi
}


setup_cpufreq() {
  if [ -n "$1" ]; then
    if isVServer; then
      debug "no powersaving on virtual machines"
      return 0
    fi
    if [ "$IMG_VERSION" -ge 70 ] ; then
      #https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/System_Administrators_Guide/sec-Persistent_Module_Loading.html
      #local CPUFREQCONF="$FOLD/hdd/etc/modules-load.d/cpufreq.conf"
      debug "no cpufreq configuration necessary"
    else
      #https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Deployment_Guide/sec-Persistent_Module_Loading.html
      local CPUFREQCONF="$FOLD/hdd/etc/sysconfig/modules/cpufreq.modules"
      {
        echo "#!/bin/sh"
        echo "### $COMPANY - installimage"
        echo "# cpu frequency scaling"
        echo "# this gets started by /etc/rc.sysinit"
      } > "$CPUFREQCONF" 2>> "$DEBUGFILE"

      if [ "$(check_cpu)" = "intel" ]; then
        debug "# Setting: cpufreq modprobe to intel"
        echo "modprobe intel_pstate >> /dev/null 2>&1" >> "$CPUFREQCONF" 2>> "$DEBUGFILE"
        echo "modprobe acpi-cpufreq >> /dev/null 2>&1" >> "$CPUFREQCONF" 2>> "$DEBUGFILE"
      else
        debug "# Setting: cpufreq modprobe to amd"
        echo "modprobe powernow-k8 >> /dev/null 2>&1" >> "$CPUFREQCONF" 2>> "$DEBUGFILE"
      fi
      echo "cpupower frequency-set --governor $1 >> /dev/null 2>&1" >> "$CPUFREQCONF" 2>> "$DEBUGFILE"
      chmod a+x "$CPUFREQCONF" >> "$DEBUGFILE"

    return 0
    fi
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  [ -n "$1" ] || return
  # we should not need to do anything, as grubby (new-kernel-pkg) should have
  # already generated a grub.conf
  if [ "$IMG_VERSION" -lt 70 ] ; then
    DMAPFILE="$FOLD/hdd/boot/grub/device.map"
  else
    # even though grub2-mkconfig will generate a device.map on the fly, the
    # anaconda installer still creates this
    DMAPFILE="$FOLD/hdd/boot/grub2/device.map"
  fi
  [ -f "$DMAPFILE" ] && rm "$DMAPFILE"
  local -i i=0
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    local j; j="$((i - 1))"
    local disk; disk="$(eval echo "\$DRIVE"$i)"
    echo "(hd$j) $disk" >> "$DMAPFILE"
  done
  cat "$DMAPFILE" >> "$DEBUGFILE"

  local elevator=''
  if isVServer; then
    elevator='elevator=noop'
  fi

  if [ "$IMG_VERSION" -lt 70 ] ; then
    execute_chroot_command "cd /boot; rm -rf boot; ln -s . boot >> /dev/null 2>&1"
    execute_chroot_command "mkdir -p /boot/grub/"
    #execute_chroot_command "grub-install --no-floppy $DRIVE1 2>&1"; declare -i EXITCODE="$?"

    BFILE="$FOLD/hdd/boot/grub/grub.conf"
    PARTNUM=$(echo "$SYSTEMBOOTDEVICE" | rev | cut -c1)

    if [ "$SWRAID" = "0" ]; then
      PARTNUM="$((PARTNUM - 1))"
    fi

    rm -rf "$FOLD/hdd/boot/grub/*" >> /dev/null 2>&1

    {
      echo "#"
      echo "# $COMPANY - installimage"
      echo "# GRUB bootloader configuration file"
      echo "#"
      echo ''
      echo "timeout 5"
      echo "default 0"
      echo >> "$BFILE"
      echo "title CentOS ($1)"
      echo "root (hd0,$PARTNUM)"
    } > "$BFILE" 2>> "$DEBUGFILE"

    # disable pcie active state power management. does not work as it should,
    # and causes problems with Intel 82574L NICs (onboard-NIC Asus P8B WS - EX6/EX8, addon NICs)
    lspci -n | grep -q '8086:10d3' && ASPM='pcie_aspm=off' || ASPM=''

    if [ "$IMG_VERSION" -ge 60 ]; then
      echo "kernel /boot/vmlinuz-$1 ro root=$SYSTEMROOTDEVICE rd_NO_LUKS rd_NO_DM nomodeset $elevator $ASPM" >> "$BFILE" 2>> "$DEBUGFILE"
    else
      echo "kernel /boot/vmlinuz-$1 ro root=$SYSTEMROOTDEVICE nomodeset" >> "$BFILE" 2>> "$DEBUGFILE"
    fi
    INITRD=''
    if [ -f "$FOLD/hdd/boot/initrd-$1.img" ]; then
     INITRD="initrd"
    fi
    if [ -f "$FOLD/hdd/boot/initramfs-$1.img" ]; then
     INITRD="initramfs"
    fi
    if [ $INITRD ]; then
      echo "initrd /boot/$INITRD-$1.img" >> "$BFILE" 2>> "$DEBUGFILE"
    fi

    echo >> "$BFILE" 2>> "$DEBUGFILE"

    uuid_bugfix
  # TODO: let grubby add its own stuff (SYSFONT, LANG, KEYTABLE)
#  if [ $IMG_VERSION -lt 60 ] ; then
#   execute_chroot_command "/sbin/new-kernel-pkg --package kernel --install $VERSION"; declare -i EXITCODE="$?"
#  else
#   execute_chroot_command "/sbin/new-kernel-pkg --install $VERSION"; declare -i EXITCODE="$?"
#  fi
  else
    if isVServer; then
      execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset rd.auto=1 crashkernel=auto elevator=noop\"/"'
    else
      execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"nomodeset rd.auto=1 crashkernel=auto\"/"'
    fi

    [ -e "$FOLD/hdd/boot/grub2/grub.cfg" ] && rm "$FOLD/hdd/boot/grub2/grub.cfg"
    execute_chroot_command "grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1"; declare -i EXITCODE="$?"

  fi
  return "$EXITCODE"
}

write_grub() {
  if [ "$IMG_VERSION" -ge 70 ] ; then
    # only install grub2 in mbr of all other drives if we use swraid
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
        local disk; disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "grub2-install --no-floppy --recheck $disk 2>&1" declare -i EXITCODE=$?
      fi
    done
  else
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ $i -eq 1 ] ;  then
        local disk; disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "echo -e \"device (hd0) $disk\nroot (hd0,$PARTNUM)\nsetup (hd0)\nquit\" | grub --batch >> /dev/null 2>&1"
      fi
    done
  fi

  return $?
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {

  execute_chroot_command "chkconfig iptables off"

  #
  # setup env in cpanel image
  #
  debug "# Testing and setup of cpanel image"
  if [ -f "$FOLD/hdd/etc/wwwacct.conf" ] && [ -f "$FOLD/hdd/etc/cpupdate.conf" ] ; then
    grep -q -i cpanel <<< "$IMAGENAME" && {
      setup_cpanel || return 1
    }
  fi

  # selinux autorelabel if enabled
  egrep -q "SELINUX=enforcing" "$FOLD/hdd/etc/sysconfig/selinux)" &&
    touch "$FOLD/hdd/.autorelabel"

  return 0

}

setup_cpanel() {
  randomize_cpanel_mysql_passwords
  change_mainIP
  modify_wwwacct
}

#
# randomize mysql passwords in cpanel image
#
randomize_cpanel_mysql_passwords() {
  CPHULKDCONF="$FOLD/hdd/var/cpanel/hulkd/password"
  CPHULKDPASS=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c16)
  ROOTPASS=$(tr -dc _A-Z-a-z-0-9 < /dev/urandom | head -c8)
  MYSQLCOMMAND="UPDATE mysql.user SET password=PASSWORD(\"$CPHULKDPASS\") WHERE user='cphulkd'; \
  UPDATE mysql.user SET password=PASSWORD(\"$ROOTPASS\") WHERE user='root';\nFLUSH PRIVILEGES;"
  echo "$MYSQLCOMMAND" > "$FOLD/hdd/tmp/pwchange.sql"
  debug "changing mysql passwords"
  execute_chroot_command "service mysql start --skip-grant-tables --skip-networking >/dev/null 2>&1"; declare -i EXITCODE=$?
  execute_chroot_command "mysql < /tmp/pwchange.sql >/dev/null 2>&1"; declare -i EXITCODE=$?
  execute_chroot_command "service mysql stop >/dev/null 2>&1"
  cp "$CPHULKDCONF" "$CPHULKDCONF.old"
  sed s/pass.*/"pass=\"$CPHULKDPASS\""/g "$CPHULKDCONF.old" > "$CPHULKDCONF"
  rm "$FOLD/hdd/tmp/pwchange.sql"
  rm "$CPHULKDCONF.old"

  # write password file
  {
    echo "[client]"
    echo "user=root"
    echo "pass=$ROOTPASS"
  } > "$FOLD/hdd/root/.my.cnf"

  return "$EXITCODE"
}

#
# set the content of /var/cpanel/mainip correct
#
change_mainIP() {
  MAINIPFILE="/var/cpanel/mainip"
  debug "changing content of ${MAINIPFILE}"
  execute_chroot_command "echo -n ${IPADDR} > $MAINIPFILE"
}

#
# set the correct hostname, IP and nameserver in /etc/wwwacct.conf
#
modify_wwwacct() {
  WWWACCT="/etc/wwwacct.conf"
  NS="ns1.first-ns.de"
  NS2="robotns2.second-ns.de"
  NS3="robotns3.second-ns.com"

  debug "setting hostname in ${WWWACCT}"
  execute_chroot_command "echo \"HOST ${SETHOSTNAME}\" >> $WWWACCT"
  debug "setting IP in ${WWWACCT}"
  execute_chroot_command "echo \"ADDR ${IPADDR}\" >> $WWWACCT"
  debug "setting NS in ${WWWACCT}"
  execute_chroot_command "echo \"NS ${NS}\" >> $WWWACCT"
  execute_chroot_command "echo \"NS2 ${NS2}\" >> $WWWACCT"
  execute_chroot_command "echo \"NS3 ${NS3}\" >> $WWWACCT"
}

# vim: ai:ts=2:sw=2:et
