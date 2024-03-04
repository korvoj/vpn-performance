#!/bin/bash

docker build -t k8s-api-bench .
docker tag k8s-api-bench quay.io/korvoj/k8s-api-bench:latest
docker tag k8s-api-bench quay.io/korvoj/k8s-api-bench:v1.0.0
docker push quay.io/korvoj/k8s-api-bench:latest
docker push quay.io/korvoj/k8s-api-bench:v1.0.0