#!/bin/bash

# mkg's Phone Updater (it's propably not working for other devices - if you're lucky to have one of the google ones try changing the CODE_NAME and pray)

set -e

die() {
  echo "$*" 1>&2 && exit 2
}

[ -z "$DEVICE" ] && die "Set the \$DEVICE env variable"

# Paths

DATA="$HOME/.autoflash"
CONF="$DATA/config"
DEV_CONF="$PWD/$DEVICE.conf"
DEV_PRIV_CONF="$DATA/$DEVICE.conf"
PACK_LOCK="/tmp/.AUTOFLASH_PACK_LOCK"

# Load conf

mkdir -p "$DATA"
touch "$CONF"
. "$CONF"
[ ! -e "$DEV_CONF" ] && touch "$DEV_CONF" && die "Edit $DEV_CONF"
. "$DEV_CONF"
[ ! -e "$DEV_PRIV_CONF" ] && touch "$DEV_PRIV_CONF" && die "Edit $DEV_PRIV_CONF"
. "$DEV_PRIV_CONF"

BACKUPS_STORE="$HOME/backups/$CODE_NAME"
DL_STORE="$DATA/dl/$CODE_NAME"
FLASH_TMP="/sdcard/flash_tmp"
VARS="$DATA/$CODE_NAME.vars"

touch "$VARS"

# Device paths

BACKUPS_LOC="/data/media/0/TWRP/BACKUPS"

# Preflight check

[ -z "$PASSPHRASE" ] && echo "\$PASSPHRASE missing! Add it to $DEV_PRIV_CONF if needed!"
which adb > /dev/null || die "No ADB binary found"
which fastboot > /dev/null || die "No fastboot binary found"

# Helper fncs

_get() {
  cat "$VARS" | grep "$1=" | sed "s|^$1=||"
}

_set() {
  touch "$VARS"
  PRE=$(cat "$VARS" | grep -v "^$1=" || echo)
  echo "$PRE
$1=$2" > "$VARS"
}

# ADB helpers

_ADB=$(which adb)
_FASTBOOT=$(which fastboot)

adb() {
  "$_ADB" -d "$@"
}

fastboot() {
  "$_FASTBOOT" "$@"
}

twrp() {
  adb shell twrp "$@"
}

_adb() {
  adb "$@" | tr "\r" " "
}

_cmd() {
 adb shell "$@"
}

_sh() {
 _adb shell "$@"
}

log() {
  echo "$(date +%s): $*"
}

# Stuff to get updates

latest_image() {
  curl -s "https://download.lineageos.org/api/v1/$CODE_NAME/nightly/1?version=$LOS" | jq -c ".response[] | [ .datetime, .filename, .url ]" | sort -r | jq -sc ".[0][2]" | sed "s|\"||g"
}

latest_gapps() {
  curl -s "https://api.github.com/repos/opengapps/$ARCH/releases/latest?per_page=100" | jq -c ".assets[] | [ .browser_download_url ]" | grep "$ARCH-$GAPPS_FLAV" | grep ".zip\"\]" | jq -c ".[0]" | sed "s|\"||g"
}

latest_addonsu() {
  echo "https://mirrorbits.lineageos.org/su/addonsu-$LOS-$ARCH-signed.zip"
}

latest_fdroid() {
  curl -s https://f-droid.org/packages/org.fdroid.fdroid.privileged.ota/ | grep -o "https.*.zip" | sort -r | head -n 1
}

latest_factory() {
  curl -s "https://developers.google.com/android/images" | grep "https://dl.google.com/dl/android/aosp/$CODE_NAME" | tail -n 1 | sed -r "s|.*\"(.+)\".*|\1|g"
}

latest_twrp() {
  echo "$PRIVATE_MIRROR/twrp-3.2.1-0-$CODE_NAME.img" # echo "https://eu.dl.twrp.me/bullhead/twrp-3.2.1-0-bullhead.img" # from https://eu.dl.twrp.me/bullhead/
}

THINGS=""
NEEDS_PATCH=""

update_prepare() {
  WHAT="$1"
  THINGS="$THINGS $WHAT"
  CURRENT=$(_get "$1")
  LATEST=$($2)

  CURRENTF=$(basename "$CURRENT")
  LATESTF=$(basename "$LATEST")

  log "Current $WHAT: $CURRENTF"
  log "Latest  $WHAT: $LATESTF"
  if [ "$CURRENTF" != "$LATESTF" ]; then
    log "Needs update..."

    if [ ! -z "$CURRENT" ]; then
      log "RM $CURRENTF"
      rm -f "$DL_STORE/$CURRENTF"
      rm -f "$DL_STORE/$CURRENTF.ok"
    fi

    if [ ! -e "$DL_STORE/$LATESTF.ok" ]; then
      log "DL $LATEST"
      mkdir -p "$DL_STORE"
      wget "$LATEST" -O "$DL_STORE/$LATESTF"
      touch "$DL_STORE/$LATESTF.ok"
    fi

    log "Add $WHAT to NEEDS_PATCH"
    NEEDS_PATCH="$NEEDS_PATCH $WHAT"
    _set "$WHAT-url" "$LATEST"
  fi
}

update_prepare_v() {
  WHAT="$1"
  THINGS_V="$THINGS_V $WHAT"
  CURRENT=$(_get "$1")
  LATEST=$($2)

  CURRENTF=$(basename "$CURRENT")
  LATESTF=$(basename "$LATEST")

  log "Current $WHAT: $CURRENTF"
  log "Latest  $WHAT: $LATESTF"
  if [ "$CURRENTF" != "$LATESTF" ]; then
    log "Needs update..."

    if [ ! -z "$CURRENT" ]; then
      log "RM $CURRENTF"
      rm -f "$DL_STORE/$CURRENTF"
      rm -f "$DL_STORE/$CURRENTF.ok"
    fi

    if [ ! -e "$DL_STORE/$LATESTF.ok" ]; then
      log "DL $LATEST"
      mkdir -p "$DL_STORE"
      wget "$LATEST" -O "$DL_STORE/$LATESTF"
      touch "$DL_STORE/$LATESTF.ok"
    fi

    log "Add $WHAT to NEEDS_PATCH_V"
    NEEDS_PATCH_V="$NEEDS_PATCH_V $WHAT"
    _set "$WHAT-url" "$LATEST"
  fi
}

# Tool funcs

extract_folder() {
  log "Extract $1 to $2..."
  _sh "mkdir" "-p" "$1"
  folder=$(_sh "find" "$1/" "-type" "d")
  file=$(_sh "find" "$1/" "-type" "f")
  for f in $folder; do
    outf=${f/"$1"/"$2"}
    mkdir -p "$outf"
  done
  for f in $file; do
    outf=${f/"$1"/"$2"}
    log "pull $f"
    adb pull -a "$f" "$outf"
  done
}

extract_backup() {
  log "Extracting backups..."
  extract_folder "$BACKUPS_LOC" "$BACKUPS_STORE"
  log "Deleting on device..."
  _sh rm -rf "$BACKUPS_LOC"
}

pack_dir() {
  nice -n100 ionice -c3 tar cf "$1.tar.gz" "$1" -I pigz
  nice -n100 ionice -c3 rm -rf "$1"
}

pack_task() {
  dir="$1"
  pushd "$dir"
  for dir in $(dir); do
    if [ -d "$dir" ]; then
      pack_dir "$dir"
    fi
  done
  popd
}

pack_all() {
  if [ -e "$PACK_LOCK" ]; then
    if [ -e "/proc/$(cat $PACK_LOCK)" ]; then
      echo "Will not pack backups: Packing currently locked!" 1>&2
      return
    fi
  fi
  echo "$$" > "$PACK_LOCK"
  while [ ! -z "$1" ]; do
    pack_task "$1"
    shift
  done
  rm "$PACK_LOCK"
}

# And finally: the actual actions

action_unlock() {
  log "Unlocking..."
  twrp decrypt "$PASSPHRASE"
}

action_backup() {
  log "Backing up..."
  twrp backup D "$(date +%s)"
  extract_backup
  log "Packing backups in background..."
  pack_all "$BACKUPS_STORE/$(dir $BACKUPS_STORE)"  & #> /dev/null &
  log "Started"
}

action_backup_direct() {
  BF="$BACKUPS_STORE/$(_adb get-serialno)/$(date +%s).ab"
  log "Backing up to $BF..."
  mkdir -p "$(dirname $BF)"
  # Do a dummy install to "unlock"
  twrp install dummy > /dev/null 2> /dev/null
  adb backup -f "$BF" --twrp --compress data
}

action_vendor() {
  log "Vendor updates:$NEEDS_PATCH_V"
  if echo "$NEEDS_PATCH_V" | grep "factory" > /dev/null; then
    log "Patching factory..."
    FA_URL=$(_get factory-url)
    FA=$(basename "$FA_URL")
    TT=$(echo "$FA" | sed "s|.zip||g" | sed -r "s|(.+)-(.+)-.+-.+|\1-\2|g")
    FA="$DL_STORE/$FA"
    TMP="/tmp/$$.factory"
    mkdir -p "$TMP"
    pushd "$TMP"
    unzip "$FA"
    pushd "$TT"
    bash -ex flash-base.sh
    unzip "$(dir -w 1 | grep 'image*')" -x system.img
    if [ -e "vendor.img" ]; then
      fastboot flash vendor vendor.img
    fi
    popd
    popd
    rm -rf "$TMP"
    _set factory "$FA_URL"
  fi
  if echo "$NEEDS_PATCH_V" | grep "twrp" > /dev/null; then
    log "Patching twrp..."
    TW_URL=$(_get twrp-url)
    TW=$(basename "$TW_URL")
    TW="$DL_STORE/$TW"
    fastboot flash recovery "$TW"
    _set twrp "$TW_URL"
  fi
}

action_flash() {
  if [ ! -z "$NEEDS_PATCH" ]; then
    log "Flashing to update$NEEDS_PATCH..."
    _cmd rm -rf "$FLASH_TMP"
    _cmd mkdir "$FLASH_TMP"
    twrp wipe system

    if [ ! -z "$GAPPS_CONF" ]; then
      log "Writing custom gapps config..."
      GCONF="/tmp/$$.gapps-conf"
      echo -e "$GAPPS_CONF" > "$GCONF"
      adb push "$GCONF" "$FLASH_TMP/.gapps-config"
      rm "$GCONF"
    fi

    for t in $THINGS; do
      log "Flash $t..."
      URL=$(_get "$t-url")
      F=$(basename "$URL")
      adb push "$DL_STORE/$F" "$FLASH_TMP/$F"
      twrp install "$FLASH_TMP/$F"
      _set "$t" "$URL"
    done

    if [ ! -z "$WIPE_FLASH_TMP" ]; then
      log "Clean up $FLASH_TMP..."
      for t in $THINGS; do
        URL=$(_get "$t-url")
        F=$(basename "$URL")
        _cmd rm "$FLASH_TMP/$F"
      done
    fi
  fi
}

# Final code

# Check for updates
update_prepare los latest_image
update_prepare su latest_addonsu
update_prepare fdroid latest_fdroid
update_prepare gapps latest_gapps

update_prepare_v factory latest_factory
update_prepare_v twrp latest_twrp

log "Trying to boot into recovery..."
adb reboot recovery & sleep 1s # Somehow go into recovery

# Go to recovery
log "Waiting for recovery..."
adb wait-for-recovery
sleep 1s
# Unlock
if [ ! -z "$PASSPHRASE" ]; then
  action_unlock
fi
sleep 1s
adb wait-for-recovery
# Make a backup
action_backup_direct
# Re-flash
action_flash

if [ ! -z "$NEEDS_PATCH_V" ]; then # If vendor updates, reboot bootloader
  # Reboot bootloader
  adb reboot bootloader
  # Vendor update
  action_vendor

  # Reboot into system from fastboot
  fastboot reboot
else # Else reboot system
  # Reboot into system from adb
  adb reboot
fi

log "DONE!"
