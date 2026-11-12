#import "./include/just_audio/BetterEventChannel.h"
#import "./include/just_audio/AudioPlayer.h"
#import "./include/just_audio/AudioSource.h"
#import "./include/just_audio/IndexedAudioSource.h"
#import "./include/just_audio/LoadControl.h"
#import "./include/just_audio/UriAudioSource.h"
#import "./include/just_audio/ConcatenatingAudioSource.h"
#import "./include/just_audio/LoopingAudioSource.h"
#import "./include/just_audio/ClippingAudioSource.h"
#import <AVFoundation/AVFoundation.h>
#import <stdlib.h>
#import <stdatomic.h>
#import <time.h>
#import <objc/runtime.h>
#include <TargetConditionals.h>

#define TREADMILL_SIZE 2
#define ERROR_ABORT 10000000

static char readAloudAuditIdentityKey;
static NSString *readAloudAuditIdentity(id object) {
    if (!object) return nil;
    NSString *identity = objc_getAssociatedObject(object, &readAloudAuditIdentityKey);
    if (!identity) {
        identity = [NSUUID UUID].UUIDString;
        objc_setAssociatedObject(object, &readAloudAuditIdentityKey, identity, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return identity;
}

// TODO: Check for and report invalid state transitions.
// TODO: Apply Apple's guidance on seeking: https://developer.apple.com/library/archive/qa/qa1820/_index.html
@implementation AudioPlayer {
    NSObject<FlutterPluginRegistrar>* _registrar;
    FlutterMethodChannel *_methodChannel;
    BetterEventChannel *_eventChannel;
    BetterEventChannel *_dataEventChannel;
    NSString *_playerId;
    AVQueuePlayer *_player;
    AudioSource *_audioSource;
    NSMutableArray<IndexedAudioSource *> *_indexedAudioSources;
    NSArray<NSNumber *> *_order;
    NSMutableArray<NSNumber *> *_orderInv;
    int _index;
    enum ProcessingState _processingState;
    enum LoopMode _loopMode;
    BOOL _shuffleModeEnabled;
    long long _updateTime;
    int _updatePosition;
    int _lastPosition;
    int _bufferedPosition;
    // Set when the current item hasn't been played yet so we aren't sure whether sufficient audio has been buffered.
    BOOL _bufferUnconfirmed;
    CMTime _seekPos;
    FlutterResult _loadResult;
    FlutterResult _playResult;
    id _timeObserver;
    BOOL _automaticallyWaitsToMinimizeStalling;
    BOOL _allowsExternalPlayback;
    LoadControl *_loadControl;
    BOOL _useLazyPreparation;
    BOOL _playing;
    float _speed;
    float _volume;
    BOOL _justAdvanced;
    BOOL _enqueuedAll;
    NSDictionary<NSString *, NSObject *> *_icyMetadata;
    NSNumber *_errorCode;
    NSString *_errorMessage;
    // QA diagnostic ownership: main thread only, except the atomic skip counter.
    // No dispatch, observer additions, retained media objects, logging or I/O.
    BOOL _queueBoundaryAuditEnabled;
    atomic_uint_fast64_t _queueBoundaryAuditOffMain;
    NSMutableArray<NSDictionary *> *_queueBoundaryAuditEvents;
    NSMutableDictionary<NSString *, NSDictionary *> *_queueBoundaryAuditSources;
    NSMutableDictionary<NSString *, NSDictionary *> *_queueBoundaryAuditItems;
    NSString *_queueBoundaryAuditSession;
    NSUInteger _queueBoundaryAuditNext;
    NSUInteger _queueBoundaryAuditOverflow;
    NSUInteger _queueBoundaryAuditRevision;
    BOOL _queueBoundaryAuditRegistryOverflow;
    BOOL _queueBoundaryAuditDisposed;
    BOOL _readAloudQueueSkipLoopOffRewind;
    BOOL _readAloudQueuePhysicalHeadIndex; // QA diagnostic override only.
    BOOL _readAloudFiniteLocalWavQueue; // Immutable per native player, macOS only.
    __weak IndexedPlayerItem *_readAloudPendingFinalCompletion;
}

+ (BOOL)readAloudQueueBoundaryAuditEnabled {
    const char *value = getenv("READALOUD_QUEUE_BOUNDARY_AUDIT");
    return value && strcmp(value, "1") == 0;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queueBoundaryAuditEnabled = [AudioPlayer readAloudQueueBoundaryAuditEnabled];
        const char *skipRewind = getenv("READALOUD_QUEUE_SKIP_LOOP_OFF_REWIND");
        _readAloudQueueSkipLoopOffRewind = skipRewind && strcmp(skipRewind, "1") == 0;
        const char *physicalHead = getenv("READALOUD_QUEUE_PHYSICAL_HEAD_INDEX");
        _readAloudQueuePhysicalHeadIndex = physicalHead && strcmp(physicalHead, "1") == 0;
        atomic_init(&_queueBoundaryAuditOffMain, 0);
        if (_queueBoundaryAuditEnabled) {
            _queueBoundaryAuditEvents = [NSMutableArray new];
            _queueBoundaryAuditSources = [NSMutableDictionary new];
            _queueBoundaryAuditItems = [NSMutableDictionary new];
            _queueBoundaryAuditSession = [NSUUID UUID].UUIDString;
        }
    }
    return self;
}

- (BOOL)queueBoundaryAuditCanRecord {
    if (!_queueBoundaryAuditEnabled) return NO;
    if (![NSThread isMainThread]) {
        atomic_fetch_add_explicit(&_queueBoundaryAuditOffMain, 1, memory_order_relaxed);
        return NO;
    }
    return YES;
}

// Immutable identities are captured while the weak source link is alive. The
// registry retains strings/numbers only, never a source/item/asset/player.
- (NSString *)queueBoundaryAuditItem:(IndexedPlayerItem *)item selectSource:(BOOL)selectSource {
    if (!item) return nil;
    NSString *itemIdentity = readAloudAuditIdentity(item);
    if (_queueBoundaryAuditItems[itemIdentity]) return itemIdentity;
    IndexedAudioSource *source = item.audioSource;
    NSString *sourceIdentity = readAloudAuditIdentity(source);
    if (!sourceIdentity) return itemIdentity;
    if (!_queueBoundaryAuditSources[sourceIdentity] && selectSource && _queueBoundaryAuditSources.count < 8) {
        NSString *url = nil;
        if ([item respondsToSelector:@selector(asset)] && [item.asset isKindOfClass:[AVURLAsset class]]) {
            url = ((AVURLAsset *)item.asset).URL.absoluteString;
        }
        _queueBoundaryAuditSources[sourceIdentity] = @{
            @"sourceIdentity": sourceIdentity, @"declaredSourceId": source.sourceId ?: (id)[NSNull null],
            @"sourceURL": url ?: (id)[NSNull null], @"firstRevision": @(_queueBoundaryAuditRevision)};
    }
    if (_queueBoundaryAuditSources[sourceIdentity]) {
        if (_queueBoundaryAuditItems.count == 64) {
            _queueBoundaryAuditRegistryOverflow = YES;
        } else {
            _queueBoundaryAuditItems[itemIdentity] = @{@"itemIdentity": itemIdentity,
                @"sourceIdentity": sourceIdentity, @"firstRevision": @(_queueBoundaryAuditRevision)};
        }
    }
    return itemIdentity;
}

- (NSDictionary *)queueBoundaryAuditItemState:(IndexedPlayerItem *)item {
    if (!item) return @{};
    double position = [item respondsToSelector:@selector(currentTime)] ? CMTimeGetSeconds(item.currentTime) : NAN;
    NSMutableArray *ranges = [NSMutableArray new];
    NSArray *loaded = [item respondsToSelector:@selector(loadedTimeRanges)] ? item.loadedTimeRanges : @[];
    for (NSUInteger i = 0; i < MIN((NSUInteger)8, loaded.count); i++) {
        CMTimeRange range = [loaded[i] CMTimeRangeValue];
        double start = CMTimeGetSeconds(range.start), duration = CMTimeGetSeconds(range.duration);
        [ranges addObject:@{@"startSeconds": isfinite(start) ? @(start) : (id)[NSNull null],
                            @"durationSeconds": isfinite(duration) ? @(duration) : (id)[NSNull null]}];
    }
    return @{@"currentTimeSeconds": isfinite(position) ? @(position) : (id)[NSNull null],
             @"status": [item respondsToSelector:@selector(status)] ? @(item.status) : (id)[NSNull null],
             @"bufferEmpty": [item respondsToSelector:@selector(isPlaybackBufferEmpty)] ? @(item.playbackBufferEmpty) : (id)[NSNull null],
             @"bufferFull": [item respondsToSelector:@selector(isPlaybackBufferFull)] ? @(item.playbackBufferFull) : (id)[NSNull null],
             @"likelyToKeepUp": [item respondsToSelector:@selector(isPlaybackLikelyToKeepUp)] ? @(item.playbackLikelyToKeepUp) : (id)[NSNull null],
             @"loadedTimeRanges": ranges, @"loadedTimeRangesTotal": @(loaded.count),
             @"loadedTimeRangesTruncated": @(loaded.count > 8)};
}

- (void)queueBoundaryAudit:(NSString *)boundary item:(IndexedPlayerItem *)item details:(NSDictionary *)details {
    if (![self queueBoundaryAuditCanRecord]) return;
    // Timestamps precede AVFoundation queries. Queue/current snapshots are
    // sequential observations, not an atomic claim about the advancing player.
    long long unixMicros = (long long)([NSDate date].timeIntervalSince1970 * 1000000.0);
    struct timespec monotonic;
    clock_gettime(CLOCK_MONOTONIC, &monotonic);
    NSString *itemId = [self queueBoundaryAuditItem:item selectSource:NO];
    NSArray *physicalQueue = _player.items ?: @[];
    IndexedPlayerItem *current = (IndexedPlayerItem *)_player.currentItem;
    NSString *currentId = [self queueBoundaryAuditItem:current selectSource:NO];
    NSMutableArray *queueIds = [NSMutableArray new];
    NSUInteger untrackedQueueItems = 0;
    BOOL selectedPresent = _queueBoundaryAuditItems[itemId] != nil || _queueBoundaryAuditItems[currentId] != nil;
    for (NSUInteger i = 0; i < MIN((NSUInteger)32, physicalQueue.count); i++) {
        NSString *identity = [self queueBoundaryAuditItem:(IndexedPlayerItem *)physicalQueue[i] selectSource:NO];
        [queueIds addObject:identity];
        selectedPresent |= _queueBoundaryAuditItems[identity] != nil;
        if (!_queueBoundaryAuditItems[identity]) untrackedQueueItems++;
    }
    BOOL lifecycle = [boundary hasPrefix:@"load."] || [boundary hasPrefix:@"dispose."];
    if (!selectedPresent && !lifecycle) return;
    id sourceInSequence = @NO;
    NSString *sourceId = _queueBoundaryAuditItems[itemId][@"sourceIdentity"];
    NSUInteger membershipLimit = MIN((NSUInteger)32, _indexedAudioSources.count);
    for (NSUInteger i = 0; i < membershipLimit; i++) {
        IndexedAudioSource *source = _indexedAudioSources[i];
        if ([objc_getAssociatedObject(source, &readAloudAuditIdentityKey) isEqual:sourceId]) {
            sourceInSequence = @YES;
            break;
        }
    }
    if (![sourceInSequence boolValue] && _indexedAudioSources.count > membershipLimit) sourceInSequence = [NSNull null];
    id timeControl = [NSNull null], waitReason = [NSNull null];
    if (@available(macOS 10.12, iOS 10.0, *)) {
        if ([_player respondsToSelector:@selector(timeControlStatus)]) timeControl = @(_player.timeControlStatus);
        if ([_player respondsToSelector:@selector(reasonForWaitingToPlay)]) waitReason = _player.reasonForWaitingToPlay ?: (id)[NSNull null];
    }
    NSDictionary *event = @{@"boundary": boundary, @"ordinal": @(_queueBoundaryAuditEvents.count + _queueBoundaryAuditOverflow), @"unixMicros": @(unixMicros),
        @"monotonicMicros": @((uint64_t)monotonic.tv_sec * 1000000 + monotonic.tv_nsec / 1000),
        @"revision": @(_queueBoundaryAuditRevision), @"disposed": @(_queueBoundaryAuditDisposed),
        @"logicalIndex": @(_index), @"loopMode": @(_loopMode), @"processingState": @(_processingState),
        @"itemIdentity": itemId ?: (id)[NSNull null], @"itemTracked": @(_queueBoundaryAuditItems[itemId] != nil),
        @"itemSourceInSequence": sourceInSequence, @"sequenceMembershipSearchTruncated": @(_indexedAudioSources.count > membershipLimit),
        @"itemState": [self queueBoundaryAuditItemState:item],
        @"currentItemIdentity": currentId ?: (id)[NSNull null], @"currentItemTracked": @(_queueBoundaryAuditItems[currentId] != nil),
        @"currentItemState": [self queueBoundaryAuditItemState:current],
        @"queueItemIdentities": queueIds, @"queueTotal": @(physicalQueue.count), @"queueTruncated": @(physicalQueue.count > 32),
        @"queueSnapshotUntrackedCount": @(untrackedQueueItems),
        @"queueSnapshotHeadIdentity": queueIds.firstObject ?: (id)[NSNull null],
        @"timeControlStatus": timeControl, @"reasonForWaitingToPlay": waitReason,
        @"details": details ?: @{}};
    if (_queueBoundaryAuditEvents.count < 2048) [_queueBoundaryAuditEvents addObject:event];
    else {
        _queueBoundaryAuditEvents[_queueBoundaryAuditNext] = event;
        _queueBoundaryAuditOverflow++;
    }
    _queueBoundaryAuditNext = (_queueBoundaryAuditNext + 1) % 2048;
}

- (NSDictionary *)readAloudQueueBoundaryAudit {
    if (![self queueBoundaryAuditCanRecord]) return @{@"id": _playerId ?: @"", @"enabled": @NO, @"events": @[]};
    NSMutableArray *ordered = [NSMutableArray new];
    for (NSUInteger i = 0; i < _queueBoundaryAuditEvents.count; i++) {
        NSUInteger index = (_queueBoundaryAuditEvents.count == 2048 ? _queueBoundaryAuditNext + i : i) % 2048;
        [ordered addObject:_queueBoundaryAuditEvents[index]];
    }
    return @{@"id": _playerId ?: @"", @"enabled": @YES, @"sessionIdentity": _queueBoundaryAuditSession,
        @"events": ordered, @"sources": _queueBoundaryAuditSources.allValues, @"items": _queueBoundaryAuditItems.allValues,
        @"overflow": @(_queueBoundaryAuditOverflow), @"offMainSkipped": @(atomic_load_explicit(&_queueBoundaryAuditOffMain, memory_order_relaxed)),
        @"identityRegistryOverflow": @(_queueBoundaryAuditRegistryOverflow), @"disposed": @(_queueBoundaryAuditDisposed),
        @"skipLoopOffRewind": @(_readAloudQueueSkipLoopOffRewind), @"physicalHeadIndex": @([self usesPhysicalHeadIndex]), @"physicalHeadIndexDiagnostic": @(_readAloudQueuePhysicalHeadIndex), @"finiteLocalWavQueue": @(_readAloudFiniteLocalWavQueue),
        @"sourceLimit": @8, @"itemLimit": @64, @"eventLimit": @2048, @"queueSnapshotLimit": @32,
        @"snapshotAtomic": @NO, @"readBeforeDisposeRequired": @YES,
        @"scope": @"first8SourceObjectsPerPlayerLifetime", @"owner": @"mainThread", @"monotonicClock": @"CLOCK_MONOTONIC"};
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam loadConfiguration:(NSDictionary *)loadConfiguration useLazyPreparation:(BOOL)useLazyPreparation readAloudFiniteLocalWavQueue:(BOOL)finiteLocalWavQueue {
    self = [self init];
    NSAssert(self, @"super init cannot be nil");
#if TARGET_OS_OSX
    _readAloudFiniteLocalWavQueue = finiteLocalWavQueue;
#endif
    _registrar = registrar;
    _playerId = idParam;
    _useLazyPreparation = useLazyPreparation;
    _methodChannel =
        [FlutterMethodChannel methodChannelWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.methods.%@", _playerId]
                                    binaryMessenger:[registrar messenger]];
    _eventChannel = [[BetterEventChannel alloc]
        initWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.events.%@", _playerId]
           messenger:[registrar messenger]];
    _dataEventChannel = [[BetterEventChannel alloc]
        initWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.data.%@", _playerId]
           messenger:[registrar messenger]];
    _index = 0;
    _processingState = psIdle;
    _loopMode = lmLoopOff;
    _shuffleModeEnabled = NO;
    _player = nil;
    _audioSource = nil;
    _indexedAudioSources = nil;
    _order = nil;
    _orderInv = nil;
    _seekPos = kCMTimeInvalid;
    _timeObserver = 0;
    _updatePosition = 0;
    _updateTime = 0;
    _lastPosition = 0;
    _bufferedPosition = 0;
    _bufferUnconfirmed = NO;
    _playing = NO;
    _loadResult = nil;
    _playResult = nil;
    _automaticallyWaitsToMinimizeStalling = YES;
    _allowsExternalPlayback = NO;
    _loadControl = nil;
    if (loadConfiguration != (id)[NSNull null]) {
        NSDictionary *map = loadConfiguration[@"darwinLoadControl"];
        if (map != (id)[NSNull null]) {
            _loadControl = [[LoadControl alloc] init];
            _loadControl.preferredForwardBufferDuration = (NSNumber *)map[@"preferredForwardBufferDuration"];
            _loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = (BOOL)[map[@"canUseNetworkResourcesForLiveStreamingWhilePaused"] boolValue];
            _loadControl.preferredPeakBitRate = (NSNumber *)map[@"preferredPeakBitRate"];
            _automaticallyWaitsToMinimizeStalling = (BOOL)[map[@"automaticallyWaitsToMinimizeStalling"] boolValue];
        }
    }
    if (!_loadControl) {
        _loadControl = [[LoadControl alloc] init];
        _loadControl.preferredForwardBufferDuration = (NSNumber *)[NSNull null];
        _loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = NO;
        _loadControl.preferredPeakBitRate = (NSNumber *)[NSNull null];
    }
    _speed = 1.0f;
    _volume = 1.0f;
    _justAdvanced = NO;
    _enqueuedAll = NO;
    _icyMetadata = @{};
    _errorCode = (NSNumber *)[NSNull null];
    _errorMessage = (NSString *)[NSNull null];
    __weak __typeof__(self) weakSelf = self;
    [_methodChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
        [weakSelf handleMethodCall:call result:result];
    }];
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    @try {
        //NSLog(@"method: %@ index=%d", call.method, _index);
        NSDictionary *request = (NSDictionary *)call.arguments;
        if ([@"load" isEqualToString:call.method]) {
            CMTime initialPosition = request[@"initialPosition"] == (id)[NSNull null] ? kCMTimeInvalid : CMTimeMake([request[@"initialPosition"] longLongValue], 1000000);
            [self load:request[@"audioSource"] initialPosition:initialPosition initialIndex:request[@"initialIndex"] result:result];
        } else if ([@"play" isEqualToString:call.method]) {
            [self play:result];
        } else if ([@"pause" isEqualToString:call.method]) {
            [self pause];
            result(@{});
        } else if ([@"setVolume" isEqualToString:call.method]) {
            [self setVolume:(float)[request[@"volume"] doubleValue]];
            result(@{});
        } else if ([@"setSkipSilence" isEqualToString:call.method]) {
            /// TODO on iOS side; Seems more involved, so someone with ObjectiveC experience might look at it.
            result(@{});
        } else if ([@"setSpeed" isEqualToString:call.method]) {
            [self setSpeed:(float)[request[@"speed"] doubleValue]];
            result(@{});
        } else if ([@"setLoopMode" isEqualToString:call.method]) {
            [self setLoopMode:[request[@"loopMode"] intValue]];
            result(@{});
        } else if ([@"setShuffleMode" isEqualToString:call.method]) {
            [self setShuffleModeEnabled:(BOOL)([request[@"shuffleMode"] intValue] == 1)];
            result(@{});
        } else if ([@"setShuffleOrder" isEqualToString:call.method]) {
            [self setShuffleOrder:(NSDictionary *)request[@"audioSource"]];
            result(@{});
        } else if ([@"setAutomaticallyWaitsToMinimizeStalling" isEqualToString:call.method]) {
            [self setAutomaticallyWaitsToMinimizeStalling:(BOOL)[request[@"enabled"] boolValue]];
            result(@{});
        } else if ([@"setCanUseNetworkResourcesForLiveStreamingWhilePaused" isEqualToString:call.method]) {
            [self setCanUseNetworkResourcesForLiveStreamingWhilePaused:(BOOL)[request[@"enabled"] boolValue]];
            result(@{});
        } else if ([@"setPreferredPeakBitRate" isEqualToString:call.method]) {
            [self setPreferredPeakBitRate:(NSNumber *)request[@"bitRate"]];
            result(@{});
        } else if ([@"setAllowsExternalPlayback" isEqualToString:call.method]) {
            [self setAllowsExternalPlayback:(BOOL)([request[@"allowsExternalPlayback"] intValue] == 1)];
            result(@{});
        } else if ([@"seek" isEqualToString:call.method]) {
            CMTime position = request[@"position"] == (id)[NSNull null] ? kCMTimePositiveInfinity : CMTimeMake([request[@"position"] longLongValue], 1000000);
            [self seek:position index:request[@"index"] completionHandler:^(BOOL finished) {
                result(@{});
            }];
        } else if ([@"concatenatingInsertAll" isEqualToString:call.method]) {
            [self concatenatingInsertAll:(NSString *)request[@"id"] index:[request[@"index"] intValue] sources:(NSArray *)request[@"children"] shuffleOrder:(NSArray<NSNumber *> *)request[@"shuffleOrder"]];
            result(@{});
        } else if ([@"concatenatingRemoveRange" isEqualToString:call.method]) {
            [self concatenatingRemoveRange:(NSString *)request[@"id"] start:[request[@"startIndex"] intValue] end:[request[@"endIndex"] intValue] shuffleOrder:(NSArray<NSNumber *> *)request[@"shuffleOrder"]];
            result(@{});
        } else if ([@"concatenatingMove" isEqualToString:call.method]) {
            [self concatenatingMove:(NSString *)request[@"id"] currentIndex:[request[@"currentIndex"] intValue] newIndex:[request[@"newIndex"] intValue] shuffleOrder:(NSArray<NSNumber *> *)request[@"shuffleOrder"]];
            result(@{});
        } else if ([@"setAndroidAudioAttributes" isEqualToString:call.method]) {
            result(@{});
        } else {
            result(FlutterMethodNotImplemented);
        }
    } @catch (NSException *exception) {
        //NSLog(@"%@", [exception callStackSymbols]);
        BOOL unsupported = [exception.name isEqual:@"readaloud_unsupported_source"];
        FlutterError *flutterError = [FlutterError errorWithCode:unsupported ? exception.name : @"error"
            message:unsupported ? exception.reason : @"Error in handleMethodCall" details:nil];
        result(flutterError);
    }
}

- (AVQueuePlayer *)player {
    return _player;
}

- (float)speed {
    return _speed;
}

- (BOOL)usesPhysicalHeadIndex {
    return _readAloudFiniteLocalWavQueue || _readAloudQueuePhysicalHeadIndex;
}

// The caller owns WAV provenance. Native admission verifies actual file assets
// and plain source/item identity, never a filename suffix or a ready duration.
// These checks run on the existing method-channel owner before any mutation.
- (BOOL)isFiniteLocalWavDefinition:(NSDictionary *)definition {
    if ([definition[@"type"] isEqual:@"progressive"]) return YES;
    if (![definition[@"type"] isEqual:@"concatenating"]) return NO;
    for (NSDictionary *child in definition[@"children"]) {
        if (![self isFiniteLocalWavDefinition:child]) return NO;
    }
    return YES;
}

- (BOOL)isPlainLocalFileItem:(IndexedPlayerItem *)item source:(IndexedAudioSource *)source {
    if (![source isKindOfClass:[UriAudioSource class]]) return NO;
    AVAsset *asset = item.asset;
    if (![asset isKindOfClass:[AVURLAsset class]]) return NO;
    NSURL *actualURL = ((AVURLAsset *)asset).URL;
    NSURL *declaredURL = [NSURL URLWithString:((UriAudioSource *)source).uri];
    return actualURL.isFileURL && actualURL.path.isAbsolutePath && declaredURL.isFileURL &&
        declaredURL.host.length == 0 && !declaredURL.query && !declaredURL.fragment &&
        [actualURL.URLByStandardizingPath isEqual:declaredURL.URLByStandardizingPath];
}

- (BOOL)isPlainLocalFileSource:(IndexedAudioSource *)source {
    return [self isPlainLocalFileItem:source.playerItem source:source] &&
        (!source.playerItem2 || [self isPlainLocalFileItem:source.playerItem2 source:source]);
}

- (BOOL)isFiniteLocalWavTree:(AudioSource *)tree {
    if (!tree) return NO;
    NSMutableArray<IndexedAudioSource *> *sequence = [NSMutableArray new];
    [tree buildSequence:sequence treeIndex:0];
    for (IndexedAudioSource *source in sequence) {
        if (![self isPlainLocalFileSource:source]) return NO;
    }
    return YES;
}

- (BOOL)hasValidLocalQueueMembership {
    for (IndexedAudioSource *source in _indexedAudioSources) {
        if (![self isPlainLocalFileSource:source]) return NO;
    }
    for (IndexedPlayerItem *item in _player.items) {
        int index = [self indexForItem:item];
        if (index < 0 || item.audioSource != _indexedAudioSources[index] ||
                ![self isPlainLocalFileItem:item source:_indexedAudioSources[index]]) return NO;
    }
    return YES;
}

// Untested
- (void)concatenatingInsertAll:(NSString *)catId index:(int)index sources:(NSArray *)sources shuffleOrder:(NSArray<NSNumber *> *)shuffleOrder {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"concatenatingInsertAll.entry" item:nil details:@{@"sourceId": catId, @"index": @(index), @"childrenCount": @(sources.count)}];
    // Find all duplicates of the identified ConcatenatingAudioSource.
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    [_audioSource findById:catId matches:matches];
    // Decode and validate the entire insertion before the first matching tree
    // changes. A bad later child/duplicate match cannot leave a partial insert.
    NSMutableArray *decodedMatches = [NSMutableArray new];
    if (_readAloudFiniteLocalWavQueue) {
        if (![self hasValidLocalQueueMembership]) {
            [NSException raise:@"readaloud_unsupported_source" format:@"Finite local WAV queue membership changed"];
        }
        for (NSDictionary *definition in sources) {
            if (![self isFiniteLocalWavDefinition:definition]) {
                [NSException raise:@"readaloud_unsupported_source" format:@"Finite local WAV player requires plain local file sources"];
            }
        }
        for (NSUInteger i = 0; i < matches.count; i++) {
            NSMutableArray *decoded = [self decodeAudioSources:sources];
            for (AudioSource *tree in decoded) {
                if (![self isFiniteLocalWavTree:tree]) {
                    [NSException raise:@"readaloud_unsupported_source" format:@"Finite local WAV player requires local AVURLAsset files"];
                }
            }
            [decodedMatches addObject:decoded];
        }
    }
    // Add each new source to each match.
    for (int i = 0; i < matches.count; i++) {
        ConcatenatingAudioSource *catSource = (ConcatenatingAudioSource *)matches[i];
        int idx = index >= 0 ? index : catSource.count;
        NSMutableArray<AudioSource *> *audioSources = _readAloudFiniteLocalWavQueue ? decodedMatches[i] : [self decodeAudioSources:sources];
        for (int j = 0; j < audioSources.count; j++) {
            AudioSource *audioSource = audioSources[j];
            [catSource insertSource:audioSource atIndex:(idx + j)];
        }
        [catSource setShuffleOrder:shuffleOrder];
    }
    // Index the new audio sources.
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        IndexedAudioSource *audioSource = _indexedAudioSources[i];
        if (!audioSource.isAttached) {
            audioSource.playerItem.audioSource = audioSource;
            [self addItemObservers:audioSource.playerItem];
        }
    }
    [self updateOrder];
    if (_player.currentItem) {
        _index = [self indexForItem:(IndexedPlayerItem *)_player.currentItem];
    } else {
        _index = 0;
    }
    [self enqueueFrom:_index preservingCurrentItem:YES];
    // Notify each new IndexedAudioSource that it's been attached to the player.
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        if (!_indexedAudioSources[i].isAttached) {
            [_indexedAudioSources[i] attach:_player initialPos:kCMTimeInvalid];
        }
    }
    [self broadcastPlaybackEvent];
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"concatenatingInsertAll.return" item:nil details:nil];
}

// Untested
- (void)concatenatingRemoveRange:(NSString *)catId start:(int)start end:(int)end shuffleOrder:(NSArray<NSNumber *> *)shuffleOrder {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"concatenatingRemoveRange.entry" item:nil details:@{@"sourceId": catId, @"start": @(start), @"end": @(end)}];
    // Find all duplicates of the identified ConcatenatingAudioSource.
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    [_audioSource findById:catId matches:matches];
    // Remove range from each match.
    for (int i = 0; i < matches.count; i++) {
        ConcatenatingAudioSource *catSource = (ConcatenatingAudioSource *)matches[i];
        int endIndex = end >= 0 ? end : catSource.count;
        [catSource removeSourcesFromIndex:start toIndex:endIndex];
        [catSource setShuffleOrder:shuffleOrder];
    }
    // Re-index the remaining audio sources.
    NSArray<IndexedAudioSource *> *oldIndexedAudioSources = _indexedAudioSources;
    const int oldIndex = _index;
    int removedBeforeCurrent = 0;
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    for (int i = 0, j = 0; i < _indexedAudioSources.count; i++, j++) {
        IndexedAudioSource *audioSource = _indexedAudioSources[i];
        while (audioSource != oldIndexedAudioSources[j]) {
            [self removeItemObservers:oldIndexedAudioSources[j].playerItem];
            if (oldIndexedAudioSources[j].playerItem2) {
                [self removeItemObservers:oldIndexedAudioSources[j].playerItem2];
            }
            if (j < oldIndex) removedBeforeCurrent++;
            j++;
        }
    }
    // Pruning several predecessors must compare their old indices against one
    // immutable index. More importantly, AVQueuePlayer may advance while the
    // source tree is rebuilt: retain its actual current item whenever it remains
    // in the new sequence instead of replacing it with a guessed neighbour.
    int currentIndex = [self indexForItem:(IndexedPlayerItem *)_player.currentItem];
    _index = currentIndex >= 0 ? currentIndex : oldIndex - removedBeforeCurrent;
    [self updateOrder];
    if (_index >= _indexedAudioSources.count) _index = (int)_indexedAudioSources.count - 1;
    if (_index < 0) _index = 0;
    [self enqueueFrom:_index preservingCurrentItem:YES];
    [self broadcastPlaybackEvent];
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"concatenatingRemoveRange.return" item:nil details:nil];
}

// Untested
- (void)concatenatingMove:(NSString *)catId currentIndex:(int)currentIndex newIndex:(int)newIndex shuffleOrder:(NSArray<NSNumber *> *)shuffleOrder {
    // Find all duplicates of the identified ConcatenatingAudioSource.
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    [_audioSource findById:catId matches:matches];
    // Move range within each match.
    for (int i = 0; i < matches.count; i++) {
        ConcatenatingAudioSource *catSource = (ConcatenatingAudioSource *)matches[i];
        [catSource moveSourceFromIndex:currentIndex toIndex:newIndex];
        [catSource setShuffleOrder:shuffleOrder];
    }
    // Re-index the audio sources.
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    [self updateOrder];
    [self enqueueFrom:[self indexForItem:(IndexedPlayerItem *)_player.currentItem]];
    [self broadcastPlaybackEvent];
}

- (void)checkForDiscontinuity {
    if (!_playing || CMTIME_IS_VALID(_seekPos) || _processingState == psCompleted) return;
    int position = [self getCurrentPosition];
    if (_processingState == psBuffering) {
        if (position > _lastPosition) {
            [self leaveBuffering:@"stall ended"];
            [self updatePosition];
            [self broadcastPlaybackEvent];
        }
    } else {
        long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        long long timeSinceLastUpdate = now - _updateTime;
        long long expectedPosition = _updatePosition + (long long)(timeSinceLastUpdate * _player.rate);
        long long drift = position - expectedPosition;
        //NSLog(@"position: %d, drift: %lld", position, drift);
        // Update if we've drifted or just started observing
        if (_updateTime == 0L) {
            [self broadcastPlaybackEvent];
        } else if (drift < -100) {
            [self enterBuffering:@"stalling"];
            //NSLog(@"Drift: %lld", drift);
            [self updatePosition];
            [self broadcastPlaybackEvent];
        }
    }
    _lastPosition = position;
}

- (void)enterBuffering:(NSString *)reason {
    if (_processingState != psIdle) {
        //NSLog(@"ENTER BUFFERING: %@", reason);
        _processingState = psBuffering;
    }
}

- (void)leaveBuffering:(NSString *)reason {
    if (_processingState == psBuffering || _processingState == psLoading) {
        //NSLog(@"LEAVE BUFFERING: %@", reason);
        _processingState = psReady;
    }
}

- (void)broadcastPlaybackEvent {
    [_eventChannel sendEvent:@{
            @"processingState": @(_processingState),
            @"updatePosition": @((long long)1000 * _updatePosition),
            @"updateTime": @(_updateTime),
            @"bufferedPosition": @((long long)1000 * [self getBufferedPosition]),
            @"icyMetadata": _icyMetadata,
            @"duration": @([self getDurationMicroseconds]),
            @"currentIndex": @(_index),
            @"errorCode": _errorCode,
            @"errorMessage": _errorMessage,
    }];
}

- (int)getCurrentPosition {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"position.read" item:nil details:nil];
    // XXX: During load, the second case will be selected returning 0.
    // TODO: Provide a similar case as _seekPos for _initialPos.
    if (CMTIME_IS_VALID(_seekPos)) {
        return (int)(1000 * CMTimeGetSeconds(_seekPos));
    } else if (_indexedAudioSources && _indexedAudioSources.count > 0) {
        int ms = (int)(1000 * CMTimeGetSeconds(_indexedAudioSources[_index].position));
        if (ms < 0) ms = 0;
        return ms;
    } else {
        return 0;
    }
}

- (int)getBufferedPosition {
    if (_processingState == psIdle || _processingState == psLoading) {
        return 0;
    } else if (_indexedAudioSources && _indexedAudioSources.count > 0) {
        int ms = (int)(1000 * CMTimeGetSeconds(_indexedAudioSources[_index].bufferedPosition));
        if (ms < 0) ms = 0;
        return ms;
    } else {
        return 0;
    }
}

- (int)getDuration {
    if (_processingState == psIdle || _processingState == psLoading) {
        return -1;
    } else if (_indexedAudioSources && _indexedAudioSources.count > 0) {
        int v = (int)(1000 * CMTimeGetSeconds(_indexedAudioSources[_index].duration));
        return v;
    } else {
        return 0;
    }
}

- (long long)getDurationMicroseconds {
    int duration = [self getDuration];
    return duration < 0 ? -1 : ((long long)1000 * duration);
}

- (void)removeItemObservers:(AVPlayerItem *)playerItem {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"observers.remove" item:(IndexedPlayerItem *)playerItem details:nil];
    [playerItem removeObserver:self forKeyPath:@"status"];
    [playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [playerItem removeObserver:self forKeyPath:@"playbackBufferFull"];
    [playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
    //[playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:playerItem];
}

- (void)addItemObservers:(AVPlayerItem *)playerItem {
    if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
        [self queueBoundaryAuditItem:(IndexedPlayerItem *)playerItem selectSource:YES];
        [self queueBoundaryAudit:@"observers.add" item:(IndexedPlayerItem *)playerItem details:nil];
    }
    // Get notified when the item is loaded or had an error loading
    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    // Get notified of the buffer state
    [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"playbackBufferFull" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    //[playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    // Get notified when playback has reached the end
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onComplete:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
    // Get notified when playback stops due to a failure (currently unused)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onFailToComplete:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];
    // Get notified when playback stalls (currently unused)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onItemStalled:) name:AVPlayerItemPlaybackStalledNotification object:playerItem];

    AVPlayerItemMetadataOutput *metadataOutput = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:nil];
    [metadataOutput setDelegate:self queue:dispatch_get_main_queue()];
    // Since the delegate is stored as a weak reference,
    // there shouldn't be a retain cycle.
    // TODO: Check this. Shouldn't need to removeOutput
    // later?
    [playerItem addOutput:metadataOutput];
}

- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output didOutputTimedMetadataGroups:(NSArray<AVTimedMetadataGroup *> *)groups fromPlayerItemTrack:(AVPlayerItemTrack *)track {
    // ICY headers aren't available here. Maybe do this in the proxy.
    BOOL hasIcyData = NO;
    NSString *title = (NSString *)[NSNull null];
    NSString *url = (NSString *)[NSNull null];
    for (int i = 0; i < groups.count; i++) {
        AVTimedMetadataGroup *group = groups[i];
        for (int j = 0; j < group.items.count; j++) {
            AVMetadataItem *item = group.items[j];
            if ([@"icy/StreamTitle" isEqualToString:item.identifier]) {
                hasIcyData = YES;
                title = (NSString *)item.value;
            } else if ([@"icy/StreamUrl" isEqualToString:item.identifier]) {
                hasIcyData = YES;
                url = (NSString *)item.value;
            }
        }
    }
    if (hasIcyData) {
        _icyMetadata = @{
            @"info": @{
                @"title": title,
                @"url": url,
            },
        };
        [self broadcastPlaybackEvent];
    }
}

- (NSMutableArray<AudioSource *> *)decodeAudioSources:(NSArray *)data {
    NSMutableArray<AudioSource *> *array = (NSMutableArray<AudioSource *> *)[[NSMutableArray alloc] init];
    for (int i = 0; i < [data count]; i++) {
        AudioSource *source = [self decodeAudioSource:data[i]];
        [array addObject:source];
    }
    return array;
}

- (AudioSource *)decodeAudioSource:(NSDictionary *)data {
    NSString *type = data[@"type"];
    if ([@"progressive" isEqualToString:type]) {
        return [[UriAudioSource alloc] initWithId:data[@"id"] uri:data[@"uri"] loadControl:_loadControl headers:data[@"headers"] options:data[@"options"]];
    } else if ([@"dash" isEqualToString:type]) {
        return [[UriAudioSource alloc] initWithId:data[@"id"] uri:data[@"uri"] loadControl:_loadControl headers:data[@"headers"] options:data[@"options"]];
    } else if ([@"hls" isEqualToString:type]) {
        return [[UriAudioSource alloc] initWithId:data[@"id"] uri:data[@"uri"] loadControl:_loadControl headers:data[@"headers"] options:data[@"options"]];
    } else if ([@"concatenating" isEqualToString:type]) {
        return [[ConcatenatingAudioSource alloc] initWithId:data[@"id"]
                                               audioSources:[self decodeAudioSources:data[@"children"]]
                                               shuffleOrder:(NSArray<NSNumber *> *)data[@"shuffleOrder"]
                                                lazyLoading:(NSNumber *)data[@"useLazyPreparation"]];
    } else if ([@"clipping" isEqualToString:type]) {
        return [[ClippingAudioSource alloc] initWithId:data[@"id"]
                                           audioSource:(UriAudioSource *)[self decodeAudioSource:data[@"child"]]
                                                 start:data[@"start"]
                                                   end:data[@"end"]];
    } else if ([@"looping" isEqualToString:type]) {
        NSMutableArray *childSources = [NSMutableArray new];
        int count = [data[@"count"] intValue];
        for (int i = 0; i < count; i++) {
            [childSources addObject:[self decodeAudioSource:data[@"child"]]];
        }
        return [[LoopingAudioSource alloc] initWithId:data[@"id"] audioSources:childSources];
    } else {
        return nil;
    }
}

- (void)enqueueFrom:(int)index {
    [self enqueueFrom:index preservingCurrentItem:NO];
}

- (void)enqueueFrom:(int)index preservingCurrentItem:(BOOL)preserveCurrentItem {
    //NSLog(@"### enqueueFrom:%d", index);
    // A sequential extension must not discard already buffered future items.
    // Only preserve a queue that is an identical prefix of the queue the
    // original loop-off path would build. Seeks, loads and mismatches fall
    // through to the original rebuild below.
    // AVQueuePlayer can advance after the caller resolves its current index or
    // while this method computes the desired queue. Use one native queue
    // snapshot for both the head and prefix check. An advance can only remove a
    // prefix of that snapshot, so appending its missing suffix remains safe.
    NSArray<AVPlayerItem *> *existingItems = _player.items;
    if (preserveCurrentItem && _loopMode == lmLoopOff &&
            _processingState != psLoading && CMTIME_IS_INVALID(_seekPos) && existingItems.count > 0) {
        int currentIndex = [self indexForItem:(IndexedPlayerItem *)existingItems.firstObject];
        if (currentIndex >= 0) index = currentIndex;
    }
    IndexedPlayerItem *targetItem = index >= 0 && index < _indexedAudioSources.count
        ? _indexedAudioSources[index].playerItem : nil;
    if (_loopMode == lmLoopOff && _processingState != psLoading &&
            CMTIME_IS_INVALID(_seekPos) && targetItem && existingItems.firstObject == targetItem) {
        NSMutableArray<IndexedPlayerItem *> *desiredItems = [NSMutableArray arrayWithObject:targetItem];
        BOOL include = NO;
        BOOL enqueuedAll = YES;
        for (NSNumber *sourceIndex in _order) {
            int si = [sourceIndex intValue];
            if (si == index) include = YES;
            if (include && _indexedAudioSources[si].playerItem != targetItem) {
                if (_indexedAudioSources[si].lazyLoading && desiredItems.count >= TREADMILL_SIZE) {
                    enqueuedAll = NO;
                    break;
                }
                [desiredItems addObject:_indexedAudioSources[si].playerItem];
            }
        }
        BOOL isPrefix = include && existingItems.count > 0 && existingItems.count <= desiredItems.count;
        for (NSUInteger i = 0; isPrefix && i < existingItems.count; i++) {
            isPrefix = existingItems[i] == desiredItems[i];
        }
        if (isPrefix) {
            _index = index;
            _enqueuedAll = enqueuedAll;
            for (NSUInteger i = existingItems.count; i < desiredItems.count; i++) {
                if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
                    [self queueBoundaryAuditItem:desiredItems[i] selectSource:YES];
                    [self queueBoundaryAudit:@"native.insert.entry" item:desiredItems[i] details:nil];
                }
                [_player insertItem:desiredItems[i] afterItem:nil];
                if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.insert.return" item:desiredItems[i] details:nil];
            }
            int currentIndex = [self indexForItem:(IndexedPlayerItem *)_player.currentItem];
            if (currentIndex >= 0) _index = currentIndex;
            [self updateEndAction];
            return;
        }
    }
    _index = index;

    // Update the queue while keeping the currently playing item untouched.

    /* NSLog(@"before reorder: _player.items.count: ", _player.items.count); */
    /* [self dumpQueue]; */

    // First, remove all _player items except for the currently playing one (if any).
    IndexedPlayerItem *oldItem = (IndexedPlayerItem *)_player.currentItem;
    IndexedPlayerItem *existingItem = nil;
    IndexedPlayerItem *newItem = _indexedAudioSources.count > 0 ? _indexedAudioSources[_index].playerItem : nil;
    NSArray *oldPlayerItems = [NSArray arrayWithArray:_player.items];
    // In the first pass, preserve the old and new items.
    // TODO: preserve as much of the treadmill as possible
    for (int i = 0; i < oldPlayerItems.count; i++) {
        if (oldPlayerItems[i] == newItem) {
            // Preserve and tag new item if it is already in the queue.
            existingItem = oldPlayerItems[i];
            //NSLog(@"Preserving existing item %d", [self indexForItem:existingItem]);
        } else if (oldPlayerItems[i] == oldItem) {
            //NSLog(@"Preserving old item %d", [self indexForItem:oldItem]);
            // Temporarily preserve old item, just to avoid jumping to
            // intermediate queue positions unnecessarily. We only want to jump
            // once to _index.
        } else {
            //NSLog(@"Removing item %d", [self indexForItem:oldPlayerItems[i]]);
            if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.remove.entry" item:oldPlayerItems[i] details:nil];
            [_player removeItem:oldPlayerItems[i]];
            if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.remove.return" item:oldPlayerItems[i] details:nil];
        }
    }
    // In the second pass, remove the old item (if different from new item).
    if (oldItem && newItem != oldItem) {
        //NSLog(@"removing old item %d", [self indexForItem:oldItem]);
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.remove.entry" item:oldItem details:nil];
        [_player removeItem:oldItem];
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.remove.return" item:oldItem details:nil];
    }

    /* NSLog(@"inter order: _player.items.count: ", _player.items.count); */
    /* [self dumpQueue]; */

    // Regenerate queue
    _enqueuedAll = NO;
    if (!existingItem || _loopMode != lmLoopOne) {
        _enqueuedAll = YES;
        BOOL include = NO;
        for (int i = 0; i < [_order count]; i++) {
            int si = [_order[i] intValue];
            if (si == _index) include = YES;
            if (include && _indexedAudioSources[si].playerItem != existingItem) {
                if (_indexedAudioSources[si].lazyLoading && _player.items.count >= TREADMILL_SIZE) {
                    // Enqueue up until the first lazy item that does not fit on the treadmill.
                    _enqueuedAll = NO;
                    break;
                }
                //NSLog(@"inserting item %d", si);
                if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
                    [self queueBoundaryAuditItem:_indexedAudioSources[si].playerItem selectSource:YES];
                    [self queueBoundaryAudit:@"native.insert.entry" item:_indexedAudioSources[si].playerItem details:nil];
                }
                [_player insertItem:_indexedAudioSources[si].playerItem afterItem:nil];
                if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.insert.return" item:_indexedAudioSources[si].playerItem details:nil];
                if (_loopMode == lmLoopOne) {
                    // We only want one item in the queue.
                    break;
                }
            }
        }
    }

    // Add next loop item if we're looping
    if (_order.count > 0) {
        if (_loopMode == lmLoopAll && _enqueuedAll) {
            int si = [_order[0] intValue];
            //NSLog(@"### add loop item:%d", si);
            if (!_indexedAudioSources[si].playerItem2) {
                [_indexedAudioSources[si] preparePlayerItem2];
                [self addItemObservers:_indexedAudioSources[si].playerItem2];
            }
            if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
                [self queueBoundaryAuditItem:_indexedAudioSources[si].playerItem2 selectSource:YES];
                [self queueBoundaryAudit:@"native.insert.entry" item:_indexedAudioSources[si].playerItem2 details:nil];
            }
            [_player insertItem:_indexedAudioSources[si].playerItem2 afterItem:nil];
            if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.insert.return" item:_indexedAudioSources[si].playerItem2 details:nil];
        } else if (_loopMode == lmLoopOne) {
            //NSLog(@"### add loop item:%d", _index);
            if (!_indexedAudioSources[_index].playerItem2) {
                [_indexedAudioSources[_index] preparePlayerItem2];
                [self addItemObservers:_indexedAudioSources[_index].playerItem2];
            }
            if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
                [self queueBoundaryAuditItem:_indexedAudioSources[_index].playerItem2 selectSource:YES];
                [self queueBoundaryAudit:@"native.insert.entry" item:_indexedAudioSources[_index].playerItem2 details:nil];
            }
            [_player insertItem:_indexedAudioSources[_index].playerItem2 afterItem:nil];
            if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.insert.return" item:_indexedAudioSources[_index].playerItem2 details:nil];
        }
    }

    /* NSLog(@"after reorder: _player.items.count: ", _player.items.count); */
    /* [self dumpQueue]; */

    if (_processingState != psLoading && oldItem != newItem) {
        // || !_player.currentItem.playbackLikelyToKeepUp;
        if (_player.currentItem.playbackBufferEmpty) {
            [self enterBuffering:@"enqueueFrom playbackBufferEmpty"];
        } else {
            [self leaveBuffering:@"enqueueFrom !playbackBufferEmpty"];
        }
        [self updatePosition];
    }

    [self updateEndAction];
}

- (void)updatePosition {
    _updatePosition = [self getCurrentPosition];
    _updateTime = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (void)load:(NSDictionary *)source initialPosition:(CMTime)initialPosition initialIndex:(NSNumber *)initialIndex result:(FlutterResult)result {
    AudioSource *validatedSource = nil;
    if (_readAloudFiniteLocalWavQueue) {
        if ([self isFiniteLocalWavDefinition:source]) validatedSource = [self decodeAudioSource:source];
        if (![self isFiniteLocalWavTree:validatedSource]) {
            result([FlutterError errorWithCode:@"readaloud_unsupported_source"
                message:@"Finite local WAV player requires plain local AVURLAsset file sources" details:nil]);
            return;
        }
    }
    _readAloudPendingFinalCompletion = nil;
    if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
        _queueBoundaryAuditRevision++;
        [self queueBoundaryAudit:@"load.entry" item:nil details:nil];
    }
    if (_playing) {
        [_player pause];
    }
    if (_processingState == psLoading) {
        [self abortExistingConnection:NO];
    }
    _loadResult = result;
    _processingState = psLoading;
    _index = (initialIndex != (id)[NSNull null]) ? [initialIndex intValue] : 0;
    _errorCode = (NSNumber *)[NSNull null];
    _errorMessage = (NSString *)[NSNull null];
    // Remove previous observers
    if (_indexedAudioSources) {
        for (int i = 0; i < [_indexedAudioSources count]; i++) {
            [self removeItemObservers:_indexedAudioSources[i].playerItem];
            if (_indexedAudioSources[i].playerItem2) {
                [self removeItemObservers:_indexedAudioSources[i].playerItem2];
            }
        }
    }
    // Decode audio source
    if (validatedSource) {
        _audioSource = validatedSource;
    } else if (_audioSource && [@"clipping" isEqualToString:source[@"type"]]) {
        // Check if we're clipping an audio source that was previously loaded.
        UriAudioSource *child = nil;
        if ([_audioSource isKindOfClass:[ClippingAudioSource class]]) {
            ClippingAudioSource *clipper = (ClippingAudioSource *)_audioSource;
            child = clipper.audioSource;
        } else if ([_audioSource isKindOfClass:[UriAudioSource class]]) {
            child = (UriAudioSource *)_audioSource;
        }
        NSString *type = source[@"child"][@"type"];
        NSString *uri = nil;
        if ([@"progressive" isEqualToString:type] || [@"dash" isEqualToString:type] || [@"hls" isEqualToString:type]) {
            uri = source[@"child"][@"uri"];
        }
        if (child && uri && [child.uri isEqualToString:uri]) {
            ClippingAudioSource *clipper =
                [[ClippingAudioSource alloc] initWithId:source[@"id"]
                                            audioSource:child
                                                  start:source[@"start"]
                                                    end:source[@"end"]];
            clipper.playerItem.audioSource = clipper;
            if (clipper.playerItem2) {
                clipper.playerItem2.audioSource = clipper;
            }
            _audioSource = clipper;
        } else {
            _audioSource = [self decodeAudioSource:source];
        }
    } else {
        _audioSource = [self decodeAudioSource:source];
    }
    _indexedAudioSources = [[NSMutableArray alloc] init];
    [_audioSource buildSequence:_indexedAudioSources treeIndex:0];
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        IndexedAudioSource *source = _indexedAudioSources[i];
        [self addItemObservers:source.playerItem];
        source.playerItem.audioSource = source;
        if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
            [self queueBoundaryAuditItem:source.playerItem selectSource:YES];
            [self queueBoundaryAudit:@"source.bound" item:source.playerItem details:nil];
        }
    }
    [self updatePosition];
    [self updateOrder];
    // Set up an empty player
    if (!_player) {
        _player = [[AVQueuePlayer alloc] initWithItems:@[]];
        if (@available(macOS 10.12, iOS 10.0, *)) {
            _player.automaticallyWaitsToMinimizeStalling = _automaticallyWaitsToMinimizeStalling;
            // TODO: Remove these observers in dispose.
            [_player addObserver:self
                      forKeyPath:@"timeControlStatus"
                         options:NSKeyValueObservingOptionNew
                         context:nil];
        }
        if (@available(macOS 10.11, iOS 6.0, *)) {
            _player.allowsExternalPlayback = _allowsExternalPlayback;
        }
        [_player addObserver:self
                  forKeyPath:@"currentItem"
                     options:NSKeyValueObservingOptionNew
                     context:nil];
        // TODO: learn about the different ways to define weakSelf.
        //__weak __typeof__(self) weakSelf = self;
        //typeof(self) __weak weakSelf = self;
        __unsafe_unretained typeof(self) weakSelf = self;
        if (@available(macOS 10.12, iOS 10.0, *)) {}
        else {
            _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(200, 1000)
                                                                  queue:nil
                                                             usingBlock:^(CMTime time) {
                if (weakSelf->_queueBoundaryAuditEnabled) [weakSelf queueBoundaryAudit:@"position.periodic" item:nil details:nil];
                                                                 [weakSelf checkForDiscontinuity];
                                                             }
            ];
        }
    }
    // Initialise the AVQueuePlayer with items.
    [self enqueueFrom:_index];
    // Notify each IndexedAudioSource that it's been attached to the player.
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        [_indexedAudioSources[i] attach:_player initialPos:(i == _index ? initialPosition : kCMTimeInvalid)];
    }

    if (_playing) {
        _player.rate = _speed;
    }
    [_player setVolume:_volume];
    [self broadcastPlaybackEvent];

    if (_loadResult && (_indexedAudioSources.count == 0 || !_player.currentItem ||
            _player.currentItem.status == AVPlayerItemStatusReadyToPlay)) {
        _processingState = psReady;
        _loadResult(@{@"duration": @([self getDurationMicroseconds])});
        _loadResult = nil;
    } else {
        // We send result after the playerItem is ready in observeValueForKeyPath.
    }
    /* NSLog(@"load:"); */
    /* for (int i = 0; i < [_indexedAudioSources count]; i++) { */
    /*     NSLog(@"- %@", _indexedAudioSources[i].sourceId); */
    /* } */
}

- (void)updateOrder {
    _orderInv = [NSMutableArray arrayWithCapacity:[_indexedAudioSources count]];
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        [_orderInv addObject:@(0)];
    }
    if (_shuffleModeEnabled) {
        _order = [_audioSource getShuffleIndices];
    } else {
        NSMutableArray *order = [[NSMutableArray alloc] init];
        for (int i = 0; i < [_indexedAudioSources count]; i++) {
            [order addObject:@(i)];
        }
        _order = order;
    }
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        _orderInv[[_order[i] intValue]] = @(i);
    }
}

- (void)onItemStalled:(NSNotification *)notification {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"item.stalled" item:notification.object details:nil];
    //IndexedPlayerItem *playerItem = (IndexedPlayerItem *)notification.object;
    //NSLog(@"onItemStalled");
}

- (void)onFailToComplete:(NSNotification *)notification {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"item.failedToComplete" item:notification.object details:nil];
    //IndexedPlayerItem *playerItem = (IndexedPlayerItem *)notification.object;
    //NSLog(@"onFailToComplete");
}

// Opted-in finite local WAV loop-off ownership, or explicit QA diagnostic.
// AVFoundation can notify a future
// item's completion before its predecessor leaves the physical head. Neither
// notification order nor the previous logical index authorizes advancement.
// Existing native callbacks own execution; no new queue, timer or retained item.
// This path is limited to positive finite media (the local
// WAV route). A notification is not EOF evidence after same-item seek/reload.
// Use rational CMTime comparison, without rounding away the last audio sample.
- (BOOL)physicalHeadHasFiniteEOF:(IndexedPlayerItem *)head {
    IndexedAudioSource *source = head.audioSource;
    CMTime position = source.position, duration = source.duration;
    return CMTIME_IS_NUMERIC(position) && CMTIME_IS_NUMERIC(duration) &&
        CMTIME_COMPARE_INLINE(duration, >, kCMTimeZero) && CMTimeCompare(position, duration) >= 0;
}

- (void)completePendingFinalFromPhysicalHead:(IndexedPlayerItem *)head {
    if (![self usesPhysicalHeadIndex] || _loopMode != lmLoopOff || !head ||
            head != _readAloudPendingFinalCompletion || _processingState == psIdle ||
            _processingState == psLoading || _processingState == psCompleted || CMTIME_IS_VALID(_seekPos)) return;
    int headIndex = [self indexForItem:head];
    if (headIndex < 0 || [_orderInv[headIndex] intValue] + 1 != _order.count ||
            ![self physicalHeadHasFiniteEOF:head]) return;
    if (_index != headIndex) {
        _index = headIndex;
        [self updateEndAction];
    }
    _readAloudPendingFinalCompletion = nil;
    [self complete];
}

- (void)completeFromPhysicalHead:(IndexedPlayerItem *)endedPlayerItem {
    // A replacement/load or explicit seek owns position until it finishes.
    if (_processingState == psIdle || _processingState == psLoading || CMTIME_IS_VALID(_seekPos)) return;
    IndexedPlayerItem *head = (IndexedPlayerItem *)_player.currentItem;
    int headIndex = head ? [self indexForItem:head] : -1;
    int endedIndex = endedPlayerItem ? [self indexForItem:endedPlayerItem] : -1;
    if (headIndex < 0 || endedIndex < 0) return;

    if (_index != headIndex) {
        _index = headIndex;
        [self updateEndAction];
        [self broadcastPlaybackEvent];
    }
    if ([_orderInv[endedIndex] intValue] + 1 < _order.count) {
        // Preserve the ended-source rewind, including a future source that
        // finished early. The independent rewind QA flag remains explicit.
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.entry" item:endedPlayerItem details:@{@"skipped": @(_readAloudQueueSkipLoopOffRewind)}];
        if (!_readAloudQueueSkipLoopOffRewind) [endedPlayerItem.audioSource seek:kCMTimeZero];
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.return" item:endedPlayerItem details:@{@"skipped": @(_readAloudQueueSkipLoopOffRewind)}];
        _justAdvanced = YES;
    } else if (endedPlayerItem == head && _processingState != psCompleted && [self physicalHeadHasFiniteEOF:head]) {
        // A future final-item notification must not terminate the current head.
        // Loop-off's final end action pauses, retaining this item at real EOF.
        _readAloudPendingFinalCompletion = nil;
        [self complete];
    } else if (_processingState != psCompleted) {
        // Remember an early final notification without transferring ownership.
        // A later existing head/paused callback must also observe finite EOF.
        _readAloudPendingFinalCompletion = endedPlayerItem;
    }
}

- (void)onComplete:(NSNotification *)notification {
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"item.complete.entry" item:notification.object details:nil];
    //NSLog(@"onComplete");

    IndexedPlayerItem *endedPlayerItem = (IndexedPlayerItem *)notification.object;
    IndexedAudioSource *endedSource = endedPlayerItem.audioSource;

    if ([self usesPhysicalHeadIndex] && _loopMode == lmLoopOff) {
        [self completeFromPhysicalHead:endedPlayerItem];
    } else if (_loopMode == lmLoopOne) {
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.entry" item:endedPlayerItem details:@{@"skipped": @NO}];
        [endedSource seek:kCMTimeZero];
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.return" item:endedPlayerItem details:@{@"skipped": @NO}];
        _justAdvanced = YES;
    } else if (_loopMode == lmLoopAll) {
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.entry" item:endedPlayerItem details:@{@"skipped": @NO}];
        [endedSource seek:kCMTimeZero];
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.return" item:endedPlayerItem details:@{@"skipped": @NO}];
        _index = [_order[([_orderInv[_index] intValue] + 1) % _order.count] intValue];
        [self broadcastPlaybackEvent];
        _justAdvanced = YES;
    } else if ([_orderInv[_index] intValue] + 1 < [_order count]) {
        // QA experiment only: the end notification can arrive before native
        // head advancement. Production/default retains the upstream rewind.
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.entry" item:endedPlayerItem details:@{@"skipped": @(_readAloudQueueSkipLoopOffRewind)}];
        if (!_readAloudQueueSkipLoopOffRewind) [endedSource seek:kCMTimeZero];
        if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"completion.rewind.return" item:endedPlayerItem details:@{@"skipped": @(_readAloudQueueSkipLoopOffRewind)}];
        _index = [_order[([_orderInv[_index] intValue] + 1)] intValue];
        [self updateEndAction];
        [self broadcastPlaybackEvent];
        _justAdvanced = YES;
    } else {
        // reached end of playlist
        [self complete];
    }
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"item.complete.return" item:notification.object details:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {

    if (_queueBoundaryAuditEnabled) {
        BOOL itemEvent = [keyPath isEqualToString:@"status"] || [keyPath isEqualToString:@"loadedTimeRanges"] ||
            [keyPath isEqualToString:@"playbackBufferEmpty"] || [keyPath isEqualToString:@"playbackBufferFull"];
        // Include nil-current transitions and non-current item readiness before
        // the production handler's early returns. Off-main skips never query AV.
        [self queueBoundaryAudit:[@"kvo." stringByAppendingString:keyPath]
                            item:itemEvent ? object : nil details:nil];
    }

    if ([keyPath isEqualToString:@"status"]) {
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)object;
        AVPlayerItemStatus status = AVPlayerItemStatusUnknown;
        NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
        if ([statusNumber isKindOfClass:[NSNumber class]]) {
            status = statusNumber.intValue;
        }
        [playerItem.audioSource onStatusChanged:status];
        switch (status) {
            case AVPlayerItemStatusReadyToPlay: {
                if (playerItem != _player.currentItem) return;
                // Detect buffering in different ways depending on whether we're playing
                if (_playing) {
                    if (@available(macOS 10.12, iOS 10.0, *)) {
                        if (_player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
                            [self enterBuffering:@"ready to play: playing, waitingToPlay"];
                        } else {
                            [self leaveBuffering:@"ready to play: playing, !waitingToPlay"];
                        }
                        [self updatePosition];
                    } else {
                        // If this happens when we're playing, check whether buffer is confirmed
                        if (_bufferUnconfirmed && !_player.currentItem.playbackBufferFull) {
                            // Stay in bufering - XXX Test
                            [self enterBuffering:@"ready to play: playing, bufferUnconfirmed && !playbackBufferFull"];
                        } else {
                            if (_player.currentItem.playbackBufferEmpty) {
                                // !_player.currentItem.playbackLikelyToKeepUp;
                                [self enterBuffering:@"ready to play: playing, playbackBufferEmpty"];
                            } else {
                                [self leaveBuffering:@"ready to play: playing, !playbackBufferEmpty"];
                            }
                            [self updatePosition];
                        }
                    }
                } else {
                    if (_player.currentItem.playbackBufferEmpty) {
                        [self enterBuffering:@"ready to play: !playing, playbackBufferEmpty"];
                        // || !_player.currentItem.playbackLikelyToKeepUp;
                    } else {
                        [self leaveBuffering:@"ready to play: !playing, !playbackBufferEmpty"];
                    }
                    [self updatePosition];
                }
                [self broadcastPlaybackEvent];
                if (_loadResult) {
                    _loadResult(@{@"duration": @([self getDurationMicroseconds])});
                    _loadResult = nil;
                }
                break;
            }
            case AVPlayerItemStatusFailed: {
                //NSLog(@"AVPlayerItemStatusFailed on item [%d]", [self indexForItem:playerItem]);
                if (playerItem == _player.currentItem) {
                    [self sendErrorForItem:playerItem];
                }
                break;
            }
            case AVPlayerItemStatusUnknown:
                break;
        }
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"] || [keyPath isEqualToString:@"playbackBufferFull"]) {
        // Use these values to detect buffering.
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)object;
        if (playerItem != _player.currentItem) return;
        // If there's a seek in progress, these values are unreliable
        if (CMTIME_IS_VALID(_seekPos)) return;
        // Detect buffering in different ways depending on whether we're playing
        if (_playing) {
            if (@available(macOS 10.12, iOS 10.0, *)) {
                // We handle this with timeControlStatus instead.
            } else {
                if (_bufferUnconfirmed && playerItem.playbackBufferFull) {
                    _bufferUnconfirmed = NO;
                    [self leaveBuffering:@"playing, _bufferUnconfirmed && playbackBufferFull"];
                    [self updatePosition];
                    //NSLog(@"Buffering confirmed! leaving buffering");
                    [self broadcastPlaybackEvent];
                }
            }
        } else {
            if (playerItem.playbackBufferEmpty) {
                [self enterBuffering:@"!playing, playbackBufferEmpty"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
            } else if (!playerItem.playbackBufferEmpty || playerItem.playbackBufferFull) {
                [self leaveBuffering:@"!playing, !playbackBufferEmpty || playbackBufferFull"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
            }
        }
    /* } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) { */
    } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
        if (@available(macOS 10.12, iOS 10.0, *)) {
            AVPlayerTimeControlStatus status = AVPlayerTimeControlStatusPaused;
            NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
            if ([self usesPhysicalHeadIndex] && _loopMode == lmLoopOff) {
                // A delayed KVO payload cannot authorize EOF for a newer state
                // or a replaced player. Final Pause retains the current item,
                // so EOF need not produce another currentItem notification.
                if (object != _player) return;
                status = _player.timeControlStatus;
            } else if ([statusNumber isKindOfClass:[NSNumber class]]) {
                status = statusNumber.intValue;
            }
            switch (status) {
                case AVPlayerTimeControlStatusPaused:
                    if ([self usesPhysicalHeadIndex] && _loopMode == lmLoopOff) [self completePendingFinalFromPhysicalHead:(IndexedPlayerItem *)_player.currentItem];
                    break;
                case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                    //NSLog(@"AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate");
                    if (_processingState != psCompleted) {
                        [self enterBuffering:@"timeControlStatus"];
                        [self updatePosition];
                        [self broadcastPlaybackEvent];
                    } else {
                        //NSLog(@"Ignoring wait signal because we reached the end");
                    }
                    break;
                case AVPlayerTimeControlStatusPlaying:
                    [self leaveBuffering:@"timeControlStatus"];
                    [self updatePosition];
                    [self broadcastPlaybackEvent];
                    break;
            }
        }
    } else if ([keyPath isEqualToString:@"currentItem"]) {
        BOOL physicalHeadIndex = [self usesPhysicalHeadIndex] && _loopMode == lmLoopOff;
        // KVO's new value can already be obsolete when this callback runs.
        // Consume one current head snapshot; nil/retired heads own no index.
        IndexedPlayerItem *head = (IndexedPlayerItem *)_player.currentItem;
        if (!head) return;
        IndexedPlayerItem *playerItem = physicalHeadIndex ? head : (IndexedPlayerItem *)change[NSKeyValueChangeNewKey];
        int physicalIndex = physicalHeadIndex ? [self indexForItem:playerItem] : -1;
        if (physicalHeadIndex && physicalIndex < 0) return;
        BOOL physicalAdvance = physicalHeadIndex && _index != physicalIndex;
        //IndexedPlayerItem *oldPlayerItem = (IndexedPlayerItem *)change[NSKeyValueChangeOldKey];
        if (playerItem.status == AVPlayerItemStatusFailed) {
            [self sendErrorForItem:playerItem];
            return;
        } else {
            int expectedIndex = physicalHeadIndex ? physicalIndex : [self indexForItem:playerItem];
            if (_index != expectedIndex) {
                // AVQueuePlayer will sometimes skip over error items without
                // notifying this observer.
                //NSLog(@"Queue change detected. Adjusting index from %d -> %d", _index, expectedIndex);
                _index = expectedIndex;
                [self updateEndAction];
                [self broadcastPlaybackEvent];
            }
        }
        //NSLog(@"currentItem changed. _index=%d", _index);
        _bufferUnconfirmed = YES;
        if (physicalHeadIndex) [self completePendingFinalFromPhysicalHead:playerItem];
        // If we've skipped or transitioned to a new item and we're not
        // currently in the middle of a seek
        /* if (CMTIME_IS_INVALID(_seekPos) && playerItem.status == AVPlayerItemStatusReadyToPlay) { */
        /*     [self updatePosition]; */
        /*     IndexedAudioSource *source = playerItem.audioSource; */
        /*     // We should already be at position zero but for */
        /*     // ClippingAudioSource it might be off by some milliseconds so we */
        /*     // consider anything <= 100 as close enough. */
        /*     if ((int)(1000 * CMTimeGetSeconds(source.position)) > 100) { */
        /*         NSLog(@"On currentItem change, seeking back to zero"); */
        /*         BOOL shouldResumePlayback = NO; */
        /*         AVPlayerActionAtItemEnd originalEndAction = _player.actionAtItemEnd; */
        /*         if (_playing && CMTimeGetSeconds(CMTimeSubtract(source.position, source.duration)) >= 0) { */
        /*             NSLog(@"Need to pause while rewinding because we're at the end"); */
        /*             shouldResumePlayback = YES; */
        /*             _player.actionAtItemEnd = AVPlayerActionAtItemEndPause; */
        /*             [_player pause]; */
        /*         } */
        /*         [self enterBuffering:@"currentItem changed, seeking"]; */
        /*         [self updatePosition]; */
        /*         [self broadcastPlaybackEvent]; */
        /*         __weak __typeof__(self) weakSelf = self; */
        /*         [source seek:kCMTimeZero completionHandler:^(BOOL finished) { */
        /*             [weakSelf leaveBuffering:@"currentItem changed, finished seek"]; */
        /*             [weakSelf updatePosition]; */
        /*             [weakSelf broadcastPlaybackEvent]; */
        /*             if (shouldResumePlayback) { */
        /*                 weakSelf.player.actionAtItemEnd = originalEndAction; */
        /*                 // TODO: This logic is almost duplicated in seek. See if we can reuse this code. */
        /*                 weakSelf.player.rate = weakSelf.speed; */
        /*             } */
        /*         }]; */
        /*     } else { */
        /*         // Already at zero, no need to seek. */
        /*     } */
        /* } */

        if (physicalHeadIndex ? ((_justAdvanced || physicalAdvance) && _processingState != psLoading && CMTIME_IS_INVALID(_seekPos)) : _justAdvanced) {
            IndexedAudioSource *audioSource = playerItem.audioSource;
            if (_loopMode == lmLoopOne) {
                [audioSource flip];
                [self enqueueFrom:_index];
            } else if (_loopMode == lmLoopAll) {
                if (_index == [_order[0] intValue] && playerItem == audioSource.playerItem2) {
                    [audioSource flip];
                    [self enqueueFrom:_index];
                } else if (!_enqueuedAll) {
                    [self enqueueFrom:_index];
                } else {
                    [self updateEndAction];
                }
            } else if (!_enqueuedAll) {
                [self enqueueFrom:_index];
            }
            _justAdvanced = NO;
        }
    } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)object;
        if (playerItem != _player.currentItem) return;
        int pos = [self getBufferedPosition];
        if (pos != _bufferedPosition) {
            _bufferedPosition = pos;
            [self broadcastPlaybackEvent];
        }
    }
}

- (void)sendErrorForItem:(IndexedPlayerItem *)playerItem {
    [self sendError:@((int)playerItem.error.code) errorMessage:playerItem.error.localizedDescription playerItem:playerItem switchToIdle:YES];
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.removeAll.entry" item:playerItem details:nil];
    [_player removeAllItems];
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"native.removeAll.return" item:playerItem details:nil];
}

- (void)sendError:(NSNumber *)errorCode errorMessage:(NSString *)errorMessage playerItem:(IndexedPlayerItem *)playerItem switchToIdle:(BOOL)switchToIdle {
    //NSLog(@"sendError (%@) %@", errorCode, errorMessage);
    FlutterError *flutterError = [FlutterError errorWithCode:[NSString stringWithFormat:@"%@", errorCode]
                                                     message:errorMessage
                                                     details:playerItem != nil ? @{@"index": @([self indexForItem:playerItem])} : nil];
    [_eventChannel sendEvent:flutterError];
    _errorCode = errorCode;
    _errorMessage = errorMessage;
    if (switchToIdle) {
        _processingState = psIdle;
    }
    [self broadcastPlaybackEvent];
    if (_loadResult && playerItem == _player.currentItem) {
        _loadResult(flutterError);
        _loadResult = nil;
    }
}

- (void)abortExistingConnection:(BOOL)switchToIdle {
    [self sendError:@(ERROR_ABORT) errorMessage:@"Connection aborted" playerItem:nil switchToIdle:switchToIdle];
}

- (int)indexForItem:(IndexedPlayerItem *)playerItem {
    for (int i = 0; i < _indexedAudioSources.count; i++) {
        if (_indexedAudioSources[i].playerItem == playerItem || _indexedAudioSources[i].playerItem2 == playerItem) {
            return i;
        }
    }
    return -1;
}

- (void)play {
    [self play:nil];
}

- (void)play:(FlutterResult)result {
    if (_playing) {
        if (result) {
            result(@{});
        }
        return;
    }
    if (result) {
        if (_playResult) {
            //NSLog(@"INTERRUPTING PLAY");
            _playResult(@{});
        }
        _playResult = result;
    }
    _playing = YES;
    _player.rate = _speed;
    [self updatePosition];
    if (@available(macOS 10.12, iOS 10.0, *)) {}
    else {
        if (_bufferUnconfirmed && !_player.currentItem.playbackBufferFull) {
            [self enterBuffering:@"play, _bufferUnconfirmed && !playbackBufferFull"];
            [self broadcastPlaybackEvent];
        }
    }
}

- (void)pause {
    if (!_playing) return;
    _playing = NO;
    [_player pause];
    [self updatePosition];
    [self broadcastPlaybackEvent];
    if (_playResult) {
        //NSLog(@"PLAY FINISHED DUE TO PAUSE");
        _playResult(@{});
        _playResult = nil;
    }
}

- (void)complete {
    [self updatePosition];
    _processingState = psCompleted;
    [self broadcastPlaybackEvent];
    if (_playResult) {
        //NSLog(@"PLAY FINISHED DUE TO COMPLETE");
        _playResult(@{});
        _playResult = nil;
    }
}

- (void)setVolume:(float)volume {
    _volume = volume;
    if (_player) {
        [_player setVolume:volume];
    }
}

- (void)setSpeed:(float)speed {
    // NOTE: We ideally should check _player.currentItem.canPlaySlowForward and
    // canPlayFastForward, but these properties are unreliable and the official
    // documentation is unclear and contradictory.
    //
    // Source #1:
    // https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate?language=objc
    //
    //     Rates other than 0.0 and 1.0 can be used if the associated player
    //     item returns YES for the AVPlayerItem properties canPlaySlowForward
    //     or canPlayFastForward.
    //
    // Source #2:
    // https://developer.apple.com/library/archive/qa/qa1772/_index.html
    //
    //     An AVPlayerItem whose status property equals
    //     AVPlayerItemStatusReadyToPlay can be played at rates between 1.0 and
    //     2.0, inclusive, even if AVPlayerItem.canPlayFastForward is NO.
    //     AVPlayerItem.canPlayFastForward indicates whether the item can be
    //     played at rates greater than 2.0.
    //
    // But in practice, it appears that even if AVPlayerItem.canPlayFastForward
    // is NO, rates greater than 2.0 still work sometimes.
    //
    // So for now, we just let the app pass in any speed and hope for the best.
    // There is no way to reliably query whether the requested speed is
    // supported.
    _speed = speed;
    if (_playing && _player) {
        _player.rate = speed;
    }
    [self updatePosition];
}

- (void)setLoopMode:(int)loopMode {
    if (loopMode == _loopMode) return;
    _readAloudPendingFinalCompletion = nil;
    _loopMode = loopMode;
    [self enqueueFrom:_index];
}

- (void)updateEndAction {
    // Should be called in the following situations:
    // - when the audio source changes
    // - when _index changes
    // - when the loop mode changes.
    // - when the shuffle order changes. (TODO)
    // - when the shuffle mode changes.
    if (!_player) return;
    if (_audioSource && (_loopMode != lmLoopOff || ([_order count] > 0 && [_orderInv[_index] intValue] + 1 < [_order count]))) {
        _player.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;
    } else {
        _player.actionAtItemEnd = AVPlayerActionAtItemEndPause; // AVPlayerActionAtItemEndNone
    }
}

- (void)setShuffleModeEnabled:(BOOL)shuffleModeEnabled {
    //NSLog(@"setShuffleModeEnabled: %d", shuffleModeEnabled);
    _shuffleModeEnabled = shuffleModeEnabled;
    if (!_audioSource) return;

    [self updateOrder];

    [self enqueueFrom:_index];
}

- (void)setShuffleOrder:(NSDictionary *)dict {
    if (!_audioSource) return;

    [_audioSource decodeShuffleOrder:dict];

    [self updateOrder];

    [self enqueueFrom:_index];
}

- (void)dumpQueue {
    for (int i = 0; i < _player.items.count; i++) {
        IndexedPlayerItem *playerItem = (IndexedPlayerItem *)_player.items[i];
        int j = [self indexForItem:playerItem];
        NSLog(@"- %d", j);
    }
}

- (void)setAutomaticallyWaitsToMinimizeStalling:(bool)automaticallyWaitsToMinimizeStalling {
    _automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling;
    if (@available(macOS 10.12, iOS 10.0, *)) {
        if(_player) {
            _player.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling;
        }
    }
}

- (void)setCanUseNetworkResourcesForLiveStreamingWhilePaused:(BOOL)enabled {
    _loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = enabled;
    if (!_indexedAudioSources) return;
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        [_indexedAudioSources[i] applyCanUseNetworkResourcesForLiveStreamingWhilePaused];
    }
}

- (void)setPreferredPeakBitRate:(NSNumber *)preferredPeakBitRate {
    _loadControl.preferredPeakBitRate = preferredPeakBitRate;
    if (!_indexedAudioSources) return;
    for (int i = 0; i < [_indexedAudioSources count]; i++) {
        [_indexedAudioSources[i] applyPreferredPeakBitRate];
    }
}

- (void)setAllowsExternalPlayback:(BOOL)allowsExternalPlayback {
    _allowsExternalPlayback = allowsExternalPlayback;
    if (@available(macOS 10.11, iOS 6.0, *)) {
        if (_player) {
            _player.allowsExternalPlayback = allowsExternalPlayback;
        }
    }
}

- (void)seek:(CMTime)position index:(NSNumber *)newIndex completionHandler:(void (^)(BOOL))completionHandler {
    _readAloudPendingFinalCompletion = nil;
    if (_processingState == psIdle || _processingState == psLoading) {
        if (completionHandler) {
            completionHandler(NO);
        }
        return;
    }
    int index = _index;
    if (newIndex != (id)[NSNull null]) {
        index = [newIndex intValue];
    }
    if (index != _index) {
        // Jump to a new item
        /* if (_playing && index == _index + 1) { */
        /*     // Special case for jumping to the very next item */
        /*     NSLog(@"seek to next item: %d -> %d", _index, index); */
        /*     [_indexedAudioSources[_index] seek:kCMTimeZero]; */
        /*     _index = index; */
        /*     [_player advanceToNextItem]; */
        /*     [self broadcastPlaybackEvent]; */
        /* } else */
        {
            // Jump to a distant item
            //NSLog(@"seek# jump to distant item: %d -> %d", _index, index);
            if (_playing) {
                [_player pause];
            }
            [_indexedAudioSources[_index] seek:kCMTimeZero];
            // The "currentItem" key observer will respect that a seek is already in progress
            _seekPos = position;
            [self updatePosition];
            [self enqueueFrom:index];
            IndexedAudioSource *source = _indexedAudioSources[_index];
            if (abs((int)(1000 * CMTimeGetSeconds(CMTimeSubtract(source.position, position)))) > 100) {
                [self enterBuffering:@"seek to index"];
                [self updatePosition];
                [self broadcastPlaybackEvent];
                [source seek:position completionHandler:^(BOOL finished) {
                    if (@available(macOS 10.12, iOS 10.0, *)) {
                        if (self->_playing) {
                            // Handled by timeControlStatus
                        } else {
                            if (self->_bufferUnconfirmed && !self->_player.currentItem.playbackBufferFull) {
                                // Stay in buffering
                            } else if (source.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                                [self leaveBuffering:@"seek to index finished, (!bufferUnconfirmed || playbackBufferFull) && ready to play"];
                                [self updatePosition];
                                [self broadcastPlaybackEvent];
                            }
                        }
                    } else {
                        if (self->_bufferUnconfirmed && !self->_player.currentItem.playbackBufferFull) {
                            // Stay in buffering
                        } else if (source.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                            [self leaveBuffering:@"seek to index finished, (!bufferUnconfirmed || playbackBufferFull) && ready to play"];
                            [self updatePosition];
                            [self broadcastPlaybackEvent];
                        }
                    }
                    if (self->_playing) {
                        self->_player.rate = self->_speed;
                    }
                    self->_seekPos = kCMTimeInvalid;
                    [self broadcastPlaybackEvent];
                    if (completionHandler) {
                        completionHandler(finished);
                    }
                }];
            } else {
                _seekPos = kCMTimeInvalid;
                if (_playing) {
                    if (@available(iOS 10.0, *)) {
                        // NOTE: Re-enable this line only after figuring out
                        // how to detect buffering when buffered audio is not
                        // immediately available.
                        //[_player playImmediatelyAtRate:_speed];
                        _player.rate = _speed;
                    } else {
                        _player.rate = _speed;
                    }
                }
                [self broadcastPlaybackEvent];
                completionHandler(YES);
            }
        }
    } else {
        // Seek within an item
        if (_playing) {
            [_player pause];
        }
        _seekPos = position;
        //NSLog(@"seek. enter buffering. pos = %d", (int)(1000*CMTimeGetSeconds(_indexedAudioSources[_index].position)));
        // TODO: Move this into a separate method so it can also
        // be used in skip.
        [self enterBuffering:@"seek"];
        [self updatePosition];
        [self broadcastPlaybackEvent];
        [_indexedAudioSources[_index] seek:position completionHandler:^(BOOL finished) {
            [self updatePosition];
            if (self->_playing) {
                // If playing, buffering will be detected either by:
                // 1. checkForDiscontinuity
                // 2. timeControlStatus
                if (@available(iOS 10.0, *)) {
                    // NOTE: Re-enable this line only after figuring out how to
                    // detect buffering when buffered audio is not immediately
                    // available.
                    //[_player playImmediatelyAtRate:_speed];
                    self->_player.rate = self->_speed;
                } else {
                    self->_player.rate = self->_speed;
                }
            } else {
                // If not playing, there is no reliable way to detect
                // when buffering has completed, so we use
                // !playbackBufferEmpty. Although this always seems to
                // be full even right after a seek.
                if (self->_player.currentItem.playbackBufferEmpty) {
                    [self enterBuffering:@"seek finished, playbackBufferEmpty"];
                } else {
                    [self leaveBuffering:@"seek finished, !playbackBufferEmpty"];
                }
                [self updatePosition];
                if (self->_processingState != psBuffering) {
                    [self broadcastPlaybackEvent];
                }
            }
            self->_seekPos = kCMTimeInvalid;
            [self broadcastPlaybackEvent];
            if (completionHandler) {
                completionHandler(finished);
            }
        }];
    }
}

- (void)dispose:(BOOL)calledFromDealloc {
    _readAloudPendingFinalCompletion = nil;
    if (_queueBoundaryAuditEnabled && [self queueBoundaryAuditCanRecord]) {
        [self queueBoundaryAudit:@"dispose.entry" item:nil details:@{@"calledFromDealloc": @(calledFromDealloc)}];
        _queueBoundaryAuditDisposed = YES;
    }
    if (!_player) return;
    if (_processingState != psIdle) {
        [_player pause];

        [self updatePosition];
        if (!calledFromDealloc) {
            [self broadcastPlaybackEvent];
        }
        if (_playResult) {
            //NSLog(@"PLAY FINISHED DUE TO STOP");
            _playResult(@{});
            _playResult = nil;
        }

        _processingState = psIdle;
        // If used just before destroying the current FlutterEngine, this will result in:
        // NSInternalInconsistencyException: 'Sending a message before the FlutterEngine has been run.'
        //[self broadcastPlaybackEvent];
    }
    if (_timeObserver) {
        [_player removeTimeObserver:_timeObserver];
        _timeObserver = 0;
    }
    if (_indexedAudioSources) {
        for (int i = 0; i < [_indexedAudioSources count]; i++) {
            [self removeItemObservers:_indexedAudioSources[i].playerItem];
            if (_indexedAudioSources[i].playerItem2) {
                [self removeItemObservers:_indexedAudioSources[i].playerItem2];
            }
        }
        _indexedAudioSources = nil;
    }
    _audioSource = nil;
    if (_player) {
        [_player removeObserver:self forKeyPath:@"currentItem"];
        if (@available(macOS 10.12, iOS 10.0, *)) {
            [_player removeObserver:self forKeyPath:@"timeControlStatus"];
        }
        _player = nil;
    }
    // Untested:
    [_eventChannel dispose];
    [_dataEventChannel dispose];
    [_methodChannel setMethodCallHandler:nil];
    if (_queueBoundaryAuditEnabled) [self queueBoundaryAudit:@"dispose.return" item:nil details:nil];
}

@end
