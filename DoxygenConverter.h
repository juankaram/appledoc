//
//  DoxygenConverter.h
//  objcdoc
//
//  Created by Tomaz Kragelj on 11.4.09.
//  Copyright 2009 Tomaz Kragelj. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kTKConverterException @"TKConverterException"

#define kTKDirClasses @"Classes"
#define kTKDirCategories @"Categories"
#define kTKDirProtocols @"Protocols"
#define kTKDirCSS @"css"
#define kTKDirDocSet @"docset"

#define kTKDataMainIndexKey @"Index"
#define kTKDataMainObjectsKey @"Objects"
#define kTKDataMainDirectoriesKey @"Directories"

#define kTKDataObjectNameKey @"ObjectName"
#define kTKDataObjectKindKey @"ObjectKind"
#define kTKDataObjectMarkupKey @"CleanedMarkup"
#define kTKDataObjectRelDirectoryKey @"RelativeDirectory"
#define kTKDataObjectRelPathKey @"RelativePath"
#define kTKDataObjectDoxygenFilenameKey @"DoxygenMarkupFilename"

@class CommandLineParser;

//////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////
/** The doxygen output converter class.

￼￼This class handles the doxygen xml output files and converts them to DocSet. The
conversion happens through several steps:
  - If @c Doxyfile doesn't exist or doxygen configuration file is not passed over via
	the command line parameters, the default file is created using the doxygen itself,
	then the configuration file options are set so that correct output is used.
  - Doxygen is started with the configuration file which results in xml files being
	created at the desired output path.
  - The generated xml files are parsed and converted to clean versions which are used
	for creating the rest of the documentation. All index xml files are created as well.
  - All references in the cleaned xml files are checked so that they point to the
	correct files and members.
  - Optionally, all cleaned xml files are converted to xhtml.
  - Optionally, the DocSet bundle is created.
  - All temporary files are optionally removed.
 
The convertion takes several steps. In the first steps the objects database is generated
which is used in later steps to get and handle the list of documented objects. The database
is a standard @c NSDictionary of the following layout:
  - @c "Index" key: contains a @c NSXMLDocument with clean index XML.
  - @c "Objects" key: contains a @c NSMutableDictionary with object descriptions. This
	is usefull for enumerating over all documented objects:
	  - @c "<ObjectName>" key: contains a @c NSMutableDictionary with object data:
		  - @c "ObjectName" key: an @c NSString with the object name (this is the same
			name as used for the key in the root dictionary).
		  - @c "ObjectKind" key: an @c NSString which has the value @c "class" if the
			object is a class, @c "category" if the object is category and @c "protocol"
			if the object is a protocol.
		  - @c "CleanedMarkup" key: contains an @c NSXMLDocument with clean XML. This
			document is updated through different steps and always contains the last
			object data.
		  - @c "RelativeDirectory" key: this @c NSString describes the sub directory 
			under which the object will be stored relative to the index file. At the
			moment this value depends on the object type and can be @c "Classes", 
			@c "Categories" or @c "Protocols".
		  - @c "RelativePath" key: this @c NSString describes the relative path including
			the file name to the index file. This path starts with the value of the
			@c RelativeDirectory key to which the object file name is added.
		  - @c "DoxygenMarkupFilename" key: contains an @c NSString that specifies the
			original name of the XML generated by the doxygen.
	  - @c "<ObjectName>"...
	  - ...
  - @c "Directories" key: contains a @c NSMutableDictionary which resembles the file
	structure under which the objects are stored. This is usefull for enumerating over
	the documented objects by their relative directory under which they will be saved:
	  - @c "<DirectoryName>" key: contains a @c NSMutableArray with the list of all
		objects for this directory. The objects stored in the array are simply pointers
		to the main @c "Objects" instances.
	  - @c "<DirectoryName>"...
	  - ...
 
Note that this class is closely coupled with @c CommandLineParser which it uses to
determine the exact conversion work flow.
 
Since this class is quite complex one, it is divided into several categories. The
categories which implement helper methods handle individual conversion tasks. The
helper methods are called from the main convert() method in the proper order. The
helper categories are:
- @c DoxygenConverter(Doxygen)
- @c DoxygenConverter(CleanXML)
- @c DoxygenConverter(CleanHTML)
- @c DoxygenConverter(DocSet)
- @c DoxygenConverter(Helpers).
*/
@interface DoxygenConverter : NSObject 
{
	CommandLineParser* cmd;
	NSFileManager* manager;
	NSString* doxygenXMLOutputPath;
	NSMutableDictionary* database;
}

//////////////////////////////////////////////////////////////////////////////////////////
/// @name Converting handling
//////////////////////////////////////////////////////////////////////////////////////////

/** Converts￼ the doxygen generated file into the desired output.
 
@exception NSException Thrown if conversion fails.
*/
- (void) convert;

@end