//
//  XCProjectFile.swift
//  XcodeEdit
//
//  Created by Tom Lokhorst on 2015-08-12.
//  Copyright (c) 2015 nonstrict. All rights reserved.
//

import Foundation

public enum ProjectFileError : Error, CustomStringConvertible {
  case invalidData
  case notXcodeproj
  case missingPbxproj

  public var description: String {
    switch self {
    case .invalidData:
      return "Data in .pbxproj file not in expected format"

    case .notXcodeproj:
      return "Path is not a .xcodeproj package"

    case .missingPbxproj:
      return "project.pbxproj file missing"
    }
  }
}

public class XCProjectFile {
  public let project: PBXProject
  let fields: Fields
  var format: PropertyListSerialization.PropertyListFormat
  let allObjects = AllObjects()

  public convenience init(xcodeprojURL: URL) throws {
    let pbxprojURL = xcodeprojURL.appendingPathComponent("project.pbxproj", isDirectory: false)
    let data = try Data(contentsOf: pbxprojURL)

    try self.init(propertyListData: data)
  }

  public convenience init(propertyListData data: Data) throws {

    let options = PropertyListSerialization.MutabilityOptions()
    var format: PropertyListSerialization.PropertyListFormat = PropertyListSerialization.PropertyListFormat.binary
    let obj = try PropertyListSerialization.propertyList(from: data, options: options, format: &format)

    guard let fields = obj as? Fields else {
      throw ProjectFileError.invalidData
    }

    try self.init(fields: fields, format: format)
  }

  private init(fields: Fields, format: PropertyListSerialization.PropertyListFormat) throws {

    guard let objects = fields["objects"] as? [String: Fields] else {
      throw AllObjectsError.wrongType(key: "objects")
    }

    for (key, obj) in objects {
      allObjects.objects[Guid(key)] = try AllObjects.createObject(Guid(key), fields: obj, allObjects: allObjects)
    }

    let rootObjectId = try fields.string("rootObject")
    guard let projectFields = objects[rootObjectId] else {
      throw AllObjectsError.objectMissing(id: Guid(rootObjectId))
    }

    let project = try PBXProject(id: Guid(rootObjectId), fields: projectFields, allObjects: allObjects)
    guard let mainGroup = project.mainGroup.value else {
      throw AllObjectsError.objectMissing(id: project.mainGroup.id)
    }

    self.fields = fields
    self.format = format
    self.project = project
    self.allObjects.fullFilePaths = paths(mainGroup, prefix: "")
  }

  static func projectName(from url: URL) throws -> String {

    let subpaths = url.pathComponents
    guard let last = subpaths.last,
          let range = last.range(of: ".xcodeproj")
    else {
      throw ProjectFileError.notXcodeproj
    }

    return last.substring(to: range.lowerBound)
  }

  private func paths(_ current: PBXGroup, prefix: String) -> [Guid: Path] {

    var ps: [Guid: Path] = [:]

    let fileRefs = current.fileRefs.flatMap { $0.value }
    for file in fileRefs {
      guard let path = file.path else { continue }

      switch file.sourceTree {
      case .group:
        switch current.sourceTree {
        case .absolute:
          ps[file.id] = .absolute(prefix + "/" + path)

        case .group:
          ps[file.id] = .relativeTo(.sourceRoot, prefix + "/" + path)

        case .relativeTo(let sourceTreeFolder):
          ps[file.id] = .relativeTo(sourceTreeFolder, prefix + "/" + path)
        }

      case .absolute:
        ps[file.id] = .absolute(path)

      case let .relativeTo(sourceTreeFolder):
        ps[file.id] = .relativeTo(sourceTreeFolder, path)
      }
    }

    let subGroups = current.subGroups.flatMap { $0.value }
    for group in subGroups {
      if let path = group.path {
        
        let str: String

        switch group.sourceTree {
        case .absolute:
          str = path

        case .group:
          str = prefix + "/" + path

        case .relativeTo(.sourceRoot):
          str = path

        case .relativeTo(.buildProductsDir):
          str = path

        case .relativeTo(.developerDir):
          str = path

        case .relativeTo(.sdkRoot):
          str = path
        }

        ps += paths(group, prefix: str)
      }
      else {
        ps += paths(group, prefix: prefix)
      }
    }

    return ps
  }
    
}
