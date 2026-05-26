import 'package:opennutritracker/core/data/data_source/anthropic_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// Turns AI-parsed food items into real diary entries, mirroring the
/// add-intake + tracked-day-totals sequence MealDetailBloc uses for a manual
/// log. Each item becomes a custom-source MealEntity whose per-100g nutriments
/// are derived from the parsed grams + totals.
class LogParsedMealUsecase {
  final AddIntakeUsecase _addIntakeUsecase;
  final AddTrackedDayUsecase _addTrackedDayUsecase;
  final GetKcalGoalUsecase _getKcalGoalUsecase;
  final GetMacroGoalUsecase _getMacroGoalUsecase;

  LogParsedMealUsecase(
    this._addIntakeUsecase,
    this._addTrackedDayUsecase,
    this._getKcalGoalUsecase,
    this._getMacroGoalUsecase,
  );

  Future<void> logItems(
    List<ParsedFoodItem> items,
    IntakeTypeEntity type,
    DateTime day,
  ) async {
    for (final item in items) {
      final intake = _toIntakeEntity(item, type, day);
      await _addIntakeUsecase.addIntake(intake);
      await _updateTrackedDay(intake, day);
    }
  }

  IntakeEntity _toIntakeEntity(
    ParsedFoodItem item,
    IntakeTypeEntity type,
    DateTime day,
  ) {
    // Guard against a zero/negative weight so we never divide by zero.
    final grams = item.grams > 0 ? item.grams : 1.0;

    // ONT stores nutriments per 100g; totalKcal = amount * (per100 / 100).
    // per100 = total / grams * 100 reproduces the parsed totals exactly.
    double per100(double total) => total / grams * 100;

    final meal = MealEntity(
      code: IdGenerator.getUniqueID(),
      name: item.name,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: '',
      nutriments: MealNutrimentsEntity(
        energyKcal100: per100(item.kcal),
        carbohydrates100: per100(item.carbsG),
        fat100: per100(item.fatG),
        proteins100: per100(item.proteinG),
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );

    return IntakeEntity(
      id: IdGenerator.getUniqueID(),
      unit: 'g',
      amount: grams,
      type: type,
      meal: meal,
      dateTime: day,
    );
  }

  /// Mirror of MealDetailBloc._updateTrackedDay: make sure the day exists with
  /// goals, then add this intake's kcal + macros to the running totals.
  Future<void> _updateTrackedDay(IntakeEntity intake, DateTime day) async {
    final hasTrackedDay = await _addTrackedDayUsecase.hasTrackedDay(day);
    if (!hasTrackedDay) {
      final kcalGoal = await _getKcalGoalUsecase.getKcalGoal();
      final carbsGoal = await _getMacroGoalUsecase.getCarbsGoal(kcalGoal);
      final fatGoal = await _getMacroGoalUsecase.getFatsGoal(kcalGoal);
      final proteinGoal =
          await _getMacroGoalUsecase.getProteinsGoal(kcalGoal);
      await _addTrackedDayUsecase.addNewTrackedDay(
        day,
        kcalGoal,
        carbsGoal,
        fatGoal,
        proteinGoal,
      );
    }
    await _addTrackedDayUsecase.addDayCaloriesTracked(day, intake.totalKcal);
    await _addTrackedDayUsecase.addDayMacrosTracked(
      day,
      carbsTracked: intake.totalCarbsGram,
      fatTracked: intake.totalFatsGram,
      proteinTracked: intake.totalProteinsGram,
    );
  }
}