import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ble_duel_provider.dart';

class BleStatusWidget extends ConsumerWidget {
  const BleStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bleDuelProvider);

    return switch (state.phase) {
      BleDuelPhase.idle => const SizedBox.shrink(),
      BleDuelPhase.running => const _Chip(
          icon: Icons.bluetooth_connected,
          label: 'BLE 연결됨',
          color: Colors.green,
        ),
      BleDuelPhase.starting => const _Chip(
          icon: Icons.bluetooth_searching,
          label: 'BLE 연결 중...',
          color: Colors.orange,
          loading: true,
        ),
      BleDuelPhase.unsupported => const _Chip(
          icon: Icons.bluetooth_disabled,
          label: 'BLE 미지원',
          color: Colors.grey,
        ),
      BleDuelPhase.error => _RetryChip(
          message: state.message ?? 'BLE 통신 실패',
          onRetry: () => ref.read(bleDuelProvider.notifier).retry(),
        ),
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _RetryChip extends StatelessWidget {
  const _RetryChip({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'BLE 실패  다시 시도',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.refresh, size: 12, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
