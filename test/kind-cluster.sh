#!/bin/bash

kind delete cluster cnpg-dev
kind create cluster -n cnpg-dev
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.1.yaml
kubectl apply -f pg-cluster.yaml