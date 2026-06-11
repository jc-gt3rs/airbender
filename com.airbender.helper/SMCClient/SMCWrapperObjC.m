#import "SMCWrapperObjC.h"
#import "SMC.h"

@interface SMCWrapperObjC ()
@property (nonatomic, assign) io_connect_t connection;
@end

@implementation SMCWrapperObjC

- (instancetype)init {
    return [self initWithError:nil];
}

- (nullable instancetype)initWithError:(NSError **)error {
    self = [super init];
    if (self) {
        _connection = SMCOpen();
        NSLog(@"[SMCWrapperObjC] initWithError called, connection: %d", _connection);
        if (_connection == 0) {
            if (error) *error = [NSError errorWithDomain:@"SMCErrorDomain" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Could not open connection to AppleSMC."}];
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_connection != 0) {
        SMCClose(_connection);
    }
}

- (NSInteger)fanCount {
    SMCVal_t val;
    kern_return_t result = SMCReadKey(self.connection, "FNum", &val);
    if (result != kIOReturnSuccess) {
        return -(NSInteger)self.connection;
    }
    return val.bytes[0];
}

- (double)readFloatKey:(const char *)key {
    SMCVal_t val;
    kern_return_t result = SMCReadKey(self.connection, key, &val);
    if (result != kIOReturnSuccess) {
        return 0.0;
    }
    
    if (val.dataType == SMCKeyToUInt32("fpe2")) {
        UInt16 raw = (val.bytes[0] << 8) | val.bytes[1];
        return (double)raw / 4.0;
    } else if (val.dataType == SMCKeyToUInt32("sp78")) {
        SInt16 raw = (val.bytes[0] << 8) | val.bytes[1];
        return (double)raw / 256.0;
    } else if (val.dataType == SMCKeyToUInt32("flt ")) {
        float f;
        memcpy(&f, val.bytes, sizeof(f));
        return (double)f;
    }
    
    // Fallback if unknown type, though typically it's fpe2 or flt
    return 0.0;
}

- (BOOL)writeFloatKey:(const char *)key value:(double)value error:(NSError **)error {
    // We first read the key to know what data type it expects.
    SMCVal_t readVal;
    kern_return_t readResult = SMCReadKey(self.connection, key, &readVal);
    
    SMCVal_t writeVal;
    memset(&writeVal, 0, sizeof(writeVal));
    writeVal.key = SMCKeyToUInt32(key);
    
    if (readResult == kIOReturnSuccess && readVal.dataType == SMCKeyToUInt32("flt ")) {
        writeVal.dataType = SMCKeyToUInt32("flt ");
        float f = (float)value;
        memcpy(writeVal.bytes, &f, sizeof(f));
    } else {
        // Default to fpe2
        writeVal.dataType = SMCKeyToUInt32("fpe2");
        UInt16 scaled = (UInt16)(value * 4.0);
        writeVal.bytes[0] = (scaled >> 8) & 0xFF;
        writeVal.bytes[1] = scaled & 0xFF;
    }
    
    kern_return_t result = SMCWriteKey(self.connection, writeVal);
    if (result != kIOReturnSuccess) {
        if (error) *error = [NSError errorWithDomain:@"SMCErrorDomain" code:result userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to write %s", key]}];
        return NO;
    }
    return YES;
}

- (double)fanSpeedForIndex:(NSInteger)index {
    char key[5];
    snprintf(key, sizeof(key), "F%dAc", (int)index);
    return [self readFloatKey:key];
}

- (double)fanMinSpeedForIndex:(NSInteger)index {
    char key[5];
    snprintf(key, sizeof(key), "F%dMn", (int)index);
    return [self readFloatKey:key];
}

- (double)fanMaxSpeedForIndex:(NSInteger)index {
    char key[5];
    snprintf(key, sizeof(key), "F%dMx", (int)index);
    return [self readFloatKey:key];
}

- (BOOL)setFanTargetSpeedForIndex:(NSInteger)index rpm:(double)rpm error:(NSError **)error {
    char key[5];
    snprintf(key, sizeof(key), "F%dTg", (int)index);
    return [self writeFloatKey:key value:rpm error:error];
}

- (BOOL)setManualMode:(BOOL)enabled fanCount:(NSInteger)fanCount error:(NSError **)error {
    BOOL success = NO;

    // 1. Try Apple Silicon style (F%dMd)
    for (int i = 0; i < fanCount; i++) {
        char key[5];
        snprintf(key, sizeof(key), "F%dMd", i);
        
        SMCVal_t readVal;
        if (SMCReadKey(self.connection, key, &readVal) == kIOReturnSuccess) {
            readVal.bytes[0] = enabled ? 1 : 0;
            if (SMCWriteKey(self.connection, readVal) == kIOReturnSuccess) {
                success = YES;
            }
        }
    }
    
    // 2. Try legacy Intel style (FS! )
    UInt16 mask = 0;
    if (enabled) {
        for (int i = 0; i < fanCount; i++) {
            mask |= (1 << i);
        }
    }
    
    SMCVal_t val;
    memset(&val, 0, sizeof(val));
    val.key = SMCKeyToUInt32("FS! ");
    val.dataType = SMCKeyToUInt32("ui16");
    val.bytes[0] = (mask >> 8) & 0xFF;
    val.bytes[1] = mask & 0xFF;
    
    if (SMCWriteKey(self.connection, val) == kIOReturnSuccess) {
        success = YES;
    }

    return success;
}

@end
