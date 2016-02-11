#!/bin/bash

#
# Debian specific functions
#
# originally written by Florian Wicke and David Mayr
# (c) 2008-2015, Hetzner Online GmbH
#
# changed and extended by Thore Bödecker, 2015-10-05
# changed and extended by Tim Meusel
#

# setup_network_config "$device" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
setup_network_config() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    # good we have a device and a MAC
    CONFIGFILE="$FOLD/hdd/etc/network/interfaces"
    if [ -f "$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules" ]; then
      UDEVFILE="$FOLD/hdd/etc/udev/rules.d/70-persistent-net.rules"
    else
      UDEVFILE="/dev/null"
    fi
    echo "### $COMPANY - installimage" > "$UDEVFILE"
    echo "# device: $1" >> $UDEVFILE
    printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$2" "$1" >> "$UDEVFILE"
    {
      echo "### $COMPANY - installimage"
      echo "# Loopback device:"
      echo "auto lo"
      echo "iface lo inet loopback"
      echo ""
    } > "$CONFIGFILE"

    if [ -n "$3" ] && [ -n "$4" ] && [ -n "$5" ] && [ -n "$6" ] && [ -n "$7" ]; then
      {
        echo "# device: $1"
        echo "auto  $1"
        echo "iface $1 inet static"
        echo "  address   $3"
        echo "  netmask   $5"
        echo "  gateway   $6"
        if ! is_private_ip "$3"; then
          echo "  # default route to access subnet"
          echo "  up route add -net $7 netmask $5 gw $6 $1"
        fi
      } >> "$CONFIGFILE"
    fi

    if [ -n "$8" ] && [ -n "$9" ] && [ -n "${10}" ]; then
      debug "setting up ipv6 networking $8/$9 via ${10}"
      {
        echo ""
        echo "iface $1 inet6 static"
        echo "  address $8"
        echo "  netmask $9"
        echo "  gateway ${10}"
      } >> "$CONFIGFILE"
    fi

    #
    # set duplex speed
    #
    if ! isNegotiated && ! isVServer; then
      echo "  # force full-duplex for ports without auto-neg" >> "$CONFIGFILE"
      echo "  post-up mii-tool -F 100baseTx-FD $1" >> "$CONFIGFILE"
    fi

    return 0
  fi
}

# generate_mdadmconf "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    MDADMCONF="/etc/mdadm/mdadm.conf"
    # echo "DEVICES /dev/[hs]d*" > $FOLD/hdd$MDADMCONF
    # execute_chroot_command "mdadm --detail --scan | sed -e 's/metadata=00.90/metadata=0.90/g' >> $MDADMCONF"; declare -i EXITCODE=$?
    execute_chroot_command "/usr/share/mdadm/mkconf > $MDADMCONF"; declare -i EXITCODE=$?
    #
    # Enable mdadm
    #
    sed -i "s/AUTOCHECK=false/AUTOCHECK=true # modified by installimage/" \
      "$FOLD/hdd/etc/default/mdadm"
    sed -i "s/AUTOSTART=false/AUTOSTART=true # modified by installimage/" \
      "$FOLD/hdd/etc/default/mdadm"
    sed -i "s/START_DAEMON=false/START_DAEMON=true # modified by installimage/" \
      "$FOLD/hdd/etc/default/mdadm"
    sed -i -e "s/^INITRDSTART=.*/INITRDSTART='all' # modified by installimage/" \
      "$FOLD/hdd/etc/default/mdadm"

    return "$EXITCODE"
  fi
}


# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ -n "$1" ]; then
    OUTFILE=$(find "$FOLD"/hdd/boot -name "initrd.img-*" -not -regex ".*\(gz\|bak\)" -printf "%f\n" | sort -nr | head -n1)
    VERSION=$(echo "$OUTFILE" |cut -d "-" -f2-)
    echo "Kernel Version found: $VERSION" | debugoutput

    if [ "$IMG_VERSION" -ge 60 ]; then
      # blacklist i915 driver due to many bugs and stability issues
      local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-hetzner.conf"
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
    fi

    #
    # just make sure that we do not accidentally try to install a bootloader
    # when we haven't configured grub yet
    # Debian won't install a boot loader anyway, but display an error message,
    # that needs to be confirmed
    #
    sed -i "s/do_bootloader = yes/do_bootloader = no/" "$FOLD/hdd/etc/kernel-img.conf"
    execute_chroot_command "update-initramfs -u -k $VERSION"; declare -i EXITCODE=$?

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
        printf 'GOVERNOR="%s"', "$1"
        echo 'MAX_SPEED="0"'
        echo 'MIN_SPEED="0"'
      } >> "$CPUFREQCONF"
    fi

    return 0
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  declare -i EXITCODE=0
  [ -n "$1" ] || return

  execute_chroot_command "mkdir -p /boot/grub/; cp -r /usr/lib/grub/* /boot/grub >> /dev/null 2>&1"
  execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_HIDDEN_TIMEOUT=.*/GRUB_HIDDEN_TIMEOUT=5/" -e "s/^GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=false/"'
  if isVServer; then
    execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"nomodeset elevator=noop\"/"'
  else
    execute_chroot_command 'sed -i /etc/default/grub -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"nomodeset\"/"'
  fi
  # only install grub2 in mbr of all other drives if we use swraid
  for ((i=1; i<="$COUNT_DRIVES"; i++)); do
    if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
      local disk; disk="$(eval echo "\$DRIVE"$i)"
      execute_chroot_command "grub-install --no-floppy --recheck $disk 2>&1"
    fi
  done
  [ -e "$FOLD/hdd/boot/grub/grub.cfg" ] && rm "$FOLD/hdd/boot/grub/grub.cfg"

  execute_chroot_command "grub-mkconfig -o /boot/grub/grub.cfg 2>&1"

  uuid_bugfix

  PARTNUM=$(echo "$SYSTEMBOOTDEVICE" | rev | cut -c1)

  if [ "$SWRAID" = "0" ]; then
    PARTNUM="$((PARTNUM - 1))"
  fi

  delete_grub_device_map

  return "$EXITCODE"
}

delete_grub_device_map() {
  [ -f "$FOLD/hdd/boot/grub/device.map" ] && rm "$FOLD/hdd/boot/grub/device.map"
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
  randomize_mdadm_checkarray_cronjob_time

  #
  # randomize mysql password for debian-sys-maint in LAMP image
  #
  debug "# Testing if mysql is installed and if this is a LAMP image and setting new debian-sys-maint password"
  if [ -f "$FOLD/hdd/etc/mysql/debian.cnf" ] ; then
    if [[ "$IMAGENAME" =~ lamp ]]; then
      randomize_maint_mysql_pass || return 1
    fi
  fi

  return 0
}

randomize_mdadm_checkarray_cronjob_time() {
  if [ -e "$FOLD/hdd/etc/cron.d/mdadm" ] && grep -q checkarray "$FOLD/hdd/etc/cron.d/mdadm"; then
    minute=$(((RANDOM % 59) + 1))
    hour=$(((RANDOM % 4) + 1))
    day=$(((RANDOM % 28) + 1))
    debug "# Randomizing cronjob run time for mdadm checkarray: day $day @ $hour:$minute"

    sed -i -e "s/^[* 0-9]*root/$minute $hour $day * * root/" -e "s/ &&.*]//" \
      "$FOLD/hdd/etc/cron.d/mdadm"
  else
    debug "# No /etc/cron.d/mdadm found to randomize cronjob run time"
  fi
}

#
# randomize mysql password for debian-sys-maint in LAMP image
#
randomize_maint_mysql_pass() {
  local SQLCONFIG="$FOLD/hdd/etc/mysql/debian.cnf"
  local MYCNF="$FOLD/hdd/root/.my.cnf"
  local PMA_DBC_CNF="$FOLD/hdd/etc/dbconfig-common/phpmyadmin.conf"
  local PMA_SEC_CNF="$FOLD/hdd/var/lib/phpmyadmin/blowfish_secret.inc.php"
  #
  # generate PW for user debian-sys-maint, root and phpmyadmin
  #
  # NEWPASS=$(cat /dev/urandom | strings | head -c 512 | md5sum | cut -b -16)
  # ROOTPASS=$(cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c8)
  local DEBIANPASS; DEBIANPASS=$(pwgen -s 16 1)
  local ROOTPASS; ROOTPASS=$(pwgen -s 16 1)
  local PMAPASS; PMAPASS=$(pwgen -s 16 1)
  local PMASEC; PMASEC=$(pwgen -s 24 1)
  if [ -f "$PMA_SEC_CNF" ]; then
    echo -e "<?php\n\$cfg['blowfish_secret'] = '$PMASEC';" > "$PMA_SEC_CNF"
  fi
  MYSQLCOMMAND="USE mysql;\nUPDATE user SET password=PASSWORD(\"$DEBIANPASS\") WHERE user='debian-sys-maint';
    UPDATE user SET password=PASSWORD(\"$ROOTPASS\") WHERE user='root';
    UPDATE user SET password=PASSWORD(\"$PMAPASS\") WHERE user='phpmyadmin'; FLUSH PRIVILEGES;"
  echo -e "$MYSQLCOMMAND" > "$FOLD/hdd/etc/mysql/pwchange.sql"
  execute_chroot_command "/etc/init.d/mysql start >>/dev/null 2>&1"
  execute_chroot_command "mysql --defaults-file=/etc/mysql/debian.cnf < /etc/mysql/pwchange.sql >>/dev/null 2>&1"; declare -i EXITCODE=$?
  execute_chroot_command "/etc/init.d/mysql stop >>/dev/null 2>&1"
  sed -i s/password.*/"password = $DEBIANPASS"/g "$SQLCONFIG"
  sed -i s/dbc_dbpass=.*/"dbc_dbpass='$PMAPASS'"/g "$PMA_DBC_CNF"
  execute_chroot_command "DEBIAN_FRONTEND=noninteractive dpkg-reconfigure phpmyadmin"
  rm "$FOLD/hdd/etc/mysql/pwchange.sql"

  #
  # generate correct ~/.my.cnf
  #
  echo '[client]' > "$MYCNF"
  echo 'user=root' >> "$MYCNF"
  echo "password=$ROOTPASS" >> "$MYCNF"

  #
  # write password file and erase script
  #
  cp "$SCRIPTPATH/password.txt" "$FOLD/hdd/"
  sed -i -e "s#<password>#$ROOTPASS#" "$FOLD/hdd/password.txt"
  chmod 600 "$FOLD/hdd/password.txt"
  printf '\nNote: Your MySQL password is in /password.txt (delete this with "erase_password_note")\n' >> "$FOLD/hdd/etc/motd.tail"
  cp "$SCRIPTPATH/erase_password_note" "$FOLD/hdd/usr/local/bin/"
  chmod +x "$FOLD/hdd/usr/local/bin/erase_password_note"

  return "$EXITCODE"
}


debian_grub_fix() {
  find "$FOLD/hdd/dev/mapper" -type l -printf '%f.%l\n' | while read -r line; do
    VOLGROUP="$(echo "$line" | cut -d'.' -f1)"
    DMDEVICE="$(echo "$line" | cut -d'/' -f2)"

    rm "$MAPPER/$VOLGROUP"
    cp -R "$FOLD/hdd/dev/$DMDEVICE" "$MAPPER/$VOLGROUP"
  done
}

# vim: ai:ts=2:sw=2:et
