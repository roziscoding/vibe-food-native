# Vibe Food

Vibe Food is a local-first iOS nutrition tracker built with SwiftUI and SwiftData.

The app is designed to be fully useful on a single device with no account, no sync, and no network connection. AI features are optional drafting tools layered on top of the local workflow.

## What The App Does

- Tracks reusable ingredients with nutrition per portion and per unit
- Tracks meals by local day and local time
- Shows daily calories and macros against configurable goals
- Imports meal drafts from free-form AI descriptions
- Imports ingredient drafts from nutrition-label images
- Generates daily `Insights` from yesterday's meals, today's goals, and saved profile data

## Current Tabs

- `Dashboard`
  - Day-based summary
  - Goal progress for calories, protein, carbs, and fat
  - Macro split card
  - Remaining-today card
- `Insights`
  - One stored insight per target day
  - First-time onboarding before the first generation
  - Pull to regenerate the current day
- `Meals`
  - Daily meal list
  - Manual meal editing
  - Ingredient-based meal editing
  - JSON import
  - `Log With AI`
- `Ingredients`
  - Ingredient CRUD
  - JSON import/export
  - Nutrition-label scan
- `Settings`
  - Goal editing
  - Goal recommendation helper
  - Editable body/profile data
  - AI provider/key configuration
  - Full local reset

## Architecture

- UI: SwiftUI
- State: feature-local `@Observable` stores
- Persistence: SwiftData
- Composition root: `App/AppContainer.swift`
- Shared styling system: `Features/Shared/AppGlass.swift`
- Day navigation state: `Features/Shared/DaySelectionStore.swift`

The app uses repository protocols between stores and SwiftData so feature logic stays decoupled from persistence details.

## Important Data Rules

- Local data is the source of truth
- Meals are stored by `localDayKey`, not UTC-derived grouping
- Meals persist ingredient snapshots so historical meals do not change if ingredients are edited later
- Ingredient and meal deletes are soft deletes
- `SettingsRecord` and `AIIntegrationRecord` are singletons
- `InsightRecord` stores generated insight content by target day

## AI Behavior

AI never commits data directly.

- Meal AI returns a structured draft, then opens the meal editor
- Label scan returns a structured ingredient draft, then opens the ingredient editor
- Insights are stored text payloads generated for a specific day and shown after review-free generation

## Reset Behavior

Reset clears local:

- ingredients
- meals
- meal snapshots
- settings
- AI integration
- insights

Then the app reseeds default settings and an empty AI integration record.

## Main Files

- `App/AppContainer.swift`
  - app composition root and SwiftData schema registration
- `Item.swift`
  - SwiftData models
- `Domain/Types.swift`
  - shared value types and enums
- `Domain/Services.swift`
  - nutrition derivation, summaries, goal recommendations
- `Features/*/*Store.swift`
  - feature state and business logic
- `Features/*/*View.swift`
  - feature UI
- `Persistence/Repositories.swift`
  - repository protocols and SwiftData implementations
- `Persistence/ResetService.swift`
  - destructive local reset

## Related Docs

- `GUIDE.md`
  - product-level behavior and cross-platform implementation guide
- `PLAN.md`
  - historical implementation plan and phased architecture notes
- `LLM_CONTEXT.md`
  - compact architecture and editing rules for coding agents

## Simulator Command Control

The app registers a `vibefood://` URL scheme so it can be controlled from the simulator CLI:

- `xcrun simctl openurl <udid> 'vibefood://command/tab?name=water'`
- `xcrun simctl openurl <udid> 'vibefood://command/day?value=previous'`
- `xcrun simctl openurl <udid> 'vibefood://command/day?value=2026-03-11'`
- `xcrun simctl openurl <udid> 'vibefood://command/water/add?ml=350'`
- `xcrun simctl openurl <udid> 'vibefood://command/water/add?ml=500&date=2026-03-10'`

Equivalent `make` helpers are available at repo root, and they avoid the system `Open` confirmation by relaunching with a launch-time command payload:

- `make command URL='vibefood://command/tab?name=settings'`
- `make command-tab TAB=dashboard`
- `make command-day DAY=today`
- `make command-water ML=300`
- `make command-meal NAME='Chicken Rice' KCAL=600 PROTEIN=40 CARBS=70 FAT=15 [DATE=YYYY-MM-DD]`
- `make command-ingredient NAME='Oats' UNIT=g PORTION=100 KCAL=389 PROTEIN=17 CARBS=66 FAT=7`
