
#import "CameraUploadOperation.h"
#import "MEGASdkManager.h"
#import "NSFileManager+MNZCategory.h"
#import "NSString+MNZCategory.h"
#import "TransferSessionManager.h"
#import "AssetUploadInfo.h"
#import "CameraUploadRecordManager.h"
#import "CameraUploadManager.h"
#import "CameraUploadRequestDelegate.h"
#import "FileEncrypter.h"
#import "NSURL+CameraUpload.h"
#import "MEGAConstants.h"
@import Photos;

@interface CameraUploadOperation ()

@property (strong, nonatomic, nullable) MEGASdk *attributesDataSDK;

@end

@implementation CameraUploadOperation

#pragma mark - initializers

- (instancetype)initWithUploadInfo:(AssetUploadInfo *)uploadInfo {
    self = [super init];
    
    if (self) {
        _uploadInfo = uploadInfo;
    }
    
    return self;
}

#pragma mark - properties

- (MEGASdk *)attributesDataSDK {
    if (_attributesDataSDK == nil) {
        _attributesDataSDK = [MEGASdkManager createMEGASdk];
    }
    
    return _attributesDataSDK;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@ %@", NSStringFromClass(self.class), [NSString mnz_fileNameWithDate:self.uploadInfo.asset.creationDate], self.uploadInfo.fileName];
}

#pragma mark - start operation

- (void)start {
    [super start];

    [self beginBackgroundTaskWithExpirationHandler:^{
        [self finishOperationWithStatus:CameraAssetUploadStatusFailed shouldUploadNextAsset:NO];
    }];
    
    MEGALogDebug(@"[Camera Upload] %@ starts processing", self);
    [CameraUploadRecordManager.shared updateRecordOfLocalIdentifier:self.uploadInfo.asset.localIdentifier withStatus:CameraAssetUploadStatusProcessing error:nil];
    
    self.uploadInfo.directoryURL = [self URLForAssetFolder];
}

#pragma mark - data processing

- (void)copyToParentNodeIfNeededForMatchingNode:(MEGANode *)node {
    if (node == nil) {
        return;
    }
    
    if (node.parentHandle != self.uploadInfo.parentNode.handle) {
        [[MEGASdkManager sharedMEGASdk] copyNode:node newParent:self.uploadInfo.parentNode];
    }
}

- (MEGANode *)nodeForOriginalFingerprint:(NSString *)fingerprint {
    MEGANode *matchingNode = [MEGASdkManager.sharedMEGASdk nodeForFingerprint:fingerprint];
    if (matchingNode == nil) {
        MEGANodeList *nodeList = [MEGASdkManager.sharedMEGASdk nodesForOriginalFingerprint:fingerprint];
        if (nodeList.size.integerValue > 0) {
            matchingNode = [self firstNodeInNodeList:nodeList hasParentNode:self.uploadInfo.parentNode];
            if (matchingNode == nil) {
                matchingNode = [nodeList nodeAtIndex:0];
            }
        }
    }
    
    return matchingNode;
}

- (MEGANode *)firstNodeInNodeList:(MEGANodeList *)nodeList hasParentNode:(MEGANode *)parent {
    for (NSInteger i = 0; i < nodeList.size.integerValue; i++) {
        MEGANode *node = [nodeList nodeAtIndex:i];
        if (node.parentHandle == parent.handle) {
            return node;
        }
    }
    
    return nil;
}

- (NSURL *)URLForAssetFolder {
    NSURL *assetDirectoryURL = [NSURL mnz_assetDirectoryURLForLocalIdentifier:self.uploadInfo.asset.localIdentifier];
    [NSFileManager.defaultManager removeItemIfExistsAtURL:assetDirectoryURL];
    [[NSFileManager defaultManager] createDirectoryAtURL:assetDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return assetDirectoryURL;
}

- (void)createThumbnailAndPreviewFiles {
    [self.attributesDataSDK createThumbnail:self.uploadInfo.fileURL.path destinatioPath:self.uploadInfo.thumbnailURL.path];
    [self.attributesDataSDK createPreview:self.uploadInfo.fileURL.path destinatioPath:self.uploadInfo.previewURL.path];
    self.attributesDataSDK = nil;
}

#pragma mark - upload task

- (void)encryptsFile {
    [self createThumbnailAndPreviewFiles];
    
    self.uploadInfo.mediaUpload = [MEGASdkManager.sharedMEGASdk backgroundMediaUpload];
    FileEncrypter *encrypter = [[FileEncrypter alloc] initWithMediaUpload:self.uploadInfo.mediaUpload outputDirectoryURL:self.uploadInfo.encryptionDirectoryURL shouldTruncateInputFile:YES];
    [encrypter encryptFileAtURL:self.uploadInfo.fileURL completion:^(BOOL success, unsigned long long fileSize, NSDictionary<NSString *,NSURL *> * _Nonnull chunkURLsKeyedByUploadSuffix, NSError * _Nonnull error) {
        if (success) {
            MEGALogDebug(@"[Camera Upload] %@ file encryption is done with chunks %@", self, chunkURLsKeyedByUploadSuffix);
            self.uploadInfo.fileSize = fileSize;
            self.uploadInfo.encryptedChunkURLsKeyedByUploadSuffix = chunkURLsKeyedByUploadSuffix;
            [self requestUploadURL];
        } else {
            MEGALogDebug(@"[Camera Upload] %@ error when to encrypt file %@", self, error);
            [self finishOperationWithStatus:CameraAssetUploadStatusFailed shouldUploadNextAsset:YES];
            return;
        }
    }];
}

- (void)requestUploadURL {
    [[MEGASdkManager sharedMEGASdk] requestBackgroundUploadURLWithFileSize:self.uploadInfo.fileSize mediaUpload:self.uploadInfo.mediaUpload delegate:[[CameraUploadRequestDelegate alloc] initWithCompletion:^(MEGARequest * _Nonnull request, MEGAError * _Nonnull error) {
        if (error.type) {
            MEGALogError(@"[Camera Upload] %@ requests upload url failed with error type: %ld", self, error.type);
            [self finishOperationWithStatus:CameraAssetUploadStatusFailed shouldUploadNextAsset:YES];
        } else {
            self.uploadInfo.uploadURLString = [self.uploadInfo.mediaUpload uploadURLString];
            MEGALogDebug(@"[Camera Upload] %@ got upload URL %@", self, self.uploadInfo.uploadURLString);
            [self archiveUploadInfoDataForBackgroundTransfer];
            [self uploadEncryptedChunksToServer];
        }
    }]];
}

- (void)uploadEncryptedChunksToServer {
    for (NSString *uploadSuffix in self.uploadInfo.encryptedChunkURLsKeyedByUploadSuffix.allKeys) {
        NSURL *serverURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", self.uploadInfo.uploadURLString, uploadSuffix]];
        NSURL *chunkURL = self.uploadInfo.encryptedChunkURLsKeyedByUploadSuffix[uploadSuffix];
        if ([NSFileManager.defaultManager fileExistsAtPath:chunkURL.path]) {
            NSURLSessionUploadTask *uploadTask;
            if (self.uploadInfo.asset.mediaType == PHAssetMediaTypeVideo) {
                uploadTask = [TransferSessionManager.shared videoUploadTaskWithURL:serverURL fromFile:chunkURL completion:nil];
            } else {
                uploadTask = [[TransferSessionManager shared] photoUploadTaskWithURL:serverURL fromFile:chunkURL completion:nil];
            }
            uploadTask.taskDescription = self.uploadInfo.asset.localIdentifier;
            [uploadTask resume];
            MEGALogDebug(@"[Camera Upload] %@ starts uploading chunk %@", self, chunkURL.lastPathComponent);
        } else {
            MEGALogDebug(@"[Camera Upload] %@ chunk doesn't exist at %@", self, chunkURL);
            [self finishOperationWithStatus:CameraAssetUploadStatusFailed shouldUploadNextAsset:YES];
            return;
        }
    }
    
    [self finishOperationWithStatus:CameraAssetUploadStatusUploading shouldUploadNextAsset:YES];
}

#pragma mark - archive upload info

- (void)archiveUploadInfoDataForBackgroundTransfer {
    MEGALogDebug(@"[Camera Upload] %@ start archiving upload info", self);
    NSURL *archivedURL = [NSURL mnz_archivedURLForLocalIdentifier:self.uploadInfo.asset.localIdentifier];
    [NSKeyedArchiver archiveRootObject:self.uploadInfo toFile:archivedURL.path];
}

#pragma mark - finish operation

- (void)finishOperationWithStatus:(NSString *)status shouldUploadNextAsset:(BOOL)uploadNextAsset {
    [self finishOperation];
    
    MEGALogDebug(@"[Camera Upload] %@ finishes with status: %@", self, status);
    [CameraUploadRecordManager.shared updateRecordOfLocalIdentifier:self.uploadInfo.asset.localIdentifier withStatus:status error:nil];
    
    if (![status isEqualToString:CameraAssetUploadStatusUploading]) {
        [[NSFileManager defaultManager] removeItemAtURL:self.uploadInfo.directoryURL error:nil];
    }
    
    if ([status isEqualToString:CameraAssetUploadStatusDone]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:MEGACameraUploadAssetUploadDoneNotificationName object:nil];
        });
    }
    
    if (uploadNextAsset) {
        [[CameraUploadManager shared] uploadNextForAsset:self.uploadInfo.asset];
    }
}

@end
