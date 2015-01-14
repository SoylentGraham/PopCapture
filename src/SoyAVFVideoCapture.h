#pragma once

#include <SoyVideoDevice.h>


class AVCaptureSessionWrapper;

class TVideoDevice_AvFoundation : public TVideoDevice
{
public:
	friend class AVCaptureSessionWrapper;
	static void					GetDevices(ArrayBridge<TVideoDeviceMeta>& Metas);
	
public:
	TVideoDevice_AvFoundation(const TVideoDeviceMeta& Meta,std::stringstream& Error);
	virtual ~TVideoDevice_AvFoundation();
	
	virtual TVideoDeviceMeta	GetMeta() const override;		//	gr: make this dynamic so other states might change
	
	virtual bool				GetOption(TVideoOption::Type Option,bool Default=false) override;
	virtual bool				SetOption(TVideoOption::Type Option,bool Enable) override;
	
private:
	bool	setFocusLocked(bool Enable);
	bool	setWhiteBalanceLocked(bool Enable);
	bool	setExposureLocked(bool Enable);
	
	bool	BeginConfiguration();
	bool	EndConfiguration();
	bool	run(const std::string& Serial,TVideoDeviceParams& Params,std::stringstream& Error);
	
	bool	Play();
	void	Pause();
	
public:
	std::shared_ptr<AVCaptureSessionWrapper>	mWrapper;
	int							mConfigurationStackCounter;
};


class SoyVideoContainer_AvFoundation : public SoyVideoContainer
{
public:
	virtual void					GetDevices(ArrayBridge<TVideoDeviceMeta>& Metas) override;
	virtual std::shared_ptr<TVideoDevice>	AllocDevice(const TVideoDeviceMeta& Meta,std::stringstream& Error) override;
	
};