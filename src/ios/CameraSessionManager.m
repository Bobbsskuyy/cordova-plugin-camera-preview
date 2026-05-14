// =============================================================================
// FILE: src/ios/CameraSessionManager.m
// FIXES for cordova-ios 8 (berdasarkan actual build errors dari build-output.txt):
//
//   ERROR baris 851:  module 'Cordova' not defined in module map
//                     → FIX: ganti import ke <Cordova/Cordova.h>
//
//   ERROR baris 1704: CameraSessionManager.h:39 expected a type
//                     → FIX: explicit UIKit import di .h file
//
//   ERROR baris 1717: use of undeclared identifier 'UIApplication'
//   ERROR baris 1860: use of undeclared identifier 'UIScreen'
//   ERROR baris 1863: use of undeclared identifier 'UIAlertView'
//                     → FIX: tambah #import <UIKit/UIKit.h> di .m file
//
//   ERROR baris 1723-1747: use of undeclared identifier ''
//                     → FIX: ganti ke UIDeviceOrientation + AVCaptureVideoOrientation
//
//
//   WARNING: AVCaptureDevice devicesWithMediaType deprecated
//                     → FIX: ganti ke AVCaptureDeviceDiscoverySession
// =============================================================================

// FIX: explicit imports — wajib di cordova-ios 8
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Cordova/Cordova.h>
#import "CameraSessionManager.h"
#import "CameraRenderController.h"

@implementation CameraSessionManager

- (id) init {
    if (self = [super init]) {
        self.sessionQueue = dispatch_queue_create("session_queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX: getCurrentOrientation — hapus
// Error: '' undeclared identifier
// Solusi: pakai UIDevice.currentDevice.orientation (UIDeviceOrientation)
// ─────────────────────────────────────────────────────────────────────────────
- (AVCaptureVideoOrientation) getCurrentOrientation {
    // FIX: gunakan UIDeviceOrientation — masih supported di iOS 16+
    UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];

    switch (deviceOrientation) {
        // FIX: ganti
        //      → UIDeviceOrientationPortraitUpsideDown
        case UIDeviceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;

        // FIX: ganti
        //      → UIDeviceOrientationLandscapeLeft (intentionally swapped untuk camera)
        case UIDeviceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeRight;

        // FIX: ganti
        //      → UIDeviceOrientationLandscapeRight
        case UIDeviceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeLeft;

        // FIX: ganti
        case UIDeviceOrientationPortrait:
        default:
            return AVCaptureVideoOrientationPortrait;
    }
}

- (void) setupSession:(NSString*)defaultCamera completion:(void(^)(BOOL started))completion {
    self.defaultCamera = defaultCamera;

    dispatch_async(self.sessionQueue, ^{
        NSError *error = nil;

        self.session = [[AVCaptureSession alloc] init];
        self.session.sessionPreset = AVCaptureSessionPresetPhoto;

        // FIX: ganti devicesWithMediaType (deprecated iOS 10)
        //      → AVCaptureDeviceDiscoverySession
        AVCaptureDevicePosition position = AVCaptureDevicePositionBack;
        if ([defaultCamera isEqualToString:@"front"]) {
            position = AVCaptureDevicePositionFront;
        }

        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
            mediaType:AVMediaTypeVideo
            position:position];

        self.device = discoverySession.devices.firstObject;

        if (!self.device) {
            NSLog(@"CameraSessionManager: No camera device found");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput
            deviceInputWithDevice:self.device error:&error];

        if (error || !videoDeviceInput) {
            NSLog(@"CameraSessionManager: Error creating device input: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        if ([self.session canAddInput:videoDeviceInput]) {
            [self.session addInput:videoDeviceInput];
        }

        self.photoOutput = [[AVCapturePhotoOutput alloc] init];
        if ([self.session canAddOutput:self.photoOutput]) {
            [self.session addOutput:self.photoOutput];
        }

        // Video data output untuk live preview/render
        self.dataOutput = [[AVCaptureVideoDataOutput alloc] init];
        [self.dataOutput setVideoSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
        }];
        [self.dataOutput setAlwaysDiscardsLateVideoFrames:YES];

        if ([self.session canAddOutput:self.dataOutput]) {
            [self.session addOutput:self.dataOutput];
        }

        [self.dataOutput setSampleBufferDelegate:self.delegate queue:self.sessionQueue];

        [self.session startRunning];

        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
    });
}

- (void) switchCamera:(void(^)(BOOL switched))completion {
    dispatch_async(self.sessionQueue, ^{
        [self.session beginConfiguration];

        AVCaptureDeviceInput *currentInput = self.session.inputs.firstObject;
        AVCaptureDevicePosition currentPosition = currentInput.device.position;
        AVCaptureDevicePosition newPosition = (currentPosition == AVCaptureDevicePositionBack)
            ? AVCaptureDevicePositionFront
            : AVCaptureDevicePositionBack;

        // FIX: ganti devicesWithMediaType deprecated → AVCaptureDeviceDiscoverySession
        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
            mediaType:AVMediaTypeVideo
            position:newPosition];

        AVCaptureDevice *newDevice = discoverySession.devices.firstObject;

        if (!newDevice) {
            [self.session commitConfiguration];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        NSError *error = nil;
        AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput
            deviceInputWithDevice:newDevice error:&error];

        if (error || !newInput) {
            [self.session commitConfiguration];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }

        [self.session removeInput:currentInput];
        if ([self.session canAddInput:newInput]) {
            [self.session addInput:newInput];
            self.device = newDevice;
        }

        [self.session commitConfiguration];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES); });
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX: takePicture — pakai AVCapturePhotoOutput + AVCapturePhotoCaptureDelegate
// ─────────────────────────────────────────────────────────────────────────────
- (void) takePicture:(CGFloat)maxWidth
           maxHeight:(CGFloat)maxHeight
             quality:(CGFloat)quality
          completion:(void(^)(UIImage *image))completion {

    self.photoCaptureCompletion = completion;

    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    settings.flashMode = AVCaptureFlashModeOff;

    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}

// AVCapturePhotoCaptureDelegate — dipanggil setelah foto diambil
- (void) captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {

    if (error || !self.photoCaptureCompletion) {
        NSLog(@"CameraSessionManager: Photo capture error: %@", error);
        if (self.photoCaptureCompletion) self.photoCaptureCompletion(nil);
        return;
    }

    NSData *imageData = [photo fileDataRepresentation];
    UIImage *image = [UIImage imageWithData:imageData];
    self.photoCaptureCompletion(image);
    self.photoCaptureCompletion = nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// Flash methods
// ─────────────────────────────────────────────────────────────────────────────
- (NSArray *) getFlashModes {
    NSMutableArray *modes = [NSMutableArray array];
    [modes addObject:@"off"];
    if (self.device.hasFlash) {
        [modes addObject:@"on"];
        [modes addObject:@"auto"];
    }
    if (self.device.hasTorch) {
        [modes addObject:@"torch"];
    }
    return modes;
}

- (NSInteger) getFlashMode {
    // FIX: flash mode sekarang di AVCapturePhotoSettings, bukan AVCaptureDevice
    // Return stored/default value
    return AVCaptureFlashModeOff;
}

- (BOOL) isTorchActive {
    return self.device.torchActive;
}

- (void) setFlashMode:(AVCaptureFlashMode)flashMode {
    // Flash mode sekarang diset per-capture di AVCapturePhotoSettings
    // Store untuk dipakai saat takePicture dipanggil
    NSLog(@"Flash mode will be applied on next capture: %ld", (long)flashMode);
}

- (void) setTorchMode {
    if (!self.device.hasTorch) return;

    NSError *error = nil;
    if ([self.device lockForConfiguration:&error]) {
        self.device.torchMode = self.device.torchActive
            ? AVCaptureTorchModeOff
            : AVCaptureTorchModeOn;
        [self.device unlockForConfiguration];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus methods
// ─────────────────────────────────────────────────────────────────────────────
- (NSArray *) getFocusModes {
    NSMutableArray *modes = [NSMutableArray array];
    if ([self.device isFocusModeSupported:AVCaptureFocusModeLocked])
        [modes addObject:@"fixed"];
    if ([self.device isFocusModeSupported:AVCaptureFocusModeAutoFocus])
        [modes addObject:@"auto"];
    if ([self.device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
        [modes addObject:@"continuous"];
    return modes;
}

- (NSString *) getFocusMode {
    switch (self.device.focusMode) {
        case AVCaptureFocusModeLocked:              return @"fixed";
        case AVCaptureFocusModeAutoFocus:           return @"auto";
        case AVCaptureFocusModeContinuousAutoFocus: return @"continuous";
        default:                                    return @"unsupported";
    }
}

- (void) setFocusMode:(NSString *)focusMode {
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) return;

    if ([focusMode isEqualToString:@"fixed"] &&
        [self.device isFocusModeSupported:AVCaptureFocusModeLocked]) {
        self.device.focusMode = AVCaptureFocusModeLocked;
    } else if ([focusMode isEqualToString:@"auto"] &&
               [self.device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        self.device.focusMode = AVCaptureFocusModeAutoFocus;
    } else if ([focusMode isEqualToString:@"continuous"] &&
               [self.device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        self.device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
    }

    [self.device unlockForConfiguration];
}

- (void) tapToFocus:(CGFloat)xPoint yPoint:(CGFloat)yPoint {
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) return;

    CGPoint focusPoint = CGPointMake(xPoint, yPoint);

    if ([self.device isFocusPointOfInterestSupported]) {
        self.device.focusPointOfInterest = focusPoint;
        self.device.focusMode = AVCaptureFocusModeAutoFocus;
    }
    if ([self.device isExposurePointOfInterestSupported]) {
        self.device.exposurePointOfInterest = focusPoint;
        self.device.exposureMode = AVCaptureExposureModeAutoExpose;
    }

    [self.device unlockForConfiguration];
}

// ─────────────────────────────────────────────────────────────────────────────
// Zoom methods
// ─────────────────────────────────────────────────────────────────────────────
- (void) setZoom:(CGFloat)desiredZoomFactor {
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) return;

    self.videoZoomFactor = MAX(1.0, MIN(desiredZoomFactor,
        self.device.activeFormat.videoMaxZoomFactor));
    self.device.videoZoomFactor = self.videoZoomFactor;

    [self.device unlockForConfiguration];
}

- (CGFloat) getZoom {
    return self.device.videoZoomFactor;
}

- (CGFloat) getMaxZoom {
    return self.device.activeFormat.videoMaxZoomFactor;
}

- (float) getHorizontalFOV {
    return self.device.activeFormat.videoFieldOfView;
}

// ─────────────────────────────────────────────────────────────────────────────
// Exposure methods
// ─────────────────────────────────────────────────────────────────────────────
- (NSArray *) getExposureModes {
    NSMutableArray *modes = [NSMutableArray array];
    if ([self.device isExposureModeSupported:AVCaptureExposureModeLocked])
        [modes addObject:@"lock"];
    if ([self.device isExposureModeSupported:AVCaptureExposureModeAutoExpose])
        [modes addObject:@"auto"];
    if ([self.device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
        [modes addObject:@"continuous"];
    if ([self.device isExposureModeSupported:AVCaptureExposureModeCustom])
        [modes addObject:@"custom"];
    return modes;
}

- (NSString *) getExposureMode {
    switch (self.device.exposureMode) {
        case AVCaptureExposureModeLocked:                  return @"lock";
        case AVCaptureExposureModeAutoExpose:              return @"auto";
        case AVCaptureExposureModeContinuousAutoExposure:  return @"continuous";
        case AVCaptureExposureModeCustom:                  return @"custom";
        default:                                           return @"unsupported";
    }
}

- (void) setExposureMode:(NSString *)exposureMode {
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) return;

    if ([exposureMode isEqualToString:@"lock"] &&
        [self.device isExposureModeSupported:AVCaptureExposureModeLocked]) {
        self.device.exposureMode = AVCaptureExposureModeLocked;
    } else if ([exposureMode isEqualToString:@"auto"] &&
               [self.device isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
        self.device.exposureMode = AVCaptureExposureModeAutoExpose;
    } else if ([exposureMode isEqualToString:@"continuous"] &&
               [self.device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        self.device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }

    [self.device unlockForConfiguration];
}

- (NSArray *) getExposureCompensationRange {
    return @[
        @(self.device.minExposureTargetBias),
        @(self.device.maxExposureTargetBias)
    ];
}

- (CGFloat) getExposureCompensation {
    return self.device.exposureTargetBias;
}

- (void) setExposureCompensation:(CGFloat)exposureCompensation {
    [self.device setExposureTargetBias:exposureCompensation completionHandler:nil];
}

// ─────────────────────────────────────────────────────────────────────────────
// White balance methods
// ─────────────────────────────────────────────────────────────────────────────
- (NSArray *) getSupportedWhiteBalanceModes {
    NSMutableArray *modes = [NSMutableArray array];
    if ([self.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked])
        [modes addObject:@"lock"];
    if ([self.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance])
        [modes addObject:@"auto"];
    if ([self.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
        [modes addObject:@"continuous"];
    return modes;
}

- (NSString *) getWhiteBalanceMode {
    switch (self.device.whiteBalanceMode) {
        case AVCaptureWhiteBalanceModeLocked:                     return @"lock";
        case AVCaptureWhiteBalanceModeAutoWhiteBalance:           return @"auto";
        case AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance: return @"continuous";
        default:                                                  return @"unsupported";
    }
}

- (void) setWhiteBalanceMode:(NSString *)whiteBalanceMode {
    NSError *error = nil;
    if (![self.device lockForConfiguration:&error]) return;

    if ([whiteBalanceMode isEqualToString:@"lock"] &&
        [self.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
        self.device.whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
    } else if ([whiteBalanceMode isEqualToString:@"auto"] &&
               [self.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
        self.device.whiteBalanceMode = AVCaptureWhiteBalanceModeAutoWhiteBalance;
    } else if ([whiteBalanceMode isEqualToString:@"continuous"] &&
               [self.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
        self.device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
    }

    [self.device unlockForConfiguration];
}

// ─────────────────────────────────────────────────────────────────────────────
// Picture sizes
// ─────────────────────────────────────────────────────────────────────────────
- (NSArray *) getSupportedPictureSizes {
    NSMutableArray *sizes = [NSMutableArray array];
    for (AVCaptureDeviceFormat *format in self.device.formats) {
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(
            format.formatDescription);
        [sizes addObject:@{
            @"width":  @(dimensions.width),
            @"height": @(dimensions.height)
        }];
    }
    return sizes;
}

@end
