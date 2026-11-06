// DDC transport and packet helpers derived from MIT-licensed m1ddc.
// See Vendor/m1ddc/LICENSE.
@import Foundation;
@import IOKit;
#include "ioregistry.h"
#include "i2c.h"
#include "utils.h"

static void writeToStdOut(NSString *text) { fputs(text.UTF8String, stdout); }

// Function to handle the reading operation (get, max, chg)
static DDCValue readingOperation(DDCTransport *transport, DDCPacket *packet) {
    DDCValue dummyAttr = {-1, -1};

    prepareDDCRead(packet);

    IOReturn err = performDDCWriteAtChipAddress(transport->service, transport->chipAddress, packet);
    if (err) {
        writeToStdOut([NSString stringWithFormat:@"DDC communication failure: %s\n", mach_error_string(err)]);
        return dummyAttr;
    }

    DDCPacket readPacket = {};
    readPacket.inputAddr = packet->inputAddr;

    err = performDDCReadAtChipAddress(transport->service, transport->chipAddress, &readPacket);
    if (err) {
        writeToStdOut([NSString stringWithFormat:@"DDC communication failure: %s\n", mach_error_string(err)]);
        return dummyAttr;
    }

    UInt8 checksum = 0x50;
    for (int index = 0; index < 11; index++) { checksum ^= readPacket.data[index]; }
    if (readPacket.data[0] != 0x6e || readPacket.data[1] != 0x88 ||
        readPacket.data[2] != 0x02 || readPacket.data[3] != 0 ||
        readPacket.data[4] != packet->data[2] || checksum != 0) {
        writeToStdOut(@"Invalid or unsupported DDC reply\n");
        return dummyAttr;
    }
    return convertI2CtoDDC((char *)readPacket.data);
}

// Function to handle the writing operation (set, chg)
static int writingOperation(DDCTransport *transport, DDCPacket *packet, UInt16 newValue) {

    prepareDDCWrite(packet, newValue);

    IOReturn err = performDDCWriteAtChipAddress(transport->service, transport->chipAddress, packet);
    if (err) {
        writeToStdOut([NSString stringWithFormat:@"DDC communication failure: %s\n", mach_error_string(err)]);
        return 1;
    }
    return 0;
}


int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3 || !STR_EQ(argv[1], "display")) { return EXIT_FAILURE; }
        DisplayInfos displays[MAX_DISPLAYS];
        int count = getOnlineDisplayInfos(displays);
        if (STR_EQ(argv[2], "list-json")) {
            NSMutableArray *items = [NSMutableArray array];
            for (int i = 0; i < count; i++) {
                [items addObject:@{@"uuid": displays[i].uuid, @"id": @(displays[i].id)}];
            }
            NSData *json = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
            if (!json) { return EXIT_FAILURE; }
            writeToStdOut([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
            return EXIT_SUCCESS;
        }
        if (argc < 5 || !STR_EQ(argv[4], "luminance")) { return EXIT_FAILURE; }
        bool reading = STR_EQ(argv[3], "get") && argc == 5;
        bool writing = STR_EQ(argv[3], "set") && argc == 6;
        if (!reading && !writing) { return EXIT_FAILURE; }
        DisplayInfos *display = selectDisplay(displays, count, argv[2]);
        if (!display) { return EXIT_FAILURE; }
        DDCTransport transport = getDisplayDDCTransport(display);
        if (!transport.service) { return EXIT_FAILURE; }
        DDCPacket packet = createDDCPacket(LUMINANCE);
        int status = EXIT_FAILURE;
        if (reading) {
            DDCValue value = readingOperation(&transport, &packet);
            if (value.curValue >= 0) {
                printf("%d\n", value.curValue);
                status = EXIT_SUCCESS;
            }
        } else {
            char *end = NULL;
            long value = strtol(argv[5], &end, 10);
            if (end != argv[5] && *end == '\0' && value >= 0 && value <= UINT16_MAX) {
                status = writingOperation(&transport, &packet, (UInt16)value);
            }
        }
        CFRelease(transport.service);
        return status;
    }
}
