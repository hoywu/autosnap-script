# autosnap-script
A simple shell script for automatically creating and cleaning BTRFS subvolume snapshots. Works on my Arch Linux. Please carefully review the code before using it, as it might corrupt your data!

## Required

- BTRFS filesystem + Systemd-boot

## Recommended subvolume layout

| subvolume   | mountpoint            |
| ----------- | --------------------- |
| @           | /                     |
| @home       | /home                 |
| @log        | /var/log              |
| @pkg        | /var/cache/pacman/pkg |
| @.snapshots | /.snapshots           |
| @docker     | /var/lib/docker       | 

## Features

You can change the following variables at the beginning of the script.

```
TIMEZONE="Asia/Shanghai"
MOUNT_POINT="/.snapshots/"
SNAPSHOT_DIR="/.snapshots/autosnap"
SUBVOLUME_NAME="@.snapshots"
BOOT_FILE="/boot/loader/entries/arch.conf"
```

### `./autosnap.sh`

1. Automatically mount `@.snapshots` subvolume to `/.snapshots`.
2. Create a directory using today's date (e.g. `/.snapshots/autosnap/2023-09-30`).
3. If `$SNAPSHOT_DIR/$CURRENT_DATE` contains a snapshots created within the past hour, it will unmount `@.snapshots` and exit without any operation.
4. Otherwise, Create a snapshot using `btrfs subvolume snapshot / "$SNAPSHOT_DIR/$CURRENT_DATE/@$CURRENT_TIME"` (e.g. `/.snapshots/autosnap/2023-09-30/@09-00`).
5. Unmount `@.snapshots` subvolume and exit.

### `./autosnap.sh now`

Skip step 3 above and create a snapshot now.

### `./autosnap.sh list`

Print all snapshots in `/.snapshots/autosnap` using `tree`.

### `./autosnap.sh list all`

Print all snapshots in `/.snapshots/autosnap` as a list.

### `./autosnap.sh clean`

Delete all snapshots created a week ago.

### `./autosnap.sh clean all`

Delete all snapshots except the one currently mounted at `/`.

### `./autosnap.sh clean yesterday`

Check the number of snapshots in yesterday's directory, and if it is greater than 1, keep the oldest one and delete all the rest.

### `./autosnap.sh mount`

Mount `@.snapshots` subvolume to `/.snapshots` and exit. It will not automatically unmount the snapshots subvolume so that the user can manually inspect it.

### `./autosnap.sh mount 2023-09-30/@09-00`

Mount a specified snapshot.

Check if the snapshot specified in the argument exists. If it does, create a Systemd-boot config file backup (e.g. `/boot/loader/entries/arch.conf.202309301800.bak`) and then modify the mount options in the config file so that the snapshot will be mounted on the next reboot.

### `./autosnap.sh restore 2023-09-30/@09-00`

Restore to a specified snapshot.

1. Create a snapshot. (`./autosnap.sh now`)
2. Backup the snapshot specified in the argument. (e.g. `btrfs subvolume snapshot "2023-09-30/@09-00" "2023-09-30/@09-00.bak"`)
3. Mount to the specified snapshot. (e.g. `./autosnap.sh mount 2023-09-30/@09-00`)

