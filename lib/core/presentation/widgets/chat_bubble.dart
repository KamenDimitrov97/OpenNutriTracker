import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/nav_key.dart';

class ChatBubbleLauncher extends StatefulWidget {
  final EdgeInsets? padding;
  const ChatBubbleLauncher({super.key, this.padding});

  @override
  State<ChatBubbleLauncher> createState() => _ChatBubbleLauncherState();
}

class _ChatBubbleLauncherState extends State<ChatBubbleLauncher> {
  bool _isOpen = false;

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
      if (popped && mounted) setState(() => _isOpen = false);
      return;
    }

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
      builder: (ctx) {
        final textTheme = Theme.of(ctx).textTheme;
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Assistant',
                        style: textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(
                child: Center(
                  child: Text('Chat coming soon'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (mounted) setState(() => _isOpen = false);
  }
}
