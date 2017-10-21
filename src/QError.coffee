
class QError extends Error

  # expects a nano error
  constructor: (err) ->
    super if typeof err is 'string' then err else err.reason
    @error = err.error ? 'syntax_error'
    Error.captureStackTrace @, QError

module.exports = QError
