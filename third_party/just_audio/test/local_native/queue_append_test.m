#import <Foundation/Foundation.h>
#import "../../darwin/just_audio/Sources/just_audio/include/just_audio/AudioPlayer.h"
#import "../../darwin/just_audio/Sources/just_audio/include/just_audio/IndexedAudioSource.h"
#import "../../darwin/just_audio/Sources/just_audio/include/just_audio/ConcatenatingAudioSource.h"

// Exercise the production enqueueFrom: with a recording queue. No Flutter
// engine, AVPlayer playback, media assets or application are started.
@interface AudioPlayer (QueueTest)
- (void)enqueueFrom:(int)index;
- (void)concatenatingRemoveRange:(NSString *)catId start:(int)start end:(int)end shuffleOrder:(NSArray<NSNumber *> *)shuffleOrder;
@end

@interface TestItem : NSObject
- (BOOL)isPlaybackBufferEmpty;
@end
@implementation TestItem
- (BOOL)isPlaybackBufferEmpty { return NO; }
@end

@interface TestQueue : NSObject
@property NSMutableArray *storage;
@property NSUInteger inserts;
@property NSUInteger removals;
@property NSUInteger rateChanges;
@property (nonatomic) float rate;
- (NSArray *)items;
- (id)currentItem;
- (void)insertItem:(id)item afterItem:(id)previous;
- (void)removeItem:(id)item;
@end
@implementation TestQueue
- (NSArray *)items { return [_storage copy]; }
- (id)currentItem { return _storage.firstObject; }
- (void)setRate:(float)rate { _rate = rate; _rateChanges++; }
- (void)insertItem:(id)item afterItem:(id)previous {
    NSCAssert(previous == nil, @"enqueue appends at tail");
    NSCAssert(![_storage containsObject:item], @"duplicate queue item");
    [_storage addObject:item];
    _inserts++;
}
- (void)removeItem:(id)item {
    [_storage removeObjectIdenticalTo:item];
    _removals++;
}
@end

@interface TestSource : IndexedAudioSource
@property id item;
@property id loopItem;
@end
@implementation TestSource
- (IndexedPlayerItem *)playerItem { return _item; }
- (IndexedPlayerItem *)playerItem2 { return _loopItem; }
- (void)preparePlayerItem2 { _loopItem = [TestItem new]; }
- (NSArray<NSNumber *> *)getShuffleIndices { return @[@0]; }
@end

@interface TestPlayer : AudioPlayer
@property NSUInteger endUpdates;
@property NSUInteger positionUpdates;
@property (copy) void (^onRemoveObserver)(void);
@end
@implementation TestPlayer
- (void)updateEndAction { _endUpdates++; }
- (void)updatePosition { _positionUpdates++; }
- (void)enterBuffering:(NSString *)reason {}
- (void)leaveBuffering:(NSString *)reason {}
- (void)addItemObservers:(id)item {}
- (void)removeItemObservers:(id)item {
    if (_onRemoveObserver) {
        void (^action)(void) = _onRemoveObserver;
        _onRemoveObserver = nil;
        action();
    }
}
- (void)broadcastPlaybackEvent {}
@end

static NSArray<TestSource *> *sources(NSUInteger count, BOOL lazy) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSUInteger i = 0; i < count; i++) {
        TestSource *source = [[TestSource alloc] initWithId:[@(i) stringValue]];
        source.item = [TestItem new];
        source.lazyLoading = lazy;
        [result addObject:source];
    }
    return result;
}

static TestPlayer *player(NSArray<TestSource *> *sources, NSArray *order, NSArray *items) {
    TestPlayer *result = [TestPlayer new];
    TestQueue *queue = [TestQueue new];
    queue.storage = [items mutableCopy];
    [result setValue:queue forKey:@"_player"];
    [result setValue:sources forKey:@"_indexedAudioSources"];
    [result setValue:order forKey:@"_order"];
    [result setValue:@(psReady) forKey:@"_processingState"];
    [result setValue:@(lmLoopOff) forKey:@"_loopMode"];
    [result setValue:[NSValue valueWithCMTime:kCMTimeInvalid] forKey:@"_seekPos"];
    return result;
}

static void expect(TestPlayer *player, NSArray *items, NSUInteger inserts, NSUInteger removals, BOOL all) {
    TestQueue *queue = (id)player.player;
    NSCAssert([queue.items isEqualToArray:items], @"wrong queue order");
    NSCAssert(queue.inserts == inserts, @"wrong insert count");
    NSCAssert(queue.removals == removals, @"wrong remove count");
    NSCAssert(queue.rateChanges == 0, @"enqueue changed rate");
    NSCAssert([[player valueForKey:@"_enqueuedAll"] boolValue] == all, @"wrong end state");
    NSCAssert(player.endUpdates == 1, @"end action not updated");
}

static TestPlayer *removalPlayer(NSArray<TestSource *> *s, NSArray *order, NSArray *items, int index, BOOL shuffle) {
    TestPlayer *p = player(s, order, items);
    ConcatenatingAudioSource *tree = [[ConcatenatingAudioSource alloc]
        initWithId:@"root" audioSources:[s mutableCopy] shuffleOrder:order lazyLoading:@NO];
    [p setValue:tree forKey:@"_audioSource"];
    [p setValue:@(index) forKey:@"_index"];
    [p setValue:@(shuffle) forKey:@"_shuffleModeEnabled"];
    return p;
}

int main(void) {
    @try {
    @autoreleasepool {
        NSArray<TestSource *> *s = sources(4, NO);
        NSArray *allItems = @[s[0].item, s[1].item, s[2].item, s[3].item];
        TestPlayer *p = player(s, @[@0, @1, @2, @3], @[s[0].item, s[1].item]);
        [p enqueueFrom:0];
        expect(p, allItems, 2, 0, YES);
        NSCAssert(p.positionUpdates == 0, @"append changed position");

        // Already complete: enqueue and a played-prefix prune do no native work.
        p = player(s, @[@0, @1, @2, @3], allItems);
        [p enqueueFrom:0];
        expect(p, allItems, 0, 0, YES);
        NSArray *pruned = @[s[1], s[2], s[3]];
        NSArray *remaining = @[s[1].item, s[2].item, s[3].item];
        p = player(pruned, @[@0, @1, @2], remaining);
        [p enqueueFrom:0];
        expect(p, remaining, 0, 0, YES);

        // Use actual playback order, including shuffled source indices.
        p = player(s, @[@1, @0, @3, @2], @[s[0].item, s[3].item]);
        [p enqueueFrom:0];
        expect(p, @[s[0].item, s[3].item, s[2].item], 1, 0, YES);

        NSArray<TestSource *> *lazy = sources(4, YES);
        p = player(lazy, @[@0, @1, @2, @3], @[lazy[0].item]);
        [p enqueueFrom:0];
        expect(p, @[lazy[0].item, lazy[1].item], 1, 0, NO);
        p = player(lazy, @[@0, @1, @2, @3], @[lazy[1].item, lazy[2].item]);
        [p enqueueFrom:1];
        expect(p, @[lazy[1].item, lazy[2].item], 0, 0, NO);
        lazy[2].lazyLoading = NO;
        p = player(lazy, @[@0, @1, @2, @3], @[lazy[0].item, lazy[1].item]);
        [p enqueueFrom:0];
        expect(p, @[lazy[0].item, lazy[1].item, lazy[2].item], 1, 0, NO);

        // Non-prefix reorder and future removal must use the original rebuild.
        p = player(s, @[@0, @2, @1, @3], @[s[0].item, s[1].item]);
        [p enqueueFrom:0];
        expect(p, @[s[0].item, s[2].item, s[1].item, s[3].item], 3, 1, YES);
        p = player(@[s[0], s[2]], @[@0, @1], @[s[0].item, s[1].item, s[2].item]);
        [p enqueueFrom:0];
        expect(p, @[s[0].item, s[2].item], 1, 2, YES);

        // Pending seek, load/replacement and both loop modes keep the fallback.
        p = player(s, @[@0, @1, @2, @3], @[s[0].item, s[1].item]);
        [p setValue:[NSValue valueWithCMTime:kCMTimeZero] forKey:@"_seekPos"];
        [p enqueueFrom:0];
        expect(p, allItems, 3, 1, YES);
        p = player(s, @[@0, @1, @2, @3], @[s[0].item, s[1].item]);
        [p setValue:@(psLoading) forKey:@"_processingState"];
        [p enqueueFrom:0];
        expect(p, allItems, 3, 1, YES);
        p = player(s, @[@0, @1, @2, @3], @[s[0].item, s[1].item]);
        [p setValue:@(lmLoopAll) forKey:@"_loopMode"];
        [p enqueueFrom:0];
        expect(p, [allItems arrayByAddingObject:s[0].loopItem], 4, 1, YES);
        p = player(s, @[@0, @1, @2, @3], @[s[0].item, s[1].item]);
        [p setValue:@(lmLoopOne) forKey:@"_loopMode"];
        [p enqueueFrom:0];
        expect(p, @[s[0].item, s[0].loopItem], 1, 1, NO);
        p = player(s, @[@0, @1, @2, @3], @[s[0].item, s[1].item]);
        [p enqueueFrom:1];
        expect(p, remaining, 2, 1, YES);

        // Exercise the production removal method, not only enqueueFrom: after a
        // pre-rebased fixture. Two removals before old index 2 must yield 0.
        NSArray<TestSource *> *r = sources(5, NO);
        p = removalPlayer(r, @[@0,@1,@2,@3,@4], @[r[2].item,r[3].item,r[4].item], 2, NO);
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[r[2].item,r[3].item,r[4].item], 0, 0, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 0, @"batch prune skipped current item");

        // Simulate native advancement during observer removal/tree mutation.
        p = removalPlayer(r, @[@0,@1,@2,@3,@4], @[r[2].item,r[3].item,r[4].item], 2, NO);
        TestQueue *advancingQueue = (id)p.player;
        p.onRemoveObserver = ^{ [advancingQueue.storage removeObjectAtIndex:0]; };
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[r[3].item,r[4].item], 0, 0, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"mutation ignored actual current item");

        // Removed-current fallback still selects its surviving successor.
        p = removalPlayer(r, @[@0,@1,@2,@3,@4], @[r[2].item,r[3].item,r[4].item], 2, NO);
        [p concatenatingRemoveRange:@"root" start:1 end:3 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[r[3].item,r[4].item], 1, 2, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"removed-current successor changed");

        // Shuffled source indices still resolve current identity in the source
        // sequence; native playback order remains the supplied shuffle order.
        p = removalPlayer(r, @[@0,@1,@3,@2,@4], @[r[3].item,r[2].item,r[4].item], 3, YES);
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@1,@0,@2]];
        expect(p, @[r[3].item,r[2].item,r[4].item], 0, 0, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"shuffle lost current source identity");

        NSLog(@"PASS: 18 native queue scenarios (recording queue; no app/audio)");
    }
    } @catch (NSException *exception) {
        NSLog(@"FAIL: %@", exception.reason);
        return 1;
    }
    return 0;
}
