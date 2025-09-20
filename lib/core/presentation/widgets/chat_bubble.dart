import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/nav_key.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/services/ai_chat_service.dart';
import 'package:opennutritracker/core/utils/env.dart';

class ChatBubbleLauncher extends StatefulWidget {
  final EdgeInsets? padding;
  const ChatBubbleLauncher({super.key, this.padding});

  @override
  State<ChatBubbleLauncher> createState() => _ChatBubbleLauncherState();
}

class _ChatBubbleLauncherState extends State<ChatBubbleLauncher> {
  bool _isOpen = false;
  // Persist messages in-memory across openings
  static final List<_ChatMsg> _messages = <_ChatMsg>[];
  final _log = Logger('ChatBubble');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = widget.padding ?? const EdgeInsets.all(16.0);
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: pad,
            child: FloatingActionButton(
              onPressed: _toggleSheet,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(_isOpen ? Icons.close : Icons.chat_bubble_outline),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSheet() async {
    final navigatorContext = rootNavigatorKey.currentContext ?? context;
    if (_isOpen) {
      // Close currently open sheet.
      final popped = await Navigator.of(navigatorContext).maybePop();
      if (popped && mounted) {
        _log.info('Chat sheet closed');
        setState(() => _isOpen = false);
      }
      return;
    }

    _log.info('Chat sheet opened (messages: \\${_messages.length})');
    setState(() => _isOpen = true);
    await showModalBottomSheet(
      context: navigatorContext,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(navigatorContext).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ChatSheet(messages: _messages),
    );

    if (mounted) {
      _log.info('Chat sheet dismissed');
      setState(() => _isOpen = false);
    }
  }
}

class _ChatSheet extends StatefulWidget {
  final List<_ChatMsg> messages;
  const _ChatSheet({required this.messages});

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _log = Logger('ChatBubble.ChatSheet');
  final FocusNode _focusNode = FocusNode();
  final _ai = AiChatService();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Ensure the text field becomes the active input on open (Flutter web quirk)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    // Log OPENAI_MODEL resolution when opening the chat (before sending anything)
    final ddModel = const String.fromEnvironment('OPENAI_MODEL');
    final envModel = Env.openAiModel;
    final preNormalized = ddModel.isNotEmpty
        ? ddModel
        : (envModel.isNotEmpty ? envModel : 'gpt-4o-mini');
    String normalize(String m) {
      final s = m.trim().toLowerCase();
      switch (s) {
        case 'gpt5-mini':
        case 'gpt-5-mini':
        case 'gpt-5m':
        case 'gpt5m':
          return 'gpt-4o-mini';
        default:
          return m;
      }
    }
    final normalized = normalize(preNormalized);
    _log.info('OPENAI_MODEL (dart-define): ' + (ddModel.isEmpty ? '(empty)' : ddModel));
    _log.info('OPENAI_MODEL (.env via Env): ' + (envModel.isEmpty ? '(empty)' : envModel));
    _log.info('OPENAI_MODEL (effective pre-normalize): ' + preNormalized);
    _log.info('OPENAI_MODEL (normalized): ' + normalized);
    _log.info('OPENAI_MODEL (AiChatService.model now): ' + _ai.model);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Assistant', style: textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: widget.messages.length,
              itemBuilder: (context, i) {
                final m = widget.messages[i];
                final isUser = m.isUser;
                final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
                final color = isUser
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest;
                return Column(
                  crossAxisAlignment: align,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Text(m.text),
                    )
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
              top: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      widget.messages.add(_ChatMsg(text: text, isUser: true, ts: DateTime.now()));
      _controller.clear();
    });
    _log.info('User message: "' + text + '" (total: ' + widget.messages.length.toString() + ')');
    _callAi();
    // Scroll to bottom on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _callAi() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      _log.info('Configured model: ' + _ai.model);
      // Create history view for service
      final history = widget.messages
          .map((e) => AiMsg(e.text, e.isUser))
          .toList(growable: false);
      // Add a placeholder assistant message for immediate feedback
      final placeholder = _ChatMsg(text: '…', isUser: false, ts: DateTime.now());
      setState(() => widget.messages.add(placeholder));

      final reply = await _ai.send(history);
      setState(() {
        final idx = widget.messages.indexOf(placeholder);
        if (idx >= 0) {
          widget.messages[idx] = _ChatMsg(
            text: reply ?? 'No response',
            isUser: false,
            ts: DateTime.now(),
          );
        }
      });
      _log.info('Assistant reply added');
    } catch (e, st) {
      _log.severe('AI call failed: $e', e, st);
      setState(() => widget.messages.add(_ChatMsg(
            text: 'Error contacting assistant',
            isUser: false,
            ts: DateTime.now(),
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      // Ensure list scrolled to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }
}

class _ChatMsg {
  final String text;
  final bool isUser;
  final DateTime ts;
  _ChatMsg({required this.text, required this.isUser, required this.ts});
}
