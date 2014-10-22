//
//  RatchetingSession.m
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import "RatchetingSession.h"

#import "AliceAxolotlParameters.h"
#import "BobAxolotlParameters.h"
#import "RootKey.h"
#import "SessionState.h"
#import <HKDFKit/HKDFKit.h>
#import <25519/Curve25519.h>
#import "ChainKey.h"

@interface DHEResult : NSObject

@property (nonatomic, readonly) RootKey *rootKey;
@property (nonatomic, readonly) NSData *chainKey;

- (instancetype)initWithMasterKey:(NSData*)data;

@end

@implementation DHEResult

- (instancetype)initWithMasterKey:(NSData*)data{
    NSAssert([data length] != 32*4, @"DHE Result is expected to be the result of 4 DHEs outputting 32 bytes each");
    
    self                           = [super init];
    const char *HKDFDefaultSalt[4] = {0};
    NSData *salt                   = [NSData dataWithBytes:HKDFDefaultSalt length:sizeof(HKDFDefaultSalt)];
    NSData *info                   = [@"WhisperText" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *derivedMaterial        = [HKDFKit deriveKey:data info:info salt:salt outputSize:64];
    _rootKey                       = [[RootKey alloc] initWithData:[derivedMaterial subdataWithRange:NSMakeRange(0, 32)]];
    _chainKey                      = [derivedMaterial subdataWithRange:NSMakeRange(32, 32)];

    return self;
}

@end


@implementation RatchetingSession

+ (void)initializeSession:(SessionState*)session sessionVersion:(int)sessionVersion AliceParameters:(AliceAxolotlParameters*)parameters{
    [session setVersion:sessionVersion];
    [session setRemoteIdentityKey:parameters.theirIdentityKey];
    [session setLocalIdentityKey:parameters.ourIdentityKeyPair];

    ECKeyPair *sendingRatchetKey = [Curve25519 generateKeyPair];
    DHEResult *result            = [self DHEKeyAgreement:parameters];
    RKCK *sendingChain           = [result.rootKey createChainWithTheirEphemeral:parameters.theirRatchetKey ourEphemeral:sendingRatchetKey];

    [session addReceiverChain:parameters.theirRatchetKey chainKey:[[ChainKey alloc]initWithData:result.chainKey index:0]];
    [session setSenderChain:sendingRatchetKey chainKey:sendingChain.chainKey];
    [session setRootKey:sendingChain.rootKey];
}

+ (void)initializeSession:(SessionState*)session sessionVersion:(int)sessionVersion BobParameters:(BobAxolotlParameters*)parameters{
    
    [session setVersion:sessionVersion];
    [session setRemoteIdentityKey:parameters.theirIdentityKey];
    [session setLocalIdentityKey:parameters.ourIdentityKeyPair];
    
    DHEResult *result     = [self DHEKeyAgreement:parameters];
    
    [session setSenderChain:parameters.ourRatchetKey chainKey:[[ChainKey alloc]initWithData:result.chainKey index:0]];
    [session setRootKey:result.rootKey];
}

+ (DHEResult*)DHEKeyAgreement:(id<AxolotlParameters>)parameters{
    NSMutableData *masterKey = [NSMutableData data];
    
    [masterKey appendData:[self discontinuityBytes]];
    
    if ([parameters isKindOfClass:[AliceAxolotlParameters class]]) {
        AliceAxolotlParameters *params = (AliceAxolotlParameters*)parameters;

        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirSignedPreKey andKeyPair:params.ourIdentityKeyPair]];
        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirIdentityKey andKeyPair:params.ourBaseKey]];
        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirSignedPreKey andKeyPair:params.ourBaseKey]];
        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirOneTimePrekey andKeyPair:params.ourBaseKey]];

    } else if ([parameters isKindOfClass:[BobAxolotlParameters class]]){
        BobAxolotlParameters *params = (BobAxolotlParameters*)parameters;

        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirIdentityKey andKeyPair:params.ourSignedPrekey]];
        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirBaseKey andKeyPair:params.ourIdentityKeyPair]];
        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirBaseKey andKeyPair:params.ourSignedPrekey]];
        [masterKey appendData:[Curve25519 generateSharedSecretFromPublicKey:params.theirBaseKey andKeyPair:params.ourOneTimePrekey]];
    
    }
    
    NSLog(@"DHE MasterKey: %@", masterKey);
    
    return [[DHEResult alloc] initWithMasterKey:masterKey];
}

/**
 *  The discontinuity bytes enforce that the session initialization is different between protocol V2 and V3.
 *
 *  @return Returns 32-bytes of 0xFF
 */

+ (NSData*)discontinuityBytes{
    NSMutableData *discontinuity = [NSMutableData data];
    int8_t byte = 0xFF;
    
    for (int i = 0; i < 32; i++) {
        [discontinuity appendBytes:&byte length:sizeof(int8_t)];
    }
    return [NSData dataWithData:discontinuity];
}


@end