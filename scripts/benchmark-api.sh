#!/bin/bash
# Based on https://github.com/InfraBuilder/k8s-bench-suite


POD_NAME="k8s-api-bench"
LOGS_OUTPUT_DIR="/root/vpns/results/02-headscaleDERP-k8s-api-bench"
DEBUG_LEVEL=3
DEBUG=true

if [ ! -d "$LOGS_OUTPUT_DIR" ]; then
        echo "Creating results output dir..."
        mkdir -p "$LOGS_OUTPUT_DIR"
fi

[ "$(tput colors)" -gt 0 ] && COLOR="true" || COLOR="false"
function color {
        $COLOR || return 0
        color="0"
        case $1 in
                normal) color="0" ;;
                rst) color="0" ;;
                red) color="31" ;;
                green) color="32" ;;
                yellow) color="33" ;;
                blue) color="34" ;;
                magenta) color="35" ;;
                cyan) color="36" ;;
                lightred) color="91" ;;
                lightgreen) color="92" ;;
                lightyellow) color="93" ;;
                lightblue) color="94" ;;
                lightmagenta) color="95" ;;
                lightcyan) color="96" ;;
                white) color="97" ;;
                *) color="0" ;;
        esac
        echo -e "\033[0;${color}m"
}
function logdate { date "+%Y-%m-%d %H:%M:%S"; }
function debug { [ $DEBUG_LEVEL -ge 3 ] && echo "$(logdate) $(color lightcyan)[DEBUG]$(color normal) $@" >&2; }
function now { date +%s; }

function waitpod {
        POD=$1
        PHASE=$2
        TIMEOUT=$3
        TMAX=$(( $(now) + $TIMEOUT ))
        $DEBUG && debug "Waiting for pod $POD to be $PHASE until $TMAX"
        while [ "$(now)" -lt "$TMAX" ]
        do
                CURRENTPHASE=$(kubectl get --request-timeout 2s $NAMESPACEOPT pod $POD -o jsonpath={.status.phase})
                $DEBUG && debug "[$(now)/$TMAX] Pod $POD is in phase $CURRENTPHASE, waiting for $PHASE"
                [ "$CURRENTPHASE" = "$PHASE" ] && return 0
                sleep 1
        done
        return 1
}

for ((i=1; i<=10; i++)); do
        echo "Run $i..."
        kubectl create -f k8s-bench.pod.yaml
        waitpod "$POD_NAME" Succeeded "60" \
                || fatal "Failed to run pod $POD_NAME until timeout"

        kubectl logs $POD_NAME > "${LOGS_OUTPUT_DIR}/k8s-api-benchmark-run$i.txt"
        kubectl delete -f k8s-bench.pod.yaml
        echo "Sleeping for 60 seconds..."
        sleep 60
done