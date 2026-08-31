#!/usr/bin/env bash
mkdir -p ~/.kube
## Change subnet if needed
multipass exec k3s-server -- sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed 's/127.0.0.1/192.168.252.241/' > ~/.kube/k3s-multipass.yaml
chmod 600 ~/.kube/k3s-multipass.yaml
export KUBECONFIG=~/.kube/k3s-multipass.yaml