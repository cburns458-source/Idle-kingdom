import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'game_popup.dart';
import 'item_icon.dart';

/// Kingdom post: unread letters, then the rest, kept until they expire.
Future<void> showMailboxPopup({required BuildContext context, required GameController controller}) {
  return showGamePopup<void>(
    context: context,
    builder: (context) => _MailboxPopup(controller: controller),
  );
}

class _MailboxPopup extends StatefulWidget {
  const _MailboxPopup({required this.controller});

  final GameController controller;

  @override
  State<_MailboxPopup> createState() => _MailboxPopupState();
}

class _MailboxPopupState extends State<_MailboxPopup> {
  String? _openId;
  String? _notice;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final nowMs = controller.session.clock();
        final messages = visibleMailbox(controller.save, nowMs);
        MailMessage? open;
        if (_openId != null) {
          for (final message in messages) {
            if (message.id == _openId) {
              open = message;
              break;
            }
          }
        }
        return GamePopupCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                open == null ? 'Mailbox' : open.subject,
                style: const TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: open == null
                    ? _MailList(
                        messages: messages,
                        onOpen: (message) {
                          controller.readMailboxMessage(message.id);
                          setState(() {
                            _openId = message.id;
                            _notice = null;
                          });
                        },
                      )
                    : _MailDetail(
                        controller: controller,
                        message: open,
                        notice: _notice,
                        onClaim: () {
                          final id = open!.id;
                          setState(() => _notice = controller.claimMailboxMessage(id));
                        },
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (open != null) ...[
                    GameButton(
                      label: 'Back',
                      tone: GameButtonTone.secondary,
                      compact: true,
                      onPressed: () => setState(() {
                        _openId = null;
                        _notice = null;
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: GameButton(
                      label: 'Close',
                      compact: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MailList extends StatelessWidget {
  const _MailList({required this.messages, required this.onOpen});

  final List<MailMessage> messages;
  final ValueChanged<MailMessage> onOpen;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const MutedText('The box is empty.');
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final message in messages)
          InkWell(
            key: Key('mailbox-row-${message.id}'),
            onTap: () => onOpen(message),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 10,
                    child: message.readAt == null
                        ? const DecoratedBox(
                            decoration: BoxDecoration(color: Palette.gold, shape: BoxShape.circle),
                            child: SizedBox(width: 8, height: 8),
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: message.readAt == null ? Palette.gold : Palette.parchmentText,
                          ),
                        ),
                        MutedText(formatSaveDate(message.sentAt) ?? message.sentAt),
                      ],
                    ),
                  ),
                  if (message.attachments.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.inventory_2_outlined, size: 14, color: Palette.gold),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MailDetail extends StatelessWidget {
  const _MailDetail({
    required this.controller,
    required this.message,
    required this.onClaim,
    this.notice,
  });

  final GameController controller;
  final MailMessage message;
  final VoidCallback onClaim;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MutedText(formatSaveDate(message.sentAt) ?? message.sentAt),
          const SizedBox(height: 8),
          Text(message.body, style: const TextStyle(height: 1.4)),
          if (message.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Attached', style: TextStyle(fontWeight: FontWeight.w400)),
            const SizedBox(height: 6),
            for (final attachment in message.attachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    ItemIcon(item: controller.indexes.itemsById[attachment.itemId], size: 22),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${controller.indexes.itemsById[attachment.itemId]?.displayName ?? attachment.itemId}'
                        ' ×${formatThousands(attachment.quantity)}',
                      ),
                    ),
                  ],
                ),
              ),
            if (message.claimedAt == null)
              GameButton(label: 'Claim', compact: true, onPressed: onClaim)
            else
              const MutedText('Claimed.'),
          ],
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(notice!, style: const TextStyle(color: Palette.gold)),
          ],
        ],
      ),
    );
  }
}

/// HUD mailbox chip with an unread count.
class MailboxHudButton extends StatelessWidget {
  const MailboxHudButton({super.key, required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = unread > 0 ? 'Mailbox, $unread unread' : 'Mailbox';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: unread > 0 ? 'Mailbox ($unread unread)' : 'Mailbox',
        child: GestureDetector(
          key: const Key('mailbox-button'),
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GameImage(uiMailboxAssetPath(), width: 28, height: 28),
                if (unread > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Palette.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            fontSize: 8,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: Palette.parchmentText,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
