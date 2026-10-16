import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../app_build.dart';
import '../theme.dart';
import 'game_popup.dart';

String feedbackClientPlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => 'other',
  };
}

/// Opens the report / suggestion form. Returns true after a successful send.
Future<bool?> showFeedbackSheet({
  required BuildContext context,
  required Future<FeedbackSubmitResult> Function(FeedbackRequest request) onSubmit,
  String? gameArea,
  String buildId = appBuild,
  String? platform,
}) {
  return showGamePopup<bool>(
    context: context,
    origin: popupOrigin(context),
    maxHeight: gamePopupCeilingHeight(context),
    builder: (dialogContext) {
      return GamePopupCard(
        child: FeedbackForm(
          onSubmit: onSubmit,
          gameArea: gameArea,
          buildId: buildId,
          platform: platform ?? feedbackClientPlatform(),
          onClose: () => Navigator.of(dialogContext).pop(false),
          onSent: () => Navigator.of(dialogContext).pop(true),
        ),
      );
    },
  );
}

class FeedbackForm extends StatefulWidget {
  const FeedbackForm({
    super.key,
    required this.onSubmit,
    required this.onClose,
    required this.onSent,
    this.gameArea,
    this.buildId = appBuild,
    this.platform,
  });

  final Future<FeedbackSubmitResult> Function(FeedbackRequest request) onSubmit;
  final VoidCallback onClose;
  final VoidCallback onSent;
  final String? gameArea;
  final String buildId;
  final String? platform;

  @override
  State<FeedbackForm> createState() => FeedbackFormState();
}

class FeedbackFormState extends State<FeedbackForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _player = TextEditingController();

  String _kind = feedbackKindBug;
  String _reportReason = reportReasonSpam;
  bool _sending = false;
  String? _titleError;
  String? _bodyError;
  String? _playerError;
  String? _formError;
  int? _retryAfterSeconds;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    _title.dispose();
    _body.dispose();
    _player.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _countdown?.cancel();
    setState(() => _retryAfterSeconds = seconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_retryAfterSeconds ?? 1) - 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (left <= 0) {
        timer.cancel();
        setState(() => _retryAfterSeconds = null);
        return;
      }
      setState(() => _retryAfterSeconds = left);
    });
  }

  bool get _blocked => _sending || (_retryAfterSeconds ?? 0) > 0;

  FeedbackRequest _request() {
    return FeedbackRequest(
      kind: _kind,
      title: _title.text,
      body: _body.text,
      targetUsername: _kind == feedbackKindPlayer ? _player.text : null,
      reportReason: _kind == feedbackKindPlayer ? _reportReason : null,
      build: widget.buildId,
      platform: widget.platform ?? feedbackClientPlatform(),
      gameArea: widget.gameArea,
    );
  }

  Future<void> _send() async {
    if (_blocked) return;
    final titleError = feedbackTitleError(_title.text);
    final bodyError = feedbackBodyError(_body.text);
    final playerError = feedbackPlayerTargetError(_kind, _player.text);
    setState(() {
      _titleError = titleError;
      _bodyError = bodyError;
      _playerError = playerError;
      _formError = null;
    });
    if (titleError != null || bodyError != null || playerError != null) return;

    setState(() => _sending = true);
    final result = await widget.onSubmit(_request());
    if (!mounted) return;
    if (result.ok) {
      widget.onSent();
      return;
    }
    setState(() {
      _sending = false;
      _formError = result.reason;
    });
    if (result.retryAfterSeconds != null && result.retryAfterSeconds! > 0) {
      _startCountdown(result.retryAfterSeconds!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Report / Suggestion',
            style: TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in feedbackKinds)
                GameTextButton(
                  label: feedbackKindLabel(kind),
                  selected: _kind == kind,
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                          _kind = kind;
                          _playerError = null;
                        }),
                ),
            ],
          ),
          if (_kind == feedbackKindPlayer) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('feedback-player'),
              controller: _player,
              enabled: !_sending,
              maxLength: 24,
              decoration: InputDecoration(
                labelText: 'Player',
                isDense: true,
                counterText: '',
                errorText: _playerError,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final reason in reportReasons)
                  GameTextButton(
                    label: reason,
                    selected: _reportReason == reason,
                    onPressed: _sending ? null : () => setState(() => _reportReason = reason),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const Key('feedback-title'),
            controller: _title,
            enabled: !_sending,
            maxLength: feedbackTitleMaxLength,
            decoration: InputDecoration(
              labelText: 'Summary',
              isDense: true,
              counterText: '',
              errorText: _titleError,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('feedback-body'),
            controller: _body,
            enabled: !_sending,
            maxLength: feedbackBodyMaxLength,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Details',
              isDense: true,
              counterText: '',
              errorText: _bodyError,
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(
              _formError!,
              style: const TextStyle(color: Palette.warning, fontSize: GameFont.s),
            ),
          ],
          const SizedBox(height: 12),
          GameButton(
            label: feedbackSendLabel(_retryAfterSeconds),
            onPressed: _blocked ? null : _send,
            waiting: _sending,
          ),
        ],
      ),
    );
  }
}
