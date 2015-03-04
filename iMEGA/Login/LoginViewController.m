/**
 * @file LoginViewController.m
 * @brief View controller that allows to login in your MEGA account
 *
 * (c) 2013-2014 by Mega Limited, Auckland, New Zealand
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

#import "LoginViewController.h"
#import "CloudDriveTableViewController.h"
#import "SVProgressHUD.h"
#import "SSKeychain.h"
#import "Helper.h"
#import "MainTabBarController.h"
#import "BrowserViewController.h"
#import "CameraUploads.h"
#import "MEGAReachabilityManager.h"

@interface LoginViewController () <MEGATransferDelegate, UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UIView *credentialsView;
@property (weak, nonatomic) IBOutlet UITextField *emailTextField;
@property (weak, nonatomic) IBOutlet UITextField *passwordTextField;

@property (weak, nonatomic) IBOutlet UIButton *loginButton;

@end

@implementation LoginViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.loginButton.layer.cornerRadius = 6;
    self.loginButton.layer.masksToBounds = YES;
    
    self.credentialsView.backgroundColor = [megaLightGray colorWithAlphaComponent:.25f];
    self.credentialsView.layer.borderWidth = 2.0f;
    self.credentialsView.layer.borderColor =[megaLightGray CGColor];
    self.credentialsView.layer.cornerRadius = 6;
    self.credentialsView.layer.masksToBounds = YES;
    
    [self.emailTextField becomeFirstResponder];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:NO];
}

#pragma mark - Private methods

- (IBAction)tapLogin:(id)sender {
    if (![MEGAReachabilityManager isReachable]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Problema de conexión" message:@"Compruba tu conexión a internet" delegate:nil cancelButtonTitle:@"ok" otherButtonTitles:nil, nil];
        [alert show];
    } else if ([self validateForm]) {
        NSOperationQueue *operationQueue = [NSOperationQueue new];
        
        NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self
                                                                                selector:@selector(generateKeys)
                                                                                  object:nil];
        
        [operationQueue addOperation:operation];
    }
    
}

- (void)generateKeys {
    NSString *privateKey = [[MEGASdkManager sharedMEGASdk] base64pwkeyForPassword:self.passwordTextField.text];
    NSString *publicKey  = [[MEGASdkManager sharedMEGASdk] hashForBase64pwkey:privateKey email:self.emailTextField.text];
    
    [[MEGASdkManager sharedMEGASdk] fastLoginWithEmail:self.emailTextField.text stringHash:publicKey base64pwKey:privateKey delegate:self];
}

- (BOOL)validateForm {
    if (![self validateEmail:self.emailTextField.text]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"emailInvalidFormat", @"Enter a valid email")];
        [self.emailTextField becomeFirstResponder];
        return NO;
    } else if (![self validatePassword:self.passwordTextField.text]) {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"passwordInvalidFormat", @"Enter a valid password")];
        [self.passwordTextField becomeFirstResponder];
        return NO;
    }
    return YES;
}

- (BOOL)validatePassword:(NSString *)password {
    if (password.length == 0) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)validateEmail:(NSString *)email {
    NSString *emailRegex =
    @"(?:[a-z0-9!#$%\\&'*+/=?\\^_`{|}~-]+(?:\\.[a-z0-9!#$%\\&'*+/=?\\^_`{|}"
    @"~-]+)*|\"(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21\\x23-\\x5b\\x5d-\\"
    @"x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])*\")@(?:(?:[a-z0-9](?:[a-"
    @"z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\\[(?:(?:25[0-5"
    @"]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-"
    @"9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21"
    @"-\\x5a\\x53-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])+)\\])";
    NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES[c] %@", emailRegex];
    
    return [emailTest evaluateWithObject:email];
    
}

- (void)checkLoginOption {
    
    switch (self.loginOption) {
        case 1: { //IMPORT
            if ([self.node type] == MEGANodeTypeFile) {
                UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Cloud" bundle:nil];
                UINavigationController *navigationController = [storyboard instantiateViewControllerWithIdentifier:@"moveNodeNav"];
                [[[[[UIApplication sharedApplication] delegate] window] rootViewController] presentViewController:navigationController animated:YES completion:nil];
                
                BrowserViewController *browserVC = navigationController.viewControllers.firstObject;
                browserVC.parentNode = [[MEGASdkManager sharedMEGASdk] rootNode];
                browserVC.selectedNodesArray = [NSArray arrayWithObject:self.node];
                
                [browserVC setIsPublicNode:YES];
            }
            
            break;
        }
            
        case 2: { //DOWNLOAD
            if (![self checkFreeSize]) {
                return;
            }
            
            if ([self.node type] == MEGANodeTypeFile) {
                [Helper downloadNode:self.node folder:@"" folderLink:NO];
            }
            
            if ([self.node type] == MEGANodeTypeFolder) {
                NSString *folderName = [[[MEGASdkManager sharedMEGASdkFolder] nameToLocal:[self.node name]] stringByAppendingString:@"/"];
                NSString *folderPath = [[Helper pathForOffline] stringByAppendingString:folderName];
                
                if ([Helper createOfflineFolder:folderName folderPath:folderPath]) {
                    [Helper downloadNodesOnFolder:folderPath parentNode:self.node folderLink:YES];
                }
            }
            break;
        }
            
        default:
            break;
    }
}

- (BOOL)checkFreeSize {
    NSNumber *nodeSizeNumber;
    if ([self.node type] == MEGANodeTypeFile) {
        nodeSizeNumber = [self.node size];
    }
    if ([self.node type] == MEGANodeTypeFolder) {
        nodeSizeNumber = [[MEGASdkManager sharedMEGASdk] sizeForNode:self.node];
    }
    NSNumber *freeSizeNumber = [[[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil] objectForKey:NSFileSystemFreeSize];
    if ([freeSizeNumber longLongValue] < [nodeSizeNumber longLongValue]) {
        UIAlertView *alertView;
        if ([self.node type] == MEGANodeTypeFile) {
            alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"fileTooBig", @"You need more free space")
                                                   message:NSLocalizedString(@"fileTooBigMessage", @"The file you are trying to download is bigger than the avaliable memory.")
                                                  delegate:self
                                         cancelButtonTitle:NSLocalizedString(@"ok", @"OK")
                                         otherButtonTitles:nil];
        }
        if ([self.node type] == MEGANodeTypeFolder) {
            alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"folderTooBig", @"You need more free space")
                                                   message:NSLocalizedString(@"folderTooBigMessage", @"The file you are trying to download is bigger than the avaliable memory.")
                                                  delegate:self
                                         cancelButtonTitle:NSLocalizedString(@"ok", @"OK")
                                         otherButtonTitles:nil];
        }
        
        [alertView show];
        return NO;
    }
    return YES;
}


#pragma mark - Dismiss keyboard

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

#pragma mark - UITextFieldDelegate

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    
    switch ([textField tag]) {
        case 0:
            [self.passwordTextField becomeFirstResponder];
            break;
            
        case 1:
            [self.passwordTextField resignFirstResponder];
            break;
            
        default:
            break;
    }
    
    return YES;
}

#pragma mark - MEGARequestDelegate

- (void)onRequestStart:(MEGASdk *)api request:(MEGARequest *)request {
    [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeClear];
}

- (void)onRequestFinish:(MEGASdk *)api request:(MEGARequest *)request error:(MEGAError *)error {
    if ([error type]) {
        [SVProgressHUD dismiss];
        switch ([error type]) {
            case MEGAErrorTypeApiEArgs:
            case MEGAErrorTypeApiENoent: {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"error", @"Error")
                                                                message:NSLocalizedString(@"invalidMailOrPassword", @"Email or password invalid.")
                                                               delegate:self
                                                      cancelButtonTitle:NSLocalizedString(@"ok", @"OK")
                                                      otherButtonTitles:nil];
                [alert show];
                break;
            }
                
            default:
                break;
        }
        return;
    }
    
    switch ([request type]) {
        case MEGARequestTypeLogin: {
            NSString *session = [[MEGASdkManager sharedMEGASdk] dumpSession];
            [SSKeychain setPassword:session forService:@"MEGA" account:@"session"];
            [self removeFromParentViewController];
            [api fetchNodesWithDelegate:self];
            break;
        }
            
        case MEGARequestTypeFetchNodes: {
            [SVProgressHUD dismiss];
            
            UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
            MainTabBarController *mainTBC = [storyboard instantiateViewControllerWithIdentifier:@"TabBarControllerID"];
            [[[[UIApplication sharedApplication] delegate] window] setRootViewController:mainTBC];
            
            [[CameraUploads syncManager] setTabBarController:mainTBC];
//            [[CameraUploads syncManager] getAllAssetsForUpload];
            
            [self checkLoginOption];
            
            break;
        }
            
        default:
            break;
    }
}

- (void)onRequestUpdate:(MEGASdk *)api request:(MEGARequest *)request {
    if ([request type] == MEGARequestTypeFetchNodes){
        float progress = [[request transferredBytes] floatValue] / [[request totalBytes] floatValue];
        if (progress > 0 && progress <0.99) {
            [SVProgressHUD showProgress:progress status:NSLocalizedString(@"fetchingNodes", @"Fetching nodes")];
        } else if (progress > 0.99 || progress < 0) {
            [SVProgressHUD showProgress:1 status:NSLocalizedString(@"preparingNodes", @"Preparing nodes")];
        }
    }
}

- (void)onRequestTemporaryError:(MEGASdk *)api request:(MEGARequest *)request error:(MEGAError *)error {
}

@end