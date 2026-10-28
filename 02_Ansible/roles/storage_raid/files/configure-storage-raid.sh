#!/usr/bin/env bash
# Idempotently creates the Garage and Restic RAID1 filesystems on storage nodes.
# Existing signatures or an unexpected array layout cause a safe failure.
set -Eeuo pipefail
export LC_ALL=C

readonly MDADM_CONFIG=/etc/mdadm/mdadm.conf
readonly BEGIN_MARKER='# BEGIN PROJECT STORAGE ARRAYS'
readonly END_MARKER='# END PROJECT STORAGE ARRAYS'

changed=0
temporary_files=()

cleanup() {
  if ((${#temporary_files[@]} > 0)); then
    rm -f -- "${temporary_files[@]}"
  fi
}

trap cleanup EXIT

log() {
  printf '[storage-raid] %s\n' "$*"
}

fail() {
  printf '[storage-raid] ERROR: %s\n' "$*" >&2
  exit 1
}

mark_changed() {
  changed=1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

wait_for_block_device() {
  local device=$1
  local attempt

  for ((attempt = 1; attempt <= 60; attempt++)); do
    [[ -b "$device" ]] && return 0
    sleep 1
  done

  fail "Block device was not found after 60 seconds: $device"
}

has_raid_metadata() {
  mdadm --examine "$1" >/dev/null 2>&1
}

require_blank_disk() {
  local device=$1
  local signatures

  signatures=$(wipefs --noheadings --output TYPE "$device")
  [[ -z "${signatures//[[:space:]]/}" ]] || \
    fail "$device contains an existing filesystem, partition table, or RAID signature"
}

verify_array_members() {
  local array_device=$1
  local member_one=$2
  local member_two=$3
  local resolved_one
  local resolved_two
  local details

  resolved_one=$(readlink -f "$member_one")
  resolved_two=$(readlink -f "$member_two")
  details=$(mdadm --detail "$array_device")

  [[ "$details" == *"$resolved_one"* ]] || \
    fail "$array_device does not contain the expected member $resolved_one"
  [[ "$details" == *"$resolved_two"* ]] || \
    fail "$array_device does not contain the expected member $resolved_two"
}

ensure_fstab_entry() {
  local filesystem_uuid=$1
  local mount_path=$2
  local entry_count
  local existing_entry
  local existing_source
  local existing_type

  entry_count=$(awk -v target="$mount_path" '$2 == target { count++ } END { print count + 0 }' /etc/fstab)

  if [[ "$entry_count" -gt 1 ]]; then
    fail "/etc/fstab contains multiple entries for $mount_path"
  fi

  if [[ "$entry_count" -eq 1 ]]; then
    existing_entry=$(awk -v target="$mount_path" '$2 == target { print $1 "|" $3 }' /etc/fstab)
    existing_source=${existing_entry%%|*}
    existing_type=${existing_entry#*|}

    [[ "$existing_source" == "UUID=$filesystem_uuid" ]] || \
      fail "/etc/fstab maps $mount_path to $existing_source instead of UUID=$filesystem_uuid"
    [[ "$existing_type" == ext4 ]] || \
      fail "/etc/fstab maps $mount_path as $existing_type instead of ext4"
    return 0
  fi

  printf 'UUID=%s %s ext4 defaults,nofail 0 2\n' "$filesystem_uuid" "$mount_path" >>/etc/fstab
  mark_changed
}

ensure_mount() {
  local filesystem_uuid=$1
  local mount_path=$2
  local mounted_source
  local mounted_uuid

  if ! mountpoint -q "$mount_path"; then
    mount "$mount_path"
    mark_changed
    return 0
  fi

  mounted_source=$(findmnt --noheadings --output SOURCE --target "$mount_path")
  mounted_uuid=$(blkid -s UUID -o value "$mounted_source" 2>/dev/null || true)
  [[ "$mounted_uuid" == "$filesystem_uuid" ]] || \
    fail "$mount_path is mounted from $mounted_source, not from the intended RAID filesystem"
}

configure_array() {
  local array_name=$1
  local array_device=$2
  local filesystem_label=$3
  local mount_path=$4
  local member_one=$5
  local member_two=$6
  local member_one_has_metadata=0
  local member_two_has_metadata=0
  local filesystem_type
  local filesystem_uuid

  log "Configuring $array_name on $array_device"
  wait_for_block_device "$member_one"
  wait_for_block_device "$member_two"

  has_raid_metadata "$member_one" && member_one_has_metadata=1
  has_raid_metadata "$member_two" && member_two_has_metadata=1

  if [[ "$member_one_has_metadata" -ne "$member_two_has_metadata" ]]; then
    fail "Only one member of $array_name contains RAID metadata; refusing automatic changes"
  fi

  if [[ -b "$array_device" ]]; then
    [[ "$member_one_has_metadata" -eq 1 ]] || \
      fail "$array_device exists, but the intended member disks have no RAID metadata"
    verify_array_members "$array_device" "$member_one" "$member_two"
  elif [[ "$member_one_has_metadata" -eq 1 ]]; then
    mdadm --assemble "$array_device" "$member_one" "$member_two"
    mark_changed
  else
    require_blank_disk "$member_one"
    require_blank_disk "$member_two"
    mdadm --create "$array_device" \
      --metadata=1.2 \
      --level=1 \
      --raid-devices=2 \
      --name "$array_name" \
      --run \
      --force \
      "$member_one" "$member_two"
    mark_changed
  fi

  wait_for_block_device "$array_device"

  filesystem_type=$(blkid -s TYPE -o value "$array_device" 2>/dev/null || true)
  case "$filesystem_type" in
    '')
      mkfs.ext4 -L "$filesystem_label" "$array_device"
      mark_changed
      ;;
    ext4)
      ;;
    *)
      fail "$array_device contains unsupported filesystem type: $filesystem_type"
      ;;
  esac

  if [[ ! -d "$mount_path" ]]; then
    mkdir -p "$mount_path"
    mark_changed
  fi

  filesystem_uuid=$(blkid -s UUID -o value "$array_device")
  [[ -n "$filesystem_uuid" ]] || fail "No filesystem UUID was found on $array_device"

  ensure_fstab_entry "$filesystem_uuid" "$mount_path"
  ensure_mount "$filesystem_uuid" "$mount_path"
  mdadm --detail --test "$array_device"
}

write_mdadm_config() {
  local stripped_config
  local candidate_config
  local garage_scan
  local backup_scan
  local array_scan

  stripped_config=$(mktemp)
  candidate_config=$(mktemp)
  temporary_files+=("$stripped_config" "$candidate_config")

  if [[ ! -f "$MDADM_CONFIG" ]]; then
    install -d -o root -g root -m 0755 /etc/mdadm
    install -o root -g root -m 0644 /dev/null "$MDADM_CONFIG"
  fi

  garage_scan=$(mdadm --detail --brief /dev/md0)
  backup_scan=$(mdadm --detail --brief /dev/md1)
  array_scan="${garage_scan}"$'\n'"${backup_scan}"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { lines[++count] = $0 }
    END {
      while (count > 0 && lines[count] == "") count--
      for (line = 1; line <= count; line++) print lines[line]
    }
  ' "$MDADM_CONFIG" >"$stripped_config"

  {
    cat "$stripped_config"
    [[ ! -s "$stripped_config" ]] || printf '\n'
    printf '%s\n%s\n%s\n' "$BEGIN_MARKER" "$array_scan" "$END_MARKER"
  } >"$candidate_config"

  if ! cmp -s "$candidate_config" "$MDADM_CONFIG"; then
    install -o root -g root -m 0644 "$candidate_config" "$MDADM_CONFIG"
    update-initramfs -u
    mark_changed
  fi
}

main() {
  local command_name

  [[ "$EUID" -eq 0 ]] || fail 'This script must run as root'

  for command_name in \
    awk blkid cmp findmnt install mdadm mkfs.ext4 mount mountpoint \
    readlink update-initramfs wipefs; do
    require_command "$command_name"
  done

  configure_array \
    garage /dev/md0 garage /srv/storage \
    /dev/disk/by-id/virtio-garage1 \
    /dev/disk/by-id/virtio-garage2

  configure_array \
    backup /dev/md1 backup /srv/backup \
    /dev/disk/by-id/virtio-backup1 \
    /dev/disk/by-id/virtio-backup2

  write_mdadm_config

  log 'Garage and backup RAID arrays are ready'
  printf 'CHANGED=%d\n' "$changed"
}

main "$@"
