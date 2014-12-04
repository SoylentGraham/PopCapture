#pragma once


#include <array.hpp>
#include <heaparray.hpp>
#include <SoyEvent.h>
#include <SoyPixels.h>
#include <SoyTime.h>



class TVideoDeviceMeta
{
public:
	TVideoDeviceMeta() :
		mVideo			( false ),
		mAudio			( false ),
		mText			( false ),
		mClosedCaption	( false ),
		mSubtitle		( false ),
		mTimecode		( false ),
		mTimedMetadata	( false ),
		mMetadata		( false ),
		mMuxed			( false )
	{
		Soy::Assert( !IsValid(), "expected invalid" );
	}
	
	bool		IsValid() const		{	return !mName.empty();	}
	bool		operator==(const std::string& Serial) const	{	return mSerial == Serial;	}
	
public:
	std::string	mName;
	std::string	mModel;
	std::string	mVendor;
	std::string	mSerial;
	bool		mConnected;
	bool		mVideo;
	bool		mAudio;
	bool		mText;
	bool		mClosedCaption;
	bool		mSubtitle;
	bool		mTimecode;
	bool		mTimedMetadata;
	bool		mMetadata;
	bool		mMuxed;
};

namespace TVideoQuality
{
	enum Type
	{
		Low,
		Medium,
		High,
	};
}
namespace TVideoOption
{
	enum Type
	{
		LockedFocus,
		LockedWhiteBalance,
		LockedExposure,
	};
}

//	seperate type for meta so we can have timecode
class TVideoFrame
{
public:
	bool			IsValid() const		{	return mPixels.IsValid();	}

public:
	SoyPixels		mPixels;
	SoyTime			mTimecode;
};


//	gr: currently RAII so no play/pause virtuals...
class TVideoDevice
{
public:
	TVideoDevice(std::string Serial,std::stringstream& Error);
	virtual ~TVideoDevice();
	
	virtual TVideoDeviceMeta	GetMeta() const=0;		//	gr: make this dynamic so other states might change
	std::string					GetSerial() const		{	return GetMeta().mSerial;	}
	const TVideoFrame&			GetLastFrame(std::stringstream& Error) const	{	Error << mLastError;	return mLastFrame;	}
	
	//	gr: might need to report if supported
	virtual bool				GetOption(TVideoOption::Type Option,bool Default=false)	{	return Default;	}
	virtual bool				SetOption(TVideoOption::Type Option,bool Enable)		{	return false;	}
	
	bool						operator==(const std::string& Serial) const				{	return GetMeta() == Serial;	}
	
protected:
	void						OnFailedFrame(const std::string& Error);
	void						OnNewFrame(const SoyPixelsImpl& Pixels,SoyTime Timecode);
	
public:
	SoyEvent<const TVideoFrame>	mOnNewFrame;
	
private:
	//	gr: video frame can cope without a lock,(no realloc) but the string will probably crash
	std::string					mLastError;		//	should be empty if last frame was okay
	TVideoFrame					mLastFrame;
};


class AVCaptureSessionWrapper;

class TVideoDevice_AvFoundation : public TVideoDevice
{
public:
	friend class AVCaptureSessionWrapper;
	static void					GetDevices(ArrayBridge<TVideoDeviceMeta>& Metas);
	
public:
	TVideoDevice_AvFoundation(std::string Serial,std::stringstream& Error);
	virtual ~TVideoDevice_AvFoundation();

	virtual TVideoDeviceMeta	GetMeta() const override;		//	gr: make this dynamic so other states might change

	virtual bool				GetOption(TVideoOption::Type Option,bool Default=false) override;
	virtual bool				SetOption(TVideoOption::Type Option,bool Enable) override;

private:
	bool setFocusLocked(bool Enable);
	bool setWhiteBalanceLocked(bool Enable);
	bool setExposureLocked(bool Enable);

	bool						BeginConfiguration();
	bool						EndConfiguration();
	bool	run(const std::string& Serial,TVideoQuality::Type Quality,std::stringstream& Error);

	bool	Play();
	void	Pause();
	
public:
	std::shared_ptr<AVCaptureSessionWrapper>	mWrapper;
	int							mConfigurationStackCounter;
};


class SoyVideoCapture //: public EventReceiver
{
public:
    
    struct FrameData
    {
        int w;
        int h;
        
        char* data;
        int dataSize;
        int rowSize;
        
        FrameData() : data(0), dataSize(0)
        { }
    };
    
    enum Flags
    {
        VideoCaptureFlag_LockFocus = 0x01,
        VideoCaptureFlag_LockWhiteBalance = 0x02,
        VideoCaptureFlag_LockExposure = 0x04,
        
        VideoCaptureFlag_LockAllParameters =
        VideoCaptureFlag_LockFocus | VideoCaptureFlag_LockWhiteBalance | VideoCaptureFlag_LockExposure
    };
    
    enum Quality
    {
        VideoCaptureQuality_Low,
        VideoCaptureQuality_Medium,
        VideoCaptureQuality_High
    };
	
public:
    SoyVideoCapture();
    virtual ~SoyVideoCapture();
	
	std::shared_ptr<TVideoDevice>	GetDevice(std::string Serial,std::stringstream& Error);
	void							GetDevices(ArrayBridge<TVideoDeviceMeta>&& Metas);
	void							CloseDevice(std::string Serial);
	
private:
	Array<std::shared_ptr<TVideoDevice>> mDevices;
};

