//
//  BDHost.h
//  Pods
//
//  Created by Isak Wiström on 2/18/14.
//
//

#import <Foundation/Foundation.h>

@interface HYHost : NSObject

+ (NSString *)addressForHostname:(NSString *)hostname;
+ (NSArray *)addressesForHostname:(NSString *)hostname;
+ (NSString *)hostnameForAddress:(NSString *)address;
+ (NSArray *)hostnamesForAddress:(NSString *)address;
+ (NSArray *)ipAddresses;
+ (NSArray *)ethernetAddresses;

@end
