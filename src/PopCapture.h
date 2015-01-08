#pragma once
#include <ofxSoylent.h>
#include <SoyApp.h>
#include <TJob.h>
#include "SoyAVFVideoCapture.h"
#include <TJobEventSubscriber.h>
#include <TChannel.h>




class TPopCapture : public TJobHandler, public TChannelManager
{
public:
	TPopCapture();
	
	virtual void	AddChannel(std::shared_ptr<TChannel> Channel) override;

	void			OnListDevices(TJobAndChannel& JobAndChannel);
	void			OnExit(TJobAndChannel& JobAndChannel);
	void			GetFrame(TJobAndChannel& JobAndChannel);
	void			SubscribeNewFrame(TJobAndChannel& JobAndChannel);
	
public:
	Soy::Platform::TConsoleApp	mConsoleApp;
	SoyVideoCapture		mVideoCapture;
	TSubscriberManager	mSubcriberManager;
};



