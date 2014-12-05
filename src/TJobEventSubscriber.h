#pragma once
#include <ofxSoylent.h>
#include <TJob.h>


class TChannel;


//	event triggered
//	find all channel metas who subscribed
//	send them a job(with specific command) with event param as default

class TEventSubscription
{
public:
	TJobChannelMeta		mClient;	//	where to send event
	std::string			mCommand;	//	outgoing job will have this command
};


class TEventSubscriptionManager
{
public:
	TEventSubscriptionManager(std::string EventName) :
		mEventName		( EventName )
	{
	}

	virtual bool			AddSubscriber(TJobChannelMeta Client,std::stringstream& Error)=0;
	
protected:
	std::string				mEventName;	//	"subscribe me to <eventname>"
	ofMutexT<Array<TEventSubscriptionManager>>	mEventClients;
};


template<typename EVENTPARAM>
class TEventSubscriptionManager_Instance : public TEventSubscriptionManager
{
public:
	TEventSubscriptionManager_Instance(SoyEvent<EVENTPARAM>& Event,std::string EventName) :
		TEventSubscriptionManager	( EventName ),
		mEvent						( Event )
	{
	}
	
	virtual bool			AddSubscriber(TJobChannelMeta Client,std::stringstream& Error) override;
	void					OnEvent(EVENTPARAM& Param);
	
public:
	SoyEvent<EVENTPARAM>&	mEvent;
};


class TSubscriberManager
{
public:
	template<typename EVENTPARAM>
	std::shared_ptr<TEventSubscriptionManager>	AddEvent(SoyEvent<EVENTPARAM>& Event,std::string EventName,std::stringstream& Error)
	{
		//	todo: check if this already exists!
		std::shared_ptr<TEventSubscriptionManager> EventSubscriber( new TEventSubscriptionManager_Instance<EVENTPARAM>( Event, EventName ) );
		mEvents.PushBack( EventSubscriber );
		return EventSubscriber;
	}

	bool			AddSubscriber(std::string EventName,TJobChannelMeta Client,std::stringstream& Error);


public:
	Array<std::shared_ptr<TEventSubscriptionManager>>	mEvents;
};

//	does the job handler for you
class TEasySubscriberManager : public TSubscriberManager
{
public:
	TEasySubscriberManager(TJobHandler& JobHandler,std::string SubscriberCommand="subscribe");
	
	void			RegisterSubscribeJob(TJobHandler& JobHandler,std::string SubscriberCommand);
	
private:
	void			OnSubscribe(TJobAndChannel& JobAndChannel);
	
};




template<typename EVENTPARAM>
inline bool TEventSubscriptionManager_Instance<EVENTPARAM>::AddSubscriber(TJobChannelMeta Client,std::stringstream& Error)
{
	//	make a lambda to recieve the event
	auto Callback = [Client](EVENTPARAM& Value)
	{
		TJob OutputJob;
		
		OutputJob.mParams.AddDefaultParam( Value );
		
		//	find channel, send to Client
		std::Debug << "Got event callback to send to " << Client << std::endl;
	};
	mEvent.AddListener( Callback );
	return true;
}

