#!/usr/bin/env bash
set -e

kubectl apply -f kubernetes/00-namespace.yml
kubectl apply -f kubernetes/10-secrets.yaml -f kubernetes/11-configmap.yaml
kubectl apply -f kubernetes/20-db-persistance.yml -f kubernetes/21-db.yaml
kubectl rollout status deployment/mongodb -n cluster-project --timeout=180s
kubectl apply -f kubernetes/

kubectl get all -n cluster-project