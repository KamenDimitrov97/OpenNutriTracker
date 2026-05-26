import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/data/data_source/anthropic_data_source.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';

/// Draggable floating button shown on top of every screen (wired in through
/// `MaterialApp.builder` in main.dart). Tap it to send a one-shot test message to
/// the Anthropic API and show Claude's reply. Everything it shows is drawn inline
/// because it lives ABOVE the app's Navigator (so `showDialog` isn't available).
class ClaudeTestBubble extends StatefulWidget {
  const ClaudeTestBubble({super.key});

  @override
  State<ClaudeTestBubble> createState() => _ClaudeTestBubbleState();
}

class _ClaudeTestBubbleState extends State<ClaudeTestBubble> {
  static const double _bubbleSize = 56;

  final SecureAppStorageProvider _storage = SecureAppStorageProvider();
  late final AnthropicDataSource _anthropic =
      AnthropicDataSource(_storage, http.Client());
  final TextEditingController _keyController = TextEditingController();

  Offset _offset = const Offset(16, 140);
  bool _loading = false;
  bool _askingForKey = false;
  String? _resultTitle;
  String? _resultMessage;
  bool _resultSuccess = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_loading) return;
    final hasKey = await _storage.hasAnthropicApiKey();
    if (!mounted) return;
    if (!hasKey) {
      setState(() => _askingForKey = true);
      return;
    }
    await _runTest();
  }

  Future<void> _saveKeyAndTest() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    await _storage.setAnthropicApiKey(key);
    _keyController.clear();
    if (!mounted) return;
    setState(() => _askingForKey = false);
    await _runTest();
  }

  Future<void> _runTest() async {
    setState(() => _loading = true);
    try {
      final reply = await _anthropic.testConnection();
      _showResult('Claude says 👋', reply, success: true);
    } on AnthropicException catch (e) {
      _showResult('Test failed', e.message, success: false);
    } catch (e) {
      _showResult('Test failed', e.toString(), success: false);
    }
  }

  void _showResult(String title, String message, {required bool success}) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _resultTitle = title;
      _resultMessage = message;
      _resultSuccess = success;
    });
  }

  void _dismissPanels() {
    setState(() {
      _askingForKey = false;
      _resultTitle = null;
      _resultMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final size = media.size;
    final panelOpen = _askingForKey || _resultMessage != null;

    return Stack(
      children: [
        // Dim scrim behind any open panel; tap outside to dismiss.
        if (panelOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissPanels,
              child: Container(color: Colors.black54),
            ),
          ),

        if (_askingForKey) _buildKeyPanel(theme, media),
        if (_resultMessage != null) _buildResultPanel(theme),

        // The draggable bubble itself.
        Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: Semantics(
            identifier: 'claude-test-bubble',
            button: true,
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  final dx = (_offset.dx + d.delta.dx)
                      .clamp(0.0, size.width - _bubbleSize);
                  final dy = (_offset.dy + d.delta.dy).clamp(
                    media.padding.top,
                    size.height - _bubbleSize - media.padding.bottom,
                  );
                  _offset = Offset(dx, dy);
                });
              },
              onTap: _onTap,
              // Long-press to (re-)enter the key, e.g. after a 401.
              onLongPress: () => setState(() => _askingForKey = true),
              child: Material(
                elevation: 6,
                shape: const CircleBorder(),
                color: theme.colorScheme.primaryContainer,
                child: SizedBox(
                  width: _bubbleSize,
                  height: _bubbleSize,
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.auto_awesome,
                          color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyPanel(ThemeData theme, MediaQueryData media) {
    // Lift the card above the on-screen keyboard when it's open.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Center(
        child: _PanelCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Anthropic API key', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'claude-test-key-field',
                child: TextField(
                  controller: _keyController,
                  autofocus: true,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Paste your key',
                    hintText: 'sk-ant-...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _dismissPanels,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'claude-test-key-save',
                    child: FilledButton(
                      onPressed: _saveKeyAndTest,
                      child: const Text('Save & test'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultPanel(ThemeData theme) {
    return Center(
      child: _PanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _resultSuccess ? Icons.check_circle : Icons.error,
                  color:
                      _resultSuccess ? Colors.green : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_resultTitle ?? '',
                      style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(_resultMessage ?? ''),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                identifier: 'claude-test-result-ok',
                child: FilledButton(
                  onPressed: _dismissPanels,
                  child: const Text('OK'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded card used for the inline panels.
class _PanelCard extends StatelessWidget {
  final Widget child;
  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}