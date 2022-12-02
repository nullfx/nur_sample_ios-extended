//
//  Utility.h
//  NURAPI Swift Demo
//
//  Created by Steve on 11/30/22.
//

#import <Foundation/Foundation.h>
#import <NurAPIBluetooth/Bluetooth.h>
#import <NurApiBluetooth/NURAPI.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct NUR_INVENTORYSTREAM_DATA NurInventoryStreamData;
typedef struct NUR_IOCHANGE_DATA NurIOChangeData;
typedef struct NUR_TRACETAG_DATA NurTraceTagData;
typedef struct NUR_TAG_DATA NurTagData;
typedef struct NUR_TAG_DATA_EX NurTagDataEx;

@interface Utility : NSObject
+ (NurInventoryStreamData) getInventoryStreamData: (LPVOID)data;
+ (NurIOChangeData) getIOChangeData: (LPVOID)data;
+ (BYTE) getBarcodeStatus: (LPVOID)data;
+ (NSString*) getBarcodeValue: (LPVOID) data length:(int)length;
+ (NurTraceTagData) getTraceTagData: (LPVOID) data;
+ (NSData*) getEpcTrace: (NurTraceTagData)tag;
+ (NSData*) getEpcTagID: (NurTagData)tag;
+ (NSData*) getEpcTagIDEx: (NurTagDataEx)tag;
+ (NSData*) getEpcDataEx: (NurTagDataEx)tag;
@end

NS_ASSUME_NONNULL_END
