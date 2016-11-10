
#import "SelectReaderViewController.h"
#import "ReaderViewController.h"

@interface SelectReaderViewController ()

@property (nonatomic, strong) NSMutableDictionary * rssiMap;
@property (nonatomic, strong) UIAlertController *   alert;

@end


@implementation SelectReaderViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // map for UUID -> RRSI
    self.rssiMap = [NSMutableDictionary dictionary];
}


- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // register for bluetooth events, this can safely be called several times
    [[Bluetooth sharedInstance] registerDelegate:self];

    // can we start scanning?
    if ( [Bluetooth sharedInstance].state == CBManagerStatePoweredOn ) {
        // bluetooth is on, start scanning
        [[Bluetooth sharedInstance] startScanning];
    }

    // make sure we don't have any stale data in case this view is reshown without being recreated
    [self.tableView reloadData];
}


- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // we no longer need bluetooth events
    [[Bluetooth sharedInstance] deregisterDelegate:self];

    // clear the selection on the table. This is done automatically by a UITableViewController, but we need to
    // do it manually as we're a UIViewContoller only
    NSIndexPath * selected = [self.tableView indexPathForSelectedRow];
    if ( selected ) {
        [self.tableView deselectRowAtIndexPath:selected animated:YES];
    }
}


/******************************************************************************************
 * Table view datasource
 **/
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = [Bluetooth sharedInstance].readers.count;
    return count;
}


/******************************************************************************************
 * Table view delegate
 **/
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"ReaderCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];

    // get the associated reader
    CBPeripheral * reader = [Bluetooth sharedInstance].readers[ indexPath.row ];

    cell.textLabel.text = reader.name;

    // the detail is the RSSI
    NSNumber * rssi = self.rssiMap[ reader.identifier.UUIDString ];
    if ( rssi == nil ) {
        rssi = @0;
    }

    cell.detailTextLabel.text = [NSString stringWithFormat:@"RSSI: %@", rssi];
    return cell;
}


- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Bluetooth * bt = [Bluetooth sharedInstance];

    // get the associated reader
    CBPeripheral * reader = bt.readers[ indexPath.row ];

    // connecting to the same reader we're already connected to?
    if ( reader == bt.currentReader ) {
        NSLog( @"selected the same reader, we're done" );
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    // if we have an alert we're already connecting somewhere, don't do it twice
    if ( self.alert ) {
        return;
    }

    // show a status popup that has no ok/cancel buttons, it's shown as long as the saving takes
    self.alert = [UIAlertController alertControllerWithTitle:@"Connecting"
                                                     message:[NSString stringWithFormat:@"Connecting to reader %@", reader.name]
                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:self.alert animated:YES completion:nil];

    // stop scanning
    [bt stopScanning];

    // are we connected to a previous reader?
    if ( bt.currentReader ) {
        NSLog( @"disconnecting from previous reader: %@", bt.currentReader );
        [bt disconnectFromReader];
    }

    NSLog( @"connecting to reader: %@", reader );
    [[Bluetooth sharedInstance] connectToReader:reader];
}


/*****************************************************************************************************************
 * Bluetooth delegate callbacks
 * The callbacks do not necessaily come on the main thread, so make sure everything that touches the UI is done on
 * the main thread only.
 **/
- (void) bluetoothStateChanged:(CBCentralManagerState)state {
    dispatch_async( dispatch_get_main_queue(), ^{
        NSLog( @"bluetooth state: %ld", (long)state );

        // only scan if powered on and not already scanning
        if ( state != CBManagerStatePoweredOn || [Bluetooth sharedInstance].isScanning ) {
            return;
        }

        NSLog( @"bluetooth turned on, starting scan" );
        [[Bluetooth sharedInstance] startScanning];
    });
}


- (void) readerFound:(CBPeripheral *)reader rssi:(NSNumber *)rssi{
    dispatch_async( dispatch_get_main_queue(), ^{
        NSLog( @"reader found: %@", reader );

        // save our RSSI
        self.rssiMap[ reader.identifier.UUIDString] = rssi;

        [self.tableView reloadData];
    });
}


/*- (void) reader:(CBPeripheral *)reader rssiUpdated:(NSNumber *)rssi {
    NSLog( @"reader: %@, rssi: %@", reader, rssi );

    // save the RSSI
    self.rssiMap[ reader.identifier.UUIDString] = rssi;
    [self.tableView reloadData];
}*/


- (void) readerConnectionOk {
    // now we have a proper connection to the reader
    dispatch_async( dispatch_get_main_queue(), ^{
        NSLog( @"connection ok" );
        // first always get rid of the status popup and wait for the alert to be dismissed before we pop ourselves away
        [self.alert dismissViewControllerAnimated:YES completion:^{
            self.alert = nil;
            [self.navigationController popViewControllerAnimated:YES];
        }];
    });
}


- (void) readerConnectionFailed {
    dispatch_async( dispatch_get_main_queue(), ^{
        NSLog( @"failed to connect to reader" );

        // first always get rid of the status popup and wait for the alert to be dismissed before we pop ourselves away
        [self.alert dismissViewControllerAnimated:YES completion:^{
            self.alert = nil;
            // show in an alert view
            UIAlertController * errorAlert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                                 message:@"Failed to connect to reader"
                                                                          preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:@"Ok"
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction * action) {
                                           // nothing special to do right now
                                       }];


            [errorAlert addAction:okButton];
            [self presentViewController:errorAlert animated:YES completion:nil];
            
        }];
    } );
}

@end
