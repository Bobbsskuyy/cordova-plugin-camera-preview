// =============================================================================
// FILE: src/ios/CameraPreview.m
// FIXES for cordova-ios 8 compatibility:
//   1. Updated imports to use unified <Cordova/Cordova.h>
//   2. Added _activeRootView helper — avoids deprecated keyWindow & direct
//      viewController.view manipulation that breaks with iOS Scene API
//   3. Added proper VC containment lifecycle calls:
//      didMoveToParentViewController (after addChild)
//      willMoveToParentViewController:nil (before removeFromParent)
// =============================================================================

// FIX #1: Ganti 3 baris import terpisah dengan unified import
#import <Cordova/Cordova.h>
#import <GLKit/GLKit.h>
#import "CameraPreview.h"

#define TMP_IMAGE_PREFIX @"cpcp_capture_"

@implementation CameraPreview

// ─────────────────────────────────────────────────────────────────────────────
// FIX #2: Helper method — safe root view resolution untuk cordova-ios 8
// Menggantikan akses langsung ke self.viewController.view atau keyWindow
// yang bermasalah dengan iOS Scene API yang diperkenalkan cordova-ios 8
// ─────────────────────────────────────────────────────────────────────────────
- (UIView *)_activeRootView {
    UIView *rootView = self.webView;
    while (rootView.superview != nil) {
        rootView = rootView.superview;
    }
    return rootView;
}

-(void) pluginInitialize{
    // start as transparent
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor clearColor];
}

- (void) startCamera:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera already started!"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    if (command.arguments.count > 3) {
        CGFloat x = (CGFloat)[command.arguments[0] floatValue] + self.webView.frame.origin.x;
        CGFloat y = (CGFloat)[command.arguments[1] floatValue] + self.webView.frame.origin.y;
        CGFloat width = (CGFloat)[command.arguments[2] floatValue];
        CGFloat height = (CGFloat)[command.arguments[3] floatValue];
        NSString *defaultCamera = command.arguments[4];
        BOOL tapToTakePicture = (BOOL)[command.arguments[5] boolValue];
        BOOL dragEnabled = (BOOL)[command.arguments[6] boolValue];
        BOOL toBack = (BOOL)[command.arguments[7] boolValue];
        CGFloat alpha = (CGFloat)[command.arguments[8] floatValue];
        BOOL tapToFocus = (BOOL) [command.arguments[9] boolValue];
        BOOL disableExifHeaderStripping = (BOOL) [command.arguments[10] boolValue]; // ignore Android only
        self.storeToFile = (BOOL) [command.arguments[11] boolValue];

        // Create the session manager
        self.sessionManager = [[CameraSessionManager alloc] init];

        // render controller setup
        self.cameraRenderController = [[CameraRenderController alloc] init];
        self.cameraRenderController.dragEnabled = dragEnabled;
        self.cameraRenderController.tapToTakePicture = tapToTakePicture;
        self.cameraRenderController.tapToFocus = tapToFocus;
        self.cameraRenderController.sessionManager = self.sessionManager;
        self.cameraRenderController.view.frame = CGRectMake(x, y, width, height);
        self.cameraRenderController.delegate = self;

        [self.viewController addChildViewController:self.cameraRenderController];

        if (toBack) {
            // display the camera below the webview
            // make transparent
            self.webView.opaque = NO;
            self.webView.backgroundColor = [UIColor clearColor];
            self.webView.scrollView.opaque = NO;
            self.webView.scrollView.backgroundColor = [UIColor clearColor];

            // FIX #2: Gunakan _activeRootView helper
            // Menggantikan [self.viewController.view insertSubview:... atIndex:0]
            // yang tidak reliable dengan iOS Scene API di cordova-ios 8
            UIView *rootView = [self _activeRootView];
            [rootView insertSubview:self.cameraRenderController.view atIndex:0];
            [self.webView.superview bringSubviewToFront:self.webView];
        } else {
            self.cameraRenderController.view.alpha = alpha;
            [self.webView.superview insertSubview:self.cameraRenderController.view aboveSubview:self.webView];
        }

        // FIX #3: Tambahkan didMoveToParentViewController setelah addChildViewController
        // Ini required oleh iOS view controller containment API — sebelumnya missing
        [self.cameraRenderController didMoveToParentViewController:self.viewController];

        // Setup session
        self.sessionManager.delegate = self.cameraRenderController;
        [self.sessionManager setupSession:defaultCamera completion:^(BOOL started) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
        }];

    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid number of parameters"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void) stopCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"stopCamera");
    CDVPluginResult *pluginResult;

    if(self.sessionManager != nil) {
        // FIX #3: Tambahkan willMoveToParentViewController:nil sebelum removeFromParentViewController
        // Proper iOS VC containment lifecycle — sebelumnya missing, bisa menyebabkan
        // memory leak dan state yang tidak konsisten di cordova-ios 8
        [self.cameraRenderController willMoveToParentViewController:nil];
        [self.cameraRenderController.view removeFromSuperview];
        [self.cameraRenderController removeFromParentViewController];
        self.cameraRenderController = nil;
        self.sessionManager = nil;

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) hideCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"hideCamera");
    CDVPluginResult *pluginResult;

    if (self.cameraRenderController != nil) {
        [self.cameraRenderController.view setHidden:YES];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) showCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"showCamera");
    CDVPluginResult *pluginResult;

    if (self.cameraRenderController != nil) {
        [self.cameraRenderController.view setHidden:NO];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) switchCamera:(CDVInvokedUrlCommand*)command {
    NSLog(@"switchCamera");
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        [self.sessionManager switchCamera:^(BOOL switched) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
        }];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void) getSupportedFocusModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSArray * focusModes = [self.sessionManager getFocusModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:focusModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getFocusMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSString * focusMode = [self.sessionManager getFocusMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:focusMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setFocusMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    NSString * focusMode = [command.arguments objectAtIndex:0];

    if (self.sessionManager != nil) {
        [self.sessionManager setFocusMode:focusMode];
        NSString * focusMode = [self.sessionManager getFocusMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:focusMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getSupportedFlashModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSArray * flashModes = [self.sessionManager getFlashModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:flashModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getFlashMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        BOOL isTorchActive = [self.sessionManager isTorchActive];
        NSInteger flashMode = [self.sessionManager getFlashMode];
        NSString * sFlashMode;

        if (isTorchActive) {
            sFlashMode = @"torch";
        } else {
            if (flashMode == 0) {
                sFlashMode = @"off";
            } else if (flashMode == 1) {
                sFlashMode = @"on";
            } else if (flashMode == 2) {
                sFlashMode = @"auto";
            } else {
                sFlashMode = @"unsupported";
            }
        }

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:sFlashMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setFlashMode:(CDVInvokedUrlCommand*)command {
    NSLog(@"Flash Mode");
    NSString *errMsg;
    CDVPluginResult *pluginResult;
    NSString *flashMode = [command.arguments objectAtIndex:0];

    if (self.sessionManager != nil) {
        if ([flashMode isEqual: @"off"]) {
            [self.sessionManager setFlashMode:AVCaptureFlashModeOff];
        } else if ([flashMode isEqual: @"on"]) {
            [self.sessionManager setFlashMode:AVCaptureFlashModeOn];
        } else if ([flashMode isEqual: @"auto"]) {
            [self.sessionManager setFlashMode:AVCaptureFlashModeAuto];
        } else if ([flashMode isEqual: @"torch"]) {
            [self.sessionManager setTorchMode];
        } else {
            errMsg = @"Flash Mode not supported";
        }
    } else {
        errMsg = @"Session not started";
    }

    if (errMsg) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errMsg];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setZoom:(CDVInvokedUrlCommand*)command {
    NSLog(@"Zoom");
    CDVPluginResult *pluginResult;
    CGFloat desiredZoomFactor = [[command.arguments objectAtIndex:0] floatValue];

    if (self.sessionManager != nil) {
        [self.sessionManager setZoom:desiredZoomFactor];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getZoom:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        CGFloat zoom = [self.sessionManager getZoom];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:zoom];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getHorizontalFOV:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        float fov = [self.sessionManager getHorizontalFOV];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:fov];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getMaxZoom:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        CGFloat maxZoom = [self.sessionManager getMaxZoom];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:maxZoom];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSArray * exposureModes = [self.sessionManager getExposureModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:exposureModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSString * exposureMode = [self.sessionManager getExposureMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:exposureMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setExposureMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    NSString * exposureMode = [command.arguments objectAtIndex:0];

    if (self.sessionManager != nil) {
        [self.sessionManager setExposureMode:exposureMode];
        NSString * exposureMode = [self.sessionManager getExposureMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:exposureMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getSupportedWhiteBalanceModes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSArray * whiteBalanceModes = [self.sessionManager getSupportedWhiteBalanceModes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:whiteBalanceModes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getWhiteBalanceMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSString * whiteBalanceMode = [self.sessionManager getWhiteBalanceMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:whiteBalanceMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setWhiteBalanceMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    NSString * whiteBalanceMode = [command.arguments objectAtIndex:0];

    if (self.sessionManager != nil) {
        [self.sessionManager setWhiteBalanceMode:whiteBalanceMode];
        NSString * whiteBalanceMode = [self.sessionManager getWhiteBalanceMode];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:whiteBalanceMode];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureCompensationRange:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSArray * range = [self.sessionManager getExposureCompensationRange];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:range];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) getExposureCompensation:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        CGFloat exposureCompensation = [self.sessionManager getExposureCompensation];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:exposureCompensation];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) setExposureCompensation:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    CGFloat exposureCompensation = [[command.arguments objectAtIndex:0] floatValue];

    if (self.sessionManager != nil) {
        [self.sessionManager setExposureCompensation:exposureCompensation];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:exposureCompensation];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) tapToFocus:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;
    CGFloat xPoint = [[command.arguments objectAtIndex:0] floatValue];
    CGFloat yPoint = [[command.arguments objectAtIndex:1] floatValue];

    if (self.sessionManager != nil) {
        [self.sessionManager tapToFocus:xPoint yPoint:yPoint];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) takePicture:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        CGFloat maxWidth = (CGFloat)[command.arguments[0] floatValue];
        CGFloat maxHeight = (CGFloat)[command.arguments[1] floatValue];
        CGFloat quality = (CGFloat)[command.arguments[2] floatValue] / 100.0f;

        [self.sessionManager takePicture:maxWidth maxHeight:maxHeight quality:quality completion:^(UIImage *image) {
            if (image) {
                if (self.storeToFile) {
                    NSString *tempPath = [self getTempFilePath];
                    NSData *jpegData = UIImageJPEGRepresentation(image, quality);
                    [jpegData writeToFile:tempPath atomically:YES];
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:tempPath] callbackId:command.callbackId];
                } else {
                    NSData *jpegData = UIImageJPEGRepresentation(image, quality);
                    NSString *base64String = [jpegData base64EncodedStringWithOptions:0];
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:base64String] callbackId:command.callbackId];
                }
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to take picture"] callbackId:command.callbackId];
            }
        }];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void) takeSnapshot:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.cameraRenderController != nil) {
        CGFloat quality = (CGFloat)[command.arguments[0] floatValue] / 100.0f;

        [self.cameraRenderController takeSnapshot:quality completion:^(UIImage *image) {
            if (image) {
                NSData *jpegData = UIImageJPEGRepresentation(image, quality);
                NSString *base64String = [jpegData base64EncodedStringWithOptions:0];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:base64String] callbackId:command.callbackId];
            } else {
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to take snapshot"] callbackId:command.callbackId];
            }
        }];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Camera not started"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void) getSupportedPictureSizes:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult;

    if (self.sessionManager != nil) {
        NSArray * pictureSizes = [self.sessionManager getSupportedPictureSizes];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:pictureSizes];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not started"];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) onPictureTaken:(UIImage*)image {
    // delegate callback — handled via takePicture completion block above
}

- (void) onFocusSet:(CGPoint)point {
    // delegate callback — no action needed here
}

- (void) onFocusSetError:(NSString*)error {
    // delegate callback — no action needed here
}

- (NSString *) getTempFilePath {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"%@%@.jpg", TMP_IMAGE_PREFIX, [[NSUUID UUID] UUIDString]];
    return [tempDir stringByAppendingPathComponent:filename];
}

@end
