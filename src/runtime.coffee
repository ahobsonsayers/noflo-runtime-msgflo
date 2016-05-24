
Base = require 'noflo-runtime-base'
debug = debug = require('debug')('noflo-runtime-msgflo:runtime')

class SendReceivePair
  constructor: (@client, baseName, options = {}) ->
    # @client should already be connected
    @options =
      persistent: false
    for k, v of options
      @options[k] = v

    @sendName = "#{baseName}.send"
    @receiveName = "#{baseName}.receive"

  create: (callback) ->
    @client.createQueue 'inqueue', @receiveName, @options, (err) =>
      return callback err if err
      @client.createQueue 'outqueue', @sendName, @options, (err) =>
        return callback err if err

        receiveHandler = (msg) =>
          debug 'SendReceivePair.receive', msg?.data?.protocol, msg?.data?.command
          @onReceive msg.data
          @client.ackMessage msg
        return @client.subscribeToQueue @receiveName, receiveHandler, callback
      
  destroy: (callback) ->
    this.onReceive = () ->
    @client.removeQueue 'outqueue', @sendName, (sendErr) =>
      @client.removeQueue 'inqueue', @receiveName, (recvErr) =>
        # if we have two errors, we report the first
        err = sendErr
        err = recvErr if not err
        return callback err

  send: (data, callback) ->
    if not callback
      callback = () ->

    @client.sendTo 'outqueue', @sendName, data, callback

  onReceive: (data) ->
    # override

# Sends FBP runtime messages across to MsgFlo coordinator, over message queue transport
# The coordinator accepts messages from many participants, and
# can then talk FBP runtime protocol over WebSocket to a typical FBP runtime client like Flowhub
class MsgFloRuntime extends Base
  constructor: (@client, options) ->
    @options = if options then options else {}

    # TODO: support capture-stdout and capture-exceptions like noflo-nodejs? or maybe it should move to -base...
    @connection = null

  # Lifetime handling
  start: (id, callback) ->
    # NOTE: assumes @client is connected already
    @connection = new SendReceivePair @client, ".fbp.#{id}"
    @connection.onReceive (data) ->
      ctx =
        connection: @connection
      @receive data.protocol, data.command, data.payload, ctx
    @connection.create callback

  stop: (callback) ->
    @connection.destroy callback

  # Transport implementation, for Base interface
  # this.receive() should be called for data going other way, and include $context
  send: (protocol, topic, payload, context) ->
    conn = context.connection
    m =
      protocol: protocol
      command: topic
      payload: payload
    conn.send m, (err) ->
      # ignored

  sendAll: (protocol, topic, payload) ->
    # XXX: do we need to handle multiple connections (multiple coordinators?)
    ctx =
      connection: @connection
    @send protocol, topic, payload, ctx


module.exports =
  Runtime: MsgFloRuntime
  runtime: (client, options) ->
    return new MsgFloRuntime client, options
  SendReceivePair: SendReceivePair

