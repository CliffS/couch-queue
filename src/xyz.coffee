#!/usr/local/bin/coffee

Nano = require 'nano'
util = require 'util'

nano = new Nano
  url: 'http://cliff:ph10na@pro1:5984'

#nano.db.create 'xyz', (err, body) ->
#  return console.log "ERROR", err.toString() if err
#  console.log body, typeof body

#xyz = nano.use 'xyz'
#xyz.insert
#  language: "coffeescript"
#  created: new Date
#  views:
#    count:
#      map:    (doc) ->
#                emit null, 1 if doc.pending
#      reduce: (keys, values) ->
#                sum values
#    dequeued:
#      map:    (doc) ->
#                emit doc.dequeued, doc.payload unless doc.pending
#    fifo:
#      map:    (doc) ->
#                emit doc.enqueued, doc.payload if doc.pending
#, '_design/queue', (err, body) ->
#  return console.log "Error", err if err
#  console.log body

counter = 0
int = setInterval ->
  process.stdout.write '.'
  if ++counter % 60 is 0 then process.stdout.write "\n"
, 1000

nano.db.changes 'alice', (err, result) ->
  seq = result.last_seq
  nano.db.changes 'alice',
    feed: 'longpoll'
    since: seq
    heartbeat: true
  , (err, result) ->
    clearInterval int
    process.stdout.write "\n"
    console.log util.inspect (if err then err.toString() else result),
      depth: null
      colors: true

