/**
 * @file OfflineTableViewController.m
 * @brief View controller that show offline files
 *
 * (c) 2013-2015 by Mega Limited, Auckland, New Zealand
 *
 * This file is part of the MEGA SDK - Client Access Engine.
 *
 * Applications using the MEGA API must present a valid application key
 * and comply with the the rules set forth in the Terms of Service.
 *
 * The MEGA SDK is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 * @copyright Simplified (2-clause) BSD License.
 *
 * You should have received a copy of the license along with this
 * program.
 */

#import "OfflineTableViewController.h"
#import "OfflineTableViewCell.h"
#import <MediaPlayer/MediaPlayer.h>
#import "SVProgressHUD.h"
#import "Helper.h"
#import "EmptyView.h"

@interface OfflineTableViewController ()

@property (nonatomic, strong) NSMutableArray *offlineDocuments;
@property (nonatomic, strong) NSMutableArray *offlineImages;

@property (nonatomic, strong) NSString *folderPathFromOffline;

@end

@implementation OfflineTableViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (self.folderPathFromOffline == nil) {
        [self.navigationItem setTitle:NSLocalizedString(@"offline", @"Offline")];
    } else {
        [self.navigationItem setTitle:self.folderPathFromOffline];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [[MEGASdkManager sharedMEGASdk] addMEGATransferDelegate:self];
    [[MEGASdkManager sharedMEGASdk] retryPendingConnections];
    [[MEGASdkManager sharedMEGASdkFolder] addMEGATransferDelegate:self];
    [[MEGASdkManager sharedMEGASdkFolder] retryPendingConnections];
    [self reloadUI];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[MEGASdkManager sharedMEGASdk] removeMEGATransferDelegate:self];
    [[MEGASdkManager sharedMEGASdkFolder] removeMEGATransferDelegate:self];
}

#pragma mark - Private methods

- (void)reloadUI {
    
    self.offlineDocuments = [NSMutableArray new];
    self.offlineImages = [NSMutableArray new];
    
    NSString *directoryPathString = [self currentOfflinePath];
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPathString error:NULL];
    int offsetIndex = 0;
    
    if (directoryContents.count == 0) {
        [self showEmptyFolderView];
    } else {
        [self.tableView setBounces:YES];
        [self.tableView setScrollEnabled:YES];
        [self.tableView setBackgroundView:nil];
    }
    
    for (int i = 0; i < (int)[directoryContents count]; i++) {
        NSString *filePath = [directoryPathString stringByAppendingPathComponent:[directoryContents objectAtIndex:i]];
        NSString *fileName = [NSString stringWithFormat:@"%@", [directoryContents objectAtIndex:i]];
        
        if (![fileName.lowercaseString.pathExtension isEqualToString:@"mega"]) {
            
            NSMutableDictionary *tempDictionary = [NSMutableDictionary new];
            [tempDictionary setValue:fileName forKey:kMEGANode];
            [tempDictionary setValue:[NSNumber numberWithInt:offsetIndex] forKey:kIndex];
            [self.offlineDocuments addObject:tempDictionary];
            
            if (isImage(fileName.lowercaseString.pathExtension)) {
                offsetIndex++;
                MWPhoto *photo = [MWPhoto photoWithURL:[NSURL fileURLWithPath:filePath]];
                NSArray *itemNameComponentsArray = [fileName componentsSeparatedByString:@"_"];
                NSString *imageName = [itemNameComponentsArray objectAtIndex:1];
                photo.caption = [[MEGASdkManager sharedMEGASdk] localToName:imageName];
                [self.offlineImages addObject:photo];
            }
        }
    }
    
    [self.tableView reloadData];
}

- (NSString *)currentOfflinePath {
    NSString *pathString = [Helper pathForOffline];
    if (self.folderPathFromOffline != nil) {
        pathString = [Helper pathForOfflineDirectory:self.folderPathFromOffline];
    }
    return pathString;
}

- (NSString *)folderPathFromOffline:(NSString *)absolutePath folder:(NSString *)folderName {
    
    NSArray *directoryPathComponents = [absolutePath pathComponents];
    NSUInteger directoryPathComponentsCount = directoryPathComponents.count;
    
    NSString *documentDirectory = [[Helper pathForOffline] lastPathComponent];
    NSUInteger documentsDirectoryPosition = 0;
    for (NSUInteger i = 0; i < directoryPathComponentsCount; i++) {
        NSString *folderString = [directoryPathComponents objectAtIndex:i];
        if ([folderString isEqualToString:documentDirectory]) {
            documentsDirectoryPosition = i;
            break;
        }
    }
    
    NSUInteger numberOfChildFolders = (directoryPathComponentsCount - (documentsDirectoryPosition + 1));
    NSIndexSet *indexSet = [[NSIndexSet alloc] initWithIndexesInRange:NSMakeRange((documentsDirectoryPosition + 1), numberOfChildFolders)];
    NSArray *childFoldersArray = [directoryPathComponents objectsAtIndexes:indexSet];
    
    NSString *pathFromOffline = @"";
    if (childFoldersArray.count > 1) {
        for (NSString *folderString in childFoldersArray) {
            pathFromOffline = [pathFromOffline stringByAppendingString:folderString];
            pathFromOffline = [pathFromOffline stringByAppendingString:@"/"];
        }
    } else {
        pathFromOffline = folderName;
    }
    
    return pathFromOffline;
}

-(unsigned long long)sizeOfFolderAtPath:(NSString *)path {
    unsigned long long folderSize = 0;
    
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    
    for (NSString *item in directoryContents) {
        NSDictionary *attributesDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
        if ([attributesDictionary objectForKey:NSFileType] == NSFileTypeDirectory) {
            folderSize += [self sizeOfFolderAtPath:[path stringByAppendingPathComponent:item]];
        } else {
            folderSize += [[attributesDictionary objectForKey:NSFileSize] unsignedLongLongValue];
        }
    }
    
    return folderSize;
}

- (void)showEmptyFolderView {
        
    EmptyView *emptyView = [[[NSBundle mainBundle] loadNibNamed:@"EmptyView"  owner:self options: nil] firstObject];
    [emptyView.emptyImageView setImage:[UIImage imageNamed:@"emptyFolder"]];
    [emptyView.emptyLabel setText:NSLocalizedString(@"emptyFolder", @"Empty Folder")];
    
    [self.tableView setBounces:NO];
    [self.tableView setScrollEnabled:NO];
    [self.tableView setBackgroundView:emptyView];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *directoryPathString = [self currentOfflinePath];
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPathString error:nil];
    
    return directoryContents.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    OfflineTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"offlineTableViewCell" forIndexPath:indexPath];
    
    NSString *directoryPathString = [self currentOfflinePath];
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPathString error:nil];
    NSString *pathForItem = [directoryPathString stringByAppendingPathComponent:[directoryContents objectAtIndex:[indexPath row]]];
    
    NSDictionary *filePropertiesDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:pathForItem error:nil];
    
    struct tm *timeinfo;
    char buffer[80];
    time_t rawtime = [[filePropertiesDictionary valueForKey:NSFileModificationDate] timeIntervalSince1970];
    timeinfo = localtime(&rawtime);
    strftime(buffer, 80, "%d/%m/%y %H:%M", timeinfo);
    NSString *date = [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
    
    unsigned long long size;
    
    NSString *handleString;
    NSString *itemNameString = [directoryContents objectAtIndex:[indexPath row]];
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath:pathForItem isDirectory:&isDirectory];
    if (isDirectory) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [cell.imageView setImage:[Helper folderImage]];
        
        size = [self sizeOfFolderAtPath:pathForItem];
    } else {
        if ([[itemNameString pathExtension] isEqualToString:@"mega"]) {
            itemNameString = NSLocalizedString(@"downloading", nil);
        } else {
            NSArray *itemNameComponentsArray = [itemNameString componentsSeparatedByString:@"_"];
            handleString = [itemNameComponentsArray objectAtIndex:0];
            itemNameString = [itemNameComponentsArray objectAtIndex:1];
        }
        
        NSString *extension = [[itemNameString pathExtension] lowercaseString];
        NSString *fileTypeIconString = [Helper fileTypeIconForExtension:extension];
        
        if (isImage(itemNameString.lowercaseString.pathExtension)) {
            NSString *thumbnailFilePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            thumbnailFilePath = [thumbnailFilePath stringByAppendingPathComponent:@"thumbs"];
            thumbnailFilePath = [thumbnailFilePath stringByAppendingPathComponent:handleString];
            
            UIImage *thumbnailImage = [UIImage imageWithContentsOfFile:thumbnailFilePath];
            if (thumbnailImage == nil) {
                thumbnailImage = [Helper defaultPhotoImage];
            }
            [cell.imageView setImage:thumbnailImage];
        } else {
            UIImage *iconImage = [UIImage imageNamed:fileTypeIconString];
            [cell.imageView setImage:iconImage];
        }
        
        size = [[[NSFileManager defaultManager] attributesOfItemAtPath:pathForItem error:nil] fileSize];
    }
    [cell.nameLabel setText:[[MEGASdkManager sharedMEGASdk] localToName:itemNameString]];
    
    NSString *sizeString = [NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleMemory];
    NSString *sizeAndDate = [NSString stringWithFormat:@"%@ • %@", sizeString, date];
    [cell.infoLabel setText:sizeAndDate];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle==UITableViewCellEditingStyleDelete) {
        OfflineTableViewCell *cell = (OfflineTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
        NSString *selectedRowNameString = [cell.nameLabel text];
        
        NSString *directoryPathString = [self currentOfflinePath];
        NSString *itemPath = [directoryPathString stringByAppendingPathComponent:selectedRowNameString];
        
        NSError *error = nil;
        BOOL success = [ [NSFileManager defaultManager] removeItemAtPath:itemPath error:&error];
        if (!success || error) {
            [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"itemDeletingError", @"Error at deleting")];
            NSLog(@"%@", error);
            return;
        } else {
            [self.tableView reloadData];
        }
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    NSString *directoryPathString = [self currentOfflinePath];
    
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPathString error:NULL];
    NSString *selectedRowName = [directoryContents objectAtIndex:[indexPath row]];
    NSString *path = [directoryPathString stringByAppendingPathComponent:selectedRowName];
    
    BOOL isDirectory;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (isDirectory) {
        NSString *folderPathFromOffline = [self folderPathFromOffline:path folder:selectedRowName];
        
        OfflineTableViewController *offlineTVC = [self.storyboard instantiateViewControllerWithIdentifier:@"OfflineTableViewControllerID"];
        [offlineTVC setFolderPathFromOffline:folderPathFromOffline];
        [self.navigationController pushViewController:offlineTVC animated:YES];
    } else {
        if (isImage(selectedRowName.lowercaseString.pathExtension)) {
            MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
            
            browser.displayActionButton = YES;
            browser.displayNavArrows = YES;
            browser.displaySelectionButtons = NO;
            browser.zoomPhotosToFill = YES;
            browser.alwaysShowControls = NO;
            browser.enableGrid = YES;
            browser.startOnGrid = NO;
            
            // Optionally set the current visible photo before displaying
            //    [browser setCurrentPhotoIndex:1];
            
            [self.navigationController pushViewController:browser animated:YES];
            
            [browser showNextPhotoAnimated:YES];
            [browser showPreviousPhotoAnimated:YES];
            NSInteger selectedIndexPhoto = [[[self.offlineDocuments objectAtIndex:indexPath.row] objectForKey:kIndex] integerValue];
            [browser setCurrentPhotoIndex:selectedIndexPhoto];
            
        } else if (isVideo(selectedRowName.lowercaseString.pathExtension)) {
            NSString *documentDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSMutableString *filePath = [NSMutableString new];
            [filePath appendFormat:@"%@/%@", documentDirectory, selectedRowName];
            NSURL *fileURL = [NSURL fileURLWithPath:filePath];
            
            MPMoviePlayerViewController *videoPlayerView = [[MPMoviePlayerViewController alloc] initWithContentURL:fileURL];
            [self presentMoviePlayerViewControllerAnimated:videoPlayerView];
            [videoPlayerView.moviePlayer play];
        }
        
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

#pragma mark - MWPhotoBrowserDelegate

- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return self.offlineImages.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.offlineImages.count)
        return [self.offlineImages objectAtIndex:index];
    return nil;
}

#pragma mark - MEGATransferDelegate

- (void)onTransferStart:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
}

- (void)onTransferUpdate:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
}

- (void)onTransferFinish:(MEGASdk *)api transfer:(MEGATransfer *)transfer error:(MEGAError *)error {
    if ([transfer type] == MEGATransferTypeDownload) {
        [self reloadUI];
    }
}

-(void)onTransferTemporaryError:(MEGASdk *)api transfer:(MEGATransfer *)transfer error:(MEGAError *)error {
}

@end