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
