#pragma once


#include <array.hpp>

class VideoCapturePIMPL;


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
	
public:
	std::string	mName;
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

    
    static bool available();
    
public:
    SoyVideoCapture();
    virtual ~SoyVideoCapture();
	
	void	GetDevices(ArrayBridge<TVideoDeviceMeta>&& Metas);
    
    // use deviceIndex == -1 to use default camera
    void Open(Quality quality = VideoCaptureQuality_Medium, int deviceIndex = -1);
    void Close();
    
    void setFlags(int flag);
    void removeFlags(int flag);
    
    virtual void onVideoFrame(const FrameData& frame) = 0;
    
private:
    friend class VideoCapturePIMPL;
    VideoCapturePIMPL* pimpl;
    int deviceIndex;
};

