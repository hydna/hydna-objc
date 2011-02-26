//
//  Stream.m
//  hydna-objc
//

#import "Stream.h"

@interface Stream ()

/**
 *  Internally close the stream.
 */
- (void) internalClose;

@end


@implementation Stream

- (id) init
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_host = @"";
    self->m_port = 7010;
    self->m_addr = 1;
    self->m_socket = nil;
    self->m_connected = NO;
    self->m_pendingClose = NO;
    self->m_readable = NO;
    self->m_writable = NO;
    self->m_emitable = NO;
    self->m_error = @"";
    self->m_openRequest = nil;
    
    self->m_dataQueue = [[ NSMutableArray alloc ] init ];
    self->m_signalQueue = [[ NSMutableArray alloc ] init ];
    
    self->m_dataMutex = [[ NSLock alloc ] init ];
    self->m_signalMutex = [[ NSLock alloc ] init ];
    
    return self;
}

- (void) dealloc
{
    [ m_dataQueue release ];
    [ m_dataMutex release ];
    [ m_signalQueue release ];
    [ m_signalMutex release ];
    
    [ super dealloc ];
}

- (BOOL) isConnected
{
    [ m_connectMutex lock ];
    BOOL result = m_connected;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) isReadable
{
    [ m_connectMutex lock ];
    BOOL result = m_connected && m_readable;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) isWritable
{
    [ m_connectMutex lock ];
    BOOL result = m_connected && m_writable;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) hasSignalSupport
{
    [ m_connectMutex lock ];
    BOOL result = m_connected && m_emitable;
    [ m_connectMutex unlock ];
    return result;
}

- (NSUInteger) getAddr
{
    [ m_connectMutex lock ];
    NSUInteger result = m_addr;
    [ m_connectMutex unlock ];
    return result;
}

- (void) connect:(NSString *)expr mode:(NSUInteger)mode token:(NSData *)token
{
    Packet* packet;
    OpenRequest* request;
    
    [ m_connectMutex lock ];
    if (m_socket) {
        [ m_connectMutex unlock ];
        [NSException raise:@"Error" format:@"Already connected"];
    }
    [ m_connectMutex unlock ];
    
    if (mode == 0x04 || mode < READ || mode > READWRITE_EMIT) {
        [NSException raise:@"Error" format:@"Invalid stream mode"];
    }
    
    if (!expr) {
        [NSException raise:@"Error" format:@"No address to connect to"];
    }
    
    m_mode = mode;
    
    m_readable = ((m_mode & READ) == READ);
    m_writable = ((m_mode & WRITE) == WRITE);
    m_emitable = ((m_mode & EMIT) == EMIT);
    
    NSString *host = expr;
    NSUInteger port = 7010;
    NSUInteger addr = 1;
    NSString *tokens = @"";
    NSRange pos;
    
    pos = [ host rangeOfString:@"?" ];
    if (pos.length != 0) {
        tokens = [ host substringFromIndex:pos.location + 1];
        host = [ host substringToIndex:pos.location ];
    }
    
    pos = [ host rangeOfString:@"/x" ];
    if (pos.length != 0) {
        unsigned int addri;
        NSString* addrs = [ host substringFromIndex:pos.location + 2];
        host = [ host substringToIndex:pos.location ];
        
        BOOL result = [[NSScanner scannerWithString:addrs] scanHexInt:&addri];
        
        if (!result) {
            [NSException raise:@"Error" format:@"Could not read the address \"%@\"", addrs];
        } else {
            addr = addri;
        }

    } else {
        pos = [ host rangeOfString:@"/" ];
        if (pos.length != 0) {
            addr = [[ host substringFromIndex:pos.location + 1] integerValue];
            host = [ host substringToIndex:pos.location ];
        }
    }
    
    pos = [ host rangeOfString:@":" ];
    if (pos.length != 0) {
        port = [[ host substringFromIndex:pos.location + 1] integerValue];
        host = [ host substringToIndex:pos.location ];
    }
    
    m_host = host;
    m_port = port;
    m_addr = addr;
    
    m_socket = [ExtSocket getSocketWithHost:m_host port:m_port];
    
    [ m_socket allocStream ];
    
    if (token || tokens == @"") {
        packet = [[ Packet alloc ] initWithAddr:m_addr op:OPEN flag:mode payload:token];
    } else {
        packet = [[ Packet alloc ] initWithAddr:m_addr op:OPEN flag:mode payload:[ tokens dataUsingEncoding:NSUTF8StringEncoding]];
    }

    request = [[ OpenRequest alloc ] initWith:self addr:m_addr packet:packet ];
    
    if (m_error != @"") {
        [ m_error release ];
    }
    
    m_error = @"";
    
    if (![ m_socket requestOpen:request ]) {
        [ self checkForStreamError ];
        [NSException raise:@"Error" format:@"Stream already open"];
    }
    
    m_openRequest = request;
}

- (void) writeBytes:(NSData *)data priority:(NSUInteger)priority
{
    BOOL result;
    
    [ m_connectMutex lock ];
    if (!m_connected || !m_socket) {
        [ m_connectMutex unlock ];
        [ self checkForStreamError ];
        [NSException raise:@"IOError" format:@"Stream is not conected" ];
    }
    [ m_connectMutex unlock ];
    
    if ((m_mode & WRITE) != WRITE) {
        [NSException raise:@"Error" format:@"Stream is not writable" ];
    }
    
    if (priority > 3 || priority == 0) {
        [NSException raise:@"RangeError" format:@"Priority must be between 1-3" ];
    }
    
    Packet* packet = [[ Packet alloc ] initWithAddr:m_addr op:DATA flag:priority payload:data];
    
    [ m_connectMutex lock ];
    ExtSocket *socket = m_socket;
    [ m_connectMutex unlock ];
    result = [ socket writeBytes:packet ];
    
    if (!result) {
        [ self checkForStreamError ];
    }
}

- (void) writeBytes:(NSData *)data
{
    [ self writeBytes:data priority:1 ];
}

- (void) writeString:(NSString *)string
{
    [ self writeBytes:[string dataUsingEncoding:NSUTF8StringEncoding] ];
}

- (void) emitBytes:(NSData *)data type:(NSUInteger)type
{
    BOOL result;
    
    [ m_connectMutex lock ];
    if (!m_connected || !m_socket) {
        [ m_connectMutex unlock ];
        [ self checkForStreamError ];
        [NSException raise:@"IOError" format:@"Stream is not connected"];
    }
    [ m_connectMutex unlock ];
    
    if ((m_mode & EMIT) != EMIT) {
        [NSException raise:@"Error" format:@"You do not have permission to send signals" ];
    }
    
    Packet* packet = [[ Packet alloc ] initWithAddr:m_addr op:SIGNAL flag:type payload:data ];
    
    [ m_connectMutex lock ];
    ExtSocket *socket = m_socket;
    [ m_connectMutex unlock ];
    result = [ socket writeBytes:packet ];
    
    if (!result) {
        [ self checkForStreamError ];
    }
}

- (void) emitBytes:(NSData *)data
{
    [ self emitBytes:data type:0 ];
}

- (void) emitString:(NSString *)string type:(NSUInteger)type
{
    [ self emitBytes:[string dataUsingEncoding:NSUTF8StringEncoding] type:type ];
}

- (void) emitString:(NSString *)string
{
    [ self emitBytes:[string dataUsingEncoding:NSUTF8StringEncoding] ];
}

- (void) close
{
    [ m_connectMutex lock ];
    if (!m_socket || m_pendingClose) {
        [ m_connectMutex unlock ];
        return;
    }
    
    if (m_openRequest) {
        if ([ m_socket cancelOpen:m_openRequest ]) {
            m_openRequest = nil;
            [ m_connectMutex unlock ];
            
            [ self destroy:@"" ];
        } else {
            m_pendingClose = YES;
            [ m_connectMutex unlock ];
        }
    } else {
        [ m_connectMutex unlock ];
        [ self internalClose ];
    }
}

- (void) openSuccess:(NSUInteger)respaddr
{
    [ m_connectMutex lock ];
    m_addr = respaddr;
    m_connected = YES;
    m_openRequest = nil;
    
    if (m_pendingClose) {
        [ m_connectMutex unlock ];
        [ self internalClose ];
    } else {
        [ m_connectMutex unlock ];
    }

}

- (void) checkForStreamError
{
    [ m_connectMutex lock ];
    if (m_error != @"") {
        [ m_connectMutex unlock ];
        [NSException raise:@"StreamError" format:@"%@", m_error];
    } else {
        [ m_connectMutex unlock ];
    }
}

- (void) destroy:(NSString*)error
{
    [ m_connectMutex lock ];
    
    m_pendingClose = NO;
    m_writable = NO;
    m_readable = NO;
    
    if (m_socket) {
        [ m_socket deallocStream:m_addr ];
    }
    
    m_connected = NO;
    m_addr = 0;
    m_openRequest = nil;
    m_socket = nil;
    m_error = [ error copy ];
    
    [ m_connectMutex unlock ];
}

- (void) internalClose
{
    [ m_connectMutex lock ];
    if (m_socket && m_connected) {
        [ m_connectMutex unlock ];
#ifdef HYDNADEBUG
        NSLog(@"Stream: Sending close signal");
#endif
        Packet* packet = [[ Packet alloc ] initWithAddr:m_addr op:SIGNAL flag:SIG_END payload:nil ];
        [ m_connectMutex lock ];
        ExtSocket *socket = m_socket;
        [ m_connectMutex unlock ];
        [ socket writeBytes:packet ];
    }
    
    NSString* error = @"";
    [ self destroy:error ];
}

- (void) addData:(StreamData*)data
{
    [ m_dataMutex lock ];
    [ m_dataQueue addObject:data ];
    [ m_dataMutex unlock ];
}

- (StreamData*) popData
{
    
    if ([ self isDataEmpty ])
        return nil;
    
    [ m_dataMutex lock ];
    
    StreamData* result = [ m_dataQueue objectAtIndex:0 ];
    [ m_dataQueue removeObjectAtIndex:0 ];
    
    [ m_dataMutex unlock ];
    return result;    
}

- (BOOL) isDataEmpty
{
    [ m_dataMutex lock ];
    BOOL result = [ m_dataQueue count ] == 0;
    [ m_dataMutex unlock ];
    return result;
}

- (void) addSignal:(StreamSignal*)signal
{
    [ m_signalMutex lock ];
    [ m_signalQueue addObject:signal ];
    [ m_signalMutex unlock ];
}

- (StreamSignal*) popSignal
{
    
    if ([ self isSignalEmpty ])
        return nil;
    
    [ m_signalMutex lock ];
    
    StreamSignal* result = [ m_signalQueue objectAtIndex:0 ];
    [ m_signalQueue removeObjectAtIndex:0 ];
    
    [ m_signalMutex unlock ];
    return result;
}

- (BOOL) isSignalEmpty
{
    [ m_signalMutex lock ];
    BOOL result = [ m_signalQueue count ] == 0;
    [ m_signalMutex unlock ];
    return result;
}

@end
