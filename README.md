# couch-queue

Safe, concurrent queuing allowing multiple writers
and multiple workers using CouchDB as its backend

The principal difference from other, similar modules
is that this will wait for another entry to become
available, if the queue is exhausted.

**THis is ALPHA software. It is currently untested and not suitable
for production use**

## Fields
* pending: boolean
* enqueued: time pushed
* dequeued: time pulled
