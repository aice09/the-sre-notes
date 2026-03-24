✅ Perfect. Here is a clean enterprise-style RCA (Root Cause Analysis) you can directly paste into ticket / Confluence / report.

I will make it:
	•	structured
	•	technically correct
	•	aligned to what REALLY happened
	•	includes orphan explanation
	•	includes Mimic limitation note

⸻

🧾 Root Cause Analysis

Incident: RGW Bucket elderly-share Cannot Be Deleted

Environment: Ceph RGW Mimic 13.2.6

⸻

🎯 Incident Summary

During storage cleanup operations, bucket elderly-share could not be deleted using standard RGW administrative commands.

Deletion attempts consistently failed with:

cannot delete bucket directory  
warning: 40 incomplete multipart uploads


⸻

🔎 Impact
	•	Bucket remained undeletable
	•	Multipart upload warnings persisted
	•	Manual cleanup operations required
	•	Potential storage consumption due to orphaned objects

No user-visible service outage occurred.

⸻

🧠 Root Cause

The issue was caused by stale multipart upload index references pointing to keys / object data that no longer existed in the RADOS data pool.

Specifically:
	•	Multipart upload metadata entries still existed in the bucket index
	•	The actual multipart object parts (keys) were already missing or corrupted
	•	RGW deletion logic requires both:
	•	zero objects
	•	zero multipart uploads

Since stale MPU metadata remained, RGW refused bucket deletion.

Additionally:
	•	The bucket had a stale bucket instance, indicating index inconsistency or reshard artifact
	•	Bucket index shards became partially invalid
	•	Garbage collection could not process cleanup because real objects were already missing

⸻

🔧 Troubleshooting Timeline

1️⃣ Multipart Abort Attempt

Multipart uploads were listed and abort operations attempted via S3 API.

Result:
	•	Abort failed because referenced keys / MPU parts did not exist
	•	Indicated ghost or stale MPU metadata

⸻

2️⃣ Bucket Repair Attempt

radosgw-admin bucket check --bucket elderly-share --fix --check-objects

Result:
	•	No change
	•	Multipart warnings persisted

⸻

3️⃣ Forced Bucket Deletion Attempt

radosgw-admin bucket rm --bucket elderly-share --purge-objects --bypass-gc

Result:
	•	Still blocked by incomplete multipart uploads

Reason:
	•	GC queue processes real objects only
	•	MPU metadata still existed

⸻

4️⃣ Stale Instance Identification

radosgw-admin reshard stale-instances list

Confirmed elderly-share bucket instance was stale.

This indicated:
	•	bucket index corruption or incomplete reshard

⸻

5️⃣ Bucket Index Purge

radosgw-admin bi purge --bucket elderly-share --yes-i-really-mean-it

Effect:
	•	Removed bucket index entries
	•	Cleared stale multipart references

Limitation:
	•	Did not remove bucket metadata
	•	Did not delete raw object data

After purge:

radosgw-admin bucket stats --bucket elderly-share

Returned:

error getting bucket stats ret=-2
No such file or directory

Meaning:
	•	bucket index already missing
	•	metadata still registered

⸻

6️⃣ Final Resolution — Metadata Removal

radosgw-admin metadata rm bucket:elderly-share

Result:
	•	Bucket successfully removed
	•	Multipart warning resolved

⸻

📦 Post-Resolution Observation — Orphan Objects

Because bucket index and metadata were manually removed:

Some raw objects remained in:

default.rgw.buckets.data

These became orphan objects, defined as:

Objects present in RADOS data pool but not referenced by any RGW bucket index.

Characteristics:
	•	Not visible to users
	•	Do not affect bucket listings
	•	Consume storage capacity

⸻

🧹 Orphan Investigation

Orphan discovery was performed:

radosgw-admin orphans find \
  --pool default.rgw.buckets.data \
  --job-id orphan-default-elderly \
  --yes-i-really-mean-it

Then finalized:

radosgw-admin orphans finish \
  --pool default.rgw.buckets.data \
  --job-id orphan-default-elderly


⸻

⚠️ Ceph Mimic Limitation

Ceph 13.2.6 (Mimic) does not provide radosgw-admin orphans rm.

Therefore:
	•	orphan objects cannot be automatically removed using RGW tooling
	•	manual RADOS deletion or cluster upgrade is required for full cleanup

⸻

📌 Recommended Follow-Up Actions
	•	Monitor RGW data pool usage:

ceph df detail

	•	Check GC queue health:

radosgw-admin gc list

	•	Plan upgrade to Nautilus or newer for improved orphan management tools
	•	Schedule storage hygiene maintenance if pool utilization increases

⸻

✅ Key Technical Lesson

In Ceph Mimic:

Stale multipart upload metadata referencing non-existent keys can make a bucket undeletable.
Resolution may require stale-instance cleanup, bucket index purge, and metadata removal, which can result in orphan objects remaining in the data pool.

⸻

If you want next, I can give you:

⭐ Preventive checklist — how to avoid ghost MPU buckets in Mimic
⭐ Quick command cheat sheet (1 page)
⭐ Upgrade risk notes Mimic → Nautilus for RGW