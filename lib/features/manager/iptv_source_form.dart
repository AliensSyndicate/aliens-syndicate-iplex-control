import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/domain/models.dart';
import '../../core/design_system/components.dart';

typedef FilePickerCallback =
    Future<({String name, String content, int size})?> Function();

class IptvSourceForm extends ConsumerStatefulWidget {
  const IptvSourceForm({
    super.key,
    this.id,
    this.initialName = '',
    this.initialFormat,
    this.onPickFileOverride,
  });

  final String? id;
  final String initialName;
  final String? initialFormat;
  final FilePickerCallback? onPickFileOverride;

  @override
  ConsumerState<IptvSourceForm> createState() => _IptvSourceFormState();
}

class _IptvSourceFormState extends ConsumerState<IptvSourceForm> {
  late final name = TextEditingController(text: widget.initialName);
  final url = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController(),
      epgUrl = TextEditingController(),
      pin = TextEditingController(),
      confirmPin = TextEditingController();

  final form = GlobalKey<FormState>();
  late String format = widget.initialFormat ?? 'm3u';
  late String? originalFormat = widget.initialFormat;
  bool isProtected = false;
  bool hasExistingPin = false;
  bool changePin = false;

  String? selectedFileName;
  String? selectedFileContent;
  int? selectedFileSize;
  String? fileError;

  bool busy = false;

  bool initialized = false;
  bool hasEpg = false, removeEpg = false;
  int? expectedRevision;
  String? requestId, lastPayload;

  void initializeEntry(Entry entry) {
    if (initialized) return;
    initialized = true;
    name.text = entry.name;
    originalFormat = entry.text('format');
    format = originalFormat!.isEmpty ? 'm3u' : originalFormat!;
    selectedFileName = format == 'file' ? entry.text('fileName') : null;
    isProtected = entry.data['isProtected'] == true;
    hasExistingPin = isProtected;
    hasEpg = entry.data['hasEpg'] == true || entry.text('epgUrl').isNotEmpty;
    expectedRevision = entry.number('revision') > 0
        ? entry.number('revision')
        : null;
    // Credentials and token-bearing URLs are never reconstructed from a hostname.
    // Blank replacement fields retain the encrypted server values.
  }

  bool get canKeepConnection =>
      widget.id != null &&
      (format == originalFormat ||
          (['m3u', 'url', 'other_m3u8'].contains(format) &&
              ['m3u', 'url', 'other_m3u8'].contains(originalFormat)));

  @override
  void dispose() {
    for (final c in [name, url, username, password, epgUrl, pin, confirmPin]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleFormatSelection(String newFormat) async {
    if (format == newFormat) return;

    if (widget.id != null &&
        originalFormat != null &&
        originalFormat != newFormat) {
      final confirmed = await confirmRemoval(
        context,
        title: context.l.confirmChangeFormatTitle,
        body: context.l.confirmChangeFormatBody,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() {
      format = newFormat;
      fileError = null;
    });
  }

  Future<void> pickFile() async {
    if (busy) return;
    setState(() => fileError = null);

    if (widget.onPickFileOverride != null) {
      final res = await widget.onPickFileOverride!();
      if (res != null && mounted) {
        const maxSizeBytes = 20 * 1024 * 1024;
        if (res.size > maxSizeBytes ||
            utf8.encode(res.content).length > maxSizeBytes) {
          setState(() => fileError = context.l.fileTooLarge);
          return;
        }
        if (!res.content.trimLeft().startsWith('#EXTM3U') ||
            !RegExp(
              r'\.(m3u|m3u8)$',
              caseSensitive: false,
            ).hasMatch(res.name)) {
          setState(() => fileError = context.l.invalidFileFormat);
          return;
        }
        setState(() {
          selectedFileName = res.name;
          selectedFileContent = res.content;
          selectedFileSize = res.size;
          fileError = null;
        });
      }
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
      );
      if (result.isEmpty) return;
      final file = result.first;

      const maxSizeBytes = 20 * 1024 * 1024;
      final size = file.lengthSync() ?? (await file.length()) ?? 0;
      if (size > maxSizeBytes) {
        if (mounted) setState(() => fileError = context.l.fileTooLarge);
        return;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (mounted) setState(() => fileError = context.l.invalidFileFormat);
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      if (!content.trimLeft().startsWith('#EXTM3U')) {
        if (mounted) setState(() => fileError = context.l.invalidFileFormat);
        return;
      }

      if (mounted) {
        setState(() {
          selectedFileName = file.name;
          selectedFileContent = content;
          selectedFileSize = size;
          fileError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => fileError = context.l.invalidFileFormat);
    }
  }

  Future<void> save() async {
    if (busy) return;
    if (!form.currentState!.validate()) return;

    if (format == 'file' && !canKeepConnection && selectedFileContent == null) {
      setState(() => fileError = context.l.requiredField);
      return;
    }

    if (isProtected && (!hasExistingPin || changePin)) {
      if (pin.text.trim() != confirmPin.text.trim()) {
        showAppFeedbackSheet(context: context, message: context.l.pinMustMatch);
        return;
      }
    }

    setState(() => busy = true);
    try {
      final payload = <String, dynamic>{
        'name': name.text.trim(),
        'format': format,
        if (widget.id != null) 'id': widget.id,
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
        if (format == 'file') ...{
          if (selectedFileName != null) 'fileName': selectedFileName,
          if (selectedFileContent != null) 'fileContent': selectedFileContent,
        } else ...{
          if (url.text.trim().isNotEmpty) 'url': url.text.trim(),
        },
        if (format == 'xtream') ...{
          if (username.text.trim().isNotEmpty) 'username': username.text.trim(),
          if (password.text.isNotEmpty) 'password': password.text,
        },
        if (removeEpg)
          'epgUrl': null
        else if (epgUrl.text.trim().isNotEmpty)
          'epgUrl': epgUrl.text.trim(),
        'isProtected': isProtected,
        if (isProtected && pin.text.trim().isNotEmpty) ...{
          'pin': pin.text.trim(),
          'confirmPin': confirmPin.text.trim(),
        },
      };
      final encoded = jsonEncode(payload);
      if (lastPayload != encoded) {
        lastPayload = encoded;
        requestId = List.generate(
          24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
      }
      await ref.read(repositoryProvider).mutate('saveSource', {
        ...payload,
        'requestId': requestId,
      });
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final isEditing = widget.id != null;
    if (isEditing && !initialized) {
      final key = (collection: 'sources', id: widget.id!);
      final state = ref.watch(entryProvider(key));
      final entry = state.asData?.value;
      if (entry != null) {
        initializeEntry(entry);
      } else {
        final hasInitialData =
            widget.initialName.isNotEmpty || widget.initialFormat != null;
        if (!hasInitialData) {
          final account = ref.watch(accountProvider);
          if (account.isLoading || state.isLoading) {
            return const Scaffold(body: AppLoadingSkeleton());
          }
          if (account.hasError) {
            return Scaffold(
              body: ErrorState(onRetry: () => ref.invalidate(accountProvider)),
            );
          }
          if (state.hasError) {
            return Scaffold(
              body: ErrorState(
                onRetry: () => ref.invalidate(entryProvider(key)),
              ),
            );
          }
          return Scaffold(body: Center(child: Text(l.notFound)));
        }
      }
    }
    final isUrlFormat = format == 'm3u' || format == 'url';
    final isFileFormat = format == 'file';
    final isXtreamFormat = format == 'xtream';
    final isOtherM3u8Format = format == 'other_m3u8';

    return Scaffold(
      body: PageTemplate(
        title: isEditing ? l.editSource : l.addSource,
        subtitle: l.credentialsHint,
        showBack: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NeumorphicFormatSelector(
                selectedFormat: format,
                onFormatSelected: _handleFormatSelection,
                disabled: busy,
              ),
              const SizedBox(height: AppTokens.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      label: l.name,
                      controller: name,
                      validator: (v) =>
                          v == null || v.trim().isEmpty || v.trim().length > 80
                          ? l.requiredField
                          : null,
                    ),

                    if (isEditing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(l.iptvKeepConnection),
                      ),
                    // Formato 1: URL (M3U / M3U8)
                    if (isUrlFormat) ...[
                      AppTextField(
                        label: l.playlistUrl,
                        controller: url,
                        keyboardType: TextInputType.url,
                        validator: (v) {
                          final raw = v?.trim() ?? '';
                          if (raw.isEmpty && canKeepConnection) return null;
                          if (raw.isEmpty || raw.length > 2048) {
                            return l.requiredField;
                          }
                          final u = Uri.tryParse(raw);
                          return u == null ||
                                  !['http', 'https']
                                      .contains(u.scheme.toLowerCase()) ||
                                  u.host.isEmpty ||
                                  u.userInfo.isNotEmpty
                              ? l.requiredField
                              : null;
                        },
                      ),
                    ],

                    // Formato 2: Arquivo (Importação M3U / M3U8)
                    if (isFileFormat) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: GraphiteSurface(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const AppIcon(
                                      AppIcons.file,
                                      size: AppDimensions.icon,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      l.sourceFile,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                if (selectedFileName != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.sm,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceRecessed,
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.sm,
                                      ),
                                      border: Border.all(
                                        color: AppColors.borderLight,
                                        width: AppDimensions.borderWidth,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const AppIcon(
                                          AppIcons.play,
                                          size: AppDimensions.iconSmall,
                                          color: AppColors.brandBlue,
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Expanded(
                                          child: Text(
                                            selectedFileSize != null
                                                ? '${selectedFileName!} (${_formatFileSize(selectedFileSize!)})'
                                                : selectedFileName!,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                ] else ...[
                                  Text(
                                    isEditing
                                        ? l.fileKeepHint
                                        : l.noFileSelected,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                ],
                                AppButton(
                                  label: selectedFileName != null
                                      ? l.changeFile
                                      : l.selectFile,
                                  icon: AppIcons.file,
                                  busy: busy,
                                  onPressed: pickFile,
                                ),
                                if (fileError != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    fileError!,
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Formato 3: Xtream Codes
                    if (isXtreamFormat) ...[
                      AppTextField(
                        label: l.serverUrl,
                        controller: url,
                        keyboardType: TextInputType.url,
                        validator: (v) {
                          final raw = v?.trim() ?? '';
                          if (raw.isEmpty && canKeepConnection) return null;
                          if (raw.isEmpty || raw.length > 2048) {
                            return l.requiredField;
                          }
                          final u = Uri.tryParse(raw);
                          return u == null ||
                                  !['http', 'https']
                                      .contains(u.scheme.toLowerCase()) ||
                                  u.host.isEmpty ||
                                  u.userInfo.isNotEmpty
                              ? l.requiredField
                              : null;
                        },
                      ),
                      AppTextField(
                        label: l.username,
                        controller: username,
                        validator: (v) =>
                            ((v == null || v.trim().isEmpty) &&
                                    !canKeepConnection) ||
                                (v?.trim().length ?? 0) > 256
                            ? l.requiredField
                            : null,
                      ),
                      AppTextField(
                        label: isEditing
                            ? '${l.password} (${l.passwordKeepHint})'
                            : l.password,
                        controller: password,
                        secret: true,
                        validator: (v) {
                          if (!canKeepConnection && (v == null || v.isEmpty)) {
                            return l.requiredField;
                          }
                          if (v != null && v.length > 512) {
                            return l.requiredField;
                          }
                          return null;
                        },
                      ),
                    ],

                    // Formato 4: Other M3U8 (M3U8 alternativo)
                    if (isOtherM3u8Format) ...[
                      AppTextField(
                        label: l.otherM3u8Url,
                        controller: url,
                        keyboardType: TextInputType.url,
                        validator: (v) {
                          final raw = v?.trim() ?? '';
                          if (raw.isEmpty && canKeepConnection) return null;
                          if (raw.isEmpty || raw.length > 2048) {
                            return l.requiredField;
                          }
                          final u = Uri.tryParse(raw);
                          return u == null ||
                                  !['http', 'https']
                                      .contains(u.scheme.toLowerCase()) ||
                                  u.host.isEmpty ||
                                  u.userInfo.isNotEmpty
                              ? l.requiredField
                              : null;
                        },
                      ),
                    ],

                    // URL do EPG (opcional para todos os 4 formatos)
                    AppTextField(
                      label: l.epgUrl,
                      controller: epgUrl,
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        final raw = v?.trim() ?? '';
                        if (raw.isEmpty) return null;
                        if (raw.length > 2048) return l.requiredField;
                        final u = Uri.tryParse(raw);
                        return u == null ||
                                !['http', 'https']
                                    .contains(u.scheme.toLowerCase()) ||
                                u.host.isEmpty ||
                                u.userInfo.isNotEmpty
                            ? l.requiredField
                            : null;
                      },
                    ),

                    if (hasEpg)
                      NeumorphicSwitchTile(
                        title: l.iptvRemoveEpg,
                        value: removeEpg,
                        disabled: busy,
                        onChanged: (value) => setState(() => removeEpg = value),
                      ),
                    // Proteção por PIN (opcional para todos os 4 formatos)
                    NeumorphicSwitchTile(
                      title: l.protectPlaylist,
                      subtitle: l.protectPlaylistHint,
                      value: isProtected,
                      disabled: busy,
                      onChanged: (val) {
                        setState(() {
                          isProtected = val;
                          if (!val) {
                            pin.clear();
                            confirmPin.clear();
                            changePin = false;
                          }
                        });
                      },
                    ),

                    if (isProtected) ...[
                      if (isEditing && hasExistingPin && !changePin) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: GraphiteSurface(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Row(
                                children: [
                                  const AppIcon(
                                    AppIcons.lock,
                                    size: AppDimensions.iconSmall,
                                    color: AppColors.brandBlue,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      l.keepExistingPin,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () =>
                                              setState(() => changePin = true),
                                    child: Text(l.changePin),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        AppTextField(
                          label: l.pin,
                          controller: pin,
                          secret: true,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return l.pinRequired;
                            if (val.length < 4 || val.length > 6) {
                              return l.pinLengthError;
                            }
                            if (!RegExp(r'^\d+$').hasMatch(val)) {
                              return l.requiredField;
                            }
                            return null;
                          },
                        ),
                        AppTextField(
                          label: l.confirmPin,
                          controller: confirmPin,
                          secret: true,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final val = v?.trim() ?? '';
                            if (val.isEmpty) return l.pinRequired;
                            if (val != pin.text.trim()) {
                              return l.pinMustMatch;
                            }
                            return null;
                          },
                        ),
                      ],
                    ],

                    const SizedBox(height: AppTokens.lg),
                    AppButton(label: l.save, busy: busy, onPressed: save),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
