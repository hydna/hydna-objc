//
//  DebugHelper.m
//  hydna-objc
//

#import "DebugHelper.h"

void debugPrint(NSString *c, NSUInteger ch, NSString *msg)
{
    NSLog(@"HydnaDebug: %10s: %i %@", [ c UTF8String ], (int)ch, msg);
}