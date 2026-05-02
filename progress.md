# Slate 3 Implementation Progress

This file is a handoff checklist for continuing the Slate 3 rewrite in this repository.

## Current Status

The repository now contains a compiling Swift package with the initial Slate 3 target structure:

- `Slate`: runtime library.
- `SlateSchema`: public schema/protocol/annotation module.
- `SlateSchemaMacros`: macro implementation target.
- `SlateGeneratorLib`: source parser, normalized schema model, validator, renderers, manifest/file writer.
- `SlateGenerator`: `slate-generator` CLI.
- `SlateFixturePatientModels` / `SlateFixturePatientPersistence`: in-tree compile-tested fixture targets that exercise the full generator pipeline (entity + relationships + embedded struct + enum + default expression). The persistence module's source files are committed and built by `swift build`; a generator round-trip test verifies they stay in sync.
- Tests for runtime basics, macro expansion, and generator/parser/rendering behavior.

Verification at this point:

- [x] `swift test` passes.
- [x] `swift build` passes.
- [x] `swift run slate-generator dump-schema ...` smoke tested.
- [x] `swift run slate-generator generate ...` smoke tested.
- [x] `swift run slate-generator check ...` smoke tested.
- [x] `swift run slate-generator clean ...` smoke tested.

Note: `Slate3` was not a git repository when checked, so no git status/diff summary is available from inside this directory.

## Implemented

### Package Shape

- [x] Created SwiftPM package with Swift tools version 6.0.
- [x] Added products:
  - `Slate`
  - `SlateSchema`
  - `slate-generator`
- [x] Added targets:
  - `Slate`
  - `SlateSchema`
  - `SlateSchemaMacros`
  - `SlateGeneratorLib`
  - `SlateGenerator`
  - `SlateTests`
  - `SlateSchemaMacroTests`
  - `SlateGeneratorTests`
- [x] Added dependencies:
  - `swift-argument-parser`
  - `swift-syntax` exact `603.0.0`

### SlateSchema

- [x] Added `SlateID` as `NSManagedObjectID`.
- [x] Added `SlateObject`.
- [x] Added `SlateKeypathAttributeProviding`.
- [x] Added `SlateKeypathRelationshipProviding`.
- [x] Added `SlateSchema`.
- [x] Added `SlateMutableObject`.
- [x] Added `SlateRelationshipHydratingMutableObject` for mutable objects that can convert with an explicit set of requested relationship names.
- [x] Added `SlateTableRegistry`.
- [x] Added type-erased `AnySlateTable`.
- [x] Added metadata types:
  - `SlateEntityMetadata`
  - `SlateAttributeMetadata`
  - `SlateRelationshipMetadata`
  - `SlateRelationshipKind`
  - `SlateDeleteRule`
- [x] Added public annotation macro declarations:
  - `@SlateEntity`
  - `@SlateAttribute`
  - `@SlateEmbedded`
- [x] Added syntax carrier types:
  - `SlateIndex`
  - `SlateUniqueness`
  - `SlateRelationship`

Important design note:

- [x] The original plan’s generic macro declaration shape using `SlateIndex<Self>`, `SlateUniqueness<Self>`, and `SlateRelationship<Self>` did not compile in a global macro declaration. The current implementation uses non-generic carrier types with generic static functions instead.

### SlateSchemaMacros

- [x] Added compiler plugin.
- [x] Implemented no-op peer macros for `@SlateAttribute` and `@SlateEmbedded`.
- [x] Implemented `@SlateEmbedded` member macro for embedded structs:
  - generates public memberwise initializer for stored `let` properties
  - keeps peer expansion no-op for property annotation compatibility
- [x] Implemented `@SlateEntity` member/extension macro for simple stored `let` properties:
  - adds `public let slateID: SlateID`
  - adds public memberwise initializer
  - adds public `init(managedObject:)`
  - adds entity-local `ManagedPropertyProviding`
  - adds `keypathToAttribute`
  - adds `SlateObject` conformance extension
  - adds `SlateKeypathAttributeProviding` conformance extension
- [x] `@SlateEntity` parses simple relationship declarations and generates optional immutable relationship properties:
  - to-one relationships as `Destination?`
  - to-many relationships as `[Destination]?`
- [x] `@SlateEntity` generates `keypathToRelationship` for macro-declared relationships.
- [x] `@SlateEntity` macro `keypathToAttribute` honors `@SlateAttribute(storageName:)` for direct stored attributes.
- [x] `@SlateEntity` emits an error diagnostic for mutable stored `var` properties.
- [x] Added macro expansion test for basic entity scaffolding.
- [x] Added macro expansion test for embedded memberwise initializer.
- [x] Added macro diagnostic test for mutable stored properties.
- [x] Added macro expansion test for relationship accessors.
- [x] Added macro expansion test for embedded keypath mapping that flattens nested `@SlateEmbedded` attributes (including `@SlateAttribute(storageName:)` overrides) into entity-level `keypathToAttribute` cases.
- [x] `@SlateEmbedded` is now peer-only. Authors must declare a public memberwise initializer manually for embedded structs. Reason: Swift macro role validation rejects `@attached(member)` on a property attachment site, and the same macro is needed in both contexts. The peer-only role matches the design decision that `@SlateEmbedded` is a property annotation only — embedded struct types still carry `@SlateEmbedded` as a parser marker but no longer get auto-synthesized inits.
- [x] `@SlateEntity`-emitted memberwise initializer reorders parameters so direct attributes precede embedded properties. Without this the bridge code's `Patient(slateID:, ..., status:, address:)` argument order disagrees with the macro-emitted source order and the persistence module fails to compile.
- [x] Parser rejects `@SlateEmbedded` on attributes nested inside another embedded struct: `@SlateEmbedded` is only valid on entity-level properties (and as a marker on the nested struct's type itself). Tests cover the rejection case.

Known macro limitations:

- [x] `@SlateEntity` invalid-declaration diagnostics broadened. The macro now emits compile-time errors for: non-public entity (`@SlateEntity types must be declared 'public'`), generic entity (`@SlateEntity does not support generic types`), inherited base class (`@SlateEntity classes may conform to protocols but must not inherit from a base class` — the macro keeps a small allowlist of well-known protocol names: `Sendable`, `Equatable`, `Hashable`, `Codable`, `Decodable`, `Encodable`, `Identifiable`, `CustomStringConvertible`, `CustomDebugStringConvertible`), `@SlateAttribute`/`@SlateEmbedded` annotated computed properties (`@SlateEntity persisted properties must be stored ('let')`), and persisted declarations nested inside `#if`/`#elseif`/`#else` (`@SlateEntity persisted properties cannot be wrapped in conditional compilation (#if) blocks`). The parser already raised these from the generator; the macro mirrors them so users see them in the IDE without running `slate-generator`.
- [x] `@SlateEntity` rejects `var` stored properties with a diagnostic.
- [x] Relationship accessors are generated as optional immutable properties.
- [x] Relationship key-path mapping is generated through `SlateKeypathRelationshipProviding`.
- [x] Embedded struct initializers are generated when the embedded struct itself is annotated with `@SlateEmbedded`.
- [x] Embedded key-path mapping is generated in macro expansion: `\Entity.address?.city` and `\Entity.name.first` cases are emitted with optional/non-optional separators and `@SlateAttribute(storageName:)` overrides honored.
- [x] `@SlateAttribute(storageName:)` is reflected in macro `keypathToAttribute` for direct attributes.

Important relationship macro note:

- [x] To-many immutable relationship accessors currently use `[Destination]?` for both ordered and unordered relationships. This is intentionally compile-safe because `Set<Destination>` would require generated immutable models to be `Hashable`, which Slate 3 has not designed yet.

### Slate Runtime

- [x] Added `Slate<Schema: SlateSchema>`.
- [x] Added async `configure()`.
- [x] Added async `query`.
- [x] Added async `mutate`.
- [x] Added Core Data store opening from generated `Schema.makeManagedObjectModel()`.
- [x] Added SQLite cache-store wipe-on-incompatible-open support:
  - deletes exact sqlite URL
  - deletes `-wal`
  - deletes `-shm`
  - does not delete parent directory
- [x] Added process-wide store registry actor keyed by URL/schema for disk stores.
- [x] Added in-memory identity handling.
- [x] Added simple reader/writer access gate actor.
- [x] Added `TaskLocal` transaction scope and nested transaction rejection.
- [x] Added `SlateQueryContext`.
- [x] Added `SlateQueryTable`.
- [x] Added `SlateMutationContext`.
- [x] Added `SlateMutationTable`.
- [x] Added basic create/many/one/count/delete behavior on tables.
- [x] Added `context.immutable(row)` explicit conversion helper.
- [x] Added query relationship requests via `SlateQueryTable.relationships([\.relationship])`.
- [x] Runtime fetches set Core Data `relationshipKeyPathsForPrefetching` for requested relationship names.
- [x] Runtime conversion passes requested relationship names through table conversion.
- [x] Runtime conversion hydrates requested relationships when the generated/manual mutable object conforms to `SlateRelationshipHydratingMutableObject`.
- [x] Renamed table fetch APIs to `one()` / `many(limit:offset:)` / `count()` per design spec; legacy `fetch()`/`fetchOne()` removed.
- [x] Added `slate.one(_:where:sort:relationships:)`, `slate.many(_:where:sort:limit:offset:relationships:)`, and `slate.count(_:where:)` direct convenience methods that go through `query`.
- [x] Added mutation table operations: `firstOrCreate(_:_:sort:)`, `firstOrCreateMany(_:_:sort:)`, `upsert(_:_:)`, `upsertMany(_:_:)`, `dictionary(by:)`, `deleteMissing(key:keeping:emptySetDeletesAll:)`, plus `one(where:)` / `many(where:)` / `count(where:)` short forms.
- [x] Added runtime test for in-memory configure, mutate insert, query fetch.
- [x] Added runtime test for requested to-one relationship hydration.
- [x] Added runtime test for requested unordered and ordered to-many relationship hydration.
- [x] Added runtime tests for direct convenience query methods (`one`/`many`/`count`/limit/offset/relationship hydration).
- [x] Added runtime tests for mutation table semantics: `firstOrCreate`, `firstOrCreateMany`, `dictionary`, `delete(where:)`, `deleteMissing` happy path, `deleteMissing` empty-set guard, and rollback on user thrown error.

Important runtime design note:

- [x] The planned overload where a mutation block returns a mutable `NSManagedObject` row and the outer `mutate` returns the immutable value was tried and removed. It is awkward under strict Sendable because the generic `mutate<Output: Sendable>` shape infers the immutable output. Current v1 path is explicit conversion inside the mutation block via `context.immutable(row)`.

Known runtime limitations:

- [x] The reader/writer access gate now uses a continuation-based FIFO queue with write priority and cancellation handling; no polling.
- [x] Basic immutable object cache (`SlateObjectCache`) wired into the store owner. Query reads with no relationships requested check/populate the cache by `NSManagedObjectID`.
- [x] Mutations now apply pre-save cache hydration: changed managed objects are converted to immutable values and inserted/updated/removed in the cache before `save()`, and a per-mutation undo snapshot is captured first so the cache can be restored if the save fails.
- [x] Failed save rollback now also restores the cache from the captured undo set; user-error paths roll back the writer context with cache untouched.
- [x] Pre-save cache invalidation also evicts mutated objects whose `convert` throws (e.g., enum attributes whose stored raw value no longer maps to a case). Without this the cache would silently return the previous valid value on the next read; with it the next read forces a fresh `slateObject(hydrating:)` call that surfaces `SlateError.invalidStoredValue`. The undo snapshot still covers these IDs, so a save-failure rollback restores the prior cache entry.
- [x] Registry exposes `table(forManagedObject:)` / `table(forEntityName:)` so the runtime can convert arbitrary writer-side `NSManagedObject`s back to immutable values during pre-save hydration.
- [x] `slate.batchDelete(_:where:)` runs as a real `NSBatchDeleteRequest` on SQLite stores (`resultType = .resultTypeObjectIDs`), merges deleted IDs into the writer context via `mergeChanges(fromRemoteContextSave:into:)`, evicts them from `SlateObjectCache`, and broadcasts to live streams through a per-stream batch-delete sink registered on `SlateStoreOwner` (so streams re-fetch even though `NSBatchDeleteRequest` does NOT post `NSManagedObjectContextDidSave`). On non-SQLite stores (in-memory, etc.) the call falls back to fetch + per-row `context.delete(_:)` + `save()` inside the writer queue — `save()` fires the normal `didSave` notification and existing stream observers handle propagation. Both paths evict the deleted IDs from the cache. Tests cover: in-memory fallback, SQLite path with on-disk store, predicate vs. no-predicate, closed-Slate rejection, fallback-path stream propagation, and SQLite-path stream propagation.
- [x] Relationship hydration during query conversion exists for requested relationships on hydrating mutable objects.
- [x] Relationship hydration generated-output coverage broadened: `rendersAllRelationshipKindHydrationExpressions` is a new renderer test that pins all three relationship kinds (to-one, ordered to-many, unordered to-many) end-to-end through `GeneratedSchemaRenderer` — covering mutable property declarations (`DestinationMutable?` / `NSOrderedSet?` / `Set<DestinationMutable>?`), `NSRelationshipDescription` setup in `makeManagedObjectModel()`, the per-kind unwrap form in `slateObject(hydrating:)` (`X?.slateObject` / `X?.map { $0.slateObject }` / `(X?.array as? [DatabaseY])?.map(\.slateObject)`), and the `SlateRelationshipHydratingMutableObject` extension. The hand-rolled `DatabaseTestPerson.slateObject(hydrating:)` was aligned byte-for-byte with the renderer's emitted form so the runtime tests in `queryHydratesRequestedToOneRelationship`, `queryHydratesRequestedToManyRelationships`, and `directQueryHydratesRelationships` exercise the exact code shape the generator produces. Compile-tested generated fixture in a synthetic multi-module package is still the open separate item under "Compile-Test Generated Output".
- [x] Streams (`SlateStream<Value>` and `SlateBackgroundStream<Value>`) implemented as `@Observable` final classes (MainActor / `@SlateStreamActor` isolated). FRC-backed; each stream owns a private-queue stream context attached to the same coordinator. Writer-context `NSManagedObjectContextDidSave` notifications drive a merge + re-fetch on the stream queue, then `controllerDidChangeContent` republishes converted immutable values across the actor boundary.
- [x] `SlateStreamActor` global actor for background-stream isolation.
- [x] `Observation` integration via `@Observable` macro on the concrete classes (no `any SlateStream` existential — design doc fallback to a concrete read-only public class was used).
- [x] `cancel()` removes the writer-save observer, severs the FRC delegate, and finishes any open async-stream continuations; subsequent saves do not update a cancelled stream.
- [x] `valuesAsync` and `valueAsync` `AsyncThrowingStream` adapters that yield current value + future updates, finish on `cancel()`, and throw on `failed`.
- [x] `slate.stream(...)` (MainActor) and `slate.streamBackground(...)` convenience methods on `Slate`.
- [x] `slate.close()` async closes the runtime: subsequent `query`/`mutate`/convenience calls and `configure()` throw `SlateError.closed`. Implemented with an internal lock; close also drains any in-flight write by acquiring the access gate.
- [x] `upsert`/`upsertMany` now consult the entity's declared uniqueness metadata before delegating to `firstOrCreate`/`firstOrCreateMany`. `AnySlateTable` carries a new `uniquenessConstraints: [[String]]` field threaded through `SlateTableRegistry.register(...)`. The runtime requires the supplied key path to match a single-attribute uniqueness constraint and otherwise throws `SlateError.upsertKeyNotUnique(entity:attribute:)` so an unconstrained upsert can't silently match (or miss) multiple rows. Generated `Schema.registerTables(...)` now passes the parsed `uniquenessConstraints` literal through to the registry; an entity without any declared uniqueness still emits `uniquenessConstraints: []` so the call signature is uniform. Tests cover: matching upsert returns existing row, upsertMany matches+creates, single-key validation rejects keys outside declared uniqueness, and the renderer emits `uniquenessConstraints: [["patientId"]]` (constrained) and `uniquenessConstraints: []` (unconstrained).
- [x] Mutation table semantics include `firstOrCreate`, `firstOrCreateMany`, `dictionary(by:)`, `deleteMissing`, and the `delete(where:)` + composed predicate combinators.
- [x] Predicate `Sendable` boxes audited and narrowed. `SendableValue` no longer uses `@unchecked Sendable` over `Any?`; it now stores `(any Sendable)?` and exposes `init<T: Sendable>(_:T?)`, so callers must pass Sendable values. Every public predicate operator and helper that stuffs a value into `SendableValue` (`==`, `!=`, `<`, `<=`, `>`, `>=`, `.in`, `.notIn`, optional-aware nil overloads) carries `Value: Sendable`, and the mutation table's `firstOrCreate`/`firstOrCreateMany`/`upsert`/`upsertMany`/`deleteMissing` follow suit. `SendablePredicate` retains `@unchecked Sendable` (NSPredicate is an NSObject subclass, not Sendable-by-default) but now carries doc commentary explaining why the box is sound: predicates are constructed from format strings and never mutated after handoff. A new `predicateCrossesActorBoundariesSafely` test sends a fully composed predicate through a detached task into `slate.query` to exercise the cross-queue path under strict concurrency.

### Predicate And Sort

- [x] Added `SlatePredicate<Root>` with Slate-native expression enum.
- [x] Added comparison operators for key paths:
  - `==`
  - `!=`
  - `<`
  - `<=`
  - `>`
  - `>=`
- [x] Added predicate composition:
  - `&&`
  - `||`
  - prefix `!`
- [x] Added `SlatePredicate.in`.
- [x] Added `SlatePredicate.notIn`.
- [x] Added `SlatePredicate.isNil` and `SlatePredicate.isNotNil` static helpers.
- [x] Added optional-aware `==` / `!=` overloads for `KeyPath<Root, Value?>`; comparing an optional key path against `nil` rewrites to a SQL `IS NULL` / `IS NOT NULL` predicate.
- [x] Added raw `NSPredicate` escape hatch via `SlatePredicate.predicate`.
- [x] Added `SlateSort<Root>`.
- [x] Added `SlateQueryTable.sort([SlateSort<I>])` and `SlateMutationTable.sort([SlateSort<I>])` for batch sort application.
- [x] Added string-comparison helpers: `SlatePredicate.contains`, `.beginsWith`, `.endsWith`, `.matches` (with `SlateStringOptions` for case- and diacritic-insensitive matching) plus `SlatePredicate.between(_:, _:)` for `ClosedRange`. Each has a non-optional and optional `KeyPath` overload.
- [x] Tests cover string contains/begins/ends with case-insensitive matching, regex MATCHES, and BETWEEN over an in-memory store.

Known predicate limitations:

- [x] Optional `nil` comparisons covered by tests (`\.foo == nil`, `\.foo != nil`, `.isNil(\.foo)`, `.isNotNil(\.foo)`).
- [x] Enum raw-value comparison: `SlateComparisonOperator` now unwraps `RawRepresentable` values (and arrays of `RawRepresentable` for `IN`/`NOT IN`/`BETWEEN`). End-to-end runtime test verifies `\.role == .caregiver` and `.in(\.role, [.patient])` filter Core Data rows correctly.
- [x] Embedded key-path mapping is aligned macro/generator end-to-end. Both sides default to `<property>_<subproperty>` for embedded fields and honor `@SlateAttribute(storageName:)` overrides; both emit the optional-aware separator (`?.` for optional embedded, `.` for non-optional) so the generated `keypathToAttribute` switch matches the immutable keypath shape. Test `macroAndGeneratorAgreeOnEmbeddedKeypathStorageNames` parses the fixture model and asserts every embedded attribute's macro-emitted storage name equals the parser-emitted `NormalizedAttribute.storageName`. End-to-end runtime test `embeddedKeypathPredicateRoutesToFlattenedStorageColumn` inserts two `Patient` rows with different `address.city` / `address.postalCode` values and queries them via `\Patient.address?.city == "Boston"` and `\Patient.address?.postalCode == "10007"` — both predicates round-trip through `keypathToAttribute → NSPredicate → Core Data column` and return the right rows, including the `@SlateAttribute(storageName: "zip")` override.
- [x] Collection predicate (`in` / `notIn`), composition (`&&` / `||` / `!`), and comparison (`<` / `<=` / `>` / `>=`) edge cases now have runtime tests against an in-memory store.

### Generator Model And Parser

- [x] Added normalized schema model:
  - `NormalizedSchema`
  - `NormalizedEntity`
  - `NormalizedAttribute`
  - `NormalizedEmbedded`
  - `NormalizedIndex`
  - `NormalizedUniqueness`
  - `NormalizedRelationship`
  - `GeneratedFile`
  - `GenerationManifest`
- [x] Added SwiftSyntax parser for `@SlateEntity` public structs/classes.
- [x] Parses entity `name:`.
- [x] Parses entity `storageName:`.
- [x] Parses stored `let` attributes.
- [x] Parses `@SlateAttribute(storageName:)`.
- [x] Parses `@SlateAttribute(indexed:)`.
- [x] Parses entity-level `indexes:` declarations for simple key paths.
- [x] Parses entity-level `uniqueness:` declarations for simple key paths.
- [x] Parses simple relationship declarations from `relationships:`.
- [x] Relationship destination accepts either spec-form `Destination.self` OR a string literal `"Destination"`. The string-literal form is an escape hatch for two `@SlateEntity` types that reference each other: Swift's macro expansion treats `Type.self` as a type reference and forms a circular-reference cycle when expanding mutually-referencing macros. The string form keeps the macro arg untyped and allows both entities to expand. The validator/renderer treat both forms identically.
- [x] Parses simple nested embedded structs where both the entity property and nested struct are annotated with `@SlateEmbedded`.
- [x] Flattens optional embedded structs with a `property_has` boolean storage field.
- [x] Flattens embedded attributes using `property_subproperty` storage names by default.
- [x] Supports embedded child `@SlateAttribute(storageName:)` overrides.
- [x] Ignores unannotated nested structs even when an entity property is marked `@SlateEmbedded`.
- [x] Uses deterministic FNV-style diagnostic fingerprint.
- [x] Added `SchemaValidator`.
- [x] Validates duplicate Swift entity names.
- [x] Validates duplicate Core Data entity names.
- [x] Validates duplicate mutable object names.
- [x] Validates duplicate per-entity storage names.
- [x] Validates duplicate per-entity relationship names.
- [x] Validates relationship destination entities.
- [x] Validates relationship inverse names.
- [x] Validates relationship inverse destination points back to the source.
- [x] Validates known relationship kinds and delete rules.
- [x] Validates index storage-name references.
- [x] Validates uniqueness storage-name references.
- [x] CLI commands validate parsed schemas before dumping/generating/checking.

Important generator parser note:

- [x] The initial fingerprint used Swift `hashValue`, which is randomized per process. This broke `generate` followed by `check`. It has been replaced with a stable FNV-style fingerprint.

Known parser limitations:

- [x] Parser now collects structural rejections (`SchemaParseError`) and surfaces them through `parseFiles`/`parseFile`. Tests cover non-public entity, generic entity, `var` stored property, computed persisted property, inherited class entity, external embedded type, and conditional-compilation persisted property rejections.
- [x] Parser issues now carry `SchemaSourceLocation { file, line, column }` populated via SwiftSyntax's `SourceLocationConverter`. `SchemaParseIssue.formatted` renders compiler-style `path:line:col: error: message`; `SchemaParseError.description` joins formatted issues so callers get a usable summary out of the box.
- [x] External embedded structs are now rejected at parse time. `@SlateEmbedded` properties whose nested type cannot be located in the entity emit a `SchemaParseIssue` referencing the missing type name. Unannotated nested types remain silently ignored to preserve the v1 escape hatch.
- [x] Enum raw-value model: nested enums with supported raw types (`String`/`Int16`/`Int32`/`Int64`) are detected by the parser and threaded onto `NormalizedAttribute.enumKind`; `NormalizedEnumKind { typeName, rawType }` is the normalized representation.
- [x] Default-value model: `NormalizedAttribute.defaultExpression` carries the raw Swift expression captured from `@SlateAttribute(default:)`.
- [x] Parses simple uniqueness/index lists.
- [x] Index/uniqueness parsing now uses a typed-AST walk: the `indexes:` and `uniqueness:` arguments are parsed as `ArrayExprSyntax` of `FunctionCallExprSyntax` (`.index(...)` / `.unique(...)`), and the keypath args go through `KeyPathExprSyntax` segment walks rather than substring scraping. Composite key paths and `@SlateAttribute(storageName:)` overrides resolve correctly. Test: `parserHandlesMultiKeyPathIndexAndCommentedKeyPath`.
- [x] Relationship parsing now uses a typed-AST walk: `relationships:` is `ArrayExprSyntax`; each element is a `FunctionCallExprSyntax` with a `MemberAccessExprSyntax` callee, so both implicit-base (`.toOne`) and qualified (`SlateRelationship.toOne`) forms work, and labeled args are read via `LabeledExprListSyntax` instead of substring matching. Test: `parserHandlesQualifiedAndCommentedRelationshipDeclarations` covers qualified form, internal comments, and labeled-int / labeled-bool / labeled-dot extraction.
- [x] Conditional compilation (`#if`) blocks containing stored `let` properties on a `@SlateEntity` are rejected with a `SchemaParseIssue`. Nested `#if` blocks are walked recursively.
- [x] Generic entity rejection is implemented at the parser level.
- [x] Computed persisted property rejection diagnostics are implemented (annotated computed properties trigger a parse issue).

### Generator Rendering

- [x] Added `GeneratedSchemaRenderer`.
- [x] Renders generated mutable `NSManagedObject` classes.
- [x] Renders persistence bridge files.
- [x] Renders generated `SlateSchema` type.
- [x] Renders programmatic `NSManagedObjectModel`.
- [x] Renders attribute metadata.
- [x] Renders relationship metadata.
- [x] Renders `NSRelationshipDescription` declarations.
- [x] Renders inverse relationship assignments when both sides are present.
- [x] Renders mutable `@NSManaged` relationship properties:
  - to-one as optional destination mutable object
  - ordered to-many as `NSOrderedSet?`
  - unordered to-many as `Set<DestinationMutable>?`
- [x] Renders `SlateRelationshipHydratingMutableObject` bridge conformance.
- [x] Renders `slateObject(hydrating:)` bridge conversion that hydrates only requested direct relationships.
- [x] Renders table registrations.
- [x] Renders generation manifest.
- [x] Renders embedded flattened storage columns.
- [x] Renders embedded provider computed properties that reconstruct nested embedded values.
- [x] Renders Core Data uniqueness constraints.
- [x] Renders Core Data fetch indexes with `NSFetchIndexDescription`.
- [x] Added tests for:
  - basic schema parsing
  - file writing/checking/cleaning
  - relationship model-builder output
  - embedded parsing
  - embedded rendering

Known renderer limitations:

- [x] Generated output is now compile-tested via the in-tree fixture targets `SlateFixturePatientModels` (model module with `@SlateEntity` declarations including a to-one + to-many relationship pair, an embedded struct with a storage-name override, and an enum attribute with a default) and `SlateFixturePatientPersistence` (committed generated output). Both targets are built by every `swift build`, so any regression in the generator's emission that breaks cross-module compilation is caught at CI. The new test `fixturePersistenceFilesRoundTrip` re-runs the generator over the model sources and compares each rendered file against the committed copy — failing the test if the committed files have drifted from what the generator would produce now.
- [x] Embedded bridge code can rely on `@SlateEmbedded` nested structs receiving a public memberwise initializer.
- [x] Enum storage uses the parsed raw type (`String`/`Int16`/`Int32`/`Int64`) for the Core Data attribute and a primitive-value-backed typed accessor on the mutable class. Inline `.case` defaults flow through to the Core Data `defaultValue` as `EntityName.EnumType.case.rawValue`.
- [x] Optional numeric/bool/decimal attributes now use the same primitive-value bridge pattern as enums: an explicit accessor reads `(primitiveValue(forKey:) as? NSNumber)?.<accessor>` and writes `setPrimitiveValue(newValue.map { NSNumber(value: $0) }, forKey:)`. `Decimal?` uses `NSDecimalNumber`. Non-optional numeric/bool stays on `@NSManaged` because Core Data bridges those scalars correctly.
- [x] Primitive default values (`String`, `Int`, `Bool`, `Double`/numeric literals) are now emitted as `defaultValue =` lines on the generated `NSAttributeDescription`. Non-literal expressions (`.unknown`, `Date.distantPast`, etc.) are intentionally skipped until enum/named-default support lands.
- [x] Uniqueness constraints are rendered.
- [x] Fetch indexes are rendered for parsed entity indexes.
- [x] Index order now flows through to Core Data: each `NSFetchIndexElementDescription` has its `isAscending` set to `false` for descending indexes; ascending defaults are left untouched. Each element is declared as a separate `let` so the property can be configured before being collected into the parent index description.
- [x] Relationship `optional`, `minCount`, and `maxCount` metadata is now parsed (`NormalizedRelationship.optional/minCount/maxCount`) and rendered onto `NSRelationshipDescription`. To-one relationships derive `minCount` from `optional` (`0` if optional, `1` otherwise) and force `maxCount = 1`. To-many relationships use parsed `minCount`/`maxCount` (defaulting to `0`/`0`).
- [x] Relationship immutable accessors are emitted by macros.
- [x] Relationship accessors can be hydrated by the runtime when requested.
- [x] Generated relationship hydration is now compile-tested. The fixture's Patient ↔ PatientNote relationship pair drives `SlateRelationshipHydratingMutableObject.slateObject(hydrating:)` emission for both `toMany(ordered: true)` (uses `(notes?.array as? [DatabasePatientNote])?.map(\.slateObject)`) and `toOne` (uses `patient?.slateObject`), and the persistence module compiles end-to-end against the runtime.

### Generator CLI

- [x] Added `dump-schema`.
- [x] Added `generate`.
- [x] Added `check`.
- [x] Added `clean`.
- [x] `generate` writes generated files and manifest.
- [x] `check` compares rendered files against disk.
- [x] `clean` removes only manifest-owned files.

Known CLI limitations:

- [x] CLI option names and layout aligned with the final design spec. The `generate` / `check` / `dump-schema` / `clean` subcommands now share three option groups: `InputOptions` (`--input`/repeatable, `--exclude`/repeatable, plus a positional fallback for ergonomics), `SchemaIdentityOptions` (`--schema-name`, `--model-module`, `--runtime-module`), and `OutputOptions` (`--output-mutable`, `--output-bridge`, `--output-schema`, `--output-manifest`, plus the legacy `--output` collapse-to-single-dir form, plus `--create-output-dirs/--no-create-output-dirs`). `generate` adds `--dry-run` and `--prune`; `check` adds `--allow-missing-output`; `clean` adds `--dry-run`. Behind the CLI, `GeneratedFile` carries a `GeneratedFileKind` (mutable/bridge/schema/manifest) and `GeneratedOutputLayout` routes each kind to its own directory. Test `writerRoutesGeneratedFilesByKind` exercises the per-kind routing end-to-end (write/staleFiles/clean across distinct dirs).
- [x] Manifest path customization: `generate`/`check`/`clean` accept `--output-manifest <path>` (with the legacy `--manifest` no longer needed since `OutputOptions.outputManifest` is the single source of truth). When omitted the manifest stays at `<output-schema>/SlateGenerationManifest.json`. The writer creates intermediate directories when the manifest path is outside the output directory and `clean` removes the manifest from its custom location. Tests cover round-trip plus intermediate-directory creation; CLI verified end-to-end.
- [ ] No stale check for extra generated files missing from current manifest beyond manifest-owned clean behavior.
- [ ] No rich diagnostic formatting.
- [ ] `--config <path>` (YAML config file) and `--diagnostics-format <human|json>` from the design spec are not yet implemented; the option groups are sized to add them without churning callers.
- [ ] `--file-header`, `--additional-import`, `--immutable-additional-import`, `--schema-additional-import`, `--emit-test-fixtures`, `--emit-debug-comments` are listed in the design spec but not yet wired into the renderer; deferring until there's a concrete consumer.

## Recommended Next Steps

### 1. Compile-Test Generated Output

- [x] Created `SlateFixturePatientModels` (model module with `@SlateEntity` declarations: Patient with attributes, embedded Address struct, Status enum + default, ordered to-many relationship to PatientNote; PatientNote with to-one relationship back to Patient) and `SlateFixturePatientPersistence` (committed generator output) targets in `Sources/`. Both build with every `swift build`.
- [x] Generator round-trip test (`fixturePersistenceFilesRoundTrip`) re-runs the parser+renderer over the model files and asserts each rendered file matches the committed copy in `Sources/SlateFixturePatientPersistence/`.

Issues discovered and resolved during fixture work:

- `@SlateEmbedded` cannot be both `@attached(member)` (on the embedded struct type) and `@attached(peer)` (on the entity property) under Swift's macro role validation — see "Finish Embedded Support" below for the resolution.
- The generator's hydrating initializer arguments were emitted in the wrong order vs. the macro-emitted memberwise init when both direct attributes and embedded properties existed. The macro now reorders parameters to emit direct attributes before embedded properties, matching the renderer.
- `@SlateAttribute(default:)` is typed as `Any?` so leading-dot enum cases (`.active`) don't type-check at the macro arg site; the renderer now also accepts type-qualified forms (`Patient.Status.active`) and routes them through the same default-value emission paths.
- Two `@SlateEntity` types referencing each other via `Destination.self` form a Swift macro circular-reference cycle. Added a string-literal destination escape hatch (`"PatientNote"`) at both the parser and macro levels, then used it in the fixture's Patient ↔ PatientNote pair to make compile-testing relationship hydration possible.

Future fixture coverage to consider:

- Self-referential relationships (e.g., a tree-shaped entity with a parent/child pair pointing at itself). Same string-destination escape hatch should cover this.
- Indexes and uniqueness in fixtures: keypath-based `indexes:` / `uniqueness:` arguments hit a Swift `~Copyable` / circular-reference problem when the keypath roots back to the entity being expanded; design needs review before this can be compile-tested.

### 2. Add Validation Layer

The parser now rejects the most common structural issues at parse time via `SchemaParseError`, and `SchemaValidator` covers cross-entity invariants.

Checklist:

- [x] Add `SchemaValidator`.
- [x] Reject generic entities.
- [x] Reject non-public entities.
- [x] Reject inherited entity classes. Parser walks `ClassDeclSyntax.inheritanceClause` and uses an allowlist of well-known protocols (`Sendable`, `Equatable`, `Hashable`, `Codable`, `Identifiable`, ...) to flag any other inherited type as a likely base class.
- [x] Reject computed persisted properties (annotated with `@SlateAttribute` / `@SlateEmbedded`).
- [x] Reject `var` persisted properties.
- [x] Reject unsupported attribute types (`SchemaValidator` already enforced a fixed `supportedStorageTypes` list; covered indirectly by parser type mapping).
- [x] Reject external embedded types until supported (parser-level `SchemaParseIssue` when nested type is missing).
- [x] Validate relationship destinations/inverses.
- [x] Validate duplicate storage names.
- [x] Validate duplicate entity names/mutable names.
- [x] Validate conditional compilation inside persisted declarations (parser walks `IfConfigDeclSyntax` and rejects).

### 3. Finish Embedded Support

Checklist:

- [x] ~~Generate public embedded struct initializers through `@SlateEmbedded` member macro.~~ Reverted: Swift's macro role validation rejects `@attached(member)` on a property attachment site, so the same `@SlateEmbedded` macro can't be both peer-on-property and member-on-struct. Authors must declare a public memberwise initializer manually for embedded structs; the parser still uses `@SlateEmbedded` on the nested struct as a marker.
- [x] Decided: `@SlateEmbedded` is a property annotation only (and a marker on the nested struct's type for parser identification). It is rejected on attributes nested inside another embedded struct — tested via `parserRejectsNestedSlateEmbedded`.
- [x] Align macro key-path mapping for embedded paths with generator flattened storage names. Macro now emits `case \Entity.embed?.field` (optional) or `case \Entity.embed.field` (non-optional) cases that match the generator's `embed_field` storage names and honor `@SlateAttribute(storageName:)` overrides.
- [x] Added parser tests for non-optional embedded structs: confirm `optional == false` and that `presenceStorageName` is `nil` (no `_has` flag is generated).
- [x] Added parser tests for embedded numeric/bool fields covering `Int64`, `Double`, `Bool`, and optional `Int16` flattened storage types and storage names.

### 4. Finish Enum And Default Support

Checklist:

- [x] Parse nested enum declarations and raw types. Parser walks `EnumDeclSyntax` members of the entity, captures `name → rawType` for raw-value enums whose first inherited type is `String`/`Int16`/`Int32`/`Int64`, and threads `enumKind: NormalizedEnumKind` onto matching `NormalizedAttribute`s. The attribute's `storageType` is overridden to the enum raw type's storage (string/integer16/integer32/integer64).
- [x] Parse imported enum references via two complementary mechanisms (option A + option B from the design discussion):
  - **A — cross-file enum index.** `parseFiles(at:)` is now a two-pass walk. The first pass collects every top-level raw-value `enum` from every input file into a `CrossFileEnumIndex { entries, collisions }`. During attribute normalization, after entity-local nested enums fall through, the parser looks up the *leaf* of the unwrapped Swift type (`SharedTypes.Status` → `Status`) in the index. Resolution priority: explicit override > entity-local nested > cross-file index. Tests cover sibling-file lookup and qualified type names.
  - **B — `@SlateAttribute(enumRawType: <T>.self)` annotation override.** The `SlateAttribute` macro decl gained an `enumRawType: Any.Type? = nil` parameter, and the parser reads it as a `MemberAccessExprSyntax` targeting `String.self` / `Int16.self` / `Int32.self` / `Int64.self`. The override beats both the nested lookup and the cross-file index, so users can annotate attributes that reference enums in precompiled modules the generator can't see, or disambiguate when the same name appears in multiple input files.
  - **Collision diagnostic.** When two input files declare a top-level enum of the same name, the index marks it as a collision. Attributes that reference a collided name emit a `SchemaParseIssue` with the suggestion to use `@SlateAttribute(enumRawType: <RawType>.self)` to disambiguate. An override on such an attribute resolves cleanly without raising the issue.
  - **Out of scope (v1):** enums nested inside a non-entity top-level declaration (e.g., `struct AppConfig { enum Mode { ... } }`) are not in the cross-file index — users either move the enum to file root or use the override. Genuinely external precompiled modules also require the override.
- [x] Parse `@SlateAttribute(default:)` raw expression.
- [x] Store default metadata in normalized schema (`NormalizedAttribute.defaultExpression`).
- [x] Render Core Data defaults where safe (string/numeric/bool literals); non-literal expressions are skipped.
- [x] Render bridge conversion from raw storage to enum. The renderer no longer emits `@NSManaged` for enum-typed attributes; instead it generates a typed accessor that calls `willAccessValue/didAccessValue` + `primitiveValue(forKey:)` for reads and `willChangeValue/didChangeValue` + `setPrimitiveValue(_:forKey:)` for writes. Optional enums fall back to `nil`; non-optional enums fall back to the declared default expression resolved as `EntityName.EnumType.case`.
- [x] Render enum default expressions: leading-dot defaults like `.unknown` are emitted onto the Core Data `NSAttributeDescription` as `EntityName.EnumType.case.rawValue` so the persisted column starts at the correct raw value. Type-qualified expressions (`Patient.Status.active`) are accepted equivalently — the renderer detects either form and routes them through the same hydration / Core Data default emission paths. This matters because `@SlateAttribute(default:)` is typed as `Any?` so leading-dot shorthand (`.active`) doesn't type-check at the macro arg site; users must write the full-qualified form.
- [x] Predicate value handling unwraps `RawRepresentable` values (and their array projections used by `IN`/`NOT IN`/`BETWEEN`) so `\Entity.field == .case` predicates compare against the persisted raw value rather than the enum case object.
- [x] Throw `SlateError.invalidStoredValue` where no default is available. `SlateError.invalidStoredValue(entity:property:valueDescription:)` now matches the design-spec signature, and the renderer's `slateObject(hydrating:)` body emits per-attribute pre-flight statements: non-optional enums WITH a default resolve via `(rawValue).flatMap(Enum.init(rawValue:)) ?? Enum.default`; non-optional enums WITHOUT a default emit two `guard` statements that throw `SlateError.invalidStoredValue` for both the missing-raw and unmappable-raw cases. Generated entities are routed through this throwing path because they conform to `SlateRelationshipHydratingMutableObject`. Runtime cache invalidation was tightened so that mutated objects whose conversion throws have their cached entries removed (and restored on save failure) — this guarantees the next read forces a fresh convert and surfaces the error rather than returning a stale cached value.

### 5. Runtime Relationship Hydration

Checklist:

- [x] Extend macro to generate optional relationship accessors.
- [x] Add immutable-side key-path-to-relationship mapping through `SlateKeypathRelationshipProviding`.
- [x] Thread relationship key-path mapping into runtime query APIs.
- [x] Add query API relationship lists.
- [x] Hydrate shallow relationships during conversion for hydrating mutable objects.
- [x] Preserve unresolved/unrequested relationships as `nil`.
- [x] Add runtime test for to-one hydration.
- [x] Add runtime tests for unordered to-many and ordered to-many hydration.
- [x] Compile-tested generated relationship hydration output via the `SlateFixturePatient*` fixture targets — the persistence module's bridge files exercise both kinds of relationship hydration expressions emitted by `slateObject(hydrating:)` and the whole module compiles as part of `swift build`.

### 6. Runtime Cache And Save Rollback

Checklist:

- [x] Implement immutable object cache (`SlateObjectCache` lock-protected class hung off `SlateStoreOwner`).
- [x] Pre-save cache hydration: `Slate.mutate` converts inserted/updated managed objects to immutable values and applies them to the cache before `save()`, so FRC-driven conversions during save propagation see hydrated values.
- [x] Save undo set / rollback cache on failed save: the runtime captures `SlateObjectCache.snapshot(...)` before applying pre-save updates and calls `SlateObjectCache.restore(...)` plus `writerContext.rollback()` if `save()` throws.
- [x] Remove deleted object IDs after successful delete (now applied as part of the pre-save `apply(setting:removing:)` call).
- [x] Added cache tests:
  - cache hydrated on insert (pre-save)
  - cache updated on update (replaces cached value rather than removing)
  - cache clears deleted entries
  - cache untouched on user error
  - cache restored on direct save-failure path (snapshot/apply/restore round trip)
  - end-to-end: a real Core Data save validation failure restores the cache to the pre-mutation state and leaves durable rows intact
- [x] Broader cache matrix tests now in place: `cacheConcurrentReadersReuseEntries` fans out 32 parallel `slate.many(...)` reads and asserts the cache count and per-ID identity (by name) stay stable; `cacheEvictsBatchDeletedIDs` warms the cache, runs `slate.batchDelete(... where: ...)`, and confirms only the deleted IDs leave the cache while surviving IDs remain; `cacheSurvivesAcrossWriterSaves` simulates the FRC-driven re-emission pattern by running successive writer saves that touch *different* rows and verifies that already-cached rows stay put across each save.

### 7. Streams

Checklist:

- [x] Add `SlateStream<Value>` (`@MainActor`, `@Observable`).
- [x] Add `SlateBackgroundStream<Value>` (`@SlateStreamActor`, `@Observable`).
- [x] Add `SlateStreamActor`.
- [x] Implement FRC-backed stream context (`SlateStreamCore`).
- [x] Add `valuesAsync` / `valueAsync` `AsyncThrowingStream` adapters.
- [x] Add cancellation lifecycle: removes writer-save observer, detaches FRC delegate, finishes async continuations.
- [x] Add tests for initial load, insert, update, delete, predicate filtering, cancel, async adapter, and background-stream isolation.

Important streams design note:

- [x] Initial implementation tried to rely solely on `NSFetchedResultsControllerDelegate` callbacks driven by `mergeChanges(fromContextDidSave:)`. With in-memory stores (and possibly some on-disk configurations), `mergeChanges` on inserts did not surface registered objects to the FRC. The concrete approach now performs a fresh `frc.performFetch()` after each writer save to guarantee correct propagation. This is heavier than diffed FRC events but reliable; future iterations can move back to delta-based emissions once a more thorough Core Data merge story is in place.

### 8. Reader/Writer Access Gate

Checklist:

- [x] Replace polling Task.sleep gate with continuation-based FIFO queue.
- [x] Honor write priority so reads queued after a writer wait behind it.
- [x] Cancel queued waiters via `withTaskCancellationHandler` and resume them with `CancellationError`.
- [x] Add tests for concurrent readers, exclusive writers, write-waits-for-active-reads, queued-write-priority, and cancellation cleanup.

## Current Test Count

At the time this file was last updated:

- [x] `swift test` reports 121 Swift Testing tests passing across 7 suites:
  - `SlateAccessGateTests` (5)
  - `SlateGeneratorTests` (50)  ← +1 (macro and generator agree on embedded keypath storage names)
  - `SlateObjectCacheTests` (10)
  - `SlatePredicateTests` (10)
  - `SlateRuntimeTests` (26)    ← +1 (embedded keypath predicate routes to flattened storage column, end-to-end through the in-tree fixture)
  - `SlateSchemaMacroTests` (10) ← +5 (non-public entity, generic entity, inherited class, annotated computed property, conditional persisted property)
  - `SlateStreamTests` (10)
