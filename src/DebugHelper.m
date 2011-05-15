//
//  DebugHelper.m
//  hydna-objc
//

#import "DebugHelper.h"

void debugPrint(NSString *c, NSUInteger ch, NSString *msg)
{
	NSLog(@"HydnaDebug: %10s: %8x: %@", [ c UTF8String ], ch, msg);
}