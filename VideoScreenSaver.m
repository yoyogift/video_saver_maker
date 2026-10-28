#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface VSMLoopScreenSaver_0000000000000000 : ScreenSaverView
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) id endObserver;
@property(nonatomic, copy) NSArray<AVAsset *> *clips;
@property(nonatomic, strong) NSMutableSet<AVPlayerItem *> *ownedItems;
@property(nonatomic) NSUInteger nextIndex;
@end

@implementation VSMLoopScreenSaver_0000000000000000
- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)preview {
    if ((self = [super initWithFrame:frame isPreview:preview])) {
        self.animationTimeInterval = 1;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
    }
    return self;
}

// Loop the actual video track, rather than the container duration. A longer
// audio track or edit-list offset must not become a black gap at the boundary.
- (AVAsset *)videoClipAtURL:(NSURL *)url {
    AVURLAsset *source = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    AVAssetTrack *video = [source tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CMTimeRange range = video.timeRange;
    CMTime duration = source.duration;
#pragma clang diagnostic pop
    if (!video || !CMTIMERANGE_IS_VALID(range) || !CMTIME_IS_NUMERIC(range.duration) ||
        CMTimeCompare(range.duration,kCMTimeZero) <= 0 || !CMTIME_IS_NUMERIC(duration)) return nil;
    range = CMTimeRangeGetIntersection(range,CMTimeRangeMake(kCMTimeZero,duration));
    if (!CMTIME_IS_NUMERIC(range.duration) || CMTimeCompare(range.duration,kCMTimeZero) <= 0) return nil;
    AVMutableComposition *clip = [AVMutableComposition composition];
    AVMutableCompositionTrack *track = [clip addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    if (![track insertTimeRange:range ofTrack:video atTime:kCMTimeZero error:&error]) {
        NSLog(@"Video Saver: could not prepare %@: %@",url.lastPathComponent,error);
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    track.preferredTransform = video.preferredTransform;
#pragma clang diagnostic pop
    return clip;
}

- (AVPlayerItem *)nextItem {
    if (!self.clips.count) return nil;
    AVAsset *clip = self.clips[self.nextIndex % self.clips.count];
    self.nextIndex = (self.nextIndex + 1) % self.clips.count;
    return [AVPlayerItem playerItemWithAsset:clip];
}

- (void)startAnimation {
    [super startAnimation];
    if (self.player) { [self.player play]; return; }
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *manifestURL = [bundle URLForResource:@"Playlist" withExtension:@"plist"];
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfURL:manifestURL];
    NSMutableArray<NSURL *> *movies = [NSMutableArray array];
    for (NSString *file in manifest[@"files"]) {
        NSURL *url = [[bundle resourceURL] URLByAppendingPathComponent:file];
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) [movies addObject:url];
    }
    if ([manifest[@"shuffle"] boolValue]) {
        for (NSUInteger i = movies.count; i > 1; i--) {
            [movies exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        }
    }
    NSMutableArray<AVAsset *> *clips = [NSMutableArray array];
    for (NSURL *url in movies) {
        AVAsset *clip = [self videoClipAtURL:url];
        if (clip) [clips addObject:clip];
    }
    self.clips = clips;
    self.nextIndex = 0;
    if (!clips.count) return;
    self.player = [AVQueuePlayer queuePlayerWithItems:@[]];
    self.player.muted = YES;
    self.player.automaticallyWaitsToMinimizeStalling = YES;
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;
    if (clips.count == 1) {
        // AVPlayerLooper prepares replicas before reaching the end; do not
        // manually seek or modify its queue during looping.
        self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:[self nextItem]];
    } else {
        NSArray *initialItems = @[[self nextItem], [self nextItem], [self nextItem]];
        self.ownedItems = [NSMutableSet setWithArray:initialItems];
        for (AVPlayerItem *item in initialItems) [self.player insertItem:item afterItem:nil];
    }
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = [manifest[@"fit"] isEqual:@"fit"]
        ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.frame = self.bounds;
    self.playerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [self.layer addSublayer:self.playerLayer];
    __weak VSMLoopScreenSaver_0000000000000000 *weakSelf = self;
    if (!self.looper) self.endObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {
            VSMLoopScreenSaver_0000000000000000 *view = weakSelf;
            if (!view.player) return;
            // Ignore events from players belonging to other screens or previews.
            if (![view.ownedItems containsObject:note.object]) return;
            [view.ownedItems removeObject:note.object];
            // Keep three prepared items queued, including across the last-to-first transition.
            AVPlayerItem *item = [view nextItem];
            if (item) {
                [view.ownedItems addObject:item];
                [view.player insertItem:item afterItem:nil];
            }
        }];
    [self.player play];
}

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.frame = self.bounds;
    [CATransaction commit];
}

- (void)stopAnimation {
    if (self.endObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.endObserver];
    self.endObserver = nil;
    [self.player pause];
    [self.looper disableLooping];
    self.looper = nil;
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer.player = nil;
    [self.player removeAllItems];
    self.player = nil;
    self.playerLayer = nil;
    self.clips = nil;
    self.ownedItems = nil;
    [super stopAnimation];
}

- (void)dealloc {
    if (_endObserver) [[NSNotificationCenter defaultCenter] removeObserver:_endObserver];
    [_player pause];
    [_looper disableLooping];
}
- (BOOL)hasConfigureSheet { return NO; }
- (void)animateOneFrame { }
@end
