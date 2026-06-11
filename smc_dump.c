#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include "com.airbender.helper/SMCClient/SMC.h"

int main() {
    io_connect_t conn = SMCOpen();
    if (!conn) { printf("Failed to open SMC\n"); return 1; }
    
    SMCVal_t val;
    if (SMCReadKey(conn, "FNum", &val) == kIOReturnSuccess) {
        printf("FNum: %d\n", val.bytes[0]);
        for(int i=0; i<val.bytes[0]; i++) {
            char key[5];
            snprintf(key, 5, "F%dMd", i);
            if (SMCReadKey(conn, key, &val) == kIOReturnSuccess) {
                printf("%s found, type: %c%c%c%c\n", key, val.dataType >> 24, (val.dataType >> 16) & 0xFF, (val.dataType >> 8) & 0xFF, val.dataType & 0xFF);
            } else {
                printf("%s not found\n", key);
            }
            snprintf(key, 5, "F%dTg", i);
            if (SMCReadKey(conn, key, &val) == kIOReturnSuccess) {
                printf("%s found\n", key);
            }
        }
    }
    
    if (SMCReadKey(conn, "FS! ", &val) == kIOReturnSuccess) {
        printf("FS! found\n");
    } else {
        printf("FS! not found\n");
    }
    SMCClose(conn);
    return 0;
}
