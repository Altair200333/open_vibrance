import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_vibrance/models/history_entry.dart';
import 'package:open_vibrance/services/history_repository.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/utils/common.dart';
import 'package:open_vibrance/widgets/hoverable_icon.dart';

enum _RetryState { retrying, success }

class HistoryView extends StatefulWidget {
  final HistoryRepository historyRepository;
  final TranscriptionService transcriptionService;
  final VoidCallback? onCopied;

  const HistoryView({
    super.key,
    required this.historyRepository,
    required this.transcriptionService,
    this.onCopied,
  });

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;
  final Map<String, _RetryState> _retryStates = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final entries = await widget.historyRepository.loadEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  void _showCopiedToast() {
    widget.onCopied?.call();
  }

  Future<void> _retryTranscription(HistoryEntry entry) async {
    if (!await File(entry.audioFilePath).exists()) {
      dprint('Audio file not found: ${entry.audioFilePath}');
      return;
    }

    setState(() => _retryStates[entry.id] = _RetryState.retrying);

    try {
      final transcription = await widget.transcriptionService
          .transcribeFileAndPaste(entry.audioFilePath, paste: false);

      final newEntry = HistoryEntry(
        id: '${widget.historyRepository.idFromPath(entry.audioFilePath)}_retry_${DateTime.now().millisecondsSinceEpoch}',
        audioFilePath: entry.audioFilePath,
        transcription: transcription,
        timestamp: DateTime.now(),
        success: true,
      );
      await widget.historyRepository.addEntry(newEntry);
      widget.historyRepository.cleanup();

      if (mounted) {
        setState(() => _retryStates[entry.id] = _RetryState.success);
        _showCopiedToast();
      }

      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() => _retryStates.remove(entry.id));
        await _loadHistory();
      }
    } catch (e) {
      dprint('Retry failed: $e');
      if (mounted) setState(() => _retryStates.remove(entry.id));
    }
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textSecondary,
            ),
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No transcription history yet',
            style: TextStyle(color: colors.textHint, fontSize: kFontSizeLg),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final retryState = _retryStates[entry.id];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildEntryTile(entry, retryState, colors),
        );
      },
    );
  }

  Widget _buildRetryIcon(HistoryEntry entry, _RetryState? retryState, AppColorTheme colors) {
    final Widget child;

    switch (retryState) {
      case _RetryState.retrying:
        child = SizedBox(
          key: const ValueKey('spinner'),
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.textSecondary,
          ),
        );
      case _RetryState.success:
        child = Icon(
          key: const ValueKey('check'),
          Icons.check,
          color: colors.accent,
          size: 20,
        );
      case null:
        child = HoverableIcon(
          key: const ValueKey('retry'),
          iconData: Icons.refresh,
          onTap: () => _retryTranscription(entry),
          color: colors.iconDefault,
          hoverColor: colors.iconHover,
        );
    }

    return SizedBox(
      width: 24,
      height: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
    );
  }

  Widget _buildEntryTile(HistoryEntry entry, _RetryState? retryState, AppColorTheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(
          color: entry.success ? colors.border : colors.errorBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            entry.success ? Icons.check_circle_outline : Icons.error_outline,
            color: entry.success ? colors.accent : colors.error,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.transcription ?? 'Transcription failed',
                  style: TextStyle(
                    color: entry.success ? colors.textPrimary : colors.errorText,
                    fontSize: kFontSizeMd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: TextStyle(color: colors.textHint, fontSize: kFontSizeXs),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildRetryIcon(entry, retryState, colors),
        ],
      ),
    );
  }
}
