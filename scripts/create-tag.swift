#!/usr/bin/env swift

import Foundation

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

@discardableResult
func git(_ args: String...) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    let output = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = output
    process.standardError = errorPipe
    do {
        try process.run()
    } catch {
        die("git \(args.joined(separator: " ")): \(error)")
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        die("git \(args.joined(separator: " ")) failed:\n\(message)")
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func tagExists(_ tag: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--verify", "--quiet", "refs/tags/\(tag)"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

enum Bump: String {
    case patch, minor, major
}

guard CommandLine.arguments.count == 2, let bump = Bump(rawValue: CommandLine.arguments[1]) else {
    die("Usage: create-tag <patch|minor|major>")
}

let dirty = git("status", "--porcelain")
if !dirty.isEmpty {
    die("Working tree is dirty:\n\(dirty)")
}

let branch = git("rev-parse", "--abbrev-ref", "HEAD")
if branch != "master" {
    die("Not on master (on \(branch))")
}

git("fetch", "--quiet", "origin", "master")
git("fetch", "--quiet", "--tags", "origin")
if git("rev-parse", "HEAD") != git("rev-parse", "origin/master") {
    die("Local master is not in sync with origin/master")
}

let tags = git("tag", "--list", "v[0-9]*.[0-9]*.[0-9]*", "--sort=-v:refname")
let latest = tags.split(separator: "\n").map(String.init).first {
    $0.range(of: #"^v\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
}

var (major, minor, patch) = (0, 0, 0)
if let latest {
    let parts = latest.dropFirst().split(separator: ".").compactMap { Int($0) }
    (major, minor, patch) = (parts[0], parts[1], parts[2])
}

switch bump {
case .major: (major, minor, patch) = (major + 1, 0, 0)
case .minor: (major, minor, patch) = (major, minor + 1, 0)
case .patch: (major, minor, patch) = (major, minor, patch + 1)
}

let tag = "v\(major).\(minor).\(patch)"
if tagExists(tag) {
    die("Tag \(tag) already exists")
}

git("tag", "-a", tag, "-m", tag)
git("push", "origin", tag)

print("Tagged and pushed \(tag) — release CI is now building")
