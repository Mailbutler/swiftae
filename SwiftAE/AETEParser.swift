//
//  AETEParser.swift
//  SwiftAE
//
//

import Foundation


// kAEInheritedProperties isn't defined in OpenScripting.h for some reason
let kSwiftAEInheritedProperties = UTGetOSTypeFromString("c@#^")


/**********************************************************************/


public class AETEParser: ApplicationTerminology {
    
    public private(set) var types: KeywordTerms = []
    public private(set) var enumerators: KeywordTerms = []
    public private(set) var properties: KeywordTerms = []
    public private(set) var elements: KeywordTerms = []
    public var commands: CommandTerms { return Array(self.commandsDict.values) }
    
    private var commandsDict = [String:CommandTerm]()
    private let keywordConverter: KeywordConverterProtocol
    
    // following are used in parse() to supply 'missing' singular/plural class names
    private var classAndElementDefsByCode = [OSType:KeywordTerm]()
    private var foundClassCodes           = Set<OSType>()
    private var foundElementCodes         = Set<OSType>()
    
    private var aeteData: NSData! // was char*
    private var cursor: Int = 0 // was unsigned long
    
    
    public init(keywordConverter: KeywordConverterProtocol = gSwiftAEKeywordConverter) {
        self.keywordConverter = keywordConverter
    }
    
    // read data methods // TO DO: AEB implementation was simple and lightweight (C pointer arithmetic) - how does this compare? how would ManagedBuffer compare?
    
    func short() -> UInt16 { // unsigned short (2 bytes)
        var value: UInt16 = 0
        self.aeteData.getBytes(&value, range: NSMakeRange(self.cursor,sizeof(UInt16)))
        self.cursor += sizeof(UInt16)
        return value
    }
    
    func code() -> OSType { // (4 bytes)
        var value: OSType = 0
        self.aeteData.getBytes(&value, range: NSMakeRange(self.cursor,sizeof(OSType)))
        self.cursor += sizeof(OSType)
        return value
    }
    
    func string() -> String {
        var length: UInt8 = 0 // Pascal string = 1-byte length (unsigned char) followed by 0-255 MacRoman chars
        self.aeteData.getBytes(&length, range: NSMakeRange(self.cursor,sizeof(UInt8)))
        self.cursor += sizeof(UInt8)
        let value = length == 0 ? "" : NSString(data: aeteData.subdataWithRange(NSMakeRange(self.cursor,Int(length))),
                                                encoding: NSMacOSRomanStringEncoding) as! String
        self.cursor += Int(length)
        return value
    }
    
    // skip unneeded aete data
    
    func skipShort() {
        self.cursor += sizeof(UInt16)
    }
    func skipCode() {
        self.cursor += sizeof(OSType)
    }
    func skipString() {
        var len: UInt8 = 0
        self.aeteData.getBytes(&len, range: NSMakeRange(self.cursor,sizeof(UInt8)))
        self.cursor += sizeof(UInt8) + Int(len)
    }
    func alignCursor() { // realign aete data cursor on even byte after reading strings
        if self.cursor % 2 != 0 {
            self.cursor += 1
        }
    }
    
    // perform a bounds check on aete data cursor to protect against malformed aete data
    
    func checkCursor() throws {
        if cursor > self.aeteData.length {
            throw TerminologyError("The AETE ended prematurely: (self.aeteData.length) bytes expected, (self.cursor) bytes read.")
        }
    }
    
    
    // Parse methods
    
    func parseCommand() throws {
        let name = self.keywordConverter.convertSpecifierName(self.string())
        self.skipString()   // description
        self.alignCursor()
        let classCode = self.code()
        let code = self.code()
        let commandDef = CommandTerm(name: name, eventClass: classCode, eventID: code)
        // skip result
        self.skipCode()     // datatype
        self.skipString()   // description
        self.alignCursor()
        self.skipShort()    // flags
        // skip direct parameter
        self.skipCode()     // datatype
        self.skipString()   // description
        self.alignCursor()
        self.skipShort()    // flags
        // parse keyword parameters
        /* Note: overlapping command definitions (e.g. InDesign) should be processed as follows:
        - If their names and codes are the same, only the last definition is used; other definitions are ignored and will not compile.
        - If their names are the same but their codes are different, only the first definition is used; other definitions are ignored and will not compile.
        - If a dictionary-defined command has the same name but different code to a built-in definition, escape its name so it doesn't conflict with the default built-in definition.
        */
        let otherCommandDef: CommandTerm! = self.commandsDict[name]
        if otherCommandDef == nil || (commandDef.eventClass == otherCommandDef.eventClass
            && commandDef.eventID == otherCommandDef.eventID) {
                self.commandsDict[name] = commandDef
        }
        let n = self.short()
        for _ in 0..<n {
            let paramName = self.keywordConverter.convertParameterName(self.string())
            self.alignCursor()
            let paramCode = self.code()
            self.skipCode()     // datatype
            self.skipString()   // description
            self.alignCursor()
            self.skipShort()    // flags
            commandDef.addParameter(paramName, code: paramCode)
            try self.checkCursor()
        }
    }
    
    
    func parseClass() throws {
        var isPlural = false
        let className = self.keywordConverter.convertSpecifierName(self.string())
        self.alignCursor()
        let classCode = self.code()
        self.skipString()   // description
        self.alignCursor()
        // properties
        let n = self.short()
        for _ in 0..<n {
            let propertyName = self.keywordConverter.convertSpecifierName(self.string())
            self.alignCursor()
            let propertyCode = self.code()
            self.skipCode()     // datatype
            self.skipString()   // description
            self.alignCursor()
            let flags = self.short()
            if propertyCode != kSwiftAEInheritedProperties { // it's a normal property definition, not a superclass  definition
                let propertyDef = KeywordTerm(name: propertyName, kind: .Property, code: propertyCode)
                if (flags % 2 != 0) { // class name is plural
                    isPlural = true
                } else if !properties.contains(propertyDef) { // add to list of property definitions
                    self.properties.append(propertyDef)
                }
            }
            try self.checkCursor()
        }
        // skip elements
        let n2 = self.short()
        for _ in 0..<n2 {
            self.skipCode()         // code
            let m = self.short()    // number of reference forms
            self.cursor += 4 * Int(m)
            try self.checkCursor()
        }
        // add either singular (class) or plural (element) name definition
        let classDef = KeywordTerm(name: className, kind: .Type, code: classCode)
        if isPlural {
            if !self.elements.contains(classDef) {
                self.elements.append(classDef)
                self.foundElementCodes.insert(classCode)
            }
        } else {
            if !self.types.contains(classDef) { // classes
                self.types.append(classDef)
                self.foundClassCodes.insert(classCode)
            }
        }
        self.classAndElementDefsByCode[classCode] = classDef
    }
    
    func parseComparison() throws {  // comparison info isn't used
        self.skipString()   // name
        self.alignCursor()
        self.skipCode()     // code
        self.skipString()   // description
        self.alignCursor()
    }
    
    func parseEnumeration() throws {
        self.skipCode()         // code
        let n = self.short()
        // enumerators
        for _ in 0..<n {
            let name = self.keywordConverter.convertSpecifierName(self.string())
            self.alignCursor()
            let enumeratorDef = KeywordTerm(name: name, kind: .Enumerator, code: self.code())
            self.skipString()    // description
            self.alignCursor()
            if !self.enumerators.contains(enumeratorDef) {
                self.enumerators.append(enumeratorDef)
            }
            try self.checkCursor()
        }
    }
    
    func parseSuite() throws {
        self.skipString()   // name string
        self.skipString()   // description
        self.alignCursor()
        self.skipCode()     // code
        self.skipShort()    // level
        self.skipShort()    // version
        let n = self.short()
        for _ in 0..<n {
            try self.parseCommand()
            try self.checkCursor()
        }
        let n2 = self.short()
        for _ in 0..<n2 {
            try self.parseClass()
            try self.checkCursor()
        }
        let n3 = self.short()
        for _ in 0..<n3 {
            try self.parseComparison()
            try self.checkCursor()
        }
        let n4 = self.short()
        for _ in 0..<n4 {
            try self.parseEnumeration()
            try self.checkCursor()
        }
    }
    
    func parse(descriptor: NSAppleEventDescriptor) throws { // accepts AETE/AEUT or AEList of AETE/AEUTs
        switch descriptor.descriptorType {
        case typeAETE, typeAEUT:
            self.aeteData = descriptor.data
            self.cursor = 6 // skip version, language, script integers
            let n = self.short()
            do {
                for _ in 0..<n {
                    try self.parseSuite()
                }
                /* singular names are normally used in the classes table and plural names in the elements table. However, if an aete defines a singular name but not a plural name then the missing plural name is substituted with the singular name; and vice-versa if there's no singular equivalent for a plural name.
                */
                for code in self.foundClassCodes {
                    if !self.foundElementCodes.contains(code) {
                        self.elements.append(self.classAndElementDefsByCode[code]!)
                    }
                }
                for code in self.foundElementCodes {
                    if !self.foundClassCodes.contains(code) {
                        self.types.append(self.classAndElementDefsByCode[code]!)
                    }
                }
                self.classAndElementDefsByCode.removeAll()
                self.foundClassCodes.removeAll()
                self.foundElementCodes.removeAll()

            } catch {
                throw TerminologyError("An error occurred while parsing AETE. \(error)")
            }
        case typeAEList:
            for i in 1...descriptor.numberOfItems {
                try self.parse(descriptor.descriptorAtIndex(i)!)
            }
        default:
            throw TerminologyError("An error occurred while parsing AETE. Invalid descriptor type.")
        }
    }
    
    func parse(descriptors: [NSAppleEventDescriptor]) throws {
        for descriptor in descriptors {
            try self.parse(descriptor)
        }
    }
}



extension AEApplication { // TO DO: extend AppData first, with convenience methods on AEApplication?

    public func getAETE() throws -> NSAppleEventDescriptor {
        return try self.sendAppleEvent(kASAppleScriptSuite, kGetAETE, [keyDirectObject:0]) as NSAppleEventDescriptor
    }
    
    public func parseAETE() throws -> AETEParser {
        let p = AETEParser()
        try p.parse(try self.getAETE())
        return p
    }
}

