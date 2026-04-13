const VALID_TRANSPORT_DIRECTIONS = new Set(['send', 'recv']);

const serializeTransport = (transport) => ({
  id: transport.id,
  iceParameters: transport.iceParameters,
  iceCandidates: transport.iceCandidates,
  dtlsParameters: transport.dtlsParameters,
});

const serializeConsumer = (consumer, producerPeerId) => ({
  id: consumer.id,
  producerId: consumer.producerId,
  producerPeerId,
  kind: consumer.kind,
  rtpParameters: consumer.rtpParameters,
  type: consumer.type,
  producerPaused: consumer.producerPaused,
});

const createResponder = (socket, events, callback) => {
  if (typeof callback === 'function') {
    return callback;
  }

  return (payload) => {
    if (payload?.ok === false) {
      socket.emit(events.ERROR, { code: payload.error, details: payload.details });
    }
  };
};

const resolveSessionId = (socket, sessionId) => {
  const resolvedSessionId = sessionId ?? socket.currentSessionId;

  if (!resolvedSessionId) {
    throw new Error('MISSING_SESSION_ID');
  }

  if (!socket.currentSessionId) {
    throw new Error('JOIN_SESSION_REQUIRED');
  }

  if (socket.currentSessionId !== resolvedSessionId) {
    throw new Error('SESSION_MISMATCH');
  }

  return resolvedSessionId;
};

const ensureMediaPeer = async ({
  socket,
  mediaServer,
  sessionId,
  syncRoomState,
}) => {
  const room = await mediaServer.getOrCreateRoom(sessionId);
  const peer = room.addPeer({
    userId: socket.user.id,
    socket,
    isAlive: true,
  });

  if (typeof syncRoomState === 'function') {
    await syncRoomState(sessionId, room);
  }

  return { room, peer };
};

const notifyProducerAvailability = (room, sourcePeerId, events, eventName) => {
  for (const [peerId, peer] of room.peers.entries()) {
    if (peerId === sourcePeerId) {
      continue;
    }

    peer.socket.emit(eventName, { producerPeerId: sourcePeerId });
  }
};

const clearStoredProducer = (peer, producer, room, events, eventName) => {
  if (peer.producer?.id !== producer.id) {
    return;
  }

  peer.setProducer(null);
  notifyProducerAvailability(room, peer.userId, events, eventName);
};

export const registerMediaSignalingHandlers = ({
  socket,
  mediaServer,
  events,
  syncRoomState,
}) => {
  socket.on(events.MEDIA_GET_ROUTER_RTP_CAPABILITIES, async ({ sessionId } = {}, cb) => {
    const respond = createResponder(socket, events, cb);

    try {
      const resolvedSessionId = resolveSessionId(socket, sessionId);
      const { room } = await ensureMediaPeer({
        socket,
        mediaServer,
        sessionId: resolvedSessionId,
        syncRoomState,
      });

      respond({
        ok: true,
        rtpCapabilities: room.router.rtpCapabilities,
      });
    } catch (error) {
      respond({ ok: false, error: error.message });
    }
  });

  socket.on(events.MEDIA_GET_PRODUCERS, async ({ sessionId } = {}, cb) => {
    const respond = createResponder(socket, events, cb);

    try {
      const resolvedSessionId = resolveSessionId(socket, sessionId);
      const { room } = await ensureMediaPeer({
        socket,
        mediaServer,
        sessionId: resolvedSessionId,
        syncRoomState,
      });

      const producerPeerIds = [...room.peers.values()]
        .filter((peer) => peer.userId !== socket.user.id)
        .filter((peer) => peer.producer && !peer.producer.closed)
        .map((peer) => peer.userId);

      respond({
        ok: true,
        producerPeerIds,
      });
    } catch (error) {
      respond({ ok: false, error: error.message });
    }
  });

  socket.on(events.MEDIA_CREATE_WEBRTC_TRANSPORT, async ({ sessionId, direction } = {}, cb) => {
    const respond = createResponder(socket, events, cb);

    try {
      const resolvedSessionId = resolveSessionId(socket, sessionId);

      if (!VALID_TRANSPORT_DIRECTIONS.has(direction)) {
        throw new Error('INVALID_TRANSPORT_DIRECTION');
      }

      const { room, peer } = await ensureMediaPeer({
        socket,
        mediaServer,
        sessionId: resolvedSessionId,
        syncRoomState,
      });

      peer.closeTransport(direction);

      const transport = await room.router.createWebRtcTransport({
        ...mediaServer.webRtcTransportOptions,
        appData: {
          roomId: resolvedSessionId,
          peerId: peer.userId,
          direction,
        },
      });

      transport.on('dtlsstatechange', (dtlsState) => {
        if (dtlsState === 'closed') {
          peer.removeTransport(direction);
        }
      });

      transport.on('close', () => {
        if (peer.getTransport(direction)?.id === transport.id) {
          peer.removeTransport(direction);
        }
      });

      peer.setTransport(direction, transport);

      respond({
        ok: true,
        direction,
        ...serializeTransport(transport),
      });
    } catch (error) {
      respond({ ok: false, error: error.message });
    }
  });

  socket.on(events.MEDIA_CONNECT_WEBRTC_TRANSPORT, async ({ sessionId, direction, dtlsParameters } = {}, cb) => {
    const respond = createResponder(socket, events, cb);

    try {
      const resolvedSessionId = resolveSessionId(socket, sessionId);

      if (!VALID_TRANSPORT_DIRECTIONS.has(direction)) {
        throw new Error('INVALID_TRANSPORT_DIRECTION');
      }

      const { peer } = await ensureMediaPeer({
        socket,
        mediaServer,
        sessionId: resolvedSessionId,
        syncRoomState,
      });

      const transport = peer.getTransport(direction);
      if (!transport) {
        throw new Error('TRANSPORT_NOT_FOUND');
      }

      await transport.connect({ dtlsParameters });
      respond({ ok: true });
    } catch (error) {
      respond({ ok: false, error: error.message });
    }
  });

  socket.on(events.MEDIA_PRODUCE, async ({ sessionId, kind, rtpParameters } = {}, cb) => {
    const respond = createResponder(socket, events, cb);

    try {
      const resolvedSessionId = resolveSessionId(socket, sessionId);
      if (kind !== 'audio') {
        throw new Error('ONLY_AUDIO_SUPPORTED');
      }

      const { room, peer } = await ensureMediaPeer({
        socket,
        mediaServer,
        sessionId: resolvedSessionId,
        syncRoomState,
      });

      const sendTransport = peer.getTransport('send');
      if (!sendTransport) {
        throw new Error('SEND_TRANSPORT_NOT_FOUND');
      }

      peer.closeProducer();

      const producer = await sendTransport.produce({
        kind,
        rtpParameters,
        appData: {
          roomId: resolvedSessionId,
          peerId: peer.userId,
        },
      });

      peer.setProducer(producer);

      producer.on('transportclose', () => {
        clearStoredProducer(
          peer,
          producer,
          room,
          events,
          events.MEDIA_PRODUCER_CLOSED,
        );
      });

      producer.on('close', () => {
        clearStoredProducer(
          peer,
          producer,
          room,
          events,
          events.MEDIA_PRODUCER_CLOSED,
        );
      });

      room.syncPeerMediaState(peer);
      notifyProducerAvailability(
        room,
        peer.userId,
        events,
        events.MEDIA_NEW_PRODUCER,
      );

      respond({
        ok: true,
        producerId: producer.id,
      });
    } catch (error) {
      respond({ ok: false, error: error.message });
    }
  });

  socket.on(events.MEDIA_CONSUME, async ({ sessionId, producerPeerId, rtpCapabilities } = {}, cb) => {
    const respond = createResponder(socket, events, cb);

    try {
      const resolvedSessionId = resolveSessionId(socket, sessionId);
      if (!producerPeerId) {
        throw new Error('MISSING_PRODUCER_PEER_ID');
      }
      if (producerPeerId === socket.user.id) {
        throw new Error('CANNOT_CONSUME_SELF');
      }

      const { room, peer } = await ensureMediaPeer({
        socket,
        mediaServer,
        sessionId: resolvedSessionId,
        syncRoomState,
      });

      const remotePeer = room.getPeer(producerPeerId);
      if (!remotePeer?.producer || remotePeer.producer.closed) {
        throw new Error('PRODUCER_NOT_FOUND');
      }

      const recvTransport = peer.getTransport('recv');
      if (!recvTransport) {
        throw new Error('RECV_TRANSPORT_NOT_FOUND');
      }

      if (!room.router.canConsume({
        producerId: remotePeer.producer.id,
        rtpCapabilities,
      })) {
        throw new Error('CANNOT_CONSUME');
      }

      const existingConsumer = peer.consumers.get(producerPeerId);
      if (existingConsumer && !existingConsumer.closed) {
        existingConsumer.close();
        peer.removeConsumer(producerPeerId);
      }

      const consumer = await recvTransport.consume({
        producerId: remotePeer.producer.id,
        rtpCapabilities,
        paused: !room.shouldEnableConsumer(peer.userId, producerPeerId),
        appData: {
          roomId: resolvedSessionId,
          peerId: peer.userId,
          producerPeerId,
        },
      });

      consumer.on('transportclose', () => {
        peer.removeConsumer(producerPeerId);
      });

      consumer.on('producerclose', () => {
        peer.removeConsumer(producerPeerId);
        if (!consumer.closed) {
          consumer.close();
        }
        socket.emit(events.MEDIA_PRODUCER_CLOSED, { producerPeerId });
      });

      peer.addConsumer(producerPeerId, consumer);
      room.syncPeerMediaState(peer);

      respond({
        ok: true,
        consumer: serializeConsumer(consumer, producerPeerId),
      });
    } catch (error) {
      respond({ ok: false, error: error.message });
    }
  });
};

export default registerMediaSignalingHandlers;
