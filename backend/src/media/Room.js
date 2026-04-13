import Peer from './Peer.js';

const safePause = (entity) => {
  if (!entity || entity.closed || entity.paused) {
    return;
  }

  entity.pause();
};

const safeResume = (entity) => {
  if (!entity || entity.closed || !entity.paused) {
    return;
  }

  entity.resume();
};

/**
 * mediasoup router + peer collection for one game session.
 */
export class Room {
  constructor({ roomId, router }) {
    this.roomId = roomId;
    this.router = router;
    this.peers = new Map();
    this.voiceState = 'lobby';
  }

  addPeer({ userId, socket, isAlive = true }) {
    const existingPeer = this.peers.get(userId);
    if (existingPeer) {
      existingPeer.setSocket(socket);
      existingPeer.setAlive(isAlive);
      return existingPeer;
    }

    const peer = new Peer({ userId, socket, isAlive });
    this.peers.set(userId, peer);
    return peer;
  }

  getPeer(userId) {
    return this.peers.get(userId) ?? null;
  }

  hasPeer(userId) {
    return this.peers.has(userId);
  }

  setPeerAlive(userId, isAlive) {
    const peer = this.getPeer(userId);
    if (!peer) {
      return null;
    }

    peer.setAlive(isAlive);
    this.syncPeerMediaState(peer);
    return peer;
  }

  setAlivePeers(alivePeerIds = []) {
    const aliveSet = new Set(alivePeerIds);

    for (const peer of this.peers.values()) {
      peer.setAlive(aliveSet.has(peer.userId));
    }

    this.syncAllMediaStates();
  }

  shouldEnableProducer(peerId) {
    const peer = this.getPeer(peerId);
    if (!peer) {
      return false;
    }

    if (this.voiceState === 'muted') {
      return false;
    }

    if (this.voiceState === 'meeting') {
      return peer.isAlive;
    }

    return true;
  }

  shouldEnableConsumer(consumerPeerId, producerPeerId) {
    const consumerPeer = this.getPeer(consumerPeerId);
    const producerPeer = this.getPeer(producerPeerId);

    if (!consumerPeer || !producerPeer) {
      return false;
    }

    if (this.voiceState === 'muted') {
      return false;
    }

    if (this.voiceState === 'meeting') {
      return consumerPeer.isAlive && producerPeer.isAlive;
    }

    return true;
  }

  syncPeerMediaState(peer) {
    if (!peer) {
      return;
    }

    if (peer.producer) {
      if (this.shouldEnableProducer(peer.userId)) {
        safeResume(peer.producer);
      } else {
        safePause(peer.producer);
      }
    }

    for (const [producerPeerId, consumer] of peer.consumers.entries()) {
      if (consumer.closed) {
        peer.removeConsumer(producerPeerId);
        continue;
      }

      if (this.shouldEnableConsumer(peer.userId, producerPeerId)) {
        safeResume(consumer);
      } else {
        safePause(consumer);
      }
    }
  }

  syncAllMediaStates() {
    for (const peer of this.peers.values()) {
      this.syncPeerMediaState(peer);
    }
  }

  muteAll() {
    this.voiceState = 'muted';
    this.syncAllMediaStates();
  }

  openLobbyVoice() {
    this.voiceState = 'lobby';
    this.syncAllMediaStates();
  }

  startEmergencyMeeting() {
    this.voiceState = 'meeting';
    this.syncAllMediaStates();
  }

  removePeer(userId) {
    const peer = this.getPeer(userId);
    if (!peer) {
      return;
    }

    peer.close();
    this.peers.delete(userId);
  }

  isEmpty() {
    return this.peers.size === 0;
  }

  close() {
    for (const peer of this.peers.values()) {
      peer.close();
    }

    this.peers.clear();

    if (this.router && !this.router.closed) {
      this.router.close();
    }
  }
}

export default Room;
