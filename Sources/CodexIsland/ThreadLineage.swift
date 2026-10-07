import Foundation

enum ThreadLineage {
    static func parentID(in source: String) -> String? {
        guard let data = source.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findParent(in: object)
    }

    private static func findParent(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            if let id = object["parent_thread_id"] as? String, !id.isEmpty { return id }
            for child in object.values {
                if let id = findParent(in: child) { return id }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let id = findParent(in: child) { return id }
            }
        }
        return nil
    }

    static func rootID(for childID: String, parents: [String: String]) -> String? {
        var current = childID
        var visited: Set<String> = [childID]
        guard parents[current] != nil else { return nil }
        while let parent = parents[current] {
            guard visited.insert(parent).inserted else { return nil }
            current = parent
        }
        return current
    }
}
