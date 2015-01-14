#include "SoyAVFVideoCapture.h"

#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
//#import <Accelerate/Accelerate.h>
#include <SoyDebug.h>
#include <SoyScope.h>
#include <SoyString.h>
#include <SortArray.h>


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


@class VideoCaptureProxy;


//	obj-c class wrapper
class AVCaptureSessionWrapper
{
public:
	AVCaptureSessionWrapper(TVideoDevice_AvFoundation& Parent) :
		_session		( nullptr ),
		_proxy			( nullptr ),
		mDevice			( nullptr ),
		mParent			( Parent ),
		mExpectedFormat	( SoyPixelsFormat::Invalid )
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

	SoyPixelsFormat::Type		mExpectedFormat;
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
	
	SoyPixelsFormat::Type Format = mExpectedFormat;

	//	if the format given isn't what we were expecting, accomodate
	int ExpectedChannels = SoyPixelsFormat::GetChannelCount(mExpectedFormat);
	if ( ExpectedChannels != ChannelCount )
	{
		Format = SoyPixelsFormat::GetFormatFromChannelCount( ChannelCount );
		std::Debug << "Expected CF video format " << mExpectedFormat << " but channels were " << ChannelCount << " not " << ExpectedChannels << ". Reverting format to " << Format << std::endl;
	}
	
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

- (void)onVideoError:(NSNotification *)notification;

@end



@implementation VideoCaptureProxy

- (void)onVideoError:(NSNotification *)notification
{
	NSLog(@"Video error: %@", notification.userInfo[AVCaptureSessionErrorKey]);
}

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



void TVideoDevice_AvFoundation::GetDevices(ArrayBridge<TVideoDeviceMeta>& Metas)
{
	NSArray* Devices = [AVCaptureDevice devices];
	
	for (id Device in Devices)
	{
		Metas.PushBack( GetDeviceMeta( Device ));
	}

}



TVideoDevice_AvFoundation::TVideoDevice_AvFoundation(const TVideoDeviceMeta& Meta,std::stringstream& Error) :
	TVideoDevice				( Meta, Error ),
	mConfigurationStackCounter	( 0 ),
	mWrapper					( new AVCaptureSessionWrapper(*this) )
{
	TVideoDeviceParams Params;
	run( Meta.mSerial, Params, Error );
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


#define CV_VIDEO_TYPE_META(Enum,SoyFormat)	TCvVideoTypeMeta( Enum, #Enum, SoyFormat )
#define CV_VIDEO_INVALID_ENUM		0
class TCvVideoTypeMeta
{
public:
	TCvVideoTypeMeta(int Enum,const char* EnumName,SoyPixelsFormat::Type SoyFormat) :
		mEnum		( Enum ),
		mName		( EnumName ),
		mSoyFormat	( SoyFormat )
	{
		Soy::Assert( IsValid(), "Expected valid enum - or invalid enum is bad" );
	}
	TCvVideoTypeMeta() :
		mEnum		( CV_VIDEO_INVALID_ENUM ),
		mName		( "Invalid enum" ),
		mSoyFormat	( SoyPixelsFormat::Invalid )
	{
	}
	
	bool		IsValid() const		{	return mEnum != CV_VIDEO_INVALID_ENUM;	}
	
	bool		operator==(const int& Enum) const	{	return mEnum == Enum;	}
	bool		operator==(const SoyPixelsFormat::Type& Format) const	{	return mSoyFormat == Format;	}
	
public:
	int						mEnum;
	SoyPixelsFormat::Type	mSoyFormat;
	std::string				mName;
};

const TCvVideoTypeMeta VideoTypes[] =
{
	CV_VIDEO_TYPE_META( kCVPixelFormatType_1Monochrome,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_2Indexed,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_4Indexed,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_8Indexed,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_1IndexedGray_WhiteIsZero,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_2IndexedGray_WhiteIsZero,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_4IndexedGray_WhiteIsZero,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_8IndexedGray_WhiteIsZero,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_16BE555,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_16LE555,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_16LE5551,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_16BE565,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_16LE565,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_24RGB,	SoyPixelsFormat::RGB ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_24BGR,	SoyPixelsFormat::BGR ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_32ARGB,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_32BGRA,	SoyPixelsFormat::BGRA ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_32ABGR,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_32RGBA,	SoyPixelsFormat::RGBA ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_64ARGB,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_48RGB,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_32AlphaGray,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_16Gray,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_422YpCbCr8,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_4444YpCbCrA8,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_4444YpCbCrA8R,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_444YpCbCr8,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_422YpCbCr16,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_422YpCbCr10,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_444YpCbCr10,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_420YpCbCr8Planar,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_420YpCbCr8PlanarFullRange,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_422YpCbCr_4A_8BiPlanar,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_422YpCbCr8_yuvs,	SoyPixelsFormat::Invalid ),
	CV_VIDEO_TYPE_META( kCVPixelFormatType_422YpCbCr8FullRange,	SoyPixelsFormat::Invalid ),
};



TCvVideoTypeMeta GetVideoMeta(int Enum)
{
	static const BufferArray<TCvVideoTypeMeta,100> Metas( VideoTypes );
	auto* Meta = Metas.Find( Enum );
	return Meta ? *Meta : TCvVideoTypeMeta();
}

void GetCompatiblePixelFormats(ArrayBridge<TCvVideoTypeMeta>&& CompatibleFormats,NSArray* AvailibleFormats)
{
	for (NSNumber* CvFormat in AvailibleFormats)
	{
		int FormatEnum = [CvFormat intValue];
		auto Meta = GetVideoMeta( FormatEnum );
		if ( !Soy::Assert(Meta.IsValid(), std::stringstream() << "Unknown CV format: " << FormatEnum ) )
			continue;

		//	not a format we can handle
		if ( !SoyPixelsFormat::IsValid( Meta.mSoyFormat) )
			continue;
		
		CompatibleFormats.PushBack( Meta );
	}
}


bool TVideoDevice_AvFoundation::run(const std::string& Serial,TVideoDeviceParams& Params,std::stringstream& Error)
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
	
	Array<TVideoQuality::Type> Qualitys;
	Qualitys.PushBack( Params.mQuality );
	Qualitys.PushBack( TVideoQuality::Low );
	Qualitys.PushBack( TVideoQuality::Medium );
	Qualitys.PushBack( TVideoQuality::High );
	
	while ( !Qualitys.IsEmpty() )
	{
		auto Quality = Qualitys.PopAt(0);
		auto QualityString = GetAVCaptureSessionQuality(Quality);
		
		if ( ![Wrapper._session canSetSessionPreset:QualityString] )
			continue;
		
		Wrapper._session.sessionPreset = QualityString;
		break;
	}
	if ( Qualitys.IsEmpty() )
	{
		Error << "Failed to set a session preset";
		return false;
	}
	
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
 
	//	find compatible soy formats
	Array<TCvVideoTypeMeta> Formats;
	GetCompatiblePixelFormats( GetArrayBridge(Formats), [_output availableVideoCVPixelFormatTypes] );
	
	while ( !Formats.IsEmpty() )
	{
		//	gr: determine "fastest" or "best" format...
		const TCvVideoTypeMeta* BestFormat = &Formats[0];
		if ( Formats.Find( SoyPixelsFormat::RGB ) )
			BestFormat = Formats.Find( SoyPixelsFormat::RGB );
		else if ( Formats.Find( SoyPixelsFormat::RGBA ) )
			BestFormat = Formats.Find( SoyPixelsFormat::RGBA );
		else if ( Formats.Find( SoyPixelsFormat::BGR ) )
			BestFormat = Formats.Find( SoyPixelsFormat::BGR );
		else if ( Formats.Find( SoyPixelsFormat::BGRA ) )
			BestFormat = Formats.Find( SoyPixelsFormat::BGRA );
		
		Wrapper.mExpectedFormat = BestFormat->mSoyFormat;
		
		_output.alwaysDiscardsLateVideoFrames = Params.mDiscardOldFrames ? YES : NO;
		_output.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
								 [NSNumber numberWithInt:BestFormat->mEnum], kCVPixelBufferPixelFormatTypeKey, nil];
		
	
		if ( ![Wrapper._session canAddOutput:_output] )
		{
			Error << "Output " << BestFormat->mName << " not supported by this output device";
			std::Debug << "Output " << BestFormat->mName << " not supported by this output device" << std::endl;
			if ( !Formats.Remove( BestFormat->mEnum ) )
			{
				Soy::Assert( false, "find of current format failed. bail out of infinite loop!");
				Formats.Clear();
				break;
			}
			continue;
		}
		
		
		//	compatible, add
		[Wrapper._session addOutput:_output];
		break;
	}
	
	//	didn't succeed, ran out of formats;
	if ( Formats.IsEmpty() )
	{
		Error << "Could not find compatible pixel format for device" << std::endl;
		return false;
	}
	
	NSNotificationCenter *notify =
	[NSNotificationCenter defaultCenter];
	[notify addObserver: Wrapper._proxy
			   selector: @selector(onVideoError:)
				   name: AVCaptureSessionRuntimeErrorNotification
				 object: Wrapper._session];
	
	//[_output setSampleBufferDelegate:_proxy queue:dispatch_get_main_queue()];
	dispatch_queue_t queue = dispatch_queue_create("camera_queue", NULL);
	[_output setSampleBufferDelegate:Wrapper._proxy queue: queue];
#if !__has_feature(objc_arc)
	dispatch_release(queue);
#endif
	
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


void SoyVideoContainer_AvFoundation::GetDevices(ArrayBridge<TVideoDeviceMeta>& Metas)
{
	TVideoDevice_AvFoundation::GetDevices( Metas );
}

std::shared_ptr<TVideoDevice> SoyVideoContainer_AvFoundation::AllocDevice(const TVideoDeviceMeta& Meta,std::stringstream& Error)
{
	return std::shared_ptr<TVideoDevice>( new TVideoDevice_AvFoundation( Meta, Error ) );
}
