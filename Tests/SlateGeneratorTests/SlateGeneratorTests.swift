import Foundation
import SlateFixturePatientModels
import SlateGeneratorLib
import Testing

@Suite
struct SlateGeneratorTests {
    @Test
    func dumpsBasicEntitySchema() throws {
        let source = """
        import SlateSchema

        @SlateEntity(
            name: "PatientRow",
            storageName: "DatabasePatient",
            relationships: [
                .toMany("notes", PatientNote.self, inverse: "patient", deleteRule: .cascade, ordered: true)
            ]
        )
        public struct Patient {
            #Index<Patient>([\\.patientId])
            #Index<Patient>([\\.age], order: .descending)
            #Unique<Patient>([\\.patientId])

            @SlateAttribute(indexed: true)
            public let patientId: String
            public let age: Int?
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "PatientSchema",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence"
        )

        #expect(schema.entities.map(\.swiftName) == ["Patient"])
        #expect(schema.entities.first?.entityName == "PatientRow")
        #expect(schema.entities.first?.mutableName == "DatabasePatient")
        #expect(schema.entities.first?.attributes.map(\.swiftName) == ["patientId", "age"])
        #expect(schema.entities.first?.attributes.first?.indexed == true)
        #expect(schema.entities.first?.indexes == [
            NormalizedIndex(storageNames: ["patientId"]),
            NormalizedIndex(storageNames: ["age"], order: "descending"),
        ])
        #expect(schema.entities.first?.uniqueness == [
            NormalizedUniqueness(storageNames: ["patientId"]),
        ])
        #expect(schema.entities.first?.relationships.first == NormalizedRelationship(
            name: "notes",
            kind: "toMany",
            destination: "PatientNote",
            inverse: "patient",
            deleteRule: "cascade",
            ordered: true
        ))
    }

    @Test
    func parsesEmbeddedStructsAsFlattenedStorage() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let patientId: String

            @SlateEmbedded
            public let address: Address?

            @SlateEmbedded
            public struct Address: Equatable, Sendable {
                public let city: String?

                @SlateAttribute(storageName: "addr_zip")
                public let postalCode: String?
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "PatientSchema",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence"
        )

        let entity = try #require(schema.entities.first)
        #expect(entity.attributes.map(\.swiftName) == ["patientId"])
        #expect(entity.embedded == [
            NormalizedEmbedded(
                swiftName: "address",
                swiftType: "Address",
                optional: true,
                presenceStorageName: "address_has",
                attributes: [
                    NormalizedAttribute(
                        swiftName: "city",
                        storageName: "address_city",
                        swiftType: "String?",
                        storageType: "string",
                        optional: true
                    ),
                    NormalizedAttribute(
                        swiftName: "postalCode",
                        storageName: "addr_zip",
                        swiftType: "String?",
                        storageType: "string",
                        optional: true
                    ),
                ]
            ),
        ])
    }

    @Test
    func parsesNonOptionalEmbeddedStruct() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateEmbedded
            public let address: Address

            @SlateEmbedded
            public struct Address: Equatable, Sendable {
                public let city: String?
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let embedded = try #require(entity.embedded.first)
        #expect(embedded.swiftName == "address")
        #expect(embedded.optional == false)
        // Non-optional embedded must NOT generate a presence flag.
        #expect(embedded.presenceStorageName == nil)
        #expect(embedded.attributes.map(\.storageName) == ["address_city"])
    }

    @Test
    func parsesNestedEnumWithStringRawType() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateAttribute(default: .unknown)
            public let sex: Sex

            public let teamRole: TeamRole?

            public enum Sex: String, Sendable {
                case unknown
                case female
                case male
            }

            public enum TeamRole: String, Sendable {
                case patient
                case caregiver
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let byName = Dictionary(uniqueKeysWithValues: entity.attributes.map { ($0.swiftName, $0) })

        let sex = try #require(byName["sex"])
        #expect(sex.enumKind == NormalizedEnumKind(typeName: "Sex", rawType: "String"))
        #expect(sex.storageType == "string")
        #expect(sex.optional == false)

        let teamRole = try #require(byName["teamRole"])
        #expect(teamRole.enumKind == NormalizedEnumKind(typeName: "TeamRole", rawType: "String"))
        #expect(teamRole.optional == true)
    }

    @Test
    func parsesImportedEnumFromSiblingFile() throws {
        // Status lives in a sibling file, NOT nested in the entity. The
        // cross-file enum index must surface its raw type so the attribute
        // gets full enum metadata rather than degrading to "rawRepresentable".
        let entitySource = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            public let status: Status
        }
        """
        let supportSource = """
        public enum Status: String, Sendable {
            case active
            case inactive
        }
        """

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let entityURL = dir.appendingPathComponent("Patient.swift")
        let supportURL = dir.appendingPathComponent("Status.swift")
        try entitySource.write(to: entityURL, atomically: true, encoding: .utf8)
        try supportSource.write(to: supportURL, atomically: true, encoding: .utf8)

        let schema = try SwiftSchemaParser().parseFiles(
            at: [entityURL, supportURL],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let status = try #require(entity.attributes.first { $0.swiftName == "status" })
        #expect(status.enumKind == NormalizedEnumKind(typeName: "Status", rawType: "String"))
        #expect(status.storageType == "string")
    }

    @Test
    func parsesQualifiedImportedEnumReference() throws {
        // The attribute uses a qualified type name `SharedTypes.Mode`. The
        // cross-file index is keyed by leaf name, so resolution must strip
        // the module prefix before lookup.
        let entitySource = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            public let mode: SharedTypes.Mode
        }
        """
        let supportSource = """
        public enum Mode: Int32, Sendable {
            case off
            case on
        }
        """
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("Patient.swift")
        let b = dir.appendingPathComponent("Mode.swift")
        try entitySource.write(to: a, atomically: true, encoding: .utf8)
        try supportSource.write(to: b, atomically: true, encoding: .utf8)

        let schema = try SwiftSchemaParser().parseFiles(
            at: [a, b],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let mode = try #require(entity.attributes.first { $0.swiftName == "mode" })
        #expect(mode.enumKind == NormalizedEnumKind(typeName: "Mode", rawType: "Int32"))
        #expect(mode.storageType == "integer32")
    }

    @Test
    func parserDetectsCrossFileEnumNameCollision() throws {
        // Two different files declare `enum Status` at top level. The
        // parser cannot disambiguate; the attribute that references
        // `Status` should produce a parse issue suggesting the explicit
        // override.
        let entitySource = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            public let status: Status
        }
        """
        let firstDecl = """
        public enum Status: String, Sendable {
            case active
            case inactive
        }
        """
        let secondDecl = """
        public enum Status: Int32, Sendable {
            case zero
            case one
        }
        """
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("Patient.swift")
        let b = dir.appendingPathComponent("StatusA.swift")
        let c = dir.appendingPathComponent("StatusB.swift")
        try entitySource.write(to: a, atomically: true, encoding: .utf8)
        try firstDecl.write(to: b, atomically: true, encoding: .utf8)
        try secondDecl.write(to: c, atomically: true, encoding: .utf8)

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [a, b, c],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected collision diagnostic")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.property == "status" &&
                    $0.message.contains("declared in multiple input files") &&
                    $0.message.contains("@SlateAttribute(enumRawType:")
            })
        }
    }

    @Test
    func enumRawTypeOverrideResolvesExternalEnum() throws {
        // The enum declaration is NOT in the parser's input set (it lives
        // in a precompiled module the generator can't see). The user
        // disambiguates with the explicit override and the attribute still
        // gets full enumKind metadata.
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateAttribute(enumRawType: String.self)
            public let mood: ExternalModule.Mood
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let mood = try #require(entity.attributes.first { $0.swiftName == "mood" })
        #expect(mood.enumKind == NormalizedEnumKind(typeName: "Mood", rawType: "String"))
        #expect(mood.storageType == "string")
    }

    @Test
    func enumRawTypeOverrideDisambiguatesCollision() throws {
        // Same setup as the collision test, but the attribute carries an
        // explicit `enumRawType:` so the parser bypasses the cross-file
        // index and resolves cleanly without emitting an issue.
        let entitySource = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateAttribute(enumRawType: Int32.self)
            public let status: Status
        }
        """
        let firstDecl = """
        public enum Status: String, Sendable { case active, inactive }
        """
        let secondDecl = """
        public enum Status: Int32, Sendable { case zero, one }
        """
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("Patient.swift")
        let b = dir.appendingPathComponent("StatusA.swift")
        let c = dir.appendingPathComponent("StatusB.swift")
        try entitySource.write(to: a, atomically: true, encoding: .utf8)
        try firstDecl.write(to: b, atomically: true, encoding: .utf8)
        try secondDecl.write(to: c, atomically: true, encoding: .utf8)

        let schema = try SwiftSchemaParser().parseFiles(
            at: [a, b, c],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let status = try #require(entity.attributes.first { $0.swiftName == "status" })
        // Override wins - Int32 storage type, even though one of the
        // colliding decls used String.
        #expect(status.enumKind == NormalizedEnumKind(typeName: "Status", rawType: "Int32"))
        #expect(status.storageType == "integer32")
    }

    @Test
    func enumRawTypeOverrideRejectsUnsupportedType() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateAttribute(enumRawType: Float.self)
            public let mood: Mood
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parse issue for unsupported enum raw type")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.message.contains("unsupported") &&
                    $0.message.contains("Float")
            })
        }
    }

    @Test
    func nestedEnumBeatsCrossFileWhenBothPresent() throws {
        // A top-level `Status` exists in a sibling file AND a nested
        // `Status` exists inside the entity. Entity-local must win so
        // users can shadow imported names without ambiguity.
        let entitySource = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            public let status: Status

            public enum Status: Int64, Sendable {
                case alpha
                case beta
            }
        }
        """
        let externalSource = """
        public enum Status: String, Sendable { case x, y }
        """
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("Patient.swift")
        let b = dir.appendingPathComponent("Status.swift")
        try entitySource.write(to: a, atomically: true, encoding: .utf8)
        try externalSource.write(to: b, atomically: true, encoding: .utf8)

        let schema = try SwiftSchemaParser().parseFiles(
            at: [a, b],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let status = try #require(entity.attributes.first { $0.swiftName == "status" })
        // Entity-local Int64 must win over external String.
        #expect(status.enumKind == NormalizedEnumKind(typeName: "Status", rawType: "Int64"))
        #expect(status.storageType == "integer64")
    }

    @Test
    func parsesNestedEnumWithIntRawType() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Reading {
            public let id: String
            @SlateAttribute(default: .none)
            public let priority: Priority

            public enum Priority: Int32, Sendable {
                case none
                case low
                case high
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let priority = try #require(entity.attributes.first { $0.swiftName == "priority" })

        #expect(priority.enumKind == NormalizedEnumKind(typeName: "Priority", rawType: "Int32"))
        #expect(priority.storageType == "integer32")
    }

    @Test
    func rendersEnumMutableAccessorAndStorage() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSchema",
            schemaFingerprint: "fp",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                        NormalizedAttribute(
                            swiftName: "sex",
                            storageName: "sex",
                            swiftType: "Sex",
                            storageType: "string",
                            optional: false,
                            defaultExpression: ".unknown",
                            enumKind: NormalizedEnumKind(typeName: "Sex", rawType: "String")
                        ),
                        NormalizedAttribute(
                            swiftName: "teamRole",
                            storageName: "teamRole",
                            swiftType: "TeamRole?",
                            storageType: "string",
                            optional: true,
                            enumKind: NormalizedEnumKind(typeName: "TeamRole", rawType: "String")
                        ),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let mutableFile = try #require(files.first { $0.path == "DatabasePatient.swift" })
        let schemaFile = try #require(files.first { $0.path == "PatientSchema.swift" })

        // Mutable class: enum attributes use primitiveValue, not @NSManaged.
        #expect(!mutableFile.contents.contains("@NSManaged public var sex:"))
        #expect(mutableFile.contents.contains("public var sex: Patient.Sex {"))
        #expect(mutableFile.contents.contains("primitiveValue(forKey: \"sex\")"))
        #expect(mutableFile.contents.contains("setPrimitiveValue(newValue.rawValue, forKey: \"sex\")"))
        // Default fallback is qualified.
        #expect(mutableFile.contents.contains("?? Patient.Sex.unknown"))
        // Optional enum: returns nil when raw absent, no fallback.
        #expect(mutableFile.contents.contains("public var teamRole: Patient.TeamRole? {"))
        #expect(mutableFile.contents.contains("return Patient.TeamRole(rawValue: raw)"))
        // Plain attribute still uses @NSManaged.
        #expect(mutableFile.contents.contains("@NSManaged public var patientId: String"))

        // Schema: Core Data attribute uses raw storage type and rendered default uses .rawValue.
        #expect(schemaFile.contents.contains("patientSexAttribute.attributeType = .stringAttributeType"))
        #expect(schemaFile.contents.contains("patientSexAttribute.defaultValue = Patient.Sex.unknown.rawValue"))
    }

    @Test
    func writerHonorsCustomManifestPath() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "fp",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ]
                ),
            ]
        )

        let baseTemp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let output = baseTemp.appendingPathComponent("Generated")
        let manifestDir = baseTemp.appendingPathComponent("Manifests")
        let manifest = manifestDir.appendingPathComponent("custom-manifest.json")
        defer { try? FileManager.default.removeItem(at: baseTemp) }

        let files = GeneratedSchemaRenderer().render(schema: schema)
        try GeneratedFileWriter().write(files: files, to: output, manifestURL: manifest)

        // Sources land in the output directory.
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("DatabasePatient.swift").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("PatientSlateSchema.swift").path))
        // Manifest is written to the explicit URL, NOT to the output directory.
        #expect(FileManager.default.fileExists(atPath: manifest.path))
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("SlateGenerationManifest.json").path))

        // staleFiles must read the manifest from the same custom path
        // (and the source files from the output dir) - everything is fresh
        // so nothing should be stale.
        #expect(try GeneratedFileWriter().staleFiles(files: files, in: output, manifestURL: manifest).isEmpty)

        // clean removes only the manifest-listed files plus the manifest at
        // its custom path.
        let removed = try GeneratedFileWriter().clean(outputDirectory: output, manifestURL: manifest).sorted()
        #expect(removed == [
            "DatabasePatient.swift",
            "Patient+SlateBridge.swift",
            "PatientSlateSchema.swift",
            "SlateGenerationManifest.json",
        ])
        #expect(!FileManager.default.fileExists(atPath: manifest.path))
    }

    // Compile-tested fixture: the persistence module
    // (SlateFixturePatientPersistence) is compiled by `swift build` from
    // the committed generated files in Sources/. This test verifies that
    // re-running the generator over the committed model sources reproduces
    // the same output bit-for-bit. If this fails, the committed files are
    // stale — regenerate them with `slate-generator generate`.
    @Test
    func fixturePersistenceFilesRoundTrip() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SlateGeneratorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        let modelsDir = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SlateFixturePatientModels")
        let persistenceDir = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SlateFixturePatientPersistence")

        let fileManager = FileManager.default
        guard let modelEnumerator = fileManager.enumerator(at: modelsDir, includingPropertiesForKeys: nil) else {
            Issue.record("Could not enumerate fixture model directory at \(modelsDir.path)")
            return
        }
        let modelFiles = modelEnumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }

        let schema = try SwiftSchemaParser().parseFiles(
            at: modelFiles,
            schemaName: "PatientSlateSchema",
            modelModule: "SlateFixturePatientModels",
            runtimeModule: "SlateFixturePatientPersistence"
        )
        try SchemaValidator().validate(schema)
        let files = GeneratedSchemaRenderer().render(schema: schema)

        // Compare each rendered file against its on-disk counterpart in
        // the persistence target. The manifest is intentionally NOT
        // committed alongside the source files (it's per-build state),
        // so we skip it here.
        for file in files where file.kind != .manifest {
            let existing = persistenceDir.appendingPathComponent(file.path)
            guard fileManager.fileExists(atPath: existing.path) else {
                Issue.record("Missing committed fixture file: \(file.path)")
                continue
            }
            let onDisk = try String(contentsOf: existing, encoding: .utf8)
            #expect(
                onDisk == file.contents,
                "Committed fixture \(file.path) is stale. Regenerate with `slate-generator generate`."
            )
        }
    }

    @Test
    func writerRoutesGeneratedFilesByKind() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "fp",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ]
                ),
            ]
        )

        let baseTemp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let mutableDir = baseTemp.appendingPathComponent("Mutable")
        let bridgeDir = baseTemp.appendingPathComponent("Bridge")
        let schemaDir = baseTemp.appendingPathComponent("Schema")
        let manifestURL = baseTemp.appendingPathComponent("manifest.json")
        defer { try? FileManager.default.removeItem(at: baseTemp) }

        let layout = GeneratedOutputLayout(
            mutable: mutableDir,
            bridge: bridgeDir,
            schema: schemaDir,
            manifest: manifestURL
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        try GeneratedFileWriter().write(files: files, layout: layout)

        // Each file kind lands in its own directory.
        #expect(FileManager.default.fileExists(atPath: mutableDir.appendingPathComponent("DatabasePatient.swift").path))
        #expect(FileManager.default.fileExists(atPath: bridgeDir.appendingPathComponent("Patient+SlateBridge.swift").path))
        #expect(FileManager.default.fileExists(atPath: schemaDir.appendingPathComponent("PatientSlateSchema.swift").path))
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        // No cross-leakage: bridge/schema do not appear in the mutable dir.
        #expect(!FileManager.default.fileExists(atPath: mutableDir.appendingPathComponent("Patient+SlateBridge.swift").path))
        #expect(!FileManager.default.fileExists(atPath: mutableDir.appendingPathComponent("PatientSlateSchema.swift").path))

        // staleFiles round-trips through the same layout.
        #expect(try GeneratedFileWriter().staleFiles(files: files, layout: layout).isEmpty)

        // clean removes everything across all per-kind directories.
        let removed = try GeneratedFileWriter().clean(layout: layout).sorted()
        #expect(removed == [
            "DatabasePatient.swift",
            "Patient+SlateBridge.swift",
            "PatientSlateSchema.swift",
            "SlateGenerationManifest.json",
        ])
        #expect(!FileManager.default.fileExists(atPath: mutableDir.appendingPathComponent("DatabasePatient.swift").path))
        #expect(!FileManager.default.fileExists(atPath: bridgeDir.appendingPathComponent("Patient+SlateBridge.swift").path))
        #expect(!FileManager.default.fileExists(atPath: schemaDir.appendingPathComponent("PatientSlateSchema.swift").path))
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
    }

    @Test
    func writerCreatesIntermediateDirectoriesForManifest() throws {
        let schema = NormalizedSchema(
            schemaName: "S",
            schemaFingerprint: "fp",
            modelModule: "M",
            runtimeModule: "R",
            entities: []
        )

        let baseTemp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let output = baseTemp.appendingPathComponent("Generated")
        let manifest = baseTemp
            .appendingPathComponent("a")
            .appendingPathComponent("b")
            .appendingPathComponent("c")
            .appendingPathComponent("manifest.json")
        defer { try? FileManager.default.removeItem(at: baseTemp) }

        let files = GeneratedSchemaRenderer().render(schema: schema)
        try GeneratedFileWriter().write(files: files, to: output, manifestURL: manifest)

        #expect(FileManager.default.fileExists(atPath: manifest.path))
    }

    @Test
    func rendersOptionalNumericAndBoolAccessors() throws {
        let schema = NormalizedSchema(
            schemaName: "PrimitiveSchema",
            schemaFingerprint: "fp",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Reading",
                    entityName: "Reading",
                    mutableName: "DatabaseReading",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "id",
                            storageName: "id",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                        // Non-optional Int stays @NSManaged.
                        NormalizedAttribute(
                            swiftName: "count",
                            storageName: "count",
                            swiftType: "Int",
                            storageType: "integer64",
                            optional: false
                        ),
                        // Optional types must use primitive-value bridge.
                        NormalizedAttribute(
                            swiftName: "age",
                            storageName: "age",
                            swiftType: "Int?",
                            storageType: "integer64",
                            optional: true
                        ),
                        NormalizedAttribute(
                            swiftName: "version",
                            storageName: "version",
                            swiftType: "Int32?",
                            storageType: "integer32",
                            optional: true
                        ),
                        NormalizedAttribute(
                            swiftName: "smallCount",
                            storageName: "smallCount",
                            swiftType: "Int16?",
                            storageType: "integer16",
                            optional: true
                        ),
                        NormalizedAttribute(
                            swiftName: "weight",
                            storageName: "weight",
                            swiftType: "Double?",
                            storageType: "double",
                            optional: true
                        ),
                        NormalizedAttribute(
                            swiftName: "ratio",
                            storageName: "ratio",
                            swiftType: "Float?",
                            storageType: "float",
                            optional: true
                        ),
                        NormalizedAttribute(
                            swiftName: "isFlagged",
                            storageName: "isFlagged",
                            swiftType: "Bool?",
                            storageType: "boolean",
                            optional: true
                        ),
                        NormalizedAttribute(
                            swiftName: "balance",
                            storageName: "balance",
                            swiftType: "Decimal?",
                            storageType: "decimal",
                            optional: true
                        ),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let mutableFile = try #require(files.first { $0.path == "DatabaseReading.swift" })

        // Non-optional Int stays @NSManaged.
        #expect(mutableFile.contents.contains("@NSManaged public var count: Int"))
        // Optional Int -> NSNumber bridge with .intValue.
        #expect(mutableFile.contents.contains("public var age: Int? {"))
        #expect(mutableFile.contents.contains("(primitiveValue(forKey: \"age\") as? NSNumber)?.intValue"))
        #expect(mutableFile.contents.contains("setPrimitiveValue(newValue.map { NSNumber(value: $0) }, forKey: \"age\")"))
        // Optional Int32 -> .int32Value.
        #expect(mutableFile.contents.contains("public var version: Int32? {"))
        #expect(mutableFile.contents.contains("?.int32Value"))
        // Optional Int16 -> .int16Value.
        #expect(mutableFile.contents.contains("public var smallCount: Int16? {"))
        #expect(mutableFile.contents.contains("?.int16Value"))
        // Optional Double -> .doubleValue.
        #expect(mutableFile.contents.contains("public var weight: Double? {"))
        #expect(mutableFile.contents.contains("?.doubleValue"))
        // Optional Float -> .floatValue.
        #expect(mutableFile.contents.contains("public var ratio: Float? {"))
        #expect(mutableFile.contents.contains("?.floatValue"))
        // Optional Bool -> .boolValue.
        #expect(mutableFile.contents.contains("public var isFlagged: Bool? {"))
        #expect(mutableFile.contents.contains("?.boolValue"))
        // Optional Decimal -> NSDecimalNumber.decimalValue.
        #expect(mutableFile.contents.contains("public var balance: Decimal? {"))
        #expect(mutableFile.contents.contains("(primitiveValue(forKey: \"balance\") as? NSDecimalNumber)?.decimalValue"))
        #expect(mutableFile.contents.contains("setPrimitiveValue(newValue.map { NSDecimalNumber(decimal: $0) }, forKey: \"balance\")"))

        // Optional types must NOT have @NSManaged variants.
        #expect(!mutableFile.contents.contains("@NSManaged public var age:"))
        #expect(!mutableFile.contents.contains("@NSManaged public var balance:"))
    }

    @Test
    func rendersThrowingEnumHydrationBranches() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSchema",
            schemaFingerprint: "fp",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "id",
                            storageName: "id",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                        // Non-optional enum WITH default: silent fallback.
                        NormalizedAttribute(
                            swiftName: "sex",
                            storageName: "sex",
                            swiftType: "Sex",
                            storageType: "string",
                            optional: false,
                            defaultExpression: ".unknown",
                            enumKind: NormalizedEnumKind(typeName: "Sex", rawType: "String")
                        ),
                        // Non-optional enum WITHOUT default: must throw.
                        NormalizedAttribute(
                            swiftName: "role",
                            storageName: "role",
                            swiftType: "Role",
                            storageType: "string",
                            optional: false,
                            enumKind: NormalizedEnumKind(typeName: "Role", rawType: "String")
                        ),
                        // Optional enum: no preflight needed.
                        NormalizedAttribute(
                            swiftName: "team",
                            storageName: "team",
                            swiftType: "Team?",
                            storageType: "string",
                            optional: true,
                            enumKind: NormalizedEnumKind(typeName: "Team", rawType: "String")
                        ),
                    ]
                ),
            ]
        )

        let bridge = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "Patient+SlateBridge.swift"
        })

        // Default-fallback branch.
        #expect(bridge.contents.contains("let resolvedSex: Patient.Sex"))
        #expect(bridge.contents.contains("?? Patient.Sex.unknown"))

        // Throwing branch (nil) and (unmappable raw).
        #expect(bridge.contents.contains("throw SlateError.invalidStoredValue(entity: \"Patient\", property: \"role\", valueDescription: \"nil\")"))
        #expect(bridge.contents.contains("guard let resolvedRole = Patient.Role(rawValue: rawRole)"))
        #expect(bridge.contents.contains("valueDescription: String(describing: rawRole)"))

        // Optional enum gets no preflight - passed through directly.
        #expect(!bridge.contents.contains("resolvedTeam"))
        #expect(bridge.contents.contains("team: team"))

        // Final initializer references the resolved locals.
        #expect(bridge.contents.contains("sex: resolvedSex"))
        #expect(bridge.contents.contains("role: resolvedRole"))
    }

    @Test
    func parsesEmbeddedNumericAndBoolFields() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Reading {
            public let id: String

            @SlateEmbedded
            public let metrics: Metrics?

            @SlateEmbedded
            public struct Metrics: Equatable, Sendable {
                public let count: Int64
                public let weight: Double
                public let isFlagged: Bool
                public let attempts: Int16?
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let embedded = try #require(entity.embedded.first)
        let byName = Dictionary(uniqueKeysWithValues: embedded.attributes.map { ($0.swiftName, $0) })

        #expect(byName["count"]?.storageType == "integer64")
        #expect(byName["count"]?.storageName == "metrics_count")
        #expect(byName["weight"]?.storageType == "double")
        #expect(byName["isFlagged"]?.storageType == "boolean")
        #expect(byName["attempts"]?.storageType == "integer16")
        // Optional embedded creates a `_has` presence flag.
        #expect(embedded.presenceStorageName == "metrics_has")
    }

    @Test
    func ignoresUnannotatedEmbeddedStructType() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            @SlateEmbedded
            public let address: Address?

            public struct Address: Equatable, Sendable {
                public let city: String?
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "PatientSchema",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence"
        )

        #expect(schema.entities.first?.embedded.isEmpty == true)
    }

    @Test
    func rendersWritesChecksAndCleansGeneratedFiles() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "test-fingerprint",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "PatientRow",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false,
                            indexed: true
                        ),
                        NormalizedAttribute(
                            swiftName: "age",
                            storageName: "age",
                            swiftType: "Int?",
                            storageType: "integer64",
                            optional: true
                        ),
                    ]
                ),
            ]
        )

        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }

        let files = GeneratedSchemaRenderer().render(schema: schema)
        try GeneratedFileWriter().write(files: files, to: output)

        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("DatabasePatient.swift").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("PatientSlateSchema.swift").path))
        #expect(try GeneratedFileWriter().staleFiles(files: files, in: output).isEmpty)

        let mutableContents = try String(
            contentsOf: output.appendingPathComponent("DatabasePatient.swift"),
            encoding: .utf8
        )
        #expect(mutableContents.contains("@objc(DatabasePatient)"))
        #expect(mutableContents.contains("@NSManaged public var patientId: String"))

        let removed = try GeneratedFileWriter().clean(outputDirectory: output)
        #expect(removed.sorted() == [
            "DatabasePatient.swift",
            "Patient+SlateBridge.swift",
            "PatientSlateSchema.swift",
            "SlateGenerationManifest.json",
        ])
    }

    // `NSAttributeDescription.isIndexed` is deprecated in iOS 11 / macOS
    // 10.13 in favor of `NSEntityDescription.indexes`. The renderer must
    // not emit `isIndexed = ...` lines, and `@SlateAttribute(indexed:
    // true)` must still produce a real index — auto-promoted to a
    // single-element `NSFetchIndexDescription` so the runtime behavior
    // matches user intent without using deprecated API.
    @Test
    func rendersIndexedAttributeAsFetchIndexNotIsIndexed() throws {
        let schema = NormalizedSchema(
            schemaName: "S",
            schemaFingerprint: "fp",
            modelModule: "M",
            runtimeModule: "R",
            entities: [
                NormalizedEntity(
                    swiftName: "Author",
                    entityName: "Author",
                    mutableName: "DatabaseAuthor",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "name",
                            storageName: "name",
                            swiftType: "String",
                            storageType: "string",
                            optional: false,
                            indexed: true
                        ),
                        NormalizedAttribute(
                            swiftName: "biography",
                            storageName: "biography",
                            swiftType: "String?",
                            storageType: "string",
                            optional: true,
                            indexed: false
                        ),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let schemaFile = try #require(files.first { $0.path == "S.swift" })

        // Deprecated `isIndexed = ...` lines must not appear anywhere.
        #expect(!schemaFile.contents.contains("isIndexed"))

        // Auto-promoted single-element fetch index must appear for the
        // indexed attribute, and its element must reference the right
        // property by storage name.
        #expect(schemaFile.contents.contains("authorFetchIndex0"))
        #expect(schemaFile.contents.contains("authorEntity.propertiesByName[\"name\"]"))
        #expect(schemaFile.contents.contains("authorEntity.indexes = [authorFetchIndex0]"))

        // The non-indexed attribute does NOT produce a second fetch index.
        #expect(!schemaFile.contents.contains("authorFetchIndex1"))
    }

    // If an entity already declares an `@SlateEntity(indexes: [.index(\.x)])`
    // for a column, that column's `@SlateAttribute(indexed: true)` flag
    // must NOT add a duplicate single-attribute index — otherwise the
    // user ends up with two fetch indexes on the same column.
    @Test
    func suppressesAutoIndexWhenEntityIndexAlreadyCoversColumn() throws {
        let schema = NormalizedSchema(
            schemaName: "S",
            schemaFingerprint: "fp",
            modelModule: "M",
            runtimeModule: "R",
            entities: [
                NormalizedEntity(
                    swiftName: "Author",
                    entityName: "Author",
                    mutableName: "DatabaseAuthor",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "name",
                            storageName: "name",
                            swiftType: "String",
                            storageType: "string",
                            optional: false,
                            indexed: true
                        ),
                    ],
                    indexes: [
                        NormalizedIndex(storageNames: ["name"]),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let schemaFile = try #require(files.first { $0.path == "S.swift" })

        // Exactly one fetch index referencing `name`, no second auto-promoted entry.
        #expect(schemaFile.contents.contains("authorFetchIndex0"))
        #expect(!schemaFile.contents.contains("authorFetchIndex1"))
    }

    @Test
    func rendersRelationshipModelBuilderCode() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "test-fingerprint",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "notes",
                            kind: "toMany",
                            destination: "PatientNote",
                            inverse: "patient",
                            deleteRule: "cascade",
                            ordered: true
                        ),
                    ]
                ),
                NormalizedEntity(
                    swiftName: "PatientNote",
                    entityName: "PatientNote",
                    mutableName: "DatabasePatientNote",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "noteId",
                            storageName: "noteId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "patient",
                            kind: "toOne",
                            destination: "Patient",
                            inverse: "notes",
                            deleteRule: "nullify"
                        ),
                    ]
                ),
            ]
        )

        let schemaFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "PatientSlateSchema.swift"
        })
        let patientFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "DatabasePatient.swift"
        })
        let noteFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "DatabasePatientNote.swift"
        })
        let bridgeFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "Patient+SlateBridge.swift"
        })

        #expect(schemaFile.contents.contains("let patientNotesRelationship = NSRelationshipDescription()"))
        #expect(schemaFile.contents.contains("patientNotesRelationship.destinationEntity = patientNoteEntity"))
        #expect(schemaFile.contents.contains("patientNotesRelationship.inverseRelationship = patientNotePatientRelationship"))
        #expect(schemaFile.contents.contains("deleteRule: .cascade"))
        #expect(patientFile.contents.contains("@NSManaged public var notes: NSOrderedSet?"))
        #expect(noteFile.contents.contains("@NSManaged public var patient: DatabasePatient?"))
        #expect(bridgeFile.contents.contains("extension DatabasePatient: SlateRelationshipHydratingMutableObject"))
        #expect(bridgeFile.contents.contains("public func slateObject(hydrating relationships: Set<String>) throws -> Patient"))
        #expect(bridgeFile.contents.contains("notes: relationships.contains(\"notes\") ? (notes?.array as? [DatabasePatientNote])?.map(\\.slateObject) : nil"))
    }

    // Comprehensive coverage of the relationship hydration code path the
    // generator emits. A `Patient` entity declares all three relationship
    // kinds — to-one, ordered to-many, and unordered to-many — and the
    // renderer must:
    //
    //  1. Declare the right Core Data property type on the mutable class
    //     (`DestinationMutable?`, `NSOrderedSet?`, `Set<DestinationMutable>?`).
    //  2. Add a `NSRelationshipDescription` per relationship in the schema
    //     file's `makeManagedObjectModel()` builder.
    //  3. Emit a typed `slateObject(hydrating:)` body whose initializer
    //     arguments match the immutable property names of the destination,
    //     using the right unwrap for each kind.
    //  4. Conform the mutable type to
    //     `SlateRelationshipHydratingMutableObject` via the bridge file.
    //
    // Runtime coverage of the same three kinds is exercised in
    // `SlateRuntimeTests.queryHydratesRequestedToManyRelationships()` and
    // `queryHydratesRequestedToOneRelationship()`. This test pins the
    // renderer's output so renderer regressions surface here, before the
    // runtime tests exercise the produced code.
    @Test
    func rendersAllRelationshipKindHydrationExpressions() throws {
        let schema = NormalizedSchema(
            schemaName: "ClinicSchema",
            schemaFingerprint: "test-fingerprint",
            modelModule: "ClinicModels",
            runtimeModule: "ClinicPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "primaryDoctor",
                            kind: "toOne",
                            destination: "Doctor",
                            inverse: "patients",
                            deleteRule: "nullify",
                            ordered: false,
                            optional: true
                        ),
                        NormalizedRelationship(
                            name: "tags",
                            kind: "toMany",
                            destination: "Tag",
                            inverse: "patients",
                            deleteRule: "nullify",
                            ordered: false
                        ),
                        NormalizedRelationship(
                            name: "visits",
                            kind: "toMany",
                            destination: "Visit",
                            inverse: "patient",
                            deleteRule: "cascade",
                            ordered: true
                        ),
                    ]
                ),
                NormalizedEntity(
                    swiftName: "Doctor",
                    entityName: "Doctor",
                    mutableName: "DatabaseDoctor",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "doctorId",
                            storageName: "doctorId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "patients",
                            kind: "toMany",
                            destination: "Patient",
                            inverse: "primaryDoctor",
                            deleteRule: "nullify",
                            ordered: false
                        ),
                    ]
                ),
                NormalizedEntity(
                    swiftName: "Tag",
                    entityName: "Tag",
                    mutableName: "DatabaseTag",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "label",
                            storageName: "label",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "patients",
                            kind: "toMany",
                            destination: "Patient",
                            inverse: "tags",
                            deleteRule: "nullify",
                            ordered: false
                        ),
                    ]
                ),
                NormalizedEntity(
                    swiftName: "Visit",
                    entityName: "Visit",
                    mutableName: "DatabaseVisit",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "visitId",
                            storageName: "visitId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "patient",
                            kind: "toOne",
                            destination: "Patient",
                            inverse: "visits",
                            deleteRule: "nullify",
                            ordered: false
                        ),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)

        let patientMutable = try #require(files.first { $0.path == "DatabasePatient.swift" })
        // 1. Mutable class property declarations.
        #expect(patientMutable.contents.contains("@NSManaged public var primaryDoctor: DatabaseDoctor?"))
        #expect(patientMutable.contents.contains("@NSManaged public var tags: Set<DatabaseTag>?"))
        #expect(patientMutable.contents.contains("@NSManaged public var visits: NSOrderedSet?"))

        let patientBridge = try #require(files.first { $0.path == "Patient+SlateBridge.swift" })
        // 4. SlateRelationshipHydratingMutableObject conformance is emitted.
        #expect(patientBridge.contents.contains("extension DatabasePatient: SlateRelationshipHydratingMutableObject"))
        // 3. Each relationship kind uses its expected unwrap form.
        #expect(patientBridge.contents.contains(
            "primaryDoctor: relationships.contains(\"primaryDoctor\") ? primaryDoctor?.slateObject : nil"
        ))
        #expect(patientBridge.contents.contains(
            "tags: relationships.contains(\"tags\") ? tags?.map { $0.slateObject } : nil"
        ))
        #expect(patientBridge.contents.contains(
            "visits: relationships.contains(\"visits\") ? (visits?.array as? [DatabaseVisit])?.map(\\.slateObject) : nil"
        ))

        let schemaFile = try #require(files.first { $0.path == "ClinicSchema.swift" })
        // 2. Each relationship has an NSRelationshipDescription emitted.
        #expect(schemaFile.contents.contains("let patientPrimaryDoctorRelationship = NSRelationshipDescription()"))
        #expect(schemaFile.contents.contains("let patientTagsRelationship = NSRelationshipDescription()"))
        #expect(schemaFile.contents.contains("let patientVisitsRelationship = NSRelationshipDescription()"))
        #expect(schemaFile.contents.contains("patientVisitsRelationship.isOrdered = true"))
        #expect(schemaFile.contents.contains("patientTagsRelationship.isOrdered = false"))
        // SlateEntityMetadata also carries the relationship metadata used by
        // introspection callers.
        #expect(schemaFile.contents.contains("name: \"primaryDoctor\""))
        #expect(schemaFile.contents.contains("name: \"tags\""))
        #expect(schemaFile.contents.contains("name: \"visits\""))
    }

    @Test
    func rendersIndexesAndUniquenessConstraints() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "test-fingerprint",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                        NormalizedAttribute(
                            swiftName: "lastName",
                            storageName: "familyName",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    indexes: [
                        NormalizedIndex(storageNames: ["patientId"]),
                        NormalizedIndex(storageNames: ["familyName"]),
                    ],
                    uniqueness: [
                        NormalizedUniqueness(storageNames: ["patientId"]),
                    ]
                ),
            ]
        )

        let schemaFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "PatientSlateSchema.swift"
        })

        #expect(schemaFile.contents.contains("patientEntity.uniquenessConstraints = [[\"patientId\"]]"))
        #expect(schemaFile.contents.contains("let patientFetchIndex0 = NSFetchIndexDescription("))
        #expect(schemaFile.contents.contains("property: patientEntity.propertiesByName[\"patientId\"]!"))
        #expect(schemaFile.contents.contains("property: patientEntity.propertiesByName[\"familyName\"]!"))
        #expect(schemaFile.contents.contains("patientEntity.indexes = [patientFetchIndex0, patientFetchIndex1]"))
        // The runtime upsert/upsertMany path consults this metadata via the
        // table registry — the renderer must thread the parsed uniqueness
        // through to `register(...)`.
        #expect(schemaFile.contents.contains("uniquenessConstraints: [[\"patientId\"]]"))
    }

    @Test
    func generatedSchemaRegistersEmptyUniquenessForUnconstrainedEntity() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "fp",
            modelModule: "PatientModels",
            runtimeModule: "PatientRuntime",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "name",
                            storageName: "name",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ]
                ),
            ]
        )

        let schemaFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "PatientSlateSchema.swift"
        })

        // No declared uniqueness should still render the keyword argument so
        // the call signature lines up with the registry — runtime upsert just
        // sees an empty constraint list and rejects upserts on every key.
        #expect(schemaFile.contents.contains("uniquenessConstraints: []"))
    }

    @Test
    func parsesRelationshipMetadata() throws {
        let source = """
        import SlateSchema

        @SlateEntity(
            relationships: [
                .toOne("primaryDoctor", Doctor.self, inverse: "patients", deleteRule: .nullify, optional: false),
                .toMany("notes", PatientNote.self, inverse: "patient", deleteRule: .cascade, ordered: true, minCount: 1, maxCount: 50)
            ]
        )
        public struct Patient {
            public let patientId: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let toOne = try #require(entity.relationships.first { $0.name == "primaryDoctor" })
        let toMany = try #require(entity.relationships.first { $0.name == "notes" })

        #expect(toOne.optional == false)
        #expect(toOne.minCount == nil)
        #expect(toOne.maxCount == nil)
        #expect(toMany.optional == true)
        #expect(toMany.minCount == 1)
        #expect(toMany.maxCount == 50)
        #expect(toMany.ordered == true)
    }

    @Test
    func rendersRelationshipMetadataOnDescription() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "fp",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    relationships: [
                        NormalizedRelationship(
                            name: "primaryDoctor",
                            kind: "toOne",
                            destination: "Doctor",
                            inverse: "patients",
                            deleteRule: "nullify",
                            optional: false
                        ),
                        NormalizedRelationship(
                            name: "notes",
                            kind: "toMany",
                            destination: "Doctor",
                            inverse: "patientNotes",
                            deleteRule: "cascade",
                            ordered: true,
                            optional: true,
                            minCount: 1,
                            maxCount: 50
                        ),
                    ]
                ),
                NormalizedEntity(
                    swiftName: "Doctor",
                    entityName: "Doctor",
                    mutableName: "DatabaseDoctor",
                    sourceKind: "struct",
                    attributes: [],
                    relationships: [
                        NormalizedRelationship(
                            name: "patients",
                            kind: "toMany",
                            destination: "Patient",
                            inverse: "primaryDoctor",
                            deleteRule: "nullify"
                        ),
                        NormalizedRelationship(
                            name: "patientNotes",
                            kind: "toOne",
                            destination: "Patient",
                            inverse: "notes",
                            deleteRule: "nullify"
                        ),
                    ]
                ),
            ]
        )

        let schemaFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "PatientSlateSchema.swift"
        })
        // Non-optional toOne: isOptional = false, minCount 1, maxCount 1
        #expect(schemaFile.contents.contains("patientPrimaryDoctorRelationship.isOptional = false"))
        #expect(schemaFile.contents.contains("patientPrimaryDoctorRelationship.minCount = 1"))
        #expect(schemaFile.contents.contains("patientPrimaryDoctorRelationship.maxCount = 1"))
        // toMany: minCount 1, maxCount 50
        #expect(schemaFile.contents.contains("patientNotesRelationship.minCount = 1"))
        #expect(schemaFile.contents.contains("patientNotesRelationship.maxCount = 50"))
        #expect(schemaFile.contents.contains("patientNotesRelationship.isOrdered = true"))
    }

    @Test
    func rendersIndexesWithDescendingOrder() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "test-fingerprint",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                        NormalizedAttribute(
                            swiftName: "updatedAt",
                            storageName: "updatedAt",
                            swiftType: "Date",
                            storageType: "date",
                            optional: false
                        ),
                    ],
                    indexes: [
                        NormalizedIndex(storageNames: ["patientId"]), // ascending default
                        NormalizedIndex(storageNames: ["updatedAt"], order: "descending"),
                    ]
                ),
            ]
        )

        let schemaFile = try #require(GeneratedSchemaRenderer().render(schema: schema).first {
            $0.path == "PatientSlateSchema.swift"
        })

        // Ascending element does NOT set isAscending (defaults to true).
        #expect(!schemaFile.contents.contains("patientFetchIndex0Element0.isAscending = false"))
        // Descending element explicitly sets isAscending = false.
        #expect(schemaFile.contents.contains("patientFetchIndex1Element0.isAscending = false"))
        #expect(schemaFile.contents.contains("elements: [patientFetchIndex1Element0]"))
    }

    @Test
    func rendersEmbeddedStorageAndProviderBridge() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "test-fingerprint",
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    embedded: [
                        NormalizedEmbedded(
                            swiftName: "address",
                            swiftType: "Address",
                            optional: true,
                            presenceStorageName: "address_has",
                            attributes: [
                                NormalizedAttribute(
                                    swiftName: "city",
                                    storageName: "address_city",
                                    swiftType: "String?",
                                    storageType: "string",
                                    optional: true
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let mutableFile = try #require(files.first { $0.path == "DatabasePatient.swift" })
        let bridgeFile = try #require(files.first { $0.path == "Patient+SlateBridge.swift" })
        let schemaFile = try #require(files.first { $0.path == "PatientSlateSchema.swift" })

        #expect(mutableFile.contents.contains("@NSManaged public var address_has: Bool"))
        #expect(mutableFile.contents.contains("@NSManaged public var address_city: String?"))
        #expect(bridgeFile.contents.contains("public var address: Patient.Address?"))
        #expect(bridgeFile.contents.contains("guard address_has else"))
        #expect(schemaFile.contents.contains("swiftName: \"address_has\""))
        #expect(schemaFile.contents.contains("patientAddress_cityAttribute.name = \"address_city\""))
    }

    @Test
    func validatesDuplicateStorageNames() throws {
        let schema = NormalizedSchema(
            schemaName: "BadSchema",
            schemaFingerprint: "bad",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "serverId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                        NormalizedAttribute(
                            swiftName: "legacyId",
                            storageName: "serverId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ]
                ),
            ]
        )

        do {
            try SchemaValidator().validate(schema)
            Issue.record("Expected validation to fail")
        } catch let error as SchemaValidationError {
            #expect(error.description.contains("duplicate storage name 'serverId'"))
        }
    }

    @Test
    func validatesRelationshipDestinationAndInverse() throws {
        let schema = NormalizedSchema(
            schemaName: "BadSchema",
            schemaFingerprint: "bad",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [],
                    relationships: [
                        NormalizedRelationship(
                            name: "notes",
                            kind: "toMany",
                            destination: "PatientNote",
                            inverse: "patient",
                            deleteRule: "cascade"
                        ),
                    ]
                ),
            ]
        )

        do {
            try SchemaValidator().validate(schema)
            Issue.record("Expected validation to fail")
        } catch let error as SchemaValidationError {
            #expect(error.description.contains("references missing destination 'PatientNote'"))
        }
    }

    @Test
    func validatesIndexesReferenceKnownStorageNames() throws {
        let schema = NormalizedSchema(
            schemaName: "BadSchema",
            schemaFingerprint: "bad",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ],
                    indexes: [
                        NormalizedIndex(storageNames: ["missing"]),
                    ]
                ),
            ]
        )

        do {
            try SchemaValidator().validate(schema)
            Issue.record("Expected validation to fail")
        } catch let error as SchemaValidationError {
            #expect(error.description.contains("index references unknown storage name 'missing'"))
        }
    }

    @Test
    func parserCapturesDefaultExpressions() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            @SlateAttribute(default: "")
            public let firstName: String

            @SlateAttribute(default: 0)
            public let sortRank: Int64

            @SlateAttribute(default: false)
            public let isArchived: Bool

            @SlateAttribute(default: .unknown)
            public let sex: Sex

            public let middleName: String?
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let byName = Dictionary(uniqueKeysWithValues: entity.attributes.map { ($0.swiftName, $0) })

        #expect(byName["firstName"]?.defaultExpression == "\"\"")
        #expect(byName["sortRank"]?.defaultExpression == "0")
        #expect(byName["isArchived"]?.defaultExpression == "false")
        #expect(byName["sex"]?.defaultExpression == ".unknown")
        #expect(byName["middleName"]?.defaultExpression == nil)
    }

    @Test
    func rendersPrimitiveDefaultsIntoSchema() throws {
        let schema = NormalizedSchema(
            schemaName: "PatientSchema",
            schemaFingerprint: "fp",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "firstName",
                            storageName: "firstName",
                            swiftType: "String",
                            storageType: "string",
                            optional: false,
                            defaultExpression: "\"\""
                        ),
                        NormalizedAttribute(
                            swiftName: "sortRank",
                            storageName: "sortRank",
                            swiftType: "Int64",
                            storageType: "integer64",
                            optional: false,
                            defaultExpression: "0"
                        ),
                        NormalizedAttribute(
                            swiftName: "isArchived",
                            storageName: "isArchived",
                            swiftType: "Bool",
                            storageType: "boolean",
                            optional: false,
                            defaultExpression: "false"
                        ),
                        NormalizedAttribute(
                            swiftName: "sex",
                            storageName: "sex",
                            swiftType: "Sex",
                            storageType: "string",
                            optional: false,
                            defaultExpression: ".unknown"
                        ),
                    ]
                ),
            ]
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let schemaFile = try #require(files.first { $0.path == "PatientSchema.swift" })

        #expect(schemaFile.contents.contains("patientFirstNameAttribute.defaultValue = \"\""))
        #expect(schemaFile.contents.contains("patientSortRankAttribute.defaultValue = 0"))
        #expect(schemaFile.contents.contains("patientIsArchivedAttribute.defaultValue = false"))
        #expect(!schemaFile.contents.contains("patientSexAttribute.defaultValue ="))
    }

    @Test
    func parserRejectsNonPublicEntity() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        struct Internal {
            let name: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject non-public entity")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains { $0.message.contains("must be declared 'public'") })
        }
    }

    @Test
    func parserRejectsGenericEntity() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Box<T> {
            public let id: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject generic entity")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains { $0.message.contains("cannot be generic") })
        }
    }

    @Test
    func parserRejectsVarStoredProperty() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            public var draft: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject 'var' stored property")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains { $0.property == "draft" && $0.message.contains("use 'let' instead") })
        }
    }

    @Test
    func parserRejectsAnnotatedComputedProperty() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            @SlateAttribute
            public var derivedName: String { "" }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject computed persisted property")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.property == "derivedName" &&
                    $0.message.contains("computed persisted properties are not supported")
            })
        }
    }

    @Test
    func parserRejectsExternalEmbeddedType() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateEmbedded
            public let address: ExternalAddress?
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject external embedded type")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.property == "address" &&
                    $0.message.contains("references external type 'ExternalAddress'")
            })
        }
    }

    @Test
    func parserRejectsNestedSlateEmbedded() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            @SlateEmbedded
            public let address: Address?

            @SlateEmbedded
            public struct Address {
                public let line1: String?
                @SlateEmbedded
                public let geo: Geo?
            }

            @SlateEmbedded
            public struct Geo {
                public let lat: Double?
                public let lon: Double?
            }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject nested @SlateEmbedded")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.property == "address.geo" &&
                    $0.message.contains("@SlateEmbedded is only supported on entity-level properties")
            })
        }
    }

    @Test
    func parserRejectsInheritedClassEntity() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public final class Patient: Person, Sendable {
            public let id: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject inherited class entity")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.message.contains("inherits from class 'Person'")
            })
        }
    }

    @Test
    func parserAcceptsClassEntityWithProtocolConformancesOnly() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public final class Patient: Sendable, Identifiable, Codable {
            public let id: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        #expect(schema.entities.first?.swiftName == "Patient")
    }

    // The destination type can be passed as a String literal instead of
    // `Foo.self` to dodge Swift's circular-reference detector when two
    // entities reference each other via macro args. The parser must
    // accept both forms; the schema validator/renderer treats them
    // identically once normalized.
    @Test
    func parserAcceptsStringDestinationRelationship() throws {
        let source = """
        import SlateSchema

        @SlateEntity(
            relationships: [
                .toMany("notes", "PatientNote", inverse: "patient", deleteRule: .cascade, ordered: true),
                .toOne("doctor", "Doctor", inverse: "patients", deleteRule: .nullify, optional: true),
            ]
        )
        public struct Patient {
            public let id: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let notes = try #require(entity.relationships.first { $0.name == "notes" })
        let doctor = try #require(entity.relationships.first { $0.name == "doctor" })
        #expect(notes.destination == "PatientNote")
        #expect(notes.kind == "toMany")
        #expect(notes.ordered == true)
        #expect(notes.deleteRule == "cascade")
        #expect(doctor.destination == "Doctor")
        #expect(doctor.kind == "toOne")
        #expect(doctor.optional == true)
    }

    @Test
    func parserHandlesQualifiedAndCommentedRelationshipDeclarations() throws {
        // Mixes:
        //  - Multi-line array literal with internal comments
        //  - Qualified `SlateRelationship.toMany(...)` form
        //  - Trailing inline comment after a labeled argument
        //  - Whitespace permutations the legacy string-substr parser couldn't
        //    survive (e.g., comment between callee and `(`).
        // Typed AST walk should produce a clean NormalizedRelationship.
        let source = """
        import SlateSchema

        @SlateEntity(
            relationships: [
                // primary doctor
                .toOne(
                    "primaryDoctor",
                    Doctor.self,
                    inverse: "patients",
                    deleteRule: .nullify,
                    optional: false
                ),
                SlateRelationship.toMany(
                    "notes",
                    PatientNote.self,
                    inverse: "patient",
                    deleteRule: .cascade,
                    ordered: true,
                    minCount: 1, // require at least one
                    maxCount: 50
                ),
            ]
        )
        public struct Patient {
            public let id: String
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        let toOne = try #require(entity.relationships.first { $0.name == "primaryDoctor" })
        let toMany = try #require(entity.relationships.first { $0.name == "notes" })

        #expect(toOne.kind == "toOne")
        #expect(toOne.destination == "Doctor")
        #expect(toOne.inverse == "patients")
        #expect(toOne.deleteRule == "nullify")
        #expect(toOne.optional == false)

        #expect(toMany.kind == "toMany")
        #expect(toMany.destination == "PatientNote")
        #expect(toMany.deleteRule == "cascade")
        #expect(toMany.ordered == true)
        #expect(toMany.minCount == 1)
        #expect(toMany.maxCount == 50)
    }

    @Test
    func parserHandlesMultiKeyPathIndexAndCommentedKeyPath() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            #Index<Patient>([\\.lastName, \\.firstName])  // composite
            #Index<Patient>([\\.updatedAt], order: .descending)
            #Unique<Patient>([\\.patientId])

            @SlateAttribute(storageName: "familyName")
            public let lastName: String
            public let firstName: String
            public let patientId: String
            public let updatedAt: Date
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = try SwiftSchemaParser().parseFiles(
            at: [url],
            schemaName: "S",
            modelModule: "M",
            runtimeModule: "R"
        )
        let entity = try #require(schema.entities.first)
        // Composite index expands to two storage names (renamed lastName -> "familyName").
        #expect(entity.indexes.count == 2)
        #expect(entity.indexes[0].storageNames == ["familyName", "firstName"])
        #expect(entity.indexes[1].storageNames == ["updatedAt"])
        #expect(entity.indexes[1].order == "descending")
        #expect(entity.uniqueness.first?.storageNames == ["patientId"])
    }

    @Test
    func parserIssuesIncludeSourceLocation() throws {
        // The 'var draft' on line 6 should produce an issue whose location
        // points back to that exact line. The 'computed annotated' issue on
        // line 8 should point to its own line.
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String
            public var draft: String
            @SlateAttribute
            public var derived: String { "" }
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to surface issues")
        } catch let error as SchemaParseError {
            let varIssue = try #require(error.issues.first { $0.property == "draft" })
            #expect(varIssue.location?.file == url.path)
            #expect(varIssue.location?.line == 6)

            let computedIssue = try #require(error.issues.first { $0.property == "derived" })
            #expect(computedIssue.location?.file == url.path)
            #expect(computedIssue.location?.line == 7) // line of @SlateAttribute (variable starts here)

            // formatted output uses "file:line:column: error: message" shape.
            #expect(varIssue.formatted.contains(url.path))
            #expect(varIssue.formatted.contains(":6:"))
            #expect(varIssue.formatted.contains("error:"))

            // SchemaParseError.description joins formatted issues so callers
            // get a usable summary out of the box.
            #expect(error.description.contains(url.path))
            #expect(error.description.contains("error:"))
        }
    }

    @Test
    func parserRejectsConditionalPersistedProperties() throws {
        let source = """
        import SlateSchema

        @SlateEntity
        public struct Patient {
            public let id: String

            #if DEBUG
            public let debugFlag: String
            #endif
        }
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SwiftSchemaParser().parseFiles(
                at: [url],
                schemaName: "S",
                modelModule: "M",
                runtimeModule: "R"
            )
            Issue.record("Expected parser to reject conditional persisted property")
        } catch let error as SchemaParseError {
            #expect(error.issues.contains {
                $0.message.contains("conditional compilation")
            })
        }
    }

    @Test
    func validatesValidBidirectionalRelationships() throws {
        let schema = NormalizedSchema(
            schemaName: "GoodSchema",
            schemaFingerprint: "good",
            modelModule: "Models",
            runtimeModule: "Persistence",
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [],
                    relationships: [
                        NormalizedRelationship(
                            name: "notes",
                            kind: "toMany",
                            destination: "PatientNote",
                            inverse: "patient",
                            deleteRule: "cascade"
                        ),
                    ]
                ),
                NormalizedEntity(
                    swiftName: "PatientNote",
                    entityName: "PatientNote",
                    mutableName: "DatabasePatientNote",
                    sourceKind: "struct",
                    attributes: [],
                    relationships: [
                        NormalizedRelationship(
                            name: "patient",
                            kind: "toOne",
                            destination: "Patient",
                            inverse: "notes",
                            deleteRule: "nullify"
                        ),
                    ]
                ),
            ]
        )

        try SchemaValidator().validate(schema)
    }

    // The macro emits `keypathToAttribute` cases for embedded fields and
    // the parser/renderer compute the flattened storage names from the
    // same source. This test asserts both ends of the pipeline land on
    // the same string for every embedded field of the fixture's
    // `Patient.Address`, including the `@SlateAttribute(storageName:)`
    // override on `postalCode`.
    @Test
    func macroAndGeneratorAgreeOnEmbeddedKeypathStorageNames() throws {
        // 1. Macro side: keypathToAttribute for every Patient.Address keypath.
        let line1Storage = Patient.keypathToAttribute(\Patient.address?.line1)
        let cityStorage = Patient.keypathToAttribute(\Patient.address?.city)
        let postalStorage = Patient.keypathToAttribute(\Patient.address?.postalCode)
        #expect(line1Storage == "address_line1")
        #expect(cityStorage == "address_city")
        #expect(postalStorage == "zip")  // honors @SlateAttribute(storageName:)

        // 2. Parser/generator side: re-parse the fixture model and confirm
        //    the same storage names land in the normalized schema.
        let modelsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SlateGeneratorTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources")
            .appendingPathComponent("SlateFixturePatientModels")
        let modelFiles = (FileManager.default.enumerator(at: modelsDir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }

        let schema = try SwiftSchemaParser().parseFiles(
            at: modelFiles,
            schemaName: "PatientSlateSchema",
            modelModule: "SlateFixturePatientModels",
            runtimeModule: "SlateFixturePatientPersistence"
        )

        let patient = try #require(schema.entities.first { $0.swiftName == "Patient" })
        let address = try #require(patient.embedded.first { $0.swiftName == "address" })
        let parserStorageNames = Dictionary(
            uniqueKeysWithValues: address.attributes.map { ($0.swiftName, $0.storageName) }
        )
        #expect(parserStorageNames["line1"] == line1Storage)
        #expect(parserStorageNames["city"] == cityStorage)
        #expect(parserStorageNames["postalCode"] == postalStorage)
        #expect(address.presenceStorageName == "address_has")
    }

    @Test
    func emitsModelModuleImportWhenModulesDiffer() throws {
        let schema = makeImportSampleSchema(
            modelModule: "PatientModels",
            runtimeModule: "PatientPersistence"
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let mutableFile = try #require(files.first { $0.kind == .mutable })
        let bridgeFile = try #require(files.first { $0.kind == .bridge })
        let schemaFile = try #require(files.first { $0.kind == .schema })

        for file in [mutableFile, bridgeFile, schemaFile] {
            #expect(
                file.contents.contains("\nimport PatientModels\n"),
                "Expected `import PatientModels` in \(file.path)"
            )
        }
    }

    @Test
    func omitsModelModuleImportWhenModulesMatch() throws {
        let schema = makeImportSampleSchema(
            modelModule: "SlateDemo",
            runtimeModule: "SlateDemo"
        )

        let files = GeneratedSchemaRenderer().render(schema: schema)
        let mutableFile = try #require(files.first { $0.kind == .mutable })
        let bridgeFile = try #require(files.first { $0.kind == .bridge })
        let schemaFile = try #require(files.first { $0.kind == .schema })

        for file in [mutableFile, bridgeFile, schemaFile] {
            #expect(
                !file.contents.contains("import SlateDemo"),
                "Did not expect `import SlateDemo` in \(file.path) when modules match"
            )
            // Sanity check: the rest of the import block is still intact.
            #expect(file.contents.contains("@preconcurrency import CoreData"))
            #expect(file.contents.contains("import Foundation"))
            #expect(file.contents.contains("import Slate\n"))
            #expect(file.contents.contains("import SlateSchema"))
        }
    }

    private func makeImportSampleSchema(
        modelModule: String,
        runtimeModule: String
    ) -> NormalizedSchema {
        NormalizedSchema(
            schemaName: "PatientSlateSchema",
            schemaFingerprint: "fp",
            modelModule: modelModule,
            runtimeModule: runtimeModule,
            entities: [
                NormalizedEntity(
                    swiftName: "Patient",
                    entityName: "Patient",
                    mutableName: "DatabasePatient",
                    sourceKind: "struct",
                    attributes: [
                        NormalizedAttribute(
                            swiftName: "patientId",
                            storageName: "patientId",
                            swiftType: "String",
                            storageType: "string",
                            optional: false
                        ),
                    ]
                ),
            ]
        )
    }
}
