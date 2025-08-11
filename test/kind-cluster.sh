#!/bin/bash
set -e

kind delete cluster -n cnpg-dev
kind create cluster -n cnpg-dev
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.26/releases/cnpg-1.26.1.yaml
kubectl apply -f test/pg-cluster.yaml
kubectl apply -f test/restic-secret.yaml
helm upgrade --install -f test/helm-values.yaml backup ./charts/backup