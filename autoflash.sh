#!/bin/bash

# mkg's Phone Updater (it's propably not working for other devices - if you're lucky to have one of the google ones try changing the CODE_NAME and pray)

set -e

# Device settings

CODE_NAME="bullhead"
ARCH="arm64"
GAPPS_FLAV="8.1-pico"

# Paths

DATA="$HOME/.autoflash"
CONF="$DATA/config"
BACKUPS_STORE="$HOME/backups/$CODE_NAME"
DL_STORE="$DATA/dl/$CODE_NAME"
FLASH_TMP="/sdcard/flash_tmp"
VARS="$DATA/$CODE_NAME.vars"

# Device paths

BACKUPS_LOC="/data/media/0/TWRP/BACKUPS"

# Load conf

mkdir -p "$DATA"
touch "$CONF"
. "$CONF"
touch "$VARS"

# Preflight check

die() {
  echo "$*" 1>&2 && exit 2
}

[ -z "$PASSPHRASE" ] && die "\$PASSPHRASE missing! Add it to $CONF!"
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
  "$_ADB" "$@"
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
  curl -s "https://download.lineageos.org/api/v1/$CODE_NAME/nightly/1" | jq -c ".response[] | [ .datetime, .filename, .url ]" | sort -r | jq -sc ".[0][2]" | sed "s|\"||g"
}

latest_gapps() {
  curl -s "https://api.github.com/repos/opengapps/$ARCH/releases/latest?per_page=100" | jq -c ".assets[] | [ .browser_download_url ]" | grep "$ARCH-$GAPPS_FLAV" | grep ".zip\"\]" | jq -c ".[0]" | sed "s|\"||g"
}

latest_addonsu() {
  echo "https://mirrorbits.lineageos.org/su/addonsu-15.1-$ARCH-signed.zip"
}

latest_fdroid() {
  echo "https://f-droid.org/repo/org.fdroid.fdroid.privileged.ota_2070.zip" # from https://f-droid.org/packages/org.fdroid.fdroid.privileged.ota/
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

# And finally: the actual actions

action_unlock() {
  log "Unlocking..."
  twrp decrypt "$PASSPHRASE"
}

action_backup() {
  log "Backing up..."
  twrp backup D "$(date +%s)"
  extract_backup
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
    fastboot flash vendor vendor.img
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

    twrp wipe cache
    twrp wipe dalvik

    for t in $THINGS; do
      log "Flash $t..."
      URL=$(_get "$t-url")
      F=$(basename "$URL")
      adb push "$DL_STORE/$F" "$FLASH_TMP/$F"
      twrp install "$FLASH_TMP/$F"
      _set "$t" "$URL"
    done

    twrp wipe cache
    twrp wipe dalvik
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

log "Doing things..."
adb reboot recovery & sleep 1s # Somehow go into recovery

# Go to recovery
log "Waiting for recovery..."
adb wait-for-recovery
# Unlock
action_unlock
sleep 1s
adb wait-for-recovery
# Make a backup
action_backup
# Re-flash
action_flash

# Reboot bootloader
adb reboot bootloader
# Vendor update
action_vendor
# Reboot and enjoy
fastboot reboot
