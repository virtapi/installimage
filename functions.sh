#!/bin/bash

#
# functions
#
# (c) 2007-2016, Hetzner Online GmbH
#

# nil settings parsed out of the config
PART_COUNT=""
PART_MOUNT=""
PART_FS=""
PART_SIZE=""
PARTS_SUM_SIZE=""
MOUNT_POINT_SIZE=""
HASROOT=""
SWRAID=""
SWRAIDLEVEL=""
LVM=""
LVM_VG_CHECK=""
IMAGE_PATH=""
IMAGE_PATH_TYPE=""
IMAGE_FILE=""
IMAGE_FILE_TYPE=""
IMAGE_SIGN=""
IMAGE_PUBKEY=""
IMAGE_PUBKEY_IMPORTED=""
IAM=""
IMG_VERSION=0
BOOTLOADER=""
GOVERNOR=""
# this var is probably not used anymore. keep it for safety
#SFDISKPARTS=""
COUNT_DRIVES=0
# this var is probably not used anymore. keep it for safety
#LAST_PART_START=""
# this var is probably not used anymore. keep it for safety
#LAST_PART_END=""
# this var is probably not used anymore. keep it for safety
#DISK_SIZE_SECTORS=""

SYSTEMROOTDEVICE=""
SYSTEMBOOTDEVICE=""
SYSTEMREALBOOTDEVICE=""
EXTRACTFROM=""

ETHDEV=""
HWADDR=""
IPADDR=""
BROADCAST=""
SUBNETMASK=""
GATEWAY=""
NETWORK=""
IP6ADDR=""
IP6PREFLEN=""
IP6GATEWAY=""

ROOTHASH=""
LILOEXTRABOOT=""

ERROREXIT="0"
FINALIMAGEPATH=""

PLESK_STD_VERSION="PLESK_12_5_30"

SYSMFC=$(dmidecode -s system-manufacturer 2>/dev/null | head -n1)
SYSTYPE=$(dmidecode -s system-product-name 2>/dev/null | head -n1)
MBTYPE=$(dmidecode -s baseboard-product-name 2>/dev/null | head -n1)

# functions
# show text in a different color
echo_red() {
  echo -e '\033[01;31m$*\033[00m'
}
echo_green() {
  echo -e '\033[01;32m$*\033[00m'
}
echo_bold() {
  echo -e '\033[0;1m$*\033[00m'
}


# generate submenus to choose which image to install
# generate_menu "SUBMENU"
generate_menu() {
 # security check - just execute the function WITH parameters
 if [ -n "$1" ]; then
  # empty the menu
  MENULIST=""
  PROXMOX=false
  # find image-files and generate raw list
  # shellcheck disable=SC2153
  FINALIMAGEPATH="$IMAGESPATH"
# don't go looking for old_openSUSE or suse images. That was a long time ago
#  if [ "$1" = "openSUSE" ]; then
#    RAWLIST=$(ls -1 "$IMAGESPATH" | grep -i -e "^$1\|^old_$1\|^suse\|^old_suse")
  if [ "$1" = "Virtualization" ]; then
    RAWLIST=""
    RAWLIST=$(find "$IMAGESPATH"/ -maxdepth 1 -type f -name "CoreOS*" -a -not -name "*.sig" -printf '%f\n'|sort)
    RAWLIST="$RAWLIST Proxmox-Virtualization-Environment-on-Debian-Wheezy"
    RAWLIST="$RAWLIST Proxmox-Virtualization-Environment-on-Debian-Jessie"
  elif [ "$1" = "old_images" ]; then
    # skip CPANEL images and signatures files from list
    RAWLIST=$(find "$OLDIMAGESPATH"/ -maxdepth 1 -type f -not -name "*.sig" -a -not -name "*cpanel*" -printf '%f\n'|sort)
    FINALIMAGEPATH="$OLDIMAGESPATH"
  else
    # skip CPANEL images and signatures files from list
    RAWLIST=$(find "$IMAGESPATH"/* -maxdepth 1 -type f -not -name "*cpanel*" -a -regextype sed -regex ".*/\\(old_\\)\\?$1.*" -a -not -regex '.*\.sig$' -printf '%f\n'|sort)
  fi
  # check if 32-bit rescue is activated and disable 64-bit images then
  if [ "$(uname -m)" != "x86_64" ]; then
    RAWLIST="$(echo "$RAWLIST" |tr ' ' '\n' |grep -v -- '-64-[a-zA-Z]')"
  fi
  # generate formatted list for usage with "dialog"
  for i in $RAWLIST; do
    TEMPVAR="$i"
    TEMPVAR=$(basename "$TEMPVAR" .bin)
    TEMPVAR=$(basename "$TEMPVAR" .bin.bz2)
    TEMPVAR=$(basename "$TEMPVAR" .txz)
    TEMPVAR=$(basename "$TEMPVAR" .tar.xz)
    TEMPVAR=$(basename "$TEMPVAR" .tgz)
    TEMPVAR=$(basename "$TEMPVAR" .tar.gz)
    TEMPVAR=$(basename "$TEMPVAR" .tbz)
    TEMPVAR=$(basename "$TEMPVAR" .tar.bz)
    TEMPVAR=$(basename "$TEMPVAR" .tar.bz2)
    TEMPVAR=$(basename "$TEMPVAR" .tar)
    MENULIST="$MENULIST$TEMPVAR . "
  done
  # add "back to mainmenu" entry
  MENULIST="$MENULIST"'back . '

  # show menu and get result
  # shellcheck disable=SC2086
  dialog --backtitle "$DIATITLE" --title "$1 images" --no-cancel --menu "choose image" 0 0 0 $MENULIST 2> "$FOLD/submenu.chosen"
  IMAGENAME=$(cat "$FOLD/submenu.chosen")

  # create proxmox post-install file if needed
  case $IMAGENAME in
    Proxmox-Virtualization-Environment*)
      case "$IMAGENAME" in
        Proxmox-Virtualization-Environment-on-Debian-Wheezy) export PROXMOX_VERSION="3" ;;
        Proxmox-Virtualization-Environment-on-Debian-Jessie) export PROXMOX_VERSION="4" ;;
      esac
      cp "$SCRIPTPATH/post-install/proxmox$PROXMOX_VERSION" /post-install
      chmod 0755 /post-install
      PROXMOX=true
      IMAGENAME=$(eval echo \$PROXMOX${PROXMOX_VERSION}_BASE_IMAGE)
      DEFAULTPARTS=""
      DEFAULTPARTS="$DEFAULTPARTS\\nPART  /boot  ext3  512M"
      DEFAULTPARTS="$DEFAULTPARTS\\nPART  lvm    vg0    all\\n"
      DEFAULTPARTS="$DEFAULTPARTS\\nLV  vg0  root  /     ext3  15G"
      DEFAULTPARTS="$DEFAULTPARTS\\nLV  vg0  swap  swap  swap   6G"
  ;;
    CoreOS*)
      PROXMOX=false
    ;;
    *)
      : # no proxmox installation
    ;;
  esac

  whoami "$IMAGENAME"
 fi
}
# create new config file from standardconfig and misc options
# create_config "IMAGENAME"
create_config() {
  if [ "$1" ]; then
    CNF="$FOLD/install.conf"
    getdrives; EXITCODE=$?

    if [ $COUNT_DRIVES -eq 0 ] ; then
      graph_notice "There are no drives in your server!\\nIf there is a raid controller in your server, please configure it!\\n\\nThe setup will quit now!"
      return 1
    fi

    {
      echo "## ======================================================"
      echo "##  $COMPANY - installimage - standard config"
      echo "## ======================================================"
      echo ""
    } > "$CNF"

    # first drive
    {
      echo ""
      echo "## ===================="
      echo "##  HARD DISK DRIVE(S):"
      echo "## ===================="
      echo ""
    } >> "$CNF"
    [ $COUNT_DRIVES -gt 2 ] && echo "## PLEASE READ THE NOTES BELOW!" >> "$CNF"
    echo "" >> "$CNF"

    local found_optdrive=0
    local optdrive_count=0
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      DISK="$(eval echo \$DRIVE${i})"
      OPTDISK="$(eval echo \$OPT_DRIVE${i})"
      if [ -n "$OPTDISK" ] ; then
        optdrive_count=$((optdrive_count+1))
        found_optdrive=1
        hdinfo "/dev/$OPTDISK" >> "$CNF"
        echo "DRIVE$i /dev/$OPTDISK" >> "$CNF"
      else
        hdinfo "$DISK" >> "$CNF"
        # comment drive out when not given via commandline
        [ $found_optdrive -eq 1 ] && echo -n "# " >> "$CNF"
        echo "DRIVE$i $DISK" >> "$CNF"
      fi
    done

    # reset drive count to number of drives explicitly passed via command line
    [ $optdrive_count -gt 0 ] && COUNT_DRIVES=$optdrive_count

    echo "" >> "$CNF"
    if [ $COUNT_DRIVES -gt 2 ] ; then
      if [ $COUNT_DRIVES -lt 4 ] ; then
        {
          echo "## if you dont want raid over your three drives then comment out the following line and set SWRAIDLEVEL not to 5"
          echo "## please make sure the DRIVE[nr] variable is strict ascending with the used harddisks, when you comment out one or more harddisks"
        } >> "$CNF"
      else
        {
          echo "## if you dont want raid over all of your drives then comment out the following line and set SWRAIDLEVEL not to 5 or 6 or 10"
          echo "## please make sure the DRIVE[nr] variable is strict ascending with the used harddisks, when you comment out one or more harddisks"
        } >> "$CNF"
      fi
    fi
    echo "" >> "$CNF"

    # software-raid
    if [ $COUNT_DRIVES -gt 1 ]; then
      {
        echo ""

        echo "## ==============="
        echo "##  SOFTWARE RAID:"
        echo "## ==============="
        echo ""
        echo "## activate software RAID?  < 0 | 1 >"
        echo ""
      } >> "$CNF"

      case "$OPT_SWRAID" in
        0) echo "SWRAID 0" >> "$CNF" ;;
        1) echo "SWRAID 1" >> "$CNF" ;;
        *) echo "SWRAID $DEFAULTSWRAID" >> "$CNF" ;;
      esac

      echo '' >> "$CNF"

      # available raidlevels
      local raid_levels="0 1 5 6 10"
      # set default raidlevel
      local default_level="$DEFAULTTWODRIVESWRAIDLEVEL"
      if [ "$COUNT_DRIVES" -eq 3 ] ; then
        default_level="$DEFAULTTHREEDRIVESWRAIDLEVEL"
      elif [ "$COUNT_DRIVES" -gt 3 ] ; then
        default_level="$DEFAULTFOURDRIVESWRAIDLEVEL"
      fi

      local set_level=""
      local avail_level=""
      # check for possible raidlevels
      for level in $raid_levels ; do
        # set raidlevel to given opt raidlevel
        if [ -n "$OPT_SWRAIDLEVEL" ] ; then
          [ "$OPT_SWRAIDLEVEL" -eq "$level" ] && set_level="$level"
        fi

        # no raidlevel 5 if less then 3 hdds
        [ "$level" -eq 5 ] && [ "$COUNT_DRIVES" -lt 3 ] && continue

        # no raidlevel 6 if less then 4 hdds
        [ "$level" -eq 6 ] && [ "$COUNT_DRIVES" -lt 4 ] && continue

        # no raidlevel 10 if less then 2 hdds
        [ "$level" -eq 10 ] && [ "$COUNT_DRIVES" -lt 2 ] && continue

        # create list of all possible raidlevels
        if [ -z "$avail_level" ] ; then
          avail_level="$level"
        else
          avail_level="$avail_level | $level"
        fi
      done
      [ -z "$set_level" ] && set_level="$default_level"

      printf '## Choose the level for the software RAID < %s >\n' "${avail_level}" >> "$CNF"
      echo "SWRAIDLEVEL $set_level" >> "$CNF"
    fi

    # bootloader
    # we no longer support lilo, so don't show this option if it isn't in the image
    if [ "$IAM" = "arch" ] ||
      [ "$IAM" = "coreos" ] ||
      [ "$IAM" = "centos" ] ||
      [ "$IAM" = "ubuntu" ] && [ "$IMG_VERSION" -ge 1204 ] ||
      [ "$IAM" = "debian" ] && [ "$IMG_VERSION" -ge 70 ] ||
      [ "$IAM" = "suse" ] && [ "$IMG_VERSION" -ge 122 ]; then
      NOLILO="true"
    else
      NOLILO=''
    fi

    {
      echo ""
      echo "## ============"
      echo "##  BOOTLOADER:"
      echo "## ============"
      echo ""
    } >> "$CNF"

    if [ "$NOLILO" ]; then
      {
        echo ""
        echo "## Do not change. This image does not include or support lilo (grub only)!:"
        echo ""
        echo "BOOTLOADER grub"
      } >> "$CNF"
    else
      {
        echo ""
        echo "## which bootloader should be used?  < lilo | grub >"
        echo ""
      } >> "$CNF"
      case "$OPT_BOOTLOADER" in
        lilo) echo "BOOTLOADER lilo" >> "$CNF" ;;
        grub) echo "BOOTLOADER grub" >> "$CNF" ;;
        *)    echo "BOOTLOADER $DEFAULTLOADER" >> "$CNF" ;;
      esac
      echo "" >> "$CNF"
    fi

    # hostname
    get_active_eth_dev
    gather_network_information
    {
      echo ""
      echo "## =========="
      echo "##  HOSTNAME:"
      echo "## =========="
      echo ""
      echo "## which hostname should be set?"
      echo "##"
      echo ""
    } >> "$CNF"

    # set default hostname to image name
    DEFAULT_HOSTNAME="$1"
    # or to proxmox if chosen
    if [ "$PROXMOX" = "true" ]; then
      echo -e '## This must be a FQDN otherwise installation will fail\n## \n' >> "$CNF"
      DEFAULT_HOSTNAME="Proxmox-VE.yourdomain.localdomain"
    fi
    # or to the hostname passed through options
    [ "$OPT_HOSTNAME" ] && DEFAULT_HOSTNAME="$OPT_HOSTNAME"
    echo "HOSTNAME $DEFAULT_HOSTNAME" >> "$CNF"
    echo "" >> "$CNF"

    ## Calculate how much hardisk space at raid level 0,1,5,6,10
    RAID0=0
    local small_hdd; small_hdd="$(smallest_hd)"
    local small_hdd_size="$(($(blockdev --getsize64 "$small_hdd")/1024/1024/1024))"
    RAID0=$((small_hdd_size*COUNT_DRIVES))
    RAID1="$small_hdd_size"
    if [ $COUNT_DRIVES -ge 3 ] ; then
      RAID5=$((RAID0-small_hdd_size))
    fi
    if [ $COUNT_DRIVES -ge 4 ] ; then
      RAID6=$((RAID0-2*small_hdd_size))
      RAID10=$((RAID0/2))
    fi

    # partitions
    {
      echo ""
      echo "## =========================="
      echo "##  PARTITIONS / FILESYSTEMS:"
      echo "## =========================="
      echo ""
      echo "## define your partitions and filesystems like this:"
      echo "##"
      echo "## PART  <mountpoint/lvm>  <filesystem/VG>  <size in MB>"
      echo "##"
      echo "## * <mountpoint/lvm> mountpoint for this filesystem  *OR*  keyword 'lvm'"
      echo "##                    to use this PART as volume group (VG) for LVM"
      echo "## * <filesystem/VG>  can be ext2, ext3, reiserfs, xfs, swap  *OR*  name"
      echo "##                    of the LVM volume group (VG), if this PART is a VG"
      echo "## * <size>           you can use the keyword 'all' to assign all the"
      echo "##                    remaining space of the drive to the *last* partition."
      echo "##                    you can use M/G/T for unit specification in MIB/GIB/TIB"
      echo "##"
      echo "## notes:"
      echo "##   - extended partitions are created automatically"
      echo "##   - '/boot' cannot be on a xfs filesystem"
      echo "##   - '/boot' cannot be on LVM!"
      echo "##   - when using software RAID 0, you need a '/boot' partition"
      echo "##"
      echo "## example without LVM (default):"
      echo "## -> 4GB   swapspace"
      echo "## -> 512MB /boot"
      echo "## -> 10GB  /"
      echo "## -> 5GB   /tmp"
      echo "## -> all the rest to /home"
      echo "#PART swap   swap      4096"
      echo "#PART /boot  ext2       512"
      echo "#PART /      reiserfs 10240"
      echo "#PART /tmp   xfs       5120"
      echo "#PART /home  ext3       all"
      echo "#"
      echo "##"
      echo "## to activate LVM, you have to define volume groups and logical volumes"
      echo "##"
      echo "## example with LVM:"
      echo "#"
      echo "## normal filesystems and volume group definitions:"
      echo "## -> 512MB boot  (not on lvm)"
      echo "## -> all the rest for LVM VG 'vg0'"
      echo "#PART /boot  ext3     512M"
      echo "#PART lvm    vg0       all"

      echo "#"
      echo "## logical volume definitions:"
      echo "#LV <VG> <name> <mount> <filesystem> <size>"
      echo "#"
      echo "#LV vg0   root   /        ext4         10G"
      echo "#LV vg0   swap   swap     swap          4G"
      echo "#LV vg0   tmp    /tmp     reiserfs      5G"
      echo "#LV vg0   home   /home    xfs          20G"
      echo "#"
    } >> "$CNF"

    if [ -x "/usr/local/bin/hwdata" ]; then
      {
        echo "#"
        echo "## your system has the following devices:"
        echo "#"
        /usr/local/bin/hwdata | grep "Disk /"  | sed "s/^  /#/"
      } >> "$CNF"
    fi

    if [ "$RAID1" ] && [ "$RAID0" ] ; then
      {
        echo "#"
        echo "## Based on your disks and which RAID level you will choose you have"
        echo "## the following free space to allocate (in GiB):"
        echo "# RAID  0: ~$RAID0"
        echo "# RAID  1: ~$RAID1"
      } >> "$CNF"
      [ "$RAID5" ] && echo "# RAID  5: ~$RAID5" >> "$CNF"
      if [ "$RAID6" ]; then
        {
          echo "# RAID  6: ~$RAID6"
          echo "# RAID 10: ~$RAID10"
        } >> "$CNF"
      fi
    fi

    {
      echo "#"
      echo ""
    } >> "$CNF"

    # check if there are 3TB disks inside and use other default scheme
    local LIMIT=2096128
    local THREE_TB=2861588
    local DRIVE_SIZE; DRIVE_SIZE="$(sfdisk -s "$(smallest_hd)" 2>/dev/null)"
    DRIVE_SIZE="$(echo "$DRIVE_SIZE" / 1024 | bc)"

    # adjust swap dynamically according to RAM
    # RAM < 2 GB : SWAP=2 * RAM
    # RAM > 2GB -  8GB : SWAP=RAM
    # RAM > 8GB - 64GB : SWAP = 0.5 RAM
    # RAM > 64GB: SWAP = 4GB
    # http://docs.fedoraproject.org/en-US/Fedora/18/html/Installation_Guide/s2-diskpartrecommend-x86.html
    # https://access.redhat.com/knowledge/docs/en-US/Red_Hat_Enterprise_Linux/6/html/Installation_Guide/s2-diskpartrecommend-x86.html
    RAM=$(free -m | grep Mem: | tr -s ' ' | cut -d' ' -f2)
    SWAPSIZE=4
    if [ "$RAM" -lt 2048 ]; then
      SWAPSIZE=$((RAM * 2 / 1024 + 1))
    elif [ "$RAM" -lt 8192 ]; then
      SWAPSIZE=$((RAM / 1024 + 1))
    elif [ "$RAM" -lt 65535 ]; then
      SWAPSIZE=$((RAM / 2 / 1024 + 1))
    fi

    DEFAULTPARTS=${DEFAULTPARTS/SWAPSIZE##/$SWAPSIZE}
    DEFAULTPARTS_BIG=${DEFAULTPARTS_BIG/SWAPSIZE##/$SWAPSIZE}
    DEFAULTPARTS_LARGE=${DEFAULTPARTS_LARGE/SWAPSIZE##/$SWAPSIZE}

    # use ext3 for vservers, because ext4 is too trigger happy of device timeouts
    if isVServer; then
      if [ "$SYSTYPE" = "vServer" ]; then
        DEFAULTPARTS=$DEFAULTPARTS_CLOUDSERVER
      else
        DEFAULTPARTS=$DEFAULTPARTS_VSERVER
      fi
    fi

    # use /var instead of /home for all partition when installing plesk
    if [ "$OPT_INSTALL" ]; then
      if echo "$OPT_INSTALL" | grep -qi 'PLESK'; then
        DEFAULTPARTS_BIG="${DEFAULTPARTS_BIG//home/var}"
      fi
    fi

    if [ "$IAM" = "coreos" ]; then
      echo "## NOTICE: This image does not support custom partition sizes." >> "$CNF"
      echo "## NOTICE: Please keep the following lines unchanged. They are just placeholders." >> "$CNF"
    fi

    if [ "$DRIVE_SIZE" -gt "$LIMIT" ]; then
      if [ "$DRIVE_SIZE" -gt "$THREE_TB" ]; then
        [ "$OPT_PARTS" ] && echo -e "$OPT_PARTS" >> "$CNF" || echo -e "$DEFAULTPARTS_LARGE" >> "$CNF"
      else
        [ "$OPT_PARTS" ] && echo -e "$OPT_PARTS" >> "$CNF" || echo -e "$DEFAULTPARTS_BIG" >> "$CNF"
      fi
    else
      [ "$OPT_PARTS" ] && echo -e "$OPT_PARTS" >> "$CNF" || echo -e "$DEFAULTPARTS" >> "$CNF"
    fi

    [ "$OPT_LVS" ] && echo -e "$OPT_LVS" >> "$CNF"
    echo "" >> "$CNF"

    # image
    {
      echo ""
      echo "## ========================"
      echo "##  OPERATING SYSTEM IMAGE:"
      echo "## ========================"
      echo ""
      echo "## full path to the operating system image"
      echo "##   supported image sources:  local dir,  ftp,  http,  nfs"
      echo "##   supported image types: tar, tar.gz, tar.bz, tar.bz2, tar.xz, tgz, tbz, txz"
      echo "## examples:"
      echo "#"
      echo "# local: /path/to/image/filename.tar.gz"
      echo "# ftp:   ftp://<user>:<password>@hostname/path/to/image/filename.tar.bz2"
      echo "# http:  http://<user>:<password>@hostname/path/to/image/filename.tbz"
      echo "# https: https://<user>:<password>@hostname/path/to/image/filename.tbz"
      echo "# nfs:   hostname:/path/to/image/filename.tgz"
      echo "#"
      echo "# for validation of the image, place the detached gpg-signature"
      echo "# and your public key in the same directory as your image file."
      echo "# naming examples:"
      echo "#  signature:   filename.tar.bz2.sig"
      echo "#  public key:  public-key.asc"
      echo ""
    } >> "$CNF"
    if [ "$1" = "custom" ]; then
      echo "IMAGE " >> "$CNF"
    else
      if [ "$OPT_IMAGE" ] ; then
        if [ -f "$FINALIMAGEPATH/$OPT_IMAGE" ] ; then
          echo "IMAGE $FINALIMAGEPATH/$OPT_IMAGE" >> "$CNF"
        else
          echo "IMAGE $OPT_IMAGE" >> "$CNF"
        fi
      else
        [ -n "$IMG_EXT" ] && IMAGESEXT="$IMG_EXT"
        echo "IMAGE $FINALIMAGEPATH$1.$IMAGESEXT" >> "$CNF"
      fi
    fi
    echo "" >> "$CNF"

  fi
  return 0
}

getdrives() {
  declare -a drives;
  mapfile -d $'\0' drives < <(find /sys/block/ \( -name  'nvme[0-9]n[0-9]' -o  -name '[hvs]d[a-z]' \) -print0)
  local i=1

  for drive in ${drives[*]} ; do
    # if we have just one drive, add it. Otherwise check that multiple drives are at least HDDMINSIZE
    if [ ${#drives[@]} -eq 1 ] || [ ! "$(awk -v DRIVE="${drive}" '{if($4==DRIVE){print $3}}' /proc/partitions)" -lt "$HDDMINSIZE" ] ; then
      eval DRIVE$i="/dev/$drive"
      (( i = i+1 ))
    fi
  done
  [ -z "$DRIVE1" ] && DRIVE1="no valid drive found"

  COUNT_DRIVES=$((i - 1))

  return 0
}

# read all variables from config file
# read_vars "CONFIGFILE"
read_vars(){
if [ -n "$1" ]; then
  # count disks again, for setting COUNT_DRIVES correct after restarting installimage
  getdrives

  # special hidden configure option: create RAID1 and 10 with assume clean to
  # avoid initial resync
  RAID_ASSUME_CLEAN="$(grep -m1 -e ^RAID_ASSUME_CLEAN "$1" |awk '{print $2}')"
  export RAID_ASSUME_CLEAN

  # special hidden configure option: GPT usage
  # if set to 1, use GPT even on disks smaller than 2TiB
  # if set to 2, always use GPT, even if the OS does not support it
  FORCE_GPT="$(grep -m1 -e ^FORCE_GPT "$1" |awk '{print $2}')"

  # another special hidden configure option: force image validation
  # if set to 1: force validation
  FORCE_SIGN="$(grep -m1 -e ^FORCE_SIGN "$1" |awk '{print $2}')"
  export FORCE_SIGN

  # hidden configure option:
  # if set to 1: force setting root password even if ssh keys are
  # provided
  FORCE_PASSWORD="$(grep -m1 -e ^FORCE_PASSWORD "$1" |awk '{print $2}')"
  export FORCE_PASSWORD

  # get all disks from configfile
  local used_disks=1
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    disk="$(grep -m1 -e ^DRIVE$i "$1" | awk '{print $2}')"
    if [ -n "$disk" ] ; then
      export DRIVE$i
      eval DRIVE$i="$disk"
      (( used_disks = used_disks + 1 ))
    else
      unset DRIVE$i
    fi
    format_disk="$(grep -m1 -e ^FORMATDRIVE$i "$1" | awk '{print $2}')"
    export FORMAT_DRIVE$i
    eval FORMAT_DRIVE$i="0"
    if [ -n "$format_disk" ] ; then
      eval FORMAT_DRIVE$i="1"
    fi
  done

  # get count of drives
  COUNT_DRIVES=$((used_disks-1))

  # is RAID activated?
  SWRAID="$(grep -m1 -e ^SWRAID "$1" |awk '{print $2}')"
  [ "$SWRAID" = "" ] && SWRAID="0"

  # Software RAID Level
  SWRAIDLEVEL="$(grep -m1 -e ^SWRAIDLEVEL "$1" | awk '{ print $2 }')"
  [ "$SWRAIDLEVEL" = "" ] && SWRAIDLEVEL="1"

  PARTS_SUM_SIZE="0"
  PART_COUNT="$(grep -c -e '^PART' "$1")"
  PART_LINES="$(grep -e '^PART ' "$1")"
  echo "$PART_LINES" > /tmp/part_lines.tmp
  i=0
  while read -r PART_LINE ; do
    i=$((i+1))
    PART_MOUNT[$i]="$(echo "$PART_LINE" | awk '{print $2}')"
    PART_FS[$i]="$(echo "$PART_LINE" | awk '{print $3}')"
    PART_SIZE[$i]="$(translate_unit "$(echo "$PART_LINE" | awk '{ print $4 }')")"
    MOUNT_POINT_SIZE[$i]=${PART_SIZE[$i]}
    #calculate new partition size if software raid is enabled and it is not /boot or swap
    if [ "$SWRAID" = "1" ]; then
      if [ "${PART_MOUNT[$i]}" != "/boot" ] && [ "${PART_SIZE[$i]}" != "all" ] && [ "${PART_MOUNT[$i]}" != "swap" ]; then
        if [ "$SWRAIDLEVEL" = "0" ]; then
          PART_SIZE[$i]=$((${PART_SIZE[$i]}/COUNT_DRIVES))
        elif [ "$SWRAIDLEVEL" = "5" ]; then
          PART_SIZE[$i]=$((${PART_SIZE[$i]}/(COUNT_DRIVES-1)))
        elif [ "$SWRAIDLEVEL" = "6" ]; then
          PART_SIZE[$i]=$((${PART_SIZE[$i]}/(COUNT_DRIVES-2)))
        elif [ "$SWRAIDLEVEL" = "10" ]; then
          PART_SIZE[$i]=$((${PART_SIZE[$i]}/(COUNT_DRIVES/2)))
        fi
      fi
    fi
    echo "${PART_MOUNT[$i]} : ${PART_SIZE[$i]}" | debugoutput
    if [ "${PART_SIZE[$i]}" != "all" ]; then
      PARTS_SUM_SIZE=$(( ${PART_SIZE[$i]} + PARTS_SUM_SIZE ))
    fi
    if [ "${PART_MOUNT[$i]}" = "/" ]; then
      HASROOT="true"
    fi
  done < /tmp/part_lines.tmp

  # get LVM volume group config
  LVM_VG_COUNT="$(grep -c -e '^PART *lvm ' "$1")"
  LVM_VG_ALL="$(grep -e '^PART *lvm ' "$1")"

  # void the check var
  LVM_VG_CHECK=""
  for ((i=1; i<=LVM_VG_COUNT; i++)); do
    LVM_VG_LINE="$(echo "$LVM_VG_ALL" | head -n$i | tail -n1)"
    #LVM_VG_PART[$i]=$i #"$(echo $LVM_VG_LINE | awk '{print $2}')"
    LVM_VG_PART[$i]=$(echo "$PART_LINES" | grep -n -e '^PART *lvm ' | head -n$i | tail -n1 | cut -d: -f1)
    LVM_VG_NAME[$i]="$(echo "$LVM_VG_LINE" | awk '{print $3}')"
    LVM_VG_SIZE[$i]="$(translate_unit "$(echo "$LVM_VG_LINE" | awk '{print $4}')")"

    if [ "${LVM_VG_SIZE[$i]}" != "all" ] ; then
      LVM_VG_CHECK="$i $LVM_VG_CHECK"
    fi
  done

  # get LVM logical volume config
  LVM_LV_COUNT="$(grep -c -e "^LV " "$1")"
  LVM_LV_ALL="$(grep -e "^LV " "$1")"
  for ((i=1; i<=LVM_LV_COUNT; i++)); do
    LVM_LV_LINE="$(echo "$LVM_LV_ALL" | head -n"$i" | tail -n1)"
    LVM_LV_VG[$i]="$(echo "$LVM_LV_LINE" | awk '{print $2}')"
    LVM_LV_VG_SIZE[$i]="$(echo "$LVM_VG_ALL" | grep "${LVM_LV_VG[$i]}" | awk '{print $4}')"
    LVM_LV_NAME[$i]="$(echo "$LVM_LV_LINE" | awk '{print $3}')"
    LVM_LV_MOUNT[$i]="$(echo "$LVM_LV_LINE" | awk '{print $4}')"
    LVM_LV_FS[$i]="$(echo "$LVM_LV_LINE" | awk '{print $5}')"
    LVM_LV_SIZE[$i]="$(translate_unit "$(echo "$LVM_LV_LINE" | awk '{ print $6 }')")"
    # we only add LV sizes to PART_SUM_SIZE if the appropiate volume group has
    # "all" as size (otherwise we would count twice: SIZE of VG + SIZE of LVs of VG)
    if [ "${LVM_LV_SIZE[$i]}" != "all" ] && [ "${LVM_LV_VG_SIZE[$i]}" == "all" ]; then
      PARTS_SUM_SIZE=$(( ${LVM_LV_SIZE[$i]} + PARTS_SUM_SIZE ))
    fi
    if [ "${LVM_LV_MOUNT[$i]}" = "/" ]; then
      HASROOT="true"
    fi
  done



  # is LVM activated?
  [ "$LVM_VG_COUNT" != "0" ] && [ "$LVM_LV_COUNT" != "0" ] && LVM="1" || LVM="0"


  IMAGE="$(grep -m1 -e ^IMAGE "$1" | awk '{print $2}')"
  # shellcheck disable=SC2154
  [ -e "$wd/$IMAGE" ] && IMAGE="$wd/$IMAGE"
  IMAGE_PATH="$(dirname "$IMAGE")/"
  IMAGE_FILE="$(basename "$IMAGE")"
  case "$IMAGE_PATH" in
    https:*|http:*|ftp:*) IMAGE_PATH_TYPE="http" ;;
    /*) IMAGE_PATH_TYPE="local" ;;
    *)  IMAGE_PATH_TYPE="nfs"   ;;
  esac
  case "$IMAGE_FILE" in
    *.tar) IMAGE_FILE_TYPE="tar" ;;
    *.tar.gz|*.tgz) IMAGE_FILE_TYPE="tgz" ;;
    *.tar.bz|*.tbz|*.tbz2|*.tar.bz2) IMAGE_FILE_TYPE="tbz" ;;
    *.tar.xz|*.txz) IMAGE_FILE_TYPE="txz" ;;
    *.bin) IMAGE_FILE_TYPE="bin" ;;
    *.bin.bz2|*.bin.bz) IMAGE_FILE_TYPE="bbz" ;;
  esac

  BOOTLOADER="$(grep -m1 -e ^BOOTLOADER "$1" |awk '{print $2}')"
  if [ "$BOOTLOADER" = "" ]; then
    BOOTLOADER=$(echo "$DEFAULTLOADER" | awk '{ print $2 }')
  fi
  BOOTLOADER="${BOOTLOADER,,}"

  NEWHOSTNAME=$(grep -m1 -e ^HOSTNAME "$1" | awk '{print $2}')

  GOVERNOR="$(grep -m1 -e ^GOVERNOR "$1" |awk '{print $2}')"
  if [ "$GOVERNOR" = "" ]; then GOVERNOR="$DEFAULTGOVERNOR"; fi

  SYSTEMDEVICE="$DRIVE1"

  # if custom nameservers are set in the installimage config, replace the default
  # v4/v6 nameservers from config.sh by those
  local nameserver_count
  nameserver_count=$(grep -c -e ^NAMESERVER "${1}")
  if [ "${nameserver_count}" -gt 0 ]; then
    declare -a nameserver_custom

    while read -r nameserver; do
      nameserver_custom+=("$nameserver")
    done < <(grep -e ^NAMESERVER "${1}" | awk '{print $2}')

    NAMESERVER=("${nameserver_custom[@]}")
  fi

  local nameserver_v6_count
  nameserver_v6_count=$(grep -c -e ^DNSRESOLVER_V6 "${1}")
  if [ "${nameserver_v6_count}" -gt 0 ]; then
    declare -a nameserver_v6_custom

    while read -r nameserver_v6; do
      nameserver_v6_custom+=("$nameserver_v6")
    done < <(grep -e ^DNSRESOLVER_V6 "${1}" | awk '{print $2}')

    DNSRESOLVER_V6=("${nameserver_v6_custom[@]}")
  fi

  local postinstall_url
  postinstall_url=$(grep -e ^POSTINSTALLURL "${1}" | awk '{print $2}')
  if [ -n "${postinstall_url}" ]; then
    POSTINSTALLURL=${postinstall_url}
  fi

  local company_custom
  company_custom=$(grep -m1 -e ^COMPANY "${1}" | awk '{$1=""; print $0}')
  if [ -n "${company_custom}" ]; then
    COMPANY="${company_custom}"
  fi

  local c_short_custom
  c_short_custom=$(grep -m1 -e ^C_SHORT "${1}" | awk '{print $2}')
  if [ -n "${c_short_custom}" ]; then
    C_SHORT="${c_short_custom}"
  fi

  # overwrite SSH key settings from commandline
  # you can set that also via -K, but configfile is superior
  local sshkeys_url
  sshkeys_url=$(grep -m1 -e ^SSHKEYS_URL "${1}" | awk '{print $2}')
  if [ -n "$sshkeys_url" ]; then
    export OPT_SSHKEYS_URL="$sshkeys_url"
    export OPT_USE_SSHKEYS=1
  fi

fi
}


# validate all variables for correct values
# validate_vars "CONFIGFILE"
validate_vars() {
 if [ "$1" ]; then

  read_vars "$1"

  # test if IMAGEPATH is given
  if [ -z "$IMAGE_PATH" ]; then
   graph_error "ERROR: No valid IMAGEPATH"
   return 1
  fi

  # test if PATHTYPE is a supported type
  CHECK="$(echo $IMAGE_PATH_TYPE |grep -i -e '^http$\|^nfs$\|^local$')"
  if [ -z "$CHECK" ]; then
   graph_error "ERROR: No valid PATHTYPE"
   return 1
  fi

  # test if IMAGEFILE is given
  if [ -z "$IMAGE_FILE" ]; then
   graph_error "ERROR: No valid IMAGEFILE"
   return 1
  fi

  # test if FILETYPE is a supported type
  CHECK="$(echo $IMAGE_FILE_TYPE |grep -i -e '^tar$\|^tgz$\|^tbz$\|^txz$\|^bin$\|^bbz$')"
  if [ -z "$CHECK" ]; then
   graph_error "ERROR: $IMAGE_FILE_TYPE is no valid FILETYPE for images"
   return 1
  fi

  whoami "$IMAGE_FILE"

  # test if "$DRIVE1" is a valid block device and is able to create partitions
  CHECK="$(test -b "$DRIVE1" && sfdisk -l "$DRIVE1" 2>>/dev/null)"
  if [ -z "$CHECK" ]; then
    graph_error "ERROR: Value for DRIVE1 is not correct: $DRIVE1 "
    return 1
  fi

  # test if "$DRIVE1" is not busy
#  CHECK="$(hdparm -z $DRIVE1 2>&1 | grep 'BLKRRPART failed: Device or resource busy')"
#  if [ "$CHECK" ]; then
#    graph_error "ERROR: DRIVE1 is busy - cannot access device $DRIVE1 "
#    return 1
#  fi

  # test if "$SWRAID" has not 0 or 1 as parameter
  if [ "$SWRAID" != "0" ] && [ "$SWRAID" != "1" ]; then
    graph_error "ERROR: Value for SWRAID is not correct"
    return 1
  fi

  # test if "$SWRAIDLEVEL" is either 0 or 1
  if [ "$SWRAID" = "1" ] && [ "$SWRAIDLEVEL" != "0" ] &&
    [ "$SWRAIDLEVEL" != "1" ] && [ "$SWRAIDLEVEL" != "5" ] &&
    [ "$SWRAIDLEVEL" != "6" ] && [ "$SWRAIDLEVEL" != "10" ]; then
    graph_error "ERROR: Value for SWRAIDLEVEL is not correct"
    return 1
  fi

  # check for valid drives
  local drive_array=( "${DRIVE1}" )
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    local format; format="$(eval echo "\$FORMAT_DRIVE$i")"
    local drive; drive="$(eval echo "\$DRIVE$i")"
    if [ "$i" -gt 1 ] ; then
      for j in $(seq 0 $((${#drive_array[@]} - 1))); do
        if [ "${drive_array[$j]}" = "$drive" ]; then
          graph_error "Duplicate DRIVE definition. $drive used for DRIVE$((j+1)) and DRIVE$i"
        fi
      done
      drive_array=( "${drive_array[@]}" "$drive" )
      if [ "$format" != "0" ] && [ "$format" != "1" ]; then
        graph_error "ERROR: Value for FORMATDRIVE$i is not correct"
        return 1
      fi
      if [ "$format" = 1 ] && [ "$SWRAID" = 1 ] ; then
        graph_error "ERROR: FORMATDRIVE$i _AND_ SWRAID are active - use one or none of these options, not both"
        return 1
      fi
    fi
    if [ "$SWRAID" = "1" ] || [ "$format" = "1" ] || [ "$i" -eq 1 ] ; then
      # test if drive is a valid block device and is able to create partitions
      CHECK="$(test -b "$drive" && sfdisk -l "$drive" 2>>/dev/null)"
      if [ -z "$CHECK" ]; then
        graph_error "ERROR: Value for DRIVE$i is not correct: $drive"
        return 1
      fi

      # test if drive is not busy
      CHECK="$(hdparm -z "$drive" 2>&1 | grep 'BLKRRPART failed: Device or resource busy')"
      if [ "$CHECK" ]; then
        graph_error "ERROR: DRIVE$i is busy - cannot access device $drive"
        return 1
      fi
    fi
  done

  # test if there is more than 1 hdd if swraid enabled
  if [ "$SWRAID" = "1" ] && [ $COUNT_DRIVES -le 1 ] ; then
    graph_error "ERROR: You need to select at least 2 disks for creating software raid!"
    return 1
  fi

  # test if enough disks for the choosen raid level
  if [ "$SWRAID" = "1" ]; then
    if [ "$SWRAIDLEVEL" = "5" ] && [ "$COUNT_DRIVES" -lt "3" ]; then
      graph_error "ERROR: Not enough disks for RAID level 5"
      return 1
    elif [ "$SWRAIDLEVEL" = "6" ] && [ "$COUNT_DRIVES" -lt "4" ]; then
      graph_error "ERROR: Not enough disks for RAID level 6"
      return 1
    elif [ "$SWRAIDLEVEL" = "10" ] && [ "$COUNT_DRIVES" -lt "2" ]; then
      graph_error "ERROR: Not enough disks for RAID level 10"
      return 1
    fi
  fi

  # test if a /boot partition is defined when using software RAID 0
  if [ "$SWRAID" = "1" ]; then
    if [ "$SWRAIDLEVEL" = "0" ] || [ "$SWRAIDLEVEL" = "5" ] ||
      [ "$SWRAIDLEVEL" = "6" ] || [ "$SWRAIDLEVEL" = "10" ]; then
      TMPCHECK=0

      for ((i=1; i<=PART_COUNT; i++)); do
        if [ "${PART_MOUNT[$i]}" = "/boot" ]; then
          TMPCHECK=1
        fi
      done

      if [ $TMPCHECK -eq 0 ]; then
        graph_error "ERROR: You need a /boot partition when using software RAID level 0, 5, 6 or 10"
        return 1
      fi
    fi
  fi

  # calculate drive_sum_size
  if [ "$SWRAID" = "0" ] ; then
    # just the first hdd is used so we need the size of DRIVE1
    DRIVE_SUM_SIZE=$(blockdev --getsize64 "$DRIVE1")
    echo "Size of the first hdd is: $DRIVE_SUM_SIZE" | debugoutput
  else
    local smallest_hdd; smallest_hdd=$(smallest_hd)
    DRIVE_SUM_SIZE="$(blockdev --getsize64 "$smallest_hdd")"
    # this variable is used later when determining what disk to use as reference
    # when drives of different sizes are in a system
    SMALLEST_HDD_SIZE="$DRIVE_SUM_SIZE"
    SMALLEST_HDD_SIZE=$((SMALLEST_HDD_SIZE / 1024 / 1024))
    echo "Size of smallest drive is $DRIVE_SUM_SIZE" | debugoutput
    if [ "$SWRAIDLEVEL" = "0" ]; then
      DRIVE_SUM_SIZE=$((DRIVE_SUM_SIZE * COUNT_DRIVES))
    elif [ "$SWRAIDLEVEL" = "5" ]; then
      DRIVE_SUM_SIZE=$((DRIVE_SUM_SIZE * (COUNT_DRIVES - 1)))
    elif [ "$SWRAIDLEVEL" = "6" ]; then
      DRIVE_SUM_SIZE=$((DRIVE_SUM_SIZE * (COUNT_DRIVES - 2)))
    elif [ "$SWRAIDLEVEL" = "10" ]; then
      DRIVE_SUM_SIZE=$((DRIVE_SUM_SIZE * (COUNT_DRIVES / 2)))
    fi
    debug "Calculated size of array is: $DRIVE_SUM_SIZE"
  fi

  DRIVE_SUM_SIZE=$((DRIVE_SUM_SIZE / 1024 / 1024))
  for ((i=1; i<=PART_COUNT; i++)); do
    if [ "${PART_SIZE[$i]}" = "all" ]; then
      # make sure that the all partition has at least 1G available
      DRIVE_SUM_SIZE=$((DRIVE_SUM_SIZE - 1024))
    fi
  done


  # test if /boot or / is mounted outside the LVM
  if [ "$LVM" = "1" ]; then
    TMPCHECK=0
    for ((i=1; i<=PART_COUNT; i++)); do
      if [ "${PART_MOUNT[$i]}" = "/boot" ]; then
        TMPCHECK=1
      fi
    done

    if [ "$TMPCHECK" = "0" ]; then
      for ((i=1; i<=PART_COUNT; i++)); do
        if [ "${PART_MOUNT[$i]}" = "/" ]; then
          TMPCHECK=1
        fi
      done
    fi

    if [ "$TMPCHECK" = "0" ]; then
      graph_error "ERROR: /boot or / may not be a Logical Volume"
      return 1
    fi
  fi

  # Check if /boot or / is mounted on one of the first three partitions.
  if [ "$PART_COUNT" -gt 3 ]; then
    tmp=0

    for ((i=1; i<=PART_COUNT; i++)); do
      if [ "${PART_MOUNT[$i]}" = "/boot" ]; then
        tmp=$i
        break
      fi
    done

    if [ "$tmp" -gt 3 ]; then
      graph_error "ERROR: /boot must be mounted on a primary partition"
      return 1
    fi

    if [ "$tmp" -eq 0 ]; then
      for ((i=4; i<=PART_COUNT; i++)); do
        if [ "${PART_MOUNT[$i]}" = "/" ]; then
          graph_error "ERROR: / must be mounted on a primary partition"
          return 1
        fi
      done
    fi
  fi


  # test if there are partitions in the configfile
  if [ "$PART_COUNT" -gt "0" ]; then
  WARNBTRFS=0
    # test each partition line
    for ((i=1; i<=PART_COUNT; i++)); do

      # test if the mountpoint is valid (start with / or swap or lvm)
      CHECK="$(echo "${PART_MOUNT[$i]}" | grep -e '^none\|^/\|^swap$\|^lvm$')"
      if [ -z "$CHECK" ]; then
        graph_error "ERROR: Mountpoint for partition $i is not correct"
        return 1
      fi

      # test if the filesystem is one of our supportet types (btrfs/ext2/ext3/ext4/reiserfs/xfs/swap)
      CHECK="$(echo "${PART_FS[$i]}" |grep -e '^bios_grub\|^btrfs$\|^ext2$\|^ext3$\|^ext4$\|^reiserfs$\|^xfs$\|^swap$\|^lvm$')"
      if [ -z "$CHECK" ] && [ "${PART_MOUNT[$i]}" != "lvm" ]; then
        graph_error "ERROR: Filesystem for partition $i is not correct"
        return 1
      fi

      if [ "${PART_FS[$i]}" = "reiserfs" ] && [ "$IAM" = "centos" ]; then
        graph_error "ERROR: centos doesn't support reiserfs"
        return 1
      fi

      # warn if using btrfs
      if [ "${PART_FS[$i]}" = "btrfs" ]; then
        WARNBTRFS=1
      fi

      # we can't use bsdtar on non ext2/3/4 partitions
      CHECK=$(echo "${PART_FS[$i]}" |grep -e '^ext2$\|^ext3$\|^ext4$\|^swap$')
      if [ -z "$CHECK" ] && [ "${PART_MOUNT[$i]}" != "lvm" ]; then
        export TAR="tar"
        echo "setting TAR to GNUtar" | debugoutput
      fi

      if [ "${PART_FS[$i]}" = "btrfs" ] && [ "$IAM" = "centos" ] && [ "$IMG_VERSION" -lt 62 ]; then
        graph_error "ERROR: CentOS older than 6.2 doesn't support btrfs"
        return 1
      fi

      # test if "all" is at the last partition entry
      ### TODO: correct this for LVM
      if [ "${PART_SIZE[$i]}" = "all" ] && [ "$i" -lt "$PART_COUNT" ]; then
        graph_error "ERROR: Partition size \"all\" has to be on the last partition"
        return 1
      fi

      # Check if the partition size is a valid number
      # shellcheck disable=SC2015
      if [ "${PART_SIZE[$i]}" != "all" ] && [ ! -z "${PART_SIZE[$i]//[0-9]}" ] || [ "${PART_SIZE[$i]}" = "0" ]; then
        graph_error "ERROR: The size of the partiton PART ${PART_MOUNT[$i]} is not a valid number"
        return 1
      fi

      # check if /boot partition has at least 200M
      if [ "${PART_MOUNT[$i]}" = "/boot" ] && [ "${PART_SIZE[$i]}" != "all" ]; then
        if [ "${MOUNT_POINT_SIZE[$i]}" -lt "200" ]; then
          graph_error "ERROR: Your /boot partition has to be at least 200M (current size: ${MOUNT_POINT_SIZE[$i]})"
          return 1
        fi
      fi

      # check if / partition has at least 1500M
      if [ "${PART_MOUNT[$i]}" = "/" ] && [ "${PART_SIZE[$i]}" != "all" ]; then
        if [ "${MOUNT_POINT_SIZE[$i]}" -lt "1500" ]; then
          graph_error "ERROR: Your / partition has to be at least 1500M (current size: ${MOUNT_POINT_SIZE[$i]})"
          return 1
        fi
      fi

      if [ "$BOOTLOADER" = "grub" ]; then
        if [ "${PART_MOUNT[$i]}" = "/boot" ] && [ "${PART_FS[$i]}" = "xfs" ]; then
          graph_error "ERROR: /boot partiton will not work properly with xfs"
          return 1
        fi

        if [ "${PART_MOUNT[$i]}" = "/" ] && [ "${PART_FS[$i]}" = "xfs" ]; then
          TMPCHECK="0"
          if [ "$IAM" = "centos" ] && [ "$IMG_ARCH" = "32" ]; then
            graph_error "ERROR: CentOS 32bit doesn't support xfs on partition /"
            return 1
          fi
          for j in $(seq 1 "$PART_COUNT"); do
            if [ "${PART_MOUNT[$j]}" = "/boot" ]; then
              TMPCHECK="1"
            fi
          done
          if [ "$TMPCHECK" = "0" ]; then
            graph_error "ERROR: / partiton will not work properly with xfs with no /boot partition"
            return 1
          fi
        fi
      fi

    done
    if [ "$WARNBTRFS" = "1" ]; then
      graph_notice "WARNING: the btrfs filesystem is still under development. Data loss may occur!"
    fi
  else
   graph_error "ERROR: The config has no partitions"
   return 1
  fi


  # test if there are lvs in the configfile
  if [ "$LVM_VG_COUNT" -gt "0" ]; then
    names=

    for i in $(seq 1 "$LVM_VG_COUNT"); do
      names="${names}\\n${LVM_VG_NAME[$i]}"
    done

    if [ "$(echo "$names" | grep -v -e "^$" | sort | uniq -d | wc -l)" -gt 1 ] && [ "$BOOTLOADER" = "lilo" ] ; then
      graph_error "ERROR: you cannot use more than one VG with lilo - use grub as bootloader"
      return 1
    fi

  fi

  CHECK="$(echo "$BOOTLOADER" |grep -i -e '^grub$\|^lilo$')"
  if [ -z "$CHECK" ]; then
   graph_error "ERROR: No valid BOOTLOADER"
   return 1
  fi

  if [ "$BOOTLOADER" = "lilo" ]; then
    if [ "$IAM" = "arch" ] ||
       [ "$IAM" = "coreos" ] ||
       [ "$IAM" = "centos" ] ||
       [ "$IAM" = "ubuntu" ] && [ "$IMG_VERSION" -ge 1204 ] ||
       [ "$IAM" = "debian" ] && [ "$IMG_VERSION" -ge 70 ] ||
       [ "$IAM" = "suse" ] && [ "$IMG_VERSION" -ge 122 ]; then
         graph_error "ERROR: Image doesn't support lilo"
         return 1
    fi
  fi

  CHECK=$(echo "$GOVERNOR" |grep -i -e '^powersave$\|^performance$\|^ondemand$')
  if [ -z "$CHECK" ]; then
   graph_error "ERROR: No valid GOVERNOR"
   return 1
  fi

  # LVM checks
  if [ "$LVM" = "0" ] && [ "$LVM_VG_COUNT" != "0" ] ; then
    graph_error "ERROR: There are volume groups defined, but no logical volumes are defined"
    return 1
  fi

  if [ "$LVM" = "0" ] && [ "$LVM_LV_COUNT" != "0" ] ; then
    graph_error "ERROR: There are logical volumes defined, but no volume groups are defined"
    return 1
  fi

  for lv_id in $(seq 1 "$LVM_LV_COUNT") ; do
    lv_size="${LVM_LV_SIZE[$lv_id]}"
    lv_mountp="${LVM_LV_MOUNT[$lv_id]}"
    lv_fs="${LVM_LV_FS[$lv_id]}"
    lv_vg="${LVM_LV_VG[$lv_id]}"


    # test if the mountpoint is valid (start with / or swap)
    CHECK="$(echo "$lv_mountp" | grep -e '^/\|^swap$')"
    if [ -z "$CHECK" ]; then
      graph_error "ERROR: Mountpoint for LV '${LVM_LV_NAME[$lv_id]}' is not correct"
      return 1
    fi

    # test if the filesystem is one of our supportet types (ext2/ext3/reiserfs/xfs/swap)
    CHECK="$(echo "$lv_fs" |grep -e '^btrfs$\|^ext2$\|^ext3$\|^ext4$\|^reiserfs$\|^xfs$\|^swap$')"
    if [ -z "$CHECK" ]; then
      graph_error "ERROR: Filesystem for LV '${LVM_LV_NAME[$lv_id]}' is not correct"
      return 1
    fi

    # test if one of the filesystem is not using ext
    CHECK=$(echo "$lv_fs" |grep -e '^ext2$\|^ext3$\|^ext4$\|^swap$')
    if [ -z "$CHECK" ]; then
      export TAR="tar"
      echo "setting TAR to GNUtar" | debugoutput
    fi

    if [ "$lv_fs" = "reiserfs" ] && [ "$IAM" = "centos" ]; then
      graph_error "ERROR: centos doesn't support reiserfs"
      return 1
    fi

#   this seems to be a very old problem. Not a problem for 6.x and later
#    if [ "$lv_fs" = "xfs" ] && [ "$lv_mountp" = "/" ] && [ "$IAM" = "centos" ]; then
#      graph_error "ERROR: centos doesn't support xfs on partition /"
#      return 1
#    fi
    # shellcheck disable=SC2015
    if [ "$lv_size" != "all" ] && [ ! -z "${lv_size//[0-9]}" ] || [ "$lv_size" = "0" ]; then
      graph_error "ERROR: size of LV '${LVM_LV_NAME[$lv_id]}' is not a valid number"
      return 1
    fi

    if [ "$lv_mountp" = "/" ] && [ "$lv_size" != "all" ]; then
      if [ "$lv_size" -lt "1500" ]; then
        graph_error "ERROR: Your / partition has to be at least 1500M"
        return 1
      fi
    fi

    # problem with multiple vgs and all as lv size
    # get last lv in vg
    for i_lv in $(seq 1 "$LVM_LV_COUNT") ; do
      if [ "${LVM_LV_VG[$i_lv]}" = "$lv_vg" ] ; then
        vg_last_lv=$i_lv
      fi
    done
    if [ "$lv_size" = "all" ] && [ "$vg_last_lv" -ne "$lv_id" ] ; then
      graph_error "ERROR: LV size \"all\" has to be on the last LV in VG $lv_vg."
      return 1
    fi
  done

  for lv_id in $(seq 1 "$LVM_LV_COUNT") ; do
    found_vg="false"
    lv_vg=${LVM_LV_VG[$lv_id]}
    for vg_id in $(seq 1 "$LVM_VG_COUNT") ; do
      [ "$lv_vg" = "${LVM_VG_NAME[$vg_id]}" ] && found_vg="true"
    done
    if [ "$found_vg" = "false" ] ; then
      graph_error "ERROR: LVM volume group '$lv_vg' not defined"
      return 1
    fi
  done

  # check for lvm size
  for vg_id in $LVM_VG_CHECK ; do
    vg_name="${LVM_VG_NAME[$vg_id]}"
    vg_size="${LVM_VG_SIZE[$vg_id]}"
    sum_size="0"

    # calculate size correct if more vg with same name
    # (e.g. for 2TB limit in CentOS workaround)
    for i in $(seq 1 "$LVM_VG_COUNT") ; do
      # check if vg has same name and is not the same vg
      if [ "${LVM_VG_NAME[$i]}" = "$vg_name" ] && [ "$i" -ne "$vg_id" ] ; then
        vg_add_size=0
        if [ "${LVM_VG_SIZE[$i]}" = "all" ] ; then
          vg_add_size=$((DRIVE_SUM_SIZE - PARTS_SUM_SIZE))
        else
          vg_add_size=${LVM_VG_SIZE[$i]}
        fi
        vg_size=$((vg_size + vg_add_size))
      fi
    done

    for lv_id in $(seq 1 "$LVM_LV_COUNT") ; do
      if [ "${LVM_LV_VG[$lv_id]}" = "$vg_name" ] && [ "${LVM_LV_SIZE[$lv_id]}" = "all" ] ; then
        sum_size=$((sum_size + ${LVM_LV_SIZE[$lv_id]}))
      fi
    done

    if [ $vg_size -lt $sum_size ] ; then
      graph_error "ERROR: You are going to use more space than your VG $vg_name has available."
      return 1
    fi

  done

  #check for identical mountpoints listed in "PART" and "LV"

  local mounts_as_string=""

  # list all mountpoints without the 'lvm' and 'swap' keyword
  for i in $(seq 1 "$PART_COUNT"); do
      if [ "${PART_MOUNT[$i]}" != "lvm" ] && [ "${PART_MOUNT[$i]}" != "swap" ]; then
          mounts_as_string="${mounts_as_string}${PART_MOUNT[$i]}\\n"
      fi
  done
  # append all logical volume mountpoints to "$mounts_as_string"
  for i in $(seq 1 "$LVM_LV_COUNT"); do
      mounts_as_string="${mounts_as_string}${LVM_LV_MOUNT[$i]}\\n"
  done

  # check if there are identical mountpoints
  local identical_mount_points; identical_mount_points="$(echo "$mounts_as_string" | sort | uniq -d)"
  if [ "$identical_mount_points" ]; then
     graph_error "ERROR: There are identical mountpoints in the config ($(echo "$identical_mount_points" | tr " " ", "))"
     return 1
  fi

  # check size of partitions
  if [ -n "$(getUSBFlashDrives)" ]; then
    graph_notice "\\nYou are going to install on an USB flash drive ($(getUSBFlashDrives)). Do you really want this?"
  fi

  if [ "$SWRAID" -eq 1 ]; then
    if [ "$(getHDDsNotInToleranceRange)" ]; then
      graph_notice "
             \\nNOTICE: You are going to use hard disks with different disk space.
             \\nWe set the maximum of your allocable disc space based on the smallest hard disk at $SMALLEST_HDD_SIZE MB
             \\nYou can change this by customizing the drive settings.
             "
    fi
  fi

  if [ "$DRIVE_SUM_SIZE" -lt "$PARTS_SUM_SIZE" ]; then
    local diff=$((DRIVE_SUM_SIZE - PARTS_SUM_SIZE))
    graph_error "ERROR: You are going to use more space than your drives have available.
                 \\nUsage: $PARTS_SUM_SIZE MiB of $DRIVE_SUM_SIZE MiB
                 \\nDiff: $diff MiB"
    return 1
  fi

  if [ "$HASROOT" != "true" ]; then
    graph_error "ERROR: You dont have a partition for /"
    return 1
  fi

  if [ "$OPT_INSTALL" ]; then
    if echo "$OPT_INSTALL" | grep -qi "PLESK"; then
        if [ "$IAM" != "centos" ] && [ "$IAM" != "debian" ]; then
          graph_error "ERROR: PLESK is not available for this image"
          return 1
        fi
    fi
  fi

  if [ "$BOOTLOADER" == "grub" ]; then
    # check dos partition sizes for centos
    local result; result="$(check_dos_partitions '')"

    if [ -n "$result" ]; then
      if [ "$result" == "PART_OVERSIZED" ]; then
        graph_error "One of your partitions is using more than 2TiB. CentOS only supports booting from hard disks with MS-DOS partition tables which allows only partition sizes up to 2TiB."
        return 1
      elif [ "$result" == "PART_BEGIN_OVER_LIMIT" ]; then
        graph_error "One of your partitions is starting above 2TiB. CentOS only supports booting from hard disks with MS-DOS partition tables which requires partitions to start below 2TiB."
        return 1
      elif [ "$result" == "PART_ALL_BEGIN_OVER_LIMIT" ]; then
        graph_error "The \"all\" partition would be starting above 2TiB. CentOS only supports booting from hard disks with MS-DOS partition tables which requires partitions to start below 2TiB."
        return 1
      elif [ "$result" == "PART_CHANGED_ALL" ]; then
        if [ "$OPT_AUTOMODE" = 1 ] || [ -e /autosetup ]; then
          echo -e 'CentOS only supports MS-DOS partition tables when using grub. We changed the space of your \"all\" partition to match the 2TiB limit.' | debugoutput
        else
          graph_notice "CentOS only supports MS-DOS partition tables when using grub. We changed the space of your \"all\" partition to match the 2TiB limit."
        fi
      fi
    fi
  fi

  if [ "$BOOTLOADER" == "lilo" ]; then
    graph_notice "WARNING: Lilo is deprecated and no longer supported. Please consider using grub"
  fi

  if [ -z "$NEWHOSTNAME" ]; then
    graph_error "ERROR: HOSTNAME may not be empty"
    return 1
  fi

  if [ "$MBTYPE" = "D3401-H1" ]; then
    if [ "$IAM" = "debian" ] && [ "$IMG_VERSION" -lt 82 ]; then
      if [ "$OPT_AUTOMODE" = 1 ] || [ -e /autosetup ]; then
        echo "WARNING: Debian versions older than Debian 8.2 have no support for the Intel i219 NIC of this board." | debugoutput
      else
        graph_notice "WARNING: Debian versions older than Debian 8.2 have no support for the Intel i219 NIC of this board."
      fi
    fi
    if [ "$IAM" = "centos" ] && [ "$IMG_VERSION" -ge 70 ] && [ "$IMG_VERSION" -lt 72 ]; then
      if [ "$OPT_AUTOMODE" = 1 ] || [ -e /autosetup ]; then
        echo "WARNING: CentOS 7.0 and 7.1 have no support for the Intel i219 NIC of this board." | debugoutput
      else
        graph_notice "WARNING: CentOS 7.0 and 7.1 have no support for the Intel i219 NIC of this board."
      fi
    fi
  fi

  if [ -n "${POSTINSTALLURL}" ]; then
    case "${POSTINSTALLURL}" in
      https:*|http:*|ftp:*)
        # test if the specified POSTINSTALLURL is available for downloading
        if ! curl -s --insecure --connect-timeout 5 --head --fail "${POSTINSTALLURL}" 1>/dev/null; then
          POSTINSTALLURL=""
          debug "Can't download postinstall script from ${POSTINSTALLURL}"
        fi
      ;;
      *)
        POSTINSTALLURL=""
        debug "Invalid URL for postinstall script"
      ;;
    esac
  fi

 fi
 return 0
}

#
# graph_error [text]
#
# Show graphical error when a validation error occurs.
#
graph_error() {
  if [ $# -gt 0 ]; then
    dialog --backtitle "$DIATITLE" --title "ERROR" --yes-label "OK" \
        --no-label "Cancel" --yesno \
        "${*}\\n\\nYou will be dropped back to the editor to fix the problem." 0 0
    EXITCODE=$?
  else
    dialog --backtitle "$DIATITLE" --title "ERROR" --yes-label "OK" \
        --no-label "Cancel" --yesno "An unknown error occured..." 0 0
    EXITCODE=$?
  fi

  # set var if user hit "Cancel"
  if [ "$EXITCODE" -eq "1" ]; then
    export CANCELLED="true"
  fi
}

#
# graph_notice [text]
#
# Show graphical notice to user.
#
graph_notice() {
  if [ $# -gt 0 ]; then
    dialog --backtitle "$DIATITLE" --title "NOTICE" --msgbox \
        "${*}\\n\\n" 0 0
  fi
}

# which operating system will be installed
# whoami "IMAGENAME"
whoami() {
 IAM="debian"
 if [ "$1" ]; then
  case "$1" in
    *SuSE*|*suse*|*Suse*|*SUSE*)IAM="suse";;
    *CentOS*|*centos*|*Centos*)IAM="centos";;
    *Ubuntu*|*ubuntu*)IAM="ubuntu";;
    Arch*)IAM="arch";;
    CoreOS*|coreos*)
      IAM="coreos"
      CLOUDINIT="$FOLD/cloud-config"
      echo -e '#cloud-config\n' > "$CLOUDINIT"
    ;;
  esac
 fi

 IMG_VERSION="$(echo "$1" | cut -d "-" -f 2)"
 [ -z "$IMG_VERSION" ] || [ "$IMG_VERSION" = "" ] || [ "$IMG_VERSION" = "h.net.tar.gz" ]  && IMG_VERSION="0"
 # shellcheck disable=SC2001
 IMG_ARCH="$(echo "$1" | sed 's/.*-\(32\|64\)-.*/\1/')"

 # shellcheck disable=SC2010
 IMG_FULLNAME="$(ls -1 "$IMAGESPATH" | grep "$1" | grep -v ".sig")"
 IMG_EXT="${IMG_FULLNAME#*.}"

 export IAM
 export IMG_VERSION
 export IMG_ARCH
 export IMG_EXT

 return 0
}

#
# unmount_all
#
# Unmount all partitions and display an error message if
# unmounting a partition failed.
#
unmount_all() {
  unmount_errors=0

  while read -r line ; do
    device="$(echo "$line" | grep -v "^/dev/loop" | grep -v "^/dev/root" | grep "^/" | awk '{ print $1 }')"
    if [ "$device" ] ; then
      unmount_output="${unmount_output}\\n$(umount "$device" 2>&1)"; EXITCODE=$?
      unmount_errors=$((unmount_errors + EXITCODE))
    fi
  done < /proc/mounts
  echo "$unmount_output"
  return "$unmount_errors"
}

#
# stop_lvm_raid
#
# Stop the Logical Volume Manager and all software RAID arrays.
# TODO: adopt to systemd
#
stop_lvm_raid() {
  test -x /etc/init.d/lvm && /etc/init.d/lvm stop &>/dev/null
  test -x /etc/init.d/lvm2 && /etc/init.d/lvm2 stop &>/dev/null

  dmsetup remove_all > /dev/null 2>&1

  if [ -x "$(command -v mdadm)" ] && [ -f /proc/mdstat ]; then
    grep md /proc/mdstat | cut -d ' ' -f1 | while read -r i; do
      [ -e "/dev/$i" ] && mdadm -S "/dev/$i" >> /dev/null 2>&1
    done
  fi
}


# delete partitiontable
# delete_partitions "DRIVE"
delete_partitions() {
 if [ "$1" ]; then
  # clean RAID information for every partition not only for the blockdevice
  for raidmember in $(sfdisk -l "$1" 1>/dev/null 2>/dev/null | grep -o "$1[0-9]"); do
    mdadm --zero-superblock "$raidmember" 2> /dev/null
  done
  # clean RAID information in superblock of blockdevice
  mdadm --zero-superblock "$1" 2> /dev/null

  #delete GPT and MBR
  sgdisk -Z "$1" 1>/dev/null 2>/dev/null

  # clean mbr boot code
  dd if=/dev/zero of="$1" bs=512 count=1 >/dev/null 2>&1 ; EXITCODE=$?

  # re-read partition table
  partprobe 2>/dev/null

  return "$EXITCODE"
 fi
}


# function which gets the end of the extended partition
# get_end_of_extended "DRIVE"
function get_end_of_extended() {
  local dev="$1"
  local drive_size; drive_size=$(blockdev --getsize64 "$DEV")
  local sectorsize; sectorsize=$(blockdev --getss "$DEV")

  local end=0
  local sum=0
  local limit=2199023255040
  # get sector limit
  local sectorlimit=$(((limit / sectorsize) - 1))
  local startsec; startsec=$(sgdisk --first-aligned-in-largest "$1" | tail -n1)

  for i in $(seq 1 3); do
    sum=$(echo "$sum + ${PART_SIZE[$i]}" | bc)
  done
  rest=$(echo "$drive_size - ($sum * 1024 * 1024)" | bc)

  end=$((drive_size / sectorsize))

  if [ "$drive_size" -lt "$limit" ]; then
    echo "$((end-1))"
  else
    if [ "$rest" -gt "$limit" ]; then
      # if the remaining space is more than 2 TiB, the end of the extended
      # partition is the current sector plus 2^32-1 sectors (2TiB-512 Byte)
      echo "$startsec+$sectorlimit" | bc
    else
      # otherwise the end is the number of sectors - 1
      echo "$((end-1))"
    fi
  fi
}

# function which calculates the end of the partition
# get_end_of_partition "PARTITION"
function get_end_of_partition {
  local dev=$1
  local start=$2
  local nr=$3
  local limit=2199023255040
  local sectorsize; sectorsize=$(blockdev --getss "$dev")
  local sectorlimit=$(((limit / sectorsize) - 1))
  local end_extended; end_extended="$(parted -s "$dev" unit b print | grep extended | awk '{print $3}' | sed -e 's/B//')"
  local devsize; devsize=$(blockdev --getsize64 "$dev")
  start=$((start * sectorsize))
  # use the smallest hdd as reference when using swraid
  # to determine the end of a partition
  local smallest_hdd; smallest_hdd=$(smallest_hd)
  local smallest_hdd_space; smallest_hdd_space="$(blockdev --getsize64 "$smallest_hdd")"
  if [ "$SWRAID" -eq "1" ] && [ "$devsize" -gt "$smallest_hdd_space" ]; then
    dev="$smallest_hdd"
  fi

  local last; last=$(blockdev --getsize64 "$dev")
  # make the partition at least 1 MiB if all else fails
  local end=$((start+1048576))

  if [ "$(echo ${PART_SIZE[$nr]} | tr "[:upper:]" "[:lower:]")" = "all" ]; then
    # leave 1MiB space at the end (may be needed for mdadm or for later conversion to GPT)
    end=$((last-1048576))
  else
    end="$(echo "$start+(${PART_SIZE[$nr]}* 1024 * 1024)" | bc)"
    # trough alignment the calculated end could be a little bit over drive size
    # or too close to the end. Always leave 1MiB space
    # (may be needed for mdadm or for later conversion to GPT)
    if [ "$end" -ge "$last" ] || [ $((last - end)) -lt 1048576 ]; then
      end=$((last-1048576))
    fi
  fi
  # check if end of logical partition is over the end extended partition
  if [ "$PCOUNT" -gt 4 ] && [ "$end" -gt "$end_extended" ]; then
    # leave 1MiB space at the end (may be needed for mdadm or for later conversion to GPT)
    end=$((end_extended-1048576))
  fi

  end=$((end / sectorsize))
  echo "$end"
}


# create partitons on the given drive
# create_partitions "DRIVE"
create_partitions() {
 if [ "$1" ]; then
  local SECTORSIZE; SECTORSIZE=$(blockdev --getss "$1")

  # write standard entries to fstab
  echo "proc /proc proc defaults 0 0" > "$FOLD/fstab"
  # add fstab entries for devpts, sys and shm in CentOS as they are not
  # automatically mounted by init skripts like in Debian/Ubuntu and OpenSUSE
  if [ "$IAM" = "centos" ]; then
    {
      echo "devpts /dev/pts devpts gid=5,mode=620 0 0"
      echo "tmpfs /dev/shm tmpfs defaults 0 0"
      echo "sysfs /sys sysfs defaults 0 0"
    } >> "$FOLD/fstab"
  fi
  #copy defaults to tempfstab for softwareraid
  ### cp "$FOLD"/fstab $FOLD/fstab.md >>/dev/null 2>&1

  echo "deactivate all dm-devices with dmraid and dmsetup" | debugoutput
  dmsetup remove_all 2>&1 | debugoutput
  mkdir -p /run/lock
  dmraid -a no 2>&1 | debugoutput

  dd if=/dev/zero of="$1" bs=1M count=10  1>/dev/null 2>&1
  hdparm -z "$1" >/dev/null 2>&1

  #create GPT
  if [ "$GPT"  -eq '1' ]; then
    #create GPT and randomize disk id (GUID)
    sgdisk -o "$1" 1>/dev/null 2>/dev/null
    sgdisk -G "$1" 1>/dev/null 2>/dev/null

    # set dummy partition active/bootable in protective MBR to give some too
    # smart BIOS the clue that this disk can be booted in legacy mode
    sfdisk -A "$1" 1 --force 1>/dev/null 2>/dev/null
  else
    parted -s "$1" mklabel msdos 1>/dev/null 2>/tmp/$$.tmp
    debugoutput < /tmp/$$.tmp
  fi

  # start loop to create all partitions
  for i in $(seq 1 "$PART_COUNT"); do

   SFDISKTYPE="83"
   if [ "${PART_FS[$i]}" = "swap" ]; then
     SFDISKTYPE="82"
   fi
   if [ "${PART_MOUNT[$i]}" = "lvm" ]; then
     SFDISKTYPE="8e"
   fi
   if [ "$SWRAID" -eq "1" ]; then
     SFDISKTYPE="fd"
   fi

   if [ "$(echo ${PART_SIZE[$i]} | tr "[:upper:]" "[:lower:]")" = "all" ]; then
     SFDISKSIZE=""
   else
     SFDISKSIZE="${PART_SIZE[$i]}"
   fi


   #create GPT partitions
   if [ "$GPT" -eq 1 ]; then

     # start at 2MiB so we have 1 MiB left for BIOS Boot Partition
     START=$((2097152/SECTORSIZE))
     if [ "$i" -gt 1 ]; then
       START=$(sgdisk --first-aligned-in-largest "$1" | tail -n1)
     fi
     END=$(sgdisk --end-of-largest "$1" | tail -n 1)
     local gpt_part_size=''

     if [ -n "$SFDISKSIZE" ]; then
       gpt_part_size="+${SFDISKSIZE}M"
     fi

     local gpt_part_type="${SFDISKTYPE}00"

     if [ "$i" -eq "$PART_COUNT" ]; then
       local bios_grub_start=$((1048576/SECTORSIZE))
       echo "Creating BIOS_GRUB partition" | debugoutput
       sgdisk --new "$i":"$bios_grub_start":+1M -t "$i":EF02 "$1" 2>&1 | debugoutput
     else
       if [ -z "$SFDISKSIZE" ] && [ "$i" -gt 1 ]; then
         sgdisk --largest-new "$i" -t "$i":"$gpt_part_type" "$1" | debugoutput
       else
         sgdisk --new "$i":"$START":"$gpt_part_size" -t "$i":"$gpt_part_type" "$1" | debugoutput
       fi
     fi

     make_fstab_entry "$1" "$i" "${PART_MOUNT[$i]}" "${PART_FS[$i]}"

   else
     # part without GPT
     START=$((1048576/SECTORSIZE))

     TYPE="primary"
     PCOUNT="$i"

     if [ "$i" -gt "1" ]; then
       START=$(sgdisk --first-aligned-in-largest "$1" | tail -n1)
     fi

     # determine the end sector of the partition
     END=$(get_end_of_partition "$1" "$START" "$i")

     if [ "$i" -eq "4" ]; then
       TYPE="extended"
       END="$(get_end_of_extended "$1")"

       # create the extended partition
       echo "create partition: parted -s $1 mkpart $TYPE ${START}s ${END}s" | debugoutput
       OUTPUT="$(parted -s "$1" mkpart "$TYPE" "${START}"s "${END}"s)"
       if [ -n "$OUTPUT" ]; then
          echo "$OUTPUT" | debugoutput
       fi

       PCOUNT=$((PCOUNT+1))

       TYPE="logical"
       START=$((START + (1048576 / SECTORSIZE) ))

       END=$(get_end_of_partition "$1" "$START" "$i")
     fi

     if [  "$i" -gt "4" ]; then
       TYPE="logical"
     fi

     # create partitions as ext3 which results in type 83
     local FSTYPE="ext3"
     if [ "${PART_FS[$i]}" = "swap" ]; then
       FSTYPE="linux-swap"
     fi

     echo "create partition: parted -s $1 mkpart $TYPE $FSTYPE ${START}s ${END}s" | debugoutput
     OUTPUT="$(parted -s "$1" mkpart "$TYPE" "$FSTYPE" "${START}"s "${END}"s)"

     if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT" | debugoutput
     fi

     if [ "${PART_MOUNT[$i]}" = "lvm" ]; then
       parted -s "$1" set $PCOUNT lvm on
     fi


     if [ "$SWRAID" = "1" ]; then
       parted -s "$1" set $PCOUNT raid on
     fi


     if [ "$PART_COUNT" -ge "4" ] && [ "$i" -ge "4" ]; then
       make_fstab_entry "$1" "$((i+1))" "${PART_MOUNT[$i]}" "${PART_FS[$i]}"
     else
       make_fstab_entry "$1" "$i" "${PART_MOUNT[$i]}" "${PART_FS[$i]}"
     fi
   fi

  done

  # we make sure in get_end_of_partition that the all msdos partitions end at
  # 1MiB before the end of the disk, so the following is not needed anymore

#  if [ "$GPT" != "1" ]; then
#    # resize last partition so that we have 128 kb free
#    echo "resize last partition for mdadm" | debugoutput
#    LAST_PART_START="$(parted -s $1 unit s print | tail -n 2 | head -n 1 | awk '{print$2}' | rev | cut -c 2- | rev)"
#    LAST_PART_END="$(parted -s $1 unit s print | tail -n 2 | head -n 1 | awk '{print$3}' |rev | cut -c 2- | rev)"
#    DISK_SIZE_SECTORS="$(parted -s $1 unit s print | grep Disk | awk '{print$3}' | rev | cut -c 2- | rev)"

#    SECTOR_DIFF=$((DISK_SIZE_SECTORS-LAST_PART_END))

#    if [ "$SWRAID" = "1" ]; then
#      if [ "$SECTOR_DIFF" -lt "250" ]; then
#       part_end_diff=$((250-SECTOR_DIFF))
#       NEW_LAST_PART_END=$((LAST_PART_END-part_end_diff))

#        parted -s $1 mkfs $PART_COUNT linux-swap >/dev/null 2>/tmp/$$.tmp
#        parted -s $1 unit s resize ${PART_COUNT} ${LAST_PART_START} ${NEW_LAST_PART_END} >/dev/null 2>/tmp/$$.tmp
#      fi
#      cat /tmp/$$.tmp | debugoutput
#    fi
#  fi

  #reread partition table after some break
  echo "reread partition table after 5 seconds" | debugoutput
  sleep 5
  hdparm -z "$1" >/dev/null 2>&1

  echo "deactivate all dm-devices with dmraid and dmsetup" | debugoutput
  mkdir -p /run/lock
  dmraid -a no 2>&1 | debugoutput
  dmsetup remove_all 2>&1 | debugoutput

 return "$EXITCODE"
 fi
}

# create fstab entries
# make_fstab_entry "DRIVE" "NUMBER" "MOUNTPOINT" "FILESYSTEM"
make_fstab_entry() {
  if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]; then
    local entry=""
    local p; p="$(echo "$1" | grep nvme)"
    [ -n "$p" ] && p='p'

    if [ "$4" = "swap" ] ; then
      entry="$1$p$2 none swap sw 0 0"
    elif [ "$3" = "lvm" ] ; then
      entry="# $1$2  belongs to LVM volume group '$4'"
    else
      if [ "$SYSTYPE" = "vServer" ] && [ "$4" = 'ext4' ]; then
        entry="$1$p$2 $3 $4 defaults,discard 0 0"
      else
        entry="$1$p$2 $3 $4 defaults 0 0"
      fi
    fi

    echo "$entry" >> "$FOLD/fstab"

    if [ "$3" = "/" ]; then
      SYSTEMREALROOTDEVICE="$1$p$2"
      export SYSTEMREALROOTDEVICE
    if [ -z "$SYSTEMREALBOOTDEVICE" ]; then
      SYSTEMREALBOOTDEVICE="$1$p$2"
    fi
  fi
  if [ "$3" = "/boot" ]; then
    SYSTEMREALBOOTDEVICE="$1$p$2"
  fi

 fi
}

next_partnum() {
  num="$1"
  if [ "$GPT" != "1" ]; then
    if [ "$num" -lt 3 ] ; then
      echo $((num+1)) ; return
    else
      echo $((num+2))
    fi
  else
    echo $((num+1))
  fi
}


make_swraid() {
  if [ -n "$1" ] ; then
    fstab=$1

    dmsetup remove_all

    count=0
    PARTNUM=0
    LASTDRIVE="$(eval echo \$DRIVE${COUNT_DRIVES})"
    SEDHDD="$(echo "$LASTDRIVE" | sed 's/\//\\\//g')"

    LILOEXTRABOOT="raid-extra-boot="
    for i in $(seq 1 $COUNT_DRIVES) ; do
      TARGETDISK="$(eval echo \$DRIVE"${i}")"
      LILOEXTRABOOT="$LILOEXTRABOOT,$TARGETDISK"
    done

    mv "$fstab" "$fstab".tmp

    debug "# create software raid array(s)"
    local metadata="--metadata=1.2"
    local metadata_boot=$metadata

    #centos 6.x metadata
    if [ "$IAM" = "centos" ] && [ "$IMG_VERSION" -lt 70 ]; then
      if [ "$IMG_VERSION" -ge 60 ]; then
        metadata="--metadata=1.0"
        metadata_boot="--metadata=0.90"
      else
        metadata="--metadata=0.90"
      fi
    fi

    # we always use /dev/mdX in Ubuntu 10.04. In all other distributions we
    # use it when we have Metadata format 0.90 in Ubuntu 11.04 we have to use
    # /boot with metadata format 0.90
    if [ "$IAM" == "ubuntu" ] && [ "$IMG_VERSION" -lt 1204 ]; then
      if [ "$IMG_VERSION" -le 1004 ]; then
        metadata="--metadata=0.90"
      else
        metadata_boot="--metadata=0.90"
      fi
    fi
    [ "$IAM" == "suse" ] && [ "$IMG_VERSION" -lt 123 ] && metadata="--metadata=0.90"
    while read -r line; do
      PARTNUM="$(next_partnum $count)"
      echo "Line is: \"$line\"" | debugoutput
      # shellcheck disable=SC2015
      if echo "$line" | grep -q "/boot" && [ "$metadata_boot" == "--metadata=0.90" ] || [ "$metadata" == "--metadata=0.90" ]; then
        # update fstab - replace /dev/sdaX with /dev/mdY
        echo "$line" | sed "s/$SEDHDD\\(p\\)\\?[0-9]\\+/\\/dev\\/md$count/g" >> "$fstab"
      else
        # update fstab - replace /dev/sdaX with /dev/md/Y
        echo "$line" | sed "s/$SEDHDD\\(p\\)\\?[0-9]\\+/\\/dev\\/md\\/$count/g" >> "$fstab"
      fi

      # create raid array
      if echo "$line" | grep "$LASTDRIVE" >/dev/null ; then

        local raid_device="/dev/md/$count"
        local components=""
        local n=0
        for n in $(seq 1 $COUNT_DRIVES) ; do
          TARGETDISK="$(eval echo \$DRIVE"${n}")"
          local p; p="$(echo "$TARGETDISK" | grep nvme)"
          [ -n "$p" ] && p='p'
          components="$components $TARGETDISK$p$PARTNUM"
        done

        local array_metadata="$metadata"
        local array_raidlevel="$SWRAIDLEVEL"
        local can_assume_clean=''

        # lilo and GRUB can't boot from a RAID0/5/6 or 10 partition, so make /boot always RAID1
        if echo "$line" | grep -q "/boot"; then
          array_raidlevel="1"
          array_metadata=$metadata_boot
        # make swap partiton RAID1 for all levels except RAID0
        elif echo "$line" | grep -q "swap" && [ "$SWRAIDLEVEL" != "0" ]; then
          array_raidlevel="1"
        fi

        if [ "$RAID_ASSUME_CLEAN" = "1" ]; then
          if [ "$SWRAIDLEVEL" = "1" ] || [ "$SWRAIDLEVEL" = "10" ] || [ "$SWRAIDLEVEL" = "6" ]; then
            can_assume_clean='--assume-clean'
          fi
        fi
        debug "Array RAID Level is: '$array_raidlevel' - $can_assume_clean"
        debug "Array metadata is: '$array_metadata'"

        # workaround: the 2>&1 redirect is valid syntax in shellcheck 0.4.3-3, but not in the older version which is currently used by travis
        # shellcheck disable=SC2069
        yes | mdadm -q -C "$raid_device" -l"$array_raidlevel" -n"$n" "$array_metadata" "$can_assume_clean" "$components" 2>&1 >/dev/null | debugoutput ; EXITCODE=$?

        count="$((count+1))"
       fi

    done < "$fstab".tmp

  fi
  return 0
}


make_lvm() {
  if [ "$1" ] && [ "$2" ] ; then
    fstab=$1
    disk1=$2

    # get device names for PVs depending if we use swraid or not
    inc_dev=1
    if [ $SWRAID -eq 1 ]; then
      for md in /dev/md/[0-9]*; do
        dev[$inc_dev]="$md"
        (( inc_dev = inc_dev + 1 ))
      done
    else
      # shellcheck disable=SC2012
      for inc_dev in $(seq 1 "$(ls -1 "${DRIVE1}"[0-9]* | wc -l)") ; do
        dev[$inc_dev]="$disk1$(next_partnum $((inc_dev-1)))"
      done
    fi

    # remove all Logical Volumes and Volume Groups
    debug "# Removing all Logical Volumes and Volume Groups"
    # shellcheck disable=SC2034
    vgs --noheadings 2> /dev/null | while read -r vg pvs; do
      lvremove -f "$vg" 2>&1 | debugoutput
      vgremove -f "$vg" 2>&1 | debugoutput
    done

    # remove all Physical Volumes
    debug "# Removing all Physical Volumes"
    pvs --noheadings 2>/dev/null | while read -r pv vg; do
      pvremove -ff "$pv" 2>&1 | debugoutput
    done

    # create PVs
    for i in $(seq 1 "$LVM_VG_COUNT") ; do
      pv=${dev[${LVM_VG_PART[${i}]}]}
      debug "# Creating PV $pv"
      pvcreate -ff "$pv" 2>&1 | debugoutput
    done

    # create VGs
    for i in $(seq 1 "$LVM_VG_COUNT") ; do
      vg=${LVM_VG_NAME[$i]}
      pv=${dev[${LVM_VG_PART[${i}]}]}

      # extend the VG if a VG with the same name already exists
      if vgs --noheadings 2>/dev/null | grep -q "$vg"; then
        debug "# Extending VG $vg with PV $pv"
        vgextend "$vg" "$pv" 2>&1 | debugoutput
      else
        debug "# Creating VG $vg with PV $pv"
        [ "$vg" ] && rm -rf "/dev/${vg:?}" 2>&1 | debugoutput
        vgcreate "$vg" "$pv" 2>&1 | debugoutput
      fi
    done

    # create LVs
    for i in $(seq 1 "$LVM_LV_COUNT") ; do
      lv=${LVM_LV_NAME[$i]}
      vg=${LVM_LV_VG[$i]}
      size=${LVM_LV_SIZE[$i]}
      vg_last_lv=''
      free=''

      # get last lv of vg
      for i_lv in $(seq 1 "$LVM_LV_COUNT") ; do
        if [ "${LVM_LV_VG[$i_lv]}" = "$vg" ] ; then
          vg_last_lv=$i_lv
        fi
      done

      # calculate free space of vg
      free="$(vgs --units m "$vg" | tail -n1 | awk '{ print $7 }' | rev | cut -b 5- | rev)"

      # calculate size of all lv
      # or resize last lv if not enough space in vg
      # (has to be recalculated because of lvm metadata)
      if [ "$size" = "all" ] ; then
        size="$(translate_unit "$free")"
      else
        if [ "$i" -eq "$vg_last_lv" ] && [ "$free" -lt "$size" ] ; then
          size="$(translate_unit "$free")"
          debug "# Resize LV $lv in VG $vg to $size MiB because of not enough free space"
        fi
      fi

      debug "# Creating LV $vg/$lv ($size MiB)"
      lvcreate --name "$lv" --size "$size" "$vg" 2>&1 | debugoutput
      test $? -eq 0 || return 1
    done

    # create fstab-entries
    for i in $(seq 1 "$LVM_LV_COUNT") ; do
      {
        echo -n "/dev/${LVM_LV_VG[$i]}/${LVM_LV_NAME[$i]}  "
        echo -n "${LVM_LV_MOUNT[$i]}  ${LVM_LV_FS[$i]}  "
        echo    "defaults 0 0"
      } >> "$fstab"
    done

  else
    debug "parameters incorrect for make_lvm()"
    echo "params incorrect for make_lvm" ; return 1
  fi
  return 0
}


format_partitions() {
  if [ "$1" ] && [ "$2" ]; then
    DEV="$1"
    FS="$2"
    EXITCODE=0

    # reread partition table after some break
    sleep 4
    hdparm -z "$1" >/dev/null 2>/dev/null

    if [ -b "$DEV" ] ; then
      debug "# formatting  $DEV  with  $FS"
      if [ "$FS" = "swap" ]; then
        # format swap partition with dd first because mkswap
        # doesnt overwrite sw-raid information!
        mkfs -t xfs -f "$DEV" 2>&1 | debugoutput
        dd if=/dev/zero of="$DEV" bs=256 count=8 2>&1 | debugoutput
        # then write swap information
        mkswap "$DEV" 2>&1 | debugoutput ; EXITCODE=$?
      elif [ "$FS" = "ext2" ] || [ "$FS" = "ext3" ] || [ "$FS" = "ext4" ]; then
        if [ "$IAM" == "centos" ] && [ "$IMG_VERSION" -lt 70 ]; then
          mkfs -t "$FS" -O '^64bit' -O '^metadata_csum' -q "$DEV" 2>&1 | debugoutput ; EXITCODE=$?
        else
          mkfs -t "$FS" -q "$DEV" 2>&1 | debugoutput ; EXITCODE=$?
        fi
      elif [ "$FS" = "btrfs" ]; then
        wipefs "$DEV" | debugoutput
        mkfs -t "$FS" "$DEV" 2>&1 | debugoutput ; EXITCODE=$?
      else
        # workaround: the 2>&1 redirect is valid syntax in shellcheck 0.4.3-3, but not in the older version which is currently used by travis
        # shellcheck disable=SC2069
        mkfs -t "$FS" -q -f "$DEV" 2>&1 >/dev/null | debugoutput ; EXITCODE=$?
      fi
    else
      debug "! this is no valid block device:  $DEV"
      debug "content from ls /dev/[hmsv]d*: $(ls /dev/[hmsv]d*)"
    fi
    return "$EXITCODE"
  fi
}

mount_partitions() {
  if [ "$1" ] && [ "$2" ]; then
    fstab="$1"
    basedir="$2"

    ROOTDEVICE="$(grep " / " "$fstab" | cut -d " " -f 1)"
    SYSTEMROOTDEVICE="$ROOTDEVICE"
    SYSTEMBOOTDEVICE="$SYSTEMROOTDEVICE"

    mount "$ROOTDEVICE" "$basedir" 2>&1 | debugoutput ; EXITCODE=$?
    [ "$EXITCODE" -ne "0" ] && return 1

    mkdir -p "$basedir"/proc 2>&1 | debugoutput
    mount -o bind /proc "$basedir"/proc 2>&1 | debugoutput ; EXITCODE=$?
    [ "$EXITCODE" -ne "0" ] && return 1

    mkdir -p "$basedir"/dev 2>&1 | debugoutput
    mount -o bind /dev "$basedir"/dev 2>&1 | debugoutput ; EXITCODE=$?
    [ "$EXITCODE" -ne "0" ] && return 1

    mkdir -p "$basedir"/dev/pts 2>&1 | debugoutput
    mount -o bind /dev/pts "$basedir"/dev/pts 2>&1 | debugoutput ; EXITCODE=$?
    [ "$EXITCODE" -ne "0" ] && return 1

    # bind /dev/shm too
    # wheezy rescue: /dev/shm links to /run/shm
    if [ -L "$basedir"/dev/shm ] ; then
      shmlink="$(readlink "$basedir"/dev/shm)"
      mkdir -p "${basedir}${shmlink}" 2>&1 | debugoutput
      if [ -e "$shmlink" ] ; then
        mount -o bind "$shmlink" "${basedir}${shmlink}" 2>&1 | debugoutput ; EXITCODE=$?
      else
        mount -o bind /dev/shm "${basedir}${shmlink}" 2>&1 | debugoutput ; EXITCODE=$?
      fi
      [ "$EXITCODE" -ne "0" ] && return 1
    else
      mkdir -p "$basedir"/dev/shm 2>&1 | debugoutput
      mount -o bind /dev/shm "$basedir"/dev/shm 2>&1 | debugoutput ; EXITCODE=$?
      [ "$EXITCODE" -ne "0" ] && return 1
    fi

    mkdir -p "$basedir"/sys 2>&1 | debugoutput
    mount -o bind /sys "$basedir"/sys 2>&1 | debugoutput ; EXITCODE=$?
    [ "$EXITCODE" -ne "0" ] && return 1

    grep -v ' / \|swap' "$fstab" | grep "^/dev/" > "$fstab".tmp

    while read -r line ; do
      DEVICE="$(echo "$line" | cut -d " " -f 1)"
      MOUNTPOINT="$(echo "$line" | cut -d " " -f 2)"
      mkdir -p "$basedir$MOUNTPOINT" 2>&1 | debugoutput

      # create lock and run dir for ubuntu if /var has its own filesystem
      # otherwise network does not come up - see ticket 2008012610009793
      if [ "$MOUNTPOINT" = "/var" ] && [ "$IAM" = "ubuntu" ]; then
        # this is expected
        # shellcheck disable=SC2174
        mkdir -p -m 1777 "$basedir/var/lock" 2>&1 | debugoutput
        # shellcheck disable=SC2174
        mkdir -p -m 1777 "$basedir/var/run" 2>&1 | debugoutput
      fi

      # mount it
      mount "$DEVICE" "$basedir$MOUNTPOINT" 2>&1 | debugoutput || return 1
      if [ "$MOUNTPOINT" = "/boot" ]; then
        SYSTEMBOOTDEVICE="$DEVICE"
      fi
    done < "$fstab".tmp

    if [ "$SWRAID" -eq "1" ]; then
      SYSTEMDEVICE="$SYSTEMBOOTDEVICE"
    fi
    mkdir -p "$basedir"/sys
    return 0
  fi
}

# set EXTRACTFROM for next functions
# params: IMAGE_PATH, IMAGE_PATH_TYPE, IMAGE_FILE
get_image_info() {
  if [ "$1" ] && [ "$2" ] && [ "$3" ]; then
    case $2 in
      nfs)
        mount -t "nfs" "$1" "$FOLD/nfs" 2>&1 | debugoutput ; EXITCODE=$?
        if [ "$EXITCODE" -ne "0" ] || [ ! -e "$FOLD/nfs/$3" ]; then
          return 1
        else
          EXTRACTFROM="$FOLD/nfs/$3"
          if [ -e "${EXTRACTFROM}.sig" ] ; then
            IMAGE_SIGN="${EXTRACTFROM}.sig"
          fi
          if [ -e "${1}public-key.asc" ] ; then
            IMAGE_PUBKEY="${1}public-key.asc"
          fi
        fi
       ;;
      http)
        mkdir "$FOLD"/keys/ 2>&1
        cd "$FOLD"/keys/ || exit
        # no exitcode, because if not found hetzner-pubkey will be used
        wget -q --no-check-certificate "${1}public-key.asc" 2>&1 | debugoutput || true
        if [ "$EXITCODE" -eq "0" ]; then
          IMAGE_PUBKEY="$FOLD/keys/public-key.asc"
        fi
        cd - >/dev/null || exit
        # download image with get_image_url later after mounting hdd
        EXITCODE=0;
       ;;
      local)
        if [ -e "$1$3" ]; then
          EXTRACTFROM="$1$3"
          if [ -e "${EXTRACTFROM}.sig" ] ; then
            IMAGE_SIGN="${EXTRACTFROM}.sig"
          elif [ -e "${1}sig/${3}.sig" ] ; then
            IMAGE_SIGN="${1}sig/${3}.sig"
          fi
          if [ -e "${1}public-key.asc" ] ; then
            IMAGE_PUBKEY="${1}public-key.asc"
          fi
        else
          return 1
        fi
       ;;
      *)return 1;;
    esac

    if [ "$EXITCODE" -eq "0" ]; then
      return 0
    else
      return 1
    fi
  fi
}

# download image via http/ftp
get_image_url() {
  # load image to mounted hdd
  cd "$FOLD"/hdd/ || exit ; wget -q --no-check-certificate "$1$2" 2>&1 | debugoutput ; EXITCODE=$?; cd - || exit >/dev/null
  if [ "$EXITCODE" -eq "0" ]; then
    EXTRACTFROM="$FOLD/hdd/$2"
    # search for sign file and download
    cd "$FOLD"/keys/ || exit ; wget -q --no-check-certificate "$1$2.sig" 2>&1 | debugoutput ; EXITCODE=$?; cd - || exit >/dev/null
    if [ "$EXITCODE" -eq "0" ]; then
      IMAGE_SIGN="$FOLD/keys/$2.sig"
    fi
    return 0
  else
    return 1
  fi
}

# import the gpg public key for imagevalidation
import_imagekey() {
  local PUBKEY=""
  # check if pubkey is given by the customer
  if [ -n "$IMAGE_PUBKEY" ] && [ -e "$IMAGE_PUBKEY" ] ; then
    PUBKEY="$IMAGE_PUBKEY"
  elif [ -e "$COMPANY_PUBKEY" ] ; then
    # if no special pubkey given, use the standard company key
    echo "Using standard $COMPANY pubkey: $COMPANY_PUBKEY" | debugoutput
    PUBKEY="$COMPANY_PUBKEY"
  fi
  if [ -n "$PUBKEY" ] ; then
    # import public key
    gpg --batch --import "$PUBKEY" 2>&1 | debugoutput ; EXITCODE=$?

    if [ "$EXITCODE" -eq "0" ]; then
      IMAGE_PUBKEY_IMPORTED="yes"
      return 0
    else
      return 1
    fi
  fi
  echo "No public key found" | debugoutput
  return 2
}

# validate image with detached signature
validate_image() {
  if [ "$IMAGE_PUBKEY_IMPORTED" = "yes" ] ; then
    if [ -n "$IMAGE_SIGN" ] ; then
      # verify image with given pubkey and signature
      gpg --batch --verify "$IMAGE_SIGN" "$EXTRACTFROM" 2>&1 | debugoutput ; EXITCODE=$?
      if [ "$EXITCODE" -eq "0" ]; then
        # image file valid
        return 0
      else
        # image file not valid
        return 1
      fi
    else
      # no detached sign found
      return 2
    fi
  else
    # no public key found
    return 3
  fi
}

# extract image file to hdd
extract_image() {
  local COMPRESSION=""
  if [ "$1" ] && [ "$2" ]; then
    case "$2" in
      tar)
        COMPRESSION=""
       ;;
      tgz)
        COMPRESSION="-z"
       ;;
      tbz)
        COMPRESSION="-j"
       ;;
      txz)
        COMPRESSION="-J"
       ;;
      *)return 1;;
    esac

    # extract image with given compression
    if [ "$TAR" = "tar" ] || [ ! -x /usr/bin/bsdtar ]; then
      tar --anchored --numeric-owner --exclude "sys" --exclude "proc" --exclude "dev" $COMPRESSION -x -f "$EXTRACTFROM" -C "$FOLD/hdd/" 2>&1 | debugoutput ; EXITCODE=$?
    else
      bsdtar --numeric-owner --exclude '^sys' --exclude '^proc' --exclude '^dev' "$COMPRESSION" -x -f "$EXTRACTFROM" -C "$FOLD/hdd/" 2>&1 | debugoutput ; EXITCODE=$?
    fi
    # remove image after extraction if we got it via wget (http(s)/ftp)
    [ "$1" = "http" ] && rm -f "$EXTRACTFROM"

    if [ "$EXITCODE" -eq "0" ]; then
      cp -r "$FOLD/fstab" "$FOLD/hdd/etc/fstab" 2>&1 | debugoutput
      return 0
    else
      return 1
    fi

  fi
}

function get_active_eth_dev() {
  local nic=""
  for nic in /sys/class/net/*; do
    # remove path from ethX so we only have "ethX"
    [[ $nic =~ ^(lo)$ ]] && continue
    nic=${nic##*/}
    #test if the interface has a ipv4 adress
    iptest=$(ip addr show dev "$nic" | grep "$nic"$ | awk '{print $2}')
    if [ -n "$iptest" ]; then
      ETHDEV="$nic"
      break
    fi
  done
}

# gather_network_information "$ETH"
gather_network_information() {
  # requires ipcalc from centos/rhel
  # removed INETADDR which was ip.ip.ip.ip/CIDR - only used in arch.sh
  # removed CIDR- only used in arch.sh
  HWADDR=$(ifdata -ph "$ETHDEV" | tr "[:upper:]" "[:lower:]")
  IPADDR=$(ifdata -pa "$ETHDEV")
  # check for a RFC6598 address, and don't set the v4 vars if we have one
  local FIRST; FIRST=$(echo "$IPADDR" | cut -d. -f1)
  if [ "$FIRST" = "100" ]; then
    debug "not configuring RFC6598 address"
    V6ONLY=1
  else
    # subnetmask calculation for rhel ipcalc
    export SUBNETMASK; SUBNETMASK=$(ifdata -pn "$ETHDEV")
    export BROADCAST; BROADCAST=$(ifdata -pb "$ETHDEV")
    export GATEWAY; GATEWAY=$(ip -4 route show default | awk '{print $3; exit}')
    export NETWORK; NETWORK=$(ifdata -pN "$ETHDEV")
  fi

  # ipv6
  # check for non-link-local ipv6
  DOIPV6=$(ip -6 addr show dev "$ETHDEV" | grep -v fe80 | grep -m1 'inet6')
  if [ -n "$DOIPV6" ]; then
    local INET6ADDR; INET6ADDR=$(ip -6 addr show dev "$ETHDEV" | grep -m1 'inet6' | awk '{print $2}')
    export IP6ADDR; IP6ADDR=$(echo "$INET6ADDR" | cut -d"/" -f1)
    export IP6PREFLEN; IP6PREFLEN=$(echo "$INET6ADDR" | cut -d'/' -f2)
    # we can get default route from here, but we could also assume fe80::1 for now
    export IP6GATEWAY; IP6GATEWAY=$(ip -6 route show default |  awk '{print $3}')
  else
    if [ "$V6ONLY" -eq 1 ]; then
      debug "no valid IPv6 adress, but v6 only because of RFC6598 IPv4 address"
      # we need to do this more graceful
      exit 1
    fi
  fi
}

# setup_network_config "ETH" "HWADDR" "IPADDR" "BROADCAST" "SUBNETMASK" "GATEWAY" "NETWORK"
setup_network_config() {
  if [ "$1" ] && [ "$2" ] && [ "$3" ] && [ "$4" ] && [ "$5" ] && [ "$6" ] && [ "$7" ]; then
    return 1
  fi
}

# setup_network_config_template "ETH" "HWADDR" "IPADDR" "BROADCAST" "SUBNETMASK" "GATEWAY" "NETWORK" "IPADDR6" "NETMASK6" "GATEWAY6"
setup_network_config_template() {
  local eth="$1"
  local hwaddr="$2"

  local ipaddr="$3"
  local broadcast="$4"
  local netmask="$5"
  local gateway="$6"
  local network="$7"

  local ipaddr6="$8"
  local netmask6="$9"
  local gateway6="${10}"

  # copy network template of distro to "$FOLD"
  local tpl_net_load="$SCRIPTPATH/templates/network/$IAM.tpl"
  local tpl_net="$FOLD/network"
  cp "$tpl_net_load" "$tpl_net"

  # copy udev template of distro to "$FOLD"
  local tpl_udev_load="$SCRIPTPATH/templates/network/udev.tpl"
  local tpl_udev="$FOLD/udev"
  cp "$tpl_udev_load" "$tpl_udev"

  # replace necessary network information
  if [ -n "$eth" ] && [ -n "$hwaddr" ] ; then
    # replace network information in udev template
    template_replace "ETH" "$eth" "$tpl_udev"
    template_replace "HWADDR" "$hwaddr" "$tpl_udev"

    # replace network information in network template
    if [ -n "$ipaddr" ] && [ -n "$broadcast" ] && [ -n "$netmask" ] && [ -n "$gateway" ] && [ -n "$network" ] ; then
      template_replace "ETH" "$eth" "$tpl_net"
      template_replace "HWADDR" "$hwaddr" "$tpl_net"
      template_replace "IPADDR" "$ipaddr" "$tpl_net"
      template_replace "BROADCAST" "$broadcast" "$tpl_net"
      template_replace "NETMASK" "$netmask" "$tpl_net"
      template_replace "GATEWAY" "$gateway" "$tpl_net"
      template_replace "NETWORK" "$network" "$tpl_net"

      template_replace "GROUP_IP4" "$tpl_net"
    else
      template_replace "GROUP_IP4" "$tpl_net" "yes"
    fi

    # replace ipv6 information in network template if given
    if [ -n "$ipaddr6" ] && [ -n "$netmask6" ] && [ -n "$gateway6" ] ; then
      template_replace "IPADDR6" "$ipaddr6" "$tpl_net"
      template_replace "NETMASK6" "$netmask6" "$tpl_net"
      template_replace "GATEWAY6" "$gateway6" "$tpl_net"

      template_replace "GROUP_IP6" "$tpl_net"
    else
      template_replace "GROUP_IP6" "$tpl_net" "yes"
    fi
  fi

  # replace duplex settings in network template if given
  if ! isNegotiated && ! isVServer; then
    template_replace "GROUP_DUPLEX" "$tpl_net"
  else
    template_replace "GROUP_DUPLEX" "$tpl_net" "yes"
  fi

  # get specified extra files from template
  local tpl_files; tpl_files=$(grep -e "%%% FILE_.*_START %%%" "$tpl_net" | sed 's/%%% FILE_\(.*\)_START %%%/\1/g')
  for file in $tpl_files ; do
    local filename; filename="$FOLD/network_$(echo "$file" | tr "[:upper:]" "[:lower:]")"
    # get content of extra file
    local content; content="$(sed -n "/%%% FILE_${file}_START %%%/,/%%% FILE_${file}_END %%%/p" "$tpl_net")"

    # create extra file
    echo "$content" > "$filename"
    # remove extra file from template
    template_replace "FILE_${file}" "$tpl_net" "yes"
    # remove file patterns from extra file
    template_replace "FILE_${file}" "$filename"
  done

  return 0
}

# template_replace
# variant 1: template_replace "SEARCH" "FILE"
#             - this remove lines with SEARCH
#             - also removes both GROUP lines if specified
# variant 2: template_replace "SEARCH" "REPLACE" "FILE"
#             - replace SEARCH with REPLACE
# variant 3: template_replace "SEARCH" "FILE" "yes"
#             - replace whole block specified
function template_replace() {
  local search="$1"
  if [ $# -eq 2 ] ; then
    # if just 2 params set, remove lines
    local file="$2"
    if echo "$search" | grep -q -e "GROUP|FILE"; then
      # if search contains GROUP or FILE, remove both group lines
      search="${search}_\\(START\\|\\END\\)"
    fi
    sed -i "/%%% $search %%%/d" "$file"
  elif [ $# -eq 3 ] ; then
    if [ "$3" = "yes" ] ; then
      # if 3rd param set yes, remove group including content
      local file="$2"
      sed -i "/%%% ${search}_START %%%/,/%%% ${search}_END %%%/d" "$file"
    else
      # replace pattern with content
      local replace="$2"
      local file="$3"
      sed -i "s/%%% $search %%%/$replace/g" "$file"
    fi
  fi

  return 0
}

#
# generate_resolvconf
#
# Generate /etc/resolv.conf by adding the nameservers defined in the array
# "$NAMESERVER" in a random order.
#
generate_resolvconf() {
  if [ "$IAM" = "suse" ] && [ "$IMG_VERSION" -ge 122 ]; then
    # disable netconfig of DNS servers in YaST config file
    sed -i -e \
      "s/^NETCONFIG_DNS_POLICY=\".*\"/NETCONFIG_DNS_POLICY=\"\"/" \
      "$FOLD/hdd/etc/sysconfig/network/config"

#    if [ "$V6ONLY" -eq 1 ]; then
#      debug "# skipping IPv4 DNS resolvers"
#    else
#      nameservers=$(echo ${NAMESERVER[@]} | sed -e "s/\./\\\./g")
#    fi
#    if [ -n "$DOIPV6" ]; then
#      # a bit pointless as netconfig will only add the first three DNS resolvers
#      nameservers=$(echo -n "$nameservers "; echo ${DNSRESOLVER_V6[@]})
#    fi
#
#    debug "#DNS $nameservers"
#    sed -i -e \
#      "s/^NETCONFIG_DNS_STATIC_SERVERS=\".*\"/NETCONFIG_DNS_STATIC_SERVERS=\"$nameservers\"/" \
#      "$FOLD"/hdd/etc/sysconfig/network/config
#    execute_chroot_command "netconfig update -f"
  fi
#  else
  NAMESERVERFILE="$FOLD/hdd/etc/resolv.conf"
  SYSTEMD_RESOLV_CONF="$FOLD/hdd/etc/systemd/resolved.conf"
  if [ "$IAM" = "ubuntu" ] && [ "$IMG_VERSION" -ge 1604 ] && \
    [ -L "$NAMESERVERFILE" ] && [ -e "$SYSTEMD_RESOLV_CONF" ]; then
    if [ "$V6ONLY" -eq 1 ]; then
      debug "# skipping IPv4 DNS resolvers"
      sed -i "s/^#DNS=/DNS=${DNSRESOLVER_V6[*]}/g" "$SYSTEMD_RESOLV_CONF"
    elif [ -n "$DOIPV6" ]; then
      sed -i "s/^#DNS=/DNS=${NAMESERVER[*]}\ ${DNSRESOLVER_V6[*]}/g" "$SYSTEMD_RESOLV_CONF"
    else
      sed -i "s/^#DNS=/DNS=${NAMESERVER[*]}/g" "$SYSTEMD_RESOLV_CONF"
    fi

  else
    echo "### $COMPANY installimage" > "$NAMESERVERFILE"
    echo "# nameserver config" >> "$NAMESERVERFILE"

    # IPV4
    if [ "$V6ONLY" -eq 1 ]; then
      debug "# skipping IPv4 DNS resolvers"
    else
      for index in $(shuf --input-range=0-$(( ${#NAMESERVER[*]} - 1 )) | tr '\n' ' ') ; do
        echo "nameserver ${NAMESERVER[$index]}" >> "$NAMESERVERFILE"
      done
    fi

    # IPv6
    if [ -n "$DOIPV6" ]; then
      for index in $(shuf --input-range=0-$(( ${#DNSRESOLVER_V6[*]} - 1 )) | tr '\n' ' ') ; do
        echo "nameserver ${DNSRESOLVER_V6[$index]}" >> "$NAMESERVERFILE"
      done
    fi
  fi

  return 0
}

# set_hostname "HOSTNAME"
set_hostname() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    local sethostname="$1"

    local mailname="$sethostname"
    local hostnamefile="$FOLD/hdd/etc/hostname"
    local mailnamefile="$FOLD/hdd/etc/mailname"
    local machinefile="$FOLD/hdd/etc/machine-id"
    local networkfile="$FOLD/hdd/etc/sysconfig/network"
    local hostsfile="$FOLD/hdd/etc/hosts"

    [ -f "$FOLD/hdd/etc/HOSTNAME" ] && hostnamefile="$FOLD/hdd/etc/HOSTNAME"

    hostname "$sethostname"
    execute_chroot_command "hostname $sethostname"

    check_fqdn "$sethostname"
    [ $? -eq 1 ] && shortname="$sethostname" || shortname="$(hostname -s )"

    if [ -f "$hostnamefile" ] || [ "$IAM" = "arch" ]; then
      echo "$shortname" > "$hostnamefile"
      debug "# set new hostname '$shortname' in $hostnamefile"
    fi

    check_fqdn "$mailname"
    [ $? -eq 1 ] && mailname="$(create_hostname "$IPADDR")"
    if [ -f "$mailnamefile" ]; then
      echo "$mailname" > "$mailnamefile"
      debug "# set new mailname '$mailname' in $mailnamefile"
    fi

    if [ -f "$machinefile" ]; then
      # clear machine-id from install (will be regen upon first boot)
      echo >  "$machinefile"
    fi

    if [ -f "$networkfile" ]; then
      debug "# set new hostname '$shortname' in $networkfile"
      echo "HOSTNAME=$shortname" >> "$networkfile" 2>> "$DEBUGFILE"
    fi

    local fqdn_name="$sethostname"
    [ "$sethostname" = "$shortname" ] && fqdn_name=''
    {
      echo "### $COMPANY installimage"
      echo "# nameserver config"
      echo "# IPv4"
      echo "127.0.0.1 localhost.localdomain localhost"
      echo "$2 $fqdn_name $shortname"
      echo "#"
      echo "# IPv6"
      echo "::1     ip6-localhost ip6-loopback"
      echo "fe00::0 ip6-localnet"
      echo "ff00::0 ip6-mcastprefix"
      echo "ff02::1 ip6-allnodes"
      echo "ff02::2 ip6-allrouters"
      echo "ff02::3 ip6-allhosts"
    } > "$hostsfile"
    if [ "$3" ]; then
      if [ "$PROXMOX" = 'true' ] && [ "$PROXMOX_VERSION" = '3' ]; then
        debug "not adding ipv6 fqdn to hosts for Proxmox3"
      else
        echo "$3 $fqdn_name $shortname" >> "$hostsfile"
      fi
    fi

    return 0
  else
    return 1
  fi
}

# generate_hosts "IP"
generate_hosts() {
  if [ -n "$1" ]; then
    HOSTSFILE="$FOLD/hdd/etc/hosts"
    [ -f "$FOLD/hdd/etc/hostname" ] && HOSTNAMEFILE="$FOLD/hdd/etc/hostname"
    [ -f "$FOLD/hdd/etc/HOSTNAME" ] && HOSTNAMEFILE="$FOLD/hdd/etc/HOSTNAME"
    if [ "$HOSTNAMEFILE" = "" ]; then
      if [ "$NEWHOSTNAME" ]; then
        HOSTNAME="$NEWHOSTNAME";
      else
        HOSTNAME="$IMAGENAME";
      fi
    else
      FULLHOSTNAME="$(cat "$HOSTNAMEFILE")"
      HOSTNAME="$(cut -d. -f1 "$HOSTNAMEFILE")";
      [ "$FULLHOSTNAME" = "$HOSTNAME" ] && FULLHOSTNAME=""
    fi
    {
      echo "### Hetzner Online GmbH installimage"
      echo "# nameserver config"
      echo "# IPv4"
      echo "127.0.0.1 localhost.localdomain localhost"
      echo "$1 $FULLHOSTNAME $HOSTNAME"
      echo "#"
      echo "# IPv6"
      echo "::1     ip6-localhost ip6-loopback"
      echo "fe00::0 ip6-localnet"
      echo "ff00::0 ip6-mcastprefix"
      echo "ff02::1 ip6-allnodes"
      echo "ff02::2 ip6-allrouters"
      echo "ff02::3 ip6-allhosts"
    } > "$HOSTSFILE"
    if [ "$2" ]; then
      if [ "$PROXMOX" = 'true' ] && [ "$PROXMOX_VERSION" = '3' ]; then
        debug "not adding ipv6 fqdn to hosts for Proxmox3"
      else
        echo "$2 $FULLHOSTNAME $HOSTNAME" >> "$HOSTSFILE"
      fi
    fi
  fi
  return 0
}

#  execute_chroot_command "COMMMAND"
execute_chroot_command() {
  if [ -n "$1" ]; then
    debug "# chroot_command: $1"
    chroot "$FOLD/hdd/" /bin/bash -c "$1" 2>&1 | debugoutput ; EXITCODE=$?
    return "$EXITCODE"
  fi
}

# execute chroot command but without debugoutput
execute_chroot_command_wo_debug() {
  if [ -n "$1" ]; then
    chroot "$FOLD/hdd/" /bin/bash -c "$1" 2>&1; EXITCODE=$?
    return "$EXITCODE"
  fi
}

# copy_mtab "NIL"
copy_mtab() {
  if [ -n "$1" ]; then
    if [ -L "$FOLD/hdd/etc/mtab" ]; then
      debug "mtab is already a symlink"
      return 0
    else
      execute_chroot_command "grep -v swap /etc/fstab > /etc/mtab" ; EXITCODE=$?
      return "$EXITCODE"
    fi
  fi
}


generate_new_sshkeys() {
  if [ "$1" ]; then

    if [ -f "$FOLD/hdd/etc/ssh/ssh_host_key" ]; then
      rm -f "$FOLD"/hdd/etc/ssh/ssh_host_k* 2>&1 | debugoutput
      execute_chroot_command "ssh-keygen -t rsa1 -b 1024 -f /etc/ssh/ssh_host_key -N '' >/dev/null"; EXITCODE=$?
      if [ "$EXITCODE" -ne "0" ]; then
       return "$EXITCODE"
     fi
    else
      debug "skipping rsa1 key gen"
    fi

    if [ -f "$FOLD/hdd/etc/ssh/ssh_host_dsa_key" ]; then
      rm -f "$FOLD"/hdd/etc/ssh/ssh_host_dsa_* 2>&1 | debugoutput
      execute_chroot_command "ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N '' >/dev/null"; EXITCODE=$?
      if [ "$EXITCODE" -ne "0" ]; then
        return "$EXITCODE"
      fi
    else
      debug "skipping dsa key gen"
    fi

    if [ -f "$FOLD/hdd/etc/ssh/ssh_host_rsa_key" ]; then
      rm -f "$FOLD"/hdd/etc/ssh/ssh_host_rsa_* 2>&1 | debugoutput
      execute_chroot_command "ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' >/dev/null"; EXITCODE=$?
      if [ "$EXITCODE" -ne "0" ]; then
        return "$EXITCODE"
      fi
    else
      debug "skipping rsa key gen"
    fi

    if [ -f "$FOLD/hdd/etc/ssh/ssh_host_ecdsa_key" ]; then
      rm -f "$FOLD"/hdd/etc/ssh/ssh_host_ecdsa_* 2>&1 | debugoutput
      execute_chroot_command "ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N '' >/dev/null"; EXITCODE=$?
      if [ "$EXITCODE" -ne "0" ]; then
        return "$EXITCODE"
      fi
    else
      debug "skipping ecdsa key gen"
    fi

    if [ -f "$FOLD/hdd/etc/ssh/ssh_host_ed25519_key" ]; then
      rm -f "$FOLD"/hdd/etc/ssh/ssh_host_ed25519_* 2>&1 | debugoutput
      execute_chroot_command "ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' >/dev/null"; EXITCODE=$?
      if [ "$EXITCODE" -ne "0" ]; then
        return "$EXITCODE"
      fi
    else
      debug "skipping ed25519 key gen"
    fi

    ### create json of host ssh fingerprints for robot
    local keys_json=""

    for key_type in rsa dsa ecdsa ed25519 ; do
        file="/etc/ssh/ssh_host_${key_type}_key.pub"
        key_json="\"key_type\": \"${key_type}\""
        if [ -f "$FOLD/hdd/$file" ]; then
          # The default key hashing algorithm used when displaying key fingerprints changes from MD5 to SHA256 in OpenSSH 6.8
          if ! execute_chroot_command "ssh-keygen -l -f ${file} -E md5 > /tmp/${key_type} 2> /dev/null"; then
            execute_chroot_command "ssh-keygen -l -f ${file} > /tmp/${key_type}"
          fi
          # shellcheck disable=SC2034
          while read -r bits fingerprint name type ; do
            key_json="${key_json}, \"key_bits\": \"${bits}\", \"key_fingerprint\": \"${fingerprint}\", \"key_name\": \"${name}\""
          done <<< "$(cat "$FOLD/hdd/tmp/${key_type}")"
          [ -z "${keys_json}" ] && keys_json="{${key_json}}" || keys_json="${keys_json}, {${key_json}}"
          rm "$FOLD/hdd/tmp/${key_type}"
        fi
    done
    keys_json="{\"keys\": [ ${keys_json} ] }"

    echo "${keys_json}" > "$FOLD/ssh_fingerprints"

    return 0
  fi
}

set_ntp_time() {
  local ntp_pid
  local count=0
  local running=1
  local systemd=0

  if [ -x /bin/systemd-notify ]; then
    systemd-notify --booted && systemd=1
  fi

  # if systemd is running and timesyncd too, then return
  if [ $systemd -eq 1 ]; then
    systemctl status systemd-timesyncd 1>/dev/null 2>&1 && return 0
  fi

  service ntp status 1>/dev/null 2>&1 && running=0

  # stop ntp daemon first
  [ $running -eq 0 ] && service ntp stop 2>&1 | debugoutput

  # manual time resync via ntp
  # start ntp in background task
  (ntpd -gq -4 2>&1 | debugoutput) &
  ntp_pid=$!
  # disconnect process from bash to hide kill message
  disown "$ntp_pid"

  # wait 15 seconds and check if ntp still running
  while [ $count -lt 15 ] ; do
    # if not running - stop waiting
    kill -0 "$ntp_pid" 2>/dev/null || break
    (( count = count + 1 ))
    sleep 1
  done

  # if process is still running
  if [ $count -eq 15 ] ; then
    debug "ntp still running - kill it"
    # workaround: the 2>&1 redirect is valid syntax in shellcheck 0.4.3-3, but not in the older version which is currently used by travis
    # shellcheck disable=SC2069
    kill -9 "$ntp_pid" 2>&1 1>/dev/null
  fi

  # write time to hwclock
  # workaround: the 2>&1 redirect is valid syntax in shellcheck 0.4.3-3, but not in the older version which is currently used by travis
  # shellcheck disable=SC2069
  hwclock -w 2>&1 | debugoutput

  # start ntp daemon again
  [ $running -eq 0 ] && service ntp start 2>&1 | debugoutput

  return 0
}

#
# Checks if a post mount script exists.
#
has_postmount_script() {
  local scripts="/root/post-mount /post-mount"
  for i in $scripts ; do test -e "$i" && return 0 ; done
  return 1
}

#
# If a post-mount script is found, it is executed
#
execute_postmount_script() {
  local script=
  [ -e "/root/post-mount" ] && script="/root/post-mount"
  [ -e "/post-mount" ] && script="/post-mount"

  if [ "$script" ]; then
    if [ ! -x "$script" ] ; then
      debug "# Found post-mount script $script, but it isn't executable"
      return 1
    fi

    debug "# Found post-mount script $script; executing it..."
    "$script" ; EXITCODE=$?

    if [ $EXITCODE -ne 0 ]; then
      debug "# Post-mount script didn't exit successfully (exit code = $EXITCODE)"
    fi

    return "$EXITCODE"
  fi
}


#
# Checks if a post installation script exists.
#
has_postinstall_script() {
  if [ -n "${POSTINSTALLURL}" ]; then
    if curl --insecure --connect-timeout 5 --max-time 10 -s --fail -o /root/post-install "${POSTINSTALLURL}"; then
      chmod +x /root/post-install
      return 0
    else
      debug "Couldn't download post-install script from ${POSTINSTALLURL}"
      return 1
    fi
  else
    local scripts="/root/post-install /post-install $FOLD/hdd/root/post-install $FOLD/hdd/root/post-install.sh"
    for i in $scripts ; do test -e "$i" && return 0 ; done
    return 1
  fi
}

#
# If a post-installation script is found, it is executed inside
# the chroot environment.
#
execute_postinstall_script() {
  local script=

  if [ -e "/root/post-install" ]; then
    cp "/root/post-install" "$FOLD/hdd/post-install"
    script="/post-install"
  elif [ -e "/post-install" ]; then
    cp "/post-install" "$FOLD/hdd/post-install"
    script="/post-install"
  elif [ -e "$FOLD/hdd/root/post-install" ]; then
    script="/root/post-install"
  elif [ -e "$FOLD/hdd/root/post-install.sh" ]; then
    script="/root/post-install.sh"
  fi

  if [ "$script" ]; then
    if [ ! -x "$FOLD/hdd$script" ]; then
      debug "# Found post-installation script $script, but it isn't executable"
      return 1
    fi

    debug "# Found post-installation script $script; executing it..."
    # don't use the execute_chroot_command function and logging here - we need output on stdout!

    chroot "$FOLD/hdd/" /bin/bash -c "$script" ; EXITCODE=$?

    if [ $EXITCODE -ne 0 ]; then
      debug "# Post-installation script didn't exit successfully (exit code = $EXITCODE)"
    fi

    return "$EXITCODE"
  fi
}


generate_config_mdadm() {
  if [ "$1" ]; then
    return 1
  fi
}


generate_new_ramdisk() {
  if [ "$1" ]; then
    return 1
  fi
}

setup_cpufreq() {
  if [ "$1" ]; then
    return 1
  fi
}

# clear_logs "NIL"
clear_logs() {
  if [ "$1" ]; then
    find "$FOLD/hdd/var/log" -type f > /tmp/filelist.tmp
    while read -r a; do
      if echo "$a" | grep -q '.gz$\|.[[:digit:]]\{1,3\}$'; then
        rm -rf "$a" >> /dev/null 2>&1
      else
        echo -n > "$a"
      fi
    done < /tmp/filelist.tmp
  fi
  return 0
}

# activate ip_forward for new netsetup
generate_sysctlconf() {
  local sysctl_conf="$FOLD/hdd/etc/sysctl.conf"
  if [ -d "$FOLD/hdd/etc/sysctl.d" ]; then
   sysctl_conf="$FOLD/hdd/etc/sysctl.d/99-hetzner.conf"
  fi
    cat << EOF > "$sysctl_conf"
### $COMPANY installimage
# sysctl config
#net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
# ipv6 settings (no autoconfiguration)
net.ipv6.conf.default.autoconf=0
net.ipv6.conf.default.accept_dad=0
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.default.accept_ra_defrtr=0
net.ipv6.conf.default.accept_ra_rtr_pref=0
net.ipv6.conf.default.accept_ra_pinfo=0
net.ipv6.conf.default.accept_source_route=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.default.forwarding=0
net.ipv6.conf.all.autoconf=0
net.ipv6.conf.all.accept_dad=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.all.accept_ra_defrtr=0
net.ipv6.conf.all.accept_ra_rtr_pref=0
net.ipv6.conf.all.accept_ra_pinfo=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.all.forwarding=0
EOF

  # only swap to avoid a OOM condition on vps
  if isVServer; then
   echo "vm.swappiness=0" >> "$sysctl_conf"
  fi

  return 0
}

# get_rootpassword "/etc/shadow"
get_rootpassword() {
  if [ -n "$1" ]; then
    ROOTHASH="$(awk -F: '/^root/ {print $2}' "$1")"
    if [ "$ROOTHASH" ]; then
      return 0
    else
      return 1
    fi
  fi
}

# set_rootpassword "$FOLD/hdd/etc/shadow" "ROOTHASH"
set_rootpassword() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    grep -v "^root" "${1}" > /tmp/shadow.tmp
    local GECOS; GECOS="$(awk -F: '/^root/ {print $3":"$4":"$5":"$6":"$7":"$8":"}' "${1}")"
    echo "root:$2:$GECOS" > "$1"
    cat /tmp/shadow.tmp >> "$1"
    return 0
  else
    return 1
  fi
}

# fetch_ssh_keys "$OPT_SSHKEYS_URL"
fetch_ssh_keys() {
   if [ -n "$1" ]; then
     local key_url="$1"
     case "$key_url" in
       https:*|http:*|ftp:*)
         curl -s -m 10 "$key_url" > "$FOLD/authorized_keys" 2>&1 | debugoutput
       ;;
       *)
         cat "$key_url" > "$FOLD/authorized_keys"
       ;;
     esac
     if [ ! -s "$FOLD/authorized_keys" ]; then
       debug "authorized keys file is empty. not disabling password"
       export OPT_USE_SSHKEYS=0
     fi
     return 0
   else
     return 1
   fi
}

# copy_ssh_keys "$user"
copy_ssh_keys() {
   local targetuser='root'

   if [ -n "$1" ]; then
     targetuser="home/$1"
   fi

   mkdir -p "$FOLD/hdd/$targetuser/.ssh"
   if [ "$targetuser" != 'root' ]; then
     execute_chroot_command "chown $targetuser: /$targetuser/.ssh"
   fi

   cat "$FOLD/authorized_keys" >> "$FOLD/hdd/$targetuser/.ssh/authorized_keys"

   return $?
}

# set sshd PermitRootLogin
set_ssh_rootlogin() {
  if [ -n "$1" ]; then
     local permit="$1"
     case "$permit" in
       yes|no|without-password|forced-commands-only)
         sed -i "$FOLD/hdd/etc/ssh/sshd_config" -e "s/^\\(#\\)\\?PermitRootLogin.*/PermitRootLogin $1/"
       ;;
       *)
         debug "invalid option for PermitRootLogin"
         return 1
       ;;
     esac
  else
     return 1
  fi
}

generate_config_grub() {
  if [ -n "$1" ]; then
    return 1
  fi
}

#
# write_grub
#
# Write the GRUB bootloader into the MBR
#
write_grub() {
  if [ -n "$1" ]; then
    return 0
  fi

#TODO: this needs to be fixed in general, as all distros now install the
#      bootloader in generate_grub_config instead

}

generate_config_lilo() {
  if [ -n "$1" ]; then
  BFILE="$FOLD/hdd/etc/lilo.conf"
  rm -rf "$FOLD/hdd/boot/grub/menu.lst" >>/dev/null 2>&1
  {
    echo "### Hetzner Online GmbH installimage"
    echo "# bootloader config"
    if [ "$LILOEXTRABOOT" ]; then
      echo "$LILOEXTRABOOT"
    fi
    echo "boot=$SYSTEMDEVICE"
    echo "root=$(grep " / " "$FOLD/hdd/etc/fstab" |cut -d " " -f 1)"
    echo "vga=0x317"
    echo "timeout=40"
    echo "prompt"
    echo "default=Linux"
    echo "large-memory"
    echo ""
  } > "$BFILE"
  if [ -e "$FOLD/hdd/boot/vmlinuz-$VERSION" ]; then
    echo "image=/boot/vmlinuz-$VERSION" >> "$BFILE"
  else
    return 1
  fi
  echo "  label=Linux" >> "$BFILE"
  # echo "  read-only" >> "$BFILE"
  if [ -e "$FOLD/hdd/boot/initrd.img-$VERSION" ]; then
    echo "  initrd=/boot/initrd.img-$VERSION" >> "$BFILE"
  elif [ -e "$FOLD/hdd/boot/initrd-$VERSION" ]; then
    echo "  initrd=/boot/initrd-$VERSION" >> "$BFILE"
  fi
  echo "" >> "$BFILE"


    return 0
  fi
}

write_lilo() {
  if [ -n "$1" ]; then
    execute_chroot_command "yes |/sbin/lilo -F" | debugoutput
    EXITCODE=$?
    return "$EXITCODE"
  fi
}

generate_ntp_config() {
  local cfgntp="/etc/ntp.conf"
  local cfgchrony="/etc/chrony/chrony.conf"
  local cfgtimesyncd="/etc/systemd/timesyncd.conf"
  local cfg="$cfgntp"

  # find out versions
  local debian_version=0
  # for future use
  #local ubuntu_version=0
  local suse_version=0
  [ "$IAM" == 'debian' ] && debian_version=$(cut -c 1 "$FOLD/hdd/etc/debian_version")
  # for future use
  #[ "$IAM" = 'ubuntu' ] && ubuntu_version="$IMG_VERSION"
  [ "$IAM" = 'suse' ] && suse_version="$IMG_VERSION"

  if [ -f "$FOLD/hdd/$cfgntp" ] || [ -f "$FOLD/hdd/$cfgchrony" ] || [ -f "$FOLD/hdd/$cfgtimesyncd" ] ; then
    if [ -f "$FOLD/hdd/$cfgtimesyncd" ]; then
      debug "# using systemd-timesyncd"
      local cfgdir="$FOLD/hdd/$cfgtimesyncd.d"
      local cfgparam='NTP'
      # jessie systemd does not recognize drop-ins for systemd-timesyncd
      if [ "$IAM" = "debian" ] && [ "$debian_version" -eq 8 ]; then
        cfgparam='Servers'
        CFG="$FOLD/hdd/$cfgtimesyncd"
      else
        mkdir -p "$cfgdir"
        CFG="$cfgdir/$C_SHORT.conf"
      fi
      {
        echo "[Time]"
        echo -n "$cfgparam="
        for i in "${NTPSERVERS[@]}"; do
          echo -n "$i "
        done
        echo ""
      } > "$CFG" | debugoutput
    elif [ -f "$FOLD/hdd/$cfgchrony" ]; then
      debug "# using chrony"
      CFG="$FOLD/hdd/$cfgchrony"
      {
        echo ""
        echo "# $C_SHORT ntp servers"
        for i in "${NTPSERVERS[@]}"; do
          echo "server $i offline minpoll 8"
        done
      } >> "$CFG" | debugoutput
    else
      CFG="$FOLD/hdd/$cfgntp"
      debug "# using NTP"
      sed -e 's/^server \(.*\)$/## server \1   ## see end of file/' -i "$cfg"
      {
        echo ""
        echo "# $C_SHORT ntp servers"
        for i in "${NTPSERVERS[@]}"; do
          echo "server $i offline iburst"
        done
      } >> "$CFG" | debugoutput
      if [ "$IAM" = "suse" ]; then
        {
          echo ""
          echo "# local clock"
          echo "server 127.127.1.0"
        } >> "$CFG" | debugoutput
      fi
    fi
  else
    debug "no ntp config found, ignoring"
  fi
  return 0
}

# check_fqdn "$DOMAIN" - return 0 when the domain is ok
check_fqdn() {

  CHECKFQDN=""
  CHECKFQDN="$(echo "$1" | grep -e '^\([[:alnum:]][[:alnum:]-]*[[:alnum:]]\.\)\{2,\}')"

  if [ -z "$CHECKFQDN" ]; then
    return 1
  else
    return 0
  fi
}

#
# create_hostname <ip> - creates a generic hostname from ip
#
create_hostname() {

  FIRST="$(echo "$1" | cut -d '.' -f 1)"
  SECOND="$(echo "$1" | cut -d '.' -f 2)"
  THIRD="$(echo "$1" | cut -d '.' -f 3)"
  FOURTH="$(echo "$1" | cut -d '.' -f 4)"

  if [ -z "$FIRST" ] || [ -z "$SECOND" ] || [ -z "$THIRD" ] || [ -z "$FOURTH" ]; then
    return 1
  fi
  if [ "$FIRST" -eq "78" ] || [ "$FIRST" -eq "188" ] || [ "$FIRST" -eq "178" ] || [ "$FIRST" -eq "46" ] || [ "$FIRST" -eq "176" ] || [ "$FIRST" -eq "5" ] || [ "$FIRST" -eq "185" ] || [ "$FIRST" -eq "136" ] || [ "$FIRST" -eq "144" ] || [ "$FIRST" -eq "148" ] || [ "$FIRST" -eq "138" ]; then
    GENERATEDHOSTNAME="static.$FOURTH.$THIRD.$SECOND.$FIRST.clients.your-server.de"
  else
    GENERATEDHOSTNAME="static.$FIRST-$SECOND-$THIRD-$FOURTH.clients.your-server.de"
  fi

  echo "$GENERATEDHOSTNAME"
  return 0

}

# Executes a command within a systemd-nspawn container <command>
execute_nspawn_command() {
  local command="${1}"

  local mount_point_blacklist=/dev
  mount_point_blacklist="${mount_point_blacklist} /proc"
  mount_point_blacklist="${mount_point_blacklist} /sys"

  local container_root_dir=${FOLD}/hdd
  local working_dir=${FOLD}

  local temp_io_fifo=${container_root_dir}/temp_io.fifo
  local temp_retval_fifo=${container_root_dir}/temp_retval.fifo
  local temp_helper_script=${container_root_dir}/temp_helper.sh
  local temp_helper_service_file=${container_root_dir}/etc/systemd/system/multi-user.target.wants/temp_helper.service
  local temp_container_service_file=/lib/systemd/system/temp_container.service
  local temp_umounted_mount_point_list=${working_dir}/temp_umounted_mount_points.txt

  local command_retval=

  local temp_files=${temp_io_fifo}
  temp_files="${temp_files} ${temp_retval_fifo}"
  temp_files="${temp_files} ${temp_helper_script}"
  temp_files="${temp_files} ${temp_helper_service_file}"
  temp_files="${temp_files} ${temp_container_service_file}"
  temp_files="${temp_files} ${temp_umounted_mount_point_list}"

  debug "Executing '${command}' within a systemd nspawn container"

  mkfifo "$temp_io_fifo"
  mkfifo "$temp_retval_fifo"

  ### ### ### ### ### ### ### ### ### ###

  cat <<HEREDOC > "$temp_helper_script"
#!/usr/bin/env bash
### $COMPANY installimage
trap "poweroff" 0
\$(cat /$(basename "$temp_io_fifo")) &> /$(basename "$temp_io_fifo")
echo \${?} > /$(basename "$temp_retval_fifo")
HEREDOC

  chmod a+x "$temp_helper_script"

  ### ### ### ### ### ### ### ### ### ###

  cat <<HEREDOC > "$temp_helper_service_file"
### $COMPANY installimage
[Unit]
Description=Temporary helper service
After=network.target
[Service]
ExecStart=/$(basename "$temp_helper_script")
HEREDOC

  ### ### ### ### ### ### ### ### ### ###

  cat <<HEREDOC > "$temp_container_service_file"
### $COMPANY installimage
[Unit]
Description=Temporary container service
[Service]
ExecStart=/usr/bin/systemd-nspawn \
  --boot \
  --directory=$container_root_dir \
  --quiet
HEREDOC

  ### ### ### ### ### ### ### ### ### ###

  touch "$temp_umounted_mount_point_list"

  debug "Temporarily umounting blacklisted mount points in order to start the systemd nspawn container"

  while read -r entry; do
    for blacklisted_mount_point in $mount_point_blacklist; do
      while read -r subentry; do
        umount --verbose "$(echo "$subentry" | awk '{ print $2 }')" 2>&1 | debugoutput || return 1
        echo "$subentry" | cat - "$temp_umounted_mount_point_list" | uniq --unique > "$temp_umounted_mount_point_list"2
        mv "$temp_umounted_mount_point_list"2 "$temp_umounted_mount_point_list"
      done < <(echo "$entry" | grep "$container_root_dir$blacklisted_mount_point")
    done
  done < <(tac /proc/mounts)

  echo "Starting the systemd nspawn container" | debugoutput

  systemctl daemon-reload 2>&1 | debugoutput || return 1
  systemctl start "$(basename $temp_container_service_file)" 2>&1 | debugoutput || return 1

  echo "$command" > "$temp_io_fifo"
  debugoutput < "$temp_io_fifo"
  command_retval="$(cat "$temp_retval_fifo")"

  while systemctl is-active "$(basename $temp_container_service_file)" &> /dev/null; do
    sleep 2
  done

  echo "The systemd nspawn container shut down" | debugoutput

  echo "Remounting temporarily umounted mount points" | debugoutput

  mount --all --fstab "$temp_umounted_mount_point_list" --verbose 2>&1 | debugoutput || return 1

  rm --force "$temp_files"

  return "$command_retval"
}

# check for latest subversion of Plesk
check_plesk_subversion() {
  local main_version="$1"
  local output=""
  local latest_release=""

  # test if pleskinstaller is already downloaded
  if [ ! -x "$FOLD/hdd/pleskinstaller" ] ; then
    wget "http://mirror.hetzner.de/tools/parallels/plesk/$IMAGENAME" -O "$FOLD/hdd/pleskinstaller" 2>&1 | debugoutput
    chmod a+x "$FOLD"/hdd/pleskinstaller >> /dev/null
  fi

  output="$(execute_chroot_command_wo_debug "/pleskinstaller --select-product-id plesk --show-releases" 2>&1)"
  latest_release="$(echo "$output" | grep "PLESK_${main_version}" | head -n1 | awk '{print $2}')"

  [ -n "$latest_release" ] && echo "$latest_release"

}

#
# determine image version and install plesk
#
install_plesk() {
  # get Plesk version to install
  local plesk_version=$1

  # we need the installer first
  wget "http://mirror.hetzner.de/tools/parallels/plesk/$IMAGENAME" -O "$FOLD/hdd/pleskinstaller" 2>&1 | debugoutput
  chmod a+x "$FOLD/hdd/pleskinstaller" >> /dev/null

  # if there was no version specified, take our standard version
  if [ "$plesk_version" == "plesk" ]; then
    debug "install standard version"
    plesk_version="$PLESK_STD_VERSION"
  elif echo "$plesk_version" | grep -q -e "plesk_[0-9]+_[0-9]+_[0-9]+$"; then
    plesk_version="$(echo "$plesk_version" | tr '[:lower:]' '[:upper:]')"
  else
    # check if we want a main version and should detect the latest subversion
    local main_version="${plesk_version#plesk_}"
    local latest_sub=""

    [ -n "$main_version" ] && latest_sub="$(check_plesk_subversion "$main_version")"
    if [ -z "$latest_sub" ]; then
      echo "Could not determine latest subversion of Plesk $main_version"
      return 1
    fi
    plesk_version="$latest_sub"
  fi

#  if [ "$IMAGENAME" == "CentOS-57-64-minimal" ] || [ "$IMAGENAME" == "CentOS-58-64-minimal" ] || [ "$IMAGENAME" == "CentOS-60-64-minimal" ] || [ "$IMAGENAME" == "CentOS-62-64-minimal" ] || [ "$IMAGENAME" == "CentOS-63-64-minimal" ]; then
  if [ "$IAM" == 'centos' ]; then
    execute_chroot_command "yum -y install mysql mysql-server"
    # we should install rails here as well, but this is a bit tricky
    # because there is no package and we would have to install via gem
    #
    # centos wants to have a fqdn for pleskinstallation
    sed -i "s|$IMAGENAME|$IMAGENAME.yourdomain.localdomain $IMAGENAME|" "$FOLD/hdd/etc/hosts"
  fi

  if [ "$IAM" == "debian" ] && [ "$IMG_VERSION" -ge 70 ]; then
    # create folder /run/lock since it doesn't exist after the installation of debian7 and needed for plesk installation
    execute_chroot_command "mkdir -p /run/lock"
  fi

  COMPONENTS="awstats bind config-troubleshooter dovecot drweb heavy-metal-skin horde l10n mailman mod-bw mod_fcgid mod_python mysqlgroup nginx panel php5.6 phpgroup pmm postfix proftpd psa-firewall roundcube spamassassin Troubleshooter webalizer web-hosting webservers"
  COMPONENTLIST="$(for component in $COMPONENTS; do echo -n "--install-component $component "; done)"

  if readlink --canonicalize /sbin/init | grep --quiet systemd && readlink --canonicalize "$FOLD"/hdd/sbin/init | grep --quiet systemd; then
    execute_nspawn_command "/pleskinstaller --select-product-id plesk --select-release-id $plesk_version --download-retry-count 99 $COMPONENTLIST"; EXITCODE=$?
  else
    execute_chroot_command "/pleskinstaller --select-product-id plesk --select-release-id $plesk_version --download-retry-count 99 $COMPONENTLIST"; EXITCODE=$?
  fi
  rm -rf "$FOLD"/hdd/pleskinstaller >/dev/null 2>&1
  return "$EXITCODE"

}

install_omsa() {
# maybe split into separate functions for debian/ubuntu and centos
#  if [ "$1" ]; then
#    return 1
#  fi
  # need to stop dell_rbu driver before install, or the installation will look
  # for the kernel modules of the rescue system inside the image
  /etc/init.d/instsvcdrv stop >/dev/null

  if [ "$IAM" = "debian" ] || [ "$IAM" = "ubuntu" ]; then
    REPOFILE="$FOLD/hdd/etc/apt/sources.list.d/dell-omsa.list"
    local codename="precise"
    if [ "$IAM" = "debian" ] && [ $IMG_VERSION -ge 70 ]; then
      codename="wheezy"
    fi
    echo -e '\n# Community OMSA packages provided by linux.dell.com' > "$REPOFILE"
    printf 'deb http://linux.dell.com/repo/community/%s %s openmanage\n' "${IAM}" "${codename}" >> "$REPOFILE"
    execute_chroot_command "gpg --keyserver pool.sks-keyservers.net --recv-key 1285491434D8786F"
    execute_chroot_command "gpg -a --export 1285491434D8786F | apt-key add -"
    execute_chroot_command "mkdir -p /run/lock"
    execute_chroot_command "aptitude update >/dev/null"
    execute_chroot_command "aptitude --without-recommends -y install srvadmin-base srvadmin-idracadm srvadmin-idrac7"; EXITCODE=$?
    return "$EXITCODE"
  elif [ "$IAM" = "centos" ]; then
    execute_chroot_command "yum -y install perl"
    execute_chroot_command "wget -q -O - http://linux.dell.com/repo/hardware/latest/bootstrap.cgi | bash"
    execute_chroot_command "yum -y install srvadmin-base srvadmin-idrac7"
  else
    debug "no OMSA packages available for this OS"
    return 0
  fi
  /etc/init.d/instsvcdrv start >/dev/null

}

#
# translate_unit <value>
#
translate_unit() {
  if [ -z "$1" ]; then
    echo "0"
    return 1
  fi
  for unit in M MiB G GiB T TiB; do
    if echo "$1" | grep -q -e "^[[:digit:]]+$unit$"; then
      value=${1//$unit}

      case "$unit" in
        M|MiB)
          factor=1
          ;;
        G|GiB)
          factor=1024
          ;;
        T|TiB)
          factor=1048576
          ;;
      esac
      echo $((value * factor))
      return 0
    fi
  done

  echo "$1"
  return 0
}


#
# install_robot_script
#
# Installs a script in the new system that is used for automatic
# installations by the Robot. The script removes itself afterwards.
#
install_robot_script() {
  VERSION=$(echo "$IMAGENAME" | cut -d- -f2)
  cp "$SCRIPTPATH/robot.sh" "$FOLD/hdd/"
  chmod +x "$FOLD/hdd/robot.sh"
  sed -i -e "s#^URL=?#URL=\"$ROBOTURL\"#" "$FOLD/hdd/robot.sh"
    case "$IAM" in
      debian|ubuntu)
        sed -e 's/^exit 0$//' -i "$FOLD/hdd/etc/rc.local"
        echo -e '[ -x /robot.sh ] && /robot.sh\nexit 0' >> "$FOLD/hdd/etc/rc.local"
        ;;
      centos)
        echo "[ -x /robot.sh ] && /robot.sh" >> "$FOLD/hdd/etc/rc.local"
        chmod +x "$FOLD/hdd/etc/rc.local" 1>/dev/null 2>&1
        ;;
      suse)
        # needs suse 12.2 or higher
        echo "bash /robot.sh" >> "$FOLD/hdd/etc/init.d/boot.local"
        ;;
    esac
}

#report_statistic "SERVER" "IMAGENAME" "SWRAID" "LVM"
report_statistic() {
  if [ "$1" ] && [ "$2" ] && [ "$3" ] && [ "$4" ] && [ "$5" ]; then
    REPORTSRV="$1"
    # shellcheck disable=SC2010
    STANDARDIMAGE="$(ls -1 "$IMAGESPATH" |grep "$2")"

    if [ ! "$STANDARDIMAGE" ]; then
      REPORTIMG="Custom"
    else
      # shellcheck disable=SC2001
      REPORTIMG="$(echo "$2" |sed 's/\./___/g')"
    fi

    REPORTSWR="$3"
    REPORTLVM="$4"
    if [ "$5" = "lilo" ] || [ "$5" = "LILO" ]; then
      BLCODE="0"
    elif [ "$5" = "grub" ] || [ "$5" = "GRUB" ]; then
      BLCODE="1"
    fi
    ERROREXITCODE="$6"
    wget --no-check-certificate --timeout=20 "https://$REPORTSRV/report/image/$REPORTIMG/$REPORTSWR/$REPORTLVM/$BLCODE/$ERROREXITCODE" -O /tmp/wget.tmp >> /dev/null 2>&1; EXITCODE=$?
    return "$EXITCODE"
  fi
}

# report_config "SERVER"
report_config() {
  if [ -n "$1" ]; then
    local config_file="$FOLD/install.conf"
    # currently use new rz-admin to report the install.conf
    # TODO: change that later to rz-admin
    local report_ip="$1"
    local report_status=""

    report_status="$(curl -m 10 -s -k -X POST -T "$config_file" "https://${report_ip}/api/${HWADDR}/image/new")"
    echo "report install.conf to rz-admin: ${report_status}" | debugoutput

    echo "${report_status}"
  fi
}

# report_debuglog "SERVER" "LOG"
report_debuglog() {
  local report_ip="$1"
  local log_id="$2"
  if [ "$#" -ne 2 ]; then
    local report_status=""

    report_status="$(curl -m 10 -s -k -X POST -T "$DEBUGFILE" "https://${report_ip}/api/${HWADDR}/image/${log_id}/log")"
    echo "report debug.txt to rz-admin: ${report_status}" | debugoutput

    return 0
  fi
}

#
# cleanup
#
# Unmount filesystems and remove temporary directories.
#
cleanup() {
  debug "# Cleaning up..."

  while read -r line ; do
    mount="$(echo "$line" | grep "$FOLD" | cut -d' ' -f2)"
    if [ -n "$mount" ] ; then
      umount -l "$mount" >> /dev/null 2>&1
    fi
  done < /proc/mounts

  rm -rf "$FOLD" >> /dev/null 2>&1
  rm -rf /tmp/install.vars 2>&1
  rm -rf /tmp/*.tmp 2>&1
}

exit_function() {
  local report_id=""
  ERROREXIT="1"

  test "$1" && echo_red "$1"
  echo
  echo -e "$RED         An error occured while installing the new system!$NOCOL"
  echo -e "$RED          See the debug file $DEBUGFILE for details.$NOCOL"
  echo
  echo "Please check our wiki for a description of the error:"
  echo
  echo "http://wiki.hetzner.de/index.php/Installimage/en"
  echo
  echo "If your problem is not described there, try booting into a fresh"
  echo "rescue system and restart the installation. If the installation"
  echo "fails again, please contact our support via Hetzner Robot, providing"
  echo "the IP address of the server and a copy of the debug file."
  echo
  echo "  https://robot.your-server.de"
  echo

  report_statistic "$STATSSERVER" "$IMAGE_FILE" "$SWRAID" "$LVM" "$BOOTLOADER" "$ERROREXIT"
  report_id="$(report_config "$REPORTSERVER")"
  report_debuglog "$REPORTSERVER" "$report_id"
  cleanup
}

#function to check if it is a intel or amd cpu
function check_cpu () {
  if grep -q GenuineIntel /proc/cpuinfo; then
    MODEL="intel"
  else
    MODEL="amd"
  fi

  echo "$MODEL"

  return 0
}

#get the smallest harddrive
function smallest_hd() {
  local smallest_drive_space; smallest_drive_space="$(blockdev --getsize64 "$DRIVE1" 2>/dev/null)"
  local smallest_drive="$DRIVE1"
  for i in $(seq 1 $COUNT_DRIVES); do
    if [ "$smallest_drive_space" -gt "$(blockdev --getsize64 "$(eval echo "\$DRIVE$i")")" ]; then
      smallest_drive_space="$(blockdev --getsize64 "$(eval echo "\$DRIVE$i")")"
      smallest_drive="$(eval echo "\$DRIVE$i")"
    fi
  done

  echo "$smallest_drive"

  return 0
}

function largest_hd() {
  LARGEST_DRIVE_SPACE="$(blockdev --getsize64 "$DRIVE1")"
  LARGEST_DRIVE="$DRIVE1"
  for i in $(seq 1 $COUNT_DRIVES); do
    if [ "$LARGEST_DRIVE_SPACE" -lt "$(blockdev --getsize64 "$(eval echo "\$DRIVE$i")")" ]; then
      LARGEST_DRIVE_SPACE="$(blockdev --getsize64 "$(eval echo "\$DRIVE$i")")"
      LARGEST_DRIVE="$(eval echo "\$DRIVE$i")"
    fi
  done

  echo "$LARGEST_DRIVE"

  return 0
}

# get the drives which are connected through an USB port
function getUSBFlashDrives() {
  for i in $(seq 1 $COUNT_DRIVES); do
    DEV=$(eval echo "\$DRIVE$i")
    # remove string '/dev/'
    local withoutdev; withoutdev=${DEV##*/}
    local removable;
    if [ -e "/sys/block/$withoutdev/removable" ]; then
      removable=$(cat "/sys/block/$withoutdev/removable")
    else
      removable=0
    fi
    if [ "$removable" -eq 1 ]; then
      echo "${DEV}"
    fi
  done

  return 0
}

# get HDDs with size not in tolerance range
function getHDDsNotInToleranceRange() {
  # RANGE in percent relative to smallest hdd
  local RANGE=135
  local smallest_hdd; smallest_hdd="$(smallest_hd)"
  local smallest_hdd_size; smallest_hdd_size="$(blockdev --getsize64 "$smallest_hdd")"
  local max_size=$(( smallest_hdd_size * RANGE / 100 ))
  debug "checking if hdd sizes are within tolerance. min: $smallest_hdd_size / max: $max_size"
  for i in $(seq 1 $COUNT_DRIVES); do
    if [ "$(blockdev --getsize64 "$(eval echo "\$DRIVE$i")")" -gt "$max_size" ]; then
      eval echo "\$DRIVE$i"
      debug "DRIVE$i not in range"
    else
      debug "DRIVE$i in range"
      blockdev --getsize64 "$(eval echo "\$DRIVE$i")" | debugoutput
    fi
  done

  return 0
}

uuid_bugfix() {
    debug "# change all device names to uuid (e.g. for ide/pata transition)"
    TEMPFILE="$(mktemp)"
    sed -n 's|^/dev/\([hsv]d[a-z][1-9][0-9]\?\).*|\1|p' < "$FOLD/hdd/etc/fstab" > "$TEMPFILE"
    while read -r LINE; do
      UUID="$(blkid -o value -s UUID "/dev/$LINE")"
      # not quite perfect. We need to match /dev/sda1 but not /dev/sda10.
      # device name may not always be followed by whitespace
      [ -e "$FOLD/hdd/etc/fstab" ] && sed -i "s|^/dev/${LINE} |# /dev/${LINE} during Installation (RescueSystem)\\nUUID=${UUID} |" "$FOLD/hdd/etc/fstab"
      [ -e "$FOLD/hdd/boot/grub/grub.cfg" ] && sed -i "s|/dev/${LINE} |UUID=${UUID} |" "$FOLD/hdd/boot/grub/grub.cfg"
      [ -e "$FOLD/hdd/boot/grub/grub.conf" ] && sed -i "s|/dev/${LINE} |UUID=${UUID} |" "$FOLD/hdd/boot/grub/grub.conf"
      [ -e "$FOLD/hdd/boot/grub/menu.lst" ] && sed -i "s|/dev/${LINE} |UUID=${UUID} |" "$FOLD/hdd/boot/grub/menu.lst"
      [ -e "$FOLD/hdd/etc/lilo.conf" ] && sed -i "s|append=\"root=/dev/${LINE}|append=\"root=UUID=${UUID}|" "$FOLD/hdd/etc/lilo.conf"
      [ -e "$FOLD/hdd/etc/lilo.conf" ] && sed -i "s|/dev/${LINE}|\"UUID=${UUID}\"|" "$FOLD/hdd/etc/lilo.conf"
    done < "$TEMPFILE"
    rm "$TEMPFILE"
    return 0
}

# param 1: /dev/sda (e.g)
function hdinfo() {
  local withoutdev
  local vendor
  local name; name=
  local logical_nr; logical_nr=
  withoutdev=${1##*/}
  vendor="$(tr -d ' ' < "/sys/block/$withoutdev/device/vendor")"

  case "$vendor" in
    LSI)
      logical_nr="$(find "/sys/block/$withoutdev/device/scsi_device/*" -maxdepth 0 -type d | cut -d: -f3)"
      name="$(megacli -ldinfo -L"$logical_nr" -aall | grep Name | cut -d: -f2)"
      [ -z "$name" ] && name="no name"
      echo "# LSI RAID (LD $logical_nr): $name"
      ;;
    Adaptec)
      #
      # Unsure if this version does work in all cases, the original one does print the filename, if the file is not present.
      #
      # logical_nr="$(awk '{print $2}' /sys/block/$withoutdev/device/model 2>&1)"
      logical_nr="$(awk '{print $2}' "/sys/block/$withoutdev/device/model" 2>/dev/null)"
      name="$(arcconf GETCONFIG 1 LD "$logical_nr" | grep "Logical device name" | sed 's/.*: \(.*\)/\1/g')"
      [ -z "$name" ] && name="no name"
      echo "# Adaptec RAID (LD $logical_nr): $name"
      ;;
    AMCC)
      logical_nr="$(find "/sys/block/$withoutdev/device/scsi_device/*" -maxdepth 0 -type d | cut -d: -f4)"
      echo "# 3ware RAID (LD $logical_nr)"
      ;;
    ATA)
      name="$(hdparm -i "$1" | grep Model | sed 's/ Model=\(.*\), Fw.*/\1/g')"
      echo "# Onboard: $name"
      ;;
    *)
      echo "# unkown"
      ;;
  esac
}

# function to check if we got autonegotiated speed with NIC or if the rescue system set speed to fix 100MBit FD
# returns 0 if we are auto negotiated and 1 if not
function isNegotiated() {
  # search for first NIC which has an IP
  find /sys/class/net/* -type l -name 'eth*' -printf '%f\n' | while read -r interface; do
    if ip a show "$interface" | grep -q "inet [1-9]"; then
      #check if we got autonegotiated
      if mii-tool "$interface" 2>/dev/null | grep -q "negotiated"; then
        return 0
      else
        return 1
      fi
    fi
  done
}

# function to check if we are in a kvm-qemu vServer environment
# returns 0 if we are in a vServer env otherwise 1
function isVServer() {
  case "$SYSTYPE" in
    vServer|Bochs|Xen|KVM|VirtualBox|'VMware,Inc.')
      debug "# Systype: $SYSTYPE"
      return 0;;
    *)
      debug "# Systype: $SYSTYPE"
      case "$SYSMFC" in
        QEMU)
          debug "# Manufacturer: $SYSMFC"
          return 0;;
        *)
          debug "# Manufacturer: $SYSMFC"
          return 1;;
      esac
      return 1;;
  esac
}

# function to check if we have to use GPT or MS-DOS partition tables

function part_test_size() {
  #2TiB limit
  local LIMIT=2096128

  GPT=0

  if [ "$FORCE_GPT" = "2" ]; then
    debug "Forcing use of GPT as directed"
    GPT=1
    PART_COUNT=$((PART_COUNT+1))
    return 0
  fi

  local dev; dev=$(smallest_hd)
  if [ "$SWRAID" -eq 0 ]; then
    dev="$DRIVE1"
  fi
  local DRIVE_SIZE; DRIVE_SIZE=$(blockdev --getsize64 "$dev")
  DRIVE_SIZE=$(( DRIVE_SIZE / 1024 / 1024 ))

  if [ $DRIVE_SIZE -ge $LIMIT ] || [ "$FORCE_GPT" = "1" ]; then
    # use only GPT if not CentOS or OpenSuSE newer than 12.2
    if [ "$IAM" != "centos" ] || [ "$IAM" == "centos" ] && [ "$IMG_VERSION" -ge 70 ]; then
      if [ "$IAM" = "suse" ] && [ "$IMG_VERSION" -lt 122 ]; then
        echo "SuSE older than 12.2. cannot use GPT (but drive size is bigger then 2TB)" | debugoutput
      else
        echo "using GPT (drive size bigger then 2TB or requested)" | debugoutput
        GPT=1
        PART_COUNT=$((PART_COUNT+1))
      fi
    else
      echo "cannot use GPT (but drive size is bigger then 2TB)" | debugoutput
    fi
  fi
}

# function to check and correct sizes of normal DOS styled partitions
# if first param is "no_output" only correct size of "all" partition

function check_dos_partitions() {
  echo "check_dos_partitions" | debugoutput
  # shellcheck disable=SC2015
  if [ "$FORCE_GPT" = "2" ] || [ "$IAM" != "centos" ] || [ "$IAM" == "centos" ] && [ "$IMG_VERSION" -ge 70 ] || [ "$BOOTLOADER" == "lilo" ]; then
    if [ "$IAM" = "suse" ] && [ "$IMG_VERSION" -lt 122 ]; then
      echo "SuSE version older than 12.2, no grub2 support" | debugoutput
    else
      return 0
    fi
  fi

  local LIMIT=2096128
  local PART_WO_ALL_SIZE_PRIM=0
  local PART_WO_ALL_SIZE=0
  local output="$1"
  local PART_ALL_SIZE=0
  local temp_size=0
  local result=''
  local found_all_part=''
  local dev; dev=$(smallest_hd)
  if [ "$SWRAID" -eq 0 ]; then
    dev="$DRIVE1"
  fi

  local DRIVE_SIZE; DRIVE_SIZE=$(blockdev --getsize64 "$dev")
  DRIVE_SIZE=$(( DRIVE_SIZE / 1024 / 1024 ))

  if [ $DRIVE_SIZE -lt $LIMIT ]; then
    return 0
  fi

  echo "DRIVE size is: $DRIVE_SIZE" | debugoutput

  # check if all primary partitions (without "all") are within the 2TB Limit
  for i in $(seq 1 $PART_COUNT); do
    #check only primary partitions
    if [ "${PART_SIZE[$i]}" != "all" ]; then
       if [ "$i" -lt 4 ]; then
         PART_WO_ALL_SIZE_PRIM="$(echo ${PART_SIZE[$i]} + $PART_WO_ALL_SIZE_PRIM | bc)"
       fi
       # MS-DOS partitions may not start above 2TiB either
       if [ $PART_WO_ALL_SIZE -gt $LIMIT ]; then
         result="PART_BEGIN_OVER_LIMIT"
       fi
       PART_WO_ALL_SIZE="$(echo ${PART_SIZE[$i]} + $PART_WO_ALL_SIZE | bc)"
       if [ ${PART_SIZE[$i]} -gt $LIMIT ]; then
         [ -z $result ] && result="PART_OVERSIZED"
       fi
    else
      found_all_part="yes"
    fi
  done

  echo "partitions without \"all\" sum up to $PART_WO_ALL_SIZE" | debugoutput
  echo "primary partitions without \"all\" sum up to $PART_WO_ALL_SIZE_PRIM" | debugoutput

  # now check how big an "all" partition is
  # MS-DOS partitions may not start above 2TiB either
  if [ "$PART_WO_ALL_SIZE" -gt $LIMIT ]; then
    if [ "$found_all_part" = "yes" ] ; then
      [ -z $result ] && result="PART_ALL_BEGIN_OVER_LIMIT"
    fi
  fi

  # if we have an extended partition
  if [ $PART_COUNT -gt 3 ]; then
    for i in $(seq 4 $PART_COUNT); do
      if [ "${PART_SIZE[$i]}" != "all" ]; then
        temp_size="$(echo "$temp_size + ${PART_SIZE[$i]}" | bc)"
      fi
    done

    PART_ALL_SIZE=$(echo "$DRIVE_SIZE - $PART_WO_ALL_SIZE_PRIM - $temp_size" | bc)
    echo "Part_all_size is: $PART_ALL_SIZE" | debugoutput
    if [ "$PART_ALL_SIZE" -gt $LIMIT ]; then
      PART_ALL_SIZE=$(echo "$LIMIT - $temp_size" | bc)
      [ -z $result ] && result="PART_CHANGED_ALL"
    fi
  # if we have no more than 3 partitions
  else
    PART_ALL_SIZE=$(echo "$DRIVE_SIZE - $PART_WO_ALL_SIZE" | bc)
    if [ "$PART_ALL_SIZE" -gt "$LIMIT" ]; then
      PART_ALL_SIZE="$LIMIT"
      [ -z $result ] && result="PART_CHANGED_ALL"
    fi
  fi

  for i in $(seq 1 $PART_COUNT); do
    if [ "${PART_SIZE[$i]}" == "all" ]; then
        PART_SIZE[$i]=$PART_ALL_SIZE
        echo "new size of \"all\" is now ${PART_SIZE[$i]}" | debugoutput
    fi
  done
  [ "$output" != "no_output" ] && echo $result
}

#
# Set udev rules
#
set_udev_rules() {
  # at this point we have configured networking for one and only one
  # active interface and written a udev rule for this device.
  # Normally, we could just rename that single interface.
  # But when the system boots, the other interface are found and numbered.
  # The system then tries to rename the interface to match the udev rules.
  # Under certain situations with more than two NICs, this may not end as
  # expected leaving some interfaces half-renamed (e.g. eth3-eth0)
  # So we copy the already generated udev rules from the rescue system in order
  # to have rules for all devices, no matter in which order they are found
  # during boot.
  UDEVPFAD="/etc/udev/rules.d"
  # this will probably fail if we ever have predictable networknames
  ETHCOUNT="$(find /sys/class/net/* -type l -name 'eth*' | wc -l)"
  if [ "$ETHCOUNT" -gt "1" ]; then
    cp "$UDEVPFAD"/70-persistent-net.rules "$FOLD/hdd$UDEVPFAD/"
    #Testeinbau
    if [ "$IAM" = "centos" ]; then
      # need to remove these parts of the rule for centos,
      # otherwise we get new rules with the old interface name again
      # plus a new  ifcfg- for the new rule, which duplicates
      # the config but does not match the MAC of the interface
      # after renaming. Terrible mess.
      sed -i 's/ ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL==\"eth\*\"//g' "$FOLD/hdd$UDEVPFAD/70-persistent-net.rules"
    fi
    for NIC in /sys/class/net/*; do
      INTERFACE=${NIC##*/}
      #test if the interface has a ipv4 adress
      iptest=$(ip addr show dev "$INTERFACE" | grep "$INTERFACE"$ | awk '{print $2}' | cut -d "." -f 1,2)
      #iptest=$(ifconfig $INTERFACE | grep "inet addr" | cut -d ":" -f2 | cut -d " " -f1 | cut -d "." -f1,2)
      #Separate udev-rules for openSUSE 12.3 in function "suse_fix" below !!!
      if [ -n "$iptest"  ] && [ "$iptest" != "192.168" ] && [ "$INTERFACE" != "eth0" ] && [ "$INTERFACE" != "lo" ]; then
        debug "# renaming active $INTERFACE to eth0 via udev in installed system"
        sed -i  "s/$INTERFACE/dummy/" "$FOLD/hdd$UDEVPFAD/70-persistent-net.rules"
        sed -i  "s/eth0/$INTERFACE/" "$FOLD/hdd$UDEVPFAD/70-persistent-net.rules"
        sed -i  "s/dummy/eth0/" "$FOLD/hdd$UDEVPFAD/70-persistent-net.rules"
        fix_eth_naming "$INTERFACE"
      fi
    done
    [ "$IAM" = 'suse' ] && suse_version="$IMG_VERSION"
    [ "$suse_version" == "123" ] && suse_netdev_fix
  fi
}

# Rename eth device (ethX to eth0)
#
fix_eth_naming() {
 if [ -n "$1" ]; then
   debug "# fix eth naming"

   # for Debian and Debian derivatives
   if [ "$IAM" = "debian" ] || [ "$IAM" = "ubuntu" ]; then
     FILE="etc/network/interfaces"
     if [ -f "$FOLD/hdd/$FILE" ]; then
       debug "# fix_eth_naming replaces $1/eth0"
       execute_chroot_command "sed -i 's/$1/eth0/g' $FILE"
     fi
   fi

   # CentOS
   if [ "$IAM" = "centos" ]; then
     FILE="/etc/sysconfig/network-scripts/ifcfg-$1"
     NEWFILE="/etc/sysconfig/network-scripts/ifcfg-eth0"
     ROUTE="/etc/sysconfig/network-scripts/route-$1"
     NEWROUTE="/etc/sysconfig/network-scripts/route-eth0"
     if [ -f "$FOLD/hdd/$FILE" ] && [ -f "$FOLD/hdd/$ROUTE" ]; then
       debug "# fix_eth_naming replaces $1 with eth0"
       execute_chroot_command "sed -i 's/$1/eth0/g' $FILE"
       execute_chroot_command "mv $FILE $NEWFILE"
       execute_chroot_command "mv $ROUTE $NEWROUTE"
     fi
   fi

   # SUSE
   if [ "$IAM" = "suse" ]; then
     FILE="/etc/sysconfig/network/ifcfg-$1"
     NEWFILE="/etc/sysconfig/network/ifcfg-eth0"
     if [ -f "$FOLD/hdd/$FILE" ]; then
       debug "# fix_eth_naming mv $FILE to $NEWFILE"
       execute_chroot_command "mv $FILE $NEWFILE"
     fi
   fi
 fi

}


suse_netdev_fix() {
# device naming in OpenSuSE 12.3 for multiple NICs is
# currently broken. (kernel and systemd disagree with each other)
# Workaround is to map the NICs to their own namespace (net0 instead of eth0)
# until the fix is released
# see https://bugzilla.novell.com/show_bug.cgi?id=809843

    FILE_NET="/etc/sysconfig/network/ifcfg-eth0"
    FILE_NET_NEW="/etc/sysconfig/network/ifcfg-net0"
    execute_chroot_command "mv $FILE_NET $FILE_NET_NEW";
    execute_chroot_command "sed -i  's/eth0/net0/g' $FILE_NET_NEW";
    sed -i  's/eth\([0-9]\)/net\1/g' "$FOLD/hdd$UDEVPFAD/70-persistent-net.rules"
}

is_private_ip() {
 if [ -n "$1" ]; then
   local first; first="$(echo "$1" | cut -d '.' -f 1)"
   local second; second="$(echo "$1" | cut -d '.' -f 2)"
   case "$first" in
     10)
       debug "detected private ip ($first.$second.x)"
       return 0
       ;;
     100)
       if [ "$second" -ge 64 ] && [ "$second" -lt 128 ]; then
         debug "detected private ip ($first.$second.x)"
         return 0
       else
         return 1
       fi
       ;;
     172)
       if [ "$second" -ge 16 ] && [ "$second" -lt 32 ]; then
         debug "detected private ip ($first.$second.x)"
         return 0
       else
         return 1
       fi
       ;;
     192)
       if [ "$second" -eq 168 ]; then
         debug "detected private ip ($first.$second.x)"
         return 0
       else
         return 1
       fi
       ;;
     *)
       return 1
       ;;
   esac
 else
  return 1
 fi
}

# netmask_cidr_conv "$SUBNETMASK"
netmask_cidr_conv() {
  oct2nils=( [255]=0 [254]=1 [252]=2 [248]=3 [240]=4 [224]=5 [192]=6 [128]=7 [0]=8 )
  local IFS='.' cidr; cidr=0
  for oct in $1; do
    cidr=$((cidr + oct2nils[oct]))
  done
  echo $cidr
}
# vim: ai:ts=2:sw=2:et
