#!/bin/bash
###############################################################################
# Docker‑Swarm overlay shaping – fixed‑size queue version
#   * per‑VM HTB cap (from CSV) + 8 KB burst
#   * per‑link netem delay
#   * per‑link netem queue with increased size (no CoDel, no fairness)
#   * AUTO‑TUNED r2q so quanta are always ≤ 60 000 B      ← NEW
###############################################################################

set -euo pipefail

LAT_FILE="latencyFile.csv"
NODES_FILE="nodes_ips.txt"
BW_FILE="/home/as00750/edgeDeviceBandwidthInfo.csv"

IFACE="enp3s0"
IFB="ifb0"

BURST="8k"          # token‑bucket cushion
PFIFO_LIMIT=10      # packets per per‑link queue
DEFAULT_BW="100mbit"
EXCL_BW="600mbit"
TOTAL_BW="700mbit"  # root rate for the interface

###############################################################################
# ── r2q auto‑sizing – keeps every quantum in the safe [1500 ; 60000] B range
###############################################################################
TOTAL_MBIT=${TOTAL_BW%mbit}                  # strip “mbit”
MAX_BPS=$(( TOTAL_MBIT * 125000 ))           # 1 Mbit = 125 000 B/s
R2Q=$(( (MAX_BPS + 59999) / 60000 ))         # ceil(MAX_BPS / 60000)
echo "✓ r2q picked automatically: $R2Q (root rate $TOTAL_BW)"

###############################################################################
# ── per‑VM bandwidth caps (read once so we can show them early)
###############################################################################
VM_IP="$1"
VM_NAME=$(hostname)

row=$(grep -E "^${VM_NAME}," "$BW_FILE" || true)
[[ -z $row ]] && { echo "No BW limits for $VM_NAME"; exit 1; }
IN_BW=$( echo "$row" | awk -F',' '{print $2}')   # in Mbit
OUT_BW=$(echo "$row" | awk -F',' '{print $3}')   # in Mbit

echo "VM=$VM_NAME  IP=$VM_IP   IN=${IN_BW}M  OUT=${OUT_BW}M"

###############################################################################
# ── host→IP map (used later for per‑link limits)
###############################################################################
declare -A H2IP; while read -r h ip; do H2IP["$h"]="$ip"; done < "$NODES_FILE"

###############################################################################
# ── reset existing qdiscs
###############################################################################
tc qdisc del dev "$IFACE" root    2>/dev/null || true
tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
ip link del "$IFB" 2>/dev/null || true
modprobe ifb numifbs=1
ip link add "$IFB" type ifb
ip link set "$IFB" up

###############################################################################
# 1. OUTBOUND ( $IFACE )
###############################################################################
tc qdisc add dev "$IFACE" root handle 1: htb default 99 r2q "$R2Q"
tc class  add dev "$IFACE" parent 1: classid 1:1  htb rate $TOTAL_BW

tc class  add dev "$IFACE" parent 1:1 classid 1:21 htb rate $EXCL_BW ceil $EXCL_BW
tc class  add dev "$IFACE" parent 1:1 classid 1:22 htb \
        rate ${OUT_BW}mbit ceil ${OUT_BW}mbit burst $BURST cburst $BURST
tc class  add dev "$IFACE" parent 1:1 classid 1:30 htb \
        rate $DEFAULT_BW   ceil $DEFAULT_BW   burst $BURST cburst $BURST

tc filter add dev "$IFACE" protocol ip parent 1: prio 10 u32 \
        match ip dst 192.168.122.98/32 flowid 1:21
tc filter add dev "$IFACE" protocol ip parent 1: prio 11 u32 \
        match ip protocol 17 0xff match ip dport 4789 0xffff flowid 1:22
tc filter add dev "$IFACE" parent 1: prio 20 u32 match u32 0 0 flowid 1:30

# child HTB trees for overlay (bolt traffic) and “everything else”
tc qdisc add dev "$IFACE" parent 1:22 handle 220: htb default 99 r2q "$R2Q"
tc qdisc add dev "$IFACE" parent 1:30 handle 300: htb default 99 r2q "$R2Q"

# ── per‑link delay + queue
tail -n +2 "$LAT_FILE" | \
while IFS=, read -r sh dh lat; do
  sip="${H2IP[$sh]}"; dip="${H2IP[$dh]}"
  [[ "$sip" != "$VM_IP" && "$dip" != "$VM_IP" ]] && continue
  peer=$([[ "$sip" == "$VM_IP" ]] && echo "$dip" || echo "$sip")
  minor=$(echo "$peer" | awk -F'.' '{print $4}')

  for ROOT in 220 300; do
    cls="${ROOT}:${minor}"
    tc class add dev "$IFACE" parent "${ROOT}:" classid "$cls" \
            htb rate $DEFAULT_BW burst $BURST cburst $BURST
    handle=$(( (ROOT/10)*256 + minor ))     # safe < 4096
    tc qdisc add dev "$IFACE" parent "$cls" handle "${handle}:" \
            netem delay ${lat}ms limit $PFIFO_LIMIT
    tc filter add dev "$IFACE" parent "${ROOT}:" protocol ip prio 12 u32 \
            match ip src ${VM_IP}/32 match ip dst ${peer}/32 flowid "$cls"
  done
done

###############################################################################
# 2. INGRESS (  $IFB  ) – bandwidth only
###############################################################################
tc qdisc add dev "$IFACE" handle ffff: ingress
tc filter add dev "$IFACE" parent ffff: protocol ip u32 match u32 0 0 \
        action mirred egress redirect dev "$IFB"

tc qdisc add dev "$IFB" root handle 1: htb default 99 r2q "$R2Q"
tc class  add dev "$IFB" parent 1: classid 1:1  htb rate $TOTAL_BW
tc class  add dev "$IFB" parent 1:1 classid 1:21 htb rate $EXCL_BW ceil $EXCL_BW
tc class  add dev "$IFB" parent 1:1 classid 1:22 htb \
        rate ${IN_BW}mbit ceil ${IN_BW}mbit burst $BURST cburst $BURST
tc class  add dev "$IFB" parent 1:1 classid 1:30 htb \
        rate $DEFAULT_BW  ceil $DEFAULT_BW  burst $BURST cburst $BURST

tc filter add dev "$IFB" protocol ip parent 1: prio 10 u32 \
        match ip src 192.168.122.98/32 flowid 1:21
tc filter add dev "$IFB" protocol ip parent 1: prio 11 u32 \
        match ip protocol 17 0xff match ip dport 4789 0xffff flowid 1:22
tc filter add dev "$IFB" parent 1: prio 20 u32 match u32 0 0 flowid 1:30

echo "✅ fixed‑queue shaping applied (r2q $R2Q, netem limit $PFIFO_LIMIT)."
