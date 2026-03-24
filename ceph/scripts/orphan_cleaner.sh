# export orphanage results
mkdir -p orphan_export
rados -p default.rgw.buckets.data ls | grep '^orphanage\.scan\.list-' > orphanage_objects.txt
while read -r obj; do
  safe_name=$(echo "$obj" | tr '/:' '__')
  rados -p default.rgw.buckets.data get "$obj" "orphan_export/$safe_name"
done < orphanage_objects.txt
cat orphan_export/* | sort -u > all_orphans.txt

# filter likely-safe MPU leftovers
grep 'multipart' all_orphans.txt > orphan_multipart.txt

# dry run
while read -r o; do
  echo rados -p default.rgw.buckets.data rm "$o"
done < orphan_multipart.txt | tee orphan-delete-dryrun.log

# real delete
while read -r o; do
  echo "$(date '+%F %T') deleting $o" | tee -a orphan-delete.log
  rados -p default.rgw.buckets.data rm "$o" >> orphan-delete.log 2>&1
  sleep 0.2
done < orphan_multipart.txt

# verify
ceph -s > post-orphan-delete-ceph-s.log 2>&1
ceph df detail > post-orphan-delete-ceph-df.log 2>&1