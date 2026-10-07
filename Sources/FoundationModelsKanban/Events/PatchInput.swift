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
        guard case .string(let text) = map else {
            throw .refMismatch(property: name)
        }
        do throws(NodeRefError) {
            self = .ref(try StoredRef(parsing: text))
        } catch {
            throw .invalidRef(error)
        }
    }
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
    /// - Parameter decoder: The decoder that holds the patch.
    /// - Throws: A `DecodingError` when a part has the wrong shape. A ``NodeRefError`` when a ref is not valid.
    ///   ``EventError/typeMismatch(node:type:)`` when `type` is not the type of `node`. An ``EventError`` from
    ///   ``init(node:set:unset:add:remove:delete:edit:)`` or ``PatchValue/init(ofProperty:from:)``.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let node = try container.decode(LocalRef.self, forKey: .node)
        let type = try container.decode(PatchNodeType.self, forKey: .type)
        guard type == node.nodeType else {
            throw EventError.typeMismatch(node: node, type: type)
        }
        let setMaps = try container.decodeIfPresent([String: Map].self, forKey: .set) ?? [:]
        let set = try Dictionary(
            uniqueKeysWithValues: setMaps.map { name, value in (name, try PatchValue(ofProperty: name, from: value)) }
        )
        try self.init(
            node: node,
            set: set,
            unset: container.decodeIfPresent([String].self, forKey: .unset) ?? [],
            add: container.decodeIfPresent([String: [StoredRef]].self, forKey: .add) ?? [:],
            remove: container.decodeIfPresent([String: [StoredRef]].self, forKey: .remove) ?? [:],
            delete: container.decodeIfPresent(Bool.self, forKey: .delete),
            edit: container.decodeIfPresent(PatchEdit.self, forKey: .edit)
        )
    }

    /// Writes the JSON form of the patch, ``map``.
    ///
    /// - Parameter encoder: The encoder that gets the patch.
    /// - Throws: An error from the encoder, for example for a number that JSON cannot hold.
    func encode(to encoder: any Encoder) throws {
        try map.encode(to: encoder)
    }
}
