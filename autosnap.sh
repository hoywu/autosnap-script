#!/bin/bash

TIMEZONE="Asia/Shanghai"
MOUNT_POINT="/.snapshots/"
SNAPSHOT_DIR="/.snapshots/autosnap"
SUBVOLUME_NAME="@.snapshots"

BOOT_FILE="/boot/loader/entries/arch.conf"

# 设置时区并获取当前日期和时间
CURRENT_DATE=$(TZ=$TIMEZONE date +'%Y-%m-%d')
CURRENT_TIME=$(TZ=$TIMEZONE date +'%H-%M-%S')
CURRENT_HOUR=$(TZ=$TIMEZONE date +'%H')
CURRENT_MINUTE=$(TZ=$TIMEZONE date +'%M')
CURRENT_SECOND=$(TZ=$TIMEZONE date +'%S')

MOUNT_DEVICE=$(df / | tail -n 1 | awk '{print $1}')                   # 获取根分区设备
sudo mount -o subvol=${SUBVOLUME_NAME} "$MOUNT_DEVICE" "$MOUNT_POINT" # 挂载 @.snapshots 子卷

suc() {
  echo -e "\033[32m$1\033[0m"
}
war() {
  echo -e "\033[33m$1\033[0m"
}
err() {
  echo -e "\033[31m$1\033[0m"
}

snap_now() {
  if [ "$2" == "" ]; then
    SNAP="$SNAPSHOT_DIR/$CURRENT_DATE/@$CURRENT_TIME"
  else
    SNAP=$2
  fi
  sudo btrfs subvolume snapshot "$1" "$SNAP"
}

clean_prev_date() {
  # 获取前一天的日期
  PREVIOUS_DATE=$(TZ=$TIMEZONE date -d "yesterday" +'%Y-%m-%d')

  # 检查前一天的日期目录是否存在
  if [ -d "$SNAPSHOT_DIR/$PREVIOUS_DATE" ]; then
    # 检查前一天日期目录中的快照数量
    DIR_COUNT=$(ls $SNAPSHOT_DIR/$PREVIOUS_DATE | wc -l)

    # 如果快照数量大于1，则保留时间最早的一个，删除其余所有快照
    if [ $DIR_COUNT -gt 1 ]; then
      EARLIEST_SNAPSHOT=$(find "$SNAPSHOT_DIR/$PREVIOUS_DATE" -maxdepth 1 -mindepth 1 ! -name ".*" | sort | head -n 1)
      for DIR in "$SNAPSHOT_DIR/$PREVIOUS_DATE"/@*; do
        if [ "$DIR" != "$EARLIEST_SNAPSHOT" ]; then
          sudo btrfs subvolume delete "$DIR"
        fi
      done
    fi
  fi
}

check_snap_exists() {
  # 检查指定快照是否存在
  if [ ! -d "$SNAPSHOT_DIR/$1" ]; then
    err "=> Snapshot $SNAPSHOT_DIR/$1 does not exist."
    return 1
  fi
  return 0
}

mount_snap() {
  # 挂载指定快照
  check_snap_exists $1
  if [ $? -ne 0 ]; then
    return 1
  fi
  cp -f ${BOOT_FILE} "${BOOT_FILE}.$(TZ=$TIMEZONE date +'%Y%m%d%H%M%S').bak"
  awk -i inplace -v snap="subvol=${SUBVOLUME_NAME}/${SNAPSHOT_DIR##*/}/$1" '{gsub(/subvol=[^ ]*/, snap); print}' ${BOOT_FILE}
  cat ${BOOT_FILE}
  suc "=> Systemd-boot config updated. Check the above config before reboot."
  return 0
}

clean_exit() {
  # 清理 SNAPSHOT_DIR 中的空文件夹
  find "$SNAPSHOT_DIR" -maxdepth 1 -mindepth 1 ! -name ".*" -type d -empty -exec echo "Clean: {}" \; -delete
  # 卸载 @.snapshots 子卷
  while mountpoint -q "$MOUNT_POINT"; do
    sudo umount "$MOUNT_POINT"
    #sleep 1
  done
  exit $1
}

# 检查执行参数
if [ "$1" == "list" ]; then

  if [ "$2" == "all" ]; then
    # 列表列出所有快照
    find ${SNAPSHOT_DIR} -maxdepth 2 -mindepth 2 ! -name ".*"
    clean_exit 0
  fi

  # 默认以树形结构列出所有快照
  tree -L 2 "$SNAPSHOT_DIR"
  clean_exit 0

elif [ "$1" == "clean" ]; then

  if [ "$2" == "all" ]; then
    # 清理除当前挂载中的快照外的所有快照
    war "=> Clean all snapshots except current subvolume. Are you sure? [y/N] \c"
    read -r confirm
    echo -n -e "\033[0m"
    if [[ "$confirm" != "y" ]]; then
      clean_exit 0
    fi
    CURRENT_SUBVOLUME=$(mount | grep " / " | sed -n -e 's/.*subvol=\/\?\([^,)]*\).*/\1/p' | sed -n -e 's/.*\(\/.*\/.*\)/\1/p')
    CURRENT_SUBVOLUME=${SNAPSHOT_DIR}${CURRENT_SUBVOLUME}
    find ${SNAPSHOT_DIR} -maxdepth 2 -mindepth 2 ! -name ".*" | while read -r snap; do
      if [ "$snap" != "$CURRENT_SUBVOLUME" ]; then
        sudo btrfs subvolume delete "$snap"
      fi
    done
    clean_exit 0
  fi

  if [ "$2" == "yesterday" ]; then
    # 清理前一天的快照目录
    clean_prev_date
    clean_exit 0
  fi

  # 清理一周前的所有快照
  ONE_WEEK_AGO=$(TZ=$TIMEZONE date -d "1 week ago" +'%Y-%m-%d')
  for DIR in "$SNAPSHOT_DIR"/*; do
    if [ -d "$DIR" ]; then
      DIR_DATE=$(basename "$DIR")
      if [[ "$DIR_DATE" < "$ONE_WEEK_AGO" ]]; then
        find "$DIR" -maxdepth 1 -mindepth 1 ! -name ".*" -exec sudo btrfs subvolume delete {} \;
      fi
    fi
  done
  clean_exit 0

elif [ "$1" == "mount" ]; then

  if [ "$2" != "" ]; then
    # 挂载指定快照
    mount_snap $2
    clean_exit $?
  fi

  # 仅挂载快照子卷
  suc "=> Mount subvolume ${SUBVOLUME_NAME} to ${MOUNT_POINT}"
  exit 0

elif [ "$1" == "restore" ]; then

  if [ "$2" != "" ]; then
    # 恢复到指定快照
    check_snap_exists $2
    if [ $? -ne 0 ]; then
      clean_exit 1
    fi

    # 备份当前
    suc "=> Backup current subvolume..."
    snap_now /

    # 备份要恢复的快照
    if [ ! -d "$SNAPSHOT_DIR/$2.bak" ]; then
      suc "=> Backup snapshot $2..."
      snap_now "$SNAPSHOT_DIR/$2" "$SNAPSHOT_DIR/$2.bak"
    else
      war "=> Snapshot $2.bak already exists, skip backup."
    fi

    # 恢复快照
    suc "=> Mount snapshot $2..."
    mount_snap $2
    clean_exit $?
  fi

  err "=> Please specify a snapshot to restore."
  clean_exit 1
fi

# 尝试创建今日快照目录
sudo mkdir -p "$SNAPSHOT_DIR/$CURRENT_DATE"

# 检查最近的快照时间
if [ "$1" != "now" ]; then
  LATEST_SNAPSHOT=$(find "$SNAPSHOT_DIR/$CURRENT_DATE" -maxdepth 1 -mindepth 1 ! -name ".*" | sort | tail -n 1)
  if [ -n "$LATEST_SNAPSHOT" ]; then
    LATEST_TIME=$(basename "$LATEST_SNAPSHOT" | cut -d'@' -f2)
    TIME=${LATEST_TIME//-/:}
    LATEST_HOUR=$(date -d "$TIME" +'%H')
    LATEST_MINUTE=$(date -d "$TIME" +'%M')
    LATEST_SECOND=$(date -d "$TIME" +'%S')

    # 计算时间差
    CURRENT_SECONDS=$((10#$CURRENT_HOUR * 3600 + 10#$CURRENT_MINUTE * 60 + 10#$CURRENT_SECOND))
    LATEST_SECONDS=$((10#$LATEST_HOUR * 3600 + 10#$LATEST_MINUTE * 60 + 10#$LATEST_SECOND))
    TIME_DIFF=$((CURRENT_SECONDS - LATEST_SECONDS))

    # 如果距离上一次快照不足1小时，则退出
    if [ $TIME_DIFF -lt 3600 ]; then
      suc "=> Last snapshot was taken less than 1 hour ago, skipping."
      clean_exit 0
    fi
  fi
fi

# 如果满足条件，则创建新的快照
snap_now /
