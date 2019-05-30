
#import "LoadMediaInfoOperation.h"
#import "MEGASdkManager.h"
#import "MEGAConstants.h"

@implementation LoadMediaInfoOperation

- (void)start {
    [super start];
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didReceiveMediaInfoReadyNotification) name:MEGAMediaInfoReadyNotificationName object:nil];
    
    if ([MEGASdkManager.sharedMEGASdk ensureMediaInfo]) {
        [self finishOperation];
    }
}

- (void)finishOperation {
    [super finishOperation];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Notification handler

- (void)didReceiveMediaInfoReadyNotification {
    [self finishOperation];
}

@end
