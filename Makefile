bootstrap:
	@brew install mint
	@mint install nicklockwood/SwiftFormat
	@cp bin/githooks/pre-commit .git/hooks/.

format:
	@mint run swiftformat --config .swiftformat .

testsetup:
	@swift run slategen gen-core-data \
		--input-model Tests/DataModel/SlateTests.xcdatamodel \
		--output-slate-object-path Tests/Generated/ImmutableModels \
		--output-core-data-entity-path Tests/Generated/DatabaseModels \
		-f --cast-int \
		--name-transform Slate%@ \
		--file-transform Slate%@ \
		--imports "import Slate"

.PHONY: bootstrap \
	format
