import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fantasy_wars_design_tokens.dart';
import 'fw_scale_tap_button.dart';

enum FwChatType { ai, user, gameEvent }

class FwChatMessage {
  const FwChatMessage({
    required this.type,
    required this.text,
    required this.createdAt,
  });

  final FwChatType type;
  final String text;
  final DateTime createdAt;
}

// ─── Layer 4: 하단 AI 채팅 시트 (드래그 확장) ─────────────────────────────
class FwAiChatSheet extends StatefulWidget {
  const FwAiChatSheet({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.messages,
    required this.sending,
    required this.currentHeight,
    required this.minHeight,
    required this.expandedHeight,
    required this.maxHeight,
    required this.onHeightChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<FwChatMessage> messages;
  final bool sending;
  final double currentHeight;
  final double minHeight;
  final double expandedHeight;
  final double maxHeight;
  final ValueChanged<double> onHeightChanged;
  final VoidCallback onSubmit;

  @override
  State<FwAiChatSheet> createState() => _FwAiChatSheetState();
}

class _FwAiChatSheetState extends State<FwAiChatSheet> {
  final ScrollController _scroll = ScrollController();
  int _lastMessageCount = 0;

  @override
  void didUpdateWidget(covariant FwAiChatSheet old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != _lastMessageCount) {
      _lastMessageCount = widget.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputBottomSafe = MediaQuery.of(context).viewInsets.bottom;
    // 기본 접힘 상태에서는 메시지 리스트를 숨겨 지도를 덜 가린다.
    // currentHeight 가 minHeight + 24 이상이면 로그 영역을 노출한다.
    final showLog = widget.currentHeight >= widget.minHeight + 24;
    // Compact preview: 로그를 펴지 않은 모든 collapsed 상태에서 최신 1줄을 보여준다.
    // minHeight 자체(=초기 진입 상태)도 포함해야 사용자가 sheet 를 잡아당기지 않고도
    // 최신 AI / 게임 이벤트를 볼 수 있다. minHeight 는 호출자 쪽에서 이 row 가 들어갈
    // 만큼 충분한 높이로 설정해야 한다.
    final showCompactPreview = !showLog;
    final latestEvent = widget.messages.isNotEmpty
        ? widget.messages.lastWhere(
            (m) => m.type == FwChatType.gameEvent || m.type == FwChatType.ai,
            orElse: () => widget.messages.last,
          )
        : null;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      // 채팅 메시지 / 입력 textfield 변경이 다른 HUD raster 를 invalidate 하지
      // 않도록 격리. RepaintBoundary 는 Positioned.child 자리에 들어가야 Stack 의
      // ParentDataWidget 계약을 깨지 않는다.
      child: RepaintBoundary(
        child: Container(
          height: widget.currentHeight + inputBottomSafe,
          decoration: const BoxDecoration(
            color: FwColors.cardSurface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(FwRadii.lg),
              topRight: Radius.circular(FwRadii.lg),
            ),
            boxShadow: FwShadows.popover,
          ),
          child: Column(
            children: [
              // 드래그 / 토글 핸들 + 봇 헤더 (온라인 표시 + 닫기/음소거)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final target =
                      showLog ? widget.minHeight : widget.expandedHeight;
                  widget.onHeightChanged(
                    target.clamp(widget.minHeight, widget.maxHeight).toDouble(),
                  );
                },
                onVerticalDragUpdate: (d) {
                  final next = (widget.currentHeight - d.delta.dy)
                      .clamp(widget.minHeight, widget.maxHeight);
                  widget.onHeightChanged(next.toDouble());
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(FwRadii.md),
                        ),
                        child: const Icon(Icons.smart_toy_outlined,
                            color: FwColors.accentInfo, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text('AI 전략 채팅',
                                    style: FwText.title.copyWith(fontSize: 15)),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: FwColors.accentHealth,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text('온라인',
                                    style: FwText.caption.copyWith(
                                      color: FwColors.accentHealth,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ],
                            ),
                            if (showLog)
                              const Text(
                                '실시간 전장 분석과 전략을 제공합니다.',
                                style: FwText.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        showLog
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_up_rounded,
                        size: 22,
                        color: FwColors.ink500,
                      ),
                    ],
                  ),
                ),
              ),
              // 메시지 리스트 — 펼친 상태에서만 노출. 접힌 상태에서는 최신 1줄만.
              if (showLog)
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    itemCount: widget.messages.length,
                    itemBuilder: (_, i) => _bubble(widget.messages[i]),
                  ),
                )
              else if (latestEvent != null && showCompactPreview)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                  child: Row(
                    children: [
                      Icon(
                        latestEvent.type == FwChatType.ai
                            ? Icons.auto_awesome_rounded
                            : Icons.bolt_rounded,
                        size: 12,
                        color: FwColors.goldStrong.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          latestEvent.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // 흰 카드 배경 위에 white70 은 거의 비가시 상태였다.
                          // ink700 으로 충분한 contrast 확보.
                          style: const TextStyle(
                            color: FwColors.ink700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // 입력창 (pill, 좌측 자물쇠 아이콘 + 우측 캡슐 전송 버튼)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    12, 4, 12, 4 + inputBottomSafe.clamp(0, 100)),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: FwColors.inputFill,
                          borderRadius: BorderRadius.circular(FwRadii.pill),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined,
                                size: 18, color: FwColors.ink500),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                autofocus: false,
                                enabled: !widget.sending,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => widget.onSubmit(),
                                style: FwText.body,
                                decoration: const InputDecoration(
                                  isCollapsed: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 14),
                                  border: InputBorder.none,
                                  hintText: 'AI에게 질문...',
                                  hintStyle: TextStyle(
                                      color: FwColors.ink500, fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FwScaleTapButton(
                      onTap: widget.sending
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              widget.onSubmit();
                            },
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: widget.sending
                              ? FwColors.ink300
                              : FwColors.accentInfo,
                          borderRadius: BorderRadius.circular(FwRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.sending)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            else
                              const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            const Text(
                              '전송',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(FwChatMessage msg) {
    switch (msg.type) {
      case FwChatType.gameEvent:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: FwColors.canvas,
                borderRadius: BorderRadius.circular(FwRadii.pill),
                border: Border.all(color: FwColors.hairline),
              ),
              child: Text(
                msg.text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: FwText.caption.copyWith(
                  color: FwColors.ink700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      case FwChatType.user:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 8, bottom: 4),
                child: Text('나', style: FwText.caption),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: FwColors.bubbleUser,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        msg.text,
                        style: FwText.body,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case FwChatType.ai:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(FwRadii.sm),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  color: FwColors.accentInfo,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 4),
                      child: Text('AI', style: FwText.caption),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: FwColors.bubbleAi,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        msg.text,
                        style: FwText.body,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}
