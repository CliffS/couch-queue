
Async = require 'async'
Nano = require 'nano'
EventEmitter = require 'events'

class Queue extends EventEmitter

  constructor: (@db = 'couch-queue', url = 'http://127.0.0.1:5984', @auth) ->
    super()
    if @auth?
      unless @auth.username and @auth.password
        throw new Error "Both username and password needed to authenticate"

  setup: ->
    new Promise (resolve, reject) =>
      nano = new Nano url
      if @auth?
        nano.auth @auth.username, @auth.password, (err, body, headers) =>
          return reject err if err
          resolve new Nano
            url: url
            cookie: headers['set-cookie']
      else resolve nano

  createQueue: ->
    new Promise (resolve, reject) =>
      @setup()
      .then (nano) =>
        nano.db.create @db, (err, body) =>
          if err
            throw switch err.error
              when 'file_exists'
                new Error "Database #{@db} already exists. Please delete it first"
              else
                err
          queue = nano.use @db
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
          if @auth
            design.validate_doc_update = "(doc, old, userCtx) ->
                                            throw 'Not authorised' unless userCtx.name is '#{@auth.username}'"
          queue.insert design, '_design/queue', (err, body) =>
            throw err if err
            resolve @
      .catch (err) =>
        reject err

  enqueue: (payload) ->
    new Promise (resolve, reject) =>
      @setup()
      .then (nano) =>
        queue = nano.use @db
        queue.insert
          pending: true
          enqueued: new Date
          payload: payload
        , (err) =>
          throw err if err
          resolve @
      .catch (err) =>
        reject err

  dequeue: ->
    pending = (nano) =>
      new Promise (resolve, reject) =>
        nano.db.changes @db,
          since: 'now'
          feed: 'longpoll'
          heartbeat: true
        , (err, result) =>
          return reject err if err
          resolve result.pending

    wait = (nano) =>
      any = 0
      any = await pending nano until any isnt 0
      any

    next = (nano) =>
      new Promise (resolve, reject) =>
        queue = nano.use @db
        queue.view 'queue', 'fifo',
          limit: 1
          include_docs: true
        , (err, body) =>
          return reject err if err
          if body.total_rows
            return resolve body.rows[0].doc
          await wait nano
          resolve await next nano

    insert = (queue, doc) =>
      new Promise (resolve, reject) =>
        queue.insert doc, (err, result) =>
          return reject err if err
          resolve doc.payload

    new Promise (resolve, reject) =>
      @setup()
      .then (nano) =>
        doc = null
        while doc is null
          doc = await next nano
          doc.dequeued = new Date
          doc.pending = false
          try
            resolve await insert queue, doc
          catch err
            throw err unless err.error is 'conflict'
            doc = null
      .catch (err) =>
        reject err

  count: ->
    new Promise (resolve, reject) =>
      @setup()
      .then (nano) =>
        queue = nano.use @db
        queue.view 'queue', count, (err, body) =>
          throw err if err
          count = body.rows[0].value
          resolve
            total: value[0] + value[1]
            pending: value[0]
            processed: value[1]
      .catch (err) =>
        reject err

  empty: ->
    new Promise (resolve, reject) =>
      @setup()
      .then (nano) =>
        queue = nano.use @db
        queue.list (err, body) =>
          rows = (row for row in body.rows when not row.id.match /^_design\// )
          resolve() if rows.length is 0
          jobs = []
          for row in rows
            do (row) ->
              jobs.push (callback) ->
                queue.destroy row.id, row.value.rev, callback
          Async.parallelLimit jobs, 100, (err, results) =>
            throw err if err
            nano.db.compact @db, 'queue', (err, body) =>
              throw err if err
              resolve()
      .catch (err) =>
        reject err

module.exports = Queue
