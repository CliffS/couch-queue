
Async = require 'async'
Nano = require 'nano'
EventEmitter = require 'events'
QError = require './QError'

authenticate = (url, auth) ->
  new Promise (resolve, reject) ->
    nano = new Nano url
    nano.auth auth.username, auth.password, (err, body, headers) =>
      return reject err if err
      nano = new Nano
        url: url
        cookie: headers['set-cookie']
      resolve nano

class Queue extends EventEmitter

  constructor: (@db = 'couch-queue', url = 'http://127.0.0.1:5984', auth) ->
    super()
    if typeof url is 'object'
      auth = url
      url  = 'http://127.0.0.1:5984'
    time = null
    @insertQueue = Async.queue (task, callback) =>
      time = new Date unless time?
      queue = @nano.use @db
      queue.insert
        pending: true
        enqueued: new Date
        payload: task
      , (err) =>
        callback err
    , 500
    @insertQueue.drain = =>
      @emit "drained", Math.round (new Date() - time) / 1000
      time = null
    if auth?
      unless auth.username and auth.password
        return setImmediate =>
          @emit 'error', new QError 'Both username and password needed to authenticate'
      @username = auth.username
      authenticate url, auth
      .then (nano) =>
        @nano = nano
        @emit 'ready', @
        setInterval =>
          authenticate url, auth
          .then (nano) =>
            @nano = nano
        , 8 * 60 * 1000
      .catch (err) =>
        @emit 'error', new QError 'Authenticating'
    else setImmediate =>
      @nano = new Nano url
      @emit 'ready', @

  createQueue: ->
    @nano.db.create @db, (err, body) =>
      return @emit 'error', new QError err if err
      queue = @nano.use @db
      design =
        language: "coffeescript"
        views:
          count:
            map:    "(doc) -> emit null, if doc.pending then [1, 0] else [0, 1]"
            reduce: """
              (keys, values, rereduce) ->
                values.reduce (prev, current) ->
                  left = prev[0] + current[0]
                  right = prev[1] + current[1]
                  [left, right]
                , [0, 0]
                  """
          dequeued:
            map:    "(doc) -> emit doc.dequeued, doc.payload unless doc.pending"
          fifo:
            map:    "(doc) -> emit doc.enqueued, doc.payload if doc.pending"
      if @username
        design.validate_doc_update = "(doc, old, userCtx) -> throw 'Not authorised' unless userCtx.name is '#{@username}'"
      queue.insert design, '_design/queue', (err, body) =>
        return @emit 'error', new QError err if err
        @emit 'created', @
    @

  enqueue: (payload) ->
    @insertQueue.push payload, (err) =>
      return @emit 'error', new QError err if err
      @emit 'enqueued', payload
    @
      
  dequeue: ->
    queue = @nano.use @db
    queue.view 'queue', 'fifo',
      limit: 1
      include_docs: true
    , (err, body) =>
      return @emit 'error', new QError err if err
      if body.total_rows
        doc = body.rows[0].doc
        doc.dequeued = new Date
        doc.pending = false
        queue.insert doc, (err, result) =>
          return @emit 'dequeued', doc.payload unless err
          return @emit 'error', new QError err unless err.error is 'conflict'
          setTimeout =>
            do @dequeue
          , Math.floor Math.random() * 500    # Try again up to 500 ms later
      else
        @nano.db.changes @db, (err, result) =>
          return @emit 'error', new QError err if err
          @nano.db.changes @db,
            feed: 'longpoll'
            since: result.last_seq
            heartbeat: true
          , (err, result) =>
            return @emit 'error', new QError err if err
            setTimeout =>
              do @dequeue
            , Math.floor Math.random() * 500    # Try again up to 500 ms later
    @

  count: ->
    queue = @nano.use @db
    queue.view 'queue', count, (err, body) =>
      return @emit 'error', new QError err if err
      count = body.rows[0].value
      @emit 'remaining',
        total: value[0] + value[1]
        pending: value[0]
        processed: value[1]
    @

  empty: ->
    queue = @nano.use @db
    queue.list (err, body) =>
      rows = (row for row in body.rows when not row.id.match /^_design\// )
      if rows.length is 0
        return setImmediate =>
          @emit 'empty', @
      jobs = []
      for row in rows
        do (row) ->
          jobs.push (callback) ->
            queue.destroy row.id, row.value.rev, callback
      Async.parallelLimit jobs, 100, (err, results) =>
        return @emit 'error', new QError err if err
        @nano.db.compact @db, 'queue', (err, body) =>
          return @emit 'error', new QError err if err
          @emit 'empty', @
    @

module.exports = Queue
