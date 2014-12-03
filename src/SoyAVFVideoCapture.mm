#include "SoyAVFVideoCapture.h"

#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
//#import <Accelerate/Accelerate.h>
#include <SoyDebug.h>



namespace Soy
{
	NSString*	StringToNSString(const std::string& String);
	std::string	NSStringToString(NSString* String);
};

std::string Soy::NSStringToString(NSString* String)
{
	return std::string([String UTF8String]);
}

NSString* Soy::StringToNSString(const std::string& String)
{
	NSString* MacString = [NSString stringWithCString:String.c_str() encoding:[NSString defaultCStringEncoding]];
	return MacString;
}

TVideoDeviceMeta GetDeviceMeta(AVCaptureDevice* Device)
{
	//	gr: allow this for failed-to-init devices
	if ( !Device )
//	if ( !Soy::Assert( Device, "Device expected") )
		return TVideoDeviceMeta();
	
	TVideoDeviceMeta Meta;
	Meta.mName = std::string([[Device localizedName] UTF8String]);
	Meta.mSerial = std::string([[Device uniqueID] UTF8String]);
	Meta.mVendor = std::string([[Device manufacturer] UTF8String]);
	Meta.mConnected = YES == [Device isConnected];
	Meta.mVideo = YES == [Device hasMediaType:AVMediaTypeVideo];
	Meta.mAudio = YES == [Device hasMediaType:AVMediaTypeAudio];
	Meta.mText = YES == [Device hasMediaType:AVMediaTypeText];
	Meta.mClosedCaption = YES == [Device hasMediaType:AVMediaTypeClosedCaption];
	Meta.mSubtitle = YES == [Device hasMediaType:AVMediaTypeSubtitle];
	Meta.mTimecode = YES == [Device hasMediaType:AVMediaTypeTimecode];
	//		Meta.mTimedMetadata = YES == [Device hasMediaType:AVMediaTypeTimedMetadata];
	Meta.mMetadata = YES == [Device hasMediaType:AVMediaTypeMetadata];
	Meta.mMuxed = YES == [Device hasMediaType:AVMediaTypeMuxed];
	/*
	 connected
	 position
	 hasMediaType:
	 modelID
	 localizedName
	 manufacturer
	 uniqueID
	 */
	
	return Meta;
}


TVideoDevice::TVideoDevice(std::string Serial,std::stringstream& Error)
{
}

TVideoDevice::~TVideoDevice()
{
}

void TVideoDevice::OnNewFrame(const SoyPixelsImpl& Pixels,SoyTime Timecode)
{
	//	lock!
	mLastFrame.mPixels.Copy( Pixels );

	//	gr: might want to reject earlier timecodes here
	mLastFrame.mTimecode = Timecode;
	
	mOnNewFrame.OnTriggered( mLastFrame );
}



@class VideoCaptureProxy;


//	obj-c class wrapper
class AVCaptureSessionWrapper
{
public:
	AVCaptureSessionWrapper(TVideoDevice_AvFoundation& Parent) :
		_session	( nullptr ),
		_proxy		( nullptr ),
		mDevice		( nullptr ),
		mParent		( Parent )
	{
	}
	~AVCaptureSessionWrapper()
	{
#if !__has_feature(objc_arc)
		[_session release];
		[_proxy release];
#endif
	}

	void handleSampleBuffer(CMSampleBufferRef);

	AVCaptureDevice*			mDevice;
	AVCaptureSession*			_session;
	VideoCaptureProxy*			_proxy;
	TVideoDevice_AvFoundation&	mParent;
};


void AVCaptureSessionWrapper::handleSampleBuffer(CMSampleBufferRef sampleBuffer)
{
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	if (CVPixelBufferLockBaseAddress(imageBuffer, 0) != kCVReturnSuccess)
	{
		//	unlock needed?
		CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
		std::Debug << "failed to lock new sample buffer";
		return;
	}

	//	gr: todo: soypixels in-place
	int Width = int(CVPixelBufferGetWidth(imageBuffer));
	int Height = int(CVPixelBufferGetHeight(imageBuffer));

	auto Data = static_cast<char*>(CVPixelBufferGetBaseAddress(imageBuffer));
	int DataSize = int(CVPixelBufferGetDataSize(imageBuffer));
	auto DataArray = GetRemoteArray( Data, DataSize, DataSize );
	int rowSize = int(CVPixelBufferGetBytesPerRow(imageBuffer));
	int ChannelCount = rowSize / Width;
	
	SoyPixels Pixels;
	auto Format = SoyPixelsFormat::GetFormatFromChannelCount( ChannelCount );
	if ( !Pixels.Init( Width, Height, Format ) )
	{
		std::Debug << "AVCapture failed to create pixels " << Width << "x" << Height << " as " << Format << std::endl;
		CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
		return;
	}
	Pixels.GetPixelsArray().Copy( DataArray );
	
	mParent.OnNewFrame( Pixels, SoyTime() );
	CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}


@interface VideoCaptureProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
{
	TVideoDevice_AvFoundation* _p;
}

- (id)initWithVideoCapturePrivate:(TVideoDevice_AvFoundation*)p;

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;

@end



@implementation VideoCaptureProxy

- (id)initWithVideoCapturePrivate:(TVideoDevice_AvFoundation*)p
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
	_p->mWrapper->handleSampleBuffer(sampleBuffer);
}

@end




SoyVideoCapture::SoyVideoCapture()
{
}

SoyVideoCapture::~SoyVideoCapture()
{
	//	kill all devices
	while ( !mDevices.IsEmpty() )
	{
		auto Device = mDevices.PopBack();
		Device.reset();
	}
}


void SoyVideoCapture::GetDevices(ArrayBridge<TVideoDeviceMeta>&& Metas)
{
	TVideoDevice_AvFoundation::GetDevices( Metas );
}

void TVideoDevice_AvFoundation::GetDevices(ArrayBridge<TVideoDeviceMeta>& Metas)
{
	NSArray* Devices = [AVCaptureDevice devices];
	
	for (id Device in Devices)
	{
		Metas.PushBack( GetDeviceMeta( Device ));
	}

}


std::shared_ptr<TVideoDevice> SoyVideoCapture::GetDevice(std::string Serial,std::stringstream& Error)
{
	//	see if device already exists
	for ( int i=0;	i<mDevices.GetSize();	i++ )
	{
		auto& Device = *mDevices[i];
		if ( Device == Serial )
			return mDevices[i];
	}
	
	//	create new device
	//	gr: todo: work out which type this is (from it's GetDevices list?)
	std::shared_ptr<TVideoDevice_AvFoundation> Device( new TVideoDevice_AvFoundation( Serial, Error ) );

	//	gr: require meta to be valid immediately, otherwise we assume the device failed to be created
	if ( !Device->GetMeta().IsValid() )
	{
		std::Debug << "Failed to initialise device " << Serial << std::endl;
		return nullptr;
	}
	
	mDevices.PushBack( Device );
	return Device;
}


TVideoDevice_AvFoundation::TVideoDevice_AvFoundation(std::string Serial,std::stringstream& Error) :
	TVideoDevice				( Serial, Error ),
	mConfigurationStackCounter	( 0 ),
	mWrapper					( new AVCaptureSessionWrapper(*this) )
{
	run( Serial, TVideoQuality::High, Error );
}

TVideoDevice_AvFoundation::~TVideoDevice_AvFoundation()
{
	pause();
}

//	run lamba
template<class ENTER_FUNCTION,class EXIT_FUNCTION>
class TScope
{
public:
	TScope(ENTER_FUNCTION EnterFunc,EXIT_FUNCTION ExitFunc) :
		mExitFunc		( ExitFunc )
	{
		EnterFunc();
	}
	~TScope()
	{
		mExitFunc();
	}
	
	EXIT_FUNCTION	mExitFunc;
};



NSString* GetAVCaptureSessionQuality(TVideoQuality::Type Quality)
{
	switch ( Quality )
	{
		case TVideoQuality::Low:
			return AVCaptureSessionPresetLow;
			
		case TVideoQuality::Medium:
			return AVCaptureSessionPresetMedium;
			
		case TVideoQuality::High:
			return AVCaptureSessionPresetHigh;
			
		default:
			Soy::Assert( false, "Unhandled TVideoQuality Type" );
			return AVCaptureSessionPresetHigh;
	}
}



bool TVideoDevice_AvFoundation::run(const std::string& Serial,TVideoQuality::Type Quality,std::stringstream& Error)
{
	if ( !Soy::Assert( mWrapper != nullptr, "expected wrapper") )
	{
		Error << "missing wrapper (internal error)";
		return false;
	}
	auto& Wrapper = *mWrapper;
	
	NSArray* devices = [AVCaptureDevice devices];
    if ([devices count] == 0)
		return false;
 
	Wrapper._proxy = [[VideoCaptureProxy alloc] initWithVideoCapturePrivate:this];
    
	Wrapper._session = [[AVCaptureSession alloc] init];
	Wrapper._session.sessionPreset = AVCaptureSessionPresetLow;
	
	NSError* error = nil;
    
    // Find a suitable AVCaptureDevice
	NSString* SerialString = [NSString stringWithCString:Serial.c_str()
												encoding:[NSString defaultCStringEncoding]];
    Wrapper.mDevice = [AVCaptureDevice deviceWithUniqueID:SerialString];
	auto* device = Wrapper.mDevice;
	
	AVCaptureDeviceInput* _input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (_input && [Wrapper._session canAddInput:_input])
		[Wrapper._session addInput:_input];
	
	AVCaptureVideoDataOutput* _output = [[AVCaptureVideoDataOutput alloc] init];
	_output.alwaysDiscardsLateVideoFrames = YES;
	_output.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey, nil];
	
    
    //[_output setSampleBufferDelegate:_proxy queue:dispatch_get_main_queue()];
    dispatch_queue_t queue = dispatch_queue_create("camera_queue", NULL);
    [_output setSampleBufferDelegate:Wrapper._proxy queue: queue];
#if !__has_feature(objc_arc)
    dispatch_release(queue);
#endif
	
    
	[Wrapper._session addOutput:_output];
	
	//AVCaptureConnection *conn = [_output connectionWithMediaType:AVMediaTypeVideo];
	//if (conn.supportsVideoMinFrameDuration)
	//	conn.videoMinFrameDuration = CMTimeMake(1, 30);
	//if (conn.supportsVideoMaxFrameDuration)
	//	conn.videoMaxFrameDuration = CMTimeMake(1, 30);

	//[_session startRunning];
	if ( !Play() )
	{
		Error << "Failed to play";
		return false;
	}

	return true;
}


bool TVideoDevice_AvFoundation::Play()
{
	if ( !mWrapper || !mWrapper->_session )
		return false;
	
	auto& Session = mWrapper->_session;
	if ( !Session.running )
		[ Session startRunning];

	return Session.running;
}

void TVideoDevice_AvFoundation::Pause()
{
	if ( mWrapper && mWrapper->_session )
	{
		auto& Session = mWrapper->_session;
		if ( Session.running)
			[Session stopRunning];
	}
}

bool TVideoDevice_AvFoundation::GetOption(TVideoOption::Type Option,bool Default)
{
	Soy::Assert( false, "Todo" );
	return Default;
}


bool TVideoDevice_AvFoundation::SetOption(TVideoOption::Type Option, bool Enable)
{
	auto* device = mWrapper ? mWrapper->mDevice : nullptr;
	if ( !device )
		return false;

	if ( !BeginConfiguration() )
		return false;

	//	gr: is this needed???
	//if (([device hasMediaType:AVMediaTypeVideo]) && ([device position] == AVCaptureDevicePositionBack))

	NSError* error = nil;
	[device lockForConfiguration:&error];
	
	bool Supported = false;
	if ( !error )
	{
		switch ( Option )
		{
			case TVideoOption::LockedExposure:
				Supported = setExposureLocked( Enable );
				break;
			
			case TVideoOption::LockedFocus:
				Supported = setFocusLocked( Enable );
				break;
			
			case TVideoOption::LockedWhiteBalance:
				Supported = setWhiteBalanceLocked( Enable );
				break;
				
			default:
				std::Debug << "tried to set video device " << GetSerial() << " unknown option " << Option << std::endl;
				Supported = false;
				break;
		}
	}
	
	//	gr: dont unlock if error?
	[device unlockForConfiguration];
	
	EndConfiguration();

	return Supported;
}

bool TVideoDevice_AvFoundation::setFocusLocked(bool Enable)
{
	auto* device = mWrapper->mDevice;
	if ( Enable )
	{
		if ( ![device isFocusModeSupported:AVCaptureFocusModeLocked] )
			return false;
		
		device.focusMode = AVCaptureFocusModeLocked;
		return true;
	}
	else
	{
		if ( ![device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
			return false;
		
		device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
		return true;
	}
}


bool TVideoDevice_AvFoundation::setWhiteBalanceLocked(bool Enable)
{
	auto* device = mWrapper->mDevice;
	if ( Enable )
	{
		if ( ![device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked] )
			return false;
		
		device.whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
		return true;
	}
	else
	{
		if ( ![device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
			return false;
		
		device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
		return true;
	}
}



bool TVideoDevice_AvFoundation::setExposureLocked(bool Enable)
{
	auto* device = mWrapper->mDevice;
	if ( Enable )
	{
		if ( ![device isExposureModeSupported:AVCaptureExposureModeLocked] )
			return false;
		
		device.exposureMode = AVCaptureExposureModeLocked;
		return true;
	}
	else
	{
		if ( ![device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
			return false;
		
		device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
		return true;
	}
}

bool TVideoDevice_AvFoundation::BeginConfiguration()
{
	auto* Session = mWrapper ? mWrapper->_session : nullptr;
	if ( !Soy::Assert( Session, "Expected session") )
		return false;
	
	if ( mConfigurationStackCounter == 0)
		[Session beginConfiguration];
	
	mConfigurationStackCounter++;
	return true;
}

bool TVideoDevice_AvFoundation::EndConfiguration()
{
	auto* Session = mWrapper ? mWrapper->_session : nullptr;
	if ( !Soy::Assert( Session, "Expected session") )
		return false;
	mConfigurationStackCounter--;
	
	if (mConfigurationStackCounter == 0)
		[Session commitConfiguration];
	return true;
}

TVideoDeviceMeta TVideoDevice_AvFoundation::GetMeta() const
{
	if ( !mWrapper )
		return TVideoDeviceMeta();
	
	return GetDeviceMeta( mWrapper->mDevice );
}
