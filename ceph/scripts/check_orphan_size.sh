#!/bin/bash

POOL="default.rgw.buckets.data"
FILE="all_orphans.txt"

TOTAL_BYTES=0
COUNT=0

while read -r OBJ
do
    SIZE=$(rados -p "$POOL" stat "$OBJ" 2>/dev/null | grep size | awk '{print $2}')
    
    if [[ -n "$SIZE" ]]; then
        TOTAL_BYTES=$((TOTAL_BYTES + SIZE))
        COUNT=$((COUNT + 1))
        echo "OK $OBJ size=$SIZE"
    else
        echo "MISS $OBJ"
    fi

done < "$FILE"

echo "--------------------------------"
echo "Objects counted: $COUNT"
echo "Total bytes: $TOTAL_BYTES"

GB=$(echo "scale=2; $TOTAL_BYTES/1024/1024/1024" | bc)
echo "Total orphan size (GB): $GB"