import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_vibrance/models/history_entry.dart';
import 'package:open_vibrance/services/history_repository.dart';
import 'package:open_vibrance/services/transcription_service.dart';
import 'package:open_vibrance/theme/app_colors.dart';
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
    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.zinc400,
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
            style: TextStyle(color: AppColors.zinc500, fontSize: 14),
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
          child: _buildEntryTile(entry, retryState),
        );
      },
    );
  }

  Widget _buildRetryIcon(HistoryEntry entry, _RetryState? retryState) {
    final Widget child;

    switch (retryState) {
      case _RetryState.retrying:
        child = SizedBox(
          key: const ValueKey('spinner'),
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.zinc400,
          ),
        );
      case _RetryState.success:
        child = Icon(
          key: const ValueKey('check'),
          Icons.check,
          color: AppColors.blue400,
          size: 20,
        );
      case null:
        child = HoverableIcon(
          key: const ValueKey('retry'),
          iconData: Icons.refresh,
          onTap: () => _retryTranscription(entry),
          color: AppColors.zinc500,
          hoverColor: AppColors.zinc300,
        );
    }

    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
    );
  }

  Widget _buildEntryTile(HistoryEntry entry, _RetryState? retryState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.zinc800,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: entry.success ? AppColors.zinc700 : AppColors.red900,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            entry.success ? Icons.check_circle_outline : Icons.error_outline,
            color: entry.success ? AppColors.blue400 : AppColors.red400,
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
                    color: entry.success ? AppColors.zinc300 : AppColors.red300,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: TextStyle(color: AppColors.zinc500, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildRetryIcon(entry, retryState),
        ],
      ),
    );
  }
}
