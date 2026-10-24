import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'models/blocked_user_model.dart';

class BlockedUsersState {
  final List<BlockedUserModel> blocks;
  final bool isLoading;
  final String? errorMessage;

  const BlockedUsersState({
    this.blocks = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  BlockedUsersState copyWith({
    List<BlockedUserModel>? blocks,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return BlockedUsersState(
      blocks: blocks ?? this.blocks,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class BlockedUsersNotifier extends Notifier<BlockedUsersState> {
  @override
  BlockedUsersState build() {
    return const BlockedUsersState();
  }

  Future<void> loadBlocks(ApiClient apiClient) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final res = await apiClient.get<dynamic>('/blocks');
      final list = <BlockedUserModel>[];
      if (res.data is List) {
        for (final item in res.data as List) {
          if (item is Map<String, dynamic>) {
            list.add(BlockedUserModel.fromJson(item));
          }
        }
      }
      state = BlockedUsersState(blocks: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load blocked users: $e',
      );
    }
  }

  Future<bool> unblock(ApiClient apiClient, String blockId) async {
    try {
      await apiClient.delete<dynamic>('/blocks/$blockId');
      final updated = state.blocks.where((b) => b.id != blockId).toList();
      state = state.copyWith(blocks: updated);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to unblock: $e');
      return false;
    }
  }
}

final blockedUsersProvider =
    NotifierProvider<BlockedUsersNotifier, BlockedUsersState>(
  BlockedUsersNotifier.new,
);
