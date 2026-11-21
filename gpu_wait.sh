#!/bin/bash
# wait until GPU has >= $1 MiB free (default 1500), max 40 min
need=${1:-1500}
for i in $(seq 1 480); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
  free=$((4096 - used))
  [ $free -ge $need ] && exit 0
  sleep 5
done
exit 1
