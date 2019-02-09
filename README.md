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

## What is supported?

Currently the following devices are supported:
 - Google Nexus 5x (bullhead)
 - Google/Asus Nexus Player (fugu)
 - OnePlus One (bacon)

_Coincidently_ they also happen to be the devices I own ;) (All of those are tested to work with this script)

Feel free to add your own devices via PRs, but don't create feature request issues.

## Why publish?

Some people may find it useful for themselves.
