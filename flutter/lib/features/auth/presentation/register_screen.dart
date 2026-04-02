// lib/features/auth/presentation/register_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _pwCtrl       = TextEditingController();
  final _pw2Ctrl      = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  bool _obscure       = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).register(
      email:    _emailCtrl.text.trim(),
      password: _pwCtrl.text,
      nickname: _nicknameCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen(authProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(next.error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원가입'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 닉네임
                TextFormField(
                  controller: _nicknameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '닉네임',
                    prefixIcon: Icon(Icons.person_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '닉네임을 입력하세요';
                    if (v.trim().length < 2) return '2자 이상 입력하세요';
                    if (v.trim().length > 20) return '20자 이하로 입력하세요';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 이메일
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '이메일을 입력하세요';
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(v)) return '올바른 이메일 형식이 아닙니다';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 비밀번호
                TextFormField(
                  controller: _pwCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    helperText: '6자 이상',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '비밀번호를 입력하세요';
                    if (v.length < 6) return '6자 이상 입력하세요';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 비밀번호 확인
                TextFormField(
                  controller: _pw2Ctrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: '비밀번호 확인',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                  validator: (v) {
                    if (v != _pwCtrl.text) return '비밀번호가 일치하지 않습니다';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // 회원가입 버튼
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                  ),
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('회원가입', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object? error) {
    final msg = error?.toString() ?? '';
    if (msg.contains('409') || msg.contains('ALREADY_EXISTS')) {
      return '이미 사용 중인 이메일입니다';
    }
    if (msg.contains('network') || msg.contains('SocketException')) {
      return '서버에 연결할 수 없습니다';
    }
    return '회원가입 실패: $msg';
  }
}
