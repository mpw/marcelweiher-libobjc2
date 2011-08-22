/* Copyright (c) 2011 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/NSObject.h>
#import <Foundation/NSTextCheckingResult.h>
#import <Foundation/NSGeometry.h>
#import <AppKit/AppKitExport.h>

@class NSView, NSMenu,NSViewController,NSPanel;

APPKIT_EXPORT NSString * const NSSpellCheckerDidChangeAutomaticTextReplacementNotification;
APPKIT_EXPORT NSString * const NSSpellCheckerDidChangeAutomaticSpellingCorrectionNotification;

APPKIT_EXPORT NSString * const NSTextCheckingOrthographyKey;
APPKIT_EXPORT NSString * const NSTextCheckingQuotesKey;
APPKIT_EXPORT NSString * const NSTextCheckingReplacementsKey;
APPKIT_EXPORT NSString * const NSTextCheckingReferenceDateKey;
APPKIT_EXPORT NSString * const NSTextCheckingReferenceTimeZoneKey;
APPKIT_EXPORT NSString * const NSTextCheckingDocumentURLKey;
APPKIT_EXPORT NSString * const NSTextCheckingDocumentTitleKey;
APPKIT_EXPORT NSString * const NSTextCheckingDocumentAuthorKey;

enum {
   NSCorrectionIndicatorTypeDefault=0,
   NSCorrectionIndicatorTypeReversion,
   NSCorrectionIndicatorTypeGuesses,
};
typedef NSInteger NSCorrectionIndicatorType;

enum {
   NSCorrectionResponseNone,
   NSCorrectionResponseAccepted,
   NSCorrectionResponseRejected,
   NSCorrectionResponseIgnored,
   NSCorrectionResponseEdited,
   NSCorrectionResponseReverted,
};
typedef NSInteger NSCorrectionResponse;

@interface NSSpellChecker : NSObject {

}

+(NSSpellChecker *)sharedSpellChecker;
+(BOOL)sharedSpellCheckerExists;

+(BOOL)isAutomaticSpellingCorrectionEnabled;
+(BOOL)isAutomaticTextReplacementEnabled;
+(NSInteger)uniqueSpellDocumentTag;

-(NSView *)accessoryView;
-(BOOL)automaticallyIdentifiesLanguages;

-(NSArray *)availableLanguages;

-(NSRange)checkGrammarOfString:(NSString *)string startingAt:(NSInteger)start language:(NSString *)language wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)documentTag details:(NSArray **)outDetails;
-(NSRange)checkSpellingOfString:(NSString *)string startingAt:(NSInteger)offset;

-(NSRange)checkSpellingOfString:(NSString *)string startingAt:(NSInteger)offset language:(NSString *)language wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)wordCount;

-(NSArray *)checkString:(NSString *)string range:(NSRange)range types:(NSTextCheckingTypes)types options:(NSDictionary *)options inSpellDocumentWithTag:(NSInteger)tag orthography:(NSOrthography **)orthography wordCount:(NSInteger *)wordCount;

-(void)closeSpellDocumentWithTag:(NSInteger)tag;

-(NSArray *)completionsForPartialWordRange:(NSRange)partialWordRange inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag;

-(NSString *)correctionForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag;

-(NSInteger)countWordsInString:(NSString *)string language:(NSString *)language;

-(void)dismissCorrectionIndicatorForView:(NSView *)view;

-(NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag;

-(BOOL)hasLearnedWord:(NSString *)word;

-(NSArray *)ignoredWordsInSpellDocumentWithTag:(NSInteger)tag;

-(void)ignoreWord:(NSString *)word inSpellDocumentWithTag:(NSInteger)tag;

-(NSString *)language;

-(void)learnWord:(NSString *)word;

-(NSMenu *)menuForResult:(NSTextCheckingResult *)result string:(NSString *)checkedString options:(NSDictionary *)options atLocation:(NSPoint)location inView:(NSView *)view;

-(void)recordResponse:(NSCorrectionResponse)response toCorrection:(NSString *)correction forWord:(NSString *)word language :(NSString *)language inSpellDocumentWithTag :(NSInteger)tag;

#ifdef NS_BLOCKS
-(NSInteger)requestCheckingOfString:(NSString *)stringToCheck range:(NSRange)range types:(NSTextCheckingTypes)checkingTypes options:(NSDictionary *)options inSpellDocumentWithTag:(NSInteger)tag completionHandler:(void (^)(NSInteger sequenceNumber, NSArray *results, NSOrthography *orthography, NSInteger wordCount))completionHandler;
#endif

-(void)setAccessoryView:(NSView *)view;

-(void)setAutomaticallyIdentifiesLanguages:(BOOL)flag;

-(void)setIgnoredWords:(NSArray *)ignoredWords inSpellDocumentWithTag:(NSInteger)tag;

-(BOOL)setLanguage:(NSString *)language;

-(void)setSubstitutionsPanelAccessoryViewController:(NSViewController *)viewController;

-(void)setWordFieldStringValue:(NSString *)string;

#ifdef NS_BLOCKS
-(void)showCorrectionIndicatorOfType:(NSCorrectionIndicatorType)type primaryString:(NSString *)primaryString alternativeStrings:(NSArray *)alternativeStrings forStringInRect:(NSRect)rect view:(NSView *)view completionHandler:(void (^)(NSString *acceptedString))completionBlock;
#endif

-(NSPanel *)spellingPanel;

-(NSPanel *)substitutionsPanel;

-(NSViewController *)substitutionsPanelAccessoryViewController;

-(void)unlearnWord:(NSString *)word;

-(void)updatePanels;

-(void)updateSpellingPanelWithGrammarString:(NSString *)problemString detail:(NSDictionary *)detail;

-(void)updateSpellingPanelWithMisspelledWord:(NSString *)word;

-(NSArray *)userPreferredLanguages;

-(NSArray *)userQuotesArrayForLanguage:(NSString *)language;

-(NSDictionary *)userReplacementsDictionary;

@end
