//
//  CoreDataSwiftTemplates.swift
//  slate
//
//  Created by Jason Fieldman on 5/30/18.
//  Copyright © 2018 Jason Fieldman. All rights reserved.
//

import Foundation

/// Inputs:
///  * FILENAME - The filename string
///  * COMMAND - The command line used to generate the slate files
///  * EXTRAIMPORT - Import an additional module if desired
let template_CD_Swift_fileheader: String = """
// {FILENAME}.swift
// ----- DO NOT MODIFY -----{COMMAND}

import Foundation
import CoreData{EXTRAIMPORT}

/** These extensions are available if conversion to basic integer is required */
private extension Int16 {
    var slate_asInt: Int { return Int(self) }
}

private extension Int32 {
    var slate_asInt: Int { return Int(self) }
}

private extension Int64 {
    var slate_asInt: Int { return Int(self) }
}


"""

/// Inputs:
///  * COREDATACLASS - The Core Data class name
///  * SLATECLASS - The Slate class name
let template_CD_Swift_SlateObjectConvertible: String = """
extension {COREDATACLASS}: SlateObjectConvertible {

    /**
     Instantiates an immutable Slate class from the receiving Core Data class.
     */
    public var slateObject: SlateObject {
        return {SLATECLASS}(managedObject: self)
    }
}


"""

/// Inputs:
///  * COREDATACLASS - The Core Data class name
///  * COREDATAENTITYNAME - The name of the corresponding Core Data entity
let template_CD_Swift_ManagedObjectExtension: String = """
extension {COREDATACLASS} {

    /**
     Helper method that instantiates a {COREDATACLASS} in the specified context.
     */
    public static func create(in moc: NSManagedObjectContext) -> {COREDATACLASS}? {
        guard let entity = NSEntityDescription.entity(forEntityName: "{COREDATAENTITYNAME}", in: moc) else {
            return nil
        }

        return {COREDATACLASS}(entity: entity, insertInto: moc)
    }
}


"""


/// Inputs:
///  * OBJTYPE - Either `class` or `struct`
///  * SLATECLASS - The Slate immutable class name
///  * COREDATACLASS - The backing Core Data class name
///  * ATTRASSIGNMENT - A series of attribute assignments for this class
///  * ATTRDECLARATIONS - A series of attribute declarations
let template_CD_Swift_SlateClassImpl: String = """
public {OBJTYPE} {SLATECLASS}: SlateObject {

    // -- Attribute Declarations --
{ATTRDECLARATIONS}
    // -- Attribute Names --

    public struct Attributes {
{ATTRNAMES}
    }

    /**
     Identifies the NSManagedObject type that backs this SlateObject
     */
    public static var __slate_managedObjectType: NSManagedObject.Type = {COREDATACLASS}.self

    /**
     Each immutable data model object should have an associated SlateID (in the
     core data case, the NSManagedObjectID.  This is a cross-mutation identifier
     for the object.
    */
    public let slateID: SlateID

    /**
     Instantiation is private to this file; Slate objects should only be instantiated
     by accessing the `slateObject` property of the corresponding managed object.
     */
    fileprivate init(managedObject: {COREDATACLASS}) {
        // All objects inherit the objectID
        self.slateID = managedObject.objectID

        // Attribute assignment
{ATTRASSIGNMENT}
    }

    // -- Substruct Definitions

{SUBSTRUCTS}
}


"""

/// Inputs:
///  * SLATESUBSTRUCT - The Slate substruct struct name
///  * COREDATACLASS - The backing Core Data class name
///  * ATTRASSIGNMENT - A series of attribute assignments for this class
///  * ATTRDECLARATIONS - A series of attribute declarations
let template_CD_Swift_SlateSubstructImpl: String = """
    public struct {SLATESUBSTRUCT} {

        // -- Attribute Declarations --
{ATTRDECLARATIONS}

        /**
         Instantiation is private to this file; Substructs should only be instantiated
         by their parent Slate object.
         */
        fileprivate init(managedObject: {COREDATACLASS}) {

            // Attribute assignment
{ATTRASSIGNMENT}
        }
    }


"""

/// Inputs:
///  * ATTR - The name of the attribute
let template_CD_Swift_AttrName: String = "        public static let {ATTR} = \"{ATTR}\"\n"

/// Inputs:
///  * ATTR - The name of the attribute
///  * CONV - The conversion to the proper swift type
let template_CD_Swift_AttrAssignment: String = "        self.{ATTR} = managedObject.{ATTR}{CONV}\n"

/// Inputs:
///  * ATTR - The name of the attribute
///  * TYPE - The type of the managed object
let template_CD_Swift_AttrForceAssignment: String = "        self.{ATTR} = { let t: {TYPE}? = managedObject.{ATTR}{CONV}; return t! }()\n"

/// Inputs:
///  * ATTR - The name of the attribute
///  * TYPE - The type of substruct
let template_CD_Swift_AttrAssignmentForSubstruct: String = "        self.{ATTR} = {TYPE}(managedObject: managedObject)\n"

/// Inputs:
///  * ATTR - The name of the attribute
///  * TYPE - The type of substruct
let template_CD_Swift_AttrAssignmentForOptSubstruct: String = "        self.{ATTR} = managedObject.{ATTR}_has ? {TYPE}(managedObject: managedObject) : nil\n"

/// Inputs:
///  * STRNAME - The managed property's struct prefix
///  * ATTR - The name of the attribute
///  * CONV - The conversion to the proper swift type
let template_CD_Swift_SubstructAttrAssignment: String = "            self.{ATTR} = managedObject.{STRNAME}_{ATTR}{CONV}\n"

/// Inputs:
///  * STRNAME - The managed property's struct prefix
///  * ATTR - The name of the attribute
///  * TYPE - The type of the managed object
///  * DEF - The default value
let template_CD_Swift_SubstructAttrForceAssignment: String = "            self.{ATTR} = { let t: {TYPE}? = managedObject.{STRNAME}_{ATTR}{CONV}; return t ?? {DEF} }()\n"

/// Inputs:
///  * ATTR - The name of the attribute
///  * TYPE - The immutable type of the attribute
///  * OPTIONAL - Use `?` to indicate that this attribute is optional
let template_CD_Swift_AttrDeclaration: String = "    public let {ATTR}: {TYPE}{OPTIONAL}\n"

/// Inputs:
///  * ATTR - The name of the attribute
///  * TYPE - The immutable type of the attribute
///  * OPTIONAL - Use `?` to indicate that this attribute is optional
let template_CD_Swift_SubstructAttrDeclaration: String = "        public let {ATTR}: {TYPE}{OPTIONAL}\n"

/// Inputs:
///  * OBJQUAL - The SO qualifier string; `: ` for class or ` == ` for struct
///  * SLATECLASS - The name of the immutable slate class
///  * RELATIONSHIPS - The listing of relationship lookups
let template_CD_Swift_SlateRelationshipResolver: String = """
public extension SlateRelationshipResolver where SO{OBJQUAL}{SLATECLASS} {
{RELATIONSHIPS}
}


"""

/// Inputs:
///  * RELATIONSHIPNAME - The attribute/name of the relationship
///  * TARGETSLATECLASS - The name of the immutable slate class of the relationship target
///  * COREDATACLASS - The name of the Core Data class of the relationship target
let template_CD_Swift_SlateRelationshipToMany: String = """
    var {RELATIONSHIPNAME}: [{TARGETSLATECLASS}] {
        guard let mo = self.managedObject as? {COREDATACLASS} else {
            fatalError("Fatal casting error")
        }

        guard let set = mo.{RELATIONSHIPNAME} as? Set<AnyHashable> else {
            return []
        }

        return self.convert(set) as! [{TARGETSLATECLASS}]
    }


"""

/// Inputs:
///  * RELATIONSHIPNAME - The attribute/name of the relationship
///  * TARGETSLATECLASS - The name of the immutable slate class of the relationship target
///  * COREDATACLASS - The name of the Core Data class of the relationship target
///  * OPTIONAL - Should be `?` if the toOne is optional
///  * NONOPTIONAL - Should be `!` if the toOne is required
let template_CD_Swift_SlateRelationshipToOne: String = """
    var {RELATIONSHIPNAME}: {TARGETSLATECLASS}{OPTIONAL} {
        guard let mo = self.managedObject as? {COREDATACLASS} else {
            fatalError("Fatal casting error")
        }

        return self.convert(mo.{RELATIONSHIPNAME}) as{NONOPTIONAL}{OPTIONAL} {TARGETSLATECLASS}
    }


"""

/// Inputs:
///  * SLATECLASS - The name of the immutable slate class
///  * ATTRS - Equatable attributes
let template_CD_Swift_SlateEquatable: String = """
extension {SLATECLASS}: Equatable {
    public static func ==(lhs: {SLATECLASS}, rhs: {SLATECLASS}) -> Bool {
        return (lhs.slateID == rhs.slateID){ATTRS}
    }
}


"""

// -----------------------------------
// --- Core Data Entity Generators ---
// -----------------------------------

/// Inputs:
///  * COMMAND - Command used to generate the file
///  * PROPERTIES - Core Data properties of the class
///  * CDENTITYCLASS - Core Data entity class name
///  * CDENTITYNAME - Core Data entity name
let template_CD_Entity: String = """
// {FILENAME}
// ----- DO NOT MODIFY -----{COMMAND}

import Foundation
import CoreData

@objc({CDENTITYCLASS})
public class {CDENTITYCLASS}: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<{CDENTITYCLASS}> {
        return NSFetchRequest<{CDENTITYCLASS}>(entityName: "{CDENTITYNAME}")
    }

{PROPERTIES}
}

"""

/// Inputs:
///  * VARNAME - Variable name
///  * TYPE - The property type
///  * OPTIONAL - The string "?" if the type is optional
let template_CD_Entity_Property: String = "    @NSManaged public var {VARNAME}: {TYPE}{OPTIONAL}\n"
