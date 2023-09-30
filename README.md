# autosnap-script
A simple shell script for automatically creating and cleaning BTRFS subvolume snapshots. Works on my Arch Linux. Please carefully review the code before using it, as it might corrupt your data!

## Required

- BTRFS filesystem + Systemd-boot

## Features

### `./autosnap.sh`

1. Automatically mount `@.snapshots` subvolume to `/.snapshots`.
2. Create a directory using today's date (e.g. `/.snapshots/autosnap/2023-09-30`).
3. Create a snapshot using `btrfs subvolume snapshot / "$SNAPSHOT_DIR/$CURRENT_DATE/@$CURRENT_TIME"` (e.g. `/.snapshots/autosnap/2023-09-30/@09-00`).
4. If `$SNAPSHOT_DIR/$CURRENT_DATE` contains a snapshots created within the past hour, it will automatically exit without any operation.
5. If a new snapshot is created, the script also checks the number of snapshots in yesterday's directory, and if it is greater than 1, it keeps the oldest one and deletes all the rest.
6. Unmount `@.snapshots` subvolume and exit.

You can change the following variables at the beginning of the script.

```
TIMEZONE="Asia/Shanghai"
MOUNT_POINT="/.snapshots/"
SNAPSHOT_DIR="/.snapshots/autosnap"
SUBVOLUME_NAME="@.snapshots"
```

### `./autosnap.sh now`

Skip step 4 above and create a snapshot now.

### `./autosnap.sh list`

Print all snapshots in `/.snapshots/autosnap` using `tree`.

### `./autosnap.sh list all`

Print all snapshots in `/.snapshots/autosnap` as a list.

### `./autosnap.sh clean`

Delete all snapshots created a week ago.

### `./autosnap.sh clean all`

Delete all snapshots except the one currently mounted at `/`.

### `./autosnap.sh mount`

mount `@.snapshots` subvolume to `/.snapshots` and exit. Do not automatically unmount the snapshots subvolume so that the user can manually inspect it.

### `./autosnap.sh mount 2023-09-30/@09-00`

Restore to specified snapshot.

Check if the snapshot specified in the argument exists. If it does, modify the mount options in the Systemd-boot config file (`/boot/loader/entries/arch.conf`) so that the snapshot will be mounted on the next reboot.

You can change the following variables at the beginning of the script.

```
BOOT_FILE="/boot/loader/entries/arch.conf"
```

