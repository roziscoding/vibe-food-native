# Vibe Food iOS MVP Implementation Plan

## Summary
- Goal: build a local-first iOS 17+ SwiftUI/SwiftData app from the current Xcode template, delivering the full standalone meal tracker plus JSON review flows first; AI and sync come later.
- Current baseline: the project only has the starter SwiftData template in [Vibe_FoodApp.swift](/Users/roziscoding/github.com/roziscoding/vibe-food-native/Vibe%20Food/Vibe%20Food/Vibe_FoodApp.swift), [ContentView.swift](/Users/roziscoding/github.com/roziscoding/vibe-food-native/Vibe%20Food/Vibe%20Food/ContentView.swift), and [Item.swift](/Users/roziscoding/github.com/roziscoding/vibe-food-native/Vibe%20Food/Vibe%20Food/Item.swift).
- Success criteria: the app is fully useful offline with no account, ingredients are reusable, meals support manual and ingredient-based entry, dashboard totals are day-based and goal-aware, imports are always review-first, and the schema is ready for future AI/sync without a rewrite.

## Architecture decisions
- Keep SwiftData as the local persistence layer. Do not add third-party runtime dependencies in the MVP.
- Add tombstone metadata to all future syncable records from day one. UI queries always filter out `deletedAt != nil`.
- Use canonical record IDs now so future sync does not require schema changes: `IngredientRecord.id: UUID`, `MealRecord.id: UUID`, `SettingsRecord.id = "settings"`, and `AIIntegrationRecord.id = "ai-integration"`. SwiftData’s `persistentModelID` is the local database identity.
- Preserve local-day semantics by storing `consumedAt`, `timeZoneIdentifier`, and `localDayKey` on every meal. Daily queries use `localDayKey`, not UTC calendar math.
- Persist meal ingredient snapshots as dedicated child records. Never recompute an existing meal from live ingredient data.
- Use `@Observable` feature stores/view models with repository protocols over SwiftData for testability and to isolate persistence from UI.
- Keep AI and sync behind protocols and placeholder models only. Do not expose sync in MVP UI. Do not expose AI UI until the later AI phase.
- Keep the current universal target because Xcode created an iPhone+iPad target, but optimize the MVP UX for iPhone. iPad gets adaptive SwiftUI layouts, not a separate tablet design pass.

## Project restructure
- Replace [Item.swift](/Users/roziscoding/github.com/roziscoding/vibe-food-native/Vibe%20Food/Vibe%20Food/Item.swift) with the real domain/persistence models.
- Replace [ContentView.swift](/Users/roziscoding/github.com/roziscoding/vibe-food-native/Vibe%20Food/Vibe%20Food/ContentView.swift) with a root `TabView` shell containing `Dashboard`, `Meals`, `Ingredients`, and `Settings`.
- Expand [Vibe_FoodApp.swift](/Users/roziscoding/github.com/roziscoding/vibe-food-native/Vibe%20Food/Vibe%20Food/Vibe_FoodApp.swift) to configure the full `ModelContainer`, create an `AppContainer`, inject repositories/services, seed singleton records, and route app-wide sheets.
- Add folders: `App`, `Domain`, `Persistence`, `Features/Dashboard`, `Features/Meals`, `Features/Ingredients`, `Features/Settings`, `Features/Shared`, and `Support/Preview`.
- Add `Vibe FoodTests` and `Vibe FoodUITests` targets before feature work starts.

## Core models and value types
- `IngredientRecord`: `id`, `name`, `unit`, `portionSize`, per-portion macros, per-unit macros, `createdAt`, `updatedAt`, `deletedAt`, `lastModifiedByDeviceId`, `syncVersion`.
- `MealRecord`: `id`, `name`, `calories`, `protein`, `carbs`, `fat`, `consumedAt`, `timeZoneIdentifier`, `localDayKey`, `createdAt`, `updatedAt`, `deletedAt`, `lastModifiedByDeviceId`, `syncVersion`, and a snapshots relationship.
- `MealIngredientSnapshotRecord`: `id`, meal relation, optional `sourceIngredientID`, `name`, `amount`, `unit`.
- `SettingsRecord`: fixed `id = "settings"`, calorie/protein/carbs/fat goals, `updatedAt`, `deletedAt = nil`, `lastModifiedByDeviceId`, `syncVersion`.
- `AIIntegrationRecord`: fixed `id = "ai-integration"`, provider, API key, `updatedAt`, `deletedAt`, `lastModifiedByDeviceId`, `syncVersion`. The model exists in MVP; the UI is deferred.
- Value types: `MacroBreakdown`, `MacroTargets`, `IngredientDraft`, `MealDraft`, `MealDraftIngredientLine`, `IngredientImportPayload`, `MealImportPayload`, `DailySummary`, `GoalRecommendationInput`, `GoalRecommendationOutput`, `ValidationError`.
- Enums: `IngredientUnit`, `MealEditorMode`, `MealEntryMode`, `AIProvider`, `ActivityLevel`, `GoalObjective`.

## Repositories and services
- `IngredientRepository`, `MealRepository`, `SettingsRepository`, and `AIIntegrationRepository` protocols with SwiftData-backed implementations.
- `DailySummaryService` aggregates meals for a `localDayKey`.
- `NutritionDerivationService` normalizes per-unit fields from portion values and validates finite/non-negative inputs.
- `GoalRecommendationService` computes calorie/macro recommendations from age, height, weight, sex, activity level, and objective. The exact formula does not need to match the web app, but the workflow and output type must match.
- `MealImportService` parses JSON into a `MealDraft`, resolves `matched_ingredients` against active ingredient UUIDs, and records unresolved matches as review errors.
- `IngredientImportService` parses nutrition-label JSON into an `IngredientDraft`.
- `ExportService` produces the lightweight ingredient catalog JSON containing only `name`, `uuid`, and `unit`.
- `ResetService` clears all local product data, cached drafts, and local operational state, then re-seeds singleton records. It intentionally does not touch remote sync because sync is deferred.
- `DeviceIdentityStore` persists `deviceId` outside ordinary product records. Use `UserDefaults` in MVP behind a protocol so it can be moved to Keychain later without caller changes.
- `DraftCoordinator` keeps active JSON import drafts in memory only for the current flow. If the app is terminated mid-review, the draft is intentionally lost.

## UI and flow decisions
- Root navigation is a `TabView` with one `NavigationStack` per tab.
- Dashboard tab shows selected day, previous/next day controls, a `Today` shortcut, summary cards, meals for that day, and a primary add-meal action.
- Meals tab shows the same day selector plus richer meal management: add, edit, delete, and manual JSON import. Import history is out of scope.
- Ingredients tab shows a searchable/sortable list, create/edit/delete actions, JSON import, and JSON export via share sheet.
- Settings tab in MVP includes Goals, Goal Recommendation Helper, and Data Reset. AI Integration and Sync sections are omitted until later phases.
- Creation/editing flows use sheets on iPhone and adaptive sheets/navigation on iPad.
- Meal editor supports `manual` and `from ingredients` modes. The chosen mode controls validation and editable fields, but both save into the same `MealRecord`.
- JSON import entry points support both `Paste JSON` and `Import File…` so the app does not force a single input method.
- Import never writes records directly. Every import opens a review editor first; save is the only commit point.
- Ingredient-composed meal save writes total macros onto the meal and writes snapshot rows. It does not keep a live nutritional dependency on the source ingredient.
- Ingredient deletion is a soft delete. Existing meals keep their snapshot history. Deleted ingredients disappear from pickers, queries, and exports.

## Delivery phases

### Phase 0: Foundation reset
- Remove the template `Item` model and sample list UI.
- Change the Xcode-created deployment target from the placeholder `26.2` value to a real iOS 17.x target before coding.
- Create unit/UI test targets and a preview/sample-data harness.
- Establish the folder layout, app container, model container, repository interfaces, and shared date/number formatting utilities.

### Phase 1: Local data layer
- Implement SwiftData schemas for ingredients, meals, meal snapshots, settings, and AI integration.
- Add first-launch bootstrapping for `SettingsRecord` with default goals `2000/150/250/70` and `AIIntegrationRecord` with empty provider/key.
- Add soft-delete filtering, timestamp updates, sync metadata defaults, and deterministic `deviceId` generation.
- Keep schema comments focused on future AI/sync expectations rather than adding separate docs.

### Phase 2: Ingredients
- Build the ingredient list with search by name and alphabetical sort.
- Build the ingredient editor with unit picker, portion size, macro inputs, live per-unit preview, and save validation.
- Re-derive per-unit values on every save and reject NaN, infinity, negative values, and zero/negative portion size.
- Add soft delete with confirmation.
- Add JSON import for the nutrition-label contract and route parsed values into the same editor as a draft.
- Add export that shares a JSON file containing only `name`, `uuid`, and `unit`.

### Phase 3: Settings and goals
- Build the goals editor backed by `SettingsRecord`.
- Build a recommendation helper sheet that collects age, height, weight, sex, activity level, and objective, then proposes calorie/macros into the form without auto-saving.
- Add a two-step destructive Data Reset flow and re-seed singleton records afterward.
- Ensure dashboard and meals read goals reactively from the singleton settings record.

### Phase 4: Meals and dashboard
- Build the dashboard day selector using `localDayKey`, previous/next day controls, and a `Today` shortcut.
- Build daily summary cards for calories and macros against goals.
- Build the meal list for a selected day with totals, timestamps, edit actions, and soft delete.
- Build the meal editor supporting manual entry and ingredient composition.
- In composition mode, each line has an ingredient picker, quantity input, and computed row macros; save requires at least one valid line.
- In manual mode, name/date/time/macros are direct inputs and ingredient lines are hidden.
- On save, compute totals from ingredient lines when in composition mode and persist snapshot rows containing ingredient name, amount, unit, and source UUID if present.
- Editing a meal loads existing snapshot rows into a composition draft or direct macros into a manual draft. Changing an ingredient later must never change the saved meal.

### Phase 5: Review-first JSON imports
- Implement meal JSON parsing for `matched_ingredients` and optional `new_ingredients`, accepting both `protein` and `proteins`.
- Resolve matched ingredient UUIDs against active ingredients. Unresolved IDs become review errors that the user can fix in the editor.
- Stage `new_ingredients` inside the meal draft as editable ingredient drafts. They are inserted into the ingredient library only after the meal save succeeds.
- Use one shared review editor path so manual JSON meal imports and future AI meal imports hit the same codepath.
- Add ingredient JSON import review so imports prefill the ingredient editor instead of saving immediately.
- Add clear, user-facing parse and validation errors for malformed JSON, missing required fields, and invalid numeric values.

### Phase 6: Hardening and polish
- Add empty states, destructive confirmations, inline validation, keyboard handling, and localized formatting for units, numbers, and dates.
- Add seeded preview data for ingredients, meals, and goals.
- Add first-run smoke coverage in UI tests and regression tests for daily totals, imports, staged ingredient commits, and data reset.
- Optimize queries and summary recomputation only if profiling shows a real issue. Do not add premature caching layers.

## Future phases after MVP
- AI phase: expose `AIIntegrationRecord` in Settings, test/store provider keys, add meal-description import and nutrition-label image import behind provider clients, and reuse the same draft editors.
- Sync phase: keep the existing model metadata, add credential storage outside SwiftData, introduce encrypted replication for `ingredients`, `meals`, `settings`, and `ai-integration`, and implement tombstone sync, conflict logs, retry/backoff, and vault/device management.
- Pairing/diagnostics phase: add linked devices, approval flow, recovery export, delete-cloud-copy, and sign-out-while-keeping-local-data.

## Interfaces, contracts, and type additions
- JSON meal import contract accepted by the app:
```json
{
  "matched_ingredients": [
    { "ingredient_id": "uuid", "amount": 2.0 }
  ],
  "new_ingredients": [
    {
      "name": "New ingredient",
      "unit": "g",
      "portion_size": 100,
      "calories": 250,
      "protein": 10,
      "carbs": 20,
      "fat": 5
    }
  ]
}
```
- JSON ingredient import contract accepted by the app:
```json
{
  "product_name": "Greek Yogurt",
  "portion_unit": "g",
  "portion_size": 170,
  "calories": 100,
  "macros_per_portion": {
    "protein_g": 17,
    "carbohydrates_g": 6,
    "total_fat_g": 0
  }
}
```
- Ingredient export contract produced by the app:
```json
[
  { "name": "Greek Yogurt", "uuid": "uuid", "unit": "g" }
]
```
- Daily summary API returned by `DailySummaryService`: selected day key, meals array, total calories, total protein, total carbs, total fat, and goal progress percentages.
- Meal save API used by editors: `save(draft: MealDraft, mode: MealEntryMode)` returns the persisted meal ID plus any newly committed ingredient IDs created from staged drafts.
- Reset API: `resetAllLocalData()` clears product data, drafts, and local operational state, then re-seeds singleton settings and AI records.

## Test cases and scenarios
- Ingredient derivation recalculates per-unit macros correctly from portion size and per-portion values.
- Ingredient validation rejects zero portion size, negative values, NaN, and infinity with field-level errors.
- Editing an ingredient after saving a composed meal does not change the meal’s stored totals or snapshots.
- A meal saved near midnight remains on its original `localDayKey`, even if the device timezone later changes.
- Dashboard totals and goal progress update correctly when meals are created, edited, soft-deleted, and restored in tests.
- Valid meal JSON creates a review draft. Malformed JSON surfaces a recoverable error. Both `protein` and `proteins` are accepted.
- Imported `new_ingredients` are not inserted into the ingredient library until meal save succeeds.
- Ingredient export includes only active ingredients and intentionally omits nutrition values.
- Data reset clears all local meals, ingredients, settings overrides, AI data, and cached drafts, then recreates defaults.
- UI smoke coverage verifies first launch, default goals, ingredient creation, manual meal creation, composed meal creation, and reviewed meal import save.

## Acceptance criteria for the MVP
- A new user can launch the app with no account and no network connection and still use it fully.
- Ingredients can be created, edited, deleted, imported from JSON into a review screen, and exported as a lightweight catalog.
- Meals can be created manually or from ingredients, edited later, and grouped by selected local day.
- The dashboard shows daily calories and macros against configurable goals.
- JSON meal imports and JSON ingredient imports always route through review before save.
- Settings support goals, goal recommendations, and full local data reset.
- The data model already contains the IDs and tombstone metadata needed for future AI/sync work, so later phases do not require a schema rethink.

## Explicit assumptions and defaults
- This is a fresh native iOS build with no migration from the web app’s IndexedDB stores or legacy PIN-protected AI key format.
- MVP scope ends after local-first core features and JSON review flows. AI and sync are intentionally deferred.
- The app targets iOS 17+ and keeps SwiftData.
- The project remains universal because the current Xcode target includes iPhone and iPad, but MVP design and QA are iPhone-first.
- No remote backend or sync server is planned in the MVP.
- No third-party runtime dependencies are required for MVP implementation.
