import GraphQL
import OrderedCollections

/// One change of the name rewrite: an item of `extensions.rewrites` in the response (plan.md §4.5).
///
/// The agent reads these items to learn the canonical names.
struct NameRewrite: Encodable, Hashable, Sendable {
    /// The name that the caller wrote, for example `taskAdd`.
    // The synthesized `Encodable` and `Hashable` conformances read this property; periphery sees no reader.
    // periphery:ignore
    let from: String

    /// The canonical name, for example `addTask`. For a root query field that the rewrite moved into `board`, the
    /// name has the `board.` prefix, for example `board.tasks`.
    // The synthesized `Encodable` and `Hashable` conformances read this property; periphery sees no reader.
    // periphery:ignore
    let to: String

    /// The path to the name in the document: the response key of each field from the root, then the names of the
    /// argument and of each `input` field, as the caller wrote them. A name in a fragment definition starts with the
    /// name of the fragment.
    // The synthesized `Encodable` and `Hashable` conformances read this property; periphery sees no reader.
    // periphery:ignore
    let path: [String]
}

/// A response key of the root query fields that the rewrite moved into a `board { … }` field that it added (plan.md
/// §4.5). All the moved fields with this key are in `board` fields with the same key.
private struct RootMove: Sendable {
    /// The response key of the `board` field that the rewrite added.
    let boardKey: String

    /// The response key of the moved field, as the caller wrote it.
    let fieldKey: String
}

/// A document after the name rewrite (plan.md §4.5).
struct RewrittenDocument: Sendable {
    /// The text of the document with the canonical names. Validation and execution read this text.
    let text: String

    /// The changes of the rewrite, in the order of the document.
    let rewrites: [NameRewrite]

    /// One error for each name that matches two or more names. When the list is not empty, the document must not
    /// run.
    let ties: [GraphQLError]

    /// The text of the document as the caller wrote it.
    fileprivate let source: String

    /// The text edits that change ``source`` to ``text``, in the order of their offsets.
    fileprivate let edits: [TextEdit]

    /// The root query fields that the rewrite moved into `board`: one move for each response key.
    fileprivate let rootMoves: [RootMove]

    /// Gives the result of the execution of ``text`` in the form of the document that the caller wrote.
    ///
    /// The result of each moved root query field goes back to the root of `data`, so that the caller finds it under
    /// the key that it wrote: `data.tasks`, not `data.<key>.tasks`. The path of an error in a moved field loses the
    /// key of the added `board` field the same way. The location of each error is in the text that the caller
    /// wrote, not in ``text``.
    ///
    /// - Parameter result: The result of the execution of ``text``.
    /// - Returns: The result with the keys and the locations of the document of the caller.
    func callerResult(from result: GraphQLResult) -> GraphQLResult {
        guard !edits.isEmpty else {
            return result
        }
        let moves = Dictionary(uniqueKeysWithValues: rootMoves.map { move in (move.boardKey, move.fieldKey) })
        return GraphQLResult(
            data: result.data.map { data in Self.restoring(data, moving: moves) },
            errors: result.errors.map { error in callerError(from: error, moving: moves) }
        )
    }

    /// Replaces each added `board` field of `data` with the moved field that it holds, at the same place.
    ///
    /// - Parameters:
    ///   - data: The `data` of the result.
    ///   - moves: The key of the moved field for the key of each added `board` field.
    /// - Returns: The `data` with the moved fields at the root.
    private static func restoring(_ data: Map, moving moves: [String: String]) -> Map {
        guard case .dictionary(let fields) = data else {
            return data
        }
        let restored = fields.map { key, value in
            guard let fieldKey = moves[key] else {
                return (key, value)
            }
            return (fieldKey, value.dictionary?[fieldKey] ?? .null)
        }
        return .dictionary(OrderedDictionary(restored) { first, _ in first })
    }

    /// Gives an error of the execution of ``text`` with the path and the locations of the document of the caller.
    ///
    /// - Parameters:
    ///   - error: An error of the result.
    ///   - moves: The key of the moved field for the key of each added `board` field.
    /// - Returns: The error without the key of an added `board` field at the start of its path, and with each
    ///   location in ``source``.
    private func callerError(from error: GraphQLError, moving moves: [String: String]) -> GraphQLError {
        let elements = error.path.elements
        let path = if case .key(let key)? = elements.first, moves[key] != nil { Array(elements.dropFirst()) } else {
            elements
        }
        return GraphQLError(
            message: error.message,
            nodes: error.nodes,
            source: error.positions.isEmpty ? error.source : Source(body: source),
            positions: error.positions.map(sourceOffset(ofTextOffset:)),
            path: IndexPath(path),
            originalError: error.originalError,
            extensions: error.extensions
        )
    }

    /// Gives the UTF-8 offset in ``source`` of a UTF-8 offset in ``text``. An offset in the replacement of an edit
    /// gives the start of the edit.
    ///
    /// - Parameter offset: The offset in ``text``.
    /// - Returns: The offset in ``source``.
    private func sourceOffset(ofTextOffset offset: Int) -> Int {
        var shift = 0
        for edit in edits {
            let start = edit.range.lowerBound + shift
            guard offset >= start else {
                break
            }
            let replacementLength = edit.replacement.utf8.count
            guard offset >= start + replacementLength else {
                return edit.range.lowerBound
            }
            shift += replacementLength - edit.range.count
        }
        return offset - shift
    }
}

/// Changes each name of a parsed document that the schema does not have to its canonical name (plan.md §4.5, §12
/// items 14 and 16).
///
/// The rewrite reads each name at its position: a top-level mutation, a field in a selection, an argument, an `input`
/// field, and an enum value. ``NameMatcher`` gives the canonical name. A field keeps its response key: the rewrite
/// adds the name of the caller as a GraphQL alias, and keeps an alias that the caller wrote. A root query field that
/// only `Board` has moves into a `board { … }` field, also in an inline fragment or a fragment definition on the
/// query type. A name with no match stays as it is, so that validation gives the "did you mean" error.
///
/// The nodes of the GraphQL syntax tree cannot be made outside the GraphQL module. Thus the rewrite changes the text
/// of the document at the places that the parse gives, and the engine parses the new text again.
struct DocumentRewriter {
    /// The schema whose names are canonical.
    private let schema: GraphQLSchema

    /// Makes a rewriter for a schema.
    ///
    /// - Parameter schema: The schema whose names are canonical.
    init(for schema: GraphQLSchema) {
        self.schema = schema
    }

    /// Rewrites the names of a document.
    ///
    /// - Parameter source: The text of the document.
    /// - Returns: The rewritten document.
    /// - Throws: A `GraphQLError` when the document does not parse, or an error from the schema when a type gives
    ///   no fields.
    func rewrittenDocument(from source: String) throws -> RewrittenDocument {
        var walk = RewriteWalk(schema: schema)
        try walk.visit(try parse(source: source))
        let edits = TextEdit.inOffsetOrder(walk.edits)
        return RewrittenDocument(
            text: source.applying(edits),
            rewrites: walk.rewrites,
            ties: walk.ties,
            source: source,
            edits: edits,
            rootMoves: walk.rootMoves
        )
    }
}

// MARK: - Walk

/// One change of the text of a document: the bytes of a range get a replacement.
private struct TextEdit {
    /// The range of UTF-8 offsets in the text. An empty range inserts the replacement.
    let range: Range<Int>

    /// The new text of the range.
    let replacement: String

    /// Sorts edits by the start of their ranges. Two edits at the same offset keep their order.
    ///
    /// - Parameter edits: The edits, in the order that the walk found them.
    /// - Returns: The edits in the order of their offsets.
    static func inOffsetOrder(_ edits: [TextEdit]) -> [TextEdit] {
        edits.enumerated()
            .sorted { lhs, rhs in
                (lhs.element.range.lowerBound, lhs.offset) < (rhs.element.range.lowerBound, rhs.offset)
            }
            .map(\.element)
    }
}

/// A name that the caller wrote, with its place in the document.
private struct WrittenName {
    /// The name as the caller wrote it.
    let text: String

    /// The node of the name, for the location of an error.
    let node: any GraphQL.Node

    /// The range of UTF-8 offsets of the name in the text, or `nil` when the parse gave no location.
    let range: Range<Int>?

    /// Makes the written name of a name node.
    ///
    /// - Parameter name: The name node.
    init(_ name: Name) {
        text = name.value
        node = name
        range = name.loc.map { location in location.start..<location.end }
    }

    /// Makes the written name of an enum value node.
    ///
    /// - Parameter value: The enum value node.
    init(_ value: EnumValue) {
        text = value.value
        node = value
        range = value.loc.map { location in location.start..<location.end }
    }
}

/// The state of one walk over a document: the text edits and the changes that it found.
private struct RewriteWalk {
    /// The name of the root query field that holds the fields of a board.
    static let boardField = "board"

    /// The start of the response key of a `board` field that the rewrite adds. The number of the root move follows it.
    static let rootMoveKeyPrefix = "_kanbanRoot"

    /// The start of the name of an introspection field, for example `__typename`. The rewrite does not change it.
    static let introspectionPrefix = "__"

    /// The schema whose names are canonical.
    let schema: GraphQLSchema

    /// The text edits, in the order that the walk found them.
    private(set) var edits: [TextEdit] = []

    /// The changes of the rewrite.
    private(set) var rewrites: [NameRewrite] = []

    /// One error for each name with a tie.
    private(set) var ties: [GraphQLError] = []

    /// The root query fields that the walk moved into `board`: one move for each response key.
    private(set) var rootMoves: [RootMove] = []

    /// Makes an empty walk.
    ///
    /// - Parameter schema: The schema whose names are canonical.
    init(schema: GraphQLSchema) {
        self.schema = schema
    }

    /// Visits each operation and each fragment definition of a document.
    ///
    /// - Parameter document: The parsed document.
    /// - Throws: An error from the schema when a type gives no fields.
    mutating func visit(_ document: Document) throws {
        for definition in document.definitions {
            switch definition {
            case let operation as OperationDefinition:
                try visit(operation)
            case let fragment as FragmentDefinition:
                let type = schema.getType(name: fragment.typeCondition.name.value)
                try visitSelections(of: fragment.selectionSet, on: type, at: [fragment.name.value], as: .anyOther)
            default:
                continue
            }
        }
    }

    /// Visits the root fields of an operation.
    ///
    /// - Parameter operation: The operation.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func visit(_ operation: OperationDefinition) throws {
        let (root, position): (GraphQLObjectType?, NamePosition) = switch operation.operation {
        case .query: (schema.queryType, .anyOther)
        case .mutation: (schema.mutationType, .topLevelMutation)
        case .subscription: (schema.subscriptionType, .anyOther)
        }
        try visitSelections(of: operation.selectionSet, on: root, at: [], as: position)
    }

    /// Visits each selection of a selection set.
    ///
    /// When the selections read the query type, a field that only `Board` has moves into `board`. This applies to
    /// the root fields of a `query`, and to the fields of an inline fragment or a fragment definition on the query
    /// type. No field gives the query type, so these fields are always at the root of `data`.
    ///
    /// - Parameters:
    ///   - selectionSet: The selection set.
    ///   - parent: The type that the selections read, or `nil` when the type is not known.
    ///   - path: The path to the selection set.
    ///   - position: The position of a field of the selection set.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func visitSelections(
        of selectionSet: SelectionSet,
        on parent: (any GraphQLNamedType)?,
        at path: [String],
        as position: NamePosition
    ) throws {
        let readsQuery = schema.queryType.map { query in parent?.name == query.name } ?? false
        for selection in selectionSet.selections {
            if readsQuery, let field = selection as? Field, try moveIntoBoard(field, at: path) {
                continue
            }
            try visit(selection, on: parent, at: path, as: position)
        }
    }

    /// Visits one selection: a field, or the selections of an inline fragment. A fragment spread has nothing to
    /// change; the walk visits its fragment definition.
    ///
    /// - Parameters:
    ///   - selection: The selection.
    ///   - parent: The type that the selection reads, or `nil` when the type is not known.
    ///   - path: The path to the selection.
    ///   - position: The position of a field of the selection.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func visit(
        _ selection: any Selection,
        on parent: (any GraphQLNamedType)?,
        at path: [String],
        as position: NamePosition
    ) throws {
        switch selection {
        case let field as Field:
            try visit(field, on: parent, at: path, as: position)
        case let fragment as InlineFragment:
            let type = fragment.typeCondition.map { condition in schema.getType(name: condition.name.value) } ?? parent
            try visitSelections(of: fragment.selectionSet, on: type, at: path, as: position)
        default:
            return
        }
    }

    /// Visits a field: gives it its canonical name with the response key of the caller, then visits its arguments
    /// and its selection.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - parent: The type that has the field, or `nil` when the type is not known.
    ///   - path: The path to the field.
    ///   - position: The position of the field.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func visit(
        _ field: Field,
        on parent: (any GraphQLNamedType)?,
        at path: [String],
        as position: NamePosition
    ) throws {
        guard !field.name.value.hasPrefix(Self.introspectionPrefix), let fields = try Self.fields(of: parent),
              let canonical = canonicalName(of: WrittenName(field.name), among: Self.candidates(fields), at: position),
              let definition = fields[canonical]
        else {
            return
        }
        let fieldPath = path + [field.alias?.value ?? field.name.value]
        rename(field, to: canonical, recordingAs: canonical, at: fieldPath)
        try visitBody(of: field, as: definition, at: fieldPath)
    }

    /// Moves a root query field into a `board { … }` field when the query type has no field with the name, and
    /// `Board` has one.
    ///
    /// - Parameters:
    ///   - field: A field that reads the query type.
    ///   - path: The path to the field: empty in an operation, or the name of a fragment definition.
    /// - Returns: `true` when the walk moved the field.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func moveIntoBoard(_ field: Field, at path: [String]) throws -> Bool {
        let name = WrittenName(field.name)
        guard !name.text.hasPrefix(Self.introspectionPrefix), let rootFields = try Self.fields(of: schema.queryType),
              NameMatcher.match(for: name.text, among: Self.candidates(rootFields), at: .anyOther) == .notFound,
              let board = rootFields[Self.boardField],
              let boardFields = try Self.fields(of: getNamedType(type: board.type)),
              let canonical = canonicalName(of: name, among: Self.candidates(boardFields), at: .anyOther),
              let definition = boardFields[canonical], let start = field.loc?.start,
              let end = field.name.loc?.startToken.fieldEnd.end
        else {
            return false
        }
        let fieldKey = field.alias?.value ?? name.text
        let fieldPath = path + [fieldKey]
        let boardKey = boardKey(forMoving: fieldKey)
        edits.append(TextEdit(range: start..<start, replacement: "\(boardKey): \(Self.boardField) { "))
        rename(field, to: canonical, recordingAs: "\(Self.boardField).\(canonical)", at: fieldPath)
        edits.append(TextEdit(range: end..<end, replacement: " }"))
        try visitBody(of: field, as: definition, at: fieldPath)
        return true
    }

    /// Gives the response key of the `board` field that holds a moved root query field.
    ///
    /// All the moved fields with the same response key get the same `board` key. Thus GraphQL merges the added
    /// `board` fields, and then the moved fields in them, the same as it merges the fields that the caller wrote.
    ///
    /// - Parameter fieldKey: The response key of the moved field, as the caller wrote it.
    /// - Returns: The `board` key of an earlier move of `fieldKey`, or a new key that the walk records.
    private mutating func boardKey(forMoving fieldKey: String) -> String {
        if let move = rootMoves.first(where: { move in move.fieldKey == fieldKey }) {
            return move.boardKey
        }
        let boardKey = Self.rootMoveKeyPrefix + String(rootMoves.count)
        rootMoves.append(RootMove(boardKey: boardKey, fieldKey: fieldKey))
        return boardKey
    }

    /// Visits the arguments and the selection of a field.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - definition: The schema definition of the field.
    ///   - path: The path to the field.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func visitBody(of field: Field, as definition: GraphQLField, at path: [String]) throws {
        let arguments = field.arguments.map { argument in (argument.name, argument.value) }
        try visitNamedValues(arguments, typedBy: definition.args.mapValues(\.type), at: path)
        if let selectionSet = field.selectionSet {
            try visitSelections(of: selectionSet, on: getNamedType(type: definition.type), at: path, as: .anyOther)
        }
    }

    /// Visits the arguments of a field, or the fields of an `input` object: gives each name its canonical name, and
    /// visits each value.
    ///
    /// - Parameters:
    ///   - items: The name and the value of each argument or `input` field.
    ///   - types: The input type of each canonical name.
    ///   - path: The path to the field or to the `input` object.
    /// - Throws: An error from the schema when a type gives no fields.
    private mutating func visitNamedValues(
        _ items: [(Name, any GraphQL.Value)],
        typedBy types: OrderedDictionary<String, any GraphQLInputType>,
        at path: [String]
    ) throws {
        let candidates = types.keys.map(CanonicalName.init(field:))
        for (name, value) in items {
            let written = WrittenName(name)
            guard let canonical = canonicalName(of: written, among: candidates, at: .anyOther),
                  let type = types[canonical]
            else {
                continue
            }
            replace(written, with: canonical, recordingAs: canonical, at: path + [written.text])
            try visitValue(value, ofType: getNamedType(type: type), at: path + [written.text])
        }
    }

    /// Visits a value of an argument or an `input` field: each item of a list, each field of an `input` object, and
    /// an enum value.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - type: The named input type of the value, or `nil` when the type is not known.
    ///   - path: The path to the value.
    /// - Throws: An error from the schema when an `input` type gives no fields.
    private mutating func visitValue(
        _ value: any GraphQL.Value,
        ofType type: (any GraphQLNamedType)?,
        at path: [String]
    ) throws {
        switch (value, type) {
        case (let list as ListValue, _):
            for item in list.values {
                try visitValue(item, ofType: type, at: path)
            }
        case (let object as ObjectValue, let inputType as GraphQLInputObjectType):
            let fields = object.fields.map { field in (field.name, field.value) }
            try visitNamedValues(fields, typedBy: try inputType.fields().mapValues(\.type), at: path)
        case (let enumValue as EnumValue, let enumType as GraphQLEnumType):
            let written = WrittenName(enumValue)
            let candidates = enumType.values.map { value in CanonicalName(name: value.name, aliases: []) }
            if let canonical = canonicalName(of: written, among: candidates, at: .anyOther) {
                replace(written, with: canonical, recordingAs: canonical, at: path + [written.text])
            }
        default:
            return
        }
    }

    /// Gives the canonical name of a name, and records an error when the name has a tie.
    ///
    /// - Parameters:
    ///   - name: The name that the caller wrote.
    ///   - candidates: The valid names at the position of the name.
    ///   - position: The position of the name.
    /// - Returns: The canonical name, or `nil` for a tie or no match.
    private mutating func canonicalName(
        of name: WrittenName,
        among candidates: [CanonicalName],
        at position: NamePosition
    ) -> String? {
        switch NameMatcher.match(for: name.text, among: candidates, at: position) {
        case .found(let canonical):
            return canonical
        case .tie(let matches):
            let tie = KanbanError.ambiguousName(name: name.text, matches: matches)
            ties.append(GraphQLError(message: tie.message, nodes: [name.node]).coded(as: tie))
            return nil
        case .notFound:
            return nil
        }
    }

    /// Gives a field its canonical name and keeps the response key of the caller: the name of the caller becomes
    /// the alias when the caller wrote no alias.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - canonical: The canonical name.
    ///   - target: The `to` text of the change.
    ///   - path: The path to the field.
    private mutating func rename(_ field: Field, to canonical: String, recordingAs target: String, at path: [String]) {
        let written = WrittenName(field.name)
        let keepsKey = field.alias != nil || canonical == written.text
        replace(written, with: keepsKey ? canonical : "\(written.text): \(canonical)", recordingAs: target, at: path)
    }

    /// Replaces a name with a new text, and records the change, when the name is not canonical.
    ///
    /// - Parameters:
    ///   - name: The name that the caller wrote.
    ///   - replacement: The new text of the name.
    ///   - target: The `to` text of the change. When it is the name of the caller, nothing changes.
    ///   - path: The path to the name.
    private mutating func replace(
        _ name: WrittenName,
        with replacement: String,
        recordingAs target: String,
        at path: [String]
    ) {
        guard target != name.text, let range = name.range else {
            return
        }
        if replacement != name.text {
            edits.append(TextEdit(range: range, replacement: replacement))
        }
        rewrites.append(NameRewrite(from: name.text, to: target, path: path))
    }

    /// Gives the fields of an object type or an interface type.
    ///
    /// - Parameter type: The type, or `nil` when the type is not known.
    /// - Returns: The fields, or `nil` for a type with no fields.
    /// - Throws: An error from the schema when the type gives no fields.
    private static func fields(of type: (any GraphQLNamedType)?) throws -> GraphQLFieldMap? {
        switch type {
        case let object as GraphQLObjectType:
            try object.fields()
        case let interface as GraphQLInterfaceType:
            try interface.fields()
        default:
            nil
        }
    }

    /// Gives the canonical names of the fields of a type, each with its aliases.
    ///
    /// - Parameter fields: The fields.
    /// - Returns: The candidates of the name matcher.
    private static func candidates(_ fields: GraphQLFieldMap) -> [CanonicalName] {
        fields.keys.map(CanonicalName.init(field:))
    }
}

extension Token {
    /// The change of the bracket depth at the token: 1 for an opening bracket, -1 for a closing bracket, else 0.
    fileprivate var depthChange: Int {
        switch kind {
        case .openingParenthesis, .openingBracket, .openingBrace:
            1
        case .closingParenthesis, .closingBracket, .closingBrace:
            -1
        default:
            0
        }
    }

    /// The next token that is not a comment, or `nil` at the end of the document.
    fileprivate var nextSignificant: Token? {
        var token = next
        while token?.kind == .comment {
            token = token?.next
        }
        return token
    }

    /// The token that closes the group that this opening bracket starts.
    fileprivate var closingToken: Token {
        var depth = depthChange
        var token = self
        while depth > 0, let following = token.next {
            depth += following.depthChange
            token = following
        }
        return token
    }

    /// The last token of the field whose name is this token: the name, or the end of its arguments, its directives,
    /// or its selection set.
    ///
    /// The parse gives each field a location that ends at its name, so the walk finds the end from the tokens.
    fileprivate var fieldEnd: Token {
        var last = self
        while let current = last.nextSignificant {
            switch current.kind {
            case .openingParenthesis:
                last = current.closingToken
            case .at:
                last = current.nextSignificant ?? current
            case .openingBrace:
                return current.closingToken
            default:
                return last
            }
        }
        return last
    }
}

extension String {
    /// Applies text edits to the text. The edits do not overlap.
    ///
    /// - Parameter edits: The edits, at UTF-8 offsets of the text, in the order of their offsets.
    /// - Returns: The new text.
    fileprivate func applying(_ edits: [TextEdit]) -> String {
        let bytes = Array(utf8)
        let starts = [0] + edits.map(\.range.upperBound)
        let pieces = zip(starts, edits).map { start, edit in
            String(decoding: bytes[start..<edit.range.lowerBound], as: UTF8.self) + edit.replacement
        }
        return pieces.joined() + String(decoding: bytes[(starts.last ?? 0)...], as: UTF8.self)
    }
}
