import GraphQL
import OrderedCollections

/// One value that the `set` part of a patch writes to a property (plan.md §5.1).
///
/// A ref is in the stored form (``StoredRef``), so that the log never holds the key of its own board. The name of
/// the property decides the kind of value: each name in ``PatchInput/refProperties`` holds a ref, and each other name
/// holds a plain JSON value.
enum PatchValue: Hashable, Sendable {
    /// A ref to one node, for example the column of a task.
    case ref(StoredRef)

    /// A plain JSON value, for example a title, an ordinal, or a color.
    case json(Map)

    /// The value as JSON: a ref gives its stored text.
    var map: Map {
        switch self {
        case .ref(let ref): .string(ref.description)
        case .json(let value): value
        }
    }

    /// Tells if the value is a ref.
    var isRef: Bool {
        switch self {
        case .ref: true
        case .json: false
        }
    }

    /// Reads the value of a property from its JSON form.
    ///
    /// - Parameters:
    ///   - name: The name of the property. It decides if the value is a ref.
    ///   - map: The JSON value.
    /// - Throws: ``EventError/refMismatch(property:)`` when the property holds a ref and the value is not text.
    ///   ``EventError/invalidRef(_:)`` when the text is not a stored ref.
    init(ofProperty name: String, from map: Map) throws(EventError) {
        guard PatchInput.refProperties.contains(name) else {
            self = .json(map)
            return
        }
        self = .ref(try StoredRef(ofProperty: name, from: map))
    }
}

extension StoredRef {
    /// Reads one ref of a property from its JSON form: the stored text of the ref.
    ///
    /// - Parameters:
    ///   - name: The name of the property.
    ///   - map: The JSON value.
    /// - Throws: ``EventError/refMismatch(property:)`` when the value is not text. ``EventError/invalidRef(_:)`` when
    ///   the text is not a stored ref.
    init(ofProperty name: String, from map: Map) throws(EventError) {
        guard case .string(let text) = map else {
            throw .refMismatch(property: name)
        }
        do throws(NodeRefError) {
            self = try StoredRef(parsing: text)
        } catch {
            throw .invalidRef(error)
        }
    }
}

/// What the decode of a patch does with one value that does not decode: a `set` value, a member of an `add` or a
/// `remove` list, a name of the `unset` list, the `delete` flag, or the `edit`.
///
/// The `node` and the `type` of a patch are not values. When one of them does not decode, the decode always throws.
enum PatchValuePolicy: Sendable {
    /// The decode throws, so the whole patch is refused. The internal `patch` mutation uses it.
    case refuse

    /// The decode records the value with swift-log, and leaves it out of the patch. Replay uses it, because replay
    /// never refuses a log, and a schema change needs no upgrade step (plan.md §3.3, rule 7).
    case skip

    /// The policy of the patch decodes that run now. ``Event/init(parsing:policy:)`` sets it for the decode of one
    /// line. The default is ``refuse``.
    @TaskLocal static var current: PatchValuePolicy = .refuse
}

/// The `edit` part of a patch: a unified diff for the Markdown body of the node (plan.md §5.5).
struct PatchEdit: Decodable, Hashable, Sendable {
    /// The unified diff from the current body to the new body.
    let body: String

    /// The edit as a JSON object: `{"body": "<unified diff>"}`.
    var map: Map {
        ["body": .string(body)]
    }
}

/// The `input` of the internal `patch` mutation: one property patch on one node (plan.md §5.1).
///
/// Each part is optional, except `node` and `type`. Each ref is in the stored form: the node is a ``LocalRef``, and
/// each ref value is a ``StoredRef``. Thus, a patch never holds the key of its own board (plan.md §12 item 18). A
/// part that is empty is not in the JSON form.
struct PatchInput: Hashable, Sendable {
    /// The properties whose value is one ref: `column` and `task` of a task or a comment, `author` of a comment, and
    /// `renamedTo` of a tag (plan.md §3.1, §6.2).
    static let refProperties: Set<String> = ["column", "task", "author", "renamedTo"]

    /// The time values. Replay derives them from the envelope `at`, so no patch can set them (plan.md §5.3, §12
    /// item 20).
    static let timeProperties: Set<String> = ["created", "updated", "deleted", "started", "completed"]

    /// The local ref of the node that the patch changes. The node is always in the board of the log.
    let node: LocalRef

    /// The properties to write. A value replaces the old value.
    let set: [String: PatchValue]

    /// The names of the properties to clear.
    let unset: [String]

    /// The refs to add to set-valued properties, for example `tags`, `assignees`, and `dependsOn`.
    let add: [String: [StoredRef]]

    /// The refs to remove from set-valued properties.
    let remove: [String: [StoredRef]]

    /// `true` makes a tombstone. `false` removes the tombstone. `nil` does not change it.
    let delete: Bool?

    /// The diff for the Markdown body of the node, or `nil` when the body does not change.
    let edit: PatchEdit?

    /// The type of the node. It is the type of the ``node`` ref.
    var type: PatchNodeType {
        node.nodeType
    }

    /// Makes a patch on one node.
    ///
    /// - Parameters:
    ///   - node: The local ref of the node.
    ///   - set: The properties to write.
    ///   - unset: The names of the properties to clear.
    ///   - add: The refs to add to set-valued properties.
    ///   - remove: The refs to remove from set-valued properties.
    ///   - delete: `true` to make a tombstone, `false` to remove it, or `nil` for no change.
    ///   - edit: The diff for the body, or `nil` for no change.
    /// - Throws: ``EventError/timeProperty(name:)`` when `set` names a time value.
    ///   ``EventError/refMismatch(property:)`` when a ref property gets a plain value, or a plain property gets a
    ///   ref.
    init(
        node: LocalRef,
        set: [String: PatchValue] = [:],
        unset: [String] = [],
        add: [String: [StoredRef]] = [:],
        remove: [String: [StoredRef]] = [:],
        delete: Bool? = nil,
        edit: PatchEdit? = nil
    ) throws(EventError) {
        for (name, value) in set.sorted(by: { $0.key < $1.key }) {
            try Self.check(value, ofProperty: name)
        }
        self.node = node
        self.set = set
        self.unset = unset
        self.add = add
        self.remove = remove
        self.delete = delete
        self.edit = edit
    }

    /// Checks that a property can get a value with `set`.
    ///
    /// - Parameters:
    ///   - value: The value to write.
    ///   - name: The name of the property.
    /// - Throws: ``EventError/timeProperty(name:)`` when the property is a time value.
    ///   ``EventError/refMismatch(property:)`` when the kind of value is not the kind of the property.
    private static func check(_ value: PatchValue, ofProperty name: String) throws(EventError) {
        guard !timeProperties.contains(name) else {
            throw .timeProperty(name: name)
        }
        guard value.isRef == refProperties.contains(name) else {
            throw .refMismatch(property: name)
        }
    }
}

// MARK: - JSON form

extension PatchInput {
    /// The text of the node ref.
    var nodeText: String {
        node.description
    }

    /// The `set` part as a JSON object, or `nil` when the patch sets nothing.
    var setMap: Map? {
        Self.object(of: set, valueMap: \.map)
    }

    /// The `unset` part, or `nil` when the patch clears nothing.
    var unsetList: [String]? {
        unset.isEmpty ? nil : unset
    }

    /// The `add` part as a JSON object, or `nil` when the patch adds nothing.
    var addMap: Map? {
        Self.object(of: add, valueMap: Self.refList)
    }

    /// The `remove` part as a JSON object, or `nil` when the patch removes nothing.
    var removeMap: Map? {
        Self.object(of: remove, valueMap: Self.refList)
    }

    /// The `edit` part as a JSON object, or `nil` when the body does not change.
    var editMap: Map? {
        edit?.map
    }

    /// The patch as a JSON value. A part that is empty is not in the value.
    ///
    /// The value is made directly, not with `MapEncoder`, because `MapEncoder` changes each `Bool` to a number.
    var map: Map {
        [
            "node": .string(nodeText),
            "type": .string(type.rawValue),
            "set": setMap ?? .undefined,
            "unset": unsetList.map { .array($0.map(Map.string)) } ?? .undefined,
            "add": addMap ?? .undefined,
            "remove": removeMap ?? .undefined,
            "delete": delete.map(Map.bool) ?? .undefined,
            "edit": editMap ?? .undefined,
        ]
    }

    /// Makes a JSON object with its keys in sorted order.
    ///
    /// - Parameters:
    ///   - fields: The fields of the object.
    ///   - valueMap: Gives the JSON form of one value.
    /// - Returns: The object, or `nil` when there are no fields.
    private static func object<Value>(of fields: [String: Value], valueMap: (Value) -> Map) -> Map? {
        guard !fields.isEmpty else {
            return nil
        }
        let sorted = fields.sorted { $0.key < $1.key }.map { ($0.key, valueMap($0.value)) }
        return .dictionary(OrderedDictionary(uniqueKeysWithValues: sorted))
    }

    /// Gives the JSON form of a list of refs: a list of their stored texts.
    ///
    /// - Parameter refs: The refs.
    /// - Returns: The JSON list.
    private static func refList(_ refs: [StoredRef]) -> Map {
        .array(refs.map { .string($0.description) })
    }
}

// MARK: - Codable

extension PatchInput: Codable {
    /// The keys of the parts of a patch.
    private enum CodingKeys: String, CodingKey {
        case node, type, set, unset, add, remove, delete, edit
    }

    /// Reads a patch from its JSON form: a log line, or the GraphQL arguments of the `patch` mutation.
    ///
    /// The `node` and the `type` always decode first. Then each value of the patch decodes by itself, with the
    /// ``PatchValuePolicy/current`` policy: with ``PatchValuePolicy/skip``, a value that does not decode is left out,
    /// and the other values stay in the patch.
    ///
    /// - Parameter decoder: The decoder that holds the patch.
    /// - Throws: A `DecodingError` when the patch, its `node`, or its `type` has the wrong shape, and with
    ///   ``PatchValuePolicy/refuse`` also when a value has the wrong shape. A ``NodeRefError`` when the node ref is
    ///   not valid. ``EventError/typeMismatch(node:type:)`` when `type` is not the type of `node`. With
    ///   ``PatchValuePolicy/refuse``, an ``EventError`` from ``PatchValue/init(ofProperty:from:)``,
    ///   ``StoredRef/init(ofProperty:from:)``, or ``init(node:set:unset:add:remove:delete:edit:)``.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let node = try container.decode(LocalRef.self, forKey: .node)
        let type = try container.decode(PatchNodeType.self, forKey: .type)
        guard type == node.nodeType else {
            throw EventError.typeMismatch(node: node, type: type)
        }
        let reader = PartReader(container: container, node: node, policy: PatchValuePolicy.current)
        try self.init(
            node: node,
            set: reader.readSet(),
            unset: reader.readUnset(),
            add: reader.readMembers(forKey: .add),
            remove: reader.readMembers(forKey: .remove),
            delete: reader.readPart(Bool.self, forKey: .delete),
            edit: reader.readPart(PatchEdit.self, forKey: .edit)
        )
    }

    /// Reads the value of one property of the `set` part, and checks that a patch can set the property.
    ///
    /// - Parameters:
    ///   - name: The name of the property.
    ///   - map: The JSON value.
    /// - Returns: The value.
    /// - Throws: An ``EventError`` from ``PatchValue/init(ofProperty:from:)`` or from the check of a `set` value.
    private static func setValue(ofProperty name: String, from map: Map) throws(EventError) -> PatchValue {
        let value = try PatchValue(ofProperty: name, from: map)
        try check(value, ofProperty: name)
        return value
    }

    /// Reads the parts of a patch from its JSON form, one value at a time, with one ``PatchValuePolicy``.
    private struct PartReader {
        /// The container of the patch.
        let container: KeyedDecodingContainer<CodingKeys>

        /// The node of the patch. The record of a skipped value names it.
        let node: LocalRef

        /// What the reader does with a value that does not decode.
        let policy: PatchValuePolicy

        /// Reads one value of the patch.
        ///
        /// - Parameters:
        ///   - place: The place of the value in the patch, for example `set.column` or `add.tags[1]`. The record of
        ///     a skipped value names it.
        ///   - decode: Reads the value.
        /// - Returns: The value, or `nil` when the patch has no value. With ``PatchValuePolicy/skip``, also `nil`
        ///   when the value does not decode: the reader records it with swift-log.
        /// - Throws: With ``PatchValuePolicy/refuse``, the error of `decode`.
        func read<Value>(_ place: String, _ decode: () throws -> Value?) throws -> Value? {
            do {
                return try decode()
            } catch {
                guard policy == .skip else {
                    throw error
                }
                Log.kanban.warning(
                    "Replay skips a patch value that does not decode",
                    metadata: ["node": "\(node)", "value": "\(place)", "error": "\(error)"]
                )
                return nil
            }
        }

        /// Reads one part of the patch as a whole.
        ///
        /// - Parameters:
        ///   - type: The type of the part.
        ///   - key: The key of the part.
        /// - Returns: The part, or `nil` when the patch has no part. With ``PatchValuePolicy/skip``, also `nil` when
        ///   the part does not decode.
        /// - Throws: With ``PatchValuePolicy/refuse``, the `DecodingError` of a part that does not decode.
        func readPart<Value: Decodable>(_ type: Value.Type, forKey key: CodingKeys) throws -> Value? {
            try read(key.stringValue) { try container.decodeIfPresent(type, forKey: key) }
        }

        /// Reads the `set` part: each property by itself.
        ///
        /// - Returns: The value of each property that decodes.
        /// - Throws: With ``PatchValuePolicy/refuse``, the error of the first value that does not decode, in name
        ///   order.
        func readSet() throws -> [String: PatchValue] {
            try readProperties(forKey: .set) { name, map, place in
                try read(place) { try setValue(ofProperty: name, from: map) }
            }
        }

        /// Reads the `unset` part: each name by itself.
        ///
        /// - Returns: The names that decode, in list order.
        /// - Throws: With ``PatchValuePolicy/refuse``, the error of the first name that does not decode.
        func readUnset() throws -> [String] {
            let part = CodingKeys.unset.stringValue
            return try (readPart([Map].self, forKey: .unset) ?? []).enumerated().compactMap { index, name in
                try read("\(part)[\(index)]") {
                    guard case .string(let text) = name else {
                        throw EventError.malformed(detail: "The name at \(part)[\(index)] is not text")
                    }
                    return text
                }
            }
        }

        /// Reads the `add` or the `remove` part: each member of each property by itself.
        ///
        /// - Parameter key: The key of the part.
        /// - Returns: The members that decode, for each property whose list decodes.
        /// - Throws: With ``PatchValuePolicy/refuse``, the error of the first value that does not decode, in name
        ///   order.
        func readMembers(forKey key: CodingKeys) throws -> [String: [StoredRef]] {
            try readProperties(forKey: key) { name, list, place in
                try readMembers(ofProperty: name, from: list, at: place)
            }
        }

        /// Reads a part that holds one JSON value for each property: each property by itself, in name order.
        ///
        /// - Parameters:
        ///   - key: The key of the part.
        ///   - readValue: Reads the value of one property from its name, its JSON value, and its place in the patch.
        ///     It gives `nil` for a value that it skips.
        /// - Returns: The value of each property that `readValue` reads.
        /// - Throws: With ``PatchValuePolicy/refuse``, the `DecodingError` of a part that is not a JSON object, or
        ///   the first error of `readValue`.
        private func readProperties<Value>(
            forKey key: CodingKeys,
            _ readValue: (String, Map, String) throws -> Value?
        ) throws -> [String: Value] {
            let maps = try readPart([String: Map].self, forKey: key) ?? [:]
            let values = try maps.sorted { lhs, rhs in lhs.key < rhs.key }.compactMap { name, map in
                try readValue(name, map, "\(key.stringValue).\(name)").map { value in (name, value) }
            }
            return Dictionary(uniqueKeysWithValues: values)
        }

        /// Reads the list of members of one property.
        ///
        /// - Parameters:
        ///   - name: The name of the property.
        ///   - list: The JSON value of the list.
        ///   - place: The place of the list in the patch.
        /// - Returns: The members that decode, in list order, or `nil` when the value is not a list and the policy
        ///   is ``PatchValuePolicy/skip``.
        /// - Throws: With ``PatchValuePolicy/refuse``, ``EventError/refMismatch(property:)`` when the value is not a
        ///   list, or the error of the first member that does not decode.
        private func readMembers(ofProperty name: String, from list: Map, at place: String) throws -> [StoredRef]? {
            let items = try read(place) {
                guard case .array(let items) = list else {
                    throw EventError.refMismatch(property: name)
                }
                return items
            }
            return try items?.enumerated().compactMap { index, item in
                try read("\(place)[\(index)]") { try StoredRef(ofProperty: name, from: item) }
            }
        }
    }

    /// Writes the JSON form of the patch, ``map``.
    ///
    /// - Parameter encoder: The encoder that gets the patch.
    /// - Throws: An error from the encoder, for example for a number that JSON cannot hold.
    func encode(to encoder: any Encoder) throws {
        try map.encode(to: encoder)
    }
}
