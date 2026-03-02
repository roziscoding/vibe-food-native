# Vibe Food Implementation Guide

This document explains what Vibe Food is and what behavior matters if you are rebuilding the same app on another platform.

It is intentionally product-focused rather than framework-focused. You do not need to copy the current Nuxt, IndexedDB, or RxDB implementation literally. You do need to preserve the same product model, feature set, and data ownership rules.

## 1. Product Definition

Vibe Food is a local-first meal tracker with optional encrypted multi-device sync.

The app is built around four ideas:

- the user's device is the primary owner of meals, ingredients, settings, and AI configuration
- the app must remain useful with no account and no network connection
- sync is replication of local records, not the canonical write path
- AI is used to produce structured drafts that the user reviews before saving

If you preserve only one thing, preserve this contract: the app should feel complete and trustworthy as a single-device offline meal tracker, and sync/AI should be optional layers on top.

## 2. Non-Negotiable Behavior

Any faithful reimplementation should keep these rules:

- local data is the source of truth
- the server does not own meal business logic, ingredient calculations, dashboard totals, or AI result interpretation
- meals are tracked by local day and local time
- meals store ingredient snapshots, not live references to ingredient records
- deleting a syncable record must replicate as a tombstone, not vanish silently
- syncable collections are exactly `ingredients`, `meals`, `settings`, and `ai-integration`
- production sync must assume end-to-end encryption; plaintext sync is only a development convenience

## 3. Core User Value

The app helps a user:

- define reusable ingredients with nutrition per portion and per unit
- compose meals from those ingredients or enter meals manually
- see daily calories and macro totals against goals
- import meals with AI from free-form descriptions
- import ingredients with AI from nutrition label images
- carry the same data across devices through optional encrypted sync
- reopen the app quickly in an installable, offline-capable shell or the platform equivalent

## 4. Core Data Concepts

You can map these records to any local database or document store on the target platform.

### Ingredient

An ingredient represents a reusable food item.

Important fields:

- local ID
- stable UUID for portability and AI matching
- name
- unit, such as `g`, `ml`, `piece`
- portion size
- nutrition per portion: calories, protein, carbs, fat
- derived nutrition per unit
- created timestamp

Behavior:

- validate that nutrition numbers are finite and non-negative
- derive per-unit values from per-portion values when needed
- keep UUIDs stable once created

### Meal

A meal is a historical nutrition entry.

Important fields:

- local ID
- name
- calories
- protein
- carbs
- fat
- created timestamp
- ingredient snapshots as an array of `{ name, amount, unit }`

Critical behavior:

- a meal must remain historically correct even if an ingredient changes later
- because of that, meals persist ingredient snapshots instead of references

### Settings

Settings are a single shared document containing:

- daily calorie goal
- protein goal
- carbs goal
- fat goal

The current app ships with defaults:

- calories: `2000`
- protein: `150`
- carbs: `250`
- fat: `70`

### AI Integration

This is another singleton document containing:

- provider, currently `openai` or `anthropic`
- API key
- last updated timestamp

Important product fact:

- the current app stores the usable API key locally in plain form so AI features can call the provider directly without another unlock step

Compatibility-only detail:

- the web app still supports a legacy format where the key was protected by a 4-digit PIN and must be unlocked once and migrated
- if you are building a fresh port with no data migration, you can skip that legacy flow

### Sync Metadata

If you support the same sync model, each syncable record also needs:

- `updatedAt`
- `deletedAt`
- `lastModifiedByDeviceId`
- `syncVersion`
- tombstone support via `_deleted` and/or `deletedAt`

Conflict resolution is last-write-wins using this tuple:

1. `updatedAt`
2. `lastModifiedByDeviceId`
3. `syncVersion`
4. `id`

## 5. Screens And Features

You do not need to preserve the exact route layout, but you should preserve the same feature surfaces.

### Home / Dashboard

This screen shows the currently selected local day.

Required behavior:

- show all meals for the selected day
- show total calories for that day
- show total protein, carbs, and fat
- show calorie progress against the goal
- let the user move backward and forward through days
- include a quick entry point to log a meal for the selected day

The dashboard should feel like a daily summary, not a reporting system.

### Meals Surface

This is the main place to view meals for a day and start creation flows.

Required behavior:

- show meals for the selected day
- allow targeted creation for that day
- allow editing existing meals
- support two creation modes:
  - manual nutrition entry
  - composition from saved ingredients and quantities
- provide JSON import
- provide AI-assisted import

For ingredient-composed meals:

- the user selects saved ingredients
- the user enters quantities in the ingredient unit
- the app computes total calories and macros from per-unit values
- when saved, the meal stores snapshots of ingredient name, amount, and unit

### Meal Editor

There are three logical editor modes:

- create a new meal
- review an imported meal draft
- edit an existing meal

Required behavior:

- set meal date and time explicitly
- switch between manual mode and ingredient-composition mode
- validate non-negative nutrition values
- require at least one ingredient row in composition mode
- save back into the local store

Important import behavior:

- imported meals are never saved directly
- they first open in a review editor
- the user can modify the meal before committing it

### Meal JSON Import Contract

Manual JSON import and AI meal import both feed the same review flow.

The review draft should understand this shape:

```json
{
  "matched_ingredients": [
    {
      "ingredient_id": "stable-ingredient-uuid",
      "amount": 2
    }
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

Notes:

- `new_ingredients` is optional
- AI may also return a meal name separately
- for compatibility, it is reasonable to accept either `protein` or `proteins` on imported new ingredients
- if imported new ingredients exist, they should be staged and editable before the meal is saved
- staged ingredients are only added to the main ingredient library when the user confirms the meal save

### AI Meal Import

This is a structured drafting flow, not an auto-log feature.

Required flow:

1. read the locally stored AI provider and API key
2. send the meal description plus the current ingredient inventory to the provider
3. ask for structured JSON describing ingredient matches and possible new ingredients
4. store the draft transiently
5. open the import review editor

The ingredient inventory sent to AI should contain enough data for matching:

- stable ingredient UUID
- name
- unit
- calories per unit
- protein per unit
- carbs per unit
- fat per unit

### Ingredients Surface

This is the reusable food library.

Required behavior:

- create ingredients
- edit ingredients
- delete ingredients
- sort or present them in a way that is easy to browse
- store nutrition per portion and per unit
- support JSON import
- support lightweight JSON export
- support AI extraction from nutrition label images

### Ingredient JSON Import Contract

The current import expects a nutrition-label-style object:

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

The flow should parse this payload, prefill the ingredient editor, and let the user confirm or adjust the record before saving.

### Ingredient Export

The current export is intentionally lightweight.

It exports a list of objects containing:

- `name`
- `uuid`
- `unit`

This is not a full backup. It is a lightweight catalog useful for portability and matching.

### AI Ingredient Import

This flow extracts one ingredient from a nutrition label image.

Required flow:

1. capture or choose an image locally
2. send it directly to the configured AI provider
3. receive structured nutrition data
4. prefill the ingredient editor
5. let the user review and save

As with meal import, AI should only create drafts, never commit records automatically.

### Settings Surface

The settings area is the operational hub. It has four major sections.

#### Goals

Required behavior:

- edit daily calorie, protein, carbs, and fat goals
- save them as synced settings
- use them on the dashboard and meals surfaces

The app also includes a recommendation helper.

Required recommendation workflow:

- ask for age, height, weight, sex, activity level, and objective
- generate recommended calorie and macro targets
- prefill the goals form
- let the user save or ignore the recommendations

Matching the exact current formula is less important than preserving the workflow and result type.

#### AI Integration

Required behavior:

- choose provider: `openai` or `anthropic`
- enter or replace the API key
- test the key before saving
- clear the configured integration

Compatibility-only behavior:

- if legacy encrypted records matter for your migration path, allow a one-time unlock with the old 4-digit PIN and migrate to the current plain local format

#### Sync

This is optional but core to the full app.

Required user-visible capabilities:

- bootstrap a new encrypted sync vault
- optionally allow plaintext bootstrap in development only
- connect a new device to an existing encrypted vault
- authorize another device from an already trusted device
- show sync status, last successful sync, and retry state
- run sync manually
- pause or resume sync on the device
- list linked devices
- show locally recorded sync conflicts
- export a recovery key
- sign out of sync while keeping local data
- delete the cloud sync copy

The recovery key should contain everything needed to restore vault access, including the vault token and passphrase or an equivalent credential bundle.

#### Data Reset

Required behavior:

- clear all local meals, ingredients, settings, and local AI/sync state
- leave the remote cloud copy untouched unless the user explicitly chooses the separate cloud-delete action

## 6. Sync Architecture To Preserve

If you build the same sync system on another platform, preserve these contracts even if the implementation changes.

### What sync replicates

Exactly these collections:

- `ingredients`
- `meals`
- `settings`
- `ai-integration`

### What the server does

The server should only handle:

- vault creation and deletion
- device registration
- replication pull and push
- wrapped key storage
- pairing requests and approvals

The server should not:

- calculate nutrition
- validate meals as product concepts
- interpret AI results
- generate dashboard totals

### Encryption model

Production transport mode is `e2ee-v1`.

Required properties:

- documents are encrypted on the client before upload
- the server stores ciphertext only
- the passphrase never leaves the client in plaintext
- additional authenticated data binds the payload to vault and document metadata
- new devices still need the vault passphrase even after being approved

The current web app uses:

- AES-GCM for document encryption
- PBKDF2-SHA256 for passphrase-based wrapping

You can change the crypto library on another platform, but not the trust model.

### Pairing model

Pairing is for encrypted vaults only.

Required flow:

1. the new device creates a pairing request and gets a short code
2. an already linked device approves that request
3. the new device receives vault credentials
4. the user enters the same vault passphrase locally to finish linking

The important product property is that approval alone is not enough; the passphrase is still required.

### Retry model

Transient sync failures should retry automatically with bounded backoff.

The current progression is:

- 5 seconds
- 15 seconds
- 30 seconds
- 60 seconds
- 120 seconds

Non-retryable auth or configuration errors should surface clearly instead of retrying forever.

## 7. Storage Model To Preserve

For another platform, use any persistent local store that supports offline reads and writes well.

What matters is not the exact storage engine. What matters is:

- user data persists locally first
- syncable collections are individually addressable
- temporary import drafts can be stored transiently
- sync credentials and passphrase are stored separately from ordinary product records
- local conflict history exists for diagnostics

If you do not need data migration from the current web app, you do not need to preserve IndexedDB database names or object store names.

## 8. Suggested Implementation Phases

This sequence is the fastest way to rebuild the app without losing the product intent.

### Phase 1: Local-First Foundation

Build:

- local data layer
- ingredient, meal, settings, and AI integration records
- app shell and navigation

Success condition:

- the app works offline with no account and no server

### Phase 2: Ingredient Library

Build:

- ingredient CRUD
- nutrition validation
- per-unit derivation
- lightweight export
- JSON import into an editable draft

Success condition:

- users can build a reliable reusable ingredient catalog

### Phase 3: Meals And Dashboard

Build:

- day-based dashboard
- daily totals and goal progress
- manual meal creation
- ingredient-composed meal creation
- meal editing
- explicit date/time selection

Success condition:

- single-device meal tracking is fully useful without AI or sync

### Phase 4: Meal Import Review Flow

Build:

- meal JSON import
- draft storage
- import review editor
- staged new ingredients that are only committed on meal save

Success condition:

- external or AI-generated meal drafts are safe to review before commit

### Phase 5: AI Features

Build:

- provider selection and API key storage
- key testing
- AI meal import from description
- AI ingredient import from image

Success condition:

- AI can generate structured drafts, but never bypass review

### Phase 6: Encrypted Sync

Build:

- vault creation
- device registration
- encrypted replication for the four syncable collections
- conflict logging
- status and retry handling
- recovery export

Success condition:

- two devices can safely converge on the same local-first dataset

### Phase 7: Device Pairing And Diagnostics

Build:

- pairing requests and approval flow
- QR or code-based handoff
- linked device list
- technical sync details
- delete cloud copy
- sign out while keeping local data

Success condition:

- users can manage sync operationally without losing trust in the system

### Phase 8: Installability And Offline Shell

Build:

- quick relaunch behavior, such as PWA installability or native packaging
- caching of app assets or equivalent shell resources
- graceful offline startup that still opens the last local data

Success condition:

- the app feels dependable when reopened without network access

### Phase 9: Compatibility Extras

Only build these if you need parity with existing Vibe Food web data:

- legacy AI key unlock and migration
- development-only plaintext sync bootstrap

## 9. Acceptance Checklist

A reimplementation is functionally faithful if all of the following are true:

- a new user can install or open the app and use it fully offline
- the app is still useful with no sync and no AI configured
- ingredients are reusable and store both portion-based and unit-based nutrition
- meals can be created manually or from ingredients
- meal totals are stored at save time and ingredient snapshots remain historical
- the dashboard shows daily calorie and macro progress against goals
- manual JSON meal import and AI meal import both go through review before save
- ingredient JSON import and AI ingredient import both prefill the editor rather than auto-save
- settings, AI integration, meals, and ingredients are the only syncable product datasets
- encrypted sync keeps the server ignorant of plaintext records and passphrases
- conflict resolution is deterministic and deletion replicates
- clearing local data does not implicitly delete the remote sync vault

## 10. Platform Freedom

These pieces may change on another platform without changing the app itself:

- route structure
- UI component library
- local database engine
- sync transport library
- background task mechanism
- crypto library
- installability model, such as PWA versus native app packaging

If you keep the product contract, data semantics, review-first AI flows, and local-first sync model intact, the result will still be Vibe Food.
