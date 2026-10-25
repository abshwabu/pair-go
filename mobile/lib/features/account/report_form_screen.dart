import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/error_banner.dart';

class ReportFormScreen extends ConsumerStatefulWidget {
  final String? reportedUserId;
  final String? podId;

  const ReportFormScreen({
    super.key,
    this.reportedUserId,
    this.podId,
  });

  @override
  ConsumerState<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends ConsumerState<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    final targetUserId = widget.reportedUserId;
    if (targetUserId == null || targetUserId.isEmpty) {
      setState(() {
        _errorMessage = 'Reported user ID is missing.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final apiClient = ref.read(apiClientProvider);

    final payload = <String, dynamic>{
      'reported_user_id': targetUserId,
      'reason': _reasonController.text.trim(),
    };
    if (widget.podId != null && widget.podId!.isNotEmpty) {
      payload['pod_id'] = widget.podId;
    }

    try {
      await apiClient.post<Map<String, dynamic>>(
        '/reports',
        data: payload,
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          final dialogTheme = Theme.of(dialogCtx);
          return AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusCard,
            ),
            title: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: dialogTheme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text('Report Submitted'),
              ],
            ),
            content: const Text(
              'Thank you for reporting this issue. Our moderation team reviews every report carefully to maintain accountability and safety.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  if (mounted) {
                    context.pop();
                  }
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to submit report. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Submit Report',
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Information Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: AppRadius.borderRadiusCard,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: AppRadius.borderRadiusMd,
                        ),
                        child: Icon(
                          Icons.security_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confidential Report',
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Reports are strictly confidential and will never be shared with the person you are reporting.',
                              style: AppTypography.bodySmall.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                Text(
                  'REASON FOR REPORT',
                  style: AppTypography.labelMedium.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Please describe what happened in detail (between 10 and 1000 characters).',
                  style: AppTypography.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                TextFormField(
                  controller: _reasonController,
                  maxLines: 6,
                  maxLength: 1000,
                  enabled: !_isSubmitting,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.bodyMedium,
                  decoration: InputDecoration(
                    hintText:
                        'Describe the inappropriate behavior, harassment, or safety concern...',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.all(AppSpacing.md),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadiusInput,
                      borderSide: BorderSide(color: theme.colorScheme.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadiusInput,
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadiusInput,
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadiusInput,
                      borderSide: BorderSide(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadiusInput,
                      borderSide: BorderSide(
                        color: theme.colorScheme.error,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.length < 10) {
                      return 'Reason must be at least 10 characters long';
                    }
                    if (trimmed.length > 1000) {
                      return 'Reason cannot exceed 1000 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.xl),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    minimumSize: const Size(double.infinity, 52),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submitReport,
                  child: _isSubmitting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onError,
                          ),
                        )
                      : Text(
                          'Submit Report',
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onError,
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
