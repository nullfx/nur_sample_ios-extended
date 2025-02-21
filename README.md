# Sample NURAPI applications for iOS

## Updates from main Nordic ID Sample
This fork contains a minor modification to the swift demo project.  The main sample shows how to perform standard inventory.  It obtains the tag EPC, this demo demonstrates how to call the InventoryEX which unlike most other devices Nordic ID will provide you with the tag data containing EPC along with either the tag's TID (which this sample shows) or some portion of the tags USER data in one pass (pretty nice actually all things considered).  While the one pass inventory is limited to small secondary tag banks (like TID or small user data blocks) its nice to get everything in one scan, vs having to query tags one at a time after the fact IMO.

The demo can be changed from TID to USER data by changing the `NUR_INVEX_FILTER` bank from `NUR_BANK_TID` to `NUR_BANK_USER` and switching the 4th parameter in `NurApiInventoryRead` to the `NUR_BANK_USER` constant as well.

## NurAPI Bluetooth framework

The framework provides an interface that works as a bridge between the NurAPI and the iOS Bluetooth stack.
It is mainly responsible for providing a mechanism for NurAPI to communicate with the ``CoreBluetooth`` framework 
in iOS as well as relaying events from NurAPI to the application. It also provides a simpler API to scan for 
and connect to RFID devices. 

The ``NurAPIBluetooth`` framework is accessible from both Objective-C and Swift.


## Using the framework from Objective-C

Drag the framework into an application. Add the framework to *Embedded binaries* section in the *General* tab of your app target.
Now you can import the ``<NurAPIBluetooth/Bluetooth.h>`` header:

```objectivec
#import <NurAPIBluetooth/Bluetooth.h>`
```

All functionality is accessed through a singleton method, for example:

```objectivec
[[Bluetooth sharedinstance] startScanning];
```

All results from the ``Bluetooth`` class are delivered to registered **delegates**. An application that uses the class
should have some component implement the ``BluetoothDelegate`` and register it as a delegate, for example:


```objectivec
// a class that implements the BluetoothDelegate protocol
@interface SelectReaderViewController : UIViewController <BluetoothDelegate>
...
@end

@implementation SelectReaderViewController
...

- (void)viewDidLoad {
    [super viewDidLoad];

    // register as a delegate
    [[Bluetooth sharedInstance] registerDelegate:self];
    ...
}

@end

```

See the ``BluetoothDelegate`` for all the methods that can be implemented.

When a connection to a reader is formed all communication with the device is performed through the low level
NurAPI functions. These require a handle which can be accessed from the ``nurapiHandle``property like this:

```objectivec
// start an inventory stream
int error = NurApiStartInventoryStream( [Bluetooth sharedInstance].nurapiHandle, rounds, q, session );
if ( error != NUR_NO_ERROR ) {
    // failed to start stream
}
```

Please refer to that header for more detailed instructions on how to access the available functionality. 


## Thread model

All callbacks to the ``BluetoothDelegate`` are on different threads than the main application thread. 
This means that care needs to be taken when accessing application data and the UI. All low level NurAPI calls
should also be performed on a secondary thread as some of the calls can block for a long time and deadlocks
can occur if delegate methods are called. An example that fetches the NurAPI version string:

 ```objectivec
 // a queue used to dispatch all NurAPI calls
@property (nonatomic, strong) dispatch_queue_t dispatchQueue;
...

// use the global queue with default priority
self.dispatchQueue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0 );
...
 
dispatch_async(self.dispatchQueue, ^{
    char buffer[256];
    if ( NurApiGetFileVersion( buffer, 256 ) ) {
        NSString * versionString = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];

        // set the UILabel on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            self.nurApiVersionLabel.text = [NSString stringWithFormat:@"NurAPI version: %@", versionString];
        } );
    }
    else {
        // failed to get version
        ...
    }
} );
```


## Using the framework from Swift

Drag the framework into an application. 
Add the framework to *Embedded binaries* section in the *General* tab of your app target.
In order to use the framework in Swift code the project needs a *bridging header*. The
contents of the bridging header is simply:

```objectivec
#import <NurAPIBluetooth/Bluetooth.h>`
```

Now the framework can be imported in Swift with:

```swift
import NurAPIBluetooth
```
 
Once the bridging header is in place the framework can be used just as in the Objective-C


## NURAPI Objective-C Demo
This is a demo application that shows how to use NURAPI in an Objective-C application.
To build you need the **NURAPIBluetooth** framework. Drag and drop it from Finder
into the `Frameworks` group and then add the framework to *Embedded binaries* section 
in the *General* tab of your application target.

The application builds both for the iOS simulator and real devices, but the simulator does
not have Bluetooth support. The application will start in the simulator, but the Bluetooth
subsystem will simply never be enabled.


## NURAPI Swift Demo
This is a minimal demo that shows how to use the NURAPI framework from a Swift application.
Add the framework to the project as per the Objective-C version. There is a *bridging header*
that makes the framework available to the Swift code.

Functionality wise the Swift version contains the same storyboard, but only the initial
view controller that starts the scanning and lists the found readers is implemented.


## NURApiBluetooth framework
The **NURAPIBluetooth** framework contains shared libraries for both device and simulator architectures. This
allows the same framework to be used for both simulator testing as well as deploying on devices. When an application
is submitted to the App Store the i386 simulator libraries can not be included and must be stripped away from the
build. This can be easily done with a build phase script that is executed last in the build.

The relevant script is below. It strips out all architectures that are not currently needed. If your ``Info.plist`` is in some other location adapt the path on line ``FRAMEWORK_EXECUTABLE_NAME=$(defaults read "$FRAMEWORK/Info.plist" CFBundleExecutable)``.


```bash
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

# This script loops through the frameworks embedded in the application and
# removes unused architectures.
find "$APP_PATH" -name '*.framework' -type d | while read -r FRAMEWORK
do
    FRAMEWORK_EXECUTABLE_NAME=$(defaults read "$FRAMEWORK/Info.plist" CFBundleExecutable)
    FRAMEWORK_EXECUTABLE_PATH="$FRAMEWORK/$FRAMEWORK_EXECUTABLE_NAME"
    echo "Executable is $FRAMEWORK_EXECUTABLE_PATH"

    EXTRACTED_ARCHS=()

    for ARCH in $ARCHS
    do
        echo "Extracting $ARCH from $FRAMEWORK_EXECUTABLE_NAME"
        lipo -extract "$ARCH" "$FRAMEWORK_EXECUTABLE_PATH" -o "$FRAMEWORK_EXECUTABLE_PATH-$ARCH"
        EXTRACTED_ARCHS+=("$FRAMEWORK_EXECUTABLE_PATH-$ARCH")
    done

    echo "Merging extracted architectures: ${ARCHS}"
    lipo -o "$FRAMEWORK_EXECUTABLE_PATH-merged" -create "${EXTRACTED_ARCHS[@]}"
    rm "${EXTRACTED_ARCHS[@]}"

    echo "Replacing original executable with thinned version"
    rm "$FRAMEWORK_EXECUTABLE_PATH"
    mv "$FRAMEWORK_EXECUTABLE_PATH-merged" "$FRAMEWORK_EXECUTABLE_PATH"
done
```

For more discussion and the original script, see:

http://ikennd.ac/blog/2015/02/stripping-unwanted-architectures-from-dynamic-libraries-in-xcode/

### License
All source files in this repository is provided under terms specified in [LICENSE](LICENSE) file.
