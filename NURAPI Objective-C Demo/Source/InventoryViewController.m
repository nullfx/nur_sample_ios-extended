

#import "InventoryViewController.h"
#import "AudioPlayer.h"
#import "TagManager.h"
#import "TagViewController.h"
#import "AverageBuffer.h"

@interface InventoryViewController ()

@property (nonatomic, strong) dispatch_queue_t dispatchQueue;
@property (nonatomic, strong) dispatch_queue_t audioDispatchQueue;
@property (nonatomic, strong) NSTimer *        timer;
@property (nonatomic, strong) NSDate *         startTime;
@property (nonatomic, strong) AverageBuffer *  averageBuffer;
@property (nonatomic, assign) unsigned int     totalTagsRead;
@property (nonatomic, assign) double           tagsPerSecond;
@property (nonatomic, assign) double           averageTagsPerSecond;
@property (nonatomic, assign) double           maxTagsPerSecond;
@property (nonatomic, assign) unsigned int     inventoryRoundsDone;
@property (nonatomic, assign) NSUInteger       lastRoundUniqueTags;
@property (nonatomic, assign) NSTimeInterval   elapsedSeconds;

@end


#define TAGS_PER_SEC_OVERTIME 2.0

@implementation InventoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // clear all statistics
    [self clearData];

    // set up the queue used to async any NURAPI calls
    self.dispatchQueue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0 );
    self.audioDispatchQueue = dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_LOW, 0 );

    // initially the share button is hidden, nothing to share
    self.shareButton.enabled = NO;
}


- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // register for bluetooth events
    [[Bluetooth sharedInstance] registerDelegate:self];
}


- (void) viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    // we no longer need bluetooth events
    [[Bluetooth sharedInstance] deregisterDelegate:self];

    // make sure no stream is running when we leave the view
    if ( [Bluetooth sharedInstance].currentReader ) {
        dispatch_async(self.dispatchQueue, ^{
            [self stopStream];
        } );
    }
}


- (void) clearData {
    self.averageBuffer = [[AverageBuffer alloc] initWithMaxSize:1000 maxAge:TAGS_PER_SEC_OVERTIME];
    self.totalTagsRead = 0;
    self.tagsPerSecond = 0;
    self.averageTagsPerSecond = 0;
    self.maxTagsPerSecond = 0;
    self.inventoryRoundsDone = 0;
    self.elapsedSeconds = 0;
    self.lastRoundUniqueTags = 0;
}


- (IBAction)shareInventory:(UIBarButtonItem *)sender {
    NSLog( @"in" );

    NSString * content = @"";

    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];

    [[TagManager sharedInstance] lock];

    // create a CSV string with one tag per line
    for ( Tag * tag in [TagManager sharedInstance].tags ) {
        content = [content stringByAppendingFormat:@"%@,%@,%@,%d\n",
                   [dateFormatter stringFromDate:tag.firstFound],
                   [dateFormatter stringFromDate:tag.lastFound],
                   tag.hex,
                   (int)tag.scaledRssi];
    }

    [[TagManager sharedInstance] unlock];

    // save to a temporary file
    NSString * filename = [NSString stringWithFormat:@"Inventory %@.csv", [dateFormatter stringFromDate:[NSDate date]]];
    NSURL *tmpDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileURL = [tmpDirURL URLByAppendingPathComponent:filename];

    NSError * error = nil;
    [content writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if ( error != nil ) {
        // failed to save the content to a temporary file
        NSLog( @"failed to save CSV file: %@", error.localizedDescription );
        return;
    }

    NSLog( @"saved CSV to: %@", fileURL );

    // set up the activity controller for sharing a single URL
    NSArray* sharedObjects = [NSArray arrayWithObjects:fileURL, nil];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc]
                                                        initWithActivityItems:sharedObjects applicationActivities:nil];

    // when the activity is completed delete the temporary file
    activityViewController.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
        NSLog(@"activity: %@ - finished flag: %d", activityType, completed);
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];

        // show an error if there was one
        if ( activityError != nil ) {
            UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error Sharing CSV File", nil)
                                                                            message:activityError.localizedDescription
                                                                     preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"Ok", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction * action) {
                                           // nothing special to do right now
                                       }];


            [alert addAction:okButton];
            [self presentViewController:alert animated:YES completion:nil];
        }
    };

    [self presentViewController:activityViewController animated:true completion:nil];
}


- (IBAction)toggleInventory {
    // if we do not have a current reader then we're coming here before having connected one. Don't do any NurAPI calls
    // in that case
    if ( ! [Bluetooth sharedInstance].currentReader ) {
        // prompt the user to connect a reader
        UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", nil)
                                                                        message:NSLocalizedString(@"No RFID reader connected!", nil)
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                          actionWithTitle:NSLocalizedString(@"Ok", nil)
                          style:UIAlertActionStyleDefault
                          handler:^(UIAlertAction * action) {
                              // nothing special to do right now
                          }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // kill any old timer
    if ( self.timer ) {
        [self.timer invalidate];
        self.timer = nil;
    }

    dispatch_async(self.dispatchQueue, ^{
        if ( NurApiIsInventoryStreamRunning( [Bluetooth sharedInstance].nurapiHandle ) ) {
            [self stopStream];
        }
        else {
            [self startStream];
        }
    } );
}


- (void) startStream {
    NSLog( @"starting inventory stream" );

    // default scanning parameters
    int rounds = 0;
    int q = 0;
    int session = 0;

    int error = NurApiStartInventoryStream( [Bluetooth sharedInstance].nurapiHandle, rounds, q, session );

    // show the error or update the button label on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        if ( error != NUR_NO_ERROR ) {
            NSLog( @"failed to start inventory stream" );
            [self showErrorMessage:error];
            return;
        }

        // clear all statistics data as we now started again
        [self clearData];

        self.inventoryButton.titleLabel.text = NSLocalizedString(@"Stop", nil);

        // no sharing while we're doing an inventory
        self.shareButton.enabled = NO;

        // start a timer that updates the elapsed time
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateLabels) userInfo:nil repeats:YES];
        self.startTime = [NSDate date];

        /**
         * Set up a background task for playing "beep" sounds as long as we're running an inventory stream.
         * Unique tags will trigger a beep and more tags give more urgent beeps.
         **/
        if ( [AudioPlayer sharedInstance].soundsEnabled ) {
            dispatch_async( self.audioDispatchQueue, ^(void) {
                while ( self.timer ) {
                    NSTimeInterval sleepTime = 0.01;

                    // if we have unique tags then play a sound and sleep as long as the sound plays
                    if ( self.lastRoundUniqueTags > 0 ) {
                        sleepTime = 100 - self.lastRoundUniqueTags;

                        // sleep at least 40 ms
                        if (sleepTime < 40) {
                            sleepTime = 40;
                        }

                        sleepTime /= 1000.0;

                        // play the real sound
                        [[AudioPlayer sharedInstance] playSound:kBlep40ms];
                    }
                    
                    [NSThread sleepForTimeInterval:sleepTime];
                }
            } );
        }
    } );
}


- (void) stopStream {
    // precautions
    if ( ! NurApiIsInventoryStreamRunning( [Bluetooth sharedInstance].nurapiHandle ) ) {
        return;
    }

    // stop stream
    NSLog( @"stopping inventory stream" );

    int error = NurApiStopInventoryStream( [Bluetooth sharedInstance].nurapiHandle );

    // show the error or update the button label on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        if ( error != NUR_NO_ERROR ) {
            NSLog( @"failed to stop inventory stream" );
            [self showErrorMessage:error];
            return;
        }

        self.inventoryButton.titleLabel.text = NSLocalizedString(@"Start", nil);
        self.startTime = nil;

        if ( self.timer ) {
            [self.timer invalidate];
            self.timer = nil;
        }

        // do we have any tags?
        if ( [TagManager sharedInstance].tags.count > 0 ) {
            NSLog( @"enabling sharing button" );
            self.shareButton.enabled = YES;
        }
    } );
}


- (void) continueStream {
    NSLog( @"continuing stream" );

    // default scanning parameters
    int rounds = 0;
    int q = 0;
    int session = 0;

    int error = NurApiStartInventoryStream( [Bluetooth sharedInstance].nurapiHandle, rounds, q, session );

    // show the error or update the button label on the main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        if ( error != NUR_NO_ERROR ) {
            NSLog( @"failed to start inventory stream" );
            [self showErrorMessage:error];
            return;
        }
    } );
}


- (IBAction)clearInventory {
    // simply clear all the tags
    [[TagManager sharedInstance] clear];
    [self.tableView reloadData];

    // and all statistics
    [self clearData];

    // clear all labels
    self.tagsLabel.text = @"0";
    self.elapsedTimeLabel.text = NSLocalizedString(@"unique tags in 0 seconds", nil);
    self.averageTagsPerSecondLabel.text = @"0";
    self.tagsPerSecondLabel.text = @"0";
    self.maxTagsPerSecondLabel.text = @"0";
}


- (void) updateLabels {
    // if we have a timer running then update the elapsed seconds. if not we use the last value
/*    if ( self.startTime ) {
        self.elapsedSeconds = -[self.startTime timeIntervalSinceNow];
    }*/

    // found tags
    self.tagsLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[TagManager sharedInstance].tags.count];

    self.elapsedTimeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"unique tags in %.1f seconds", nil), self.elapsedSeconds];
    self.tagsPerSecondLabel.text = [NSString stringWithFormat:@"%.1f", self.tagsPerSecond];
    self.averageTagsPerSecondLabel.text = [NSString stringWithFormat:@"%.1f", self.averageTagsPerSecond];
    self.maxTagsPerSecondLabel.text = [NSString stringWithFormat:@"%.1f", self.maxTagsPerSecond];
}


- (void) tagsFound:(NSArray *)tags added:(int)tagsAdded {
    // do we need to update the table?
    if ( tags.count > 0 ) {
        [self.tableView reloadData];
    }

    [self.averageBuffer add:tagsAdded];

    self.totalTagsRead += tagsAdded;

    self.tagsPerSecond = self.averageBuffer.sumValue / TAGS_PER_SEC_OVERTIME;

    // the shown elapsed time is only incremented when tags are found
    if ( tags.count > 0 ) {
        self.elapsedSeconds = -[self.startTime timeIntervalSinceNow];
    }

    // TODO: is this the above "stopping elapsed seconds" or a real time since the start (as below)?
    NSTimeInterval elapsedSeconds = -[self.startTime timeIntervalSinceNow];

    if ( elapsedSeconds > 1 ) {
        self.averageTagsPerSecond = self.totalTagsRead / elapsedSeconds;
    }
    else {
        self.averageTagsPerSecond = self.tagsPerSecond;
    }

    if ( self.tagsPerSecond > self.maxTagsPerSecond ) {
        self.maxTagsPerSecond = self.tagsPerSecond;
    }

    NSLog( @"added tags: %lu, total: %lu", (unsigned long)tags.count, (unsigned long)[TagManager sharedInstance].tags.count );
}


- (void) showErrorMessage:(int)error {
    // extract the NURAPI error
    char buffer[256];
    NurApiGetErrorMessage( error, buffer, 256 );
    NSString * message = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];

    NSLog( @"NURAPI error: %@", message );

    // show in an alert view
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", nil)
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"Ok", nil)
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * action) {
                                   // nothing special to do right now
                               }];


    [alert addAction:okButton];
    [self presentViewController:alert animated:YES completion:nil];
}


- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // stop the stream first, no reasont to run the stream behind the scenes
    [self stopStream];

    TagViewController * destination = [segue destinationViewController];
    NSIndexPath *indexPath = [sender isKindOfClass:[NSIndexPath class]] ? (NSIndexPath*)sender : [self.tableView indexPathForSelectedRow];

    [[TagManager sharedInstance] lock];
    destination.tag = [TagManager sharedInstance].tags[ indexPath.row ];
    [[TagManager sharedInstance] unlock];

    destination.rounds = self.inventoryRoundsDone;
    NSLog( @"rounds: %d", self.inventoryRoundsDone );
}



//******************************************************************************************
#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [TagManager sharedInstance].tags.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell" forIndexPath:indexPath];

    // get the associated tag
    [[TagManager sharedInstance] lock];
    Tag * tag = [TagManager sharedInstance].tags[ indexPath.row ];
    [[TagManager sharedInstance] unlock];

    NSString * hex = tag.hex;
    cell.textLabel.text = hex.length == 0 ? NSLocalizedString(@"<empty tag>", nil) : hex;

    return cell;
}


//******************************************************************************************
#pragma mark - Table view delegate

- (void) tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    [self performSegueWithIdentifier:@"ShowTagSegue" sender:indexPath];
}


//*****************************************************************************************************************
#pragma mark - Bluetooth delegate

- (void) notificationReceived:(DWORD)timestamp type:(int)type data:(LPVOID)data length:(int)length {
    switch ( type ) {
        case NUR_NOTIFICATION_INVENTORYSTREAM: {
            const struct NUR_INVENTORYSTREAM_DATA *inventoryStream = (const struct NUR_INVENTORYSTREAM_DATA *)data;
            NSLog( @"tag data from inventory stream, tags added: %d", inventoryStream->tagsAdded);

            self.inventoryRoundsDone += inventoryStream->roundsDone;

            int tagCount;
            int error = NurApiGetTagCount( [Bluetooth sharedInstance].nurapiHandle, &tagCount );
            if (error != NUR_NO_ERROR) {
                // failed to fetch tag count
                NSLog( @"failed to fetch tag count" );
                tagCount = 0;
            }

            NSMutableArray * newTags = [NSMutableArray new];
            TagManager * tm = [TagManager sharedInstance];

            // fetch all new tags
            for ( int index = 0; index < tagCount; ++index ) {
                Tag * tag = [tm getTag:index];
                if ( tag ) {
                    BOOL isTagNew = [tm addTag:tag];

                    // play a short blip if the tag was new
                    if ( isTagNew ) {
                        [newTags addObject:tag];
                        NSLog( @"found new tag: %@", tag );
                    }
                }
            }

            // clear the tags
            NurApiClearTags( [Bluetooth sharedInstance].nurapiHandle );

            // did the stream stop by itself? it will stop after 25 seconds or so, but keep it running
            if ( inventoryStream->stopped ) {
                [self continueStream];
            }

            // save the number of unique tags for the audio thread
            self.lastRoundUniqueTags = newTags.count;

            // run on the main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [self tagsFound:newTags added:inventoryStream->tagsAdded];
            });
        }
            break;

            // trigger pressed or released?
        case NUR_NOTIFICATION_IOCHANGE: {
            struct NUR_IOCHANGE_DATA *iocData = (struct NUR_IOCHANGE_DATA *)data;
            if (iocData->source == NUR_ACC_TRIGGER_SOURCE) {
                NSLog( @"trigger changed, dir: %d", iocData->dir );
                if (iocData->dir == 0) {
                    [self toggleInventory];
                }
            }
        }
            break;

        default:
            break;
    }
}


@end
