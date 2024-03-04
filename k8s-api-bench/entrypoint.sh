#!/bin/bash

set -e

# Check environment
if [[ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]]; then
    echo "Running in a Kubernetes pod..."
    K8S_API_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    K8S_API_URL=https://kubernetes.default.svc/api/v1/pods
elif [[ -z "$K8S_API_TOKEN" || -z "$K8S_API_URL" ]]; then
    echo "Running outside of a Kubernetes pod and K8S_API_TOKEN or K8S_API_URL environment variable is not sent, aborting..."
    exit 1
fi

if [[ -z "$ITERATIONS" || -z "$CONCURRENCY" || -z "$REQUESTS_PER_SECOND" ]]; then
    echo "Not all arguments present... Hint: '$ITERATIONS' '$CONCURRENCY' '$REQUESTS_PER_SECOND'"
    exit 1
fi

hey -n $ITERATIONS -c $CONCURRENCY -q $REQUESTS_PER_SECOND -m GET -o csv -H "Authorization: Bearer $K8S_API_TOKEN" "$K8S_API_URL"

exit 0