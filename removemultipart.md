Ahhh yes 👍 you mean:

✅ Remove ALL incomplete multipart uploads in a bucket
❌ WITHOUT manually typing key / upload-id one by one

Yes — you must still use S3 API (aws cli)
But we can automate it.

There are 3 clean ways.

⸻

⭐ BEST WAY (Permanent) → Lifecycle Rule (No scripting)

If you want to remove ALL incomplete multipart uploads automatically

Just set lifecycle:

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

Then force run lifecycle NOW:

radosgw-admin lc process --bucket BUCKET

✅ This removes ALL incomplete multipart uploads
✅ No need to know keys
✅ No need upload id
✅ Safe
✅ Production recommended

⸻

⭐ WAY 2 — One time cleanup script (Remove ALL immediately)

This will:
	•	list ALL multipart uploads
	•	loop
	•	abort automatically

No manual typing.

Script

#!/bin/bash

BUCKET="mybucket"
ENDPOINT="http://RGW:PORT"

aws --endpoint-url $ENDPOINT \
s3api list-multipart-uploads \
--bucket $BUCKET \
--query 'Uploads[].{Key:Key,UploadId:UploadId}' \
--output text |

while read KEY UPLOADID
do
    echo "Aborting $KEY $UPLOADID"

    aws --endpoint-url $ENDPOINT \
    s3api abort-multipart-upload \
    --bucket $BUCKET \
    --key "$KEY" \
    --upload-id "$UPLOADID"

done

Run:

chmod +x cleanup.sh
./cleanup.sh

✅ removes ALL incomplete uploads
✅ no manual key input

⸻

⭐ WAY 3 — Dangerous RGW deep cleanup (NOT recommended)

There is NO safe direct radosgw-admin command like:

radosgw-admin delete-incomplete-mpu

It does NOT exist.

Because multipart metadata is stored across:
	•	bucket index
	•	data_extra_pool
	•	multipart namespace objects

Deleting raw RADOS objects will corrupt bucket.

Only lifecycle or S3 abort is supported.

⸻

⭐ VERY IMPORTANT (Why this happens)

Incomplete MPU accumulates when:
	•	upload interrupted
	•	client timeout
	•	network failure
	•	rgw restart
	•	app crash

Ceph will NOT auto clean unless lifecycle exists.

So always configure lifecycle in production.

⸻

⭐ Pro Tip (Enterprise Ceph)

If bucket has MANY incomplete uploads
Lifecycle may take time.

You can check status:

radosgw-admin lc list
radosgw-admin lc get --bucket BUCKET


⸻

🚀 If you want

I can give you next:

✅ script to clean ALL buckets in whole RGW cluster
✅ script to show how much space incomplete MPU is consuming
✅ how to find incomplete MPU using radosgw-admin bucket stats
✅ how to tune lifecycle workers for faster cleanup

Just tell me 👍