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


std::shared_ptr<MemFileArray> TPopCapture::mFrameMemFile;


TPopCapture::TPopCapture() :
	mSubcriberManager	( *this ),
	mFileManager		( "soy" )
{
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
	mCoreVideo.GetDevices( GetArrayBridge(Metas) );

	std::stringstream MetasString;
	for ( int i=0;	i<Metas.GetSize();	i++ )
	{
		auto& Meta = Metas[i];
		if ( i > 0 )
			MetasString << ",";

		MetasString << Meta.mName << "[" << Meta.mSerial << "]";
		if ( Meta.mVideo )	MetasString << " +Video";
		if ( Meta.mAudio )	MetasString << " +Audio";
		if ( Meta.mText )	MetasString << " +Text";
		if ( Meta.mClosedCaption )	MetasString << " +ClosedCaption";
		if ( Meta.mSubtitle )	MetasString << " +Subtitle";
		if ( Meta.mTimecode )	MetasString << " +Timecode";
		if ( Meta.mTimedMetadata )	MetasString << " +TimedMetadata";
		if ( Meta.mMetadata )	MetasString << " +Metadata";
		if ( Meta.mMuxed )	MetasString << " +Muxed";
	}
	
	Reply.mParams.AddDefaultParam( MetasString.str() );

	TChannel& Channel = JobAndChannel;
	Channel.OnJobCompleted( Reply );
}

std::shared_ptr<MemFileArray> TPopCapture::UpdateFrameMemFile(TVideoDevice& Device,std::stringstream& Error)
{
	auto& LastFrame = Device.GetLastFrame(Error);
	if ( !Soy::Assert( LastFrame.IsValid(), "Should have already checked this" ) )
		return nullptr;

	//	get data so we can initialise memfile
	//	gr: todo; write STRAIGHT to memfilearray array
	Array<char> RawSoyPixelsData;
	LastFrame.GetPixelsConst().GetRawSoyPixels( GetArrayBridge(RawSoyPixelsData) );
	
	auto& TargetMemFile = mFrameMemFile;
	
	//	alloc memfile
	if ( !TargetMemFile )
	{
		std::stringstream Filename;
		Filename << "/frame_" << Device.GetSerial();
		TargetMemFile.reset( new MemFileArray( Filename.str(), RawSoyPixelsData.GetDataSize() ) );
		if ( !TargetMemFile->IsValid() )
		{
			TargetMemFile.reset();
			Error << "Failed to alloc memfile";
			return nullptr;
		}
	}
	
	TargetMemFile->Copy( RawSoyPixelsData );

	return TargetMemFile;
}


void TPopCapture::GetFrame(TJobAndChannel& JobAndChannel)
{
	const TJob& Job = JobAndChannel;
	TJobReply Reply( JobAndChannel );
	
	auto Serial = Job.mParams.GetParamAs<std::string>("serial");
	auto AsMemFile = Job.mParams.GetParamAsWithDefault<bool>("memfile",true);

	std::stringstream Error;
	auto Device = mCoreVideo.GetDevice( Serial, Error );
	
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
		std::shared_ptr<MemFileArray> MemFile;
		if ( AsMemFile )
			MemFile = UpdateFrameMemFile( *Device, Error );

		if ( MemFile )
		{
			TYPE_MemFile MemFile( *mFrameMemFile );
			Reply.mParams.AddDefaultParam( MemFile );
		}
		else
		{
			Reply.mParams.AddDefaultParam( LastFrame.GetPixelsConst() );
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
	auto Device = mCoreVideo.GetDevice( Serial, Error );
	if ( !Device )
	{
		std::stringstream ReplyError;
		ReplyError << "Device " << Serial << " not found " << Error.str();
		Reply.mParams.AddErrorParam( ReplyError.str() );
		TChannel& Channel = JobAndChannel;
		Channel.OnJobCompleted( Reply );
		return;
	}

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
	
	//	subscribe this caller
	if ( !Event->AddSubscriber( Job.mChannelMeta, Error ) )
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


class TChannelLiteral : public TChannel
{
public:
	TChannelLiteral(SoyRef ChannelRef) :
	TChannel	( ChannelRef )
	{
	}
	
	virtual void				GetClients(ArrayBridge<SoyRef>&& Clients)
	{

	}
	
	bool				FixParamFormat(TJobParam& Param,std::stringstream& Error) override
	{
		return true;
	}
	void		Execute(std::string Command)
	{
		TJobParams Params;
		Execute( Command, Params );
	}
	void		Execute(std::string Command,const TJobParams& Params)
	{
		auto& Channel = *this;
		TJob Job;
		Job.mParams = Params;
		Job.mParams.mCommand = Command;
		Job.mChannelMeta.mChannelRef = Channel.GetChannelRef();
		Job.mChannelMeta.mClientRef = SoyRef("x");
		
		//	send job to handler
		Channel.OnJobRecieved( Job );
	}
	
	//	we don't do anything, but to enable relay, we say it's "done"
	virtual bool				SendJobReply(const TJobReply& Job) override
	{
		OnJobSent( Job );
		return true;
	}
	virtual bool				SendCommandImpl(const TJob& Job) override
	{
		OnJobSent( Job );
		return true;
	}
};



//	horrible global for lambda
std::shared_ptr<TChannel> gStdioChannel;



TPopAppError::Type PopMain(TJobParams& Params)
{
	std::cout << Params << std::endl;
	
	//	job handler
	TPopCapture App;

	auto CommandLineChannel = std::shared_ptr<TChan<TChannelLiteral,TProtocolCli>>( new TChan<TChannelLiteral,TProtocolCli>( SoyRef("cmdline") ) );
	
	//	create stdio channel for commandline output
	auto StdioChannel = CreateChannelFromInputString("std:", SoyRef("stdio") );
	gStdioChannel = StdioChannel;
	auto HttpChannel = CreateChannelFromInputString("http:8080-8090", SoyRef("http") );
	auto WebSocketChannel = CreateChannelFromInputString("ws:json:9090-9099", SoyRef("websock") );
	//auto WebSocketChannel = CreateChannelFromInputString("ws:cli:9090-9099", SoyRef("websock") );
	auto SocksChannel = CreateChannelFromInputString("cli:7070-7079", SoyRef("socks") );
	
	App.AddChannel( CommandLineChannel );
	App.AddChannel( StdioChannel );
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
	CommandLineChannel->mOnJobSent.AddListener( RelayFunc );

	Array<char> Data;
	Data.SetSize(100);
	Data.SetAll(0x1f);
	App.mFileManager.AllocFile( GetArrayBridge(Data) );
	
	//	run until something triggers exit
	App.mConsoleApp.WaitForExit();

	gStdioChannel.reset();
	return TPopAppError::Success;
}




