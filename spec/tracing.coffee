
chai = require 'chai' unless chai
path = require 'path'
msgflo = require 'msgflo'
randomstring = require 'randomstring'

mount = require('..').mount

transportTests = (address) ->
  broker = null

  beforeEach (done) ->
    broker = msgflo.transport.getBroker address
    broker.connect done

  afterEach (done) ->
    broker.disconnect done

  describe 'graph with proccessed data', ->
    m = null
    options = null
    spy = null
    started = false
    participant = null
    testid = ''

    beforeEach (done) ->
      @timeout 6*1000
      testid = randomstring.generate 4
      options =
        broker: address
        graph: 'RepeatTest'
        name: '3anyone-'+testid
        trace: true # enable tracing

      spy = new msgflo.utils.spy address, "tracingspy-#{testid}", { 'repeated': "#{options.name}.OUT" }
      m = new mount.Mounter options

      broker.subscribeParticipantChange (msg) ->
        return broker.nackMessage(msg) if started
        broker.ackMessage msg

        participant = msg.data.payload 
        if participant.role != options.name
          console.log "WARN: tracing test got unexpected participant #{participant.role}" if participant.role != "tracingspy-#{testid}"
          return

        started = true
        spy.startSpying (err) ->
          return done err if err
          # process some data
          spy.getMessages 'repeated', 1, (messages) ->
            data = messages[0]
            err = if data.repeat == 'this!' then null else new Error "wrong output data: #{JSON.stringify(data)}"
            done err
#            spy.stop done
          broker.sendTo 'inqueue', "#{participant.role}.IN", { repeat: 'this!' }, (err) ->
            return done err if err

      m.start (err) ->
        return done err if err

    afterEach (done) ->
      m.stop done

    describe 'triggering with FBP protocol message', ->
      it 'should return it over FBP protocol', (done) ->
        @timeout 4*1000

        # TODO: have these queues declared in the discovery message. Don't rely on convention
        fbpQueue =
          IN: ".fbp.#{participant.id}.receive"
          OUT: ".fbp.#{participant.id}.send"
        msg =
          protocol: 'trace'
          command: 'dump'
          payload:
            graph: 'default'
            type: 'flowtrace.json'
        onTraceReceived = (data) ->
          #console.log 'got trace', data
          chai.expect(data).to.have.keys [ 'protocol', 'command', 'payload' ]
          chai.expect(data.protocol).to.eql 'trace'
          chai.expect(data.command).to.eql 'dump'
          p = data.payload
          chai.expect(p).to.have.keys ['graph', 'type', 'flowtrace']
          chai.expect(p.type).to.eql 'flowtrace.json'
          trace = JSON.parse p.flowtrace
          chai.expect(trace).to.have.keys ['header', 'events']
          chai.expect(trace.events).to.be.an 'array'
          events = trace.events.map (e) -> "#{e.command}"
          chai.expect(events).to.eql ['connect', 'data', 'disconnect']
          return done()

        spy = new msgflo.utils.spy address, 'protocolspy-'+testid, { 'reply': fbpQueue.OUT }
        spy.startSpying (err) ->
          chai.expect(err).to.not.exist
          spy.getMessages 'reply', 1, (messages) ->
            onTraceReceived messages[0]
          broker.sendTo 'inqueue', fbpQueue.IN, msg, (err) ->
            chai.expect(err).to.not.exist

    describe 'enabling tracing using FBP message', ->
      it 'should respond with ack'

describe 'Tracing', () ->

    transportTests 'amqp://localhost'