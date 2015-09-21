# couch-queue

Safe, concurrent queuing allowing multiple writers
and multiple workers using CouchDB as its backend

**THis is ALPHA software. It is currently untested and not suitable
for production use**

## Fields
* pending: boolean
* enqueued: time pushed
* dequeued: time pulled
