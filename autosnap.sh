#!/usr/bin/env bash

# 设置常量
readonly TIMEZONE="Asia/Shanghai"
readonly MOUNT_DEVICE=$(df / | awk 'END{print $1}') # 获取根分区设备
readonly MOUNT_POINT="/.snapshots/"
readonly SNAPSHOT_DIR="/.snapshots/autosnap"
readonly SUBVOLUME_NAME="@.snapshots"

readonly BOOT_FILE="/boot/loader/entries/arch.conf"

# 获取当前挂载的子卷
readonly CURRENT_SUBVOLUME=${SNAPSHOT_DIR}$(mount | grep " / " | sed -n -e 's/.*subvol=\/\?\([^,)]*\).*/\1/p' | sed -n -e 's/.*\(\/.*\/.*\)/\1/p')

# 设置颜色代码
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m' # No Color

# 获取当前日期和时间
readonly NOW=$(TZ=${TIMEZONE} date +'%Y-%m-%d %H-%M-%S')
readonly CURRENT_DATE=$(echo "${NOW}" | cut -d' ' -f1)
readonly CURRENT_TIME=$(echo "${NOW}" | cut -d' ' -f2)

# 实用函数
log_success() { printf "${GREEN}%s${NC}\n" "$*"; }
log_warning() { printf "${YELLOW}%s${NC}\n" "$*"; }
log_error() { printf "${RED}%s${NC}\n" "$*"; }
require_confirm() {
  printf "${YELLOW}%s${NC} [y/N] " "${1}"
  read -r confirm
  if [[ "${confirm}" != "y" ]]; then
    return 1
  fi
}

init() {
  # 挂载 @.snapshots 子卷
  sudo mount -o "subvol=${SUBVOLUME_NAME}" "${MOUNT_DEVICE}" "${MOUNT_POINT}"
}

quit() {
  # 清理 SNAPSHOT_DIR 中的空文件夹
  sudo find "$SNAPSHOT_DIR" -maxdepth 1 -mindepth 1 ! -name ".*" -type d -empty -exec echo "Clean: {}" \; -delete
  # 卸载 @.snapshots 子卷
  while mountpoint -q "${MOUNT_POINT}"; do
    sudo umount "${MOUNT_POINT}"
    #sleep 1
  done
  exit "$1"
}

create_snapshot() {
  local default_path="${SNAPSHOT_DIR}/${CURRENT_DATE}/@${CURRENT_TIME}"
  local snapshot_path=${2:-${default_path}}
  local dir=$(dirname "${snapshot_path}")
  if [[ ! -d "${dir}" ]]; then
    sudo mkdir -p "${dir}"
  fi
  sudo btrfs subvolume snapshot "${1}" "${snapshot_path}"
  log_success "=> Created snapshot: ${snapshot_path}"
}

list_snapshots() {
  if [[ "${1:-}" == "all" ]]; then
    # 列表列出所有快照
    find "${SNAPSHOT_DIR}" -maxdepth 2 -mindepth 2 ! -name ".*"
  else
    # 默认以树形结构列出所有快照
    tree -L 2 "${SNAPSHOT_DIR}"
  fi
}

clean_snapshots() {
  case "${1:-}" in

  "all")
    ### 清理除当前挂载中的快照外的所有快照
    if ! require_confirm "=> Clean all snapshots except current subvolume. Are you sure?"; then
      return
    fi
    find "${SNAPSHOT_DIR}" -maxdepth 2 -mindepth 2 ! -name ".*" ! -path "${CURRENT_SUBVOLUME}" -exec sudo btrfs subvolume delete {} \;
    ;;

  "yesterday")
    ### 清理前一天的快照目录
    local previous_date
    previous_date=$(TZ=${TIMEZONE} date -d "yesterday" +'%Y-%m-%d')
    # 检查前一天的日期目录是否存在
    if [[ -d "${SNAPSHOT_DIR}/${previous_date}" ]]; then
      # 如果快照数量小于等于1，则不进行清理
      local dir_count=$(find "${SNAPSHOT_DIR}/${previous_date}" -maxdepth 1 -mindepth 1 ! -name ".*" ! -path "${CURRENT_SUBVOLUME}" | wc -l)
      if ((dir_count <= 1)); then
        return
      fi

      # 保留时间最早的一个快照，删除其余所有快照
      earliest_snapshot=$(find "${SNAPSHOT_DIR}/${previous_date}" -maxdepth 1 -mindepth 1 ! -name ".*" ! -path "${CURRENT_SUBVOLUME}" | sort | head -n 1)
      for snapshot in "${SNAPSHOT_DIR}/${previous_date}"/@*; do
        if [[ "${snapshot}" != "${earliest_snapshot}" ]]; then
          sudo btrfs subvolume delete "${snapshot}"
        fi
      done
    fi
    ;;

  *)
    ### 清理一周前的所有快照
    local one_week_ago
    one_week_ago=$(TZ=${TIMEZONE} date -d "1 week ago" +'%Y-%m-%d')
    for dir in "${SNAPSHOT_DIR}"/*; do
      if [[ -d "${dir}" ]]; then
        dir_date=$(basename "${dir}")
        if [[ "${dir_date}" < "${one_week_ago}" ]]; then
          find "${dir}" -maxdepth 1 -mindepth 1 ! -name ".*" ! -path "${CURRENT_SUBVOLUME}" -exec sudo btrfs subvolume delete {} \;
        fi
      fi
    done
    ;;

  esac
}

check_snapshot_exists() {
  # 检查指定快照是否存在
  if [[ ! -d "${SNAPSHOT_DIR}/${1}" ]]; then
    log_error "=> Snapshot ${SNAPSHOT_DIR}/$1 does not exist."
    return 1
  fi
  return 0
}

mount_snapshot() {
  # 如果不带参数，直接退出，保持 @.snapshots 子卷挂载
  if [[ -z "${1}" ]]; then
    exit 0
  fi

  # 挂载指定快照
  if ! check_snapshot_exists "${1}"; then
    return 1
  fi

  # 更新 systemd-boot 配置
  local boot_file_backup="${BOOT_FILE}.$(TZ=${TIMEZONE} date +'%Y%m%d%H%M%S').bak"
  sudo cp -f "${BOOT_FILE}" "${boot_file_backup}"
  sudo awk -i inplace -v snap="subvol=${SUBVOLUME_NAME}/${SNAPSHOT_DIR##*/}/$1" '{gsub(/subvol=[^ ]*/, snap); print}' ${BOOT_FILE}
  sudo cat "${BOOT_FILE}"
  log_success "=> Systemd-boot config updated. Check the above config before reboot."
}

restore_snapshot() {
  if [[ -z "${1}" ]]; then
    log_error "=> Please specify a snapshot to restore."
    return 1
  fi

  # 恢复到指定快照
  if ! check_snapshot_exists "${1}"; then
    return 1
  fi

  # 备份当前
  log_success "=> Backup current subvolume..."
  create_snapshot /

  # 备份要恢复的快照
  local snapshot_path="${SNAPSHOT_DIR}/${1}"
  local backup_path="${SNAPSHOT_DIR}/${1}.bak"
  if [[ ! -f "${backup_path}" ]]; then
    log_success "=> Backup snapshot ${1}..."
    create_snapshot "${snapshot_path}" "${backup_path}"
  else
    log_warning "=> Snapshot ${1}.bak already exists, skip backup."
  fi

  # 恢复快照
  log_success "=> Mount snapshot ${1}..."
  mount_snapshot "${1}"
}

auto_snap() {
  # 检查最近的快照时间
  local latest_snapshot=$(find "${SNAPSHOT_DIR}/${CURRENT_DATE}" -maxdepth 1 -mindepth 1 ! -name ".*" | sort | tail -n 1)

  if [[ -n "${latest_snapshot}" ]]; then
    # 计算时间差
    latest_time=$(basename "${latest_snapshot}" | cut -d'@' -f2)
    latest_time=$(TZ=${TIMEZONE} date -d "${latest_time//-/:}" +'%s')
    current_time=$(TZ=${TIMEZONE} date -d "${CURRENT_TIME//-/:}" +'%s')
    time_diff=$((current_time - latest_time))

    if [[ ${time_diff} -lt 3600 ]]; then
      log_success "=> Last snapshot was taken less than 1 hour ago, skipping."
      return
    fi
  fi

  create_snapshot /
}

main() {
  init

  case "${1:-}" in
  "list")
    list_snapshots "${2:-}"
    ;;
  "clean")
    clean_snapshots "${2:-}"
    ;;
  "mount")
    mount_snapshot "${2:-}"
    ;;
  "restore")
    restore_snapshot "${2:-}"
    ;;
  "now")
    create_snapshot /
    ;;
  *)
    auto_snap
    ;;
  esac

  quit $?
}

main "$@"
