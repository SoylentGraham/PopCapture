#include "PopCapture.h"
#include <TParameters.h>
#include <SoyDebug.h>
#include <TProtocolCli.h>
#include <TProtocolHttp.h>
#include <SoyApp.h>
#include <PopMain.h>
#include <TJobRelay.h>
#include <SoyPixels.h>
#include <SoyString.h>
#include <SoyJson.h>	//	just for test
#include <TChannelLiteral.h>


TPopCapture::TPopCapture() :
	mSubcriberManager	( *this )
{
	//	add video contaienr
	std::shared_ptr<SoyVideoContainer> AvFoundationContainer( new SoyVideoContainer_AvFoundation() );
	mVideoCapture.AddContainer( AvFoundationContainer );
	
	AddJobHandler("exit", TParameterTraits(), *this, &TPopCapture::OnExit );
	AddJobHandler("list", TParameterTraits(), *this, &TPopCapture::OnListDevices );

	TParameterTraits GetFrameTraits;
	GetFrameTraits.mAssumedKeys.PushBack("serial");
	AddJobHandler("getframe", GetFrameTraits, *this, &TPopCapture::GetFrame );

	//	we need extra params for this subscription to say WHICH device we want to subscribe to
	//	we create the new subscriptions
	TParameterTraits SubscribeNewFrameTraits;
	SubscribeNewFrameTraits.mAssumedKeys.PushBack("serial");
	SubscribeNewFrameTraits.mDefaultParams.PushBack( std::make_tuple(std::string("command"),std::string("newframe")) );
	AddJobHandler("subscribenewframe", SubscribeNewFrameTraits, *this, &TPopCapture::SubscribeNewFrame );
}

void TPopCapture::AddChannel(std::shared_ptr<TChannel> Channel)
{
	TChannelManager::AddChannel( Channel );
	if ( !Channel )
		return;
	TJobHandler::BindToChannel( *Channel );
}


void TPopCapture::OnExit(TJobAndChannel& JobAndChannel)
{
	mConsoleApp.Exit();
	
	//	should probably still send a reply
	TJobReply Reply( JobAndChannel );
	Reply.mParams.AddDefaultParam(std::string("exiting..."));
	TChannel& Channel = JobAndChannel;
	Channel.OnJobCompleted( Reply );
}

void TPopCapture::OnListDevices(TJobAndChannel& JobAndChannel)
{
	TJobReply Reply( JobAndChannel );

	Array<TVideoDeviceMeta> Metas;
	mVideoCapture.GetDevices( GetArrayBridge(Metas) );

	std::stringstream MetasString;
	for ( int i=0;	i<Metas.GetSize();	i++ )
	{
		auto& Meta = Metas[i];
		if ( i > 0 )
			MetasString << ",";

		MetasString << Meta;
	}
	
	Reply.mParams.AddDefaultParam( MetasString.str() );

	TChannel& Channel = JobAndChannel;
	Channel.OnJobCompleted( Reply );
}


void TPopCapture::GetFrame(TJobAndChannel& JobAndChannel)
{
	const TJob& Job = JobAndChannel;
	TJobReply Reply( JobAndChannel );
	
	auto Serial = Job.mParams.GetParamAs<std::string>("serial");
	auto AsMemFile = Job.mParams.GetParamAsWithDefault<bool>("memfile",true);

	std::stringstream Error;
	auto Device = mVideoCapture.GetDevice( Serial, Error );
	
	if ( !Device )
	{
		std::stringstream ReplyError;
		ReplyError << "Device " << Serial << " not found " << Error.str();
		Reply.mParams.AddErrorParam( ReplyError.str() );
		TChannel& Channel = JobAndChannel;
		Channel.OnJobCompleted( Reply );
		return;
	}
	
	//	grab pixels
	auto& LastFrame = Device->GetLastFrame( Error );
	if ( LastFrame.IsValid() )
	{
		if ( AsMemFile )
		{
			TYPE_MemFile MemFile( LastFrame.mPixels.mMemFileArray );
			TJobFormat Format;
			Format.PushFirstContainer( Soy::GetTypeName<SoyPixels>() );
			Format.PushFirstContainer( Soy::GetTypeName<Array<char>>() );
			Format.PushFirstContainer( Soy::GetTypeName<TYPE_MemFile>() );
			Reply.mParams.AddDefaultParam( MemFile, Format );
		}
		else
		{
			SoyPixels Pixels;
			Pixels.Copy( LastFrame.mPixels );
			Reply.mParams.AddDefaultParam( Pixels );
		}
	}

	//	add error if present (last frame could be out of date)
	if ( !Error.str().empty() )
		Reply.mParams.AddErrorParam( Error.str() );

	//	add other stats
	auto FrameRate = Device->GetFps();
	auto FrameMs = Device->GetFrameMs();
	Reply.mParams.AddParam("fps", FrameRate);
	Reply.mParams.AddParam("framems", FrameMs );
	Reply.mParams.AddParam("serial", Device->GetMeta().mSerial );
	
	TChannel& Channel = JobAndChannel;
	Channel.OnJobCompleted( Reply );
	
}

void TPopCapture::SubscribeNewFrame(TJobAndChannel& JobAndChannel)
{
	const TJob& Job = JobAndChannel;
	TJobReply Reply( JobAndChannel );

	std::stringstream Error;

	//	get device
	auto Serial = Job.mParams.GetParamAs<std::string>("serial");
	auto Device = mVideoCapture.GetDevice( Serial, Error );
	if ( !Device )
	{
		std::stringstream ReplyError;
		ReplyError << "Device " << Serial << " not found " << Error.str();
		Reply.mParams.AddErrorParam( ReplyError.str() );
		TChannel& Channel = JobAndChannel;
		Channel.OnJobCompleted( Reply );
		return;
	}
	
	auto AsMemFile = Job.mParams.GetParamAsWithDefault<bool>("memfile",false);

	//	create new subscription for it
	//	gr: determine if this already exists!
	auto EventName = Job.mParams.GetParamAs<std::string>("command");
	auto Event = mSubcriberManager.AddEvent( Device->mOnNewFrame, EventName, Error );
	if ( !Event )
	{
		std::stringstream ReplyError;
		ReplyError << "Failed to create new event " << EventName << ". " << Error.str();
		Reply.mParams.AddErrorParam( ReplyError.str() );
		TChannel& Channel = JobAndChannel;
		Channel.OnJobCompleted( Reply );
		return;
	}
	
	//	make a lambda to recieve the event
	auto Client = Job.mChannelMeta;
	TEventSubscriptionCallback<TVideoDevice> ListenerCallback = [Client,AsMemFile](TEventSubscriptionManager& SubscriptionManager,TVideoDevice& Value)
	{
		TJob OutputJob;
		auto& Reply = OutputJob;
		
		auto& Device = Value;
		std::stringstream Error;
		//	grab pixels
		auto& LastFrame = Device.GetLastFrame(Error);
		if ( LastFrame.IsValid() )
		{
			if ( AsMemFile )
			{
				auto& MemFile = LastFrame.mPixels.mMemFileArray;
				TYPE_MemFile MemFileData( MemFile );
				Reply.mParams.AddDefaultParam( MemFileData );
			}
			else
			{
				SoyPixels Pixels;
				Pixels.Copy( LastFrame.mPixels );
				Reply.mParams.AddDefaultParam( Pixels );
			}
			
			Reply.mParams.AddParam("timecode", LastFrame.mTimecode );
		}
		
		//	add other meta
		Reply.mParams.AddParam("serial", Device.GetSerial() );
	
		//	add error if present (last frame could be out of date)
		if ( !Error.str().empty() )
			Reply.mParams.AddErrorParam( Error.str() );
		
		//	find channel, send to Client
		//	std::Debug << "Got event callback to send to " << Client << std::endl;
		
		if ( !SubscriptionManager.SendSubscriptionJob( Reply, Client ) )
			return false;
		
		return true;
	};
	
	//	subscribe this caller
	if ( !Event->AddSubscriber( Job.mChannelMeta, ListenerCallback, Error ) )
	{
		std::stringstream ReplyError;
		ReplyError << "Failed to add subscriber to event " << EventName << ". " << Error.str();
		Reply.mParams.AddErrorParam( ReplyError.str() );
		TChannel& Channel = JobAndChannel;
		Channel.OnJobCompleted( Reply );
		return;
	}

	
	std::stringstream ReplyString;
	ReplyString << "OK subscribed to " << EventName;
	Reply.mParams.AddDefaultParam( ReplyString.str() );
	if ( !Error.str().empty() )
		Reply.mParams.AddErrorParam( Error.str() );
	Reply.mParams.AddParam("eventcommand", EventName);

	TChannel& Channel = JobAndChannel;
	Channel.OnJobCompleted( Reply );
}


//	horrible global for lambda
std::shared_ptr<TChannel> gStdioChannel;



TPopAppError::Type PopMain(TJobParams& Params)
{
	//	in future, we're ALWAYS in child mode and caller/bootup.txt can specify what channels to create etc
	bool ChildProcessMode = Params.GetParamAsWithDefault("childmode", false );
	bool BinaryStdio = Params.GetParamAsWithDefault("binarystdio", false );

	//	dont debug to stdout if we're using it for comms!
	if ( ChildProcessMode )
		std::Debug.EnableStdOut(false);
	
	//	job handler
	TPopCapture App;

	//	create stdio channel
	std::string stdioChannelSpec = "std:";
	if ( BinaryStdio )
		stdioChannelSpec += "binaryin,binaryout";
	
	gStdioChannel = CreateChannelFromInputString(stdioChannelSpec, SoyRef("stdio") );
	App.AddChannel( gStdioChannel );

	
	static bool TestGenericForkChannel = false;
	if ( TestGenericForkChannel )
	{
		auto PwdChannel = CreateChannelFromInputString("fork:pwd", SoyRef("pwd") );
		App.AddChannel( PwdChannel );
	}
	
	if ( !ChildProcessMode )
	{
		auto CommandLineChannel = std::shared_ptr<TChan<TChannelLiteral,TProtocolCli>>( new TChan<TChannelLiteral,TProtocolCli>( SoyRef("cmdline") ) );
		App.AddChannel( CommandLineChannel );

		auto HttpChannel = CreateChannelFromInputString("http:8080-8090", SoyRef("http") );
		auto WebSocketChannel = CreateChannelFromInputString("ws:json:9090-9099", SoyRef("websock") );
		//auto WebSocketChannel = CreateChannelFromInputString("ws:cli:9090-9099", SoyRef("websock") );
		auto SocksChannel = CreateChannelFromInputString("cli:7070", SoyRef("socks") );
	
		App.AddChannel( HttpChannel );
		App.AddChannel( WebSocketChannel );
		App.AddChannel( SocksChannel );
	
		//	when the commandline SENDs a command (a reply), send it to stdout
		auto RelayFunc = [](TJobAndChannel& JobAndChannel)
		{
			if ( !gStdioChannel )
				return;
			TJob Job = JobAndChannel;
			Job.mChannelMeta.mChannelRef = gStdioChannel->GetChannelRef();
			Job.mChannelMeta.mClientRef = SoyRef();
			gStdioChannel->SendCommand( Job );
		};
		gStdioChannel = gStdioChannel;
		CommandLineChannel->mOnJobSent.AddListener( RelayFunc );
	}
	
	//	run until something triggers exit
	App.mConsoleApp.WaitForExit();

	gStdioChannel.reset();
	return TPopAppError::Success;
}




