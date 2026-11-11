#import <Foundation/Foundation.h>
#import "../../darwin/just_audio/Sources/just_audio/include/just_audio/AudioPlayer.h"
#import "../../darwin/just_audio/Sources/just_audio/include/just_audio/IndexedAudioSource.h"
#import "../../darwin/just_audio/Sources/just_audio/include/just_audio/ConcatenatingAudioSource.h"

// Exercise the production enqueueFrom: with a recording queue. No Flutter
// engine, AVPlayer playback, media assets or application are started.
@interface AudioPlayer (QueueTest)
- (void)enqueueFrom:(int)index;
- (void)concatenatingRemoveRange:(NSString *)catId start:(int)start end:(int)end shuffleOrder:(NSArray<NSNumber *> *)shuffleOrder;
- (void)concatenatingInsertAll:(NSString *)catId index:(int)index sources:(NSArray *)sources shuffleOrder:(NSArray<NSNumber *> *)shuffleOrder;
- (void)onComplete:(NSNotification *)notification;
- (void)updateOrder;
@end

@interface TestItem : NSObject
@property id audioSource;
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
@property (copy) void (^afterCurrentRead)(void);
@property (copy) void (^beforeItemsRead)(void);
@property (copy) void (^afterItemsRead)(void);
- (NSArray *)items;
- (id)currentItem;
- (void)insertItem:(id)item afterItem:(id)previous;
- (void)removeItem:(id)item;
@end
@implementation TestQueue
- (NSArray *)items {
    if (_beforeItemsRead) {
        void (^action)(void) = _beforeItemsRead;
        _beforeItemsRead = nil;
        action();
    }
    NSArray *snapshot = [_storage copy];
    if (_afterItemsRead) {
        void (^action)(void) = _afterItemsRead;
        _afterItemsRead = nil;
        action();
    }
    return snapshot;
}
- (id)currentItem {
    id current = _storage.firstObject;
    if (_afterCurrentRead) {
        void (^action)(void) = _afterCurrentRead;
        _afterCurrentRead = nil;
        action();
    }
    return current;
}
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
@property NSArray *insertionSources;
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
- (NSMutableArray *)decodeAudioSources:(NSArray *)sources { return [_insertionSources mutableCopy]; }
@end

static NSArray<TestSource *> *sources(NSUInteger count, BOOL lazy) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSUInteger i = 0; i < count; i++) {
        TestSource *source = [[TestSource alloc] initWithId:[@(i) stringValue]];
        source.item = [TestItem new];
        [(TestItem *)source.item setAudioSource:source];
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

        // Advancing immediately after the caller reads currentItem used to
        // invalidate enqueueFrom:'s target and destructively replay that item.
        p = removalPlayer(r, @[@0,@1,@2,@3,@4], @[r[2].item,r[3].item,r[4].item], 2, NO);
        TestQueue *callerRace = (id)p.player;
        NSMutableArray *callerStorage = callerRace.storage;
        callerRace.afterCurrentRead = ^{ [callerStorage removeObjectAtIndex:0]; };
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[r[3].item,r[4].item], 0, 0, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"caller snapshot race lost live current item");

        // The native head can advance between the old target guard and queue
        // snapshot; snapshot-derived preservation must never enter the rebuild.
        p = removalPlayer(r, @[@0,@1,@2,@3,@4], @[r[2].item,r[3].item,r[4].item], 2, NO);
        TestQueue *snapshotRace = (id)p.player;
        NSMutableArray *snapshotStorage = snapshotRace.storage;
        snapshotRace.beforeItemsRead = ^{ [snapshotStorage removeObjectAtIndex:0]; };
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[r[3].item,r[4].item], 0, 0, YES);

        // Advancement after copying the queue snapshot also preserves current
        // audio: only its tail may be extended, never the stale copied head.
        p = removalPlayer(r, @[@0,@1,@2,@3,@4], @[r[2].item,r[3].item,r[4].item], 2, NO);
        TestQueue *copiedRace = (id)p.player;
        NSMutableArray *copiedStorage = copiedRace.storage;
        copiedRace.afterItemsRead = ^{ [copiedStorage removeObjectAtIndex:0]; };
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[r[3].item,r[4].item], 0, 0, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"copied snapshot race did not report current item");

        // Production append has the same caller-snapshot race. Its suffix must
        // be appended after the surviving native head, without replaying it.
        NSArray<TestSource *> *a = sources(4, NO);
        p = removalPlayer(@[a[0],a[1]], @[@0,@1], @[a[0].item,a[1].item], 0, NO);
        p.insertionSources = @[a[2],a[3]];
        TestQueue *appendRace = (id)p.player;
        NSMutableArray *appendStorage = appendRace.storage;
        appendRace.afterCurrentRead = ^{ [appendStorage removeObjectAtIndex:0]; };
        [p concatenatingInsertAll:@"root" index:2 sources:@[] shuffleOrder:@[@0,@1,@2,@3]];
        expect(p, @[a[1].item,a[2].item,a[3].item], 2, 0, YES);

        // An intentional insertion into the queued future is not an identical
        // prefix extension and continues to use the existing reorder fallback.
        a = sources(3, NO);
        p = removalPlayer(@[a[0],a[1]], @[@0,@1], @[a[0].item,a[1].item], 0, NO);
        p.insertionSources = @[a[2]];
        [p concatenatingInsertAll:@"root" index:1 sources:@[] shuffleOrder:@[@0,@1,@2]];
        expect(p, @[a[0].item,a[2].item,a[1].item], 2, 1, YES);

        // Production completion publishes logical next index while the native
        // queue can still own the just-ended item. A second distinct completion
        // proves the older predecessor is no longer the physical head.
        NSArray<TestSource *> *lag = sources(4, NO);
        p = removalPlayer(lag, @[@0,@1,@2,@3], @[lag[0].item,lag[1].item,lag[2].item,lag[3].item], 0, NO);
        [p updateOrder];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:lag[0].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"completion did not publish logical next index");
        NSCAssert((id)p.player.currentItem == lag[0].item, @"fixture lost native head lag");
        TestQueue *lagQueue = (id)p.player;
        [lagQueue.storage removeObjectAtIndex:0]; // physical advance to item 1
        [p onComplete:[NSNotification notificationWithName:@"ended" object:lag[1].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 2, @"second completion did not advance logical index");
        p.endUpdates = 0;
        [p concatenatingRemoveRange:@"root" start:0 end:1 shuffleOrder:@[@0,@1,@2]];
        expect(p, @[lag[1].item,lag[2].item,lag[3].item], 0, 0, YES);

        NSLog(@"PASS: 24 native queue scenarios (recording queue; no app/audio)");
    }
    } @catch (NSException *exception) {
        NSLog(@"FAIL: %@", exception.reason);
        return 1;
    }
    return 0;
}
