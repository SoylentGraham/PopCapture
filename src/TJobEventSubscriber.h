#pragma once
#include <ofxSoylent.h>
#include <TJob.h>


class TChannel;
class TSubscriberManager;
class TChannelManager;


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
	TEventSubscriptionManager(std::string EventName,TSubscriberManager& Parent) :
		mEventName		( EventName ),
		mParent			( Parent )
	{
	}

	virtual bool			AddSubscriber(TJobChannelMeta Client,std::stringstream& Error)=0;

protected:
	bool					SendSubscriptionJob(TJob& Job,TJobChannelMeta Client );
	
protected:
	std::string				mEventName;	//	"subscribe me to <eventname>"
	ofMutexT<Array<TEventSubscriptionManager>>	mEventClients;

private:
	TSubscriberManager&		mParent;
};


template<typename EVENTPARAM>
class TEventSubscriptionManager_Instance : public TEventSubscriptionManager
{
public:
	TEventSubscriptionManager_Instance(SoyEvent<EVENTPARAM>& Event,std::string EventName,TSubscriberManager& Parent) :
		TEventSubscriptionManager	( EventName, Parent ),
		mEvent						( Event )
	{
	}
	
	virtual bool			AddSubscriber(TJobChannelMeta Client,std::stringstream& Error) override;
	void					OnEvent(EVENTPARAM& Param);
	
public:
	SoyEvent<EVENTPARAM>&	mEvent;
	
private:
	Array<std::tuple<TJobChannelMeta,std::function<void(EVENTPARAM&)>>>	mSubscriberCallbacks;	//	list of callbacks to clean up if we unsubscribe
};


class TSubscriberManager
{
public:
	TSubscriberManager(TChannelManager& ChannelManager) :
		mChannelManager	( ChannelManager )
	{
	}
	
	template<typename EVENTPARAM>
	std::shared_ptr<TEventSubscriptionManager>	AddEvent(SoyEvent<EVENTPARAM>& Event,std::string EventName,std::stringstream& Error)
	{
		//	todo: check if this already exists!
		std::shared_ptr<TEventSubscriptionManager> EventSubscriber( new TEventSubscriptionManager_Instance<EVENTPARAM>( Event, EventName, *this ) );
		mEvents.PushBack( EventSubscriber );
		return EventSubscriber;
	}

	bool						AddSubscriber(std::string EventName,TJobChannelMeta Client,std::stringstream& Error);
	std::shared_ptr<TChannel>	GetChannel(SoyRef Channel);

public:
	Array<std::shared_ptr<TEventSubscriptionManager>>	mEvents;
	TChannelManager&			mChannelManager;
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

class TVideoDevice;
std::shared_ptr<MemFileArray> UpdateFrameMemFile(TVideoDevice& Device,std::stringstream& Error);


template<typename EVENTPARAM>
inline bool TEventSubscriptionManager_Instance<EVENTPARAM>::AddSubscriber(TJobChannelMeta Client,std::stringstream& Error)
{
	//	make a lambda to recieve the event
	std::function<void(EVENTPARAM&)> ListenerCallback = [this,Client](EVENTPARAM& Value)
	{
		TJob OutputJob;
		auto& Reply = OutputJob;
		
		//	gr; obviously need to make this generic
		
		auto& Device = Value;
		std::stringstream Error;
		//	grab pixels
		bool AsMemFile = true;
		auto& LastFrame = Device.GetLastFrame(Error);
		if ( LastFrame.IsValid() )
		{
			std::shared_ptr<MemFileArray> MemFile;
			if ( AsMemFile )
				MemFile = UpdateFrameMemFile( Device, Error );
			
			if ( MemFile )
			{
				TYPE_MemFile MemFileData( *MemFile );
				Reply.mParams.AddDefaultParam( MemFileData );
			}
			else
			{
				Reply.mParams.AddDefaultParam( LastFrame.GetPixelsConst() );
			}
		}
		
		//	add error if present (last frame could be out of date)
		if ( !Error.str().empty() )
			Reply.mParams.AddErrorParam( Error.str() );
		
		//	find channel, send to Client
	//	std::Debug << "Got event callback to send to " << Client << std::endl;
		
		if ( !this->SendSubscriptionJob( Reply, Client ) )
		{
			//	unsubscibe on failure!
		}
	};
	
	//	add to listeners we need to remove when unsubscribing
	//	gr: maybe map, but I guess it's possible to have ONE client subscrube to this event multiple times...
	mSubscriberCallbacks.PushBack( std::make_tuple(Client,ListenerCallback) );

	//	subscribe this lambda to the event
	mEvent.AddListener( ListenerCallback );
	return true;
}

