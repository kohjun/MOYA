import 'package:flutter/material.dart';

// MOYA Flutter Handoff v0.1 (2026-05-02) — Fantasy Wars 디자인 토큰.
// 시각적 변경은 모두 이 토큰을 통해서. 호스트 빌드/운영 차이가 생기면 여기서 일괄 조정.

class FwColors {
  FwColors._();

  // Brand & Surface
  static const Color canvas = Color(0xFFF2F4EE);
  // 결투 진입/룰 안내 화면처럼 살짝 따뜻한 보조 배경.
  static const Color canvasWarm = Color(0xFFEDEEE6);
  static const Color cardSurface = Colors.white;
  static const Color ink900 = Color(0xFF1F2630);
  static const Color ink700 = Color(0xFF2C3540);
  static const Color ink500 = Color(0xFF6E7682);
  static const Color ink300 = Color(0xFFB7BCC4);
  static const Color hairline = Color(0xFFE6E8EC);
  // 약한 디바이더 / 트랙 배경 (e.g. HP track, stat row bg).
  static const Color line2 = Color(0xFFEFEFEA);

  // Team & Semantic
  static const Color teamRed = Color(0xFFC0392B);
  static const Color teamRedSoft = Color(0xFFFBEDEB);
  static const Color teamBlue = Color(0xFF2A6FB8);
  static const Color teamBlueSoft = Color(0xFFE8F0F8);
  static const Color teamGreen = Color(0xFF5BAE6A);
  static const Color teamGreenSoft = Color(0xFFEBF5ED);
  static const Color teamGold = Color(0xFFE8A33D);
  static const Color teamGoldSoft = Color(0xFFFBF1E2);

  static const Color accentHealth = Color(0xFF3FA98C);
  static const Color accentInfo = Color(0xFF2F86F2);
  static const Color danger = Color(0xFFD14343);
  static const Color neutralMarker = Color(0xFF9CA3AE);
  // 결투 결과 VICTORY 등 명시적 'ok' 톤 (accentHealth 와 별개의 forest green).
  static const Color ok = Color(0xFF2D8A4E);

  // Toast / HUD 강조용 deep 톤 (Material 800–900). 위 semantic 톤보다 진하다.
  static const Color infoStrong = Color(0xFF1565C0);
  static const Color goldStrong = Color(0xFFFFD700);
  static const Color dangerStrong = Color(0xFFB71C1C);
  static const Color okStrong = Color(0xFF1B5E20);

  // Chat
  static const Color bubbleAi = Color(0xFFF4F5F7);
  static const Color bubbleUser = Color(0xFFDDEBFF);
  static const Color inputFill = Color(0xFFF4F5F7);

  // Skill colors (직업별)
  static const Color skillPriest = Color(0xFF06B6D4);
  static const Color skillMage = Color(0xFF8B5CF6);
  static const Color skillRanger = Color(0xFF10B981);
  static const Color skillRogue = Color(0xFFEF4444);

  static Color teamFromGuildId(String? guildId) => switch (guildId) {
        'guild_alpha' => teamRed,
        'guild_beta' => teamBlue,
        'guild_gamma' => teamGreen,
        'guild_delta' => teamGold,
        _ => neutralMarker,
      };

  static Color skillFromJob(String? job) => switch (job) {
        'priest' => skillPriest,
        'mage' => skillMage,
        'ranger' => skillRanger,
        'rogue' => skillRogue,
        _ => ink500,
      };
}

class FwRadii {
  FwRadii._();

  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;
}

class FwSpace {
  FwSpace._();

  static const double x4 = 4;
  static const double x8 = 8;
  static const double x12 = 12;
  static const double x16 = 16;
  static const double x20 = 20;
  static const double x24 = 24;
  static const double x32 = 32;

  static const double pageHorizontal = 16;
}

class FwShadows {
  FwShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0F1F2630),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> popover = [
    BoxShadow(
      color: Color(0x1F1F2630),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

// Pretendard 가 없으면 시스템 fallback. 폰트 등록은 pubspec 에서 별도 처리.
class FwText {
  FwText._();

  static const String _family = 'Pretendard';

  static const TextStyle display = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    color: FwColors.ink900,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    color: FwColors.ink900,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: FwColors.ink900,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w500,
    color: FwColors.ink900,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    color: FwColors.ink500,
  );

  // mono: 숫자/code 우선이지만 한글 라벨이 섞여 들어갈 수 있으므로 CJK 폰트를
  // fallback 체인 끝에 둔다. monospace / RobotoMono / Menlo / Consolas 는 한글
  // 글리프가 없어 tofu 또는 시스템 fallback 으로 떨어지면서 깨져 보였다.
  // Pretendard / NotoSansKR / NanumGothic / Apple SD Gothic Neo 는 각각
  // Android(시스템 등록 시) / 일부 디바이스 / 일부 디바이스 / iOS 에서 한글을
  // 렌더한다. 시스템에 폰트가 없으면 OS 가 다음 fallback 으로 자동 시도.
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: [
      'RobotoMono',
      'Menlo',
      'Consolas',
      'Pretendard',
      'NotoSansKR',
      'Noto Sans KR',
      'NanumGothic',
      'Apple SD Gothic Neo',
    ],
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    color: FwColors.ink900,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // 결투 화면의 대형 표시(예: VS 110px, 카운트다운 92px, 결과 스탬프 20px,
  // 편지 카드 이탤릭 대사)에 사용. 별도 폰트 자산을 추가하지 않고 플랫폼
  // 기본 serif + Pretendard fallback 으로 처리. 시각 효과는 호출부에서
  // copyWith(fontSize/letterSpacing/fontStyle) 로 조정.
  static const TextStyle serif = TextStyle(
    fontFamily: 'serif',
    fontFamilyFallback: ['Pretendard', 'Noto Serif KR'],
    fontSize: 22,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: FwColors.ink900,
    letterSpacing: -0.3,
  );
}
