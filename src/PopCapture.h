#pragma once
#include <ofxSoylent.h>
#include <SoyApp.h>
#include <TJob.h>
#include "SoyAVFVideoCapture.h"
#include "TJobEventSubscriber.h"

class TChannel;



class TChannelManager
{
public:
	virtual void				AddChannel(std::shared_ptr<TChannel> Channel);
	std::shared_ptr<TChannel>	GetChannel(SoyRef Channel);
	
public:
	std::vector<std::shared_ptr<TChannel>>		mChannels;
};


class TPopCapture : public SoyApp, public TJobHandler, public TChannelManager
{
public:
	TPopCapture();
	
	virtual void	AddChannel(std::shared_ptr<TChannel> Channel) override;
	virtual bool	Update()	{	return mRunning;	}

	void			OnListDevices(TJobAndChannel& JobAndChannel);
	void			OnExit(TJobAndChannel& JobAndChannel);
	void			GetFrame(TJobAndChannel& JobAndChannel);
	void			SubscribeNewFrame(TJobAndChannel& JobAndChannel);
	
public:
	
	bool				mRunning;
	
	SoyVideoCapture		mCoreVideo;
	TSubscriberManager	mSubcriberManager;
	std::shared_ptr<MemFileArray>	mFrameMemFile;
	SoyMemFileManager	mFileManager;
};



