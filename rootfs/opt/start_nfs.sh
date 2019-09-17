#!/bin/bash

set -e

# environment variables

: ${EXPORT_PATH:="/data/nfs"}
: ${PSEUDO_PATH:="/"}
: ${EXPORT_ID:=0}
: ${PROTOCOLS:=4}
: ${TRANSPORTS:="UDP, TCP"}
: ${SEC_TYPE:="sys"}
: ${SQUASH_MODE:="No_Root_Squash"}
: ${GRACELESS:=true}
: ${VERBOSITY:="NIV_EVENT"} # NIV_DEBUG, NIV_EVENT, NIV_WARN

: ${GANESHA_CONFIG:="/etc/ganesha/ganesha.conf"}
: ${GANESHA_LOGFILE:="/dev/stdout"}
: ${CEPH_MONITORS:=""}
: ${CEPH_USER_ID:=""}
: ${CEPH_SECRET_ACCESS_KEY:=""}
: ${CEPH_CLIENT_MOUNT_UID:="0"}
: ${CEPH_CLIENT_MOUNT_GID:="0"}

init_rpc() {
    echo "* Starting rpcbind"
    if [ ! -x /run/rpcbind ] ; then
        install -m755 -g 32 -o 32 -d /run/rpcbind
    fi
    rpcbind || return 0
    rpc.statd -L || return 0
    rpc.idmapd || return 0
    sleep 1
}

init_dbus() {
    echo "* Starting dbus"
    if [ ! -x /var/run/dbus ] ; then
        install -m755 -g 81 -o 81 -d /var/run/dbus
    fi
    rm -f /var/run/dbus/*
    rm -f /var/run/messagebus.pid
    dbus-uuidgen --ensure
    dbus-daemon --system --fork
    sleep 1
}

# pNFS
# Ganesha by default is configured as pNFS DS.
# A full pNFS cluster consists of multiple DS
# and one MDS (Meta Data server). To implement
# this one needs to deploy multiple Ganesha NFS
# and then configure one of them as MDS:
# GLUSTER { PNFS_MDS = ${WITH_PNFS}; }

bootstrap_config() {
    echo "* Writing configuration"
    cat <<END >${GANESHA_CONFIG}

NFS_CORE_PARAM
{
    Enable_NLM = false;
    Enable_RQUOTA = false;
}

NFSv4
{
    Graceless = ${GRACELESS};
    Minor_Versions =  1,2;
}

MDCACHE
{
    Dir_Chunk = 0;
    NParts = 1;
    Cache_Size = 1;
}

EXPORT
{
    Export_Id = ${EXPORT_ID};
    Protocols = ${PROTOCOLS};
    Path = "${EXPORT_PATH}";
    Pseudo = "${PSEUDO_PATH}";
    Access_type = RW;
    Attr_Expiration_Time = 0;
    Disable_ACL = true;
    Squash = ${SQUASH_MODE};
    FSAL
    {
        Name = CEPH;
        User_Id = "${CEPH_USER_ID}";
        Secret_Access_Key = "${CEPH_SECRET_ACCESS_KEY}";
    }
}

EXPORT_DEFAULTS
{
    Transports = ${TRANSPORTS};
    SecType = ${SEC_TYPE};
}

CEPH
{
    Ceph_Conf = /ceph.conf;
}

RADOS_KV
{
}

RADOS_URLS
{
}

END

    cat <<END >/ceph.conf
[client.ganesha]
client mount uid = ${CEPH_CLIENT_MOUNT_UID}
client mount gid = ${CEPH_CLIENT_MOUNT_GID}
mon host = ${CEPH_MONITORS}
END
}

sleep 0.5

if [ ! -f ${EXPORT_PATH} ]; then
    mkdir -p "${EXPORT_PATH}"
fi

echo "Initializing Ganesha NFS server"
echo "=================================="
echo "export path: ${EXPORT_PATH}"
echo "=================================="

bootstrap_config
init_rpc
init_dbus

echo "Generated NFS-Ganesha config:"
cat ${GANESHA_CONFIG}

echo "* Starting Ganesha-NFS"
exec /usr/bin/ganesha.nfsd -F -L ${GANESHA_LOGFILE} -f ${GANESHA_CONFIG} -N ${VERBOSITY}
