#!/bin/bash
set -e

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  CEPH_DISK_OPTIONS=""
  log "INFO - DATA_UUID = ${OSD_DEVICE}-part1"
  DATA_UUID=$(blkid -o value -s PARTUUID ${OSD_DEVICE}-part1)
  LOCKBOX_UUID=$(blkid -o value -s PARTUUID ${OSD_DEVICE}-part3 || true)
  ACTUAL_OSD_DEVICE=$(readlink -f ${OSD_DEVICE}) # resolve /dev/disk/by-* names

  # watch the udev event queue, and exit if all current events are handled
  udevadm settle --timeout=600

  # wait till partition exists then activate it
  if [[ -n "${OSD_JOURNAL}" ]]; then
    wait_for_file ${OSD_DEVICE}
    chown ceph. ${OSD_JOURNAL}
  fi

  DATA_PART=$(dev_part ${OSD_DEVICE} "-part1")
  MOUNTED_PART=${DATA_PART}

  if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
    echo "Mounting LOCKBOX directory"
    # NOTE(leseb): adding || true so when this bug will be fixed the entrypoint will not fail
    # Ceph bug tracker: http://tracker.ceph.com/issues/18945
    mkdir -p /var/lib/ceph/osd-lockbox/${DATA_UUID}
    mount /dev/disk/by-partuuid/${LOCKBOX_UUID} /var/lib/ceph/osd-lockbox/${DATA_UUID} || true
    CEPH_DISK_OPTIONS="$CEPH_DISK_OPTIONS --dmcrypt"
    MOUNTED_PART="/dev/mapper/${DATA_UUID}"
  fi

  ceph-disk -v --setuser ceph --setgroup disk activate ${CEPH_DISK_OPTIONS} --no-start-daemon ${DATA_PART}

  OSD_ID=$(grep "${MOUNTED_PART}" /proc/mounts | awk '{print $2}' | grep -oh '[0-9]*')
  OSD_PATH=$(get_osd_path $OSD_ID)
  OSD_KEYRING="$OSD_PATH/keyring"
  if [[ ${OSD_BLUESTORE} -eq 1 ]] && [ -e "${OSD_PATH}block" ]; then
    OSD_WEIGHT=$(awk "BEGIN { d= $(blockdev --getsize64 ${OSD_PATH}block)/1099511627776 ; r = sprintf(\"%.2f\", d); print r }")
  else
    OSD_WEIGHT=$(df -P -k $OSD_PATH | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  fi
  ceph ${CLI_OPTS} --name=osd.${OSD_ID} --keyring=$OSD_KEYRING osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  log "SUCCESS"
  exec /usr/bin/ceph-osd ${CLI_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk
}
