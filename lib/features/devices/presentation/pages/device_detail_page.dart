import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/data/providers.dart';
import '../../../../core/design_system/components.dart';
import '../controllers/device_controller.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

  /// Last name known to be saved (the stream value or a successful rename).
  String? _savedName;

  @override
  void initState() {
    super.initState();
    // The name is edited in place: leaving the field (or "done" on the
    // keyboard) saves it.
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _saveName();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name == _savedName || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await ref
          .read(deviceRepositoryProvider)
          .renameDevice(widget.deviceId, name);
      _savedName = name;
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> unlink() async {
    final l = context.l;
    final unlinked = await confirmAndRun(
      context,
      title: l.unlinkConfirmTitle,
      body: l.unlinkConfirmBody,
      confirmLabel: l.unlinkDevice,
      operation: () =>
          ref.read(deviceRepositoryProvider).unlinkDevice(widget.deviceId),
    );
    if (unlinked && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final deviceAsync = ref.watch(deviceDetailStreamProvider(widget.deviceId));
    final admin = ref.watch(canManageResourcesProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: deviceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          onRetry: () =>
              ref.invalidate(deviceDetailStreamProvider(widget.deviceId)),
        ),
        data: (device) {
          if (device == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.notFound),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: l.backToDevices,
                    onPressed: () => context.go('/devices'),
                  ),
                ],
              ),
            );
          }

          final isOnline = device.isOnline(now);
          if (!_nameFocus.hasFocus && _savedName != device.displayName) {
            _savedName = device.displayName;
            _name.text = device.displayName;
          }

          String linkedDateStr = '-';
          if (device.linkedAt != null) {
            linkedDateStr = DateFormat.yMd(locale).format(device.linkedAt!);
          }

          String lastSeenStr = l.neverActive;
          if (device.lastSeenAt != null &&
              device.lastSeenAt!.millisecondsSinceEpoch > 0) {
            lastSeenStr = DateFormat.yMd(locale)
                .add_Hm()
                .format(device.lastSeenAt!);
          }

          return PageTemplate(
            title: device.displayName,
            showBack: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(
                              AppIcons.devices,
                              size: AppSpacing.xxl,
                              color: isOnline
                                  ? AppColors.accent
                                  : AppColors.textDisabled,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      NeumorphicStatusIndicator(
                                        online: isOnline,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isOnline ? l.online : l.offline,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: isOnline
                                              ? AppColors.textPrimary
                                              : AppColors.textDisabled,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${l.lastSeen}: $lastSeenStr',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(height: 1, color: AppColors.borderDark),
                        const SizedBox(height: AppSpacing.md),
                        _InfoRow(
                          label: l.platformLabel,
                          value: device.platformLabel,
                        ),
                        if (device.manufacturer.isNotEmpty)
                          _InfoRow(
                            label: l.manufacturerLabel,
                            value: device.manufacturer,
                          ),
                        if (device.model.isNotEmpty)
                          _InfoRow(label: l.modelLabel, value: device.model),
                        _InfoRow(label: l.linkedAtLabel, value: linkedDateStr),
                        _InfoRow(
                          label: l.maskedIdLabel,
                          value: device.maskedId,
                        ),
                      ],
                    ),
                  ),
                ),
                if (admin) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Form(
                    key: _form,
                    child: AppTextField(
                      key: const Key('device-name-field'),
                      label: l.tvNameLabel,
                      controller: _name,
                      focusNode: _nameFocus,
                      validator: (v) =>
                          v == null || v.trim().isEmpty || v.trim().length > 80
                          ? l.requiredField
                          : null,
                    ),
                  ),
                  AppButton(
                    key: const Key('device-unlink'),
                    label: l.unlinkDevice,
                    icon: AppIcons.delete,
                    onPressed: unlink,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDisabled,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
