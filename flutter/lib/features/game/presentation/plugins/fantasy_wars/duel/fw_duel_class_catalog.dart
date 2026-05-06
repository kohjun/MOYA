import 'package:flutter/material.dart';

import '../fantasy_wars_design_tokens.dart';

// 결투 미니게임 6종의 클래스(컨셉) 카탈로그.
// 디자인 핸드오프 shared.jsx 의 CLASSES 객체를 그대로 옮긴 것.
// - 게임마다 고유한 accent/soft 컬러를 모든 화면(VS/Brief/Play/Result) 에 일관 적용.
// - icon kind 는 FwClassEmblem 에서 SVG path 를 분기하기 위한 키.
//
// 주의: 'priest' 는 내부 키 호환을 위해 유지하되, 표시명은 모두 "러시안 룰렛" 이다.

enum FwDuelClass {
  warrior,
  mage,
  archer,
  assassin,
  priest, // 내부 키 호환용. 표시는 러시안 룰렛.
  council,
}

enum FwClassEmblemKind {
  sword,
  bow,
  rune,
  chalice,
  dagger,
  banner,
}

@immutable
class FwDuelClassData {
  const FwDuelClassData({
    required this.id,
    required this.name,
    required this.en,
    required this.accent,
    required this.soft,
    required this.icon,
  });

  final FwDuelClass id;
  final String name;
  final String en;
  final Color accent;
  final Color soft;
  final FwClassEmblemKind icon;
}

class FwDuelClasses {
  FwDuelClasses._();

  static const Map<FwDuelClass, FwDuelClassData> catalog = {
    FwDuelClass.warrior: FwDuelClassData(
      id: FwDuelClass.warrior,
      name: '전사',
      en: 'Warrior',
      accent: Color(0xFFC0392B),
      soft: Color(0xFFFBEDEB),
      icon: FwClassEmblemKind.sword,
    ),
    FwDuelClass.mage: FwDuelClassData(
      id: FwDuelClass.mage,
      name: '마법사',
      en: 'Mage',
      accent: Color(0xFF2A6FB8),
      soft: Color(0xFFE8F0F8),
      icon: FwClassEmblemKind.rune,
    ),
    FwDuelClass.archer: FwDuelClassData(
      id: FwDuelClass.archer,
      name: '궁수',
      en: 'Archer',
      accent: Color(0xFF3CB191),
      soft: Color(0xFFE2F4ED),
      icon: FwClassEmblemKind.bow,
    ),
    FwDuelClass.assassin: FwDuelClassData(
      id: FwDuelClass.assassin,
      name: '암살자',
      en: 'Assassin',
      accent: Color(0xFF1F2630),
      soft: Color(0xFFEDEEF1),
      icon: FwClassEmblemKind.dagger,
    ),
    FwDuelClass.priest: FwDuelClassData(
      id: FwDuelClass.priest,
      name: '러시안',
      en: 'Roulette',
      accent: Color(0xFF7B4A2A),
      soft: Color(0xFFF1E7DD),
      icon: FwClassEmblemKind.chalice,
    ),
    FwDuelClass.council: FwDuelClassData(
      id: FwDuelClass.council,
      name: '평의회',
      en: 'Council',
      accent: Color(0xFFE07A1F),
      soft: Color(0xFFFBEEDD),
      icon: FwClassEmblemKind.banner,
    ),
  };

  // 결투 추첨 스피너에 노출되는 미니게임 후보 (= 서버가 실제로 pickMinigame
  // 으로 뽑을 수 있는 풀과 1:1 매칭). 카운트가 두 군데 박혀 있으면 미니게임
  // 추가/제거 시 한쪽이 stale 해지므로, 카운트 표시는 모두 이 리스트의 .length
  // 에서 derive 한다.
  static const List<FwDuelClass> spinnerCandidates = <FwDuelClass>[
    FwDuelClass.warrior,
    FwDuelClass.archer,
    FwDuelClass.mage,
    FwDuelClass.priest,
    FwDuelClass.assassin,
    FwDuelClass.council,
  ];

  static int get minigamePoolSize => spinnerCandidates.length;

  static FwDuelClassData of(FwDuelClass klass) => catalog[klass]!;

  // 서버 minigameType 또는 직업 키 → FwDuelClass 매핑.
  // 미니게임이 ​​추가/리네임될 때 호출부 변경 없이 여기서 흡수.
  static FwDuelClass? fromMinigameType(String? type) => switch (type) {
        'precision' => FwDuelClass.archer,
        'rapid_tap' => FwDuelClass.warrior,
        'speed_blackjack' => FwDuelClass.mage,
        'russian_roulette' => FwDuelClass.priest,
        'reaction_time' => FwDuelClass.assassin,
        'council_bidding' => FwDuelClass.council,
        _ => null,
      };

  // MOYA 플레이어 직업(warrior/priest/mage/ranger/rogue) → 디자인 클래스 시각 매핑.
  // 진입 플로우(Battlefield/DuelRequest/DuelAccepted) 에서 플레이어 본인의
  // 클래스 뱃지 색·아이콘을 결정할 때 사용.
  // - ranger 는 활(archer) 디자인이 가장 잘 맞고
  // - rogue 는 단검(assassin) 이 잘 맞음.
  static FwDuelClass fromPlayerJob(String? job) => switch (job) {
        'warrior' => FwDuelClass.warrior,
        'priest' => FwDuelClass.priest,
        'mage' => FwDuelClass.mage,
        'ranger' => FwDuelClass.archer,
        'rogue' => FwDuelClass.assassin,
        _ => FwDuelClass.warrior,
      };

  // 결투 결과/스탬프 등에서 ok/warn 톤 헬퍼 (디자인 토큰과 한 곳에서 묶기 위해 여기 둠).
  static Color resultAccent({required bool won}) =>
      won ? FwColors.ok : FwColors.danger;
}
