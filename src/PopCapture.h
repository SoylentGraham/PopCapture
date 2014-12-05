#pragma once
#include <ofxSoylent.h>
#include <SoyApp.h>
#include <TJob.h>
#include "SoyAVFVideoCapture.h"


class TChannel;


class TPopCapture : public SoyApp, public TJobHandler
{
public:
	TPopCapture();
	
	void			AddChannel(std::shared_ptr<TChannel> Channel);
	virtual bool	Update()	{	return mRunning;	}

	void			OnListDevices(TJobAndChannel& JobAndChannel);
	void			OnExit(TJobAndChannel& JobAndChannel);
	void			GetFrame(TJobAndChannel& JobAndChannel);

public:
	std::vector<std::shared_ptr<TChannel>>		mChannels;

	bool			mRunning;
	
	SoyVideoCapture	mCoreVideo;
};

