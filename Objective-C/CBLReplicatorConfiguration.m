//
//  CBLReplicatorConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLReplicatorConfiguration.h"
#import "CBLAuthenticator+Internal.h"
#import "CBLReplicator+Internal.h"
#import "CBLDatabase+Internal.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "repo_version.h"    // Generated by get_repo_version.sh at build time

@implementation CBLReplicatorConfiguration {
    BOOL _readonly;
}

@synthesize database=_database, target=_target;
@synthesize replicatorType=_replicatorType, continuous=_continuous;
@synthesize authenticator=_authenticator;
@synthesize pinnedServerCertificate=_pinnedServerCertificate;
@synthesize headers=_headers;
@synthesize documentIDs=_documentIDs, channels=_channels;
@synthesize checkpointInterval=_checkpointInterval, heartbeatInterval=_heartbeatInterval;

#if TARGET_OS_IPHONE
@synthesize allowReplicatingInBackground=_allowReplicatingInBackground;
#endif

- (instancetype) initWithDatabase: (CBLDatabase*)database
                           target: (id<CBLEndpoint>)target
{
    CBLAssertNotNil(database);
    CBLAssertNotNil(target);
    
    self = [super init];
    if (self) {
        _database = database;
        _target = target;
        _replicatorType = kCBLReplicatorTypePushAndPull;
    }
    return self;
}


- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config {
    CBLAssertNotNil(config);
    
    return [self initWithConfig: config readonly: NO];
}


- (void) setReplicatorType: (CBLReplicatorType)replicatorType {
    [self checkReadonly];
    _replicatorType = replicatorType;
}


- (void) setContinuous: (BOOL)continuous {
    [self checkReadonly];
    _continuous = continuous;
}


- (void) setAuthenticator: (CBLAuthenticator *)authenticator {
    [self checkReadonly];
    _authenticator = authenticator;
}


- (void) setPinnedServerCertificate: (SecCertificateRef)pinnedServerCertificate {
    [self checkReadonly];
    _pinnedServerCertificate = pinnedServerCertificate;
}


- (void) setHeaders: (NSDictionary<NSString *,NSString *> *)headers {
    [self checkReadonly];
    _headers = headers;
}


- (void) setDocumentIDs: (NSArray<NSString *> *)documentIDs {
    [self checkReadonly];
    _documentIDs = documentIDs;
}


- (void) setChannels: (NSArray<NSString *> *)channels {
    [self checkReadonly];
    _channels = channels;
}


#if TARGET_OS_IPHONE
- (void) setAllowReplicatingInBackground: (BOOL)allowReplicatingInBackground {
    [self checkReadonly];
    _allowReplicatingInBackground = allowReplicatingInBackground;
}
#endif

#pragma mark - Internal


- (instancetype) initWithConfig: (CBLReplicatorConfiguration*)config
                       readonly: (BOOL)readonly {
    self = [super init];
    if (self) {
        _readonly = readonly;
        _database = config.database;
        _target = config.target;
        _replicatorType = config.replicatorType;
        _continuous = config.continuous;
        _authenticator = config.authenticator;
        _pinnedServerCertificate = config.pinnedServerCertificate;
        _headers = config.headers;
        _documentIDs = config.documentIDs;
        _channels = config.channels;
#if TARGET_OS_IPHONE
        _allowReplicatingInBackground = config.allowReplicatingInBackground;
#endif
    }
    return self;
}


- (void) checkReadonly {
    if (_readonly) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"This configuration object is readonly."];
    }
}


- (NSDictionary*) effectiveOptions {
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    
    // Add authentication info if any:
    [_authenticator authenticate: options];
    
    // Add the pinned certificate if any:
    if (_pinnedServerCertificate) {
        NSData* certData = CFBridgingRelease(SecCertificateCopyData(_pinnedServerCertificate));
        options[@kC4ReplicatorOptionPinnedServerCert] = certData;
    }
    
    // User-Agent and HTTP headers:
    NSMutableDictionary* httpHeaders = [NSMutableDictionary dictionary];
    httpHeaders[@"User-Agent"] = [self.class userAgentHeader];
    if (self.headers)
        [httpHeaders addEntriesFromDictionary: self.headers];
    options[@kC4ReplicatorOptionExtraHeaders] = httpHeaders;
    
    // Filters:
    options[@kC4ReplicatorOptionDocIDs] = _documentIDs;
    options[@kC4ReplicatorOptionChannels] = _channels;
    
    // Checkpoint & heartbeat intervals (no public api now):
    if (_checkpointInterval > 0)
        options[@kC4ReplicatorCheckpointInterval] = @(_checkpointInterval);
    if (_heartbeatInterval > 0)
        options[@kC4ReplicatorHeartbeatInterval] = @(_heartbeatInterval);
    
    return options;
}


+ (NSString*) userAgentHeader {
    static NSString* sUserAgent;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_IPHONE
        UIDevice* device = [UIDevice currentDevice];
        NSString* system = [NSString stringWithFormat: @"%@ %@; %@",
                            device.systemName, device.systemVersion, device.model];
#else
        NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
        NSString* version = [NSString stringWithFormat:@"%ld.%ld.%ld",
                             v.majorVersion, v.minorVersion, v.patchVersion];
        NSString* system = [NSString stringWithFormat: @"macOS %@", version];
#endif
        NSString* platform = strcmp(CBL_PRODUCT_NAME, "CouchbaseLiteSwift") == 0 ?
        @"Swift" : @"ObjC";
        
        NSString* commit = strlen(GitCommit) > (0) ?
        [NSString stringWithFormat: @"Commit/%.8s%s", GitCommit, GitDirty] : @"NA";
        
        C4StringResult liteCoreVers = c4_getVersion();
        
        sUserAgent = [NSString stringWithFormat: @"CouchbaseLite/%s (%@; %@) Build/%d %@ LiteCore/%.*s",
                      CBL_VERSION_STRING, platform, system, CBL_BUILD_NUMBER, commit,
                      (int)liteCoreVers.size, liteCoreVers.buf];
        c4slice_free(liteCoreVers);
    });
    return sUserAgent;
}


@end
