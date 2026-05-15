// =============================================================================
// FILE: src/ios/CameraSessionManager.h
// FIXES for cordova-ios 8:
//   1. Tambah explicit UIKit import — cordova-ios 8 tidak auto-include UIKit
//   2. Ganti AVCaptureStillImageOutput → AVCapturePhotoOutput (deprecated iOS 10)
//   3. Hapus UIInterfaceOrientation dari method signature
// =============================================================================

// FIX #1: explicit UIKit import — wajib di cordova-ios 8
// Sebelumnya UIKit ter-include secara implicit, sekarang harus eksplisit
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Cordova/Cordova.h>

@protocol TakePictureDelegate
- (void) invokeTakePicture;
- (void) invokeTakePictureOnFocus;
- (void) onPictureTaken:(NSString *)image;
@end

@protocol FocusDelegate
- (void) invokeTapToFocus:(CGPoint)point;
- (void) onFocusSet:(CGPoint)point;
- (void) onFocusSetError:(NSString*)error;
@end

@interface CameraSessionManager : NSObject <AVCapturePhotoCaptureDelegate>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice  *device;

// FIX #2: Ganti AVCaptureStillImageOutput → AVCapturePhotoOutput
// AVCaptureStillImageOutput deprecated sejak iOS 10, dihapus di iOS 17+
// Error di build log: 'AVCaptureStillImageOutput' is deprecated
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;

@property (nonatomic, strong) AVCaptureVideoDataOutput *dataOutput;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) NSString *defaultCamera;
@property (nonatomic)         CGFloat  videoZoomFactor;
@property (nonatomic, weak)   id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate;

// Callback blocks untuk photo capture
@property (nonatomic, copy) void (^photoCaptureCompletion)(UIImage *image);

- (void) setupSession:(NSString*)defaultCamera
           completion:(void(^)(BOOL started))completion;

- (void) switchCamera:(void(^)(BOOL switched))completion;

// FIX #3: Hapus UIInterfaceOrientation dari parameter
// UIInterfaceOrientation enum dihapus di Xcode 16 / iOS 16+
// Ganti pakai UIDeviceOrientation yang masih supported
- (AVCaptureVideoOrientation) getCurrentOrientation;

- (void) takePicture:(CGFloat)maxWidth
           maxHeight:(CGFloat)maxHeight
             quality:(CGFloat)quality
          completion:(void(^)(UIImage *image))completion;

- (NSArray *)  getFocusModes;
- (NSString *) getFocusMode;
- (void)       setFocusMode:(NSString *)focusMode;

- (NSArray *)  getFlashModes;
- (NSInteger)  getFlashMode;
- (BOOL)       isTorchActive;
- (void)       setFlashMode:(AVCaptureFlashMode)flashMode;
- (void)       setTorchMode;

- (void)       setZoom:(CGFloat)desiredZoomFactor;
- (CGFloat)    getZoom;
- (CGFloat)    getMaxZoom;
- (float)      getHorizontalFOV;

- (NSArray *)  getExposureModes;
- (NSString *) getExposureMode;
- (void)       setExposureMode:(NSString *)exposureMode;

- (NSArray *)  getSupportedWhiteBalanceModes;
- (NSString *) getWhiteBalanceMode;
- (void)       setWhiteBalanceMode:(NSString *)whiteBalanceMode;

- (NSArray *)  getExposureCompensationRange;
- (CGFloat)    getExposureCompensation;
- (void)       setExposureCompensation:(CGFloat)exposureCompensation;

- (NSArray *)  getSupportedPictureSizes;

- (void)       tapToFocus:(CGFloat)xPoint yPoint:(CGFloat)yPoint;
- (void) updateOrientation:(AVCaptureVideoOrientation)orientation;
@end
