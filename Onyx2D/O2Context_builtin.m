/*
 * Copyright (c) 2007 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and /or associated documentation files
 * (the "Materials "), to deal in the Materials without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Materials,
 * and to permit persons to whom the Materials are furnished to do so,
 * subject to the following conditions: 
 *
 * The above copyright notice and this permission notice shall be included 
 * in all copies or substantial portions of the Materials. 
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE MATERIALS OR
 * THE USE OR OTHER DEALINGS IN THE MATERIALS.
 */
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2MutablePath.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2GraphicsState.h>
#import "VGPath.h"
#import <Onyx2D/O2Paint_image.h>
#import <Onyx2D/O2Paint_color.h>
#import <Onyx2D/O2Paint_axialGradient.h>
#import <Onyx2D/O2Paint_radialGradient.h>
#import "O2Blending.h"
#import <Onyx2D/O2Shading.h>

#define MAX_SAMPLES     COVERAGE_MULTIPLIER

void O2DContextClipAndFillEdges(O2Context_builtin *self,int fillRuleMask);

@implementation O2Context_builtin

static inline O2GState *currentState(O2Context *self){        
   return [self->_stateStack lastObject];
}

+(BOOL)canInitBitmap {
   return YES;
}

+(BOOL)canInitBackingWithContext:(O2Context *)context deviceDictionary:(NSDictionary *)deviceDictionary {
   NSString *name=[deviceDictionary objectForKey:@"CGContext"];

   if(name==nil)
    return YES;
    
   return [name isEqual:@"Onyx"];
}

-(void)reallocateForSurface {
   size_t width=O2ImageGetWidth(_surface);
   
    free(self->_winding);
    // +1 is so we can modify the the next winding value without a bounds check
    self->_winding=calloc((width*MAX_SAMPLES)+1,sizeof(int));
    free(self->_increase);
    self->_increase=malloc(width*sizeof(int));
    int i;
    for(i=0;i<width;i++)
     self->_increase[i]=INT_MAX;
}


-initWithSurface:(O2Surface *)surface flipped:(BOOL)flipped {
   [super initWithSurface:surface flipped:flipped];
        
   _clipContext=nil;
   _paint=[[O2Paint_color alloc] initWithGray:0 alpha:1];

   O2RasterizeSetBlendMode(self,kO2BlendModeNormal);

   _vpwidth=self->_vpheight=0;
   
   _edgeCount=0;
   _edgeCapacity=256;
   _edges=NSZoneMalloc(NULL,self->_edgeCapacity*sizeof(Edge *));
   _sortCache=NSZoneMalloc(NULL,(self->_edgeCapacity/2 + 1)*sizeof(Edge *));
   
   samplesX=NSZoneMalloc(NULL,MAX_SAMPLES*sizeof(O2Float));

   O2RasterizerSetViewport(self,0,0,O2ImageGetWidth(_surface),O2ImageGetHeight(_surface));
   [self reallocateForSurface];
   return self;
}

-initWithSize:(O2Size)size context:(O2Context *)context {
   O2Surface *surface=[context createSurfaceWithWidth:size.width height:size.height];
   
   if(surface==nil){
    [self dealloc];
    return nil;
   }
   
   [self initWithSurface:surface flipped:NO];
   
   [surface release];
   
   return self;
}

-(void)dealloc {
   [_clipContext release];
   [_paint release];
   
   if(_edges!=NULL){
    int i;
    for(i=0;i<_edgeCount;i++)
     NSZoneFree(NULL,_edges[i]);

    NSZoneFree(NULL,_edges);
   }
   if(_sortCache!=NULL)
    NSZoneFree(NULL,_sortCache);

   if(_winding!=NULL) 
    free(_winding);
   if(_increase!=NULL)
    free(_increase);
   if(samplesX!=NULL)
    NSZoneFree(NULL,samplesX);
   
   [super dealloc];
}

-(O2Surface *)surface {
   return _surface;
}

-(void)setWidth:(size_t)width height:(size_t)height reallocateOnlyIfRequired:(BOOL)roir {
   [_surface setWidth:width height:height reallocateOnlyIfRequired:roir];
   [self reallocateForSurface];
   O2RasterizerSetViewport(self,0,0,O2ImageGetWidth(_surface),O2ImageGetHeight(_surface));
   O2AffineTransform flip={1,0,0,-1,0,O2ImageGetHeight(_surface)};
   O2GStateSetDeviceSpaceCTM(currentState(self),flip);
}

-(O2Surface *)createSurfaceWithWidth:(size_t)width height:(size_t)height {
  return [[O2Surface alloc] initWithBytes:NULL width:width height:height bitsPerComponent:O2ImageGetBitsPerComponent(_surface) bytesPerRow:O2ImageGetBytesPerRow(_surface) colorSpace:O2ImageGetColorSpace(_surface) bitmapInfo:O2ImageGetBitmapInfo(_surface)];
}

-(O2Size)size {
   return O2SizeMake(O2ImageGetWidth(_surface),O2ImageGetHeight(_surface));
}

-(void)beginTransparencyLayerWithInfo:(NSDictionary *)unused {
   O2LayerRef layer=O2LayerCreateWithContext(self,[self size],unused);
   
   [self->_layerStack addObject:layer];
   O2LayerRelease(layer);
   O2ContextSaveGState(self);
}

-(void)endTransparencyLayer {
   O2LayerRef layer=O2LayerRetain([self->_layerStack lastObject]);
   
   O2ContextRestoreGState(self);
   [self->_layerStack removeLastObject];
   
   O2Surface *shadow=[self createSurfaceWithWidth:O2ImageGetWidth(_surface) height:O2ImageGetHeight(_surface)];
   O2Size size=[self size];
   
   O2SurfaceGaussianBlur(shadow,O2LayerGetSurface(layer),currentState(self)->_shadowKernel,currentState(self)->_shadowColor);
   O2ContextDrawImage(self,O2RectMake(currentState(self)->_shadowOffset.width,currentState(self)->_shadowOffset.height,size.width,size.height),shadow);
   
   O2ContextDrawLayerInRect(self,O2RectMake(0,0,size.width,size.height),layer);
   O2LayerRelease(layer);
}

void O2ContextDeviceClipReset_builtin(O2Context_builtin *self){
   O2RasterizerSetViewport(self,0,0,O2ImageGetWidth(self->_surface),O2ImageGetHeight(self->_surface));
}

-(void)deviceClipReset {
   O2ContextDeviceClipReset_builtin(self);
}

static void O2ContextClipViewportToPath(O2Context_builtin *self,O2Path *path) {
   O2MutablePath *copy=O2PathCreateMutableCopy(path);
    
   O2PathApplyTransform(copy,O2AffineTransformInvert(currentState(self)->_userSpaceTransform));
   O2PathApplyTransform(copy,currentState(self)->_deviceSpaceTransform);
   O2Rect rect=O2PathGetBoundingBox(copy);
   
   [copy release];

   O2Rect viewport=O2RectMake(self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
   
   viewport=O2RectIntersection(viewport,rect);
   
   self->_vpx=viewport.origin.x;
   self->_vpy=viewport.origin.y;
   self->_vpwidth=viewport.size.width;
   self->_vpheight=viewport.size.height;
}

void O2ContextDeviceClipToNonZeroPath_builtin(O2Context_builtin *self,O2Path *path){
   O2ContextClipViewportToPath(self,path);
}

void O2ContextDeviceClipToEvenOddPath_builtin(O2Context_builtin *self,O2Path *path){
   O2ContextClipViewportToPath(self,path);
}

-(void)deviceClipToNonZeroPath:(O2Path *)path {
   O2ContextDeviceClipToNonZeroPath_builtin(self,path);
}

-(void)deviceClipToEvenOddPath:(O2Path *)path {
   O2ContextDeviceClipToEvenOddPath_builtin(self,path);
}

-(void)deviceClipToMask:(O2Image *)mask inRect:(O2Rect)rect {
//   O2InvalidAbstractInvocation();
}

static O2Paint *paintFromColor(O2Context_builtin *self,O2ColorRef color){
   O2PatternRef pattern=O2ColorGetPattern(color);
   
   if(pattern!=NULL){
    O2Size           size=[pattern bounds].size;
    O2Surface       *surface=[self createSurfaceWithWidth:size.width height:size.height];
    O2BitmapContext *context=[[self->isa alloc] initWithSurface:surface flipped:NO];

    O2ContextClearRect(context,O2RectMake(0,0,size.width,size.height));
// do save/restore? probably pointless
    [pattern drawInContext:context];
    
    O2Paint *result=[[O2Paint_image alloc] initWithImage:surface mode:VG_DRAW_IMAGE_NORMAL paint:nil interpolationQuality:kO2InterpolationNone];
    
    O2ContextRelease(context);
    [surface release];

    return result;
   }
   else {
    size_t    count=O2ColorGetNumberOfComponents(color);
    const float *components=O2ColorGetComponents(color);

    if(count==2)
     return [[O2Paint_color alloc] initWithGray:components[0]  alpha:components[1]];
    if(count==4)
     return [[O2Paint_color alloc] initWithRed:components[0] green:components[1] blue:components[2] alpha:components[3]];
    
    return [[O2Paint_color alloc] initWithGray:0 alpha:1];
   }
}

-(void)drawPath:(O2PathDrawingMode)drawingMode {
   O2GState *gState=currentState(self);
   
   O2RasterizeSetBlendMode(self,gState->_blendMode);

   O2RasterizerSetShouldAntialias(self,gState->_shouldAntialias,gState->_antialiasingQuality);

/* Path construction is affected by the CTM, and the stroke pen is affected by the CTM , this means path points and the stroke can be affected by different transforms as the CTM can change during path construction and before stroking. For example, creation of transformed shapes which are drawn using an untransformed pen. The current tesselator expects everything to be in user coordinates and it tesselates from there into device space, but the path points are already in base coordinates. So, path points are brought from base coordinates into the active coordinate space using an inverted transform and then everything is tesselated using the CTM into device space.  */
 
   O2AffineTransform userToSurfaceMatrix=gState->_deviceSpaceTransform;

   O2PathApplyTransform(_path,O2AffineTransformInvert(gState->_userSpaceTransform));
   VGPath *vgPath=[[VGPath alloc] initWithKGPath:_path];

   if(drawingMode!=kO2PathStroke){
    O2Paint *paint=paintFromColor(self,gState->_fillColor);
    O2DContextSetPaint(self,paint);
    [paint release];
    
    O2AffineTransform surfaceToPaintMatrix =userToSurfaceMatrix;//context->m_pathUserToSurface * context->m_fillPaintToUser;
    
    surfaceToPaintMatrix=O2AffineTransformInvert(surfaceToPaintMatrix);
     O2PaintSetSurfaceToPaintMatrix(paint,surfaceToPaintMatrix);

     VGPathFill(vgPath,userToSurfaceMatrix,self);
                
     VGFillRuleMask fillRule=(drawingMode==kO2PathFill || drawingMode==kO2PathFillStroke)?VG_NON_ZERO:VG_EVEN_ODD;
                
     O2DContextClipAndFillEdges(self,fillRule);
   }

   if(drawingMode>=kO2PathStroke){
    if(gState->_lineWidth > 0.0f){
     O2Paint *paint=paintFromColor(self,gState->_strokeColor);
     O2DContextSetPaint(self,paint);
     [paint release];
     
     O2AffineTransform surfaceToPaintMatrix=userToSurfaceMatrix;// = context->m_pathUserToSurface * context->m_strokePaintToUser;

     surfaceToPaintMatrix=O2AffineTransformInvert(surfaceToPaintMatrix);
      O2PaintSetSurfaceToPaintMatrix(paint,surfaceToPaintMatrix);

      O2RasterizerClear(self);
                                 
      VGPathStroke(vgPath,userToSurfaceMatrix, self, gState->_dashLengths,gState->_dashLengthsCount, gState->_dashPhase, YES /* context->m_strokeDashPhaseReset ? YES : NO*/,
        gState->_lineWidth, gState->_lineCap,  gState->_lineJoin, RI_MAX(gState->_miterLimit, 1.0f));
      O2DContextClipAndFillEdges(self,VG_NON_ZERO);
    }
   }

   O2DContextSetPaint(self,nil);
   [vgPath release];
   O2RasterizerClear(self);
   O2PathReset(_path);
}

-(void)showGlyphs:(const O2Glyph *)glyphs count:(unsigned)count {
#if 0
   O2FontRef font=currentState(self)->_font;
   int i;
   
   for(i=0;i<count;i++){
    O2Glyph    glyph=glyphs[i];
    O2ImageRef stencil;
   }
#endif
}

-(void)drawShading:(O2Shading *)shading {
   O2GState *gState=currentState(self);
   O2Paint         *paint;

   O2RasterizeSetBlendMode(self,gState->_blendMode);
   O2RasterizerSetShouldAntialias(self,gState->_shouldAntialias,gState->_antialiasingQuality);

   if([shading isAxial]){
    paint=[[O2Paint_axialGradient alloc] initWithShading:shading deviceTransform:gState->_deviceSpaceTransform];
   }
   else {
    paint=[[O2Paint_radialGradient alloc] initWithShading:shading deviceTransform:gState->_deviceSpaceTransform];
   }
  

   O2DContextSetPaint(self,paint);
   [paint release];
 
   O2DContextAddEdge(self,O2PointMake(0,0), O2PointMake(0,O2ImageGetHeight(_surface)));
   O2DContextAddEdge(self,O2PointMake(O2ImageGetWidth(_surface),0), O2PointMake(O2ImageGetWidth(_surface),O2ImageGetHeight(_surface)));

   O2DContextClipAndFillEdges(self,VG_NON_ZERO);
   O2RasterizerClear(self);
}

-(void)drawImage:(O2Image *)image inRect:(O2Rect)rect {
   O2GState *gState=currentState(self);
   
   O2AffineTransform xform=O2AffineTransformMakeTranslation(rect.origin.x,rect.origin.y);
   
   xform=O2AffineTransformScale(xform,rect.size.width/(O2Float)O2ImageGetWidth(image),rect.size.height/(O2Float)O2ImageGetHeight(image));
   xform=O2AffineTransformConcat(xform,gState->_deviceSpaceTransform);

   O2AffineTransform i2u=O2AffineTransformMakeTranslation(0,O2ImageGetHeight(image));
   i2u=O2AffineTransformScale(i2u,1,-1);

   xform=O2AffineTransformConcat(i2u,xform);

   O2AffineTransform imageUserToSurface=xform;

 // FIX, adjustable
   O2AffineTransform fillPaintToUser=O2AffineTransformIdentity;
        
		//transform image corners into the surface space
   O2Point p0=O2PointMake(0, 0);
   O2Point p1=O2PointMake(0, (O2Float)O2ImageGetHeight(image));
   O2Point p2=O2PointMake((O2Float)O2ImageGetWidth(image), (O2Float)O2ImageGetHeight(image));
   O2Point p3=O2PointMake((O2Float)O2ImageGetWidth(image), 0);
   p0 = O2PointApplyAffineTransform(p0,imageUserToSurface);
   p1 = O2PointApplyAffineTransform(p1,imageUserToSurface);
   p2 = O2PointApplyAffineTransform(p2,imageUserToSurface);
   p3 = O2PointApplyAffineTransform(p3,imageUserToSurface);


   O2RasterizerSetShouldAntialias(self,gState->_shouldAntialias,gState->_antialiasingQuality);

   O2Paint *paint=paintFromColor(self,gState->_fillColor);
   O2InterpolationQuality iq;
   if(gState->_interpolationQuality==kO2InterpolationDefault)
    iq=kO2InterpolationLow;
   else
    iq=gState->_interpolationQuality;

   O2Paint *imagePaint=[[O2Paint_image alloc] initWithImage:image mode:VG_DRAW_IMAGE_NORMAL paint:paint interpolationQuality:iq];
        
   O2DContextSetPaint(self,imagePaint);

   O2RasterizeSetBlendMode(self,gState->_blendMode);

   O2AffineTransform surfaceToImageMatrix = imageUserToSurface;
   O2AffineTransform surfaceToPaintMatrix = O2AffineTransformConcat(imageUserToSurface,fillPaintToUser);
        
   surfaceToImageMatrix=O2AffineTransformInvert(surfaceToImageMatrix);
   surfaceToPaintMatrix=O2AffineTransformInvert(surfaceToPaintMatrix);
   O2PaintSetSurfaceToPaintMatrix(paint,surfaceToPaintMatrix);
   O2PaintSetSurfaceToPaintMatrix(imagePaint,surfaceToImageMatrix);

   O2DContextAddEdge(self,p0, p1);
   O2DContextAddEdge(self,p1, p2);
   O2DContextAddEdge(self,p2, p3);
   O2DContextAddEdge(self,p3, p0);
   O2DContextClipAndFillEdges(self,VG_EVEN_ODD);

   O2DContextSetPaint(self,nil);
   O2PaintRelease(paint);
   O2PaintRelease(imagePaint);

   O2RasterizerClear(self);
}

-(void)drawLayer:(O2LayerRef)layer inRect:(O2Rect)rect {
   O2ImageRef image=O2LayerGetSurface(layer);
   
   [self drawImage:image inRect:rect];
}

void O2RasterizerSetViewport(O2Context_builtin *self,int x,int y,int width,int height) {
	RI_ASSERT(vpwidth >= 0 && vpheight >= 0);
    self->_vpx=x;
    self->_vpy=y;
    self->_vpwidth=width;
    self->_vpheight=height;
}

void O2RasterizerClear(O2Context_builtin *self) {
   int i;
   for(i=0;i<self->_edgeCount;i++)
    NSZoneFree(NULL,self->_edges[i]);
    
   self->_edgeCount=0;   
}

void O2DContextAddEdge(O2Context_builtin *self,const O2Point v0, const O2Point v1) {

	if(v0.y == v1.y)
		return;	//skip horizontal edges (they don't affect rasterization since we scan horizontally)

    if(v0.y<self->_vpy && v1.y<self->_vpy)  // ignore below miny
     return;
    
    int MaxY=self->_vpy+self->_vpheight;
    
    if(v0.y>=MaxY && v1.y>=MaxY) // ignore above maxy
     return;
         
	Edge *edge=NSZoneMalloc(NULL,sizeof(Edge));
    if(self->_edgeCount+1>=self->_edgeCapacity){
     self->_edgeCapacity*=2;
     self->_edges=NSZoneRealloc(NULL,self->_edges,self->_edgeCapacity*sizeof(Edge *));
     self->_sortCache=NSZoneRealloc(NULL,self->_sortCache,(self->_edgeCapacity/2 + 1)*sizeof(Edge *));
    }
    self->_edges[self->_edgeCount]=edge;
    self->_edgeCount++;
    
    if(v0.y < v1.y){	//edge is going upward
        edge->v0 = v0;
        edge->v1 = v1;
        edge->direction = 1;
    }
    else {	//edge is going downward
        edge->v0 = v1;
        edge->v1 = v0;
        edge->direction = -1;
    }

    edge->next=NULL;
}

// Returns a radical inverse of a given integer for Hammersley point set.
static double radicalInverseBase2(unsigned int i)
{
	if( i == 0 )
		return 0.0;
	double p = 0.0;
	double f = 0.5f;
	double ff = f;
    unsigned int j;
	for(j=0;j<32;j++)
	{
		if( i & (1<<j) )
			p += f;
		f *= ff;
	}
	return p;
}

void O2RasterizerSetShouldAntialias(O2Context_builtin *self,BOOL antialias,int quality) {
 
	//make a sampling pattern

   quality=RI_INT_CLAMP(quality,1,MAX_SAMPLES);
   
   self->alias=(!antialias || quality==1)?YES:NO;
   
#if 0
   {
    self->numSamples=1;
			self->samplesX[0] = 0.5;
			self->samplesInitialY = 0.5;
			self->samplesDeltaY = 0;
			self->samplesWeight = MAX_SAMPLES;
   }
   else
#endif   
   {
    int shift;
    int numberOfSamples=1;
        
    for(shift=0;numberOfSamples<quality;shift++)
     numberOfSamples<<=1;

        self->sampleSizeShift=shift;
		self->numSamples = numberOfSamples;
        int i;

		 self->samplesInitialY = ((O2Float)(0.5f)) / (O2Float)numberOfSamples;
		 self->samplesDeltaY = ((O2Float)(1.0f)) / (O2Float)numberOfSamples;
        for(i=0;i<numberOfSamples;i++){
	     self->samplesX[i] = (O2Float)radicalInverseBase2(i);
         self->samplesWeight=MAX_SAMPLES/numberOfSamples;
        }
    }
}

static void O2ApplyCoverageAndMaskToSpan_lRGBAffff_PRE(O2argb32f *dst,int icoverage,O2Float *mask,O2argb32f *src,int length){
   int i;
   
   for(i=0;i<length;i++){
    O2argb32f r=src[i];
    O2argb32f d=dst[i];
    O2Float coverage=zeroToOneFromCoverage(icoverage);
    O2Float cov=mask[i]*coverage;
     
    dst[i]=O2argb32fAdd(O2argb32fMultiplyByFloat(r , cov) , O2argb32fMultiplyByFloat(d , (1.0f - cov)));
   }
}

static void O2ApplyCoverageToSpan_lRGBAffff_PRE(O2argb32f *dst,int icoverage,O2argb32f *src,int length){
   int i;
   O2Float coverage=zeroToOneFromCoverage(icoverage);
   
   for(i=0;i<length;i++){
    O2argb32f r=src[i];
    O2argb32f d=dst[i];
     
    dst[i]=O2argb32fAdd(O2argb32fMultiplyByFloat(r , coverage) , O2argb32fMultiplyByFloat(d , (1.0f - coverage)));
   }
}
         
static void O2ApplyCoverageAndMaskToSpan_lRGBA8888_PRE(O2argb8u *dst,int icoverage,uint8_t *mask,O2argb8u *src,int length){
   int i;
   
   for(i=0;i<length;i++){
    O2argb8u r=src[i];
    O2argb8u d=dst[i];
    int cov=(mask[i]*icoverage)/255;
    int oneMinusCov=inverseCoverage(cov);
     
    dst[i]=O2argb8uAdd(O2argb8uMultiplyByCoverage(r , cov) , O2argb8uMultiplyByCoverage(d , oneMinusCov));
   }
}

void O2ApplyCoverageToSpan_lRGBA8888_PRE(O2argb8u *dst,int coverage,O2argb8u *src,int length){
   int i;
   
   if(coverage==256){   
    for(i=0;i<length;i++,src++,dst++){    
     *dst=*src;
    }
   }
   else {
    int oneMinusCoverage=inverseCoverage(coverage);
   
    for(i=0;i<length;i++,src++,dst++){
     O2argb8u r=*src;
     O2argb8u d=*dst;
    
     *dst=O2argb8uAdd(O2argb8uMultiplyByCoverage(r , coverage) , O2argb8uMultiplyByCoverage(d , oneMinusCoverage));
    }
   }
}

void O2BlendSpanNormal_8888_coverage(O2argb8u *src,O2argb8u *dst,int coverage,int length){
// Passes Visual Test
   int i;
   
   if(coverage==256){
    for(i=0;i<length;i++,src++,dst++){
     O2argb8u s=*src;
     O2argb8u d=*dst;
     O2argb8u r;
    
     if(s.a==255)
      r=*src;
     else {
      unsigned char sa=255-s.a;

      r.r=RI_INT_MIN((int)s.r+alphaMultiply(d.r,sa),255);
      r.g=RI_INT_MIN((int)s.g+alphaMultiply(d.g,sa),255);
      r.b=RI_INT_MIN((int)s.b+alphaMultiply(d.b,sa),255);
      r.a=RI_INT_MIN((int)s.a+alphaMultiply(d.a,sa),255);
     }
     *dst=r;
    }
   }
   else {
    int oneMinusCoverage=inverseCoverage(coverage);

    for(i=0;i<length;i++,src++,dst++){
     O2argb8u s=*src;
     O2argb8u d=*dst;
     O2argb8u r;
     unsigned char sa=255-s.a;
     
     r.r=RI_INT_MIN((int)s.r+alphaMultiply(d.r,sa),255);
     r.r=multiplyByCoverage(r.r,coverage);
     d.r=(d.r*oneMinusCoverage)/256;
     r.r=RI_INT_MIN((int)r.r+(int)d.r,255);
    
     r.g=RI_INT_MIN((int)s.g+alphaMultiply(d.g,sa),255);
     r.g=multiplyByCoverage(r.g,coverage);
     d.g=(d.g*oneMinusCoverage)/256;
     r.g=RI_INT_MIN((int)r.g+(int)d.g,255);
    
     r.b=RI_INT_MIN((int)s.b+alphaMultiply(d.b,sa),255);
     r.b=multiplyByCoverage(r.b,coverage);
     d.b=(d.b*oneMinusCoverage)/256;
     r.b=RI_INT_MIN((int)r.b+(int)d.b,255);
    
     r.a=RI_INT_MIN((int)s.a+alphaMultiply(d.a,sa),255);
     r.a=multiplyByCoverage(r.a,coverage);
     d.a=(d.a*oneMinusCoverage)/256;
     r.a=RI_INT_MIN((int)r.a+(int)d.a,255);
    
     *dst=r;
    }
   }
}

static void O2BlendSpanCopy_8888_coverage(O2argb8u *src,O2argb8u *dst,int coverage,int length){
// Passes Visual Test
   int i;

   if(coverage==256){
    for(i=0;i<length;i++)
     *dst++=*src++;
   }
   else {
    int oneMinusCoverage=256-coverage;

    for(i=0;i<length;i++,src++,dst++){
     O2argb8u d=*dst;
     O2argb8u r=*src;
    
     r.r=multiplyByCoverage(r.r,coverage);
     d.r=(d.r*oneMinusCoverage)/256;
     r.r=RI_INT_MIN((int)r.r+(int)d.r,255);
    
     r.g=multiplyByCoverage(r.g,coverage);
     d.g=(d.g*oneMinusCoverage)/256;
     r.g=RI_INT_MIN((int)r.g+(int)d.g,255);
    
     r.b=multiplyByCoverage(r.b,coverage);
     d.b=(d.b*oneMinusCoverage)/256;
     r.b=RI_INT_MIN((int)r.b+(int)d.b,255);
    
     r.a=multiplyByCoverage(r.a,coverage);
     d.a=(d.a*oneMinusCoverage)/256;
     r.a=RI_INT_MIN((int)r.a+(int)d.a,255);
     
     *dst=r;
    }
   }
}

/* Paint functions can selectively paint or not paint at all, e.g. gradients with extend turned off, they do this by returning a negative chunk for a pixels which aren't generated and positive chunk for pixels that are. We need to make sure we cover the entire span so we loop until the span is complete.
 */
static inline void O2RasterizeWriteCoverageSpan8888_Normal(O2Surface *surface,O2Surface *mask,O2Paint *paint,int x, int y,int coverage,int length,O2BlendSpan_RGBA8888 blendFunction) {
    O2argb8u *dst=__builtin_alloca(length*sizeof(O2argb8u));
    O2argb8u *direct=surface->_read_lRGBA8888_PRE(surface,x,y,dst,length);
   
    if(direct!=NULL)
     dst=direct;
     
    O2argb8u *src=__builtin_alloca(length*sizeof(O2argb8u));
    
    while(YES){
     int chunk=O2PaintReadSpan_lRGBA8888_PRE(paint,x,y,src,length);
           
     if(chunk<0) // skip
      chunk=-chunk;
     else {
      O2BlendSpanNormal_8888_coverage(src,dst,coverage,chunk);
     // FIXME: doesnt handle mask if present

      if(direct==NULL){
   	 //write result to the destination surface
       O2SurfaceWriteSpan_lRGBA8888_PRE(surface,x,y,dst,chunk);
      }
     }
     length-=chunk;
     if(length==0)
      break;
      
     x+=chunk;
     src+=chunk;
     dst+=chunk;
    }
}


static inline void O2RasterizeWriteCoverageSpan8888_Copy(O2Surface *surface,O2Surface *mask,O2Paint *paint,int x, int y,int coverage,int length,O2BlendSpan_RGBA8888 blendFunction) {
   O2argb8u *dst=__builtin_alloca(length*sizeof(O2argb8u));
   O2argb8u *direct=surface->_read_lRGBA8888_PRE(surface,x,y,dst,length);
   
   if(direct!=NULL)
    dst=direct;
     
   O2argb8u *src=__builtin_alloca(length*sizeof(O2argb8u));
    
   while(YES){
    int chunk=O2PaintReadSpan_lRGBA8888_PRE(paint,x,y,src,length);
           
    if(chunk<0) // skip
     chunk=-chunk;
    else {
     O2BlendSpanCopy_8888_coverage(src,dst,coverage,chunk);
     // FIXME: doesnt handle mask if present

     if(direct==NULL){
     //write result to the destination surface
      O2SurfaceWriteSpan_lRGBA8888_PRE(surface,x,y,dst,chunk);
     }
    }
    
    length-=chunk;
    if(length==0)
     break;
      
    x+=chunk;
    src+=chunk;
    dst+=chunk;
   }
}

static inline void O2RasterizeWriteCoverageSpan8888(O2Surface *surface,O2Surface *mask,O2Paint *paint,int x, int y,int coverage,int length,O2BlendSpan_RGBA8888 blendFunction) {
   O2argb8u *dst=__builtin_alloca(length*sizeof(O2argb8u));
   O2argb8u *direct=surface->_read_lRGBA8888_PRE(surface,x,y,dst,length);
   
   if(direct!=NULL)
    dst=direct;
     
   O2argb8u *src=__builtin_alloca(length*sizeof(O2argb8u));
   
   while(YES){
    int chunk=O2PaintReadSpan_lRGBA8888_PRE(paint,x,y,src,length);

    if(chunk<0) // skip
     chunk=-chunk;
    else {
     blendFunction(src,dst,chunk);
    
     //apply masking
     if(mask==NULL)
      O2ApplyCoverageToSpan_lRGBA8888_PRE(dst,coverage,src,chunk);
     else {
      uint8_t maskSpan[chunk];
     
      O2ImageReadSpan_A8_MASK(mask,x,y,maskSpan,chunk);
      O2ApplyCoverageAndMaskToSpan_lRGBA8888_PRE(dst,coverage,maskSpan,src,chunk);
     }

     if(direct==NULL){
      //write result to the destination surface
      O2SurfaceWriteSpan_lRGBA8888_PRE(surface,x,y,dst,chunk);
     }
    }
    
    length-=chunk;
    if(length==0)
     break;
      
    x+=chunk;
    src+=chunk;
    dst+=chunk;
   }
}

static inline void O2RasterizeWriteCoverageSpanffff(O2Surface *surface,O2Surface *mask,O2Paint *paint,int x, int y,int coverage,int length,O2BlendSpan_RGBAffff blendFunction) {
   O2argb32f *dst=__builtin_alloca(length*sizeof(O2argb32f));
   O2argb32f *direct=O2ImageReadSpan_lRGBAffff_PRE(surface,x,y,dst,length);

   if(direct!=NULL)
    dst=direct;

   O2argb32f *src=__builtin_alloca(length*sizeof(O2argb32f));

   while(YES){
    int chunk=O2PaintReadSpan_lRGBAffff_PRE(paint,x,y,src,length);
    
    if(chunk<0) // skip
     chunk=-chunk;
    else {
     blendFunction(src,dst,chunk);
    
     //apply masking
 	 if(mask==NULL)
      O2ApplyCoverageToSpan_lRGBAffff_PRE(dst,coverage,src,chunk);
     else {
      O2Float maskSpan[length];
     
      O2ImageReadSpan_Af_MASK(mask,x,y,maskSpan,chunk);
      O2ApplyCoverageAndMaskToSpan_lRGBAffff_PRE(dst,coverage,maskSpan,src,chunk);
     }
    
     if(direct==NULL){
  	 //write result to the destination surface
      O2SurfaceWriteSpan_lRGBAffff_PRE(surface,x,y,dst,chunk);
     }
    }

    length-=chunk;
    if(length==0)
     break;
      
    x+=chunk;
    src+=chunk;
    dst+=chunk;
   }
}

static inline void sortEdgesByMinY(Edge **edges,int count,Edge **B){
  int h, i, j, k, l, m, n = count;
  Edge  *A;

  for (h = 1; h < n; h += h)
  {
     for (m = n - 1 - h; m >= 0; m -= h + h)
     {
        l = m - h + 1;
        if (l < 0)
           l = 0;

        for (i = 0, j = l; j <= m; i++, j++)
           B[i] = edges[j];

        for (i = 0, k = l; k < j && j <= m + h; k++)
        {
           A = edges[j];
           if (A->v0.y>B[i]->v0.y)
              edges[k] = B[i++];
           else
           {
              edges[k] = A;
              j++;
           }
        }

        while (k < j)
           edges[k++] = B[i++];
     }
  }
}

static inline void initEdgeForAET(O2Context_builtin *self,Edge *edge,int scany){
   //compute edge min and max x-coordinates for this scanline
   
   O2Point vd = Vector2Subtract(edge->v1,edge->v0);
   O2Float wl = 1.0f /vd.y;
   edge->vdxwl=vd.x*wl;

   if(edge->v0.x<edge->v1.x){
    edge->isVertical=0;
    edge->bminx=edge->v0.x;
    edge->bmaxx=edge->v1.x;
   }
   else {
    edge->isVertical=(edge->v0.x==edge->v1.x)?1:0;
    edge->bminx=edge->v1.x;
    edge->bmaxx=edge->v0.x;
   }
       
   edge->sxPre = edge->v0.x-(edge->v0.y*edge->vdxwl);
   edge->exPre=edge->sxPre;
   edge->sxPre+=(scany-1)*edge->vdxwl;
   edge->exPre+=(scany+1)*edge->vdxwl;

   O2Float autosx = RI_CLAMP(edge->sxPre, edge->bminx, edge->bmaxx);
   O2Float autoex  = RI_CLAMP(edge->exPre, edge->bminx, edge->bmaxx); 
   O2Float minx=RI_MIN(autosx,autoex);
      
   edge->minx = MAX(self->_vpx,minx);
   edge->samples=NSZoneMalloc(NULL,sizeof(O2Float)*self->numSamples);
   
   O2Float *pre=edge->samples;
   int      i,numberOfSamples=self->numSamples;
   O2Float  sampleY=self->samplesInitialY;
   O2Float  deltaY=self->samplesDeltaY;
   O2Float *samplesX=self->samplesX;
       
   O2Float  normalX=edge->v0.y-edge->v1.y;
   O2Float  normalY=edge->v0.x-edge->v1.x;
   O2Float min=0,max=0;
       
   for(i=0;i<numberOfSamples;sampleY+=deltaY,samplesX++,i++){
    O2Float value=sampleY*normalY-*samplesX*normalX;
        
    *pre++ = value;
        
    if(i==0)
     min=max=value;
    else {
     min=MIN(min,value);
     max=MAX(max,value);
    }
   }
   edge->minSample=min;
   edge->maxSample=max;
}

static inline void incrementEdgeForAET(Edge *edge,int vpx){
   edge->sxPre+= edge->vdxwl;
   edge->exPre+= edge->vdxwl;
   
   O2Float autosx=RI_CLAMP(edge->sxPre, edge->bminx, edge->bmaxx);
   O2Float autoex=RI_CLAMP(edge->exPre, edge->bminx, edge->bmaxx); 
   O2Float minx=RI_MIN(autosx,autoex);
      
   edge->minx = MAX(vpx,minx);
}

static inline void removeEdgeFromAET(Edge *edge){
   NSZoneFree(NULL,edge->samples);
}

typedef struct CoverageNode {
   struct CoverageNode *next;
   int scanx;
   int coverage;
   int length;
} CoverageNode;

void O2DContextFillEdgesOnSurface(O2Context_builtin *self,O2Surface *surface,O2Image *mask,O2Paint *paint,int fillRuleMask) {
   int    edgeCount=self->_edgeCount;
   Edge **edges=self->_edges;
      
   CoverageNode *freeCoverage=NULL;
   CoverageNode *currentCoverage=NULL;
   
   sortEdgesByMinY(edges,edgeCount,self->_sortCache);

   int ylimit=self->_vpy+self->_vpheight;
   int xlimit=self->_vpx+self->_vpwidth;

   Edge *activeRoot=NULL;
   int nextAvailableEdge=0;

   int scany;

   int *winding=self->_winding;
   int  numberOfSamples=self->numSamples;
   int  shiftNumberOfSamples=self->sampleSizeShift;
   int  totalActiveEdges=0;
   int  totalActiveVerticalEdgesFullCoverage=0;
   
   for(scany=self->_vpy;scany<ylimit;scany++){
    Edge *edge,*previous=NULL;
    int   unchangedActiveEdges=1;
    
    // increment and remove edges out of range
    for(edge=activeRoot;edge!=NULL;edge=edge->next){
     if(edge->v1.y>scany){
      incrementEdgeForAET(edge,self->_vpx);
      previous=edge;
      
      if(edge->isVertical){
       if(edge->v0.y<scany && edge->v1.y>=(scany+1)){
        if(!edge->isFullCoverage){
         edge->isFullCoverage=1;
         unchangedActiveEdges=0;
         totalActiveVerticalEdgesFullCoverage++;
        }
       }
       else {
        if(edge->isFullCoverage){
         edge->isFullCoverage=0;
         unchangedActiveEdges=0;
         totalActiveVerticalEdgesFullCoverage--;
        }
       }
      }
     }
     else {
      unchangedActiveEdges=0;
      
      totalActiveEdges--;
      if(edge->isVertical && edge->isFullCoverage)
       totalActiveVerticalEdgesFullCoverage--;
      
      removeEdgeFromAET(edge);
      if(previous==NULL)
       activeRoot=edge->next;
      else
       previous->next=edge->next;
     }
    }

     // load more available edges
    for(;nextAvailableEdge<edgeCount;nextAvailableEdge++){
     edge=edges[nextAvailableEdge];
        
     if(edge->v0.y>=(scany+1))
      break;
     
     unchangedActiveEdges=0;
     edge->next=activeRoot;
     activeRoot=edge;
     initEdgeForAET(self,edge,scany);
     totalActiveEdges++;
     
     if(edge->isVertical){
      if(edge->v0.y<scany && edge->v1.y>=(scany+1)){
       edge->isFullCoverage=1;
       totalActiveVerticalEdgesFullCoverage++;
      }
      else {
       edge->isFullCoverage=0;
      }
     }
    }

    if(unchangedActiveEdges){
     if(activeRoot==NULL && nextAvailableEdge==edgeCount)
      break;
      
     if(totalActiveVerticalEdgesFullCoverage==totalActiveEdges){
      CoverageNode *node;
      
      for(node=currentCoverage;node!=NULL;node=node->next){
#if 0
       if(node->scanx<self->_vpx || node->scanx+node->length>xlimit || scany>=ylimit || scany<self->_vpy){
        NSLog(@"drawing out of viewport, node %d %d %d",node->scanx,scany,node->length);
        NSLog(@"viewport=%d %d %d %d",self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
        NSLog(@"xlimit=%d,ylimit=%d",xlimit,ylimit);
        }
#endif
       self->_writeCoverageFunction(surface,mask,paint,node->scanx,scany,node->coverage,node->length,self->_blendFunction);
      }
      continue;
     }
    }
    
    int minx=xlimit,maxx=0;
    int *increase=self->_increase;

    for(edge=activeRoot;edge!=NULL;edge=edge->next){
     if(edge->minx>=xlimit){
      maxx=MAX(maxx,xlimit);
      continue;
     }

     O2Float  deltaY=self->samplesDeltaY;
     O2Float  scanFloatY=scany+self->samplesInitialY;
     O2Float  v0y=edge->v0.y;
     O2Float  v1y=edge->v1.y;

     int      belowY=0;
     int      aboveY;
       
     for(;scanFloatY<v0y && belowY<numberOfSamples;scanFloatY+=deltaY)
      belowY++;

     if(scany+1<v1y)
      aboveY=numberOfSamples;
     else {
      aboveY=belowY;
      for(;scanFloatY<v1y && aboveY<numberOfSamples;scanFloatY+=deltaY)
       aboveY++;
     }
      
      // it is possible for the edge to be inside the scanline a tiny bit and below/above first/last sample, skip it
     if(aboveY-belowY==0)
      continue;

     int direction=edge->direction;
     int scanx=edge->minx;
       
     minx=MIN(minx,scanx);

     O2Float normalX=edge->v0.y-edge->v1.y;
     O2Float normalY=edge->v0.x-edge->v1.x;
     O2Float pcxnormal=(scanx-edge->v0.x)*normalX-(scany-edge->v0.y)*normalY;
        
     int *windptr=winding+(scanx<<shiftNumberOfSamples);
            
     O2Float *pre=edge->samples;
            
     for(;;pcxnormal+=normalX,windptr+=numberOfSamples){
      /*
        Some edges do have pcxnormal>edge->maxSample when the normalX is less than zero
        we should be able to eliminate that condition prior to the loop to avoid an iteration.
        
        For now they just end up in the general loop
       */
       
      if(increase[scanx]==INT_MAX)
       increase[scanx]=0;
                       
      if(pcxnormal<=edge->minSample){
        windptr[belowY]+=direction;
                                   
        if(aboveY!=numberOfSamples)
         windptr[aboveY]-=direction;
        else if(belowY==0){
         increase[scanx]+=direction;
         break;
        }
       }
       else {
        int idx=belowY;

         while(idx<aboveY){
          if(pcxnormal<=pre[idx]){
           windptr[idx]+=direction;
           windptr[idx+1]-=direction;
          }
                         
          idx++;
         }
          
        if(aboveY==numberOfSamples){
         // if we overwrote past the last value, undo it, this is cheaper than not writing it
         if(pcxnormal<=pre[idx-1])
          windptr[idx]+=direction;
        }
       }

      scanx++;
      if(scanx==xlimit)
       break;
     }

     maxx=MAX(maxx,scanx);

    }        
    minx=MAX(self->_vpx,minx);
    maxx=MIN(xlimit,maxx+1);
        
    int *maxAdvance=increase+maxx;

    increase+=minx;
    for(;increase<maxAdvance;increase++)               
     if(*increase!=INT_MAX){
      break;
     }
         
 	int accum=0;

    int *windptr=winding+((increase-self->_increase)<<shiftNumberOfSamples);
    int *windend=windptr+numberOfSamples;
    
    CoverageNode *node;
    for(node=currentCoverage;node!=NULL;){
     CoverageNode *next=node->next;
     node->next=freeCoverage;
     freeCoverage=node;
     node=next;
    }
    currentCoverage=NULL;    

    for(;increase<maxAdvance;){
     int total=accum;
     int coverage=0;

     if(fillRuleMask==1){
      do{       
       total+=*windptr;
       
       coverage+=(total&0x01);

       *windptr++=0;
      }while(windptr<windend);
     }
     else {
      do{
       total+=*windptr;
       
       coverage+=total?1:0;

       *windptr++=0;
      }while(windptr<windend);
     }

     int *advance=increase+1;
     for(;advance<maxAdvance;advance++)
      if(*advance!=INT_MAX){
       break;
      }

	    if(coverage>0){

      if(self->alias)
       coverage=256;
      else
       coverage*=self->samplesWeight;
      
      int scanx=increase-self->_increase;
      
      CoverageNode *node;
      
      if(freeCoverage==NULL)
       node=NSZoneMalloc(NULL,sizeof(CoverageNode));
      else {
       node=freeCoverage;
       freeCoverage=freeCoverage->next;
      }
      node->next=currentCoverage;
      currentCoverage=node;
      node->scanx=scanx;
      node->coverage=coverage;
      node->length=(advance-increase);
     }
     
     windend+=(advance-increase)<<shiftNumberOfSamples;
     windptr=windend-numberOfSamples;

     accum+=*increase;
     *increase=INT_MAX;
     increase=advance;
    }
    
    for(node=currentCoverage;node!=NULL;node=node->next){
#if 0
       if(node->scanx<self->_vpx || node->scanx+node->length>xlimit || scany>=ylimit || scany<self->_vpy){
        NSLog(@"drawing out of viewport, node %d %d %d",node->scanx,scany,node->length);
        NSLog(@"viewport=%d %d %d %d",self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
        NSLog(@"xlimit=%d,ylimit=%d",xlimit,ylimit);
        }
#endif
     self->_writeCoverageFunction(surface,mask,paint,node->scanx,scany,node->coverage,node->length,self->_blendFunction);
    }
   }
      
   for(;activeRoot!=NULL;activeRoot=activeRoot->next)
    removeEdgeFromAET(activeRoot);

   CoverageNode *node,*next;
   for(node=freeCoverage;node!=NULL;node=next){
    next=node->next;
    NSZoneFree(NULL,node);
   }
   for(node=currentCoverage;node!=NULL;node=next){
    next=node->next;
    NSZoneFree(NULL,node);    
   }
}

void O2DContextClipAndFillEdges(O2Context_builtin *self,int fillRuleMask){
   O2Image *mask=(self->_clipContext!=nil)?self->_clipContext->_surface:nil;
   O2Surface *surface;
   
   if([self->_layerStack count]>0)
    surface=O2LayerGetSurface([self->_layerStack lastObject]);
   else
    surface=self->_surface;
    
   O2DContextFillEdgesOnSurface(self,surface,mask,self->_paint,fillRuleMask);
}

void O2RasterizeSetBlendMode(O2Context_builtin *self,O2BlendMode blendMode) {
   RI_ASSERT(blendMode >= kO2BlendModeNormal && blendMode <= kO2BlendModePlusLighter);
   
   self->_blend_lRGBA8888_PRE=NULL;
   self->_writeCoverage_lRGBA8888_PRE=NULL;
   
   switch(blendMode){
   
    case kO2BlendModeNormal:
     self->_blend_lRGBA8888_PRE=O2BlendSpanNormal_8888;
     self->_blend_lRGBAffff_PRE=O2BlendSpanNormal_ffff;
     self->_writeCoverage_lRGBA8888_PRE=O2RasterizeWriteCoverageSpan8888_Normal;
     break;
     
	case kO2BlendModeMultiply:
     self->_blend_lRGBAffff_PRE=O2BlendSpanMultiply_ffff;
     break;
     
	case kO2BlendModeScreen:
     self->_blend_lRGBAffff_PRE=O2BlendSpanScreen_ffff;
	 break;

	case kO2BlendModeOverlay:
     self->_blend_lRGBAffff_PRE=O2BlendSpanOverlay_ffff;
     break;
        
	case kO2BlendModeDarken:
     self->_blend_lRGBAffff_PRE=O2BlendSpanDarken_ffff;
     break;

	case kO2BlendModeLighten:
     self->_blend_lRGBAffff_PRE=O2BlendSpanLighten_ffff;
     break;

	case kO2BlendModeColorDodge:
     self->_blend_lRGBAffff_PRE=O2BlendSpanColorDodge_ffff;
     break;
        
	case kO2BlendModeColorBurn:
     self->_blend_lRGBAffff_PRE=O2BlendSpanColorBurn_ffff;
     break;
        
	case kO2BlendModeHardLight:
     self->_blend_lRGBAffff_PRE=O2BlendSpanHardLight_ffff;
     break;
        
	case kO2BlendModeSoftLight:
     self->_blend_lRGBAffff_PRE=O2BlendSpanSoftLight_ffff;
     break;
        
	case kO2BlendModeDifference:
     self->_blend_lRGBAffff_PRE=O2BlendSpanDifference_ffff;
     break;
        
	case kO2BlendModeExclusion:
     self->_blend_lRGBAffff_PRE=O2BlendSpanExclusion_ffff;
     break;
        
	case kO2BlendModeHue:
     self->_blend_lRGBAffff_PRE=O2BlendSpanHue_ffff;
     break; 
        
	case kO2BlendModeSaturation:
     self->_blend_lRGBAffff_PRE=O2BlendSpanSaturation_ffff;
     break;
        
	case kO2BlendModeColor:
     self->_blend_lRGBAffff_PRE=O2BlendSpanColor_ffff;
     break;
        
	case kO2BlendModeLuminosity:
     self->_blend_lRGBAffff_PRE=O2BlendSpanLuminosity_ffff;
     break;
        
	case kO2BlendModeClear:
     self->_blend_lRGBA8888_PRE=O2BlendSpanClear_8888;
     self->_blend_lRGBAffff_PRE=O2BlendSpanClear_ffff;
     break;

	case kO2BlendModeCopy:
     self->_blend_lRGBA8888_PRE=O2BlendSpanCopy_8888;
     self->_blend_lRGBAffff_PRE=O2BlendSpanCopy_ffff;
     self->_writeCoverage_lRGBA8888_PRE=O2RasterizeWriteCoverageSpan8888_Copy;
     break;

	case kO2BlendModeSourceIn:
     self->_blend_lRGBA8888_PRE=O2BlendSpanSourceIn_8888;
     self->_blend_lRGBAffff_PRE=O2BlendSpanSourceIn_ffff;
     break;

	case kO2BlendModeSourceOut:
     self->_blend_lRGBAffff_PRE=O2BlendSpanSourceOut_ffff;
     break;

	case kO2BlendModeSourceAtop:
     self->_blend_lRGBAffff_PRE=O2BlendSpanSourceAtop_ffff;
     break;

	case kO2BlendModeDestinationOver:
     self->_blend_lRGBAffff_PRE=O2BlendSpanDestinationOver_ffff;
     break;

	case kO2BlendModeDestinationIn:
     self->_blend_lRGBAffff_PRE=O2BlendSpanDestinationIn_ffff;
     break;

	case kO2BlendModeDestinationOut:
     self->_blend_lRGBAffff_PRE=O2BlendSpanDestinationOut_ffff;
     break;

	case kO2BlendModeDestinationAtop:
     self->_blend_lRGBAffff_PRE=O2BlendSpanDestinationAtop_ffff;
     break;

	case kO2BlendModeXOR:
     self->_blend_lRGBA8888_PRE=O2BlendSpanXOR_8888;
     self->_blend_lRGBAffff_PRE=O2BlendSpanXOR_ffff;
     break;

	case kO2BlendModePlusDarker:
     self->_blend_lRGBAffff_PRE=O2BlendSpanPlusDarker_ffff;
     break;

	case kO2BlendModePlusLighter:
     self->_blend_lRGBA8888_PRE=O2BlendSpanPlusLighter_8888;
     self->_blend_lRGBAffff_PRE=O2BlendSpanPlusLighter_ffff;
     break;
   }

   if(self->_writeCoverage_lRGBA8888_PRE!=NULL){
    self->_blendFunction=NULL;
    self->_writeCoverageFunction=self->_writeCoverage_lRGBA8888_PRE;
   }
   else {
    if(self->_blend_lRGBA8888_PRE!=NULL){
     self->_blendFunction=self->_blend_lRGBA8888_PRE;
     self->_writeCoverageFunction=O2RasterizeWriteCoverageSpan8888;
    }
    else {
     self->_blendFunction=self->_blend_lRGBAffff_PRE;
     self->_writeCoverageFunction=O2RasterizeWriteCoverageSpanffff;
    }
   }
}

void O2DContextSetPaint(O2Context_builtin *self, O2Paint* paint) {
   paint=O2PaintRetain(paint);
   O2PaintRelease(self->_paint);
   self->_paint=paint;
}


@end
