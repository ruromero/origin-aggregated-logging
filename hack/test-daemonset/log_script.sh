#!/bin/sh

while true
do
  echo "Hello from ${HOSTNAME} at $(date)"
  sleep ${LOG_INTERVAL}
done

