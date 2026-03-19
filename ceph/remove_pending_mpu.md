# Remove Pending Multipart Upload in RGW

## Lifecycle Rule (No scripting)

If you want to remove ALL incomplete multipart uploads automatically

Just set lifecycle:
```
aws --endpoint-url http://RGW:PORT \
s3api put-bucket-lifecycle-configuration \
--bucket BUCKET \
--lifecycle-configuration '{
 "Rules":[{
   "ID":"abort-mpu",
   "Status":"Enabled",
   "Filter":{"Prefix":""},
   "AbortIncompleteMultipartUpload":{
     "DaysAfterInitiation":1
   }
 }]
}'
```
Then force run lifecycle NOW:
```
radosgw-admin lc process --bucket BUCKET
```

If bucket has MANY incomplete uploads, lifecycle may take time. You can check status:
```
radosgw-admin lc list
radosgw-admin lc get --bucket BUCKET
```
This tells RGW:

> Process lifecycle NOW for this bucket.

Still not always instant instant — but MUCH faster.

This removes ALL incomplete multipart uploads, no need to know keys, upload id, and its safe for production.

## One time cleanup script (Remove ALL immediately)

This will list ALL multipart uploads using loop automatically
```bash
#!/bin/bash

echo "Enter RGW Endpoint (example: http://10.0.0.5:7480):"
read ENDPOINT

echo "Enter Bucket Name:"
read BUCKET

echo ""
echo "Cleaning incomplete multipart uploads in bucket: $BUCKET"
echo "Using endpoint: $ENDPOINT"
echo ""

aws --endpoint-url "$ENDPOINT" \
s3api list-multipart-uploads \
--bucket "$BUCKET" \
--query 'Uploads[].{Key:Key,UploadId:UploadId}' \
--output text |

while read KEY UPLOADID
do
    echo "Aborting -> Key: $KEY | UploadId: $UPLOADID"

    aws --endpoint-url "$ENDPOINT" \
    s3api abort-multipart-upload \
    --bucket "$BUCKET" \
    --key "$KEY" \
    --upload-id "$UPLOADID"

done

echo ""
echo "✅ Cleanup finished"
```
You can also download the raw file from GitHub using curl or wget and the make exectuble.
```
curl -O https://raw.githubusercontent.com/aice09/the-sre-notes/refs/heads/main/ceph/scripts/remove_pending_mpu.sh
wget https://raw.githubusercontent.com/aice09/the-sre-notes/refs/heads/main/ceph/scripts/remove_pending_mpu.sh

chmod +x cleanup-mpu.sh
./cleanup-mpu.sh
```

### Notes
- Why this happen?

  Incomplete MPU accumulates when:
    - upload interrupted
    - client timeout
    - network failure
    - rgw restart
    - app crash
  
  Ceph will NOT auto clean unless lifecycle exists.

- Space reclaim behavior after abort:
    - MPU metadata removed immediately
    - parts marked deleted
    - real disk reclaim depends on Ceph PG cleanup / GC
    - So sometimes you see AWS cleanup done but df / ceph df still same, wait a bit space will drop.
