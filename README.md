# autoflash

My tiny update script for my phone

## Magisk

To enable magisk, add `MAGISK=true` to `$HOME/.autoflash/$DEVICE.conf`

## Why

### Because doing it manually got annoying

## What does it do?

Download, install and update:
 - Latest vendor image, if supported
 - Latest TWRP
 - Latest LineageOS
 - Latest F-Droid privileged OTA
 - Latest addon su for LinageOS
 - Latest OpenGApps pico

Note that the last 4 items get updated by doing a full re-flash of the system partion (takes longer than just flashing them individually, but this keeps the system partion cleaner)

## Other nice features:

 - Parallel flashing: Add the `ANDROID_SERIAL=<your-serial>` parameter in front of the command to safely flash multiple phones in parallel
 - Backups: Before every flash a backup of the data partition is taken
 - Robust and well tested: Used in production for over a year. My devices are living proof that this script won't brick yours!

## What is supported?

Currently the following devices are supported:
 - Google Nexus 5x (bullhead)
 - Google/Asus Nexus Player (fugu)
 - OnePlus One (bacon)

_Coincidently_ they also happen to be the devices I own ;) (All of those are tested to work with this script)

Feel free to add your own devices via PRs, but don't create device request issues as I can't test any of those devices.

## Why publish?

Some people may find it useful for themselves.
