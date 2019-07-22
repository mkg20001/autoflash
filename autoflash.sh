#!/bin/bash

# mkg's Phone Updater (it's propably not working for other devices - if you're lucky to have one of the google ones try changing the CODE_NAME and pray)

set -e

die() {
  echo "$*" 1>&2 && exit 2
}

contains() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

[ -z "$DEVICE" ] && die "Set the \$DEVICE env variable"

# Paths

SELF=$(dirname $(readlink -f "$0"))
DATA="$HOME/.autoflash"
CONF="$DATA/config"
DEV_CONF="$PWD/$DEVICE.conf"
DEV_PRIV_CONF="$DATA/$DEVICE.conf"
if [ -z "$ALT_TMP" ]; then
  TMP="/tmp/autoflash-$DEVICE"
else
  TMP="$ALT_TMP/autoflash-$DEVICE"
fi
PACK_LOCK="$TMP/.AUTOFLASH_PACK_LOCK"

# Load conf

MAGISK=false

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
  echo $(cat "$VARS" | grep "$1=" | sed "s|^$1=||")
}

_set() {
  touch "$VARS"
  PRE=$(cat "$VARS" | grep -v "^$1=" || echo)
  echo "$PRE
$1=$2" | sort > "$VARS"
}

# ADB helpers

_ADB=$(which adb)
_FASTBOOT=$(which fastboot)

adb() {
  if [ ! -z "$ANDROID_SERIAL" ]; then
    "$_ADB" -s "$ANDROID_SERIAL" -d "$@"
  else
    "$_ADB" -d "$@"
  fi
}

fastboot() {
  if [ ! -z "$ANDROID_SERIAL" ]; then
    "$_FASTBOOT" -s "$ANDROID_SERIAL" "$@"
  else
    "$_FASTBOOT" "$@"
  fi
}

twrp() {
  adb shell twrp "$@"
  sleep 10s
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

_dl() {
  URL="$1"
  URLF=$(basename "$URL")
  while [ ! -e "$DL_STORE/$URLF.ok" ]; do
    log "DL $URL"
    mkdir -p "$DL_STORE"
    if echo "$URL" | grep "twrp-" > /dev/null 2> /dev/null; then
      TWH=(--header='User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:63.0) Gecko/20100101 Firefox/63.0' --header='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' --header="Referer: $URL.html" --header='DNT: 1' --header='Connection: keep-alive' --header='Upgrade-Insecure-Requests: 1')
      (wget "$URL" "${TWH[@]}" -O "$DL_STORE/$URLF" --continue && touch "$DL_STORE/$URLF.ok") || (log "Download failed. Trying again in 10s..." && sleep 10s)
    else
      (wget "$URL" -O "$DL_STORE/$URLF" --continue && touch "$DL_STORE/$URLF.ok") || (log "Download failed. Trying again in 10s..." && sleep 10s)
    fi
  done
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

latest_factory_google() {
  curl -s "https://developers.google.com/android/images" | grep "https://dl.google.com/dl/android/aosp/$CODE_NAME" | tail -n 1 | sed -r "s|.*\"(.+)\".*|\1|g"
}

latest_twrp() {
  VER=$(curl -s "https://eu.dl.twrp.me/$DEVICE/" | grep .img | grep -o ">twrp-.*img" | grep -o "twrp-.*" | sort -r | head -n 1)
  echo "https://eu.dl.twrp.me/$DEVICE/$VER"
}

lastest_magisk() {
  curl -s "https://api.github.com/repos/topjohnwu/Magisk/releases?per_page=100" | jq -r "map(select(.name | contains(\"Magisk v\")))[0].assets[] | .browser_download_url" | grep -v uninstaller
}

create_magisk_manager_zip() {
  LATEST_MANAGER=$(curl -s "https://api.github.com/repos/topjohnwu/Magisk/releases?per_page=100" | jq -r "map(select(.name | contains(\"Magisk Manager\")))[0].assets[] | .browser_download_url")
  CUR_MANAGER=$(_get mgmg)
  MG_SAFE=$(basename "$LATEST_MANAGER" | sed -r "s|[^a-zA-Z0-9]|.|g")
  MG_ZIP="$DL_STORE/magisk_manager_zip.$MG_SAFE.zip"
  if [ "$CUR_MANAGER" != "$LATEST_MANAGER" ] || [ ! -e "$MG_ZIP" ]; then
    log "MAGISK Update Magisk Manger: $LATEST_MANAGER"
    rm -f $DL_STORE/magisk_manager_zip.*
    _dl "$LATEST_MANAGER"
    T="$TMP/magisk"
    rm -rf "$T"
    mkdir -p "$(dirname $T)"
    cp -rpv "$SELF/magisk-zip" "$T"
    mv -v "$DL_STORE/$URLF" "$T/MagiskManager.apk"
    rm "$DL_STORE/$URLF.ok"
    pushd "$T"
    zip ../mgmg.zip -r .
    popd
    mv -v "$TMP/mgmg.zip" "$MG_ZIP"
    rm -rf "$T"
    touch "$MG_ZIP.ok"
    log "MAGISK OK"
    _set mgmg "$LATEST_MANAGER"
  fi
}

latest_magisk_manager() {
  echo "http://$MG_ZIP"
}

create_aurora_services_zip() {
  LATEST_SERVICES=$(curl -s https://gitlab.com/AuroraOSS/AuroraServices/-/tags | grep -o "/AuroraOSS/.*apk" | head -n 1)
  CUR_SERVICES=$(_get aserv)
  AS_SAFE=$(basename "$LATEST_SERVICES" | sed -r "s|[^a-zA-Z0-9]|.|g")
  AS_ZIP="$DL_STORE/aurora_services_zip.$AS_SAFE.zip"
  if [ "$CUR_SERVICES" != "$LATEST_SERVICES" ] || [ ! -e "$AS_ZIP" ]; then
    log "AURORA Update Aurora Services: $LATEST_SERVICES"
    rm -f $DL_STORE/aurora_services_zip.*
    _dl "$LATEST_SERVICES"
    T="$TMP/services"
    rm -rf "$T"
    mkdir -p "$(dirname $T)"
    cp -rpv "$SELF/services-zip" "$T"
    mv -v "$DL_STORE/$URLF" "$T/AuroraServices.apk"
    rm "$DL_STORE/$URLF.ok"
    pushd "$T"
    zip ../aserv.zip -r .
    popd
    mv -v "$TMP/aserv.zip" "$AS_ZIP"
    rm -rf "$T"
    touch "$AS_ZIP.ok"
    log "AURORA OK"
    _set aserv "$LATEST_SERVICES"
  fi
}

latest_aurora_services() {
  echo "http://$AS_ZIP"
}

THINGS=""
NEEDS_PATCH=""
NEEDS_PATCH_V=""

_update_prepare() {
  _NEED="$1"
  _THINGS="$2"

  WHAT="$3"
  eval "$_THINGS='${!_THINGS} $WHAT'"
  CURRENT=$(_get "$3")
  LATEST=$($4)

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

    log "Add $WHAT to $_NEED"
    eval "$_NEED='${!_NEED} $WHAT'"
    _set "$WHAT-url" "$LATEST"
  fi

  _dl "$LATEST"
}

update_prepare() {
  _update_prepare "NEEDS_PATCH" "THINGS" "$@"
}

update_prepare_v() {
  _update_prepare "NEEDS_PATCH_V" "THINGS_V" "$@"
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
  i=0
  while echo "$OUT" | grep "Failed to decrypt" > /dev/null || [ -z "$OUT" ]; do
    i=$(( $i + 1 ))
    log "Unlocking ($i/3)..."
    OUT=$(twrp decrypt "$PASSPHRASE")
    echo "$OUT"
    if [ "$i" == "3" ]; then
      log "ERROR: FAILED TO UNLCOK" 2>&1
      exit 2
    fi
  done
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
  sleep 5s
}

action_vendor() {
  log "Vendor updates:$NEEDS_PATCH_V"

  if echo "$NEEDS_PATCH_V" | grep "factory_google" > /dev/null; then
    log "Patching factory_google..."
    FA_URL=$(_get factory-url)
    FA=$(basename "$FA_URL")
    TT=$(echo "$FA" | sed "s|.zip||g" | sed -r "s|(.+)-(.+)-.+-.+|\1-\2|g")
    SHASTART=$(echo "$FA" | sed -r "s|.+-([a-z0-9]+).zip$|\1|g")
    FA="$DL_STORE/$FA"
    TMP="$TMP/$$.factory"
    mkdir -p "$TMP"
    pushd "$TMP"
    if [[ "$(sha256sum $FA)" != "$SHASTART"* ]]; then
      echo "Checksum validation failed!"
      echo "Expected: $SHASTART..."
      echo "Got: $(sha256sum $FA)"
      exit 2
    fi
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
    _cmd mkdir -p "$FLASH_TMP"

    FILES=$(_sh "find" "$FLASH_TMP/" "-type" "f")
    FILES=$(echo $FILES)
    FILES=($FILES) # turn into array

    KEEP_FILES=()
    THING_FILES=()

    for t in $THINGS; do
      URL=$(_get "$t-url")
      F=$(basename "$URL")
      KEEP_FILES=("${KEEP_FILES[@]}" "$FLASH_TMP/$F")
      THING_FILES=("${THING_FILES[@]}" "$F")
    done

    for f in "${FILES[@]}"; do # remove unneeded files
      if ! contains "$f" "${KEEP_FILES[@]}"; then
        echo "RM $f"
        _cmd rm -f "$f"
      fi
    done

    for f in "${THING_FILES[@]}"; do # push missing
      if ! contains "$FLASH_TMP/$f" "${FILES[@]}"; then
        echo "PUSH $f"
        adb push "$DL_STORE/$f" "$FLASH_TMP/$f"
      fi
    done

    if [ ! -z "$GAPPS_CONF" ]; then
      log "Writing custom gapps config..."
      GCONF="$TMP/$$.gapps-conf"
      echo -e "$GAPPS_CONF" > "$GCONF"
      adb push "$GCONF" "$FLASH_TMP/.gapps-config"
      rm "$GCONF"
    fi

    if [ ! -z "$BAKA" ]; then
      echo -n "$(log Backup running...)"
      while [ -e "/proc/$BAKA" ]; do
        echo -n .
        sleep 5s
      done
      echo
    fi

    twrp wipe /system

    for t in $THINGS; do
      log "Flash $t..."
      URL=$(_get "$t-url")
      F=$(basename "$URL")
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

action_pull_updates() {
  update_prepare los latest_image
  if $MAGISK; then
    update_prepare magisk lastest_magisk
    create_magisk_manager_zip
    update_prepare magisk_manager latest_magisk_manager
  else
    update_prepare su latest_addonsu
  fi

  create_aurora_services_zip
  update_prepare aurora_services latest_aurora_services

  update_prepare fdroid latest_fdroid
  update_prepare gapps latest_gapps

  case "$VENDOR_MODE" in
    google)
      update_prepare_v factory_google latest_factory_google
      update_prepare_v twrp latest_twrp
      ;;
    oneplus)
      update_prepare_v twrp latest_twrp
      ;;
  esac
}

# Final code

if [ ! -z "$PULL_ONLY" ]; then
  log "Pulling updates..."
  action_pull_updates
  exit
fi

log "Trying to boot into recovery..."
adb reboot recovery & sleep 1s # Somehow go into recovery

# Go to recovery
log "Waiting for recovery..."
adb "wait-for-recovery"
sleep 1s
# Unlock
if [ ! -z "$PASSPHRASE" ]; then
  action_unlock
fi
sleep 1s
adb "wait-for-recovery"
# Make a backup
if [ -z "$SKIP_BACKUP" ]; then
  action_backup_direct &
  BAKA=$!
  sleep 10s
fi

# Check for updates
action_pull_updates

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

rm -rfv "$TMP"
