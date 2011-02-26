//
//  StreamError.m
//  hydna-objc
//
//  Created by Emanuel Dahlberg on 2/23/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "StreamError.h"
#import "Packet.h"

@implementation StreamError

+ (NSString*) fromHandshakeError:(NSInteger)flag
{
    NSString *msg = @"";
    
    switch (flag) {
        case HANDSHAKE_UNKNOWN:
            msg = @"Unknown handshake error";
            break;
        case HANDSHAKE_SERVER_BUSY:
            msg = @"Handshake failed, server is busy";
            break;
        case HANDSHAKE_BADFORMAT:
            msg = @"Handshake failed, bad format sent by client";
            break;
        case HANDSHAKE_HOSTNAME:
            msg = @"Handshake failed, invalid hostname";
            break;
        case HANDSHAKE_PROTOCOL:
            msg = @"Handshake failed, protocol not allowed";
            break;
        case HANDSHAKE_SERVER_ERROR:
            msg = @"Handshake failed, server error";
            break;
    }
    
    return msg;
}

+ (NSString*) fromOpenError:(NSInteger)flag data:(NSString*)data
{
    NSString *msg;
    
    if (data != @"" || [ data length ] != 0) {
        msg = data;
    } else {
        switch (flag) {
            case OPEN_FAIL_NA:
                msg = @"Failed to open stream, not available";
                break;
            case OPEN_FAIL_MODE:
                msg = @"Not allowed to open stream with specified mode";
                break;
            case OPEN_FAIL_PROTOCOL:
                msg = @"Not allowed to open stream with specified protocol";
                break;
            case OPEN_FAIL_HOST:
                msg = @"Not allowed to open stream from host";
                break;
            case OPEN_FAIL_AUTH:
                msg = @"Not allowed to open stream with credentials";
                break;
            case OPEN_FAIL_SERVICE_NA:
                msg = @"Failed to open stream, service is not available";
                break;
            case OPEN_FAIL_SERVICE_ERR:
                msg = @"Failed to open stream, service error";
                break;
                
            default:
            case OPEN_FAIL_OTHER:
                msg = @"Failed to open stream, unknown error";
                break;
        }
    }
    
    return msg;
}
    
+ (NSString*) fromSigError:(NSInteger)flag data:(NSString*)data
{
    NSString *msg;
    
    if (data != @"" || [ data length ] != 0) {
        msg = data;
    } else {
        switch (flag) {
            case SIG_ERR_PROTOCOL:
                msg = @"Protocol error";
                break;
            case SIG_ERR_OPERATION:
                msg = @"Operational error";
                break;
            case SIG_ERR_LIMIT:
                msg = @"Limit error";
                break;
            case SIG_ERR_SERVER:
                msg = @"Server error";
                break;
            case SIG_ERR_VIOLATION:
                msg = @"Violation error";
                break;
                
            default:
            case SIG_ERR_OTHER:
                msg = @"Unknown error";
                break;
        }
    }
    
    return msg;
}

@end
