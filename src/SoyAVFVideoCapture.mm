#include "SoyAVFVideoCapture.h"

#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
//#import <Accelerate/Accelerate.h>



@class VideoCaptureProxy;


	class VideoCapturePIMPL
	{
	public:
		VideoCapturePIMPL(SoyVideoCapture* owner, SoyVideoCapture::Quality q);
		~VideoCapturePIMPL();
		
		void handleSampleBuffer(CMSampleBufferRef);
        void run();
        void stop();
        
		void setFocusLocked(bool isLocked);
		void setWhiteBalanceLocked(bool isLocked);
		void setExposureLocked(bool isLocked);
		
		void beginConfiguration();
		void endConfiguration();
		
	private:
		SoyVideoCapture* _owner;
		VideoCaptureProxy* _proxy;
		AVCaptureSession* _session;
		int _configurationCounter;
	};



    @interface VideoCaptureProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
    {
        VideoCapturePIMPL* _p;
    }

    - (id)initWithVideoCapturePrivate:(VideoCapturePIMPL*)p;

    - (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;

    @end



    @implementation VideoCaptureProxy

    - (id)initWithVideoCapturePrivate:(VideoCapturePIMPL*)p
    {
        self = [super init];
        if (self)
        {
            _p = p;
        }
        return self;
    }

    - (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
    {
        _p->handleSampleBuffer(sampleBuffer);
    }

    @end




SoyVideoCapture::SoyVideoCapture()
    : pimpl(nullptr), deviceIndex(-1)
{
}

SoyVideoCapture::~SoyVideoCapture()
{
    Close();
}

void SoyVideoCapture::Open(Quality q, int deviceIndex)
{
    this->deviceIndex = deviceIndex;
 
    if (pimpl == nullptr)
        pimpl = new VideoCapturePIMPL(this, q);
    
    pimpl->run();
}

void SoyVideoCapture::Close()
{
    if (pimpl != nullptr)
    {
        pimpl->stop();
        delete pimpl;
        pimpl = nullptr;
    }
}

void SoyVideoCapture::setFlags(int flags)
{
	if (flags)
		pimpl->beginConfiguration();
	
	if ((flags & VideoCaptureFlag_LockFocus) == VideoCaptureFlag_LockFocus)
		pimpl->setFocusLocked(true);
	if ((flags & VideoCaptureFlag_LockExposure) == VideoCaptureFlag_LockExposure)
		pimpl->setExposureLocked(true);
	if ((flags & VideoCaptureFlag_LockWhiteBalance) == VideoCaptureFlag_LockWhiteBalance)
		pimpl->setWhiteBalanceLocked(true);
	
	if (flags)
		pimpl->endConfiguration();
}

void SoyVideoCapture::removeFlags(int flags)
{
	if (flags)
		pimpl->beginConfiguration();
	
	if ((flags & VideoCaptureFlag_LockFocus) == VideoCaptureFlag_LockFocus)
		pimpl->setFocusLocked(false);
	if ((flags & VideoCaptureFlag_LockExposure) == VideoCaptureFlag_LockExposure)
		pimpl->setExposureLocked(false);
	if ((flags & VideoCaptureFlag_LockWhiteBalance) == VideoCaptureFlag_LockWhiteBalance)
		pimpl->setWhiteBalanceLocked(false);
	
	if (flags)
		pimpl->endConfiguration();
}

bool SoyVideoCapture::available()
{
    return [[AVCaptureDevice devices] count] > 0;
}

VideoCapturePIMPL::VideoCapturePIMPL(SoyVideoCapture* owner, SoyVideoCapture::Quality q) :
_owner(owner)
{
	NSArray* devices = [AVCaptureDevice devices];
    if ([devices count] == 0) return;
 
	_proxy = [[VideoCaptureProxy alloc] initWithVideoCapturePrivate:this];
    
	_session = [[AVCaptureSession alloc] init];
	
	if (q == SoyVideoCapture::VideoCaptureQuality_Low)
		_session.sessionPreset = AVCaptureSessionPresetLow;
	else if (q == SoyVideoCapture::VideoCaptureQuality_High)
		_session.sessionPreset = AVCaptureSessionPresetHigh;
	else
		_session.sessionPreset = AVCaptureSessionPresetMedium;
    
	NSError* error = nil;
    
    // Find a suitable AVCaptureDevice
    AVCaptureDevice *device = owner->deviceIndex == -1 ?
                                [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] : [devices objectAtIndex:owner->deviceIndex];
    
	AVCaptureDeviceInput* _input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (_input && [_session canAddInput:_input])
		[_session addInput:_input];
	
	AVCaptureVideoDataOutput* _output = [[AVCaptureVideoDataOutput alloc] init];
	_output.alwaysDiscardsLateVideoFrames = YES;
	_output.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey, nil];
	
    
    //[_output setSampleBufferDelegate:_proxy queue:dispatch_get_main_queue()];
    dispatch_queue_t queue = dispatch_queue_create("camera_queue", NULL);
    [_output setSampleBufferDelegate:_proxy queue: queue];
#if !__has_feature(objc_arc)
    dispatch_release(queue);
#endif
	
    
	[_session addOutput:_output];
	
	//AVCaptureConnection *conn = [_output connectionWithMediaType:AVMediaTypeVideo];
	//if (conn.supportsVideoMinFrameDuration)
	//	conn.videoMinFrameDuration = CMTimeMake(1, 30);
	//if (conn.supportsVideoMaxFrameDuration)
	//	conn.videoMaxFrameDuration = CMTimeMake(1, 30);

	//[_session startRunning];
}

VideoCapturePIMPL::~VideoCapturePIMPL()
{
    stop();
    
#if !__has_feature(objc_arc)
	[_session release];
	[_proxy release];
#endif
}

void VideoCapturePIMPL::handleSampleBuffer(CMSampleBufferRef sampleBuffer)
{
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	if (CVPixelBufferLockBaseAddress(imageBuffer, 0) == kCVReturnSuccess)
    {
        SoyVideoCapture::FrameData data;
        data.w = int(CVPixelBufferGetWidth(imageBuffer));
        data.h = int(CVPixelBufferGetHeight(imageBuffer));
        data.data = static_cast<char*>(CVPixelBufferGetBaseAddress(imageBuffer));
        data.dataSize = int(CVPixelBufferGetDataSize(imageBuffer));
        data.rowSize = int(CVPixelBufferGetBytesPerRow(imageBuffer));
        
        
        
        /*
         // possible to scale using vDSP...
         
        int cropX0=100, cropY0=100, cropHeight=100, cropWidth=100, outWidth=100, outHeight=100;
        
        char *baseAddress = data.data;
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        
        vImage_Buffer inBuff;
        inBuff.height = cropHeight;
        inBuff.width = cropWidth;
        inBuff.rowBytes = bytesPerRow;
        
        int startpos = cropY0*bytesPerRow+4*cropX0;
        inBuff.data = baseAddress+startpos;
        
        unsigned char *outImg= (unsigned char*)malloc(4*outWidth*outHeight);
        vImage_Buffer outBuff;
        outBuff.data = outImg;
        outBuff.height = outHeight;
        outBuff.width = outWidth;
        outBuff.rowBytes = 4*outWidth;
        
        vImage_Error err = vImageScale_ARGB8888(&inBuff, &outBuff, NULL, 0);
        if (err != kvImageNoError) NSLog(@" error %ld", err);
        */
        
        
        
        /*
        // easy to convert to juce::Image...
         
        Image img(Image::RGB, frame.w, frame.h, false);
        
        Image::BitmapData d(img, Image::BitmapData::writeOnly);
        
        if (d.lineStride*d.height != frame.rowSize*frame.h)
        {
            jassert(false);
        }
        else
        {
            uint8* l = d.getLinePointer(0);
            memcpy(l, frame.data, frame.rowSize*frame.h);
        }
        */
        
        _owner->onVideoFrame(data);
    }
    
	CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}

void VideoCapturePIMPL::run()
{
	if (!_session.running)
		[_session startRunning];
}

void VideoCapturePIMPL::stop()
{
	if (_session.running)
		[_session stopRunning];
}

void VideoCapturePIMPL::setFocusLocked(bool isLocked)
{
	if (_session == nullptr) return;
    
	beginConfiguration();
	
	NSArray* devices = [AVCaptureDevice devices];
	NSError* error = nil;
	
	for (AVCaptureDevice* device in devices)
	{
		if (([device hasMediaType:AVMediaTypeVideo]) && ([device position] == AVCaptureDevicePositionBack))
		{
			[device lockForConfiguration:&error];
			if (isLocked)
			{
				if ([device isFocusModeSupported:AVCaptureFocusModeLocked])
					device.focusMode = AVCaptureFocusModeLocked;
			}
			else
			{
				if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
					device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
			}
			[device unlockForConfiguration];
		}
	}
	
	endConfiguration();
}

void VideoCapturePIMPL::setWhiteBalanceLocked(bool isLocked)
{
	if (_session == nullptr) return;
	
	beginConfiguration();
	
	NSArray* devices = [AVCaptureDevice devices];
	NSError* error = nil;
	
	for (AVCaptureDevice* device in devices)
	{
		if (([device hasMediaType:AVMediaTypeVideo]) && ([device position] == AVCaptureDevicePositionBack))
		{
			[device lockForConfiguration:&error];
			if (isLocked)
			{
				if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked])
					device.whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
			}
			else
			{
				if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
					device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
			}
			[device unlockForConfiguration];
		}
	}
	
	endConfiguration();
}

void VideoCapturePIMPL::setExposureLocked(bool isLocked)
{
	if (_session == nullptr) return;
    
	beginConfiguration();
	
	NSArray* devices = [AVCaptureDevice devices];
	NSError* error = nil;
	
	for (AVCaptureDevice* device in devices)
	{
		if (([device hasMediaType:AVMediaTypeVideo]) && ([device position] == AVCaptureDevicePositionBack))
		{
			[device lockForConfiguration:&error];
			if (isLocked)
			{
				if ([device isExposureModeSupported:AVCaptureExposureModeLocked])
					device.exposureMode = AVCaptureExposureModeLocked;
			}
			else
			{
				if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
					device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
			}
			[device unlockForConfiguration];
		}
	}
	
	endConfiguration();
}

void VideoCapturePIMPL::beginConfiguration()
{
	if (_configurationCounter == 0)
		[_session beginConfiguration];
	
	++_configurationCounter;
}

void VideoCapturePIMPL::endConfiguration()
{
	--_configurationCounter;
	
	if (_configurationCounter == 0)
		[_session commitConfiguration];
}