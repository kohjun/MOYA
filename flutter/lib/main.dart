// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart'; // FlutterFire CLI로 생성되는 파일

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 — 실패해도 앱은 계속 실행
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[Firebase] 초기화 실패: $e');
  }

  runApp(
    const ProviderScope(
      child: LocationApp(),
    ),
  );
}
