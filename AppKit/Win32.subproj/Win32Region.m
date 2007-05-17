/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/Win32Region.h>

@implementation Win32Region

-initWithHandle:(HRGN)handle {
   _handle=handle;
   return self;
}

-initWithRect:(NSRect)rect {
   POINT points[2]={
    { NSMinX(rect), NSMinY(rect) },
    { NSMaxX(rect), NSMaxY(rect) },
   };
   _handle=CreateRectRgn(points[0].x,points[0].y,points[1].x,points[1].y);
   return self;
}

-(void)dealloc {
   DeleteObject(_handle);
   NSDeallocateObject(self);
}

static inline id copyWithZone(Win32Region *self,NSZone *zone){
   Win32Region *copy=NSCopyObject(self,0,zone);

   copy->_handle=CreateRectRgn(0,0,0,0);
   CombineRgn(copy->_handle,self->_handle,NULL,RGN_COPY);

   return copy;
}

-(id)copy {
   return copyWithZone(self,NULL);
}

-(id)copyWithZone:(NSZone *)zone {
   return copyWithZone(self,zone);
}

-(void)intersectWithRect:(NSRect)rect {
   POINT points[2]={
    { NSMinX(rect), NSMinY(rect) },
    { NSMaxX(rect), NSMaxY(rect) },
   };
   HRGN add;

   add=CreateRectRgn(points[0].x,points[0].y,points[1].x,points[1].y);

   CombineRgn(_handle,_handle,add,RGN_AND);
   DeleteObject(add);
}

-(void)intersectWithRects:(NSRect *)rects count:(unsigned)count {
   HRGN group=NULL;
   int  i;

   for(i=0;i<count;i++){
    NSRect rect=rects[i];
    POINT points[2]={
     { NSMinX(rect), NSMinY(rect) },
     { NSMaxX(rect), NSMaxY(rect) },
    };
    HRGN   add;

    add=CreateRectRgn(points[0].x,points[0].y,points[1].x,points[1].y);

    if(group==NULL)
     group=add;
    else {
     CombineRgn(group,group,add,RGN_OR);
     DeleteObject(add);
    }
   }
   DeleteObject(group);
   CombineRgn(_handle,_handle,group,RGN_AND);
}

-(HRGN)regionHandle {
   return _handle;
}

@end