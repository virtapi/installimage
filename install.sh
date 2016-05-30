#!/bin/bash

#
# install - installation commands
#
# (c) 2007-2016, Hetzner Online GmbH
#

STATUS_POSITION="\033[60G"

TOTALSTEPS=15
CURSTEP=0

# read global variables and functions
clear
# shellcheck disable=SC1091
. /tmp/install.vars

# get UUID from cmdline for installstatus reporting
for param in $(< /proc/cmdline); do
  case "${param}" in
    UUID=*)
      INSTALL_UUID=${param#*=}
      ;;
  esac
done

# installation step will be reported only if REPORT_STEP=1, this is needed for being able
# to handle the not counted sub-steps correctly
REPORT_STEP=0

report_status() {
  if [ -n "${INSTALL_UUID}" ] && [ "${REPORT_STEP}" -eq 1 ] && [ -n "${INSTALLSTATUS_URL}" ]; then
    local status_code; status_code=${1}
    shopt -s extglob
    local step_description=${REPORT_STEP_DESCRIPTION##+([[:space:]])}
    shopt -u extglob
    local status_data
    status_data="status_code=${status_code}&step_description=${step_description}&current_step=${CURSTEP}&total_steps=${TOTALSTEPS}"
    curl -s -m 5 --data "${status_data}" "${INSTALLSTATUS_URL}"/"${INSTALL_UUID}"
  fi
}

# used to report that the group of "status_none" sub tasks has completed
report_nosteps_completed(){
  REPORT_STEP=1
  report_status 0
}

inc_step() {
  CURSTEP=$((CURSTEP + 1))
}

status_busy() {
  REPORT_STEP=1
  REPORT_STEP_DESCRIPTION="$*"
  local step="$CURSTEP"
  test "$CURSTEP" -lt 10 && step=" $CURSTEP"
  echo -n -e "  $step/$TOTALSTEPS  :  $* $STATUS_POSITION${CYAN} busy $NOCOL"
  debug "# $*"
}

status_busy_nostep() {
  REPORT_STEP=0
  echo -n -e "         :  $* $STATUS_POSITION${CYAN} busy $NOCOL"
}

status_none() {
  REPORT_STEP=1
  REPORT_STEP_DESCRIPTION="$*"
  local step="$CURSTEP"
  test "$CURSTEP" -lt 10 && step=" $CURSTEP"
  echo -e "  $step/$TOTALSTEPS  :  $*"
}

status_none_nostep() {
  echo -e "         :  $*"
}

status_done() {
  report_status 0
  echo -e "$STATUS_POSITION${GREEN} done $NOCOL"
}

status_failed() {
  REPORT_STEP=1
  report_status 1
  echo -e "$STATUS_POSITION${RED}failed$NOCOL"
  [ $# -gt 0 ] && echo "${RED}         :  $*${NOCOL}"
  debug "=> FAILED"
  exit_function
  exit 1
}

status_warn() {
  echo -e "$STATUS_POSITION${YELLOW} warn"
  echo -e "         :  $*${NOCOL}"
}

status_donefailed() {
  if [ "$1" ] && [ "$1" -eq 0 ]; then
    status_done
  else
    status_failed
  fi
}

echo
echo_bold "                $COMPANY - installimage\n"
echo_bold "  Your server will be installed now, this will take some minutes"
echo_bold "             You can abort at any time with CTRL+C ...\n"

#
# get active nic and gather network information
#
get_active_eth_dev
gather_network_information


#
# Read configuration
#
STEP_DESCRIPTION="Reading configuration"
status_busy_nostep "${STEP_DESCRIPTION}"
read_vars "$FOLD/install.conf"
status_donefailed $?

#
# Load image variables
#
STEP_DESCRIPTION="Loading image file variables"
status_busy_nostep "${STEP_DESCRIPTION}"
get_image_info "$IMAGE_PATH" "$IMAGE_PATH_TYPE" "$IMAGE_FILE"
status_donefailed $?


# change sizes of DOS partitions
check_dos_partitions "no_output"

whoami "$IMAGE_FILE"
STEP_DESCRIPTION="Loading $IAM specific functions "
status_busy_nostep "${STEP_DESCRIPTION}"
debug "# load $IAM specific functions..."
if [ -e "$SCRIPTPATH/$IAM.sh" ]; then
  # shellcheck disable=SC1090 disable=SC2069
  . "$SCRIPTPATH/$IAM".sh 2>&1 > /dev/null
  status_done
else
  status_failed
fi

test "$SWRAID" = "1" && TOTALSTEPS=$((TOTALSTEPS + 1))
test "$LVM" = "1" && TOTALSTEPS=$((TOTALSTEPS + 1))
test "$OPT_INSTALL" && TOTALSTEPS=$((TOTALSTEPS + 1))
test "$IMAGE_PATH_TYPE" = "http" && TOTALSTEPS=$((TOTALSTEPS + 1))

#
# Remove partitions
#
inc_step
STEP_DESCRIPTION="Deleting partitions"
status_busy "${STEP_DESCRIPTION}"

unmount_all
stop_lvm_raid

for part_inc in $(seq 1 "$COUNT_DRIVES") ; do
  if [ "$(eval echo "\$FORMAT_DRIVE${part_inc}")" = "1" ] || [ "$SWRAID" = "1" ] || [ "$part_inc" -eq 1 ] ; then
    TARGETDISK="$(eval echo "\$DRIVE${part_inc}")"
    debug "# Deleting partitions on $TARGETDISK"
    delete_partitions "$TARGETDISK" || status_failed
  fi
done

status_done

#
# Test partition size
#
inc_step
STEP_DESCRIPTION="Test partition size"
status_busy "${STEP_DESCRIPTION}"
part_test_size
check_dos_partitions "no_output"
status_done


#
# Create partitions
#
inc_step
STEP_DESCRIPTION="Creating partitions and /etc/fstab"
status_busy "${STEP_DESCRIPTION}"

for part_inc in $(seq 1 "$COUNT_DRIVES") ; do
  if [ "$SWRAID" = "1" ] || [ "$part_inc" -eq 1 ] ; then
    TARGETDISK="$(eval echo "\$DRIVE${part_inc}")"
    debug "# Creating partitions on $TARGETDISK"
    create_partitions "$TARGETDISK" || status_failed
  fi
done

status_done


#
# Software RAID
#
if [ "$SWRAID" = "1" ]; then
  inc_step
  STEP_DESCRIPTION="Creating software RAID level $SWRAIDLEVEL"
  status_busy "${STEP_DESCRIPTION}"
  make_swraid "$FOLD/fstab"
  status_donefailed $?
fi


#
# LVM
#
if [ "$LVM" = "1" ]; then
  inc_step
  STEP_DESCRIPTION="Creating LVM volumes"
  status_busy "${STEP_DESCRIPTION}"
  make_lvm "$FOLD/fstab" "$DRIVE1" "$DRIVE2"
  LVM_EXIT=$?
  if [ $LVM_EXIT -eq 2 ] ; then
    status_failed "LVM thin-pool detected! Can't remove automatically!"
  else
    status_donefailed "$LVM_EXIT"
  fi
fi


#
# Format partitions
#
inc_step
STEP_DESCRIPTION="Formatting partitions"
status_none "${STEP_DESCRIPTION}"
grep "^/dev/" "$FOLD/fstab" > /tmp/fstab.tmp
while read -r line ; do
  echo "# parsed fstab line:$line" | debugoutput
  DEV="$(echo "$line" | awk '{print $1}')"
  FS="$(echo "$line" | awk '{print $3}')"
  status_busy_nostep "  formatting $DEV with $FS"
  format_partitions "$DEV" "$FS"
  status_donefailed $?
done < /tmp/fstab.tmp
report_nosteps_completed


#
# Mount filesystems
#
inc_step
STEP_DESCRIPTION="Mounting partitions"
status_busy "${STEP_DESCRIPTION}"
mount_partitions "$FOLD/fstab" "$FOLD/hdd" || status_failed
status_donefailed $?


#
# Look for a post-mount script and call it if existing
#
# this can be used e.g. for asking the user if
# he wants to restore from an ebackup-server
#
if has_postmount_script ; then
  status_none_nostep "Executing post mount script"
  execute_postmount_script || exit 0
fi

#
# ntp resync
#
inc_step
STEP_DESCRIPTION="Sync time via ntp"
status_busy "${STEP_DESCRIPTION}"
set_ntp_time
status_donefailed $?

#
# Download image
#
if [ "$IMAGE_PATH_TYPE" = "http" ] ; then
  inc_step
  STEP_DESCRIPTION="Downloading image ($IMAGE_PATH_TYPE)"
  status_busy "${STEP_DESCRIPTION}"
  get_image_url "$IMAGE_PATH" "$IMAGE_FILE"
  status_donefailed $?
fi

#
# Import public key for image validation
#
STEP_DESCRIPTION="Importing public key for image validation"
status_busy_nostep "${STEP_DESCRIPTION}"
import_imagekey
IMPORT_EXIT=$?
if [ $IMPORT_EXIT -eq 2 ] ; then
  status_warn "No public key found!"
else
  status_donefailed "$IMPORT_EXIT"
fi

#
# Validate image
#
inc_step
STEP_DESCRIPTION="Validating image before starting extraction"
status_busy "${STEP_DESCRIPTION}"
validate_image
VALIDATE_EXIT=$?
if [ -n "$FORCE_SIGN" ] || [ -n "$OPT_FORCE_SIGN" ] && [ $VALIDATE_EXIT -gt 0 ] ; then
  debug "FORCE_SIGN set, but validation failed!"
  status_failed
fi
if [ $VALIDATE_EXIT -eq 3 ] ; then
  status_warn "No imported public key found!"
elif [ $VALIDATE_EXIT -eq 2 ] ; then
  status_warn "No detached signature file found!"
else
  status_donefailed "$VALIDATE_EXIT"
fi

#
# Extract image
#
inc_step
STEP_DESCRIPTION="Extracting image ($IMAGE_PATH_TYPE)"
status_busy "${STEP_DESCRIPTION}"
extract_image "$IMAGE_PATH_TYPE" "$IMAGE_FILE_TYPE"
status_donefailed $?

#
# Setup network
#
inc_step
STEP_DESCRIPTION="Setting up network for $ETHDEV"
status_busy "${STEP_DESCRIPTION}"
setup_network_config "$ETHDEV" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
status_donefailed $?

#
# Set udev rules
#
set_udev_rules

#
# chroot commands
#
inc_step
STEP_DESCRIPTION="Executing additional commands"
status_none "${STEP_DESCRIPTION}"

copy_mtab "NIL"

status_busy_nostep "  Setting hostname"
debug "# Setting hostname"
#set_hostname "$NEWHOSTNAME" || status_failed
set_hostname "$NEWHOSTNAME" "$IPADDR" "$IP6ADDR" || status_failed
status_done

status_busy_nostep "  Generating new SSH keys"
debug "# Generating new SSH keys"
generate_new_sshkeys "NIL" || status_failed
status_done

if [ "$SWRAID" = "1" ]; then
  status_busy_nostep "  Generating mdadm config"
  debug "# Generating mdadm configuration"
  generate_config_mdadm "NIL" || status_failed
  status_done
fi

status_busy_nostep "  Generating ramdisk"
debug "# Generating ramdisk"
generate_new_ramdisk "NIL" || status_failed
status_done

status_busy_nostep "  Generating ntp config"
debug "# Generating ntp config"
generate_ntp_config "NIL" || status_failed
status_done

report_nosteps_completed


#
# Cool'n'Quiet
#
#inc_step
#status_busy "Setting CPU frequency scaling to $GOVERNOR"
setup_cpufreq "$GOVERNOR" || {
  debug "=> FAILED"
#  exit 1
}
#status_donefailed $?



#
# Set up misc files
#
inc_step
STEP_DESCRIPTION="Setting up miscellaneous files"
status_busy "${STEP_DESCRIPTION}"
generate_resolvconf || status_failed
# already done in set_hostname
#generate_hosts "$IPADDR" "$IP6ADDR" || status_failed
generate_sysctlconf || status_failed
status_done


#
# Set root password and/or install ssh keys
#
inc_step
STEP_DESCRIPTION="Configuring authentication"
status_none "${STEP_DESCRIPTION}"

if [ -n "$OPT_SSHKEYS_URL" ] ; then
  STEP_DESCRIPTION="  Fetching SSH keys"
  status_busy_nostep "${STEP_DESCRIPTION}"
  debug "# Fetch public SSH keys"
  fetch_ssh_keys "$OPT_SSHKEYS_URL"
  status_donefailed $?
fi

if [ "$OPT_USE_SSHKEYS" = "1" ] && [ -z "$FORCE_PASSWORD" ]; then
  STEP_DESCRIPTION="  Disabling root password"
  status_busy_nostep "${STEP_DESCRIPTION}"
  set_rootpassword "$FOLD/hdd/etc/shadow" "*"
  status_donefailed $?
  status_busy_nostep "  Disabling SSH root login without password"
  set_ssh_rootlogin "without-password"
  status_donefailed $?
else
  STEP_DESCRIPTION="  Setting root password"
  status_busy_nostep "${STEP_DESCRIPTION}"
  get_rootpassword "/etc/shadow" || status_failed
  set_rootpassword "$FOLD/hdd/etc/shadow" "$ROOTHASH"
  status_donefailed $?
  STEP_DESCRIPTION="  Enabling SSH root login with password"
  status_busy_nostep "${STEP_DESCRIPTION}"
  set_ssh_rootlogin "yes"
  status_donefailed $?
fi

if [ "$OPT_USE_SSHKEYS" = "1" ] ; then
    STEP_DESCRIPTION="  Copying SSH keys"
    status_busy_nostep "${STEP_DESCRIPTION}"
    debug "# Adding public SSH keys"
    copy_ssh_keys
    status_donefailed $?
fi

report_nosteps_completed

#
# Write Bootloader
#
inc_step
STEP_DESCRIPTION="Installing bootloader $BOOTLOADER"
status_busy "${STEP_DESCRIPTION}"

debug "# Generating config for $BOOTLOADER"
if [ "$BOOTLOADER" = "grub" ] || [ "$BOOTLOADER" = "GRUB" ]; then
  generate_config_grub "$VERSION" || status_failed
else
  generate_config_lilo "$VERSION" || status_failed
fi

debug "# Writing bootloader $BOOTLOADER into MBR"
if [ "$BOOTLOADER" = "grub" ] || [ "$BOOTLOADER" = "GRUB" ]; then
  write_grub "NIL" || status_failed
else
  write_lilo "NIL" || status_failed
fi

status_done

#
# installing optional software (e.g. Plesk)
#

if [ "$OPT_INSTALL" ]; then
  inc_step
  STEP_DESCRIPTION="Installing additional software"
  status_none "${STEP_DESCRIPTION}"
  # shellcheck disable=SC2001
  opt_install_items="$(echo "$OPT_INSTALL" | sed s/,/\\n/g)"
  for opt_item in $opt_install_items; do
    opt_item=$(echo "$opt_item" | tr "[:upper:]" "[:lower:]")
    case "$opt_item" in
      plesk*)
        STEP_DESCRIPTION="  Installing PLESK Control Panel"
        status_busy_nostep "${STEP_DESCRIPTION}"
        debug "# installing PLESK"
        install_plesk "$opt_item"
        status_donefailed $?
        ;;
      omsa)
        STEP_DESCRIPTION="  Installing Open Manage"
        status_busy_nostep "${STEP_DESCRIPTION}"
        debug "# installing OMSA"
        install_omsa
        status_donefailed $?
        ;;
    esac
  done
fi

#
# os specific functions
# details in debian.sh / suse.sh / ubuntu.sh
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
inc_step
STEP_DESCRIPTION="Running some $IAM specific functions"
status_busy "${STEP_DESCRIPTION}"
run_os_specific_functions || status_failed
status_done

#
# Clear log files
#
inc_step
STEP_DESCRIPTION="Clearing log files"
status_busy "${STEP_DESCRIPTION}"
clear_logs "NIL"
status_donefailed $?

#
# Execute post installation script
#
if has_postinstall_script; then
  status_none_nostep "Executing post installation script"
  execute_postinstall_script
fi

#
# Install robot script for automatic installations
#
if [ "$ROBOTURL" ]; then
  debug "# Installing Robot script..."
  install_robot_script 2>&1 | debugoutput
fi

#
### report SSH fingerprints to URL where we got the pubkeys from (or not)
if [ -n "$OPT_SSHKEYS_URL" ] ; then
  case "$OPT_SSHKEYS_URL" in
    https:*|http:*)
      debug "# Reporting SSH fingerprints..."
      curl -s -m 10 -X POST -H "Content-Type: application/json" -d @"$FOLD/ssh_fingerprints" "$OPT_SSHKEYS_URL" -o /dev/null
    ;;
    *)
      debug "# cannot POST SSH fingerprints to non-HTTP URLs"
   esac
fi

#
#
# Report statistic
#
report_statistic "$STATSSERVER" "$IMAGE_FILE" "$SWRAID" "$LVM" "$BOOTLOADER" "$ERROREXIT"

#
# Report install.conf to rz_admin
# Report debug.txt to rz_admin
#
report_id="$(report_config "$REPORTSERVER")"
report_debuglog "$REPORTSERVER" "$report_id"

#
# Save installimage configuration and debug file on the new system
#
(
  echo "#"
  echo "# $COMPANY - installimage"
  echo "#"
  echo "# This file contains the configuration used to install this"
  echo "# system via installimage script. Comments have been removed."
  echo "#"
  echo "# More information about the installimage script and"
  echo "# automatic installations can be found on our github page:"
  echo "#"
  echo "# https://github.com/virtapi/installimage#installimage---generic-and-automated-linux-installer"
  echo "#"
  echo
  grep -v "^#" "$FOLD/install.conf" | grep -v "^$"
) > "$FOLD"/hdd/installimage.conf
cat /root/debug.txt > "$FOLD/hdd/installimage.debug"
chmod 640 "$FOLD/hdd/installimage.conf"
chmod 640 "$FOLD/hdd/installimage.debug"

echo
echo_bold "                  INSTALLATION COMPLETE"
echo_bold "   You can now reboot and log in to your new system with"
echo_bold "  the same password as you logged in to the rescue system.\n"

# vim: ai:ts=2:sw=2:et
