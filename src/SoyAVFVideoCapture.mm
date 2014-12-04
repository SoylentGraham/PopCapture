#include "SoyAVFVideoCapture.h"

#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
//#import <Accelerate/Accelerate.h>
#include <SoyDebug.h>
#include <SoyScope.h>
#include <SoyString.h>
#include <SortArray.h>



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


bool TVideoDeviceMeta::operator==(const std::string& Serial) const
{
	if ( mSerial == Serial )
		return true;
	
	//	gr: allow loose match by name
	if ( Soy::StringContains( mName, Serial, false ) )
		return true;
	
	return false;
}


TVideoDevice::TVideoDevice(std::string Serial,std::stringstream& Error) :
	mLastError		( "waiting for first frame" ),
	mFrameCount		( 0 )
{
}

TVideoDevice::~TVideoDevice()
{
}

float TVideoDevice::GetFps() const
{
	uint64 TotalMs = mLastFrameTime.GetTime() - mFirstFrameTime.GetTime();
	if ( TotalMs == 0 )
		return 0.f;
	
	float TotalSecs = TotalMs / 1000.f;
	return mFrameCount / TotalSecs;
}

int TVideoDevice::GetFrameMs() const
{
	uint64 TotalMs = mLastFrameTime.GetTime() - mFirstFrameTime.GetTime();
	if ( TotalMs == 0 )
		return 0;
	uint64 AverageMs = TotalMs / mFrameCount;
	//	cast, this shouldn't be massive
	if ( !Soy::Assert( AverageMs < 0xffffffff, "very large avergage ms" ) )
		return -1;
	return static_cast<int>(AverageMs);
}

void TVideoDevice::ResetFrameCounter()
{
	mLastFrameTime = SoyTime();
	mFirstFrameTime = SoyTime();
	mFrameCount = 0;
}


void TVideoDevice::OnFailedFrame(const std::string &Error)
{
	mLastError = Error;
}

void TVideoDevice::OnNewFrame(const SoyPixelsImpl& Pixels,SoyTime Timecode)
{
	mLastError.clear();
	
	mLastFrame.mPixels.Copy( Pixels );

	//	gr: might want to reject earlier timecodes here
	mLastFrame.mTimecode = Timecode;
	
	//	update frame/rate counting
	mFrameCount++;
	mLastFrameTime = SoyTime(true);
	if ( !mFirstFrameTime.IsValid() )
		mFirstFrameTime = mLastFrameTime;
	
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
	//	auto unlock
	//	gr: old code called this even when it failed... so include before the lock...
	auto ScopeUnlock = SoyScopeSimple( []{}, [&imageBuffer]{ CVPixelBufferUnlockBaseAddress(imageBuffer, 0); } );
	if (CVPixelBufferLockBaseAddress(imageBuffer, 0) != kCVReturnSuccess)
	{
		mParent.OnFailedFrame("failed to lock new sample buffer");
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
	
	//	gr: find this out! but currently, 4 channels from built in camera gives us BGRA (not sure what alpha is)
	auto Format = (ChannelCount ==4) ? SoyPixelsFormat::BGRA : SoyPixelsFormat::GetFormatFromChannelCount( ChannelCount );
	if ( !Pixels.Init( Width, Height, Format ) )
	{
		std::stringstream Error;
		Error << "AVCapture failed to create pixels " << Width << "x" << Height << " as " << Format;
		mParent.OnFailedFrame( Error.str() );
		return;
	}

	Pixels.GetPixelsArray().Copy( DataArray );
	mParent.OnNewFrame( Pixels, SoyTime() );
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


class TSortPolicy_BestVideoMeta : public TSortPolicy<TVideoDeviceMeta>
{
public:
	TSortPolicy_BestVideoMeta(const std::string& Serial)
	{
		mMatchSerial = Serial;
	}
	
	template<typename TYPEB>
	static int		Compare(const TVideoDeviceMeta& a,const TYPEB& b)
	{
		bool aExactSerial = a.mSerial == mMatchSerial;
		bool bExactSerial = b.mSerial == mMatchSerial;
		if ( aExactSerial && !bExactSerial )	return -1;
		if ( !aExactSerial && bExactSerial )	return 1;

		bool aExactName = a.mName == mMatchSerial;
		bool bExactName = b.mName == mMatchSerial;
		if ( aExactName && !bExactName )	return -1;
		if ( !aExactName && bExactName )	return 1;
		
		bool aSerialStartsWith = Soy::StringBeginsWith( a.mSerial, mMatchSerial, false );
		bool bSerialStartsWith = Soy::StringBeginsWith( b.mSerial, mMatchSerial, false );
		if ( aSerialStartsWith && !bSerialStartsWith )	return -1;
		if ( !aSerialStartsWith && bSerialStartsWith )	return 1;
		
		bool aNameStartsWith = Soy::StringBeginsWith( a.mName, mMatchSerial, false );
		bool bNameStartsWith = Soy::StringBeginsWith( b.mName, mMatchSerial, false );
		if ( aNameStartsWith && !bNameStartsWith )	return -1;
		if ( !aNameStartsWith && bNameStartsWith )	return 1;
		
		std::stringstream Error;
		Error << "Need some more sorting comparisons for [" << mMatchSerial << "] with [" << a.mSerial << "/" << a.mName << "] and [" << b.mSerial << "/" << b.mName << "]";
		Soy::Assert( false, Error );
		return 0;
	}

private:
	static std::string		mMatchSerial;	//	gr: need a better way of having variables in sort policies
};
std::string TSortPolicy_BestVideoMeta::mMatchSerial;


TVideoDeviceMeta SoyVideoCapture::GetDeviceMeta(std::string Serial)
{
	Array<TVideoDeviceMeta> Metas;
	GetDevices( GetArrayBridge(Metas) );
	return GetBestDeviceMeta( Serial, GetArrayBridge(Metas) );
}



int DoTest()
{
	TVideoDeviceMeta MetasDef[] =
	{
		TVideoDeviceMeta("123456789", "Camera" ),
		TVideoDeviceMeta("123456780", "Camera 2" ),
		TVideoDeviceMeta("cameraX", "Left Camera" ),
	};
	BufferArray<TVideoDeviceMeta,100> Metas;

	Metas = BufferArray<TVideoDeviceMeta,100>(MetasDef);
	TVideoDeviceMeta BestMetaA = SoyVideoCapture::GetBestDeviceMeta("Camera", GetArrayBridge(Metas) );
	Soy::Assert( BestMetaA.mSerial == MetasDef[0].mSerial, "Wrong match" );
	
	Metas = BufferArray<TVideoDeviceMeta,100>(MetasDef);
	TVideoDeviceMeta BestMetaB = SoyVideoCapture::GetBestDeviceMeta("Camera 2", GetArrayBridge(Metas) );
	Soy::Assert( BestMetaB.mSerial == MetasDef[1].mSerial, "Wrong match" );
	
	Metas = BufferArray<TVideoDeviceMeta,100>(MetasDef);
	TVideoDeviceMeta BestMetaC = SoyVideoCapture::GetBestDeviceMeta("left", GetArrayBridge(Metas) );
	Soy::Assert( BestMetaC.mSerial == MetasDef[2].mSerial, "Wrong match" );
	
	Metas = BufferArray<TVideoDeviceMeta,100>(MetasDef);
	TVideoDeviceMeta BestMetaD = SoyVideoCapture::GetBestDeviceMeta("123456789", GetArrayBridge(Metas) );
	Soy::Assert( BestMetaD.mSerial == MetasDef[0].mSerial, "wrong match" );
	
	return 0;
	
}
int gfgfdg = DoTest();



TVideoDeviceMeta SoyVideoCapture::GetBestDeviceMeta(std::string Serial,ArrayBridge<TVideoDeviceMeta>&& Metas)
{
	//	get all meta's first and filter until we find the best
	//	this way we can match serial, name, and odd names (eg. "Camera" and "Camera 2") properly
	//	"Cam" will find "Camera" and "Camera2" (so whichever is first), but "Camera" will find camera
	
	//	standard meta==string filter
	for ( int m=Metas.GetSize()-1;	m>=0;	m-- )
	{
		auto& Meta = Metas[m];
		if ( Meta == Serial )
			continue;
		Metas.RemoveBlock( m, 1 );
	}
	
	if ( Metas.IsEmpty() )
		return TVideoDeviceMeta();

	auto SortArray = GetSortArray( Metas, TSortPolicy_BestVideoMeta(Serial) );
	SortArray.Sort();
	
	Soy::Assert( SortArray[0] == Serial, "Error in Meta==String" );
	
	return SortArray[0];
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
	
	//	in case we've provided the name, find the proper serial
	auto Meta = GetDeviceMeta( Serial );
	if ( !Meta.IsValid() )
	{
		Error << "Unknown device " << Serial << " (meta not found)";
		return nullptr;
	}
	
	//	create new device
	//	gr: todo: work out which type this is (from different type's list?)
	std::stringstream InitError;
	std::shared_ptr<TVideoDevice_AvFoundation> Device( new TVideoDevice_AvFoundation( Meta.mSerial, InitError ) );

	//	gr: require meta to be valid immediately, otherwise we assume the device failed to be created
	if ( !Device->GetMeta().IsValid() )
	{
		Error << "Failed to initialise device " << Serial << " " << InitError.str();
		return nullptr;
	}
	
	//	if there was some error/debug at init... include it
	Error << InitError.str();
	
	mDevices.PushBack( Device );
	return Device;
}


TVideoDevice_AvFoundation::TVideoDevice_AvFoundation(std::string Serial,std::stringstream& Error) :
	TVideoDevice				( Serial, Error ),
	mConfigurationStackCounter	( 0 ),
	mWrapper					( new AVCaptureSessionWrapper(*this) )
{
	run( Serial, TVideoQuality::Low, Error );
	if ( !Error.str().empty() )
		OnFailedFrame( Error.str() );
}

TVideoDevice_AvFoundation::~TVideoDevice_AvFoundation()
{
	Pause();
}

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
