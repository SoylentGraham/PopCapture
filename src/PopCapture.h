#pragma once
#include <ofxSoylent.h>
#include <SoyApp.h>
#include <TJob.h>



class TChannel;


class TPopCapture : public SoyApp, public TJobHandler
{
public:
	TPopCapture();
	
	void			AddChannel(std::shared_ptr<TChannel> Channel);
	virtual bool	Update()	{	return mRunning;	}

	void			OnExit(TJobAndChannel& JobAndChannel);

public:
	std::vector<std::shared_ptr<TChannel>>		mChannels;

	bool			mRunning;
};

