#!/usr/bin/env bash
set -e
set -u
set -o pipefail



IMAGE="24.04"
CPUS="2"
MEMORY="2G"
DISK="10G"

K3S_CHANNEL="stable"
DB_NODE_LABEL="role=database"
KUBECONFIG_OUT="$PWD/k3s-kubeconfig.yaml"

SERVER="k3s-server"
AGENT1="k3s-agent-1"
AGENT2="k3s-agent-2"

SUBNET=""
GATEWAY=""
SERVER_IP=""
AGENT1_IP=""
AGENT2_IP=""

TMP_NETPLAN=$(mktemp)
TMP_TOKEN=$(mktemp)

NULLOUT=$(mktemp)
trap 'rm -f "$TMP_NETPLAN" "$TMP_TOKEN" "$NULLOUT"' EXIT

say()  { echo; echo "==> $*"; }
ok()   { echo "    ok: $*"; }
warn() { echo "    warning: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }


TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=gtimeout
fi

run_limited() {
  local seconds=$1; shift
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

in_vm()       { run_limited "${EXEC_TIMEOUT:-60}" multipass exec "$1" -- bash -c "$2" </dev/null; }
in_vm_quiet() { run_limited "${PROBE_TIMEOUT:-10}" multipass exec "$1" -- bash -c "( $2 ) >/dev/null 2>&1" </dev/null >"$NULLOUT" 2>&1; }

wait_for() {
  local tries="$1"
  local pause="$2"
  local vm="$3"
  local command="$4"
  local i

  for (( i = 1; i <= tries; i++ )); do
    if in_vm_quiet "$vm" "$command"; then
      return 0
    fi
    sleep "$pause"
  done

  return 1
}

vm_exists() {
  multipass info "$1" > /dev/null 2>&1
}

vm_is_running() {
  multipass info "$1" 2>/dev/null | grep -i "^State" | grep -qi "running"
}


check_requirements() {
  say "Checking that Multipass is available"

  command -v multipass > /dev/null 2>&1 \
    || die "multipass is not installed - see https://multipass.run"

  multipass version > /dev/null 2>&1 \
    || die "the multipass daemon is not answering"

  ok "multipass is ready"
}


launch_one_vm() {
  local vm="$1"

  if vm_exists "$vm"; then
    if ! vm_is_running "$vm"; then
      echo "    starting $vm"
      multipass start "$vm" || die "cannot start $vm"
    fi
    ok "$vm already exists"
  else
    echo "    creating $vm (this takes a minute)"
    multipass launch "$IMAGE" \
      --name "$vm" \
      --cpus "$CPUS" \
      --memory "$MEMORY" \
      --disk "$DISK" \
      || die "cannot create $vm"
    ok "$vm created"
  fi

  wait_for 30 2 "$vm" "true" || die "$vm does not answer to 'multipass exec'"
}

launch_vms() {
  say "Creating the virtual machines"
  launch_one_vm "$SERVER"
  launch_one_vm "$AGENT1"
  launch_one_vm "$AGENT2"
  multipass list
}


find_network() {
  say "Looking at the network Multipass is using"

  wait_for 30 2 "$SERVER" "ip -4 -o addr show scope global | grep -q ." \
    || die "$SERVER has no IP address yet"

  local address
  address=$(in_vm "$SERVER" "ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -1") \
    || die "cannot read the address of $SERVER"

  SUBNET=$(echo "$address" | cut -d. -f1-3)

  GATEWAY=$(in_vm "$SERVER" "ip -4 route show default | awk '{print \$3}' | head -1") || GATEWAY=""
  if [ -z "$GATEWAY" ]; then
    GATEWAY="$SUBNET.1"
  fi

  SERVER_IP="$SUBNET.241"
  AGENT1_IP="$SUBNET.242"
  AGENT2_IP="$SUBNET.243"

  echo "    subnet:        $SUBNET.0/24"
  echo "    gateway:       $GATEWAY"
  echo "    control plane: $SERVER_IP"
  echo "    workers:       $AGENT1_IP, $AGENT2_IP"
}


netplan_id_of() {
  local id
  id=$(in_vm "$1" "sudo netplan get ethernets 2>/dev/null | awk '/^[A-Za-z0-9_.-]+:/{sub(/:.*/,\"\"); print; exit}'" 2>/dev/null) || id=""
  if [ "$id" = "null" ]; then
    id=""
  fi
  echo "$id"
}

set_static_ip() {
  local vm="$1"
  local ip="$2"

  if in_vm_quiet "$vm" "ip -4 -o addr show | grep -q ' $ip/24 '"; then
    ok "$vm already has $ip"
    return 0
  fi

  local interface
  interface=$(in_vm "$vm" "ip -4 route show default | awk '{print \$5}' | head -1") \
    || die "$vm: cannot find the network interface"
  [ -n "$interface" ] || die "$vm: cannot find the network interface"

  local id
  id=$(netplan_id_of "$vm")
  [ -n "$id" ] || id="$interface"

  cat > "$TMP_NETPLAN" <<EOF
network:
  version: 2
  ethernets:
    # This key must match the one cloud-init already uses (often "default",
    # not the kernel name) or netplan writes a second, ignored .network unit.
    $id:
      # DHCP stays ON. Multipass uses the DHCP lease to reach the VM, so
      # turning it off would break "multipass exec" and you would have to
      # repair the machine from its console.
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
      # The fixed address we actually want Kubernetes to use.
      addresses: [$ip/24]
      routes:
        - to: default
          via: $GATEWAY
EOF

  multipass transfer "$TMP_NETPLAN" "$vm:/tmp/99-k3s-static.yaml" \
    || die "$vm: cannot copy the netplan file"

  in_vm "$vm" "sudo install -m 600 -o root -g root /tmp/99-k3s-static.yaml /etc/netplan/99-k3s-static.yaml" \
    || die "$vm: cannot install the netplan file"

  if ! in_vm "$vm" "sudo netplan generate"; then
    in_vm "$vm" "sudo rm -f /etc/netplan/99-k3s-static.yaml" || true
    die "$vm: netplan refused this configuration"
  fi

  in_vm "$vm" "sudo systemd-run --collect --unit=k3s-netplan --no-block netplan apply" || true

  if ! wait_for 45 2 "$vm" "ip -4 -o addr show | grep -q ' $ip/24 '"; then
    undo_static_ip "$vm"
    die "$vm: the address $ip never came up"
  fi

  if ! wait_for 20 3 "$vm" "ip -4 route show default | grep -q . && getent hosts get.k3s.io > /dev/null"; then
    undo_static_ip "$vm"
    die "$vm: lost its default route or DNS after the change"
  fi

  ok "$vm -> $ip (interface $interface, netplan id '$id')"
}

undo_static_ip() {
  local vm="$1"
  warn "$vm: undoing the network change"
  in_vm_quiet "$vm" "sudo rm -f /etc/netplan/99-k3s-static.yaml" || true
  in_vm_quiet "$vm" "sudo systemd-run --collect --unit=k3s-netplan-undo --no-block netplan apply" || true
}



set_static_ips() {
  say "Giving each VM a fixed address"
  set_static_ip "$SERVER" "$SERVER_IP"
  set_static_ip "$AGENT1" "$AGENT1_IP"
  set_static_ip "$AGENT2" "$AGENT2_IP"
}

install_server() {
  say "Installing k3s on the control plane ($SERVER)"

  if in_vm_quiet "$SERVER" "systemctl is-active --quiet k3s"; then
    ok "k3s is already running here"
  else
    in_vm "$SERVER" "curl -sfL https://get.k3s.io | \
      INSTALL_K3S_CHANNEL=$K3S_CHANNEL sh -s - server \
        --write-kubeconfig-mode 644 \
        --node-ip $SERVER_IP \
        --advertise-address $SERVER_IP \
        --tls-san $SERVER_IP" \
      || die "the k3s server installation failed"
    ok "k3s server installed"
  fi

  wait_for 60 2 "$SERVER" "sudo test -s /var/lib/rancher/k3s/server/node-token" \
    || die "the join token never appeared"

  in_vm "$SERVER" "sudo cat /var/lib/rancher/k3s/server/node-token" > "$TMP_TOKEN" \
    || die "cannot read the join token"
  chmod 600 "$TMP_TOKEN"
  [ -s "$TMP_TOKEN" ] || die "the join token is empty"

  wait_for 60 3 "$SERVER" "sudo k3s kubectl get --raw /readyz > /dev/null" \
    || warn "the API server is not ready yet, carrying on anyway"
}


join_agent() {
  local vm="$1"
  local ip="$2"

  if in_vm_quiet "$vm" "systemctl is-active --quiet k3s-agent"; then
    ok "$vm has already joined"
    return 0
  fi

  wait_for 30 3 "$vm" "curl -sk --max-time 5 -o /dev/null https://$SERVER_IP:6443/ping" \
    || die "$vm cannot reach the API server at $SERVER_IP:6443"

  multipass transfer "$TMP_TOKEN" "$vm:/tmp/k3s-token" || die "$vm: cannot copy the token"
  in_vm "$vm" "chmod 600 /tmp/k3s-token"

  in_vm "$vm" "curl -sfL https://get.k3s.io | \
    INSTALL_K3S_CHANNEL=$K3S_CHANNEL \
    K3S_URL=https://$SERVER_IP:6443 \
    K3S_TOKEN=\$(cat /tmp/k3s-token) sh -s - agent --node-ip $ip" \
    || { in_vm_quiet "$vm" "rm -f /tmp/k3s-token" || true; die "$vm: the agent installation failed"; }

  in_vm "$vm" "rm -f /tmp/k3s-token" || true
  ok "$vm joined the cluster ($ip)"
}

join_agents() {
  say "Joining the workers to the cluster"
  join_agent "$AGENT1" "$AGENT1_IP"
  join_agent "$AGENT2" "$AGENT2_IP"
}

label_node() {
  say "Labelling $AGENT1 with $DB_NODE_LABEL"

  if ! wait_for 30 5 "$SERVER" "sudo k3s kubectl get node $AGENT1"; then
    warn "$AGENT1 is not registered yet, skipping the label"
    return 0
  fi

  if in_vm_quiet "$SERVER" "sudo k3s kubectl label node $AGENT1 $DB_NODE_LABEL --overwrite"; then
    ok "label applied"
  else
    warn "could not apply the label - a pod that requires it would stay Pending"
  fi
}


save_kubeconfig() {
  say "Saving the kubeconfig to $KUBECONFIG_OUT"

  in_vm "$SERVER" "sudo cat /etc/rancher/k3s/k3s.yaml" \
    | sed "s#https://127.0.0.1:6443#https://$SERVER_IP:6443#" \
    > "$KUBECONFIG_OUT" \
    || die "cannot export the kubeconfig"

  [ -s "$KUBECONFIG_OUT" ] || die "the exported kubeconfig is empty"
  chmod 600 "$KUBECONFIG_OUT"
  ok "use it with: export KUBECONFIG=$KUBECONFIG_OUT"
}


wait_until_ready() {
  say "Waiting for the three nodes to be Ready"

  wait_for 60 5 "$SERVER" \
    "sudo k3s kubectl get nodes --no-headers | grep -cw Ready | grep -qx 3" \
    || warn "the cluster is not fully Ready yet - here is its current state"

  in_vm "$SERVER" "sudo k3s kubectl get nodes -o wide" || true
}



show_status() {
  multipass list
  if vm_exists "$SERVER"; then
    in_vm "$SERVER" "sudo k3s kubectl get nodes -o wide" || true
  fi
}

destroy_cluster() {
  echo "This will delete $SERVER, $AGENT1 and $AGENT2 and everything on them."
  read -r -p "Type yes to continue: " answer
  if [ "$answer" != "yes" ]; then
    echo "Nothing was deleted."
    return 0
  fi

  say "Deleting the virtual machines"
  for vm in "$SERVER" "$AGENT1" "$AGENT2"; do
    if vm_exists "$vm"; then
      multipass delete "$vm"
    fi
  done
  multipass purge
  ok "cluster removed"
}


command="${1:-up}"

case "$command" in
  up)
    check_requirements
    launch_vms
    find_network
    set_static_ips
    install_server
    join_agents
    label_node
    save_kubeconfig
    wait_until_ready
    echo
    echo "Cluster ready. Try:"
    echo "  kubectl --kubeconfig $KUBECONFIG_OUT get nodes"
    ;;
  status)
    check_requirements
    show_status
    ;;
  destroy)
    check_requirements
    destroy_cluster
    ;;
  *)
    die "unknown command: $command (use: up, status or destroy)"
    ;;
esac