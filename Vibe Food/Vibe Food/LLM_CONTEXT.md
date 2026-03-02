# Vibe Food LLM Context

This file is for coding agents working inside the iOS project.

Read this first when making changes.

## Project Shape

- Platform: iOS
- UI: SwiftUI
- Persistence: SwiftData
- State: `@Observable` stores per feature
- Composition root: `App/AppContainer.swift`
- Core models: `Item.swift`
- Shared value types: `Domain/Types.swift`

## High-Value Invariants

- Do not make meals depend on live ingredient nutrition after save
- Always preserve `localDayKey` semantics
- AI features must produce drafts first, never auto-save records
- Reset must clear insights too
- Insights are stored by target day in `InsightRecord`
- `SettingsRecord.id` is always `"settings"`
- `AIIntegrationRecord.id` is always `"ai-integration"`

## Feature Boundaries

### Dashboard

- Store: `Features/Dashboard/DashboardStore.swift`
- View: `Features/Dashboard/DashboardView.swift`
- Reads meals and goals for the selected day
- Uses shared day navigation state from `DaySelectionStore`

### Meals

- Store: `Features/Meals/MealsStore.swift`
- View: `Features/Meals/MealsView.swift`
- Supports:
  - manual entry
  - ingredient-composed meals
  - JSON import
  - AI meal logging
- New ingredients returned by AI are staged first and only inserted into the ingredient library when the meal is saved

### Ingredients

- Store: `Features/Ingredients/IngredientsStore.swift`
- View: `Features/Ingredients/IngredientsView.swift`
- Supports:
  - CRUD
  - JSON import/export
  - nutrition-label AI scan

### Insights

- Store: `Features/Insights/InsightsStore.swift`
- View: `Features/Insights/InsightsView.swift`
- First opening behavior:
  - if no insights exist at all, show onboarding instead of generating immediately
  - first generation requires explicit user action
- Normal behavior:
  - one stored insight per target day
  - uses cached or stored content when available
  - pull-to-refresh regenerates for the active day
- Input includes:
  - previous day meals
  - previous day totals
  - current goals
  - saved profile/body data when available

### Settings

- Store: `Features/Settings/SettingsStore.swift`
- View: `Features/Settings/SettingsView.swift`
- Recommendation helper and plain profile editing are separate flows

## Persistence Layer

Repositories live in `Persistence/Repositories.swift`.

Protocols:

- `IngredientRepository`
- `MealRepository`
- `SettingsRepository`
- `AIIntegrationRepository`
- `InsightRepository`

Current repository expectations:

- ingredient and meal fetches exclude soft-deleted records
- `InsightRepository.hasAnyInsights()` is used by onboarding logic

## Reset Behavior

`Persistence/ResetService.swift`

Current reset order deletes:

- `IngredientRecord`
- `MealIngredientSnapshotRecord`
- `MealRecord`
- `SettingsRecord`
- `AIIntegrationRecord`
- `InsightRecord`

After deletion, `AppContainer.seedIfNeeded()` recreates default singleton records.

## Shared Systems

### Day Navigation

- Store: `Features/Shared/DaySelectionStore.swift`
- Used by dashboard, meals, and insights
- Handles:
  - selected day
  - settled day after swipe animation
  - horizontal swipe offset
  - vertical-scroll lock coordination
  - future-day blocking

### Glass / Theme

- Shared styling: `Features/Shared/AppGlass.swift`
- Prefer changing shared visual tokens here instead of patching many views

## AI Entry Points

### Meal AI

- `Domain/MealAILogService.swift`
- Supports:
  - local FoundationModels generation
  - OpenAI structured output
  - Anthropic JSON parsing

### Label Scan AI

- `Domain/LabelScanService.swift`
- Supports:
  - OCR + FoundationModels local parse
  - OpenAI remote schema output
  - Anthropic remote JSON parse

### Insights AI

- `Domain/InsightsService.swift`
- Generates structured content currently rendered by `InsightsView`

## Safe Editing Strategy

- If a change affects data shape, inspect:
  - `Item.swift`
  - `Repositories.swift`
  - the corresponding feature store
  - `AppContainer.swift`
  - `ResetService.swift`
- If a change affects visuals across tabs, inspect `AppGlass.swift` first
- If a change affects day-based behavior, inspect `DaySelectionStore.swift` first

## Files To Read Before Specific Changes

- Meal save/import bugs:
  - `Features/Meals/MealsStore.swift`
  - `Domain/MealImport.swift`
  - `Domain/MealAILogService.swift`
- Ingredient draft/import bugs:
  - `Features/Ingredients/IngredientsStore.swift`
  - `Domain/ImportExport.swift`
  - `Domain/LabelScanService.swift`
- Insight generation/onboarding/reset bugs:
  - `Features/Insights/InsightsStore.swift`
  - `Features/Insights/InsightsView.swift`
  - `Persistence/Repositories.swift`
  - `Persistence/ResetService.swift`

## Documentation Map

- `README.md`
  - human-facing project overview
- `GUIDE.md`
  - product and cross-platform behavior guide
- `PLAN.md`
  - earlier implementation plan

If these docs conflict, trust the current code first, then update the docs.
