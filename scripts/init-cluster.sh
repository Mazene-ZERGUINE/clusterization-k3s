#!/usr/bin/env bash

set -euo pipefail


IMAGE="${IMAGE:-24.04}"
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-2G}"
DISK="${DISK:-10G}"

K3S_CHANNEL="${K3S_CHANNEL:-stable}"
SUBNET="${SUBNET:-}"
GATEWAY="${GATEWAY:-}"
KEEP_DHCP="${KEEP_DHCP:-yes}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$PWD/k3s-kubeconfig.yaml}"
DB_NODE_LABEL="${DB_NODE_LABEL:-role=database}"

PROBE_TIMEOUT="${PROBE_TIMEOUT:-10}"
EXEC_TIMEOUT="${EXEC_TIMEOUT:-60}"
LONG_TIMEOUT="${LONG_TIMEOUT:-900}"

NODES=(k3s-server k3s-agent-1 k3s-agent-2)
OCTETS=(241       242         243)

SERVER_IP=""
TOKEN=""


BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; OFF=$'\033[0m'

log()  { printf '%s==>%s %s\n'   "$BLUE"   "$OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n'  "$GREEN"  "$OFF" "$*"; }
warn() { printf '%s warn%s %s\n' "$YELLOW" "$OFF" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$RED"    "$OFF" "$*" >&2; exit 1; }

TMPFILE=$(mktemp)
NULLOUT=$(mktemp)
trap 'rm -f "$TMPFILE" "$NULLOUT"' EXIT

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=gtimeout
fi



run_limited() {
  local seconds=$1
  shift
  local rc=0

  if [ -n "$TIMEOUT_CMD" ]; then
    "$TIMEOUT_CMD" -k 5 "$seconds" "$@" || rc=$?
    return "$rc"
  fi

  "$@" &
  local pid=$!
  ( sleep "$seconds"; kill -TERM "$pid"; sleep 5; kill -KILL "$pid" ) >/dev/null 2>&1 &
  local guard=$!
  wait "$pid" || rc=$?
  kill -KILL "$guard" >/dev/null 2>&1 || true
  wait "$guard" >/dev/null 2>&1 || true
  return "$rc"
}

retry() {
  local attempts=$1 pause=$2
  shift 2
  local n=1
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -gt "$attempts" ]; then
      return 1
    fi
    sleep "$pause"
  done
}


in_vm()      { run_limited "$EXEC_TIMEOUT" multipass exec "$1" -- bash -lc "$2" </dev/null; }
in_vm_long() { run_limited "$LONG_TIMEOUT" multipass exec "$1" -- bash -lc "$2" </dev/null; }

# 'multipass exec' never returns when its stdout is /dev/null and the remote
# command writes something, so probes discard the output inside the VM and send
# whatever the client itself prints to a scratch file instead of /dev/null.
probe()      { run_limited "$PROBE_TIMEOUT" multipass exec "$1" -- bash -lc "( $2 ) >/dev/null 2>&1" </dev/null >"$NULLOUT" 2>&1; }

vm_exists()  { run_limited 30 multipass info "$1" >/dev/null 2>&1; }
vm_running() { run_limited 30 multipass info "$1" --format csv 2>/dev/null | tail -1 | cut -d, -f2 | grep -qi running; }

ip_of() { echo "${SUBNET}.${OCTETS[$1]}"; }


check_prereqs() {
  command -v multipass >/dev/null 2>&1 || die "multipass is not installed (https://multipass.run)"
  run_limited 30 multipass version >/dev/null 2>&1 || die "the multipass daemon is not responding"

  if [ -z "$TIMEOUT_CMD" ]; then
    warn "timeout(1) not found, using the built-in watchdog (brew install coreutils for gtimeout)"
  fi

  if [ "$KEEP_DHCP" != "yes" ] && [ "$(uname -s)" = "Darwin" ]; then
    warn "KEEP_DHCP=no drops the DHCP lease multipass uses to reach the VM; 'multipass exec' will stop working"
  fi
}


launch_vms() {
  log "Launching the virtual machines"

  for vm in "${NODES[@]}"; do
    if vm_exists "$vm"; then
      if ! vm_running "$vm"; then
        log "starting $vm"
        run_limited "$LONG_TIMEOUT" multipass start "$vm" || die "cannot start $vm"
      fi
      ok "$vm already exists"
    else
      run_limited "$LONG_TIMEOUT" multipass launch "$IMAGE" \
        --name "$vm" --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK" \
        || die "$vm: launch failed or timed out after ${LONG_TIMEOUT}s"
      ok "$vm created"
    fi

    retry 30 2 probe "$vm" "true" || die "$vm: no response to 'multipass exec' after launch"
  done

  multipass list
}


detect_network() {
  retry 30 2 probe k3s-server "ip -4 -o addr show scope global | grep -q ." \
    || die "k3s-server has no IPv4 address yet"

  local addr
  addr=$(in_vm k3s-server "ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -1") \
    || die "cannot read the address of k3s-server"
  [ -n "$addr" ] || die "k3s-server has no IPv4 address yet"

  if [ -z "$SUBNET" ]; then
    SUBNET=$(echo "$addr" | cut -d. -f1-3)
  fi
  if [ -z "$GATEWAY" ]; then
    GATEWAY=$(in_vm k3s-server "ip -4 route show default | awk '{print \$3}' | head -1") || GATEWAY=""
  fi
  if [ -z "$GATEWAY" ]; then
    GATEWAY="${SUBNET}.1"
  fi

  SERVER_IP=$(ip_of 0)
  log "Subnet ${SUBNET}.0/24 - gateway ${GATEWAY} - control plane ${SERVER_IP}"
}


netplan_id_of() {
  local id
  id=$(in_vm "$1" "sudo netplan get ethernets 2>/dev/null | awk '/^[A-Za-z0-9_.-]+:/{sub(/:.*/,\"\"); print; exit}'" 2>/dev/null) || id=""
  if [ "$id" = "null" ]; then
    id=""
  fi
  echo "$id"
}

write_netplan_config() {
  local iface_id=$1 ip=$2

  {
    echo "network:"
    echo "  version: 2"
    echo "  ethernets:"
    echo "    ${iface_id}:"
    echo "      addresses: [${ip}/24]"

    if [ "$KEEP_DHCP" = "yes" ]; then
      echo "      dhcp4: true"
      echo "      dhcp4-overrides:"
      echo "        use-routes: false"
    else
      echo "      dhcp4: false"
    fi

    echo "      routes:"
    echo "        - to: default"
    echo "          via: ${GATEWAY}"

    if [ "$KEEP_DHCP" != "yes" ]; then
      echo "      nameservers:"
      echo "        addresses: [${GATEWAY}, 1.1.1.1]"
    fi
  } > "$TMPFILE"
}

rollback_netplan() {
  local vm=$1
  warn "$vm: rolling back /etc/netplan/99-k3s-static.yaml"
  probe "$vm" "sudo rm -f /etc/netplan/99-k3s-static.yaml" || true
  probe "$vm" "sudo systemd-run --collect --unit=k3s-netplan-rollback --no-block netplan apply" || true
}

configure_one_ip() {
  local vm=$1 ip=$2
  local iface id

  iface=$(in_vm "$vm" "ip -4 route show default | awk '{print \$5}' | head -1") \
    || die "$vm: cannot determine the network interface"
  [ -n "$iface" ] || die "$vm: cannot determine the network interface"

  id=$(netplan_id_of "$vm")
  [ -n "$id" ] || id=$iface

  write_netplan_config "$id" "$ip"

  local held=no
  if probe "$vm" "ip -4 -o addr show | grep -q ' ${ip}/24 '"; then
    held=yes
  fi

  if [ "$held" = "yes" ] \
     && in_vm "$vm" "sudo cat /etc/netplan/99-k3s-static.yaml 2>/dev/null" | diff -q - "$TMPFILE" >/dev/null 2>&1; then
    ok "$vm already holds $ip"
    return 0
  fi

  if [ "$held" = "no" ] && probe k3s-server "ping -c1 -W1 ${ip}"; then
    warn "$vm: ${ip} already answers on this subnet - change SUBNET/OCTETS if the cluster misbehaves"
  fi

  run_limited "$EXEC_TIMEOUT" multipass transfer "$TMPFILE" "${vm}:/tmp/99-k3s-static.yaml" \
    || die "$vm: cannot copy the netplan file"
  in_vm "$vm" "sudo install -m 600 -o root -g root /tmp/99-k3s-static.yaml /etc/netplan/99-k3s-static.yaml" \
    || die "$vm: cannot install the netplan file"

  if ! in_vm "$vm" "sudo netplan generate"; then
    rollback_netplan "$vm"
    die "$vm: netplan rejected the configuration"
  fi


  if probe "$vm" "command -v systemd-run"; then
    in_vm "$vm" "sudo systemd-run --collect --unit=k3s-netplan-apply --no-block netplan apply" || true
  else
    in_vm "$vm" "sudo setsid nohup netplan apply </dev/null >/dev/null 2>&1 & exit 0" || true
  fi

  if ! retry 45 2 probe "$vm" "ip -4 -o addr show | grep -q ' ${ip}/24 '"; then
    rollback_netplan "$vm"
    die "$vm: address $ip never came up"
  fi

  if ! retry 20 3 probe "$vm" "ip -4 route show default | grep -q . && getent hosts get.k3s.io >/dev/null"; then
    rollback_netplan "$vm"
    die "$vm: lost the default route or DNS after applying $ip"
  fi

  if ! retry 20 2 probe "$vm" "ip -4 route get 1.1.1.1 | grep -q 'src ${ip}'"; then
    rollback_netplan "$vm"
    die "$vm: ${ip} is not the preferred source address"
  fi

  ok "$vm -> $ip ($iface, netplan id '$id')"
}

configure_static_ips() {
  log "Applying the static addresses via netplan"
  for i in "${!NODES[@]}"; do
    configure_one_ip "${NODES[$i]}" "$(ip_of "$i")"
  done
}


install_server() {
  log "Installing k3s on the control plane"

  local need_install=yes
  if probe k3s-server "systemctl is-active --quiet k3s"; then
    if probe k3s-server "grep -qF '${SERVER_IP}' /etc/systemd/system/k3s.service"; then
      need_install=no
      ok "k3s server already running on ${SERVER_IP}"
    else
      warn "k3s server is bound to another address, reinstalling on ${SERVER_IP}"
    fi
  fi

  if [ "$need_install" = "yes" ]; then
    in_vm_long k3s-server "curl -sfL https://get.k3s.io | \
      INSTALL_K3S_CHANNEL=${K3S_CHANNEL} sh -s - server \
      --write-kubeconfig-mode 644 \
      --node-ip ${SERVER_IP} \
      --advertise-address ${SERVER_IP} \
      --tls-san ${SERVER_IP}" || die "the k3s server installation failed"
    ok "k3s server installed"
  fi

  retry 60 2 probe k3s-server "sudo test -s /var/lib/rancher/k3s/server/node-token" \
    || die "the node token never appeared"
  TOKEN=$(in_vm k3s-server "sudo cat /var/lib/rancher/k3s/server/node-token") \
    || die "cannot read the node token"
  [ -n "$TOKEN" ] || die "the node token is empty"

  retry 60 3 probe k3s-server "sudo k3s kubectl get --raw /readyz >/dev/null" \
    || warn "the API server is not reporting ready yet, continuing"
}


join_agents() {
  log "Joining the workers to the cluster"

  for i in 1 2; do
    local vm=${NODES[$i]}
    local ip
    ip=$(ip_of "$i")

    if probe "$vm" "systemctl is-active --quiet k3s-agent" \
       && probe "$vm" "grep -qF '${SERVER_IP}' /etc/systemd/system/k3s-agent.service.env"; then
      ok "$vm already joined"
      continue
    fi

    retry 30 3 probe "$vm" "curl -sk --max-time 5 -o /dev/null https://${SERVER_IP}:6443/ping" \
      || die "$vm: cannot reach the API server at ${SERVER_IP}:6443"

    in_vm_long "$vm" "curl -sfL https://get.k3s.io | \
      INSTALL_K3S_CHANNEL=${K3S_CHANNEL} \
      K3S_URL=https://${SERVER_IP}:6443 \
      K3S_TOKEN=${TOKEN} sh -s - agent --node-ip ${ip}" || die "$vm: the k3s agent installation failed"

    ok "$vm joined ($ip)"
  done
}


label_nodes() {
  [ -n "$DB_NODE_LABEL" ] || return 0

  log "Labelling k3s-agent-1 with ${DB_NODE_LABEL}"
  if ! retry 30 5 probe k3s-server "sudo k3s kubectl get node k3s-agent-1"; then
    warn "k3s-agent-1 is not registered yet, skipping the label"
    return 0
  fi

  if ! in_vm k3s-server "sudo k3s kubectl label node k3s-agent-1 ${DB_NODE_LABEL} --overwrite" >"$NULLOUT" 2>&1; then
    warn "cannot apply the label: $(tail -1 "$NULLOUT")"
    return 0
  fi

  if probe k3s-server "sudo k3s kubectl get nodes -l ${DB_NODE_LABEL} --no-headers | grep -qw k3s-agent-1"; then
    ok "label applied"
  else
    warn "k3s-agent-1 does not carry ${DB_NODE_LABEL}, the database pod will stay Pending"
  fi
}

export_kubeconfig() {
  log "Writing the kubeconfig to ${KUBECONFIG_OUT}"

  in_vm k3s-server "sudo cat /etc/rancher/k3s/k3s.yaml" \
    | sed "s#https://127.0.0.1:6443#https://${SERVER_IP}:6443#" > "$KUBECONFIG_OUT" \
    || die "cannot export the kubeconfig"

  [ -s "$KUBECONFIG_OUT" ] || die "the exported kubeconfig is empty"
  chmod 600 "$KUBECONFIG_OUT"
  ok "export KUBECONFIG=${KUBECONFIG_OUT}"
}

wait_ready() {
  log "Waiting for the three nodes to be Ready"
  retry 60 5 probe k3s-server \
    "sudo k3s kubectl get nodes --no-headers 2>/dev/null | grep -cw Ready | grep -qx 3" \
    || warn "the cluster is not fully Ready yet, current state below"
  in_vm k3s-server "sudo k3s kubectl get nodes -o wide" || true
}


destroy() {
  log "Deleting the virtual machines"
  for vm in "${NODES[@]}"; do
    if vm_exists "$vm"; then
      multipass delete "$vm"
    fi
  done
  multipass purge
  ok "cluster removed"
}

status() {
  multipass list
  if vm_exists k3s-server; then
    in_vm k3s-server "sudo k3s kubectl get nodes -o wide"
  fi
}


case "${1:-up}" in
  up)
    check_prereqs
    launch_vms
    detect_network
    configure_static_ips
    install_server
    join_agents
    label_nodes
    export_kubeconfig
    wait_ready
    printf '\n%sCluster ready.%s  kubectl --kubeconfig %s get nodes\n' "$GREEN" "$OFF" "$KUBECONFIG_OUT"
    ;;
  destroy)
    check_prereqs
    destroy
    ;;
  status)
    check_prereqs
    status
    ;;
  *)
    die "unknown command: $1 (use: up | status | destroy)"
    ;;
esac