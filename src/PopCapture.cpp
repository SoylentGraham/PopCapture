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




void TVideoCapture::onVideoFrame(const FrameData& frame)
{
	std::Debug << "On new frame" << std::endl;
}



TPopCapture::TPopCapture() :
	mRunning	( true )
{
	AddJobHandler("exit", TParameterTraits(), *this, &TPopCapture::OnExit );
	AddJobHandler("list", TParameterTraits(), *this, &TPopCapture::OnListDevices );

	TParameterTraits GetFrameTraits;
	GetFrameTraits.mAssumedKeys.PushBack("serial");
	AddJobHandler("getframe", GetFrameTraits, *this, &TPopCapture::GetFrame );

}

void TPopCapture::AddChannel(std::shared_ptr<TChannel> Channel)
{
	if ( !Channel )
		return;
	mChannels.push_back( Channel );
	TJobHandler::BindToChannel( *Channel );
}


void TPopCapture::OnExit(TJobAndChannel& JobAndChannel)
{
	mRunning = false;
	
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

void TPopCapture::GetFrame(TJobAndChannel& JobAndChannel)
{
	const TJob& Job = JobAndChannel;
	TJobReply Reply( JobAndChannel );
	
	auto Serial = Job.mParams.GetParamAs<std::string>("serial");

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
	auto LastFrame = Device->GetLastFrame();
	Reply.mParams.AddDefaultParam( LastFrame.mPixels );
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
	
	bool				FixParamFormat(TJobParam& Param,std::stringstream& Error)
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
	virtual bool				SendCommand(const TJob& Job) override
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
	auto SocksChannel = CreateChannelFromInputString("json:7070-7079", SoyRef("socks") );
	
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

	
	//	run
	Soy::Platform::TConsoleApp Console( App );
	auto Result = static_cast<TPopAppError::Type>( Console.RunLoop() );
	gStdioChannel.reset();
	return Result;
}




