#!/usr/bin/env bash

testdir=$(readlink -f $(dirname $0))
rootdir=$(readlink -f $testdir/../../..)
source $rootdir/test/common/autotest_common.sh
source $rootdir/test/nvmf/common.sh

rpc_py="$rootdir/scripts/rpc.py"
loops=5

SUBSYSNQN="nqn.2016-06.io.spdk:cnode1"
HOSTNQN="nqn.2016-06.io.spdk:host1"

function connect() {
	nvme connect -t $TEST_TRANSPORT -n $SUBSYSNQN -q $HOSTNQN -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
	waitforserial "$NVMF_SERIAL" $1
	ctrl_id=$(nvme list-subsys | sed -n "s/traddr=$NVMF_FIRST_TARGET_IP trsvcid=$NVMF_PORT//p" | sed 's/[^0-9]*//g')
}

function disconnect() {
	nvme disconnect -n $SUBSYSNQN
}

# $1 == hex nsid
function check_active() {
	nvme list-ns /dev/nvme$ctrl_id | grep "$1"
	nguid=$(nvme id-ns /dev/nvme$ctrl_id -n $1 -o json | jq -r ".nguid")
	if [[ $nguid == "00000000000000000000000000000000" ]]; then
		echo "Namespace with NSID $1 not active." && false
	fi
}

# $1 == hex nsid
function check_inactive() {
	NOT grep "$1" <(nvme list-ns /dev/nvme$ctrl_id)
	nguid=$(nvme id-ns /dev/nvme$ctrl_id -n $1 -o json | jq -r ".nguid")
	if [[ $nguid != "00000000000000000000000000000000" ]]; then
		echo "Namespace with NSID $1 active." && false
	fi
}

nvmftestinit
nvmfappstart -m 0xF

$rpc_py nvmf_create_transport $NVMF_TRANSPORT_OPTS -u 8192

MALLOC_BDEV_SIZE=64
MALLOC_BLOCK_SIZE=512

$rpc_py bdev_malloc_create $MALLOC_BDEV_SIZE $MALLOC_BLOCK_SIZE -b Malloc1
$rpc_py bdev_malloc_create $MALLOC_BDEV_SIZE $MALLOC_BLOCK_SIZE -b Malloc2

# Auto attach all ctrlrs to namespace
$rpc_py nvmf_create_subsystem $SUBSYSNQN -a -s $NVMF_SERIAL
$rpc_py nvmf_subsystem_add_ns $SUBSYSNQN Malloc1 -n 1
$rpc_py nvmf_subsystem_add_listener $SUBSYSNQN -t $TEST_TRANSPORT -a $NVMF_FIRST_TARGET_IP -s $NVMF_PORT

# Namespace should be active
connect 1
check_active "0x1"

# Add 2nd namespace and check active
$rpc_py nvmf_subsystem_add_ns $SUBSYSNQN Malloc2 -n 2
check_active "0x1"
check_active "0x2"

# TODO: Try attach/detach => should fail
disconnect

# Remove ns and re-add without auto attachment
$rpc_py nvmf_subsystem_remove_ns $SUBSYSNQN 1
$rpc_py nvmf_subsystem_add_ns $SUBSYSNQN Malloc1 -n 1 --no-auto-attach

# namespace should be inactive
connect 1
check_inactive "0x1"

# hot + cold attach and check active
$rpc_py nvmf_ns_attach_ctrlrs $SUBSYSNQN 1 $HOSTNQN
check_active "0x1"

# hot detach and check inactive
$rpc_py nvmf_ns_detach_ctrlrs $SUBSYSNQN 1 $HOSTNQN -hot
check_inactive "0x1"
disconnect

# connect and check active
connect 2
check_active "0x1"

# hot + cold detach
$rpc_py nvmf_ns_detach_ctrlrs $SUBSYSNQN 1 $HOSTNQN
check_inactive "0x1"
disconnect

# connect and check inactive
connect 1
check_inactive "0x1"

# hot attach and check active
$rpc_py nvmf_ns_attach_ctrlrs $SUBSYSNQN 1 $HOSTNQN -hot
check_active "0x1"
disconnect

# connect and check inactive
connect 1
check_inactive "0x1"

# cold attach and check inactive
$rpc_py nvmf_ns_attach_ctrlrs $SUBSYSNQN 1 $HOSTNQN -cold
check_inactive "0x1"
disconnect

# connect and check active
connect 2
check_active "0x1"

# cold detach and check active
$rpc_py nvmf_ns_detach_ctrlrs $SUBSYSNQN 1 $HOSTNQN -cold
check_active "0x1"
disconnect

# connect and check inactive
connect 1
check_inactive "0x1"
disconnect

$rpc_py nvmf_delete_subsystem $SUBSYSNQN

trap - SIGINT SIGTERM EXIT

nvmftestfini
