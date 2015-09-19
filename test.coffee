
Couch = require './src/queue.coffee'

couch = new Couch null, 'http://pro1:5984',
  username: 'cliff'
  password: 'ph10na'

couch.on 'ready', (response) ->
  console.log "Ready"
  couch.createQueue()
.on 'created', ->
  console.log "Created"
  process.exit 0
.on 'error', (err) ->
  console.log err
  process.exit 1

setTimeout ->
  console.log "DONE"
, 30000

