#import "NSGraphicsStyle_uxtheme.h"
#import <AppKit/NSGraphicsContext.h>
#import <Onyx2D/O2Context.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import "Win32DeviceContextWindow.h"

#undef WINVER
#define WINVER 0x0501
#import <uxtheme.h>
#import <tmschema.h>

static void *functionWithName(const char *name){
   void              *result;
   static BOOL        lookForUxTheme=YES;
   static HANDLE      uxtheme=NULL;
   static NSMapTable *table=NULL;
   
   if(lookForUxTheme){
    if((uxtheme=LoadLibrary("UXTHEME"))!=NULL)
     table=NSCreateMapTable(NSObjectMapKeyCallBacks,NSNonOwnedPointerMapValueCallBacks,0);
     
    lookForUxTheme=NO;
   }
   
   if(table==NULL)
    result=NULL;
   else {
    NSString *string=[[NSString alloc] initWithCString:name];
    
    if((result=NSMapGet(table,string))==NULL){
     if((result=GetProcAddress(uxtheme,name))==NULL)
      NSLog(@"GetProcAddress(\"UXTHEME\",%s) FAILED",name);
     else
      NSMapInsert(table,string,result);
    }
    
    [string release];
   }
   
   return result;
}

static BOOL isThemeActive(){
   WINAPI BOOL (*function)(void)=functionWithName("IsThemeActive");
   
   if(function==NULL)
    return NO;
    
   return function();
}

HANDLE openThemeData(HWND window,LPCWSTR classList){
   WINAPI HANDLE (*function)(HWND,LPCWSTR)=functionWithName("OpenThemeData");
   
   if(function==NULL)
    return NULL;
   
   return function(window,classList);
}

void closeThemeData(HANDLE theme){
   WINAPI HRESULT (*function)(HANDLE)=functionWithName("CloseThemeData");
   
   if(function==NULL)
    return;
   
   if(function(theme)!=S_OK)
    NSLog(@"CloseThemeData failed");
}

static BOOL getThemePartSize(HANDLE theme,HDC dc,int partId,int stateId,LPCRECT prc,THEME_SIZE eSize,SIZE *size){
   WINAPI HRESULT (*function)(HANDLE,HDC,int,int,LPCRECT,THEME_SIZE,SIZE *)=functionWithName("GetThemePartSize");
   
   if(function==NULL)
    return NO;
   
   if(function(theme,dc,partId,stateId,prc,eSize,size)!=S_OK){
    NSLog(@"GetThemePartSize failed");
    return NO;
   }
   
   return YES;
}

static BOOL drawThemeBackground(HANDLE theme,HDC dc,int partId,int stateId,const RECT *rect,const RECT *clip){
   WINAPI HRESULT (*function)(HANDLE,HDC,int,int,const RECT *,const RECT *)=functionWithName("DrawThemeBackground");
   
   if(function==NULL)
    return NO;
   
   if(function(theme,dc,partId,stateId,rect,clip)!=S_OK){
    NSLog(@"DrawThemeBackground(%x,%x,%d,%d,{%d %d %d %d}) failed",theme,dc,partId,stateId,rect->top,rect->left,rect->bottom,rect->right);
    return NO;
   }
   return YES;
}

@implementation NSGraphicsStyle(uxtheme)

+allocWithZone:(NSZone *)zone {
   if(isThemeActive())
    return NSAllocateObject([NSGraphicsStyle_uxtheme class],0,zone);
   
   return [super allocWithZone:zone];
}

@end

@implementation NSGraphicsStyle_uxtheme

-(HANDLE)themeForClassList:(LPCWSTR)classList deviceContext:(O2DeviceContext_gdi *)deviceContext  {
   HWND windowHandle=[[deviceContext windowDeviceContext] windowHandle];
   
   if(windowHandle==NULL)
    return NULL;
    
   return openThemeData(windowHandle,classList);
}

static inline RECT transformToRECT(O2AffineTransform matrix,NSRect rect) {
   RECT    result;
   NSPoint point1=O2PointApplyAffineTransform(rect.origin,matrix);
   NSPoint point2=O2PointApplyAffineTransform(NSMakePoint(NSMaxX(rect),NSMaxY(rect)),matrix);

   if(point2.y<point1.y){
    float temp=point2.y;
    point2.y=point1.y;
    point1.y=temp;
   }

   result.top=point1.y;
   result.left=point1.x;
   result.bottom=point2.y;
   result.right=point2.x;
   
   return result;
}

-(O2Context *)context {
   O2Context *context=[[NSGraphicsContext currentContext] graphicsPort];
   
   return context;
}

-(O2DeviceContext_gdi *)deviceContext {
   O2Context *context=[[NSGraphicsContext currentContext] graphicsPort];
   
   if([context respondsToSelector:@selector(deviceContext)]){
    O2DeviceContext_gdi *result=[context performSelector:@selector(deviceContext)];
    
    if([result isKindOfClass:[O2DeviceContext_gdi class]])
     return result;
   }
   
   return nil;
}

-(BOOL)sizeOfPartId:(int)partId stateId:(int)stateId uxthClassId:(int)uxthClassId size:(NSSize *)result {
   O2DeviceContext_gdi *deviceContext=[self deviceContext];
   HANDLE               theme;

   if(deviceContext==nil)
    return NO;
    
   if((theme=[[deviceContext windowDeviceContext] theme:uxthClassId])!=NULL){
    SIZE size;
     
    if(getThemePartSize(theme,[deviceContext dc],partId,stateId,NULL,TS_DRAW,&size)){
     result->width=size.cx;
     result->height=size.cy;
     // should invert translate here
    }    
    return YES;
   }
   return NO;
}

-(BOOL)drawPartId:(int)partId stateId:(int)stateId uxthClassId:(int)uxthClassId inRect:(NSRect)rect {
   O2DeviceContext_gdi *deviceContext=[self deviceContext];
   HANDLE               theme;
   
   if(deviceContext==nil)
    return NO;
       
   if((theme=[[deviceContext windowDeviceContext] theme:uxthClassId])!=NULL){
    O2AffineTransform matrix;
    RECT tlbr;

    matrix=O2ContextGetUserSpaceToDeviceSpaceTransform([self context]);
    tlbr=transformToRECT(matrix,rect);

    drawThemeBackground(theme,[deviceContext dc],partId,stateId,&tlbr,NULL);
    return YES;
   }
   return NO;
}

-(BOOL)drawButtonPartId:(int)partId stateId:(int)stateId inRect:(NSRect)rect {
   return [self drawPartId:partId stateId:stateId uxthClassId:uxthBUTTON inRect:rect];
}

-(void)drawPushButtonNormalInRect:(NSRect)rect defaulted:(BOOL)defaulted {
   if(![self drawButtonPartId:BP_PUSHBUTTON stateId:defaulted?PBS_DEFAULTED:PBS_NORMAL inRect:rect])
    [super drawPushButtonNormalInRect:rect defaulted:defaulted];
}

-(void)drawPushButtonPressedInRect:(NSRect)rect {
   if(![self drawButtonPartId:BP_PUSHBUTTON stateId:PBS_PRESSED inRect:rect])
    [super drawPushButtonPressedInRect:rect];
}

-(BOOL)getPartId:(int *)partId stateId:(int *)stateId forButtonImage:(NSImage *)image enabled:(BOOL)enabled mixed:(BOOL)mixed {
   BOOL valid=NO;

   if([[image name] isEqual:@"NSSwitch"]){
    *partId=BP_CHECKBOX;
    *stateId=enabled?CBS_UNCHECKEDNORMAL:CBS_UNCHECKEDDISABLED;
    valid=YES;
   }
   else if([[image name] isEqual:@"NSHighlightedSwitch"]){
    *partId=BP_CHECKBOX;
    *stateId=mixed?(enabled?CBS_MIXEDNORMAL:CBS_MIXEDDISABLED):(enabled?CBS_CHECKEDNORMAL:CBS_CHECKEDDISABLED);
    valid=YES;
   }
   else if([[image name] isEqual:@"NSRadioButton"]){
    *partId=BP_RADIOBUTTON;
    *stateId=enabled?RBS_UNCHECKEDNORMAL:RBS_UNCHECKEDDISABLED;
    valid=YES;
   }
   else if([[image name] isEqual:@"NSHighlightedRadioButton"]){
    *partId=BP_RADIOBUTTON;
    *stateId=enabled?RBS_CHECKEDNORMAL:RBS_CHECKEDDISABLED;
    valid=YES;
   }
   return valid;
}

-(NSSize)sizeOfButtonImage:(NSImage *)image enabled:(BOOL)enabled mixed:(BOOL)mixed {
   int partId,stateId;
   
   if([self getPartId:&partId stateId:&stateId forButtonImage:image enabled:enabled mixed:mixed]){
    NSSize result;
    
    if([self sizeOfPartId:partId stateId:stateId uxthClassId:uxthBUTTON size:&result])
     return result;
   }
   
   return [super sizeOfButtonImage:image enabled:enabled mixed:mixed];
}

-(void)drawButtonImage:(NSImage *)image inRect:(NSRect)rect enabled:(BOOL)enabled mixed:(BOOL)mixed {
   int partId,stateId;
   
   if([self getPartId:&partId stateId:&stateId forButtonImage:image enabled:enabled mixed:mixed])
    if([self drawButtonPartId:partId stateId:stateId inRect:rect])
     return;

   [super drawButtonImage:image inRect:rect enabled:enabled mixed:mixed];
}

#if 0
// these menu ones don't appear to work
-(void)drawMenuSeparatorInRect:(NSRect)rect {
   if(![self drawPartId:MP_SEPARATOR stateId:MS_NORMAL uxthClassId:uxthMENU inRect:rect])
    [super drawMenuSeparatorInRect:rect];
}

-(void)drawMenuBranchArrowInRect:(NSRect)rect selected:(BOOL)selected {   
   if(![self drawPartId:MP_CHEVRON stateId:selected?MS_SELECTED:MS_NORMAL uxthClassId:uxthMENU inRect:rect])
    [super drawMenuBranchArrowInRect:rect selected:selected];
}
#endif

-(void)drawMenuWindowBackgroundInRect:(NSRect)rect {
   rect.size.width-=1.0;
   rect.size.height-=1.0;

   [[NSColor menuBackgroundColor] setFill];
   NSRectFill(rect);
   [[NSColor controlShadowColor] setStroke];
   NSFrameRect(rect);
}

-(void)drawPopUpButtonWindowBackgroundInRect:(NSRect)rect {
#if 0
   if(![self drawPartId:MENU_POPUPBORDERS stateId:0 uxthClassId:uxthMENU inRect:rect])
    [super drawPopUpButtonWindowBackgroundInRect:rect];
#else
   [[NSColor menuBackgroundColor] setFill];
   NSRectFill(rect);
   [[NSColor blackColor] setStroke];
   NSFrameRect(rect);
#endif
}

-(NSRect)drawProgressIndicatorBackground:(NSRect)rect clipRect:(NSRect)clipRect bezeled:(BOOL)bezeled {
   if(bezeled){
    if([self drawPartId:PP_BAR stateId:0 uxthClassId:uxthPROGRESS inRect:rect])
     return NSInsetRect(rect,3,3);
   }

   return [super drawProgressIndicatorBackground:rect clipRect:clipRect bezeled:bezeled];
}

-(void)drawProgressIndicatorChunk:(NSRect)rect {
   [self drawPartId:PP_CHUNK stateId:0 uxthClassId:uxthPROGRESS inRect:rect];
}

-(void)drawScrollerButtonInRect:(NSRect)rect enabled:(BOOL)enabled pressed:(BOOL)pressed vertical:(BOOL)vertical upOrLeft:(BOOL)upOrLeft {
   int stateId;
   
   if(vertical){
    if(upOrLeft)
     stateId=enabled?(pressed?ABS_UPPRESSED:ABS_UPNORMAL):ABS_UPDISABLED;
    else
     stateId=enabled?(pressed?ABS_DOWNPRESSED:ABS_DOWNNORMAL):ABS_DOWNDISABLED;
    }
   else {
    if(upOrLeft)
     stateId=enabled?(pressed?ABS_LEFTPRESSED:ABS_LEFTNORMAL):ABS_LEFTDISABLED;
    else
     stateId=enabled?(pressed?ABS_RIGHTPRESSED:ABS_RIGHTNORMAL):ABS_RIGHTDISABLED;
   }
   
   if(![self drawPartId:SBP_ARROWBTN stateId:stateId uxthClassId:uxthSCROLLBAR inRect:rect])
    [super drawScrollerButtonInRect:rect enabled:enabled pressed:pressed vertical:vertical upOrLeft:upOrLeft];
}

-(void)drawScrollerKnobInRect:(NSRect)rect vertical:(BOOL)vertical highlight:(BOOL)highlight {
   if(![self drawPartId:vertical?SBP_THUMBBTNVERT:SBP_THUMBBTNHORZ stateId:highlight?SCRBS_PRESSED:SCRBS_NORMAL uxthClassId:uxthSCROLLBAR inRect:rect])
    [super drawScrollerKnobInRect:rect vertical:vertical highlight:highlight];

   [self drawPartId:vertical?SBP_GRIPPERVERT:SBP_GRIPPERHORZ stateId:0 uxthClassId:uxthSCROLLBAR inRect:rect];
}

-(void)drawScrollerTrackInRect:(NSRect)rect vertical:(BOOL)vertical upOrLeft:(BOOL)upOrLeft {
   int partId=vertical?(upOrLeft?SBP_UPPERTRACKVERT:SBP_LOWERTRACKVERT):(upOrLeft?SBP_UPPERTRACKHORZ:SBP_LOWERTRACKHORZ);
   
   if(![self drawPartId:partId stateId:SCRBS_NORMAL uxthClassId:uxthSCROLLBAR inRect:rect])
    [super drawScrollerTrackInRect:rect vertical:vertical upOrLeft:upOrLeft];
}

-(void)drawTableViewHeaderInRect:(NSRect)rect highlighted:(BOOL)highlighted {
   if(![self drawPartId:HP_HEADERITEM stateId:highlighted?HIS_PRESSED:HIS_NORMAL uxthClassId:uxthHEADER inRect:rect])
    [super drawTableViewHeaderInRect:rect highlighted:highlighted];
}

-(void)drawTableViewCornerInRect:(NSRect)rect {
   if(![self drawPartId:HP_HEADERITEM stateId:HIS_NORMAL uxthClassId:uxthHEADER inRect:rect])
    [super drawTableViewCornerInRect:rect];
}

-(void)drawComboBoxButtonInRect:(NSRect)rect enabled:(BOOL)enabled bordered:(BOOL)bordered pressed:(BOOL)pressed {
   if(![self drawPartId:CP_DROPDOWNBUTTON stateId:enabled?(pressed?CBXS_PRESSED:CBXS_NORMAL):CBXS_DISABLED uxthClassId:uxthCOMBOBOX inRect:rect])
    [super drawComboBoxButtonInRect:rect enabled:(BOOL)enabled bordered:bordered pressed:pressed];
}

-(void)drawSliderKnobInRect:(NSRect)rect vertical:(BOOL)vertical highlighted:(BOOL)highlighted hasTickMarks:(BOOL)hasTickMarks tickMarkPosition:(NSTickMarkPosition)tickMarkPosition {
   int partId;
   
   if(vertical){
    if(!hasTickMarks)
     partId=TKP_THUMBVERT;
    else if(tickMarkPosition==NSTickMarkLeft)
     partId=TKP_THUMBLEFT;
    else
     partId=TKP_THUMBRIGHT;
   }
   else {
    if(!hasTickMarks)
     partId=TKP_THUMB;
    else if(tickMarkPosition==NSTickMarkAbove)
     partId=TKP_THUMBTOP;
    else
     partId=TKP_THUMBBOTTOM;
   }
      
   if(![self drawPartId:partId stateId:highlighted?TUS_PRESSED:TUS_NORMAL uxthClassId:uxthTRACKBAR inRect:rect])
    [super drawSliderKnobInRect:rect vertical:vertical highlighted:highlighted hasTickMarks:hasTickMarks tickMarkPosition:tickMarkPosition];
}

-(void)drawSliderTrackInRect:(NSRect)rect vertical:(BOOL)vertical hasTickMarks:(BOOL)hasTickMarks {
   NSRect thin=rect;
   
   if(hasTickMarks){
    if(vertical){
     thin.origin.x+=(thin.size.width-4)/2;
     thin.size.width=4;
    }
    else {
     thin.origin.y+=(thin.size.height-4)/2;
     thin.size.height=4;
    }
   }
   
   if(![self drawPartId:vertical?TKP_TRACKVERT:TKP_TRACK stateId:TRS_NORMAL uxthClassId:uxthTRACKBAR inRect:thin])
    [super drawSliderTrackInRect:rect vertical:vertical hasTickMarks:hasTickMarks];
}

-(void)drawStepperButtonInRect:(NSRect)rect clipRect:(NSRect)clipRect enabled:(BOOL)enabled highlighted:(BOOL)highlighted upNotDown:(BOOL)upNotDown {
   if(![self drawPartId:upNotDown?SPNP_UP:SPNP_DOWN stateId:enabled?DNS_NORMAL:DNS_DISABLED uxthClassId:uxthSPIN inRect:rect])
    [super drawStepperButtonInRect:rect clipRect:(NSRect)clipRect enabled:enabled highlighted:highlighted upNotDown:upNotDown];
}

-(void)drawTabInRect:(NSRect)rect clipRect:(NSRect)clipRect color:(NSColor *)color selected:(BOOL)selected {   
   rect.origin.y-=1;
   
   if(!selected)
    rect.origin.y-=2;
    
   if(![self drawPartId:TABP_TABITEM stateId:selected?TIS_SELECTED:TIS_NORMAL uxthClassId:uxthTAB inRect:rect])
    [super drawTabInRect:rect clipRect:clipRect color:color selected:selected];
}

-(void)drawTabPaneInRect:(NSRect)rect {
   if(![self drawPartId:TABP_PANE stateId:TIS_NORMAL uxthClassId:uxthTAB inRect:rect])
    [super drawTabPaneInRect:rect];
}

-(void)drawTabViewBackgroundInRect:(NSRect)rect {
   if(![self drawPartId:TABP_BODY stateId:TIS_NORMAL uxthClassId:uxthTAB inRect:rect])
    [super drawTabPaneInRect:rect];
}

-(void)drawTextFieldBorderInRect:(NSRect)rect bezeledNotLine:(BOOL)bezeledNotLine {
   if(![self drawPartId:EP_EDITTEXT stateId:ETS_NORMAL uxthClassId:uxthEDIT inRect:rect])
    [super drawTextFieldBorderInRect:rect bezeledNotLine:bezeledNotLine];
}

-(void)drawBoxWithBezelInRect:(NSRect)rect clipRect:(NSRect)clipRect {
   if(![self drawPartId:BP_GROUPBOX stateId:GBS_NORMAL uxthClassId:uxthBUTTON inRect:rect])
    [super drawBoxWithBezelInRect:rect clipRect:clipRect];
}

-(void)drawBoxWithGrooveInRect:(NSRect)rect clipRect:(NSRect)clipRect {
   if(![self drawPartId:BP_GROUPBOX stateId:GBS_NORMAL uxthClassId:uxthBUTTON inRect:rect])
    [super drawBoxWithGrooveInRect:rect clipRect:clipRect];
}

@end
