✅ Nice 👍 — here is your REAL-WORLD QUICK CHEATSHEET
for Ceph RGW Ghost Bucket / Multipart / Orphan Cleanup (Mimic 13.x)

You can literally save this.

⸻

🚑 Ceph RGW Bucket Cannot Delete — QUICK CHEATSHEET (Mimic)

🎯 Symptom

cannot delete bucket
XX incomplete multipart uploads


⸻

✅ Step 1 — Try Normal MPU Abort

aws s3api list-multipart-uploads --bucket <bucket> --endpoint-url <rgw>
aws s3api abort-multipart-upload --bucket <bucket> --key <key> --upload-id <id>

⚠️ If abort fails → likely ghost MPU.

⸻

✅ Step 2 — Try Bucket Repair

radosgw-admin bucket check \
  --bucket <bucket> \
  --fix \
  --check-objects


⸻

✅ Step 3 — Try Forced Delete

radosgw-admin bucket rm \
  --bucket <bucket> \
  --purge-objects \
  --bypass-gc

If still blocked → continue.

⸻

✅ Step 4 — Check Stale Instance (VERY IMPORTANT)

radosgw-admin reshard stale-instances list

If bucket appears:

radosgw-admin reshard stale-instances rm --bucket <bucket>


⸻

✅ Step 5 — Purge Broken Bucket Index

radosgw-admin bi purge \
  --bucket <bucket> \
  --yes-i-really-mean-it

⭐ This removes:
	•	bucket listing
	•	object references
	•	multipart metadata

❗ Does NOT delete real data.

⸻

✅ Step 6 — Check Bucket Stats

radosgw-admin bucket stats --bucket <bucket>

If:

ret=-2
No such file or directory

→ index gone but metadata still exists.

⸻

✅ Step 7 — Remove Bucket Metadata (FINAL FIX)

radosgw-admin metadata get bucket:<bucket>

radosgw-admin metadata rm bucket:<bucket>

Bucket should now disappear.

⸻

📦 Orphan Objects After Fix

Orphans = raw objects left in:

default.rgw.buckets.data

Because:
	•	index removed
	•	metadata removed
	•	data objects still exist

⸻

🔍 Orphan Discovery (Mimic)

radosgw-admin orphans find \
  --pool default.rgw.buckets.data \
  --job-id orphan-<bucket> \
  --yes-i-really-mean-it

radosgw-admin orphans finish \
  --pool default.rgw.buckets.data \
  --job-id orphan-<bucket>

⚠️ Mimic has NO orphans rm command

⸻

🧹 Storage Hygiene Decision

Pool Usage	Action
<70%	ignore
70-85%	monitor
>85%	manual cleanup / upgrade


⸻

🔎 Check GC Queue

radosgw-admin gc list
radosgw-admin gc process


⸻

⭐ Real Root Cause Pattern (Remember This)

Ghost bucket deletion usually caused by:
	•	stale MPU metadata
	•	missing object keys
	•	stale bucket instance
	•	broken bucket index
	•	Mimic RGW limitations

⸻

🚀 Golden Order (Memorize)

Abort MPU
→ bucket check
→ bypass delete
→ stale-instance rm
→ bi purge
→ metadata rm
→ orphan scan


⸻

If you want next, I can give you a SUPER CHEATSHEET

👉 “How to avoid ghost multipart in Mimic”
👉 “How to detect broken RGW GC early”
👉 “When to NEVER run bi purge”

Very useful in real ops 👍