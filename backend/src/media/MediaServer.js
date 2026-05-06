import os from 'node:os';
import * as mediasoup from 'mediasoup';
import Room from './Room.js';

const AUDIO_CODECS = [
  {
    kind: 'audio',
    mimeType: 'audio/opus',
    clockRate: 48000,
    channels: 2,
    parameters: {
      'useinbandfec': 1,
      'usedtx': 1,
      'minptime': 10,
      'stereo': 1,
      'sprop-stereo': 1,
    },
  },
];

let mediaServerInstance = null;

const getWorkerCount = () => {
  const envWorkerCount = Number(process.env.MEDIASOUP_WORKER_COUNT);
  if (Number.isInteger(envWorkerCount) && envWorkerCount > 0) {
    return envWorkerCount;
  }

  // 개발 환경에서는 9~15인 세션 규모로 충분하므로 워커 수를 작게 잡는다.
  // 매 부팅마다 CPU 코어 수만큼(보통 16-24) 워커를 띄우면
  // 노드 프로세스 시작 시간이 길어지고 dev 머신 리소스를 과점한다.
  const isProduction = process.env.NODE_ENV === 'production';
  if (!isProduction) {
    return Math.min(Math.max(os.cpus().length, 1), 2);
  }

  return Math.max(os.cpus().length, 1);
};

const buildListenInfos = () => {
  const listenIp = process.env.MEDIASOUP_LISTEN_IP || '0.0.0.0';
  const announcedAddress = process.env.MEDIASOUP_ANNOUNCED_IP || undefined;

  return [
    {
      protocol: 'udp',
      ip: listenIp,
      announcedAddress,
    },
    {
      protocol: 'tcp',
      ip: listenIp,
      announcedAddress,
    },
  ];
};

export const createMediasoupWorkers = async () => {
  const workerCount = getWorkerCount();
  const workers = [];

  for (let index = 0; index < workerCount; index += 1) {
    const worker = await mediasoup.createWorker({
      logLevel: process.env.MEDIASOUP_WORKER_LOG_LEVEL || 'warn',
      logTags: ['ice', 'dtls', 'rtp', 'rtcp'],
      rtcMinPort: Number(process.env.MEDIASOUP_RTC_MIN_PORT) || 40000,
      rtcMaxPort: Number(process.env.MEDIASOUP_RTC_MAX_PORT) || 49999,
    });

    worker.on('died', () => {
      console.error(`[mediasoup] Worker ${worker.pid} died. Restart the process to recover cleanly.`);
    });

    workers.push(worker);
  }

  return workers;
};

export class MediaServer {
  constructor({ workers, mediaCodecs = AUDIO_CODECS }) {
    this.workers = workers;
    this.mediaCodecs = mediaCodecs;
    this.rooms = new Map();
    this.nextWorkerIndex = 0;
    this.webRtcTransportOptions = {
      listenInfos: buildListenInfos(),
      enableUdp: true,
      enableTcp: true,
      preferUdp: true,
      initialAvailableOutgoingBitrate:
        Number(process.env.MEDIASOUP_INITIAL_BITRATE) || 1_000_000,
    };
  }

  getRoom(roomId) {
    return this.rooms.get(roomId) ?? null;
  }

  getNextWorker() {
    const worker = this.workers[this.nextWorkerIndex];
    this.nextWorkerIndex = (this.nextWorkerIndex + 1) % this.workers.length;
    return worker;
  }

  async createRoom(roomId) {
    const existingRoom = this.getRoom(roomId);
    if (existingRoom) {
      return existingRoom;
    }

    const worker = this.getNextWorker();
    const router = await worker.createRouter({
      mediaCodecs: this.mediaCodecs,
    });

    const room = new Room({ roomId, router });
    this.rooms.set(roomId, room);
    return room;
  }

  async getOrCreateRoom(roomId) {
    return this.getRoom(roomId) ?? this.createRoom(roomId);
  }

  removePeer(roomId, userId) {
    const room = this.getRoom(roomId);
    if (!room) {
      return;
    }

    room.removePeer(userId);

    if (room.isEmpty()) {
      room.close();
      this.rooms.delete(roomId);
    }
  }

  closeRoom(roomId) {
    const room = this.getRoom(roomId);
    if (!room) {
      return;
    }

    room.close();
    this.rooms.delete(roomId);
  }

  async close() {
    for (const roomId of this.rooms.keys()) {
      this.closeRoom(roomId);
    }

    for (const worker of this.workers) {
      if (!worker.closed) {
        await worker.close();
      }
    }
  }
}

export const initializeMediaServer = async () => {
  const workers = await createMediasoupWorkers();
  mediaServerInstance = new MediaServer({ workers });
  return mediaServerInstance;
};

export const getMediaServer = () => mediaServerInstance;

export default MediaServer;
