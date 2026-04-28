// 신체정보 입력 다이얼로그.
// 게임 시작 직후 force-modal 로 표시되며, 모든 attribute 를 선택해야 닫힌다.
// 미입력 attribute 는 서버에서 'unknown' 으로 처리되어 narrowing 시 fallthrough.

import 'package:flutter/material.dart';

import '../color_chaser_models.dart';

class CcBodyProfileDialog extends StatefulWidget {
  const CcBodyProfileDialog({
    super.key,
    required this.attributes,
    required this.initial,
    required this.onSubmit,
  });

  final List<CcAttributeDef> attributes;
  final Map<String, String> initial;

  /// 제출. ack 결과 반환.
  final Future<Map<String, dynamic>> Function(Map<String, String> profile)
      onSubmit;

  @override
  State<CcBodyProfileDialog> createState() => _CcBodyProfileDialogState();
}

class _CcBodyProfileDialogState extends State<CcBodyProfileDialog> {
  late Map<String, String> _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = Map<String, String>.from(widget.initial);
  }

  bool get _isComplete =>
      widget.attributes.every((attr) => _selected.containsKey(attr.key));

  Future<void> _submit() async {
    if (_submitting || !_isComplete) return;
    setState(() => _submitting = true);
    try {
      final ack = await widget.onSubmit(_selected);
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
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 480),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.person_outline, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text(
                  '내 신체정보 입력',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '다른 사람이 미션을 성공할 때마다, 당신의 정보 한 가지가 무작위로 공개됩니다.\n'
              '정직하게 입력할수록 게임이 재미있어집니다.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.attributes
                      .map((attr) => _buildAttributeBlock(attr))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${_selected.length} / ${widget.attributes.length} 입력됨',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: (!_isComplete || _submitting) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade800,
                    disabledForegroundColor: Colors.white38,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributeBlock(CcAttributeDef attr) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            attr.label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: attr.options.map((opt) {
              final selected = _selected[attr.key] == opt.id;
              return ChoiceChip(
                label: Text(opt.label),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selected[attr.key] = opt.id);
                },
                selectedColor: Colors.cyan.shade700,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? Colors.cyan : Colors.white24,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
