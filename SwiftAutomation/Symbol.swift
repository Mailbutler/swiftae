//
//  Symbol.swift
//  SwiftAutomation
//
//
//  Represents typeType/typeEnumerated/typeProperty/typeKeyword descriptors. Static glues subclass this to add static vars representing each type/enum/property keyword defined by the application dictionary.
//
//  Also used to represent string-based record keys (where type=0 and name!=nil) when unpacking an AERecord's keyASUserRecordFields property, allowing the resulting dictionary to hold any mixture of terminology- (keyword) and user-defined (string) keys while typed as [Symbol:Any].
//


import Foundation



// `@unchecked` only because a non-final class can never take a *checked* `Sendable` conformance, and
// this one is subclassed by every static glue (`MAISymbol`, `TEDSymbol`, …) so it cannot be final.
// Nothing else is being asserted: the three stored properties are `let`s of `String?` and `OSType`,
// all `Sendable`, and glue subclasses add no stored properties of their own — they only declare
// static constants and override `typeAliasName`.
open class Symbol: @unchecked Sendable, Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable, SelfPacking {

    public let name: String?, code: OSType, type: OSType
    
    open var typeAliasName: String {return "Symbol"} // provides prefix used in description var; glue subclasses override this with their own strings (e.g. "FIN" for Finder)
    
    public required init(name: String?, code: OSType, type: OSType = typeType, descriptor: NSAppleEventDescriptor? = nil) { // (When unpacking a symbol descriptor returned by an application command, if the returned AEDesc is passed here it'll be cached here for reuse, avoiding the need to fully-repack the new Symbol instance if/when it's subsequently used in another application command. In practice, this is mostly irrelevant to static glues, as Symbol subclasses in static glues are normally constructed via Symbol.symbol(), which lazily instantiates existing glue-defined static vars instead. Whether it makes any noticeable difference to dynamic bridges remains to be seen [it's not likely to be a major bottleneck], but it costs nothing for AppData to include it if it has it.)
        self.name = name
        self.code = code
        self.type = type
        // `descriptor` is accepted and discarded. It used to be cached in a stored property, which
        // made every Symbol carry shared mutable state: static glues expose their symbols as
        // process-wide `static let`s, and the cache was filled without synchronisation on first
        // `descriptor` access, so two threads packing the same symbol raced on the field. The
        // descriptor is fully derived from `name`, `code` and `type`, so rebuilding it on demand
        // loses no information — only the reuse of one small object, which is nothing beside the
        // Apple event round trip it is built for. The parameter stays so call sites are unchanged.
        _ = descriptor
    }
    
    // special constructor for string-based record keys (avoids the need to wrap dictionary keys in a `StringOrSymbol` enum when unpacking)
    // e.g. the AppleScript record `{name:"Bob", isMyUser:true}` maps to the Swift Dictionary `[Symbol.name:"Bob", Symbol("isMyUser"):true]`
    
    public convenience init(_ name: String, descriptor: NSAppleEventDescriptor? = nil) {
        self.init(name: name, code: noOSType, type: noOSType, descriptor: descriptor)
    }
    
    // convenience constructors for creating Symbols using raw four-char codes
    
    public convenience init(code: String, type: String = "type") {
        self.init(name: nil, code: UTGetOSTypeFromString(code as CFString), type: UTGetOSTypeFromString(type as CFString))
    }
    
    public convenience init(code: OSType, type: OSType = typeType) {
        self.init(name: nil, code: code, type: type)
    }
    
    // this is called by AppData when unpacking typeType, typeEnumerated, etc; glue-defined symbol subclasses should override to return glue-defined symbols where available
    open class func symbol(code: OSType, type: OSType = typeType, descriptor: NSAppleEventDescriptor? = nil) -> Symbol {
        return self.init(name: nil, code: code, type: type, descriptor: descriptor)
    }
    
    // this is called by AppData when unpacking string-based record keys
    public class func symbol(string: String, descriptor: NSAppleEventDescriptor? = nil) -> Symbol {
        return self.init(name: string, code: noOSType, type: noOSType, descriptor: descriptor)
    }
    
    // display
    
    public var description: String {
        if let name = self.name {
            return self.nameOnly ? "\(self.typeAliasName)(\(name.debugDescription))" : "\(self.typeAliasName).\(name)"
        } else {
            return "\(self.typeAliasName)(code:\(formatFourCharCodeString(self.code)),type:\(formatFourCharCodeString(self.type)))"
        }
    }
    
    public var debugDescription: String { return self.description }
    
    public var customMirror: Mirror {
        let children: [Mirror.Child] = [(label: "description", value: self.description), (label: "name", value: self.name ?? ""),
                                        (label: "code", value: fourCharCode(self.code)), (label: "type", value: fourCharCode(self.type))]
        return Mirror(self, children: children, displayStyle: .`class`, ancestorRepresentation: .suppressed)
    }
    
    // packing
    
    public var descriptor: NSAppleEventDescriptor { // used by SwiftAutomation_packSelf and previous()/next() selectors
        return self.nameOnly ? NSAppleEventDescriptor(string: self.name!) : NSAppleEventDescriptor(type: self.type, code: self.code)
    }
    
    // returns true if Symbol contains name but not code (i.e. it represents a string-based record property key)
    public var nameOnly: Bool { return self.type == noOSType && self.name != nil }
    
    public func SwiftAutomation_packSelf(_ appData: AppData) throws -> NSAppleEventDescriptor {
        return self.descriptor
    }
    
    // equatable, hashable
    
    public var hashValue: Int { return self.nameOnly ? self.name!.hashValue : Int(self.code) } // see also comments in `==()` below
    
    public static func ==(lhs: Symbol, rhs: Symbol) -> Bool {
        // note: operands are not required to be the same subclass as this compares for AE equality only, e.g.:
        //
        //    TED.document == AESymbol(code: "docu") -> true
        //
        // note: AE types are also ignored on the [reasonable] assumption that any differences in descriptor type (e.g. typeType vs typeProperty) are irrelevant as apps will only care about the code itself
        return lhs.nameOnly && rhs.nameOnly ? lhs.name == rhs.name : lhs.code == rhs.code
    }
}




