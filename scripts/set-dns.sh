#!/usr/bin/env bash
set -e

IP="192.168.252.241"
HOST="cluster-project.local"

if [ "${1-}" = "--remove" ]; then
  sudo sed -i.bak "/${HOST}/d" /etc/hosts
  echo "removed ${HOST}"
else
  sudo sed -i.bak "/${HOST}/d" /etc/hosts
  echo "${IP}  ${HOST}" | sudo tee -a /etc/hosts >/dev/null
  echo "${IP}  ${HOST}"
fi

grep "$HOST" /etc/hosts || true