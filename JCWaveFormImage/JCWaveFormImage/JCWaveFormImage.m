//
//  JCWaveFormImage.m
//  JCWaveFormImage
//
//  Created by John Clem on 12/12/13.
//  Copyright (c) 2013 Pretty Great. All rights reserved.
//

#import "JCWaveFormImage.h"
#import <AVFoundation/AVFoundation.h>

#define absX(x) (x<0?0-x:x)
#define minMaxX(x,mn,mx) (x<=mn?mn:(x>=mx?mx:x))
#define noiseFloor (-50.0)
#define decibel(amplitude) (20.0 * log10(absX(amplitude)/32767.0))

@implementation JCWaveFormImage
{
    JCWaveformStyle _style;
}

- (id)initWithStyle:(JCWaveformStyle)style
{
    self = [super init];
    if (self) {
        _graphColor = [NSColor whiteColor];
        _style = style;
    }
    
    return self;
}

+ (NSImage *)waveformForAssetAtURL:(NSURL *)url
                             color:(NSColor *)color
                              size:(CGSize)size
                             scale:(CGFloat)scale
                             style:(JCWaveformStyle)style
{
    AVURLAsset *urlA = [AVURLAsset URLAssetWithURL:url options:nil];
    JCWaveFormImage *waveformImage = [[JCWaveFormImage alloc] initWithStyle:style];
    
    waveformImage.graphColor = color;
    size.width *= scale;
    size.height *= scale;
    NSData *imageData = [waveformImage renderPNGAudioPictogramLogForAssett:urlA withSize:size];
    
    return [[NSImage alloc] initWithData:imageData];
}

- (void)fillContext:(CGContextRef)context withRect:(CGRect)rect withColor:(NSColor *)color
{
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextSetAlpha(context, 1.0);
    CGContextFillRect(context, rect);
}

- (void)fillBackgroundInContext:(CGContextRef)context withColor:(NSColor *)backgroundColor
{
    CGSize imageSize = CGSizeMake(_imageWidth, _imageHeight);
    CGRect rect = CGRectZero;
    rect.size = imageSize;
    
    [self fillContext:context withRect:(CGRect) rect withColor:backgroundColor];
}

- (void)drawGraphWithStyle:(JCWaveformStyle)style
                    inRect:(CGRect)rect
                 onContext:(CGContextRef)context
                 withColor:(CGColorRef)graphColor {
    
    float graphCenter = rect.size.height / 2;
    float verticalPaddingDivisor = 1.2; // 2 = 50 % of height
    float sampleAdjustmentFactor = (rect.size.height / verticalPaddingDivisor) / 2;
    switch (style) {
        case JCWaveformStyleStripes:
            for (NSInteger intSample = 0; intSample < _sampleCount; intSample++) {
                Float32 sampleValue = (Float32) *_samples++;
                float pixels = (1.0 + sampleValue) * sampleAdjustmentFactor;
                float amplitudeUp = graphCenter - pixels;
                float amplitudeDown = graphCenter + pixels;
                
                if (intSample % 5 != 0) continue;
                CGContextMoveToPoint(context, intSample, amplitudeUp);
                CGContextAddLineToPoint(context, intSample, amplitudeDown);
                CGContextSetStrokeColorWithColor(context, graphColor);
                CGContextStrokePath(context);
            }
            break;
            
        case JCWaveformStyleFull:
            for (NSInteger pointX = 0; pointX < _sampleCount; pointX++) {
                Float32 sampleValue = (Float32) *_samples++;
                
                float pixels = ((1.0 + sampleValue) * sampleAdjustmentFactor);
                float amplitudeUp = graphCenter - pixels;
                float amplitudeDown = graphCenter + pixels;
                
                CGContextMoveToPoint(context, pointX, amplitudeUp);
                CGContextAddLineToPoint(context, pointX, amplitudeDown);
                CGContextSetStrokeColorWithColor(context, graphColor);
                CGContextStrokePath(context);
            }
            break;
            
        default:
            break;
    }
}

- (NSImage *)audioImageLogGraph:(Float32 *)samples
                   normalizeMax:(Float32)normalizeMax
                    sampleCount:(NSInteger)sampleCount
                     imageWidth:(float)imageWidth
                    imageHeight:(float)imageHeight {
    
    _samples = samples;
    _normalizeMax = normalizeMax;
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    
    _sampleCount = sampleCount;
    _imageHeight = imageHeight;
    _imageWidth = imageWidth;
    [self fillBackgroundInContext:context withColor:[NSColor whiteColor]];
    
    CGColorRef graphColor = self.graphColor.CGColor;
    CGContextSetLineWidth(context, 1.0);
    CGRect graphRect = CGRectMake(0, 0, imageWidth, imageHeight);
    
    [self drawGraphWithStyle:self.style inRect:graphRect onContext:context withColor:graphColor];
    
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    NSImage *newImage = [[NSImage alloc] initWithCGImage:imageRef size:NSMakeSize(imageWidth, imageHeight)];

    NSBitmapImageRep *rep = [[newImage representations] objectAtIndex: 0];
    NSData *data = [rep representationUsingType:NSPNGFileType
                                     properties:nil];
    [data writeToFile:@"/Users/johnnyclem/Desktop/waveform.png" atomically:YES];

    return newImage;
}

- (NSData *)renderPNGAudioPictogramLogForAssett:(AVURLAsset *)songAsset withSize:(CGSize)size {
    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:songAsset error:&error];
    AVAssetTrack *songTrack = [songAsset.tracks objectAtIndex:0];
    
    NSDictionary *outputSettingsDict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                        [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                                        [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                        [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
                                        [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
                                        nil];
    
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:songTrack outputSettings:outputSettingsDict];
    [reader addOutput:output];
    
    UInt32 sampleRate, channelCount = 0;
    NSArray *formatDesc = songTrack.formatDescriptions;
    for (unsigned int i = 0; i < [formatDesc count]; ++i) {
        CMAudioFormatDescriptionRef item = (CMAudioFormatDescriptionRef) CFBridgingRetain([formatDesc objectAtIndex:i]);
        const AudioStreamBasicDescription *fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription(item);
        if (fmtDesc) {
            sampleRate = fmtDesc -> mSampleRate;
            channelCount = fmtDesc -> mChannelsPerFrame;
        }
    }
    
    _graphSize = size;
    NSInteger requiredNumberOfSamples = _graphSize.width;
    UInt32 bytesPerSample = 2 * channelCount;
    Float32 normalizeMax = fabsf(noiseFloor);
    NSMutableData *fullSongData = [[NSMutableData alloc] initWithCapacity:requiredNumberOfSamples];
    [reader startReading];
    
    // first, read entire reader data (end of this while loop; copy all data over)
    NSMutableData *allData = [[NSMutableData alloc] initWithCapacity:requiredNumberOfSamples];
    while (reader.status == AVAssetReaderStatusReading) {
        AVAssetReaderTrackOutput *trackOutput = (AVAssetReaderTrackOutput *) [reader.outputs objectAtIndex:0];
        CMSampleBufferRef sampleBufferRef = [trackOutput copyNextSampleBuffer];
        
        if (sampleBufferRef) {
            CMBlockBufferRef blockBufferRef = CMSampleBufferGetDataBuffer(sampleBufferRef);
            
            size_t length = CMBlockBufferGetDataLength(blockBufferRef);
            NSMutableData *data = [NSMutableData dataWithLength:length];
            CMBlockBufferCopyDataBytes(blockBufferRef, 0, length, data.mutableBytes);
            
            [allData appendData:data];
            
            CMSampleBufferInvalidate(sampleBufferRef);
            CFRelease(sampleBufferRef);
        }
    }
    
    NSData *finalData = nil;
    
    if (reader.status == AVAssetReaderStatusFailed || reader.status == AVAssetReaderStatusUnknown) {
        // Something went wrong. Handle it.
    }
    
    if (reader.status == AVAssetReaderStatusCompleted) {
        NSInteger sampleCount = allData.length / bytesPerSample;
        
        // FOR THE MOMENT WE ASSUME: sampleCount > requiredNumberOfSamples (SEE (a))
        // -> DOWNSAMPLE THE FINAL SAMPLES ARRAY
        // TODO: SUPPORT UPSAMPLING THE DATA
        Float32 samplesPerPixel = sampleCount / (float) requiredNumberOfSamples; // (a) always > 1
        
        // fill the samples with their values
        Float64 totalAmplitude = 0;
        SInt16 *samples = (SInt16 *) allData.mutableBytes;
        int j = 0;
        for (int i = 0; i < requiredNumberOfSamples; i++) {
            Float32 bucketLimit = (i + 1) * samplesPerPixel;
            while (j++ < bucketLimit) {
                Float32 amplitude = (Float32) *samples++;
                amplitude = decibel(amplitude);
                amplitude = minMaxX(amplitude, noiseFloor, 0);
                
                totalAmplitude += amplitude;
            }
            
            Float32 medianAmplitude = totalAmplitude / samplesPerPixel;
            if (fabsf(medianAmplitude) > fabsf(normalizeMax)) {
                normalizeMax = fabsf(medianAmplitude);
            }
            
            [fullSongData appendBytes:&medianAmplitude length:sizeof(medianAmplitude)];
            totalAmplitude = 0;
        }
        
        NSData *normalizedData = [self normalizeData:fullSongData normalizeMax:normalizeMax];
        
        NSImage *graphImage = [self audioImageLogGraph:(Float32 *) normalizedData.bytes
                                          normalizeMax:normalizeMax
                                           sampleCount:fullSongData.length / sizeof(Float32)
                                            imageWidth:requiredNumberOfSamples
                                           imageHeight:_graphSize.height];
        
        finalData = [graphImage TIFFRepresentationUsingCompression:NSTIFFCompressionJPEG factor:0.75];
    }
    
    return finalData;
}

- (NSData *)normalizeData:(NSData *)samples normalizeMax:(Float32)normalizeMax {
    NSMutableData *normalizedData = [[NSMutableData alloc] init];
    Float32 *rawData = (Float32 *) samples.bytes;
    
    for (int sampleIndex = 0; sampleIndex < _graphSize.width; sampleIndex++) {
        Float32 amplitude = (Float32) *rawData++;
        amplitude /= normalizeMax;
        [normalizedData appendBytes:&amplitude length:sizeof(amplitude)];
    }
    
    return normalizedData;
}

@end
