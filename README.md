# couch-queue

Safe, concurrent queuing allowing multiple writers
and multiple workers using CouchDB as its backend.

The principal difference from other, similar modules
is that this will wait for another entry to become
available, if the queue is exhausted.

## Example

```javascript

static Queue = require('couch-queue');

static queue = new Queue(undefined, undefined, {
  username: 'cliff',
  password: 'pass'
});
queue.on('ready', function() {
  queue.createQueue();
})
.on('dequeued', function(data) {
  console.log("Dequeued payload " + JSON.stringify(data, null, 2));
});
.on('created', function() {
  var payload = {
    anything: "you like",
    canGo: "in here"
  }
  queue.enqueue(payload);
})




## Database Fields
* pending: boolean
* enqueued: time pushed
* dequeued: time pulled

## Installation

    npm install couch-queue

## Events

    ready

Emitted by the contructor
