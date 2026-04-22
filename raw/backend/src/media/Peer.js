/**
 * Per-socket mediasoup state for a single player.
 * One player uses:
 * - one send transport for their microphone
 * - one recv transport for all remote audio consumers
 * - one audio producer (scoped to a single voice channelId)
 * - multiple consumers keyed by remote peer id
 */
export class Peer {
  constructor({
    userId,
    socket,
    isAlive = true,
    channelId = 'lobby',
  }) {
    this.userId = userId;
    this.socket = socket;
    this.isAlive = Boolean(isAlive);
    this.channelId = channelId;
    this.forceMuted = false;
    this.transport = {
      send: null,
      recv: null,
    };
    this.producer = null;
    this.consumers = new Map();
  }

  setSocket(socket) {
    this.socket = socket;
  }

  setAlive(isAlive) {
    this.isAlive = Boolean(isAlive);
  }

  setChannel(channelId) {
    this.channelId = channelId;
  }

  setForceMuted(forceMuted) {
    this.forceMuted = Boolean(forceMuted);
  }

  setTransport(direction, transport) {
    this.transport[direction] = transport;
  }

  getTransport(direction) {
    return this.transport[direction] ?? null;
  }

  removeTransport(direction) {
    this.transport[direction] = null;
  }

  setProducer(producer) {
    this.producer = producer;
  }

  addConsumer(producerPeerId, consumer) {
    this.consumers.set(producerPeerId, consumer);
  }

  removeConsumer(producerPeerId) {
    this.consumers.delete(producerPeerId);
  }

  closeTransport(direction) {
    const transport = this.getTransport(direction);
    if (!transport || transport.closed) {
      return;
    }

    transport.close();
    this.removeTransport(direction);
  }

  closeProducer() {
    if (!this.producer || this.producer.closed) {
      return;
    }

    this.producer.close();
    this.producer = null;
  }

  closeConsumers() {
    for (const consumer of this.consumers.values()) {
      if (!consumer.closed) {
        consumer.close();
      }
    }

    this.consumers.clear();
  }

  close() {
    this.closeProducer();
    this.closeConsumers();
    this.closeTransport('send');
    this.closeTransport('recv');
  }
}

export default Peer;
