// src/game/VoteSystem.js
import EventBus from './EventBus.js';

const VOTE_PHASE = {
  DISCUSSION: 'discussion',
  VOTING:     'voting',
  RESULT:     'result',
  ENDED:      'ended',
};

// ─── VoteSession ────────────────────────────────────────────────────────────

class VoteSession {
  constructor({ sessionId, callerId, bodyId, reason, settings = {} }) {
    this.sessionId      = sessionId;
    this.callerId       = callerId;
    this.bodyId         = bodyId ?? null;
    this.reason         = reason;
    this.phase          = VOTE_PHASE.DISCUSSION;
    this.votes          = new Map();   // voterId → targetId
    this.preVotes       = new Map();   // voterId → targetId
    this.result         = null;
    this._timers        = [];
    this.discussionTime = settings.discussion_time ?? 90;
    this.voteTime       = settings.vote_time       ?? 30;
  }

  // ── 사전 투표 (토론 단계) ──────────────────────────────────────────────
  submitPreVote(voterId, targetId) {
    if (this.phase !== VOTE_PHASE.DISCUSSION) {
      throw new Error(`사전 투표는 토론 단계에서만 가능합니다. (현재: ${this.phase})`);
    }
    if (voterId === targetId) {
      throw new Error('자기 자신에게는 투표할 수 없습니다.');
    }
    this.preVotes.set(voterId, targetId);
  }

  // ── 본 투표 (투표 단계) ───────────────────────────────────────────────
  submitVote(voterId, targetId) {
    if (this.phase !== VOTE_PHASE.VOTING) {
      throw new Error(`아직 투표 단계가 아닙니다. (현재: ${this.phase})`);
    }
    if (voterId === targetId) {
      throw new Error('자기 자신에게는 투표할 수 없습니다.');
    }
    if (this.votes.has(voterId)) {
      throw new Error('이미 투표했습니다.');
    }
    this.votes.set(voterId, targetId);
  }

  // ── 전원 사전투표 완료 여부 ───────────────────────────────────────────
  isAllPreVoted(alivePlayers) {
    return alivePlayers.every(p => this.preVotes.has(p.userId));
  }

  // ── 전원 본투표 완료 여부 ─────────────────────────────────────────────
  isAllVoted(alivePlayers) {
    return alivePlayers.every(p => this.votes.has(p.userId));
  }

  // ── 사전 투표 이월 (아직 본투표 안 한 사람만) ─────────────────────────
  applyPreVotes() {
    for (const [voterId, targetId] of this.preVotes) {
      if (!this.votes.has(voterId)) {
        this.votes.set(voterId, targetId);
      }
    }
  }

  // ── 집계 ─────────────────────────────────────────────────────────────
  tally(alivePlayers) {
    const counts = new Map(); // targetId → count

    for (const player of alivePlayers) {
      const target = this.votes.get(player.userId) ?? 'skip';
      counts.set(target, (counts.get(target) ?? 0) + 1);
    }

    let topTarget = null;
    let topCount  = 0;
    let isTied    = false;

    for (const [target, count] of counts) {
      if (target === 'skip') continue;
      if (count > topCount) {
        topTarget = target;
        topCount  = count;
        isTied    = false;
      } else if (count === topCount) {
        isTied = true;
      }
    }

    const ejected = (!isTied && topTarget) ? topTarget : null;

    return {
      count:     Object.fromEntries(counts),
      topTarget,
      topCount,
      isTied,
      ejected,
    };
  }

  // ── 페이즈 전환 ───────────────────────────────────────────────────────
  moveToVoting() {
    this.phase = VOTE_PHASE.VOTING;
  }

  moveToResult(result) {
    this.phase  = VOTE_PHASE.RESULT;
    this.result = result;
  }

  end() {
    this.phase = VOTE_PHASE.ENDED;
    this._clearTimers();
  }

  // ── 타이머 관리 ───────────────────────────────────────────────────────
  addTimer(handle) {
    this._timers.push(handle);
  }

  _clearTimers() {
    for (const handle of this._timers) {
      clearInterval(handle);
      clearTimeout(handle);
    }
    this._timers = [];
  }

  // ── 공개 상태 직렬화 ─────────────────────────────────────────────────
  toPublicState() {
    return {
      sessionId:      this.sessionId,
      callerId:       this.callerId,
      bodyId:         this.bodyId,
      reason:         this.reason,
      phase:          this.phase,
      result:         this.result,
      voteCount:      this.votes.size,
      preVoteCount:   this.preVotes.size,
      discussionTime: this.discussionTime,
      voteTime:       this.voteTime,
    };
  }
}

// ─── VoteSystem ─────────────────────────────────────────────────────────────

class VoteSystem {
  constructor() {
    this.sessions = new Map(); // sessionId → VoteSession
  }

  // ── 미팅 시작 전 유효성 검사 ─────────────────────────────────────────
  validateMeeting(session, callerId, bodyId) {
    if (this.sessions.has(session.id)) {
      throw new Error('이미 진행 중인 회의가 있습니다.');
    }
    const caller = (session.aliveMembers ?? []).find(m => m.userId === callerId);
    if (!caller) {
      throw new Error('생존한 플레이어만 회의를 소집할 수 있습니다.');
    }
  }

  // ── 미팅 시작 ────────────────────────────────────────────────────────
  startMeeting(session, { callerId, bodyId, reason }) {
    this.validateMeeting(session, callerId, bodyId);

    const voteSession = new VoteSession({
      sessionId: session.id,
      callerId,
      bodyId,
      reason,
      settings: session,
    });

    this.sessions.set(session.id, voteSession);
    this._startDiscussionTimer(session, voteSession);
    EventBus.emit('meeting_started', { session, voteSession });

    return voteSession;
  }

  // ── 토론 타이머 ──────────────────────────────────────────────────────
  _startDiscussionTimer(session, voteSession) {
    let remaining = voteSession.discussionTime;
    let earlyEndPending = false;

    // 조기 종료 이벤트 수신
    const onEarlyEnd = () => {
      if (!earlyEndPending && remaining > 10) {
        remaining = 10;
        earlyEndPending = true;
      }
    };
    EventBus.on('discussion_early_end', onEarlyEnd);

    const handle = setInterval(() => {
      remaining -= 1;

      EventBus.emit('meeting_tick', {
        session,
        phase:     VOTE_PHASE.DISCUSSION,
        remaining,
        earlyEnd:  earlyEndPending,
      });

      if (remaining <= 0) {
        clearInterval(handle);
        EventBus.off('discussion_early_end', onEarlyEnd);
        this._startVotingPhase(session, voteSession);
      }
    }, 1000);

    voteSession.addTimer(handle);
  }

  // ── 투표 단계 전환 ────────────────────────────────────────────────────
  _startVotingPhase(session, voteSession) {
    voteSession.applyPreVotes();
    voteSession.moveToVoting();
    EventBus.emit('voting_started', { session, voteSession });

    const alivePlayers = session.aliveMembers ?? [];
    let remaining      = voteSession.voteTime;

    const handle = setInterval(() => {
      remaining -= 1;

      EventBus.emit('meeting_tick', {
        session,
        phase:     VOTE_PHASE.VOTING,
        remaining,
        earlyEnd:  false,
      });

      const done = voteSession.isAllVoted(alivePlayers) || remaining <= 0;
      if (done) {
        clearInterval(handle);
        this._processResult(session, voteSession);
      }
    }, 1000);

    voteSession.addTimer(handle);
  }

  // ── 투표/사전투표 제출 ────────────────────────────────────────────────
  submitVote(sessionId, voterId, targetId) {
    const voteSession = this.sessions.get(sessionId);
    if (!voteSession) {
      throw new Error('진행 중인 회의가 없습니다.');
    }

    if (voteSession.phase === VOTE_PHASE.DISCUSSION) {
      voteSession.submitPreVote(voterId, targetId);

      // session 객체가 없으므로 aliveMembers를 직접 확인할 수 없어
      // 집계는 외부에서 처리하도록 preVote 결과만 반환
      const count = voteSession.preVotes.size;
      const allPreVoted = false; // 외부에서 session 넘겨 확인 권장

      EventBus.emit('pre_vote_submitted', { sessionId, voterId, targetId, count });

      return { preVote: true, count };
    }

    voteSession.submitVote(voterId, targetId);
    const count = voteSession.votes.size;
    EventBus.emit('vote_submitted', { sessionId, voterId, targetId, count });

    return { preVote: false, count };
  }

  // ── 결과 처리 ─────────────────────────────────────────────────────────
  _processResult(session, voteSession) {
    // 중복 실행 방지
    if (voteSession.phase === VOTE_PHASE.RESULT || voteSession.phase === VOTE_PHASE.ENDED) {
      return;
    }

    const alivePlayers = session.aliveMembers ?? [];
    const result       = voteSession.tally(alivePlayers);

    // 추방 처리
    if (result.ejected && session.aliveMembers) {
      session.aliveMembers = session.aliveMembers.filter(
        m => m.userId !== result.ejected
      );
    }

    voteSession.moveToResult(result);
    EventBus.emit('vote_result', {
      session,
      voteSession,
      result,
      ejected: result.ejected,
    });

    const endTimer = setTimeout(() => {
      this._endMeeting(session, voteSession);
    }, 5000);

    voteSession.addTimer(endTimer);
  }

  // ── 회의 종료 ─────────────────────────────────────────────────────────
  _endMeeting(session, voteSession) {
    voteSession.end();
    this.sessions.delete(session.id);
    EventBus.emit('meeting_ended', { session, voteSession });
  }

  // ── 세션 강제 정리 ────────────────────────────────────────────────────
  cleanupSession(sessionId) {
    const voteSession = this.sessions.get(sessionId);
    if (voteSession) {
      voteSession.end();
      this.sessions.delete(sessionId);
    }
  }
}

export default new VoteSystem();
export { VOTE_PHASE };
