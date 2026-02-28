import 'dart:async';
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

typedef ToastCallback = void Function(
  String message, {
  IconData icon,
  Duration duration,
  String? actionLabel,
  VoidCallback? onAction,
});

class HistoryView extends StatefulWidget {
  final HistoryRepository historyRepository;
  final TranscriptionService transcriptionService;
  final ToastCallback? onToast;
  final VoidCallback? onDismissToast;

  const HistoryView({
    super.key,
    required this.historyRepository,
    required this.transcriptionService,
    this.onToast,
    this.onDismissToast,
  });

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _PendingDelete {
  final HistoryEntry entry;
  final int index;

  const _PendingDelete({required this.entry, required this.index});
}

class _HistoryViewState extends State<HistoryView> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;
  final Map<String, _RetryState> _retryStates = {};
  final _listKey = GlobalKey<AnimatedListState>();

  _PendingDelete? _pendingDelete;
  Timer? _finalizeTimer;

  static const _kUndoDuration = Duration(seconds: 5);
  static const _kAnimDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    if (_pendingDelete != null) {
      widget.onDismissToast?.call();
      _finalizePendingDelete();
    }
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final entries = await widget.historyRepository.loadEntries();
    if (mounted) {
      setState(() {
        _entries = List.of(entries);
        _loading = false;
      });
    }
  }

  void _showCopiedToast() {
    widget.onToast?.call('Copied to clipboard');
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
        // Insert new entry at top with animation instead of full reload
        _entries.insert(0, newEntry);
        _listKey.currentState?.insertItem(0, duration: _kAnimDuration);
      }
    } catch (e) {
      dprint('Retry failed: $e');
      if (mounted) setState(() => _retryStates.remove(entry.id));
    }
  }

  Future<void> _softDelete(HistoryEntry entry) async {
    // Finalize any previous pending delete first
    _finalizeTimer?.cancel();
    await _finalizePendingDelete();

    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index == -1) return;

    // Remove from local list and animate out
    _entries.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAnimatedTile(entry, null, context.colors, animation),
      duration: _kAnimDuration,
    );

    // Set pending BEFORE await so rapid deletes don't lose track
    _pendingDelete = _PendingDelete(entry: entry, index: index);
    _finalizeTimer = Timer(_kUndoDuration, () => _finalizePendingDelete());

    // Show undo toast
    widget.onToast?.call(
      'Entry deleted',
      icon: Icons.delete_outline,
      duration: _kUndoDuration,
      actionLabel: 'Undo',
      onAction: _undoDelete,
    );

    if (mounted) setState(() {});

    // Persist removal in background
    await widget.historyRepository.softDeleteEntry(entry.id);
  }

  Future<void> _undoDelete() async {
    _finalizeTimer?.cancel();
    final pending = _pendingDelete;
    if (pending == null) return;
    _pendingDelete = null;

    // Re-insert into repository
    await widget.historyRepository.insertEntryAt(pending.entry, pending.index);

    // Re-insert into local list and animate in
    final insertIndex = pending.index.clamp(0, _entries.length);
    _entries.insert(insertIndex, pending.entry);
    _listKey.currentState?.insertItem(insertIndex, duration: _kAnimDuration);

    if (mounted) setState(() {});
  }

  Future<void> _finalizePendingDelete() async {
    final pending = _pendingDelete;
    if (pending == null) return;
    _pendingDelete = null;

    await widget.historyRepository.deleteAudioIfUnreferenced(pending.entry.audioFilePath);

    // Trigger rebuild so empty state shows if list is now empty
    if (mounted) setState(() {});
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
          child: _AnimatedDots(color: colors.textHint, fontSize: kFontSizeMd),
        ),
      );
    }

    if (_entries.isEmpty && _pendingDelete == null) {
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

    return AnimatedList(
      key: _listKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: _entries.length,
      itemBuilder: (context, index, animation) {
        final entry = _entries[index];
        final retryState = _retryStates[entry.id];
        return _buildAnimatedTile(entry, retryState, colors, animation);
      },
    );
  }

  Widget _buildAnimatedTile(
    HistoryEntry entry,
    _RetryState? retryState,
    AppColorTheme colors,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: animation.drive(CurveTween(curve: kHoverCurve)),
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildEntryTile(entry, retryState, colors),
        ),
      ),
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

  Widget _buildDeleteIcon(HistoryEntry entry, AppColorTheme colors) {
    return SizedBox(
      width: 24,
      height: 24,
      child: HoverableIcon(
        iconData: Icons.close,
        onTap: () => _softDelete(entry),
        color: colors.iconDefault,
        hoverColor: colors.error,
        size: 18,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              entry.success ? Icons.check_circle_outline : Icons.error_outline,
              color: entry.success ? colors.accent : colors.error,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: entry.transcription ?? 'Transcription failed',
                  child: Text(
                    entry.transcription ?? 'Transcription failed',
                    style: TextStyle(
                      color: entry.success ? colors.textPrimary : colors.errorText,
                      fontSize: kFontSizeMd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
          _buildDeleteIcon(entry, colors),
        ],
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  final Color color;
  final double fontSize;

  const _AnimatedDots({required this.color, required this.fontSize});

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        const dots = ['...', '.', '..'];
        final index = (_controller.value * 3).floor() % 3;
        return Text(
          'Loading history${dots[index]}',
          style: TextStyle(color: widget.color, fontSize: widget.fontSize),
        );
      },
    );
  }
}
