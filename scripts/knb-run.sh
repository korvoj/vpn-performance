#!/bin/bash

set -eu

ITERATIONS=100
ITER_START=1
TEST_DURATION=60
PROTOCOLS=all # all,tcp,udp
PACKET_LOSS=('1' '5' '10')
PACKET_DELAY=('50ms' '250ms' '350ms')
RUN_INDEX='1'
RUN_FAMILY='headscale'

execute_run() {
        ploss=$1
        pdelay=$2
        duration=$3
        protos=$4
        idx=$5
        family=$6
        iters=$7
        RUN_NAME="${idx}-${family}-${duration}s-${protos}-loss${ploss}p-delay${pdelay}"
        DIR_NAME="/root/vpns/results/$RUN_NAME"

        if [ ! -d "$DIR_NAME" ]; then
                echo "$DIR_NAME directory does not exist, creating it..."
                mkdir -p "${DIR_NAME}/logs"
        fi

        echo "Start: $(date '+%s%N')" > "$DIR_NAME/00-meta-info.txt"

        for (( i=$ITER_START; i<=$iters; i++ )); do
                echo "Test run $i..."
                mkdir -p "${DIR_NAME}/logs/${i}"
                ./knb --keep --data-dir "${DIR_NAME}/logs/${i}" --debug --client-node l26-node02 --server-node l26-node03 --output data --file "$DIR_NAME/$i.data" --duration $duration --only-tests $protos --socket-buffer-size 2M --timeout 90
                echo "Results from run $i: "
                ./knb --from-data "$DIR_NAME/$i.data" -o yaml
        done
        echo "End: $(date '+%s%N')" >> "$DIR_NAME/00-meta-info.txt"
}


# execute without any obstacles
execute_run 0 0 $TEST_DURATION $PROTOCOLS $RUN_INDEX $RUN_FAMILY 100

# test packet loss
for pl in ${PACKET_LOSS[@]}; do
        echo "Packet loss: $pl"
        ssh root@79.99.57.140 "tc qdisc add dev enp5s0f0 root netem loss ${pl}%"
        execute_run $pl 0 $TEST_DURATION $PROTOCOLS $RUN_INDEX $RUN_FAMILY 10
        ssh root@79.99.57.140 "tc qdisc del dev enp5s0f0 root netem loss ${pl}%"
done

# test packet delay
for pd in ${PACKET_DELAY[@]}; do
      echo "Packet delay: $pd"
      ssh root@79.99.57.140 "tc qdisc add dev enp5s0f0 root netem delay $pd"
      execute_run 0 $pd $TEST_DURATION $PROTOCOLS $RUN_INDEX $RUN_FAMILY 10
      ssh root@79.99.57.140 "tc qdisc del dev enp5s0f0 root netem delay $pd"
done
