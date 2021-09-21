#!/usr/bin/env bash

testdir=$(readlink -f $(dirname $0))
rootdir=$(readlink -f $testdir/../../..)
source $rootdir/test/common/autotest_common.sh
source $rootdir/test/nvmf/common.sh

rpc_py="$rootdir/scripts/rpc.py"
loops=5

nvmftestinit
nvmfappstart -m 0xF

$rpc_py nvmf_create_transport $NVMF_TRANSPORT_OPTS -u 8192

MALLOC_BDEV_SIZE=64
MALLOC_BLOCK_SIZE=512

$rpc_py bdev_malloc_create $MALLOC_BDEV_SIZE $MALLOC_BLOCK_SIZE -b Malloc1

# Auto attach all ctrlrs to namespace
$rpc_py nvmf_create_subsystem nqn.2016-06.io.spdk:cnode1 -a -s $NVMF_SERIAL
$rpc_py nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Malloc1
$rpc_py nvmf_subsystem_add_listener nqn.2016-06.io.spdk:cnode1 -t $TEST_TRANSPORT -a $NVMF_FIRST_TARGET_IP -s $NVMF_PORT

# namespace should be active
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check active
# TODO: Try attach/detach => should fail
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

# Remove ns and re-add without auto attachment
$rpc_py nvmf_subsystem_remove_ns nqn.2016-06.io.spdk:cnode1 1
$rpc_py nvmf_subsystem_add_ns nqn.2016-06.io.spdk:cnode1 Malloc1 --no-auto-attach

# namespace should be inactive
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check inactive

# hot + cold attach and check active
$rpc_py nvmf_ns_attach_ctrlr nqn.2016-06.io.spdk:cnode1 1 nqn.2016-06.io.spdk:host1
# TODO: list active ns / ns-id => check active

# hot detach and check inactive
$rpc_py nvmf_ns_detach_ctrlr nqn.2016-06.io.spdk:cnode1 1 nqn.2016-06.io.spdk:host1 -hot
# TODO: list active ns / ns-id => check inactive
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

# connect and check active
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check active

# hot + cold detach
$rpc_py nvmf_ns_detach_ctrlr nqn.2016-06.io.spdk:cnode1 1 nqn.2016-06.io.spdk:host1
# TODO: list active ns / ns-id => check inactive
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

# connect and check inactive
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check inactive

# hot attach and check active
$rpc_py nvmf_ns_attach_ctrlr nqn.2016-06.io.spdk:cnode1 1 nqn.2016-06.io.spdk:host1 -hot
# TODO: list active ns / ns-id => check active
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

# connect and check inactive
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check inactive

# cold attach and check inactive
$rpc_py nvmf_ns_attach_ctrlr nqn.2016-06.io.spdk:cnode1 1 nqn.2016-06.io.spdk:host1 -cold
# TODO: list active ns / ns-id => check inactive
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

# connect and check active
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check active

# cold detach and check active
$rpc_py nvmf_ns_detach_ctrlr nqn.2016-06.io.spdk:cnode1 1 nqn.2016-06.io.spdk:host1 -cold
# TODO: list active ns / ns-id => check active
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

# connect and check inactive
nvme connect -t $TEST_TRANSPORT -n nqn.2016-06.io.spdk:cnode1 -q nqn.2016-06.io.spdk:host1 -a "$NVMF_FIRST_TARGET_IP" -s "$NVMF_PORT"
waitforserial "$NVMF_SERIAL"
# TODO: list active ns / ns-id => check inactive
nvme disconnect -n nqn.2016-06.io.spdk:cnode1

$rpc_py nvmf_delete_subsystem nqn.2016-06.io.spdk:cnode1

trap - SIGINT SIGTERM EXIT

nvmftestfini
