// 타이핑 미션 다이얼로그.
// 서버가 발급한 단어를 정해진 시간 안에 정확히 입력하면 성공.

import 'dart:async';

import 'package:flutter/material.dart';

class CcMissionDialog extends StatefulWidget {
  const CcMissionDialog({
    super.key,
    required this.word,
    required this.expiresAt,
    required this.onSubmit,
  });

  final String word;
  final int expiresAt;

  /// 답안을 받아 ack 결과를 반환. ok/success/reason 등 포함.
  final Future<Map<String, dynamic>> Function(String answer) onSubmit;

  @override
  State<CcMissionDialog> createState() => _CcMissionDialogState();
}

class _CcMissionDialogState extends State<CcMissionDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _ticker;
  int _remainingMs = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateRemaining();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _updateRemaining() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = widget.expiresAt - now;
    if (!mounted) return;
    if (remaining <= 0) {
      _ticker?.cancel();
      Navigator.of(context).pop({
        'ok': true,
        'success': false,
        'reason': 'TIMEOUT',
      });
      return;
    }
    setState(() => _remainingMs = remaining);
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final answer = _controller.text.trim();
    if (answer.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final ack = await widget.onSubmit(answer);
      if (!mounted) return;
      Navigator.of(context).pop(ack);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('제출 실패: $e')),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_remainingMs / 1000).ceil();
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      title: Row(
        children: [
          const Icon(Icons.keyboard, color: Colors.amberAccent),
          const SizedBox(width: 8),
          const Text('타이핑 미션', style: TextStyle(color: Colors.white)),
          const Spacer(),
          Text(
            '${seconds}s',
            style: TextStyle(
              color: seconds <= 3 ? Colors.redAccent : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '아래 단어를 정확히 입력하세요',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.word,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            enabled: !_submitting,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleSubmit(),
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              hintText: '여기에 입력',
              hintStyle: TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('포기'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('제출'),
        ),
      ],
    );
  }
}
