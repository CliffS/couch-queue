

Nano = require 'nano'
EventEmitter = require 'events'

class Queue extends EventEmitter

  constructor: (@db = 'couch-queue', url = 'http://127.0.0.1:5984', auth) ->
    nano = new Nano url
    if auth?
      unless auth.username and auth.password
        return process.nextTick =>
          @emit 'error', "Both username and password needed to authenticate"
      @username = auth.username
      nano.auth auth.username, auth.password, (err, body, headers) =>
        return @emit 'error', err.toString() if err
        @nano = new Nano
          url: url
          cookie: headers['set-cookie']
        @emit 'ready', @
    else process.nextTick =>
      @nano = nano
      @emit 'ready', @
    @setMaxListeners 0

  createQueue: ->
    @nano.db.create @db, (err, body) =>
      if err
        return @emit 'error', switch err.error
          when 'file_exists'
            "Database #{@db} already exists. Please delete it first"
          else
            err.toString()
      queue = @nano.use @db
      design =
        language: "coffeescript"
        views:
          count:
            map:    "(doc) -> emit null, 1 if doc.pending"
            reduce: "(keys, values) -> sum values"
          dequeued:
            map:    "(doc) -> emit doc.dequeued, doc.payload unless doc.pending"
          fifo:
            map:    "(doc) -> emit doc.enqueued, doc.payload if doc.pending"
      if @username
        design.validate_doc_update = "(doc, old, userCtx) -> throw 'Not authorised' unless userCtx.name is '#{@username}'"
      queue.insert design, '_design/queue', (err, body) =>
        return @emit 'error', err.toString() if err
        @emit 'created', @
        console.log "THIS", @
    @

  enqueue: (payload) ->
    queue = @nano.use @db
    queue.insert
      pending: true
      enqueued: new Date
      payload: payload
    , (err) =>
      return @emit 'error', err.toString() if err
      @emit 'enqueued', payload
    @
      
  dequeue: ->
    queue = @nano.use @db
    queue.view 'queue', 'fifo',
      limit: 1
      include_docs: true
    , (err, body) =>
      return @emit 'error', err.toString() if err
      if body.total_rows
        doc = body.rows[0].doc
        doc.dequeued = new Date
        doc.pending = false
        queue.insert doc, (err, result) =>
          return @emit 'dequeued', doc.payload unless err
          return @emit 'error', err.toString() unless err.error is 'conflict'
          setTimeout =>
            do @dequeue
          , Math.floor Math.random() * 500    # Try again up to 500 ms later
      else
        @nano.db.changes @db, (err, result) =>
          return @emit 'error', err.toString() if err
          @nano.db.changes @db,
            feed: 'longpoll'
            since: result.last_seq
            heartbeat: true
          , (err, result) =>
            return @emit 'error', err.toString() if err
            setTimeout =>
              do @dequeue
            , Math.floor Math.random() * 500    # Try again up to 500 ms later
    @

  count: ->
    queue = @nano.use @db
    queue.view 'queue', count, (err, body) =>
      return @emit 'error', err.toString() if err
      @emit 'remaining', body.rows[0].value
    @

module.exports = Queue
