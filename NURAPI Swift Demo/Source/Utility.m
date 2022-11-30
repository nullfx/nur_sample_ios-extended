//
//  Utility.m
//  NURAPI Swift Demo
//
//  Created by Steve on 11/30/22.
//  Copyright © 2022 Jan Ekholm. All rights reserved.
//

#import "Utility.h"
@import CoreFoundation;

@implementation Utility

/**
 Gets inventory stream data

 @param data the data
 @return the inventory data
 */
+ (NurInventoryStreamData) getInventoryStreamData: (LPVOID)data {
    const NurInventoryStreamData *inventoryStream = (const NurInventoryStreamData *)data;
    return *inventoryStream;
}

/**
 Gets IO change data

 @param data the data
 @return an io change data type
 */
+ (NurIOChangeData) getIOChangeData: (LPVOID)data {
    const NurIOChangeData *iocData = (const NurIOChangeData *)data;
    return *iocData;
}

/**
 Gets the barcode status by checking the first byte of the byte array

 @param data event data
 @return returns an `NUR_ERRORCODES` enum value
 */
+ (UInt8) getBarcodeStatus: (LPVOID)data {
    BYTE *dataPtr = (BYTE*)data;
    return UINT8_C(dataPtr[0]);
}

/**
 Gets the barcode values by removing the first byte of the byte array and returning the result as a String

 @param data The event data
 @param length Length of the event data
 @return A string containing the scanned barcode value
 */
+ (NSString*) getBarcodeValue: (LPVOID) data length:(int)length {
    NSString *barcode = [[NSString alloc] initWithBytes: data + 1 length: length - 1 encoding:NSASCIIStringEncoding];
    barcode = [barcode stringByTrimmingCharactersInSet: [ NSCharacterSet newlineCharacterSet ] ];
    return barcode;
}

+ (NurTraceTagData) getTraceTagData:(LPVOID)data {
    return *((NurTraceTagData*)data);
}

+ (NSData*) getEpcTrace: (NurTraceTagData)tag {
    int len = tag.epcLen > 0 ? tag.epcLen : NUR_MAX_EPC_LENGTH;
    return [NSData dataWithBytes:tag.epc length:len];
}

+ (NSData*) getEpcTagID: (NurTagData)tag {
    return [NSData dataWithBytes:tag.epc length:tag.epcLen];
}

+ (NSData*) getEpcTagIDEx: (NurTagDataEx)tag {
    return [NSData dataWithBytes:tag.epc length:tag.epcLen];
}

+ (NSData*) getEpcDataEx: (NurTagDataEx)tag {
    return [NSData dataWithBytes:tag.data length:tag.dataLen];
}
@end
