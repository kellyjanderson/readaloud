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
- (void)load:(NSDictionary *)source initialPosition:(CMTime)initialPosition initialIndex:(NSNumber *)initialIndex result:(FlutterResult)result;
- (void)seek:(CMTime)position index:(NSNumber *)index completionHandler:(void (^)(BOOL))completionHandler;
- (void)updateOrder;
- (void)queueBoundaryAudit:(NSString *)boundary item:(id)item details:(NSDictionary *)details;
- (NSString *)queueBoundaryAuditItem:(id)item selectSource:(BOOL)selectSource;
@end

@interface TestItem : NSObject
@property id audioSource;
@property AVAsset *asset;
@property AVPlayerItemStatus status;
- (BOOL)isPlaybackBufferEmpty;
@end
@implementation TestItem
- (BOOL)isPlaybackBufferEmpty { return NO; }
- (BOOL)isPlaybackBufferFull { return YES; }
@end

@interface TestQueue : NSObject
@property NSMutableArray *storage;
@property NSUInteger inserts;
@property NSUInteger removals;
@property NSUInteger rateChanges;
@property NSUInteger auditQueries;
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
    _auditQueries++;
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
    _auditQueries++;
    id current = _storage.firstObject;
    if (_afterCurrentRead) {
        void (^action)(void) = _afterCurrentRead;
        _afterCurrentRead = nil;
        action();
    }
    return current;
}
- (void)setRate:(float)rate { _rate = rate; _rateChanges++; }
- (void)setVolume:(float)volume {}
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
@property NSUInteger seeks;
@property CMTime lastSeek;
@property CMTime testDuration;
@end
@implementation TestSource
- (IndexedPlayerItem *)playerItem { return _item; }
- (IndexedPlayerItem *)playerItem2 { return _loopItem; }
- (void)preparePlayerItem2 { _loopItem = [TestItem new]; }
- (NSArray<NSNumber *> *)getShuffleIndices { return @[@0]; }
- (void)seek:(CMTime)position { _seeks++; _lastSeek = position; }
- (void)seek:(CMTime)position completionHandler:(void (^)(BOOL))completionHandler {
    [self seek:position];
    if (completionHandler) completionHandler(YES);
}
- (CMTime)position { return _lastSeek; }
- (CMTime)duration { return _testDuration; }
@end

@interface TestPlayer : AudioPlayer
@property NSUInteger endUpdates;
@property NSUInteger positionUpdates;
@property NSMutableArray<NSDictionary *> *events;
@property AudioSource *loadSource;
@property NSUInteger errors;
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
- (void)broadcastPlaybackEvent {
    if (!_events) _events = [NSMutableArray new];
    [_events addObject:@{@"index": [self valueForKey:@"_index"], @"state": [self valueForKey:@"_processingState"]}];
}
- (AudioSource *)decodeAudioSource:(NSDictionary *)data { return _loadSource; }
- (void)sendErrorForItem:(id)item { _errors++; }
- (NSMutableArray *)decodeAudioSources:(NSArray *)sources { return [_insertionSources mutableCopy]; }
@end

static NSArray<TestSource *> *sources(NSUInteger count, BOOL lazy) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSUInteger i = 0; i < count; i++) {
        TestSource *source = [[TestSource alloc] initWithId:[@(i) stringValue]];
        source.item = [TestItem new];
        [(TestItem *)source.item setAudioSource:source];
        [(TestItem *)source.item setStatus:AVPlayerItemStatusReadyToPlay];
        source.lastSeek = kCMTimeZero;
        source.testDuration = CMTimeMake(1, 1);
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
        unsetenv("READALOUD_QUEUE_PHYSICAL_HEAD_INDEX");
        unsetenv("READALOUD_QUEUE_BOUNDARY_AUDIT");
        unsetenv("READALOUD_QUEUE_SKIP_LOOP_OFF_REWIND");
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
        // queue can still own the just-ended item. Notifications alone cannot
        // prove head advancement; the explicit queue mutation below does.
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

        // A disabled audit must perform no native queue queries, even when its
        // capture/readout methods are called directly. Existing 24 race cases
        // above also run disabled so their exact query interleavings stay valid.
        p = player(s, @[@0,@1,@2,@3], allItems);
        TestQueue *disabledQueue = (id)p.player;
        [p queueBoundaryAudit:@"disabled" item:s[0].item details:nil];
        NSDictionary *disabled = [p readAloudQueueBoundaryAudit];
        NSCAssert([(NSArray *)disabled[@"events"] count] == 0 && disabledQueue.auditQueries == 0, @"disabled audit touched queue");
        NSCAssert(![disabled[@"enabled"] boolValue], @"audit enabled by default");

        setenv("READALOUD_QUEUE_BOUNDARY_AUDIT", "true", 1);
        NSCAssert(![AudioPlayer readAloudQueueBoundaryAuditEnabled], @"only exact opt-in 1 is allowed");
        setenv("READALOUD_QUEUE_BOUNDARY_AUDIT", "1", 1);
        // Exercise enabled instrumentation around the real production enqueue.
        NSArray<TestSource *> *admission = sources(2, NO);
        p = player(admission, @[@0,@1], @[admission[0].item]);
        [p queueBoundaryAuditItem:admission[0].item selectSource:YES];
        [p enqueueFrom:0];
        NSArray<NSDictionary *> *admissionEvents = [p readAloudQueueBoundaryAudit][@"events"];
        NSCAssert(admissionEvents.count == 2 && [admissionEvents[0][@"boundary"] isEqual:@"native.insert.entry"] && [admissionEvents[1][@"boundary"] isEqual:@"native.insert.return"], @"native admission boundaries missing");
        NSCAssert([admissionEvents[0][@"queueTotal"] intValue] == 1 && [admissionEvents[1][@"queueTotal"] intValue] == 2, @"admission did not capture actual physical queue before/after");

        // Two real source objects with identical declared IDs remain distinct.
        TestSource *sameA = [[TestSource alloc] initWithId:@"same"];
        TestSource *sameB = [[TestSource alloc] initWithId:@"same"];
        sameA.item = [TestItem new]; sameB.item = [TestItem new];
        [(TestItem *)sameA.item setAudioSource:sameA];
        [(TestItem *)sameB.item setAudioSource:sameB];
        p = player(@[sameA,sameB], @[], @[sameA.item,sameB.item]);
        NSString *sameAId = [p queueBoundaryAuditItem:sameA.item selectSource:YES];
        NSString *sameBId = [p queueBoundaryAuditItem:sameB.item selectSource:YES];
        NSCAssert(![sameAId isEqual:sameBId] && [(NSArray *)[p readAloudQueueBoundaryAudit][@"sources"] count] == 2, @"declared IDs collapsed actual identities");
        for (NSUInteger i = 0; i < 65; i++) {
            TestItem *extra = [TestItem new]; extra.audioSource = sameA;
            [p queueBoundaryAuditItem:(id)extra selectSource:YES];
        }
        NSDictionary *identityCap = [p readAloudQueueBoundaryAudit];
        NSCAssert([(NSArray *)identityCap[@"items"] count] == 64 && [identityCap[@"identityRegistryOverflow"] boolValue], @"item identity registry is unbounded or silently truncated");

        NSArray<TestSource *> *auditSources = sources(40, NO);
        NSMutableArray *auditItems = [NSMutableArray new];
        for (TestSource *source in auditSources) [auditItems addObject:source.item];
        p = player(auditSources, @[], auditItems);
        for (TestSource *source in auditSources) {
            [(TestItem *)source.item setAsset:[AVURLAsset URLAssetWithURL:[NSURL URLWithString:@"file:///immutable-first.wav"] options:nil]];
            [p queueBoundaryAuditItem:source.item selectSource:YES];
        }
        [p queueBoundaryAudit:@"fixture.initial" item:auditSources[0].item details:nil];
        NSDictionary *initial = [p readAloudQueueBoundaryAudit];
        NSCAssert([(NSArray *)initial[@"sources"] count] == 8 && [(NSArray *)initial[@"items"] count] == 8, @"first-eight identity cap failed");
        NSDictionary *firstEvent = [initial[@"events"] firstObject];
        NSCAssert([(NSArray *)firstEvent[@"queueItemIdentities"] count] == 32 && [firstEvent[@"queueTotal"] intValue] == 40 && [firstEvent[@"queueTruncated"] boolValue], @"physical queue snapshot bound is not explicit");
        NSCAssert([firstEvent[@"unixMicros"] longLongValue] > 0 && [firstEvent[@"monotonicMicros"] longLongValue] > 0, @"clock evidence missing");
        NSCAssert([firstEvent[@"queueSnapshotHeadIdentity"] isEqual:firstEvent[@"itemIdentity"]], @"item identity differs from physical head");

        // Immutable registry facts survive URL/source-link mutation and logical
        // sequence removal. Neither filenames nor sourceId strings are identity.
        id auditedItem = auditSources[0].item;
        [(TestItem *)auditedItem setAsset:[AVURLAsset URLAssetWithURL:[NSURL URLWithString:@"file:///changed.wav"] options:nil]];
        [(TestItem *)auditedItem setAudioSource:nil];
        [p setValue:@[] forKey:@"_indexedAudioSources"];
        [p queueBoundaryAudit:@"fixture.stale" item:auditedItem details:nil];
        NSDictionary *stale = [p readAloudQueueBoundaryAudit];
        NSDictionary *staleEvent = [stale[@"events"] lastObject];
        NSCAssert([staleEvent[@"itemIdentity"] isEqual:firstEvent[@"itemIdentity"]] && [staleEvent[@"itemTracked"] boolValue], @"weak-link removal changed immutable identity");
        NSCAssert(![staleEvent[@"itemSourceInSequence"] boolValue], @"removed source reported current");
        for (NSDictionary *source in stale[@"sources"]) NSCAssert([source[@"sourceURL"] isEqual:@"file:///immutable-first.wav"], @"registry URL mutated");

        // Ring overwrites oldest events and reports loss without growing. The
        // returned snapshot is independent of subsequent callback mutations.
        for (NSUInteger i = 0; i < 2055; i++) [p queueBoundaryAudit:@"fixture.cap" item:auditedItem details:@{@"n": @(i)}];
        NSDictionary *capped = [p readAloudQueueBoundaryAudit];
        NSCAssert([(NSArray *)capped[@"events"] count] == 2048 && [capped[@"overflow"] intValue] == 9, @"ring bound/loss accounting failed");
        NSCAssert([capped[@"events"] firstObject][@"details"] && [[capped[@"events"] firstObject][@"details"][@"n"] intValue] == 7, @"ring chronological ordering failed");
        NSCAssert([(NSArray *)initial[@"events"] count] == 1, @"readout was not an immutable snapshot");

        TestQueue *auditQueue = (id)p.player;
        NSUInteger queries = auditQueue.auditQueries;
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [p queueBoundaryAudit:@"fixture.offmain" item:auditedItem details:nil];
            dispatch_semaphore_signal(finished);
        });
        NSCAssert(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"off-main fixture timed out");
        NSDictionary *offMain = [p readAloudQueueBoundaryAudit];
        NSCAssert([offMain[@"offMainSkipped"] intValue] == 1 && auditQueue.auditQueries == queries, @"off-main audit queried/mutated native queue");
        NSCAssert([NSJSONSerialization isValidJSONObject:offMain], @"receipt is not serializable");

        // Dispose remains observable on the retained player snapshot even if
        // there is no AVQueuePlayer. Global plugin readout requires pre-dispose.
        [p setValue:nil forKey:@"_player"];
        [p dispose:NO];
        NSDictionary *disposed = [p readAloudQueueBoundaryAudit];
        NSCAssert([disposed[@"disposed"] boolValue] && [[[disposed[@"events"] lastObject] objectForKey:@"boundary"] isEqual:@"dispose.entry"], @"dispose lifetime boundary missing");
        unsetenv("READALOUD_QUEUE_BOUNDARY_AUDIT");
        NSLog(@"PASS: native audit disabled, identity/stale, first-eight/queue/ring caps, off-main and dispose scenarios (no app/audio)");

        // Completion can publish index 1 while item 0 is still the physical
        // head. Default behavior still rewinds that item; only the exact QA
        // opt-in may suppress this loop-off, non-final seek.
        setenv("READALOUD_QUEUE_BOUNDARY_AUDIT", "1", 1);
        setenv("READALOUD_QUEUE_SKIP_LOOP_OFF_REWIND", "true", 1);
        NSArray<TestSource *> *rewind = sources(2, NO);
        p = removalPlayer(rewind, @[@0,@1], @[rewind[0].item,rewind[1].item], 0, NO);
        [p updateOrder];
        [p queueBoundaryAuditItem:rewind[0].item selectSource:YES];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:rewind[0].item]];
        NSCAssert(rewind[0].seeks == 1 && CMTIME_COMPARE_INLINE(rewind[0].lastSeek, ==, kCMTimeZero), @"default loop-off rewind changed");
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1 && (id)p.player.currentItem == rewind[0].item, @"completion head-lag fixture invalid");
        NSArray<NSDictionary *> *rewindEvents = [p readAloudQueueBoundaryAudit][@"events"];
        NSCAssert(rewindEvents.count == 4 && [rewindEvents[1][@"boundary"] isEqual:@"completion.rewind.entry"] && [rewindEvents[2][@"boundary"] isEqual:@"completion.rewind.return"] && ![rewindEvents[1][@"details"][@"skipped"] boolValue], @"default rewind boundary trace missing");
        NSCAssert([rewindEvents[1][@"itemIdentity"] isEqual:rewindEvents[1][@"currentItemIdentity"]], @"trace lost ended/current physical identity");

        setenv("READALOUD_QUEUE_SKIP_LOOP_OFF_REWIND", "1", 1);
        rewind = sources(2, NO);
        p = removalPlayer(rewind, @[@0,@1], @[rewind[0].item,rewind[1].item], 0, NO);
        [p updateOrder];
        [p queueBoundaryAuditItem:rewind[0].item selectSource:YES];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:rewind[0].item]];
        NSCAssert(rewind[0].seeks == 0 && [[p valueForKey:@"_index"] intValue] == 1 && [[p valueForKey:@"_justAdvanced"] boolValue], @"QA skip changed logical completion");
        NSCAssert(p.endUpdates == 1 && (id)p.player.currentItem == rewind[0].item, @"QA skip mutated physical queue/end action");
        NSDictionary *skipped = [p readAloudQueueBoundaryAudit];
        NSCAssert([skipped[@"skipLoopOffRewind"] boolValue] && [skipped[@"events"][1][@"details"][@"skipped"] boolValue], @"QA skip not declared in receipt");

        // Loop-one/all still rewind under the flag; an explicit source seek is
        // likewise untouched. No change is made to final-item completion.
        for (NSNumber *loop in @[@(lmLoopOne), @(lmLoopAll)]) {
            rewind = sources(2, NO);
            p = removalPlayer(rewind, @[@0,@1], @[rewind[0].item,rewind[1].item], 0, NO);
            [p updateOrder]; [p setValue:loop forKey:@"_loopMode"];
            [p onComplete:[NSNotification notificationWithName:@"ended" object:rewind[0].item]];
            NSCAssert(rewind[0].seeks == 1, @"QA flag suppressed a loop rewind");
            [rewind[0] seek:CMTimeMake(1, 2)];
            NSCAssert(rewind[0].seeks == 2 && CMTIME_COMPARE_INLINE(rewind[0].lastSeek, ==, CMTimeMake(1, 2)), @"QA flag suppressed explicit seek");
        }
        unsetenv("READALOUD_QUEUE_BOUNDARY_AUDIT");
        unsetenv("READALOUD_QUEUE_SKIP_LOOP_OFF_REWIND");
        NSLog(@"PASS: default/QA completion rewind, head ownership, index/events and loop/explicit seek preservation (no app/audio)");
        // Exact opt-in only. The old global-index path is the negative control:
        // future packet 4 completion while packet 3 owns the head advances it.
        setenv("READALOUD_QUEUE_PHYSICAL_HEAD_INDEX", "true", 1);
        NSArray<TestSource *> *physical = sources(5, NO);
        p = removalPlayer(physical, @[@0,@1,@2,@3,@4], @[physical[3].item,physical[4].item], 3, NO);
        [p updateOrder];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 4, @"negative control no longer exercises speculative advancement");

        setenv("READALOUD_QUEUE_PHYSICAL_HEAD_INDEX", "1", 1);
        p = removalPlayer(physical, @[@0,@1,@2,@3,@4], @[physical[3].item,physical[4].item], 3, NO);
        [p updateOrder]; [p setValue:@YES forKey:@"_enqueuedAll"];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 3 && [[p valueForKey:@"_processingState"] intValue] == psReady && p.events.count == 0, @"future/duplicate final completion advanced index or published EOF");
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[3].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 3 && physical[3].seeks == 1, @"physical-head lag lost index ownership or ended rewind");

        // KVO can carry an old/future/NSNull newKey. One live currentItem read
        // owns this event even if the queue advances immediately after the read.
        TestQueue *physicalQueue = (id)p.player;
        [physicalQueue.storage removeObjectAtIndex:0];
        NSUInteger beforeHead = physicalQueue.auditQueries;
        [p observeValueForKeyPath:@"currentItem" ofObject:physicalQueue change:@{NSKeyValueChangeNewKey: physical[3].item} context:nil];
        NSCAssert(physicalQueue.auditQueries == beforeHead + 1 && [[p valueForKey:@"_index"] intValue] == 4 && p.events.count == 1, @"KVO trusted stale newKey or reread physical head");
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[3].item]];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[3].item]];
        NSCAssert([[p valueForKey:@"_processingState"] intValue] == psReady && p.events.count == 1, @"stale predecessor completion falsely completed actual final head");
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        NSCAssert([[p valueForKey:@"_processingState"] intValue] == psCompleted && [[p.events lastObject][@"index"] intValue] == 4, @"normal final EOF missing");
        NSUInteger finalEvents = p.events.count;
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        NSCAssert(p.events.count == finalEvents, @"duplicate final EOF republished completion");

        // Null and retired physical heads cannot fabricate -1 or authorize EOF.
        [physicalQueue.storage removeAllObjects];
        [p setValue:@(psReady) forKey:@"_processingState"];
        [p observeValueForKeyPath:@"currentItem" ofObject:physicalQueue change:@{NSKeyValueChangeNewKey: physical[4].item} context:nil];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 4 && [[p valueForKey:@"_processingState"] intValue] == psReady && p.events.count == finalEvents, @"null physical head fabricated index/EOF");
        NSArray<TestSource *> *retired = sources(2, NO);
        [physicalQueue.storage addObject:retired[0].item];
        [p observeValueForKeyPath:@"currentItem" ofObject:physicalQueue change:@{NSKeyValueChangeNewKey: physical[0].item} context:nil];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:retired[0].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 4 && p.events.count == finalEvents, @"retired physical head fabricated index");

        // A future non-final item still gets its required rewind. Its callback
        // and a duplicate cannot evict/publish past packet 3.
        physical = sources(6, NO);
        p = removalPlayer(physical, @[@0,@1,@2,@3,@4,@5], @[physical[3].item,physical[4].item,physical[5].item], 3, NO);
        [p updateOrder];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[4].item]];
        NSCAssert(physical[4].seeks == 2 && [[p valueForKey:@"_index"] intValue] == 3 && p.events.count == 0, @"future completion lost rewind or exposed current head to pruning");
        p.endUpdates = 0;
        [p concatenatingRemoveRange:@"root" start:0 end:2 shuffleOrder:@[@0,@1,@2,@3]];
        expect(p, @[physical[3].item,physical[4].item,physical[5].item], 0, 0, YES);
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"safe played-prefix prune lost physical head");

        // Snapshot ownership is conservative if AV advances after the one read.
        physical = sources(3, NO);
        p = removalPlayer(physical, @[@0,@1,@2], @[physical[0].item,physical[1].item,physical[2].item], 0, NO);
        [p updateOrder]; [p setValue:@YES forKey:@"_enqueuedAll"];
        physicalQueue = (id)p.player;
        NSMutableArray *headStorage = physicalQueue.storage;
        physicalQueue.afterCurrentRead = ^{ [headStorage removeObjectAtIndex:0]; };
        [p observeValueForKeyPath:@"currentItem" ofObject:physicalQueue change:@{NSKeyValueChangeNewKey: physical[2].item} context:nil];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 0 && p.events.count == 0, @"single head snapshot raced into future KVO index");
        [p observeValueForKeyPath:@"currentItem" ofObject:physicalQueue change:@{NSKeyValueChangeNewKey: [NSNull null]} context:nil];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1, @"physical snapshot did not recover on next native callback");

        // KVO may precede the predecessor's end notification. Lazy preparation
        // must append its bounded successor without removing the head.
        NSArray<TestSource *> *lazyPhysical = sources(4, YES);
        TestPlayer *lazyPlayer = removalPlayer(lazyPhysical, @[@0,@1,@2,@3], @[lazyPhysical[0].item,lazyPhysical[1].item], 0, NO);
        for (TestSource *source in lazyPhysical) source.lazyLoading = YES;
        [lazyPlayer updateOrder];
        TestQueue *lazyQueue = (id)lazyPlayer.player;
        [lazyQueue.storage removeObjectAtIndex:0];
        [lazyPlayer observeValueForKeyPath:@"currentItem" ofObject:lazyQueue change:@{NSKeyValueChangeNewKey: lazyPhysical[0].item} context:nil];
        NSCAssert(([[lazyPlayer valueForKey:@"_index"] intValue] == 1 && [lazyQueue.storage isEqualToArray:@[lazyPhysical[1].item,lazyPhysical[2].item]] && lazyQueue.inserts == 1 && lazyQueue.removals == 0), @"KVO-before-end starved or rebuilt lazy successor");
        [lazyPlayer onComplete:[NSNotification notificationWithName:@"ended" object:lazyPhysical[0].item]];
        NSCAssert([[lazyPlayer valueForKey:@"_index"] intValue] == 1, @"late predecessor end skipped lazy current head");

        // An early final notification need not recur: existing head KVO can
        // finish it at observed EOF, but cannot finish it at the start or when
        // duration is unknown. Seek/load invalidate this pending witness.
        NSArray<TestSource *> *earlyFinal = sources(2, NO);
        TestPlayer *finalPlayer = removalPlayer(earlyFinal, @[@0,@1], @[earlyFinal[0].item,earlyFinal[1].item], 0, NO);
        [finalPlayer updateOrder]; [finalPlayer setValue:@YES forKey:@"_enqueuedAll"];
        [finalPlayer onComplete:[NSNotification notificationWithName:@"ended" object:earlyFinal[1].item]];
        TestQueue *finalQueue = (id)finalPlayer.player;
        [finalQueue.storage removeObjectAtIndex:0];
        [finalPlayer observeValueForKeyPath:@"currentItem" ofObject:finalQueue change:@{NSKeyValueChangeNewKey: earlyFinal[0].item} context:nil];
        NSCAssert([[finalPlayer valueForKey:@"_index"] intValue] == 1 && [[finalPlayer valueForKey:@"_processingState"] intValue] == psReady, @"pending final completed at head start");
        earlyFinal[1].lastSeek = CMTimeMake(1, 1);
        earlyFinal[1].testDuration = kCMTimeIndefinite;
        [finalPlayer observeValueForKeyPath:@"currentItem" ofObject:finalQueue change:@{NSKeyValueChangeNewKey: [NSNull null]} context:nil];
        NSCAssert([[finalPlayer valueForKey:@"_processingState"] intValue] == psReady, @"unknown duration authorized pending EOF");
        earlyFinal[1].testDuration = CMTimeMake(1, 1);
        [finalPlayer observeValueForKeyPath:@"currentItem" ofObject:finalQueue change:@{NSKeyValueChangeNewKey: earlyFinal[0].item} context:nil];
        NSCAssert([[finalPlayer valueForKey:@"_processingState"] intValue] == psCompleted, @"early final completion was lost at actual final head EOF");

        // Superseding seeks and loads must not inherit that old EOF witness,
        // even if a subsequent same-source KVO arrives with end-time position.
        for (NSNumber *invalidateByLoad in @[@NO, @YES]) {
            earlyFinal = sources(2, NO);
            finalPlayer = removalPlayer(earlyFinal, @[@0,@1], @[earlyFinal[0].item,earlyFinal[1].item], 0, NO);
            [finalPlayer updateOrder]; [finalPlayer setValue:@YES forKey:@"_enqueuedAll"];
            [finalPlayer onComplete:[NSNotification notificationWithName:@"ended" object:earlyFinal[1].item]];
            if (invalidateByLoad.boolValue) {
                finalPlayer.loadSource = [[ConcatenatingAudioSource alloc] initWithId:@"same-source" audioSources:[earlyFinal mutableCopy] shuffleOrder:@[@0,@1] lazyLoading:@NO];
                [finalPlayer load:@{@"type": @"concatenating"} initialPosition:kCMTimeZero initialIndex:@1 result:^(id result) {}];
            } else {
                [finalPlayer seek:kCMTimeZero index:@1 completionHandler:^(BOOL finished) {}];
            }
            earlyFinal[1].lastSeek = CMTimeMake(1, 1);
            [finalPlayer observeValueForKeyPath:@"currentItem" ofObject:finalPlayer.player change:@{NSKeyValueChangeNewKey: earlyFinal[1].item} context:nil];
            NSCAssert([[finalPlayer valueForKey:@"_processingState"] intValue] == psReady, @"superseded future-final witness completed seek/load");
        }

        // Exercise the real explicit-seek route and real load replacement. Old
        // item callbacks are no longer members and cannot complete the new load.
        __block BOOL seekFinished = NO;
        [p seek:CMTimeMake(1, 2) index:@1 completionHandler:^(BOOL finished) { seekFinished = finished; }];
        NSCAssert(seekFinished && physical[1].seeks == 1 && CMTIME_COMPARE_INLINE(physical[1].lastSeek, ==, CMTimeMake(1, 2)), @"physical flag changed explicit same-index seek");
        seekFinished = NO;
        [p seek:kCMTimeZero index:@2 completionHandler:^(BOOL finished) { seekFinished = finished; }];
        NSCAssert(seekFinished && [[p valueForKey:@"_index"] intValue] == 2 && (id)p.player.currentItem == physical[2].item, @"physical flag changed explicit index seek");
        [p setValue:@(psLoading) forKey:@"_processingState"];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[2].item]];
        NSCAssert([[p valueForKey:@"_processingState"] intValue] == psLoading, @"completion stole load ownership");
        [p setValue:@(psReady) forKey:@"_processingState"];
        [p setValue:[NSValue valueWithCMTime:kCMTimeZero] forKey:@"_seekPos"];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[2].item]];
        NSCAssert([[p valueForKey:@"_processingState"] intValue] == psReady, @"completion stole pending seek ownership");
        [p setValue:[NSValue valueWithCMTime:kCMTimeInvalid] forKey:@"_seekPos"];
        NSArray<TestSource *> *replacement = sources(2, NO);
        p.loadSource = [[ConcatenatingAudioSource alloc] initWithId:@"replacement" audioSources:[replacement mutableCopy] shuffleOrder:@[@0,@1] lazyLoading:@NO];
        __block BOOL loadFinished = NO;
        [p load:@{ @"type": @"concatenating" } initialPosition:kCMTimeZero initialIndex:@1 result:^(id result) { loadFinished = YES; }];
        NSCAssert(loadFinished && [[p valueForKey:@"_index"] intValue] == 1 && (id)p.player.currentItem == replacement[1].item, @"physical flag changed load initial index");
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[2].item]];
        NSCAssert([[p valueForKey:@"_processingState"] intValue] == psReady && [[p valueForKey:@"_index"] intValue] == 1, @"retired source completed replacement");

        // Shuffled finality uses playback order, not numerical source index.
        physical = sources(3, NO);
        p = removalPlayer(physical, @[@2,@0,@1], @[physical[0].item,physical[1].item], 0, YES);
        [p updateOrder];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[1].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 0 && [[p valueForKey:@"_processingState"] intValue] == psReady, @"future shuffled final source completed early");
        [((TestQueue *)(id)p.player).storage removeObjectAtIndex:0];
        [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[1].item]];
        NSCAssert([[p valueForKey:@"_index"] intValue] == 1 && [[p valueForKey:@"_processingState"] intValue] == psCompleted, @"shuffled actual final source did not complete");

        for (NSNumber *loop in @[@(lmLoopOne), @(lmLoopAll)]) {
            physical = sources(2, NO);
            p = removalPlayer(physical, @[@0,@1], @[physical[0].item,physical[1].item], 0, NO);
            [p updateOrder]; [p setValue:loop forKey:@"_loopMode"];
            [p onComplete:[NSNotification notificationWithName:@"ended" object:physical[0].item]];
            NSCAssert(physical[0].seeks == 1 && [[p valueForKey:@"_justAdvanced"] boolValue], @"physical flag changed loop completion");
            NSCAssert([[p valueForKey:@"_index"] intValue] == (loop.intValue == lmLoopAll ? 1 : 0), @"physical flag changed loop index");
        }
        setenv("READALOUD_QUEUE_BOUNDARY_AUDIT", "1", 1);
        p = player(physical, @[@0,@1], @[physical[0].item]);
        NSCAssert([[p readAloudQueueBoundaryAudit][@"physicalHeadIndex"] boolValue], @"QA mode absent from native audit receipt");
        unsetenv("READALOUD_QUEUE_BOUNDARY_AUDIT");
        unsetenv("READALOUD_QUEUE_PHYSICAL_HEAD_INDEX");
        NSLog(@"PASS: physical-head QA future/stale/duplicate/EOF/KVO/snapshot/prune/load/seek/shuffle/loop scenarios (no app/audio)");

    }
    } @catch (NSException *exception) {
        NSLog(@"FAIL: %@", exception.reason);
        return 1;
    }
    return 0;
}
