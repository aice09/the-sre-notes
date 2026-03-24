Here’s a cleaned and corrected version with the points you wanted added:

Incident Summary — RGW Bucket elderly-share Deletion Issue (Ceph 13.2.6 Mimic)

The issue started when we attempted to delete the bucket using:

radosgw-admin bucket rm --bucket elderly-share --purge-objects

The deletion failed with an error indicating that the bucket could not be deleted because of 40 incomplete multipart uploads.

Troubleshooting Steps Performed
	1.	Tried aborting multipart uploads
	•	We attempted to list and abort the incomplete multipart uploads through the S3 API.
	•	This did not work, which suggested that the multipart upload entries were stale or inconsistent.
	2.	Tried bucket repair
	•	We ran:

radosgw-admin bucket check --bucket elderly-share --fix --check-objects

	•	This also did not resolve the problem.

	3.	Tried forced bucket deletion with bypass GC
	•	We ran:

radosgw-admin bucket rm --bucket elderly-share --purge-objects --bypass-gc

	•	This still failed with the same multipart-related issue.

	4.	Checked for stale bucket instances
	•	We ran the stale-instance check and identified that elderly-share had a stale instance.
	•	This is how we confirmed that the bucket state was already inconsistent.
	5.	Removed the stale instance
	•	We used the stale-instance cleanup command for elderly-share.
	•	Even after removing the stale instance, the bucket still could not be deleted normally.
	6.	Investigated bucket index
	•	We then tried:

radosgw-admin bi list --bucket elderly-share

	•	After identifying that the bucket index path was still problematic, we decided to use BI purge.

	7.	Ran bucket index purge
	•	We executed:

radosgw-admin bi purge --bucket elderly-share --yes-i-really-mean-it



What bi purge Does

radosgw-admin bi purge removes the bucket index entries for the bucket.

That means it deletes the bucket’s logical references to:
	•	objects
	•	multipart uploads
	•	listings
	•	index records

However, it does not remove the actual object data stored in the RADOS data pool.

Why Orphans Happened After bi purge

After bi purge, the bucket index was removed, but the underlying object data still existed in the data pool. Because the metadata/index references were gone, those remaining raw objects were no longer connected to any valid bucket listing.

That is why orphan objects were created.

In short:
	•	BI purge removed the bucket index
	•	actual data objects were left behind
	•	those leftover raw objects became orphans

Why Bucket Metadata Still Existed After bi purge

bi purge only works on the bucket index. It does not remove the separate bucket metadata record.

So after bi purge, this happened:
	•	bucket index was already gone or broken
	•	bucket stats began failing with:

error getting bucket stats ret=-2
No such file or directory

	•	but the bucket metadata still existed

That is why the bucket name could still appear even though the bucket index was no longer valid.

Final Resolution

After seeing:
	•	bucket stats failure (ret=-2)
	•	missing/broken bucket index
	•	metadata still existing

we checked bucket metadata and confirmed it was still present.

We then removed the dangling metadata entry:

radosgw-admin metadata rm bucket:elderly-share

This successfully removed the bucket from RGW.

Result

The bucket was successfully removed only after:
	•	identifying and removing the stale instance
	•	purging the broken bucket index
	•	removing the remaining bucket metadata

Post-Fix Note About Orphans

After the bucket was removed, orphan objects remained in:

default.rgw.buckets.data

These orphans exist because the object data was not deleted when the bucket index and metadata were removed.

We then ran orphan discovery on the data pool and completed the orphan job.

Important Mimic Version Note

In Ceph 13.2.6 (Mimic):
	•	orphan discovery commands are available
	•	but radosgw-admin orphans rm is not supported

So in Mimic:
	•	we can identify orphan objects
	•	but there is no built-in orphans rm cleanup command through radosgw-admin

This means orphan cleanup requires:
	•	manual object removal from the pool, or
	•	upgrading Ceph to a newer version with better orphan-management tooling

⸻

If you want, I can turn this into a more formal RCA format with sections for Impact, Root Cause, Resolution, and Preventive Actions.