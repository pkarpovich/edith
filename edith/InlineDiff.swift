import SwiftUI

func attributedDiff(
    original: String,
    result: String,
    insertColor: Color,
    insertForeground: Color? = nil
) -> AttributedString {
    let diff = result.difference(from: original)
    var insertedOffsets = Set<Int>()
    for change in diff.insertions {
        if case let .insert(offset, _, _) = change {
            insertedOffsets.insert(offset)
        }
    }

    let characters = Array(result)
    var attributed = AttributedString()

    var runStart = 0
    var runIsInsert = false
    var hasRun = false

    func flush(end: Int) {
        guard hasRun, runStart < end else { return }
        let segment = String(characters[runStart..<end])
        var piece = AttributedString(segment)
        if runIsInsert {
            piece.backgroundColor = insertColor
            if let insertForeground {
                piece.foregroundColor = insertForeground
            }
        }
        attributed.append(piece)
    }

    for index in characters.indices {
        let isInsert = insertedOffsets.contains(index)
        if !hasRun {
            runStart = index
            runIsInsert = isInsert
            hasRun = true
        } else if isInsert != runIsInsert {
            flush(end: index)
            runStart = index
            runIsInsert = isInsert
        }
    }
    flush(end: characters.count)

    return attributed
}
