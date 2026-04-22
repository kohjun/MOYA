import Peer from './Peer.js';

const DEFAULT_CHANNEL_ID = 'lobby';

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
 *
 * A room groups peers, and each peer is assigned to exactly one voice channel
 * at a time (e.g. 'lobby', 'game', '1on1:<peerId>:<peerId>', 'team:red').
 * Produce/consume routing is scoped to the channel — two peers only hear each
 * other when they share a channelId.
 *
 * Channels let the game master move players into sub-channels (1:1 whisper,
 * team rooms, alive vs dead) and force-mute/expel peers without tearing down
 * the whole room.
 */
export class Room {
  constructor({ roomId, router }) {
    this.roomId = roomId;
    this.router = router;
    this.peers = new Map();
    // Map<channelId, Set<peerId>>
    this.channels = new Map();
    this.voiceState = 'lobby';
  }

  // ── Channel bookkeeping ─────────────────────────────────────────────
  _addToChannel(channelId, peerId) {
    if (!this.channels.has(channelId)) {
      this.channels.set(channelId, new Set());
    }
    this.channels.get(channelId).add(peerId);
  }

  _removeFromChannel(channelId, peerId) {
    const members = this.channels.get(channelId);
    if (!members) {
      return;
    }
    members.delete(peerId);
    if (members.size === 0) {
      this.channels.delete(channelId);
    }
  }

  getChannelMembers(channelId) {
    const members = this.channels.get(channelId);
    if (!members) {
      return [];
    }
    return [...members]
      .map((peerId) => this.peers.get(peerId))
      .filter(Boolean);
  }

  inSameChannel(peerIdA, peerIdB) {
    const a = this.getPeer(peerIdA);
    const b = this.getPeer(peerIdB);
    return Boolean(a && b && a.channelId === b.channelId);
  }

  // ── Peer lifecycle ──────────────────────────────────────────────────
  addPeer({ userId, socket, isAlive = true, channelId = DEFAULT_CHANNEL_ID }) {
    const existingPeer = this.peers.get(userId);
    if (existingPeer) {
      existingPeer.setSocket(socket);
      existingPeer.setAlive(isAlive);
      return existingPeer;
    }

    const peer = new Peer({ userId, socket, isAlive, channelId });
    this.peers.set(userId, peer);
    this._addToChannel(channelId, userId);
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

  // ── Produce/Consume gating ──────────────────────────────────────────
  shouldEnableProducer(peerId) {
    const peer = this.getPeer(peerId);
    if (!peer) {
      return false;
    }

    if (peer.forceMuted) {
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

    // 채널이 다른 peer의 소리는 원천 차단.
    if (consumerPeer.channelId !== producerPeer.channelId) {
      return false;
    }

    if (producerPeer.forceMuted) {
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

  // ── Voice state transitions (applied across all channels) ────────────
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

  // ── GameMaster / admin controls ─────────────────────────────────────

  /**
   * Move a peer to a different voice channel. Cleans up the peer's producer
   * and any consumers that no longer make sense (cross-channel consumers
   * from/to this peer). Clients must re-produce and re-consume in the new
   * channel afterwards.
   *
   * Returns the peer, or null if not found.
   */
  setPeerChannel(peerId, channelId) {
    const peer = this.getPeer(peerId);
    if (!peer) {
      return null;
    }

    const previousChannel = peer.channelId;
    if (previousChannel === channelId) {
      return peer;
    }

    this._removeFromChannel(previousChannel, peerId);
    peer.setChannel(channelId);
    this._addToChannel(channelId, peerId);

    // 채널을 떠나면 이전 채널용 produce/consume은 모두 폐기한다.
    peer.closeProducer();
    peer.closeConsumers();

    // 다른 peer가 이 peer를 consume하던 항목도 정리.
    for (const other of this.peers.values()) {
      if (other.userId === peerId) {
        continue;
      }
      const consumer = other.consumers.get(peerId);
      if (consumer && !consumer.closed) {
        consumer.close();
      }
      other.removeConsumer(peerId);
    }

    this.syncPeerMediaState(peer);
    return peer;
  }

  /**
   * Server-side force mute (pause the producer and keep it paused).
   * The client's local "enabled" toggle cannot override this.
   */
  forceMutePeer(peerId) {
    const peer = this.getPeer(peerId);
    if (!peer) {
      return null;
    }
    peer.setForceMuted(true);
    this.syncPeerMediaState(peer);
    // 이 peer의 소리를 듣던 다른 peer들의 consumer도 pause 처리.
    for (const other of this.peers.values()) {
      if (other.userId === peerId) {
        continue;
      }
      const consumer = other.consumers.get(peerId);
      if (consumer && !consumer.closed) {
        safePause(consumer);
      }
    }
    return peer;
  }

  forceUnmutePeer(peerId) {
    const peer = this.getPeer(peerId);
    if (!peer) {
      return null;
    }
    peer.setForceMuted(false);
    this.syncPeerMediaState(peer);
    for (const other of this.peers.values()) {
      if (other.userId === peerId) {
        continue;
      }
      const consumer = other.consumers.get(peerId);
      if (consumer && !consumer.closed) {
        if (this.shouldEnableConsumer(other.userId, peerId)) {
          safeResume(consumer);
        }
      }
    }
    return peer;
  }

  /**
   * 강제로 peer의 producer를 닫는다 (kick from voice, 다시 produce하려면 새 Producer 필요).
   */
  forceCloseProducer(peerId) {
    const peer = this.getPeer(peerId);
    if (!peer) {
      return null;
    }
    peer.closeProducer();
    return peer;
  }

  removePeer(userId) {
    const peer = this.getPeer(userId);
    if (!peer) {
      return;
    }

    this._removeFromChannel(peer.channelId, userId);
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
    this.channels.clear();

    if (this.router && !this.router.closed) {
      this.router.close();
    }
  }
}

export default Room;
