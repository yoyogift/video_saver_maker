// Structural playback checks; visual continuity still needs a desktop preview.
#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 10;
        for (int index = 1; index < argc; index++) {
            NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[index]]];
            if (![bundle load]) return 11;
            ScreenSaverView *view = [[bundle.principalClass alloc] initWithFrame:NSMakeRect(0,0,640,360) isPreview:YES];
            for (int pass = 0; pass < 2; pass++) {
                [view startAnimation];
                NSArray<AVAsset *> *clips = [view valueForKey:@"clips"];
                if (clips.count != (NSUInteger)index) return 12;
                for (AVAsset *clip in clips) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    NSArray<AVAssetTrack *> *tracks = [clip tracksWithMediaType:AVMediaTypeVideo];
                    if (tracks.count != 1 || [clip tracksWithMediaType:AVMediaTypeAudio].count) return 13;
                    CMTimeRange range = tracks.firstObject.timeRange;
                    if (CMTimeCompare(range.start,kCMTimeZero) != 0 ||
                        CMTimeCompare(range.duration,clip.duration) != 0 ||
                        CMTimeCompare(clip.duration,kCMTimeZero) <= 0) return 14;
#pragma clang diagnostic pop
                }
                AVPlayerLooper *looper = [view valueForKey:@"looper"];
                id observer = [view valueForKey:@"endObserver"];
                if (index == 1 && (!looper || observer)) return 15;
                if (index == 2 && (looper || !observer || [[view valueForKey:@"ownedItems"] count] != 3)) return 16;
                [view stopAnimation];
                if ([view valueForKey:@"player"] || [view valueForKey:@"looper"] ||
                    [view valueForKey:@"endObserver"] || [view valueForKey:@"clips"]) return 17;
            }
        }
        puts("PASS: video-only timelines, zero-based ranges, dedicated single-video looper, playlist lookahead, stop/restart cleanup");
    }
    return 0;
}
