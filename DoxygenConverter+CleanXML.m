//
//  DoxygenConverter+CleanXML.m
//  objcdoc
//
//  Created by Tomaz Kragelj on 17.4.09.
//  Copyright 2009 Tomaz Kragelj. All rights reserved.
//

#import "DoxygenConverter+CleanXML.h"
#import "DoxygenConverter+Helpers.h"
#import "CommandLineParser.h"
#import "LoggingProvider.h"
#import "Systemator.h"

@implementation DoxygenConverter (CleanXML)

//----------------------------------------------------------------------------------------
- (void) createCleanObjectDocumentationMarkup
{
	logNormal(@"Creating clean object XML files...");
	NSAutoreleasePool* loopAutoreleasePool = nil;
	
	// First get the list of all files (and directories) at the doxygen output path. Note
	// that we only handle certain files, based on their names.
	NSArray* files = [manager directoryContentsAtPath:doxygenXMLOutputPath];
	for (NSString* filename in files)
	{
		// Setup the autorelease pool for this iteration. Note that we are releasing the
		// previous iteration pool here as well. This is because we use continue to 
		// skip certain iterations, so releasing at the end of the loop would not work...
		// Also note that after the loop ends, we are releasing the last iteration loop.
		[loopAutoreleasePool drain];
		loopAutoreleasePool = [[NSAutoreleasePool alloc] init];
		
		// (1) First check if the file is .xml and starts with correct name.
		BOOL parse = [filename hasSuffix:@".xml"];
		parse &= [filename hasPrefix:@"class_"] ||
				 [filename hasPrefix:@"interface_"] ||
				 [filename hasPrefix:@"protocol_"];
		if (!parse)
		{
			logVerbose(@"Skipping '%@' because it doesn't describe known object.", filename);
			continue;
		}
		
		// (2) Parse the XML and check if the file is documented or not. Basically
		// we check if at least one brief or detailed description contains a
		// para tag. If so, the document is considered documented... If parsing
		// fails, log and skip the file.
		NSError* error = nil;
		NSString* inputFilename = [doxygenXMLOutputPath stringByAppendingPathComponent:filename];
		NSURL* originalURL = [NSURL fileURLWithPath:inputFilename];
		NSXMLDocument* originalDocument = [[[NSXMLDocument alloc] initWithContentsOfURL:originalURL
																				options:0
																				  error:&error] autorelease];
		if (!originalDocument)
		{
			logError(@"Skipping '%@' because parsing failed with error %@!", 
					 filename, 
					 [error localizedDescription]);
			continue;
		}
		
		// (3) If at least one item is documented, run the document through the
		// xslt converter to get clean XML. Then use the clean XML to get
		// further object information and finally add the object to the data
		// dictionary.
		if ([[originalDocument nodesForXPath:@"//briefdescription/para" error:NULL] count] == 0 &&
			[[originalDocument nodesForXPath:@"//detaileddescription/para" error:NULL] count] == 0)
		{
			logVerbose(@"Skipping '%@' because it contains non-documented object...", filename);
			continue;
		}

		// (4) Prepare file names and run the xslt converter. Catch any exception
		// and log it, then continue with the next file.
		@try
		{
			// (A) Run the xslt converter.
			NSString* stylesheetFile = [cmd.templatesPath stringByAppendingPathComponent:@"object.xslt"];
			NSXMLDocument* cleanDocument = [self applyXSLTFromFile:stylesheetFile 
														toDocument:originalDocument
															 error:&error];
			if (!cleanDocument)
			{
				logError(@"Skipping '%@' because creating clean XML failed with error %@!", 
						 filename, 
						 [error localizedDescription]);
				continue;
			}

			// (B) If object node is not present, exit. This means the convertion failed...
			NSArray* objectNodes = [cleanDocument nodesForXPath:@"/object" error:NULL];
			if ([objectNodes count] == 0)
			{
				logError(@"Skipping '%@' because object node not found!", filename);
				continue;
			}
			
			// (C) Get object name node. If not found, exit.
			NSXMLElement* objectNode = [objectNodes objectAtIndex:0];
			NSArray* objectNameNodes = [objectNode nodesForXPath:@"name" error:NULL];
			if ([objectNameNodes count] == 0)
			{
				logError(@"Skipping '%@' because object name node not found!", filename);
				continue;
			}
			
			// (D) Now we have all information, get the data and add the object to the list.
			NSXMLElement* objectNameNode = [objectNameNodes objectAtIndex:0];
			NSString* objectName = [objectNameNode stringValue];
			NSString* objectKind = [[objectNode attributeForName:@"kind"] stringValue];
			if ([objectName length] == 0 || [objectKind length] == 0)
			{
				logError(@"Skipping '%@' because data cannot be collected (name %@, kind %@)!",
						 filename,
						 objectName,
						 objectKind);
				continue;
			}
			
			// (E) Prepare the object relative directory and relative path to the index.
			NSString* objectRelativeDirectory = nil;
			if ([objectKind isEqualToString:@"protocol"])
				objectRelativeDirectory = kTKDirProtocols;
			else if ([objectKind isEqualToString:@"category"])
				objectRelativeDirectory = kTKDirCategories;
			else
				objectRelativeDirectory = kTKDirClasses;
			
			NSString* objectRelativePath = [objectRelativeDirectory stringByAppendingPathComponent:objectName];
			objectRelativePath = [objectRelativePath stringByAppendingPathExtension:@"html"];
			
			// (F) OK, now really add the node to the database... ;) First create the
			// object's description dictionary. Then add the object to the Objects
			// dictionary. Then check if the object's relative directory key already
			// exists in the directories dictionary. If not, create it, then add the
			// object to the end of the list.
			NSMutableDictionary* objectData = [[NSMutableDictionary alloc] init];
			[objectData setObject:objectName forKey:kTKDataObjectNameKey];
			[objectData setObject:objectKind forKey:kTKDataObjectKindKey];
			[objectData setObject:cleanDocument forKey:kTKDataObjectMarkupKey];
			[objectData setObject:objectRelativeDirectory forKey:kTKDataObjectRelDirectoryKey];
			[objectData setObject:objectRelativePath forKey:kTKDataObjectRelPathKey];
			[objectData setObject:inputFilename forKey:kTKDataObjectDoxygenFilenameKey];
			
			// Add the object to the object's dictionary.
			NSMutableDictionary* objectsDict = [database objectForKey:kTKDataMainObjectsKey];
			[objectsDict setObject:objectData forKey:objectName];
			
			// Add the object to the directories list.
			NSMutableDictionary* directoriesDict = [database objectForKey:kTKDataMainDirectoriesKey];
			NSMutableArray* directoryArray = [directoriesDict objectForKey:objectRelativeDirectory];
			if (directoryArray == nil)
			{
				directoryArray = [NSMutableArray array];
				[directoriesDict setObject:directoryArray forKey:objectRelativeDirectory];
			}
			[directoryArray addObject:objectData];
			
			// Log the object.
			logVerbose(@"Found '%@' of type '%@' in file '%@'...", 
					   objectName, 
					   objectKind,
					   filename);
		}
		@catch (NSException* e)
		{
			logError(@"Skipping '%@' because converting to clean documentation failed with error %@!", 
					 filename, 
					 [e reason]);
			continue;
		}
	}
	
	// Release the last iteration pool.
	[loopAutoreleasePool drain];	
	logInfo(@"Finished creating clean object documentation files.");
}

//----------------------------------------------------------------------------------------
- (void) createCleanIndexDocumentationFile
{
	logNormal(@"Creating clean index documentation file...");	
	NSAutoreleasePool* loopAutoreleasePool = [[NSAutoreleasePool alloc] init];
	
	// Create the default markup.
	NSXMLDocument* document = [[NSXMLDocument alloc] init];
	NSXMLElement* projectElement = [NSXMLElement elementWithName:@"project"];
	[document setVersion:@"1.0"];
	[document addChild:projectElement];
	
	// Enumerate through all the enumerated objects and create the markup. Note that
	// we use directory structure so that we get proper enumeration.
	NSDictionary* objects = [database objectForKey:kTKDataMainObjectsKey];
	NSArray* sortedObjectNames = [[objects allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString* objectName in sortedObjectNames)
	{
		NSDictionary* objectData = [objects valueForKey:objectName];
		NSString* objectKind = [objectData valueForKey:kTKDataObjectKindKey];
		
		// Create the object element and the kind attribute.
		NSXMLElement* objectElement = [NSXMLElement elementWithName:@"object"];
		NSXMLNode* kindAttribute = [NSXMLNode attributeWithName:@"kind" stringValue:objectKind];
		[objectElement addAttribute:kindAttribute];
		[projectElement addChild:objectElement];
		
		// Create the name element.
		NSXMLElement* nameElement = [NSXMLElement elementWithName:@"name"];
		[nameElement setStringValue:objectName];
		[objectElement addChild:nameElement];
	}
	
	// Store the cleaned markup to the application data.
	[database setObject:document forKey:kTKDataMainIndexKey];
	
	// Save the markup.
	NSError* error = nil;
	NSData* markupData = [document XMLDataWithOptions:NSXMLNodePrettyPrint];
	NSString* filename = [cmd.outputCleanXMLPath stringByAppendingPathComponent:@"Index.xml"];
	if (![markupData writeToFile:filename options:0 error:&error])
	{
		[Systemator throwExceptionWithName:kTKConverterException basedOnError:error];
	}
	
	[loopAutoreleasePool drain];
	logInfo(@"Finished creating clean index documentation file.");
}

//----------------------------------------------------------------------------------------
- (void) fixCleanObjectDocumentation
{
	logNormal(@"Fixing clean objects documentation links...");
	
	// Prepare common variables to optimize loop a bit.
	NSAutoreleasePool* loopAutoreleasePool = nil;
	
	// Handle all files in the database.
	NSDictionary* objects = [database objectForKey:kTKDataMainObjectsKey];
	for (NSString* objectName in objects)
	{
		// Setup the autorelease pool for this iteration. Note that we are releasing the
		// previous iteration pool here as well. This is because we use continue to 
		// skip certain iterations, so releasing at the end of the loop would not work...
		// Also note that after the loop ends, we are releasing the last iteration loop.
		[loopAutoreleasePool drain];
		loopAutoreleasePool = [[NSAutoreleasePool alloc] init];
		
		// Get the required object data.
		NSMutableDictionary* objectData = [objects objectForKey:objectName];
		logVerbose(@"Handling '%@'...", objectName);
		
		[self fixInheritanceForObject:objectName objectData:objectData objects:objects];
		[self fixReferencesForObject:objectName objectData:objectData objects:objects];
		[self fixParaLinksForObject:objectName objectData:objectData objects:objects];
		[self fixEmptyParaForObject:objectName objectData:objectData objects:objects];
	}
	
	// Release last iteration pool.
	[loopAutoreleasePool drain];
	logInfo(@"Finished fixing clean objects documentation links.");
}

//----------------------------------------------------------------------------------------
- (void) saveCleanObjectDocumentationFiles
{
	logNormal(@"Saving clean object documentation files...");
	
	NSDictionary* objects = [database objectForKey:kTKDataMainObjectsKey];
	for (NSString* objectName in objects)
	{
		NSAutoreleasePool* loopAutoreleasePool = [[NSAutoreleasePool alloc] init];		
		NSDictionary* objectData = [objects objectForKey:objectName];
		
		// Prepare the file name.
		NSString* relativeDirectory = [objectData objectForKey:kTKDataObjectRelDirectoryKey];
		NSString* filename = [cmd.outputCleanXMLPath stringByAppendingPathComponent:relativeDirectory];
		filename = [filename stringByAppendingPathComponent:objectName];
		filename = [filename stringByAppendingPathExtension:@"xml"];
		
		// Convert the file.
		logDebug(@"Saving '%@' to '%@'...", objectName, filename);
		NSXMLDocument* document = [objectData objectForKey:kTKDataObjectMarkupKey];
		NSData* documentData = [document XMLDataWithOptions:NSXMLNodePrettyPrint];
		if (![documentData writeToFile:filename atomically:NO])
		{
			logError(@"Failed saving '%@' to '%@'!", objectName, filename);
		}
		
		[loopAutoreleasePool drain];
	}
	
	logInfo(@"Finished saving clean object documentation files...");
}

//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Clean XML "makeup" handling
//////////////////////////////////////////////////////////////////////////////////////////

//----------------------------------------------------------------------------------------
- (void) fixInheritanceForObject:(NSString*) objectName
					  objectData:(NSMutableDictionary*) objectData
						 objects:(NSDictionary*) objects
{
	NSCharacterSet* whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
	
	// Fix the base class link. If the base class is one of the known objects,
	// add the id attribute so we can link to it when creating xhtml. Note that
	// we need to handle protocols here too - if a class conforms to protocols,
	// we should change the name of the node from <base> to <conforms> so that we
	// have easier job while generating html. We should also create the link to
	// the known protoocol.
	NSXMLDocument* cleanDocument = [objectData objectForKey:kTKDataObjectMarkupKey];
	NSArray* baseNodes = [cleanDocument nodesForXPath:@"/object/base" error:nil];
	for (NSXMLElement* baseNode in baseNodes)
	{
		NSString* refValue = [baseNode stringValue];
		if ([objects objectForKey:refValue])
		{
			NSString* linkReference = [self objectReferenceFromObject:objectName toObject:refValue];
			NSXMLNode* idAttribute = [NSXMLNode attributeWithName:@"id" stringValue:linkReference];
			[baseNode addAttribute:idAttribute];
			logVerbose(@"- Found base class reference to '%@' at '%@'.", refValue, linkReference);
		}
		else
		{
			refValue = [refValue stringByTrimmingCharactersInSet:whitespaceSet];
			if ([refValue hasPrefix:@"<"] && [refValue hasSuffix:@">"])
			{					
				NSRange protocolNameRange = NSMakeRange(1, [refValue length] - 2);
				refValue = [refValue substringWithRange:protocolNameRange];
				refValue = [refValue stringByTrimmingCharactersInSet:whitespaceSet];
				
				NSXMLElement* protocolNode = [NSXMLNode elementWithName:@"protocol"];
				[protocolNode setStringValue:refValue];
				
				if ([objects objectForKey:refValue])
				{
					NSString* linkReference = [self objectReferenceFromObject:objectName toObject:refValue];
					NSXMLNode* idAttribute = [NSXMLNode attributeWithName:@"id" stringValue:linkReference];
					[protocolNode addAttribute:idAttribute];
					logVerbose(@"- Found protocol reference to '%@' at '%@'.", refValue, linkReference);
				}
				else
				{
					logVerbose(@"- Found protocol reference to '%@'.", refValue);
				}
				
				NSUInteger index = [baseNode index];
				NSXMLElement* parentNode = (NSXMLElement*)[baseNode parent];
				[parentNode replaceChildAtIndex:index withNode:protocolNode];
			}
		}
	}	
}

//----------------------------------------------------------------------------------------
- (void) fixReferencesForObject:(NSString*) objectName
					 objectData:(NSMutableDictionary*) objectData
						objects:(NSDictionary*) objects
{
	NSCharacterSet* whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
	NSCharacterSet* classStartSet = [NSCharacterSet characterSetWithCharactersInString:@"("];
	NSCharacterSet* classEndSet = [NSCharacterSet characterSetWithCharactersInString:@")"];
	
	// Now look for all <ref> nodes. Then determine the type of link from the link
	// text. The link can either be internal, within the same object or it can be
	// to a member of another object.
	NSXMLDocument* cleanDocument = [objectData objectForKey:kTKDataObjectMarkupKey];
	NSArray* refNodes = [cleanDocument nodesForXPath:@"//ref" error:nil];
	for (NSXMLElement* refNode in refNodes)
	{
		// Get the reference (link) object and member components. The links from
		// doxygen have the format "memberName (ClassName)". The member name includes
		// all the required objective-c colons for methods. Note that some links may 
		// only contain member and some only object components! The links that only
		// contain object component don't encapsulate the object name within the
		// parenthesis! However these are all links to the current object, so we can
		// easily determine the type by comparing to the current object name.
		NSString* refValue = [refNode stringValue];
		if ([refValue length] > 0)
		{
			NSString* refObject = nil;
			NSString* refMember = nil;
			NSScanner* scanner = [NSScanner scannerWithString:refValue];
			
			// If we cannot parse the value of the tag, write the error and continue
			// with next one. Although this should not really happen since we only
			// come here if some text is found, it's still nice to obey the framework...
			if (![scanner scanUpToCharactersFromSet:classStartSet intoString:&refMember])
			{
				logNormal(@"Skipping reference '%@' for object '%@' because tag value was invalid!",
						  refValue,
						  refMember);
				continue;
			}
			refMember = [refMember stringByTrimmingCharactersInSet:whitespaceSet];
			
			// Find and parse the object name part if it exists.
			if ([scanner scanCharactersFromSet:classStartSet intoString:NULL])
			{
				if ([scanner scanUpToCharactersFromSet:classEndSet intoString:&refObject])
				{
					refObject = [refObject stringByTrimmingCharactersInSet:whitespaceSet];
				}
			}
			
			// If we only have one component, we should first determine if it
			// represents an object name or member name. In the second case, the
			// reference is alredy setup properly. In the first case, however, we
			// need to swapt the object and member reference.
			if (!refObject && [objects objectForKey:refMember])
			{
				refObject = refMember;
				refMember = nil;
			}
			
			// If we have both components and the object part points to current
			// object, we should discard it and only use member component.
			if (refObject && refMember && [refObject isEqualToString:objectName])
			{
				refObject = nil;
			}
			
			// Prepare the reference description. Again it depends on the components
			// of the reference value. If both components are present, we should
			// combine them. Otherwise just use the one that is available. Note that
			// in case this is inter-file link we should check if we need to link to
			// another sub-directory.
			NSString* linkDescription = nil;
			NSString* linkReference = nil;
			if (refObject && refMember)
			{
				linkDescription = [NSString stringWithFormat:@"[%@ %@]", refObject, refMember];
				linkReference = [NSString stringWithFormat:@"#%@", refMember];
			}
			else if (refObject)
			{
				linkDescription = refObject;
				linkReference = @"";
			}
			else
			{
				linkDescription = refMember;
				linkReference = [NSString stringWithFormat:@"#%@", refMember];
			}
			
			// Check if we need to link to another directory.
			if (refObject && ![refObject isEqualToString:objectName])
			{
				NSString* linkPath = [self objectReferenceFromObject:objectName toObject:refObject];
				linkReference = [NSString stringWithFormat:@"%@%@", linkPath, linkReference];
			}
			
			// Update the <ref> tag. First we need to remove any existing id
			// attribute otherwise the new one will not be used. Then we need to
			// replace the value with the new description.
			NSXMLNode* idAttribute = [NSXMLNode attributeWithName:@"id" stringValue:linkReference];
			[refNode removeAttributeForName:@"id"];
			[refNode addAttribute:idAttribute];
			[refNode setStringValue:linkDescription];
			logVerbose(@"- Found reference to %@ at '%@'.", linkDescription, linkReference);
		}
	}
}

//----------------------------------------------------------------------------------------
- (void) fixParaLinksForObject:(NSString*) objectName
					objectData:(NSMutableDictionary*) objectData
					   objects:(NSDictionary*) objects
{
	NSCharacterSet* whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
	NSMutableDictionary* replacements = [NSMutableDictionary dictionary];
	
	// We also need to handle broken doxygen member links handling. This is especially
	// evident in categories where the links to member functions are not properly
	// handled at all. At the moment we only handle members which are expressed either
	// as ::<membername> or <membername>() notation. Since doxygen skips these, and
	// leaves the format as it was written in the original documentation, we can
	// easily find them in the source text without worrying about breaking the links
	// we fixed in the above loop.
	NSXMLDocument* cleanDocument = [objectData objectForKey:kTKDataObjectMarkupKey];
	NSArray* textNodes = [cleanDocument nodesForXPath:@"//para/text()|//para/*/text()" error:nil];
	for (NSXMLNode* textNode in textNodes)
	{
		// Scan the text word by word and check the words for possible member links.
		// For each detected member link, add the original and replacement text to
		// the replacements dictionary. We'll use it later on to replace all occurences
		// of the text node string and then replace the whole text node string value.
		NSString* word = nil;			
		NSScanner* scanner = [NSScanner scannerWithString:[textNode stringValue]];
		while ([scanner scanUpToCharactersFromSet:whitespaceSet intoString:&word])
		{
			// Fix members that are declared with two colons. Skip words which are composed
			// from double colons only so that users can still use that in documentation.
			if ([word hasPrefix:@"::"] && [word length] > 2 && ![replacements objectForKey:word])
			{
				NSString* member = [word substringFromIndex:2];
				NSString* link = [NSString stringWithFormat:@"<ref id=\"#%@\">%@</ref>", member, member];
				[replacements setObject:link forKey:word];
				logVerbose(@"- Found reference to %@ at '#%@'.", member, member);
			}
			
			// Fix members that are declated with parenthesis. Skip words which are composed
			// from parenthesis only so that users can still use that in documentation.
			if ([word hasSuffix:@"()"] && [word length] > 2 && ![replacements objectForKey:word])
			{
				NSString* member = [word substringToIndex:[word length] - 2];
				NSString* link = [NSString stringWithFormat:@"<ref id=\"#%@\">%@</ref>", member, member];
				[replacements setObject:link forKey:word];
				logVerbose(@"- Found reference to %@ at '#%@'.", member, member);
			}
			
			// Fix known category links.
			NSDictionary* linkedObjectData = [objects objectForKey:word];
			if (linkedObjectData && [[linkedObjectData objectForKey:kTKDataObjectKindKey] isEqualToString:@"category"])
			{
				NSString* link = [self objectReferenceFromObject:objectName toObject:word];
				NSString* linkReference = [NSString stringWithFormat:@"<ref id=\"%@\">%@</ref>", link, word];
				[replacements setObject:linkReference forKey:word];
				logVerbose(@"- Found reference to %@ at '%@'.", word, link);
			}
		}			
	}
	
	// We should replace all found references with correct ones. Note that we
	// must also wrap the replaced string within the <ref> tag. So for example
	// instead of 'work()' we would end with '<ref id="#work">work</ref>'. In order
	// for this to work, we have to export the whole XML, replace all occurences and
	// then re-import the new XML. If we would change text nodes directly, the <ref>
	// tags would be imported as &lt; and similar...
	if ([replacements count] > 0)
	{
		// Replace all occurences of the found member links with the fixed notation.
		NSString* xmlString = [cleanDocument XMLString];
		for (NSString* word in replacements)
		{
			NSString* replacement = [replacements objectForKey:word];
			xmlString = [xmlString stringByReplacingOccurrencesOfString:word withString:replacement];
		}
		
		// Reload the XML from the updated string and replace the old one in the
		// object data. A bit inefficient, but works...
		NSError* error = nil;
		cleanDocument = [[NSXMLDocument alloc] initWithXMLString:xmlString 
														 options:0 
														   error:&error];
		if (!cleanDocument)
		{
			[Systemator throwExceptionWithName:kTKConverterException basedOnError:error];
		}
		[objectData setObject:cleanDocument forKey:kTKDataObjectMarkupKey];
		[cleanDocument release];
	}		
}

//----------------------------------------------------------------------------------------
- (void) fixEmptyParaForObject:(NSString*) objectName
					objectData:(NSMutableDictionary*) objectData
					   objects:(NSDictionary*) objects
{
	if (cmd.removeEmptyParagraphs)
	{
		// Note that 0xFFFC chars are added during clean XML xstl phase, so these have to be
		// removed too - if the paragraph only contains those, we should delete it... Why
		// this happens I don't know, but this fixes it (instead of only deleting the 0xFFFC
		// we are deleting the last 16 unicode chars). If this creates problems in other
		// languages, we should make this code optional.
		NSCharacterSet* whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
		NSCharacterSet* customSet = [NSCharacterSet characterSetWithRange:NSMakeRange(0xFFF0, 16)];
		
		// Find all paragraphs that only contain empty text and remove them. This will result
		// in better looking documentation. Although these are left because spaces or such
		// were used in the documentation, in most cases they are not desired. For example,
		// Xcode automatically appends a space for each empty documentation line in my style
		// of documenting; since I don't want to deal with this, I will fix it after the
		// documentation has been created.	
		NSXMLDocument* cleanDocument = [objectData objectForKey:kTKDataObjectMarkupKey];
		NSArray* paraNodes = [cleanDocument nodesForXPath:@"//para" error:nil];
		for (NSXMLElement* paraNode in paraNodes)
		{
			NSString* paragraph = [paraNode stringValue];
			paragraph = [paragraph stringByTrimmingCharactersInSet:whitespaceSet];
			paragraph = [paragraph stringByTrimmingCharactersInSet:customSet];
			if ([paraNode childCount] == 0 || [paragraph length] == 0)
			{
				NSXMLElement* parent = (NSXMLElement*)[paraNode parent];
				logVerbose(@"- Removing empty paragraph '%@' index %d from '%@'...",
						   paraNode,
						   [paraNode index],
						   [parent name]);
				[parent removeChildAtIndex:[paraNode index]];
			}
		}		
	}
}

//////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Helper methods
//////////////////////////////////////////////////////////////////////////////////////////

//----------------------------------------------------------------------------------------
- (NSString*) objectReferenceFromObject:(NSString*) source 
							   toObject:(NSString*) destination
{
	NSDictionary* objects = [database objectForKey:kTKDataMainObjectsKey];
	
	// Get the source and destination object's data.
	NSDictionary* sourceData = [objects objectForKey:source];
	NSDictionary* destinationData = [objects objectForKey:destination];
	
	// Get the source and destination object's sub directory.
	NSString* sourceSubdir = [sourceData objectForKey:kTKDataObjectRelDirectoryKey];
	NSString* destinationSubdir = [destinationData objectForKey:kTKDataObjectRelDirectoryKey];
	
	// If the two subdirectories are not the same, we should prepend the relative path.
	if (![sourceSubdir isEqualToString:destinationSubdir])
	{
		return [NSString stringWithFormat:@"../%@/%@.html", destinationSubdir, destination];
	}
	
	return [NSString stringWithFormat:@"%@.html", destination];
}

@end