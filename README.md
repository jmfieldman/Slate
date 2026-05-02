# Slate 3

A Swift Core Data framework that gives you immutable, `Sendable` data
models, a single-writer / multi-reader transaction model, and FRC-backed
streams — without ever touching a `.xcdatamodeld` file.

Slate 3 is an evolution of the original
[Slate](https://github.com/jmfieldman/Slate). The design goals are the
same — thread-safe immutable views over a Core Data store with a clean
read/write split — but the surface has been rewritten for Swift's
structured concurrency, and the schema authoring story takes its cues
from the macro ergonomics that SwiftData popularized.

If you're coming from Slate 2, expect:

- `async`/`await` everywhere instead of `Combine` + completion handlers.
- Schema declared in Swift with `@SlateEntity`, not in an Xcode editor.
- A source-based code generator that reads your annotated structs and
  emits both the `NSManagedObject` subclasses and the bridge code that
  connects them to the immutable models.
- `Observable` streams — not `Publisher`s.
- Strict concurrency. Every public type is `Sendable`. Every
  immutable model is `Sendable` by construction.

## At a glance

```swift
// 1. Define the immutable model in your shared model module.
@SlateEntity
public struct Patient {
    public let patientId: String
    public let firstName: String
    public let lastName: String
    public let age: Int?
}

// 2. Run `slate-generator generate` to produce the Core Data class
//    (DatabasePatient), the persistence bridge, and the schema.

// 3. Spin up a store and use it.
let slate = Slate<MyAppSchema>(storeURL: url)
try await slate.configure()

try await slate.mutate { context in
    let row = context.create(DatabasePatient.self)
    row.patientId = "P-001"
    row.firstName = "Ada"
    row.lastName = "Lovelace"
    row.age = 36
}

let adults = try await slate.many(
    Patient.self,
    where: \.age >= 18,
    sort: [\.lastName]
)
```

The shared model module sees only `Patient` (immutable, `Sendable`).
The persistence module sees `DatabasePatient` (mutable, `@NSManaged`).
Slate brokers between them.

## Installation

Slate 3 is a SwiftPM package. Add it as a dependency:

```swift
.package(url: "https://github.com/jmfieldman/Slate3", from: "<version>")
```

Then wire two products into the appropriate targets:

```swift
.target(
    name: "MyAppModels",
    dependencies: [
        .product(name: "SlateSchema", package: "Slate3"),
    ]
),
.target(
    name: "MyAppPersistence",
    dependencies: [
        "MyAppModels",
        .product(name: "Slate", package: "Slate3"),
        .product(name: "SlateSchema", package: "Slate3"),
    ]
),
```

`SlateSchema` is the lightweight macro / annotation module — it holds the
public protocols, metadata types, and the `@SlateEntity` /
`@SlateAttribute` / `@SlateEmbedded` macro declarations. The model
module imports it. `Slate` is the runtime — it holds the
`Slate<Schema>` actor, the query/mutate APIs, and streams. The
persistence module imports it. Apps usually import only the model
module and call into a higher-level repository wrapper that hides the
persistence module.

## Defining a schema

Schemas live in your model module as plain `public` Swift types
annotated with `@SlateEntity`. The macro generates the immutable
scaffolding — a `slateID`, a public memberwise initializer, and
key-path mappings — and conforms the type to `SlateObject`,
`SlateKeypathAttributeProviding`, and `SlateKeypathRelationshipProviding`.

### Attributes

```swift
@SlateEntity
public struct Patient {
    public let patientId: String
    public let firstName: String
    public let lastName: String
    public let age: Int?
}
```

Rules of the road:

- Stored properties must be `let`. The macro emits a diagnostic for
  `var` so you find out at the call site, not at runtime.
- Optional scalars (`Int?`, `Bool?`, `Double?`, `Decimal?`) work — the
  generator emits a `primitiveValue`-backed accessor on the
  `NSManagedObject` to bridge `NSNumber?` correctly. `@NSManaged Bool?`
  on a Swift scalar does not.
- `@SlateAttribute(storageName: "yearsOld")` overrides the Core Data
  column. Useful for renames without breaking your Swift API.
- `@SlateAttribute(default: ...)` provides a default expression.
  Literals (strings, numbers, bools) flow through to the Core Data
  attribute description; enum cases are reflected as the enum's raw
  value.

### Embedded structs

`@SlateEmbedded` flattens a value type into columns on the owning
entity:

```swift
@SlateEntity
public struct Patient {
    public let patientId: String

    @SlateEmbedded
    public let address: Address?

    @SlateEmbedded
    public struct Address: Sendable, Equatable {
        public let line1: String?
        public let city: String?
        @SlateAttribute(storageName: "zip")
        public let postalCode: String?

        // Until Swift macros learn to be both peer-on-property and
        // member-on-type at once, write the public init by hand.
        public init(line1: String?, city: String?, postalCode: String?) {
            self.line1 = line1
            self.city = city
            self.postalCode = postalCode
        }
    }
}
```

Storage naming defaults to `<property>_<subproperty>` (so
`address.line1` becomes the `address_line1` column), and an optional
embedded struct gets a `<property>_has` boolean to track presence. You
can override any subfield with `@SlateAttribute(storageName:)`.

`@SlateEmbedded` is allowed only on entity-level properties and on the
embedded struct's type itself. Annotating a field _inside_ an embedded
struct fails the parser — embedded structs are flat, not recursive.

### Enums

Nested raw-value enums are first-class. The parser sees
`enum Status: String { ... }` declared inside the entity and threads
the raw type onto the attribute:

```swift
@SlateEntity
public struct Patient {
    public enum Status: String, Sendable {
        case active
        case archived
    }

    @SlateAttribute(default: Patient.Status.active)
    public let status: Status
}
```

Reading a row whose stored raw value no longer maps to a case behaves
like this: a non-optional enum with a default falls back silently; an
enum without a default throws `SlateError.invalidStoredValue(entity:
property: valueDescription:)` from the conversion path. The cache
invalidates the failing row so the next read calls `convert` again —
no stale data masks the error.

(Heads-up: `@SlateAttribute(default:)` is typed as `Any?`, so the Swift
type checker can't use leading-dot shorthand. Write the enum case
type-qualified: `default: Patient.Status.active`.)

### Indexes and uniqueness

Indexes and uniqueness constraints are declared with the freestanding
`#Index` and `#Unique` macros _inside_ the entity body:

```swift
@SlateEntity
public struct Patient {
    #Index<Patient>([\.patientId])
    #Index<Patient>([\.lastName, \.firstName])
    #Index<Patient>([\.updatedAt], order: .descending)
    #Unique<Patient>([\.patientId])

    public let patientId: String
    public let firstName: String
    public let lastName: String
    public let updatedAt: Date
}
```

Each `[\.foo, \.bar]` array argument is **one** index (or uniqueness
constraint). A single-key-path array is a single-attribute index; a
multi-key-path array is a composite. You can pass several arrays to
the same `#Index`/`#Unique` call when they share the same `order:`,
or split them across multiple calls when they don't:

```swift
#Index<Patient>([\.lastName], [\.firstName])               // two indexes, ascending
#Index<Patient>([\.updatedAt], order: .descending)         // one descending index
#Unique<Patient>([\.patientId])                            // single-attribute uniqueness
#Unique<Person>([\.givenName, \.familyName])               // composite uniqueness
```

The macros themselves expand to nothing — they're pure markers. The
offline generator parses your source, harvests the metadata, and emits
indexes onto `NSEntityDescription.indexes` and uniqueness onto
`uniquenessConstraints`. Uniqueness is _also_ surfaced to the runtime,
where it gates `upsert(_:_:)` — you can't upsert by a key that isn't
in a single-attribute uniqueness constraint, because that operation
has no defined semantics on an unconstrained column.

### Relationships

Relationships are declared in the `@SlateEntity` argument list, not as
stored properties:

```swift
@SlateEntity(
    relationships: [
        .toMany("notes", "PatientNote", inverse: "patient", deleteRule: .cascade, ordered: true),
    ]
)
public struct Patient { ... }

@SlateEntity(
    relationships: [
        .toOne("patient", "Patient", inverse: "notes", deleteRule: .nullify, optional: false),
    ]
)
public struct PatientNote {
    public let noteId: String
    public let body: String
}
```

The destination accepts either `Destination.self` (the spec form) or a
string literal (`"PatientNote"`). The string form is the escape hatch
for two `@SlateEntity` types that reference each other — Swift's
macro expansion treats `Type.self` as a real type reference and
forms a circular-reference cycle when resolving mutually-referencing
macros. The string form keeps both ends typeless at the macro arg site
and lets both entities expand. The validator and renderer treat the
two forms identically.

The macro emits immutable accessors for relationships:

- `to-one` → `Destination?`
- `to-many` → `[Destination]?` (ordered or unordered — `[]?` either way,
  because requiring a `Hashable` immutable model just to support
  `Set<Destination>` would force a heavy conformance on every entity)

Relationships are `nil` by default on a fetched immutable model. You
have to ask for them explicitly — see "Querying" below.

## Running the generator

`slate-generator` reads your annotated source, validates the schema,
and writes the persistence module's source files.

```bash
swift run slate-generator generate \
  --input Sources/MyAppModels \
  --output-mutable Sources/MyAppPersistence/Generated/Mutable \
  --output-bridge Sources/MyAppPersistence/Generated/Bridge \
  --output-schema Sources/MyAppPersistence/Generated/Schema \
  --schema-name MyAppSchema \
  --model-module MyAppModels \
  --runtime-module MyAppPersistence
```

What you get out:

| Kind     | Per entity                     | What it is                                                                                                                              |
| -------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Mutable  | `Database<Entity>.swift`       | `final class DatabaseEntity: NSManagedObject` with `@NSManaged` properties (or primitive-value accessors for optional scalars / enums). |
| Bridge   | `<Entity>+SlateBridge.swift`   | The `ManagedPropertyProviding` extension, `SlateMutableObject` conformance, and `slateObject(hydrating:)` for relationship hydration.   |
| Schema   | `<SchemaName>.swift`           | The `SlateSchema` enum: entity metadata, programmatic `NSManagedObjectModel` builder, and `registerTables`.                             |
| Manifest | `SlateGenerationManifest.json` | A list of generated files. Used by `clean` and `check`.                                                                                 |

Subcommands:

- `generate` — write the files, with optional `--dry-run` and
  `--prune` (delete files no longer in the manifest).
- `check` — exit non-zero if the on-disk files differ from what
  generation would produce now. Wire this into CI to catch drift.
- `clean` — remove every file recorded in the manifest plus the
  manifest itself.
- `dump-schema` — print the normalized schema model as JSON. Useful
  for debugging the parser.

The `--output` form (single directory for all kinds) is also accepted
when you don't need separate target locations.

## Creating a Slate instance

`Slate<Schema>` is the runtime entry point. The schema you pass is the
generated enum (`MyAppSchema` from the example above):

```swift
let slate = Slate<MyAppSchema>(
    storeURL: URL(fileURLWithPath: "/path/to/store.sqlite")
)
try await slate.configure()
```

The `storeURL: nil` form opens an in-memory store, which is ideal for
tests:

```swift
let slate = Slate<MyAppSchema>(storeURL: nil, storeType: NSInMemoryStoreType)
try await slate.configure()
```

A few details worth knowing:

- Multiple `Slate<Schema>` handles for the same on-disk URL share an
  internal owner — there's exactly one Core Data stack per file URL,
  no matter how many handles you spin up.
- An incompatible store on disk (schema fingerprint mismatch on a
  SQLite file) is wiped and recreated. Slate is designed for the case
  where the store is a disposable cache, not the system of record. If
  you need migrations, this is the wrong tool.
- `await slate.close()` drains in-flight writes, severs the access
  gate, and rejects subsequent calls with `SlateError.closed`. After
  close, the handle is dead — make a new one if you need to reopen.

## Querying

Every read goes through a `SlateQueryContext`. The simplest way to use
it is the direct convenience API on `Slate`:

```swift
// Optional first row
let patient = try await slate.one(
    Patient.self,
    where: \.patientId == "P-001"
)

// Filtered + sorted (ascending-only key paths inferred from `Patient.self`).
let adults = try await slate.many(
    Patient.self,
    where: \.age >= 18,
    sort: [\.lastName, \.firstName],
    limit: 50
)

// Mixed direction — `.asc` / `.desc` factories on `SlateSort` resolve
// against the inferred element type, so the leading-dot shorthand
// works without naming the type.
let recent = try await slate.many(
    Patient.self,
    sort: [.desc(\.createdAt), .asc(\.lastName)]
)

// Just the count
let total = try await slate.count(Patient.self, where: \.age >= 18)
```

For composed work that should run inside a single read transaction,
drop down to `query`:

```swift
let summary = try await slate.query { context in
    let active = try context[Patient.self]
        .where(\.status == .active)
        .count()
    let archived = try context[Patient.self]
        .where(\.status == .archived)
        .count()
    return Summary(active: active, archived: archived)
}
```

Every read inside `query { ... }` operates on the same snapshot. Reads
run concurrently; writers wait their turn behind active reads.

### Predicates

Predicates compose with operators on key paths:

```swift
let predicate: SlatePredicate<Patient> =
    (\.lastName == "Lovelace" && \.firstName == "Ada") ||
    \.patientId == "P-001"
```

The full kit:

- Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=` (with optional-aware
  `nil` overloads — `\.middleName == nil` becomes `IS NULL`).
- Composition: `&&`, `||`, prefix `!`.
- Collections: `.in(\.role, [.patient, .clinician])`, `.notIn(...)`.
- Strings: `.contains`, `.beginsWith`, `.endsWith`, `.matches`, plus a
  `SlateStringOptions` for case-insensitive / diacritic-insensitive
  matching.
- Ranges: `.between(\.age, 18 ... 65)`.
- Null checks: `.isNil(\.middleName)`, `.isNotNil(\.middleName)`.
- Raw escape hatch: `.predicate(NSPredicate(...))`.

Enum raw values unwrap automatically: `\.role == .caregiver` compares
against the persisted raw value, not the boxed enum case.

### Hydrating relationships

Fetched immutable models have `nil` relationships unless you ask:

```swift
let patient = try await slate.one(
    Patient.self,
    where: \.patientId == "P-001",
    relationships: [\.notes]
)
// patient?.notes is non-nil and contains the related PatientNote rows.
```

Hydration is shallow. Asking for `\.notes` does not also hydrate
`note.author` — that needs an API that supports nested relationship
paths, which is on the roadmap, not in v1. Many-to-many and
self-referential relationships are fine because nothing is
deep-resolved by default.

## Mutating

Writes happen inside `mutate`, which acquires the writer barrier and
blocks until the closure returns. Inside the closure you have a
`SlateMutationContext` and access to mutable rows:

```swift
try await slate.mutate { context in
    let row = context.create(DatabasePatient.self)
    row.patientId = "P-002"
    row.firstName = "Grace"
    row.lastName = "Hopper"
    row.age = 79
}
```

`context.create` returns the `NSManagedObject` subclass for the entity.
This is the same class you'd see if you had hand-written Core Data —
`@NSManaged` properties for typed values, regular Core Data
relationship semantics, etc. You can mutate it directly. When the
closure returns successfully, Slate saves; if you throw, the context
rolls back (and the immutable cache is restored to its pre-mutation
state).

A return value from `mutate` flows out — but it has to be `Sendable`,
because you're handing it across the writer boundary back to the
caller. Convert before returning:

```swift
let saved: Patient = try await slate.mutate { context in
    let row = context.create(DatabasePatient.self)
    row.patientId = "P-003"
    row.firstName = "Margaret"
    row.lastName = "Hamilton"
    return context.immutable(row)
}
```

`context.immutable(row)` is the explicit conversion helper. The
generic `mutate<Output: Sendable>` shape can't infer the conversion
for you, so be explicit.

### Mutation tables

`context[DatabaseFoo.self]` returns a `SlateMutationTable` with a few
patterns that come up over and over again:

```swift
try await slate.mutate { context in
    // Insert if absent, otherwise return the existing row.
    let p = try context[DatabasePatient.self]
        .firstOrCreate(\.patientId, "P-001")
    p.firstName = "Ada"

    // Bulk variant — pass keys, get a dictionary back.
    let map = try context[DatabasePatient.self]
        .firstOrCreateMany(\.patientId, ["P-001", "P-002", "P-003"])

    // Upsert by a uniqueness-constrained key (validated against the
    // schema's declared uniqueness constraints).
    _ = try context[DatabasePatient.self]
        .upsert(\.patientId, "P-004")

    // Sync semantics: delete rows whose key isn't in `keeping`.
    _ = try context[DatabasePatient.self]
        .deleteMissing(key: \.patientId, keeping: ["P-001", "P-002"])

    // Snapshot existing rows by key.
    let byID = try context[DatabasePatient.self]
        .dictionary(by: \.patientId)

    // Predicate-driven delete.
    _ = try context[DatabasePatient.self]
        .delete(where: \.status == .archived)
}
```

`upsert` rejects keys that aren't in a single-attribute uniqueness
constraint — `SlateError.upsertKeyNotUnique(entity:attribute:)` —
because an unconstrained upsert can silently match (or miss) multiple
rows.

### Batch deletes

For maintenance work that shouldn't go through the object graph, use
`slate.batchDelete`:

```swift
try await slate.batchDelete(
    Patient.self,
    where: .in(\.status, [.archived])
)
```

This is a `NSBatchDeleteRequest` on a SQLite store and a fetch +
per-row delete fallback on in-memory stores. Both paths evict the
deleted IDs from the immutable cache and broadcast to live streams so
they re-fetch.

`batchDelete` cannot be called from inside a `mutate` block — it's a
top-level operation, not an object-graph edit. It also bypasses Core
Data validation and delete rules, by design. If you need cascading
edits, do them inside a `mutate` block.

## Streaming

`SlateStream<Value>` is an `@Observable`, MainActor-bound view of a
fetched results controller. The values are immutable models, the
property updates are observable from any SwiftUI / `@Observable` host:

```swift
@MainActor
final class PatientListModel {
    let patients: SlateStream<Patient>

    init(slate: Slate<MyAppSchema>) {
        self.patients = slate.stream(
            Patient.self,
            sort: [\.lastName]
        )
    }
}
```

In SwiftUI:

```swift
struct PatientList: View {
    let model: PatientListModel
    var body: some View {
        List(model.patients.values, id: \.patientId) { patient in
            Text(patient.lastName)
        }
    }
}
```

For background work — e.g., a syncing pipeline that wants change
notifications without bouncing through the main actor —
`slate.streamBackground(...)` returns a `SlateBackgroundStream`
isolated to the global `SlateStreamActor`.

If you'd rather drive things off `AsyncSequence`, every stream exposes
`valuesAsync` and `valueAsync`:

```swift
for try await snapshot in slate.stream(Patient.self).valuesAsync {
    // snapshot is [Patient]
}
```

Streams own their FRC. `cancel()` removes the writer-save observer,
detaches the FRC delegate, and finishes any open async sequences.
Subsequent saves don't hit a cancelled stream. Drop your reference and
the stream cancels itself.

A small honesty about the implementation: emissions today are driven
by re-running `frc.performFetch()` after each writer save rather than
by the diffed `controllerDidChangeContent` deltas. In-memory stores
don't surface inserts to the FRC reliably through `mergeChanges`, and
predictability beat per-row diffs as a v1 tradeoff. Diffed emissions
are still on the table once we have a more thorough Core Data merge
story.

## Relationships in detail

Two halves of the same coin:

- **Reads** see relationships as immutable optionals: `Destination?`
  for to-one, `[Destination]?` for to-many. They are `nil` unless the
  read explicitly asked for them via `relationships:`. There is no
  faulting and no lazy navigation.
- **Writes** see relationships as the regular Core Data dynamic
  accessors: `databasePatient.notes` returns the live `NSOrderedSet`
  (or `Set<DatabasePatientNote>` for unordered to-many; `Database X?`
  for to-one). Mutate through `mutableSetValue(forKey:)` /
  `mutableOrderedSetValue(forKey:)` or assign directly. The graph is
  alive while inside `mutate { ... }`.

```swift
try await slate.mutate { context in
    let patient = try context[DatabasePatient.self]
        .one(where: \.patientId == "P-001")
    let note = context.create(DatabasePatientNote.self)
    note.noteId = UUID().uuidString
    note.body = "First visit."
    note.patient = patient
    // The inverse `patient.notes` is wired up automatically by Core Data.
}
```

Gotchas:

- Hydration is shallow. If you need two levels of relationships,
  request both. Nested-path APIs are not in v1.
- Mutable rows are not `Sendable` and must not escape the `mutate`
  closure. This is enforced by the compiler — the conversion has to
  go through `context.immutable(row)`.
- Long-lived references to `NSManagedObject` outside a transaction
  scope are not supported. The reader/writer model assumes that every
  mutable row is bound to its owning context's lifetime.

## Caching

Slate keeps an in-memory cache of converted immutable values, keyed by
`NSManagedObjectID`. Reads with no relationship request consult the
cache before hitting Core Data, so repeated identical fetches are
cheap. Mutations apply pre-save cache updates so any concurrent
read or stream emission picks up the new value immediately. If a save
fails, the cache is restored from a per-mutation undo snapshot
captured before the apply.

You shouldn't need to interact with the cache directly. It exists so
that `slate.many(Patient.self)` called twice in a row doesn't allocate
a fresh `Patient` for each row both times.

## Tradeoffs and non-goals

Slate 3 is opinionated about what it _isn't_:

- **Not a migration tool.** The store on disk is treated as a
  disposable cache. An incompatible schema is wiped, not migrated.
- **Not a full Core Data wrapper.** Faulting, transformable
  attributes (in v1), arbitrary `NSPredicate` features beyond what
  `SlatePredicate` exposes, multiple stacks per file URL — all
  out of scope.
- **Not Combine-aware.** Streams are `@Observable` and
  `AsyncSequence`. If you need Combine you can adapt, but there's no
  built-in `Publisher` API.
- **Not a SwiftData replacement.** SwiftData and Slate solve different
  problems with overlapping ergonomics. SwiftData owns the persistent
  model object; Slate keeps Core Data underneath and exposes
  immutable views over it. If you want SwiftData's dynamic mutation
  model, use SwiftData.

## Status

Slate 3 is in active development. The runtime is stable, the
generator is feature-complete for the core schema surface, and the
test suite covers the runtime, the parser, the renderer, the macros,
and an in-tree compile-tested fixture that exercises the generated
code end-to-end.

Tracked work-in-progress lives in `progress.md`.

## License

Slate 3 is released under the MIT license. See `LICENSE.txt` for
details.
