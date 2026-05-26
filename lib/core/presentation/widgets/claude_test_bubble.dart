import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/data/data_source/anthropic_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/log_parsed_meal_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';

/// Draggable floating button shown on top of every screen (wired in through
/// `MaterialApp.builder` in main.dart). Tap it to describe a meal in natural
/// language; Claude parses it, and you can log the items straight to the diary.
/// Drawn inline because the bubble lives ABOVE the app's Navigator.
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
  late final LogParsedMealUsecase _logger = LogParsedMealUsecase(
    locator<AddIntakeUsecase>(),
    locator<AddTrackedDayUsecase>(),
    locator<GetKcalGoalUsecase>(),
    locator<GetMacroGoalUsecase>(),
  );
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _mealController = TextEditingController();

  Offset _offset = const Offset(16, 140);
  bool _loading = false;
  bool _askingForKey = false;
  bool _obscureKey = true;
  bool _askingMeal = false;
  List<ParsedFoodItem>? _parsedItems;
  IntakeTypeEntity _selectedType = _defaultTypeForNow();
  String? _errorMessage;
  String? _successMessage;

  static IntakeTypeEntity _defaultTypeForNow() {
    final hour = DateTime.now().hour;
    if (hour < 11) return IntakeTypeEntity.breakfast;
    if (hour < 15) return IntakeTypeEntity.lunch;
    if (hour < 21) return IntakeTypeEntity.dinner;
    return IntakeTypeEntity.snack;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _mealController.dispose();
    super.dispose();
  }

  // --- actions ---

  Future<void> _onTap() async {
    if (_loading) return;
    final hasKey = await _storage.hasAnthropicApiKey();
    if (!mounted) return;
    setState(() {
      if (hasKey) {
        _askingMeal = true;
      } else {
        _askingForKey = true;
      }
    });
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    await _storage.setAnthropicApiKey(key);
    _keyController.clear();
    if (!mounted) return;
    setState(() {
      _askingForKey = false;
      _askingMeal = true;
    });
  }

  Future<void> _parseMeal() async {
    final text = _mealController.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final items = await _anthropic.parseMeal(text);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _askingMeal = false;
        _parsedItems = items;
      });
    } on AnthropicException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _logMeal() async {
    final items = _parsedItems;
    if (items == null || items.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _logger.logItems(items, _selectedType, DateTime.now());
      _refreshDiaryViews();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _parsedItems = null;
        _successMessage =
            'Logged ${items.length} item(s) to ${_typeLabel(_selectedType)}.';
      });
    } catch (e) {
      _showError('Couldn\'t log: $e');
    }
  }

  /// Best-effort: nudge the Home and Diary screens to reload from Hive so the
  /// new entries appear immediately. Guarded because these blocs may not be
  /// instantiated yet depending on where the user is.
  void _refreshDiaryViews() {
    try {
      locator<HomeBloc>().add(const LoadItemsEvent());
    } catch (_) {}
    try {
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
    } catch (_) {}
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _askingMeal = false;
      _errorMessage = message;
    });
  }

  void _dismissPanels() {
    setState(() {
      _askingForKey = false;
      _askingMeal = false;
      _parsedItems = null;
      _errorMessage = null;
      _successMessage = null;
      _mealController.clear();
    });
  }

  String _typeLabel(IntakeTypeEntity type) {
    switch (type) {
      case IntakeTypeEntity.breakfast:
        return 'Breakfast';
      case IntakeTypeEntity.lunch:
        return 'Lunch';
      case IntakeTypeEntity.dinner:
        return 'Dinner';
      case IntakeTypeEntity.snack:
        return 'Snack';
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final size = media.size;
    final panelOpen = _askingForKey ||
        _askingMeal ||
        _parsedItems != null ||
        _errorMessage != null ||
        _successMessage != null;

    return Stack(
      children: [
        if (panelOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissPanels,
              child: Container(color: Colors.black54),
            ),
          ),
        if (_askingForKey) _buildKeyPanel(theme, media),
        if (_askingMeal) _buildMealPanel(theme, media),
        if (_parsedItems != null) _buildParsedPanel(theme),
        if (_errorMessage != null) _buildErrorPanel(theme),
        if (_successMessage != null) _buildSuccessPanel(theme),

        Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: Semantics(
            identifier: 'ai-log-bubble',
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
                identifier: 'ai-log-key-field',
                child: TextField(
                  controller: _keyController,
                  autofocus: true,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'Paste your key',
                    hintText: 'sk-ant-...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _dismissPanels, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'ai-log-key-save',
                    child: FilledButton(
                      onPressed: _saveKey,
                      child: const Text('Save & continue'),
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

  Widget _buildMealPanel(ThemeData theme, MediaQueryData media) {
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Center(
        child: _PanelCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Describe your meal', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('e.g. "300g chicken breast, 200g rice, 15g olive oil"',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Semantics(
                identifier: 'ai-log-input',
                child: TextField(
                  controller: _mealController,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'What did you eat?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _dismissPanels, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  Semantics(
                    identifier: 'ai-log-submit',
                    child: FilledButton(
                      onPressed: _loading ? null : _parseMeal,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Parse meal'),
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

  Widget _buildParsedPanel(ThemeData theme) {
    final items = _parsedItems ?? [];
    final totalKcal = items.fold<double>(0, (sum, i) => sum + i.kcal);
    return Center(
      child: _PanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Parsed ${items.length} item(s)',
                      style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final item in items) _buildItemRow(theme, item),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Text('Total: ${totalKcal.round()} kcal',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.right),
            const SizedBox(height: 12),
            Text('Log as', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final type in IntakeTypeEntity.values)
                  ChoiceChip(
                    label: Text(_typeLabel(type)),
                    selected: _selectedType == type,
                    onSelected: (_) => setState(() => _selectedType = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: _dismissPanels, child: const Text('Close')),
                const SizedBox(width: 8),
                Semantics(
                  identifier: 'ai-log-confirm',
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _logMeal,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Log to diary'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(ThemeData theme, ParsedFoodItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('${item.name} • ${item.grams.round()}g',
                    style: theme.textTheme.bodyLarge),
              ),
              Text('${item.kcal.round()} kcal',
                  style: theme.textTheme.bodyLarge),
            ],
          ),
          Text(
            'C ${item.carbsG.round()}g · F ${item.fatG.round()}g · '
            'P ${item.proteinG.round()}g',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessPanel(ThemeData theme) {
    return Center(
      child: _PanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text('Logged!', style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_successMessage ?? ''),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: _dismissPanels, child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPanel(ThemeData theme) {
    return Center(
      child: _PanelCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Something went wrong',
                      style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(_errorMessage ?? ''),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: _dismissPanels, child: const Text('OK')),
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