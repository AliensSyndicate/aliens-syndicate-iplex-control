import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'remote_directional_pad.dart';

class RemotePage extends ConsumerStatefulWidget {
  const RemotePage({super.key, required this.deviceId});
  final String deviceId;
  @override
  ConsumerState<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends ConsumerState<RemotePage> {
  bool busy = false;
  String? commandId;
  DateTime? sentAt;

  Future<void> send(RemoteCommand command, Entry device) async {
    if (busy) return;
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).mutate('sendCommand', {
        'deviceId': device.id,
        'sessionId': device.text('sessionId'),
        'commandId': id,
        'commandType': command.name,
      });
      if (mounted) {
        setState(() {
          commandId = id;
          sentAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        showFailure(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l,
        device = ref.watch(
          entryProvider((collection: 'devices', id: widget.deviceId)),
        );
    final isOnline = ref.watch(
      clockProvider.select(
        (time) => device.value?.onlineAt(time.value ?? DateTime.now()) ?? false,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leadingWidth: AppDimensions.touch + AppSpacing.md,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md),
          child: CircularButton(
            label: l.back,
            icon: AppIcons.left,
            size: AppDimensions.touch,
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        title: Text(
          device.value?.name ?? l.remote,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: device.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.textPrimary),
        ),
        error: (e, s) => ErrorState(
          onRetry: () => ref.invalidate(
            entryProvider((collection: 'devices', id: widget.deviceId)),
          ),
        ),
        data: (d) {
          if (d == null || !isOnline) {
            return PageTemplate(
              title: l.remote,
              showBack: true,
              child: EmptyState(
                title: l.offline,
                body: l.remoteUnavailable,
                icon: AppIcons.devices,
              ),
            );
          }

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const NeumorphicStatusIndicator(online: true),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              l.online,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        // Section 5: Sculpted physical Neumorphic D-Pad
                        RemoteDirectionalPad(
                          onCommand: busy ? null : (c) => send(c, d),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        // Section 5: Bottom 3 Discrete Physical Buttons (Back, Play/Pause, Menu)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            CircularButton(
                              label: l.back,
                              icon: AppIcons.back,
                              size: 64,
                              hasSocket: true,
                              onPressed: busy
                                  ? null
                                  : () => send(RemoteCommand.back, d),
                            ),
                            CircularButton(
                              label: l.playPause,
                              icon: AppIcons.play,
                              size: 64,
                              hasSocket: true,
                              onPressed: busy
                                  ? null
                                  : () => send(RemoteCommand.playPause, d),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        if (commandId != null && sentAt != null) ...[
                          _CommandAckStatus(
                            deviceId: d.id,
                            commandId: commandId!,
                            sentAt: sentAt!,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CommandAckStatus extends ConsumerWidget {
  const _CommandAckStatus({
    required this.deviceId,
    required this.commandId,
    required this.sentAt,
  });
  final String deviceId;
  final String commandId;
  final DateTime sentAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final ack = ref
        .watch(
          entryProvider((
            collection: 'devices/$deviceId/commands',
            id: commandId,
          )),
        )
        .value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    return Text(
      ack?.text('status') == 'acknowledged'
          ? l.acknowledged
          : now.difference(sentAt).inSeconds >= 5
          ? l.noAcknowledgement
          : l.sent,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
  }
}
