enum MatchingStatus {
  none,
  searching,
  proposed,
  matched;

  static MatchingStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'searching':
        return MatchingStatus.searching;
      case 'proposed':
        return MatchingStatus.proposed;
      case 'matched':
        return MatchingStatus.matched;
      case 'none':
      default:
        return MatchingStatus.none;
    }
  }
}

class PartnerProfileModel {
  final String name;
  final String? avatarUrl;
  final String timezone;
  final int utcOffsetHours;

  const PartnerProfileModel({
    required this.name,
    this.avatarUrl,
    required this.timezone,
    required this.utcOffsetHours,
  });

  factory PartnerProfileModel.fromJson(Map<String, dynamic> json) {
    return PartnerProfileModel(
      name: json['name'] as String? ?? 'Partner',
      avatarUrl: json['avatar_url'] as String?,
      timezone: json['timezone'] as String? ?? 'UTC',
      utcOffsetHours: json['utc_offset_hours'] is num
          ? (json['utc_offset_hours'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar_url': avatarUrl,
        'timezone': timezone,
        'utc_offset_hours': utcOffsetHours,
      };
}

class PartnerGoalModel {
  final String title;
  final String category;
  final String pace;

  const PartnerGoalModel({
    required this.title,
    required this.category,
    required this.pace,
  });

  factory PartnerGoalModel.fromJson(Map<String, dynamic> json) {
    return PartnerGoalModel(
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      pace: json['pace'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'pace': pace,
      };
}

class MatchProposalModel {
  final String id;
  final String myResponse; // 'pending' | 'accepted'
  final DateTime expiresAt;
  final PartnerProfileModel partner;
  final PartnerGoalModel partnerGoal;

  const MatchProposalModel({
    required this.id,
    required this.myResponse,
    required this.expiresAt,
    required this.partner,
    required this.partnerGoal,
  });

  bool get isAccepted => myResponse == 'accepted';
  bool get isPending => myResponse == 'pending';

  factory MatchProposalModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedExpires;
    try {
      parsedExpires = DateTime.parse(json['expires_at'] as String);
    } catch (_) {
      parsedExpires = DateTime.now().add(const Duration(hours: 12));
    }

    return MatchProposalModel(
      id: json['id'] as String? ?? '',
      myResponse: json['my_response'] as String? ?? 'pending',
      expiresAt: parsedExpires,
      partner: PartnerProfileModel.fromJson(
        json['partner'] as Map<String, dynamic>? ?? {},
      ),
      partnerGoal: PartnerGoalModel.fromJson(
        json['partner_goal'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'my_response': myResponse,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'partner': partner.toJson(),
        'partner_goal': partnerGoal.toJson(),
      };
}

class MatchingStateModel {
  final MatchingStatus status;
  final String? requestId;
  final String? podId;
  final MatchProposalModel? proposal;
  final String? rejectionBannerMessage;

  const MatchingStateModel({
    required this.status,
    this.requestId,
    this.podId,
    this.proposal,
    this.rejectionBannerMessage,
  });

  bool get isNone => status == MatchingStatus.none;
  bool get isSearching => status == MatchingStatus.searching;
  bool get isProposed => status == MatchingStatus.proposed;
  bool get isMatched => status == MatchingStatus.matched;

  factory MatchingStateModel.fromJson(
    Map<String, dynamic> json, {
    String? rejectionBannerMessage,
  }) {
    final statusStr = json['state'] as String? ?? 'none';
    final proposalJson = json['proposal'] as Map<String, dynamic>?;

    return MatchingStateModel(
      status: MatchingStatus.fromString(statusStr),
      requestId: json['request_id'] as String?,
      podId: json['pod_id'] as String?,
      proposal: proposalJson != null
          ? MatchProposalModel.fromJson(proposalJson)
          : null,
      rejectionBannerMessage: rejectionBannerMessage,
    );
  }

  MatchingStateModel copyWith({
    MatchingStatus? status,
    String? requestId,
    String? podId,
    MatchProposalModel? proposal,
    String? rejectionBannerMessage,
    bool clearBanner = false,
  }) {
    return MatchingStateModel(
      status: status ?? this.status,
      requestId: requestId ?? this.requestId,
      podId: podId ?? this.podId,
      proposal: proposal ?? this.proposal,
      rejectionBannerMessage: clearBanner
          ? null
          : (rejectionBannerMessage ?? this.rejectionBannerMessage),
    );
  }

  Map<String, dynamic> toJson() => {
        'state': status.name,
        'request_id': requestId,
        'pod_id': podId,
        'proposal': proposal?.toJson(),
      };
}
