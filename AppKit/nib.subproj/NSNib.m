/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSNib.h>
#import <Foundation/NSURL.h>
#import <AppKit/NSRaise.h>
#import "NSNibKeyedUnarchiver.h"
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSTableCornerView.h>
#import "NSIBObjectData.h"
#import "NSNibHelpConnector.h"
#import "NSCustomObject.h"

NSString *NSNibOwner=@"NSOwner";
NSString *NSNibTopLevelObjects=@"NSNibTopLevelObjects";

@implementation NSNib

-initWithContentsOfFile:(NSString *)path {
   NSString *keyedobjects=path;
   BOOL      isDirectory=NO;
   
   if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
    keyedobjects=[[path stringByAppendingPathComponent:@"keyedobjects"] stringByAppendingPathExtension:@"nib"];
   
   if(!keyedobjects && !isDirectory)
      keyedobjects=path; // assume new-style compiled xib
   
   if((_data=[[NSData alloc] initWithContentsOfFile:keyedobjects])==nil){
    NSLog(@"%s: unable to init nib from file '%@'", __PRETTY_FUNCTION__, keyedobjects);
    [self release];
    return nil;
   }

   _allObjects=[NSMutableArray new];
   
   return self;
}

-initWithContentsOfURL:(NSURL *)url {
   if(![url isFileURL]){
    [self release];
    return nil;
   }
   
   return [self initWithContentsOfFile:[url path]];
}

-initWithNibNamed:(NSString *)name bundle:(NSBundle *)bundle {
   NSString *path=[bundle pathForResource:name ofType:@"nib"];
   
   if(path==nil){
    NSLog(@"%s: unable to init nib from file '%@'", __PRETTY_FUNCTION__, path);
    [self release];
    return nil;
   }
   
   return [self initWithContentsOfFile:path];
}

-(void)dealloc {
   [_data release];
   [_allObjects release];
   [super dealloc];
}

-unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:object {
   [_allObjects addObject:object];
   return object;
}

-(void)unarchiver:(NSKeyedUnarchiver *)unarchiver willReplaceObject:object withObject:replacement {
   NSUInteger index=[_allObjects indexOfObjectIdenticalTo:object];
   [_allObjects replaceObjectAtIndex:index withObject:replacement];
}

-(NSDictionary *)externalNameTable {
   return _nameTable;
}

-(BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)nameTable {
   _nameTable=[nameTable retain];
    NSNibKeyedUnarchiver *unarchiver=[[[NSNibKeyedUnarchiver alloc] initForReadingWithData:_data] autorelease];
    NSIBObjectData    *objectData;
    NSArray           *allObjects;
    int                i,count;
    NSMenu            *menu;
    NSArray           *topLevelObjects;
    
    [unarchiver setDelegate:self];
    
    /*
    TO DO:
     - utf8 in the multinational panel
     - misaligned objects in boxes everywhere
    */
    [unarchiver setClass:[NSTableCornerView class] forClassName:@"_NSCornerView"];
    [unarchiver setClass:[NSNibHelpConnector class] forClassName:@"NSIBHelpConnector"];
    
    objectData=[unarchiver decodeObjectForKey:@"IB.objectdata"];
        
    [objectData buildConnectionsWithNameTable:nameTable];
    if((menu=[objectData mainMenu])!=nil)
     [NSApp setMainMenu:menu];
     
    NSMutableDictionary *aDict = [NSMutableDictionary dictionaryWithDictionary:nameTable];
    [aDict removeObjectForKey:NSNibTopLevelObjects];
    nameTable = aDict;

    // Top-level objects are always retained; if external table contains a mutable
    // array for key NSNibTopLevelObjects, then this array retains all top-level objects,
    // else we simply do a retain on them.
    topLevelObjects = [objectData topLevelObjects];
    if([nameTable objectForKey:NSNibTopLevelObjects])
        [[nameTable objectForKey:NSNibTopLevelObjects] setArray:topLevelObjects];
    else
        [topLevelObjects makeObjectsPerformSelector:@selector(retain)];
    
    // We do not need to add the objects from nameTable to allObjects as they get put into the uid->object table already
    // Do we send awakeFromNib to objects in the nameTable *not* present in the nib ?

    count=[_allObjects count];

    for(i=0;i<count;i++){
     id object=[_allObjects objectAtIndex:i];
     
     if([object respondsToSelector:@selector(awakeFromNib)])
      [object awakeFromNib];
    }

    for(i=0;i<count;i++){
     id object=[_allObjects objectAtIndex:i];

     if([object respondsToSelector:@selector(postAwakeFromNib)])
      [object performSelector:@selector(postAwakeFromNib)];
    }

    [[objectData visibleWindows] makeObjectsPerformSelector:@selector(makeKeyAndOrderFront:) withObject:nil];
    
    [_nameTable release];
    _nameTable=nil;

    return (objectData!=nil);
}

-(BOOL)instantiateNibWithOwner:owner topLevelObjects:(NSArray **)objects {
   NSMutableArray   *topLevelObjects = (objects != NULL ? [[NSMutableArray alloc] init] : nil);
   NSDictionary     *nameTable=[NSDictionary dictionaryWithObjectsAndKeys:owner, NSNibOwner, topLevelObjects, NSNibTopLevelObjects, nil];
   BOOL             result = [self instantiateNibWithExternalNameTable:nameTable];
   
   if(objects != NULL){
       if(result)
           *objects = [NSArray arrayWithArray:topLevelObjects];
       [topLevelObjects release];
   }
   
   return result;
}

@end
