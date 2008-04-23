/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "KGContext.h"

@interface KGBitmapContext : KGContext {
   void         *_bytes;
   size_t        _width;
   size_t        _height;
   size_t        _bitsPerComponent;
   size_t        _bytesPerRow;
   KGColorSpace *_colorSpace;
   CGBitmapInfo  _bitmapInfo;
}

-initWithBytes:(void *)bytes width:(size_t)width height:(size_t)height bitsPerComponent:(size_t)bitsPerComponent bytesPerRow:(size_t)bytesPerRow colorSpace:(KGColorSpace *)colorSpace bitmapInfo:(CGBitmapInfo)bitmapInfo;

-(void *)bytes;
-(size_t)width;
-(size_t)height;
-(size_t)bitsPerComponent;
-(size_t)bytesPerRow;
-(KGColorSpace *)colorSpace;
-(CGBitmapInfo)bitmapInfo;

-(size_t)bitsPerPixel;
-(CGImageAlphaInfo)alphaInfo;
-(KGImage *)createImage;

@end
