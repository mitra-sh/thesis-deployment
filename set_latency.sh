#!/bin/bash
###############################################################################
#  Per‑peer latency script – attaches clsact filters with `action netem`
###############################################################################
set -euo pipefail

# ---------- FILES -----------------------------------------------------------
LAT_FILE="latencyFile.csv"
NODES_FILE="nodes_ips.txt"

# ---------- CONSTANTS --------------------------------------------------------
IFACE="enp3s0"

# ---------- ARGUMENTS --------------------------------------------------------
VM_IP="$1"                                  # this host's IP

# ---------- REQUIRE act_netem ------------------------------------------------
if ! tc actions list 2>/dev/null | grep -q netem; then
    if sudo modprobe act_netem 2>/dev/null; then
        echo "ℹ️  Loaded act_netem module."
    else
        echo "❌  Kernel/iproute2 lack netem‑action support. Aborting."
        exit 1
    fi
fi

###############################################################################
# 1. Build hostname→IP map
###############################################################################
declare -A H2IP
while read -r h ip; do H2IP["$h"]="$ip"; done < "$NODES_FILE"

###############################################################################
# 2. Attach clsact (idempotent) and add egress filters
###############################################################################
tc qdisc replace dev "$IFACE" clsact   # safe to call repeatedly

added=0
tail -n +2 "$LAT_FILE" | \
while IFS=, read -r sh dh lat; do
    sip="${H2IP[$sh]}"; dip="${H2IP[$dh]}"
    [[ "$sip" != "$VM_IP" && "$dip" != "$VM_IP" ]] && continue
    peer=$([[ "$sip" == "$VM_IP" ]] && echo "$dip" || echo "$sip")

    tc filter add dev "$IFACE" egress protocol ip prio 10 \
        flower dst_ip "$peer" action netem delay "${lat}ms" limit 1
    ((added++))
done

echo "✅  Installed $added per‑peer latency filters on egress."
