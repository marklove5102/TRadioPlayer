unit Radio.Output.WASAPI;

interface

uses
{$IF CompilerVersion >= 23.0}
  Winapi.Windows,
  Winapi.ActiveX,
{$ELSE}
  Windows,
  ActiveX,
{$IFEND}
  System.SysUtils,
  Radio.Output,
  WinApi.CoreAudioApi.AudioClient,
  WinApi.CoreAudioApi.Endpointvolume,
  WinApi.CoreAudioApi.FunctionDiscoveryKeys_devpkey,
  WinApi.CoreAudioApi.MMDevApiUtils,
  WinApi.CoreAudioApi.AudioSessionTypes,
  WinApi.CoreAudioApi.MMDeviceApi,
  WinApi.KsMedia,
  WinApi.WinMM.MMReg,
  WinApi.WinMM.MMeApi,
  Radio.Types;

type
  TPackedWaveFormatEx = packed record
    wFormatTag: Word;
    nChannels: Word;
    nSamplesPerSec: DWORD;
    nAvgBytesPerSec: DWORD;
    nBlockAlign: Word;
    wBitsPerSample: Word;
    cbSize: Word;
  end;

  PPackedWaveFormatExtensible = ^TPackedWaveFormatExtensible;
  TPackedWaveFormatExtensible = packed record
    Format: TPackedWaveFormatEx;
    Samples: packed record
      case Integer of
        0: (wValidBitsPerSample: Word);
        1: (wSamplesPerBlock: Word);
        2: (wReserved: Word);
    end;
    dwChannelMask: DWORD;
    SubFormat: TGUID;
  end;

  TAudioOutputWASAPI = class(TAudioOutput)
  private
    FEnumerator: IMMDeviceEnumerator;
    FDevice: IMMDevice;
    FAudioClient: IAudioClient;
    FRenderClient: IAudioRenderClient;
    FSimpleVolume: ISimpleAudioVolume;
    FEndpointVolume: IAudioEndpointVolume;
    FBufferFrameCount: UINT32;
    FLatencyHns: Int64;
    FStarted: Boolean;
    FDeviceId: string;
    FVolumeMode: TRadioWASAPIVolumeMode;
    procedure ApplyVolume;
    procedure CheckHR(HR: HResult; const Action: string);
    procedure AdoptWaveFormat(const Format: PWAVEFORMATEX);
    procedure SetVolumeMode(const Value: TRadioWASAPIVolumeMode);
    class procedure CheckHRStatic(HR: HResult; const Action: string); static;
    class function GetDeviceIdString(const Device: IMMDevice): string; static;
  public
    constructor Create; override;
    destructor Destroy; override;
    function Open(SampleRate, Channels, BitsPerSample: Integer): Boolean; override;
    procedure Close; override;
    procedure Start; override;
    procedure Stop; override;
    function Write(Buffer: PByte; ByteCount: Integer): Integer; override;
    function GetBufferedBytes: Integer; override;
    function GetLatencyMS: Integer; override;
    procedure SetVolume(const Value: Single); override;
    procedure SetMuted(const Value: Boolean); override;
    class function EnumerateDevices: TRadioWASAPIDeviceInfos; static;
    property DeviceId: string read FDeviceId write FDeviceId;
    property VolumeMode: TRadioWASAPIVolumeMode read FVolumeMode write SetVolumeMode;
  end;

implementation

constructor TAudioOutputWASAPI.Create;
begin
  inherited Create;
  FVolumeMode := rwvmSession;
end;

procedure TAudioOutputWASAPI.AdoptWaveFormat(const Format: PWAVEFORMATEX);
var
  Extensible: PPackedWaveFormatExtensible;
begin
  SampleRate := Format^.nSamplesPerSec;
  Channels := Format^.nChannels;
  BitsPerSample := Format^.wBitsPerSample;

  if Format^.wFormatTag = WAVE_FORMAT_IEEE_FLOAT then
  begin
    if Format^.wBitsPerSample <> 32 then
      raise EAudioOutputError.CreateFmt('Unsupported WASAPI float bit depth %d', [Format^.wBitsPerSample]);
    SampleType := astFloat32
  end
  else if Format^.wFormatTag = WAVE_FORMAT_PCM then
  begin
    if Format^.wBitsPerSample <> 16 then
      raise EAudioOutputError.CreateFmt('Unsupported WASAPI PCM bit depth %d', [Format^.wBitsPerSample]);
    SampleType := astInt16
  end
  else if Format^.wFormatTag = WAVE_FORMAT_EXTENSIBLE then
  begin
    Extensible := PPackedWaveFormatExtensible(Format);
    if IsEqualGUID(Extensible^.SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) then
    begin
      if Format^.wBitsPerSample <> 32 then
        raise EAudioOutputError.CreateFmt('Unsupported WASAPI float bit depth %d', [Format^.wBitsPerSample]);
      SampleType := astFloat32
    end
    else if IsEqualGUID(Extensible^.SubFormat, KSDATAFORMAT_SUBTYPE_PCM) then
    begin
      if Format^.wBitsPerSample <> 16 then
        raise EAudioOutputError.CreateFmt('Unsupported WASAPI PCM bit depth %d', [Format^.wBitsPerSample]);
      SampleType := astInt16
    end
    else
      raise EAudioOutputError.Create('Unsupported WASAPI sub-format');
  end
  else
    raise EAudioOutputError.CreateFmt('Unsupported WASAPI format tag %d', [Format^.wFormatTag]);
end;

procedure TAudioOutputWASAPI.ApplyVolume;
var
  EmptyGuid: TGUID;
  MuteValue: BOOL;
  VolumeValue: Single;
begin
  if Muted then
    MuteValue := True
  else
    MuteValue := False;

  if Muted then
    VolumeValue := 0
  else
    VolumeValue := Volume;

  if ((FVolumeMode = rwvmEndpoint) and Assigned(FEndpointVolume)) or
     (not Assigned(FSimpleVolume) and Assigned(FEndpointVolume)) then
  begin
    FillChar(EmptyGuid, SizeOf(EmptyGuid), 0);
    CheckHR(FEndpointVolume.SetMute(Integer(MuteValue), EmptyGuid), 'IAudioEndpointVolume.SetMute');
    CheckHR(FEndpointVolume.SetMasterVolumeLevelScalar(VolumeValue, nil), 'IAudioEndpointVolume.SetMasterVolumeLevelScalar');
    Exit;
  end;

  if Assigned(FSimpleVolume) then
  begin
    CheckHR(FSimpleVolume.SetMute(MuteValue, nil), 'ISimpleAudioVolume.SetMute');
    CheckHR(FSimpleVolume.SetMasterVolume(VolumeValue, nil), 'ISimpleAudioVolume.SetMasterVolume');
  end;
end;

procedure TAudioOutputWASAPI.CheckHR(HR: HResult; const Action: string);
begin
  if Failed(HR) then
    raise EAudioOutputError.CreateFmt('%s failed (0x%.8x)', [Action, Cardinal(HR)]);
end;

class procedure TAudioOutputWASAPI.CheckHRStatic(HR: HResult; const Action: string);
begin
  if Failed(HR) then
    raise EAudioOutputError.CreateFmt('%s failed (0x%.8x)', [Action, Cardinal(HR)]);
end;

procedure TAudioOutputWASAPI.Close;
begin
  Stop;
  FEndpointVolume := nil;
  FSimpleVolume := nil;
  FRenderClient := nil;
  FAudioClient := nil;
  FDevice := nil;
  FEnumerator := nil;
  FBufferFrameCount := 0;
  FLatencyHns := 0;
end;

destructor TAudioOutputWASAPI.Destroy;
begin
  Close;
  inherited Destroy;
end;

class function TAudioOutputWASAPI.EnumerateDevices: TRadioWASAPIDeviceInfos;
  function TryGetFriendlyName(const Device: IMMDevice): string;
  var
    DeviceText: WideString;
  begin
    Result := '';
    DeviceText := '';
    try
      if Succeeded(GetDeviceDescriptions(Device, PKEY_Device_FriendlyName, DeviceText)) then
        Result := DeviceText;
    except
      Result := '';
    end;
  end;
  function TryGetInterfaceName(const Device: IMMDevice): string;
  var
    DeviceText: WideString;
  begin
    Result := '';
    DeviceText := '';
    try
      if Succeeded(GetDeviceDescriptions(Device, PKEY_DeviceInterface_FriendlyName, DeviceText)) then
        Result := DeviceText;
    except
      Result := '';
    end;
  end;
  function TryGetDeviceDescription(const Device: IMMDevice): string;
  var
    DeviceText: WideString;
  begin
    Result := '';
    DeviceText := '';
    try
      if Succeeded(GetDeviceDescriptions(Device, PKEY_Device_DeviceDesc, DeviceText)) then
        Result := DeviceText;
    except
      Result := '';
    end;
  end;
var
  Collection: IMMDeviceCollection;
  CoInitResult: HRESULT;
  Count: UINT;
  DefaultDevice: IMMDevice;
  DefaultId: string;
  Device: IMMDevice;
  Enumerator: IMMDeviceEnumerator;
  I: UINT;
begin
  CoInitResult := CoInitializeEx(nil, COINIT_MULTITHREADED);
  Enumerator := nil;
  Collection := nil;
  DefaultDevice := nil;
  DefaultId := '';
  try
    CheckHRStatic(CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_ALL,
      IID_IMMDeviceEnumerator, Enumerator), 'CoCreateInstance(MMDeviceEnumerator)');

    if Succeeded(Enumerator.GetDefaultAudioEndpoint(eRender, eMultimedia, DefaultDevice)) then
      DefaultId := GetDeviceIdString(DefaultDevice);

    CheckHRStatic(Enumerator.EnumAudioEndpoints(eRender, DEVICE_STATEMASK_ALL, Collection),
      'EnumAudioEndpoints');
    CheckHRStatic(Collection.GetCount(Count), 'IMMDeviceCollection.GetCount');

    SetLength(Result, Count);
    for I := 0 to Count - 1 do
    begin
      Device := nil;
      CheckHRStatic(Collection.Item(I, Device), 'IMMDeviceCollection.Item');
      Result[I].Id := GetDeviceIdString(Device);
      Result[I].FriendlyName := TryGetFriendlyName(Device);
      Result[I].InterfaceName := TryGetInterfaceName(Device);
      Result[I].DeviceDescription := TryGetDeviceDescription(Device);

      CheckHRStatic(Device.GetState(Result[I].State), 'IMMDevice.GetState');
      Result[I].StateText := GetDeviceStateAsString(Result[I].State);
      Result[I].IsDefault := SameText(Result[I].Id, DefaultId);
    end;
  finally
    if (CoInitResult = S_OK) or (CoInitResult = S_FALSE) then
      CoUninitialize;
  end;
end;

function TAudioOutputWASAPI.GetBufferedBytes: Integer;
var
  PaddingFrames: UINT32;
begin
  Result := 0;
  if not Assigned(FAudioClient) then
    Exit;

  if Succeeded(FAudioClient.GetCurrentPadding(PaddingFrames)) then
    Result := Integer(PaddingFrames) * BytesPerFrame;
end;

function TAudioOutputWASAPI.GetLatencyMS: Integer;
begin
  if FLatencyHns > 0 then
    Result := Integer(FLatencyHns div 10000)
  else if (SampleRate > 0) and (BytesPerFrame > 0) then
    Result := (GetBufferedBytes * 1000) div (SampleRate * BytesPerFrame)
  else
    Result := 0;
end;

class function TAudioOutputWASAPI.GetDeviceIdString(const Device: IMMDevice): string;
var
  DeviceId: PWideChar;
begin
  DeviceId := nil;
  CheckHRStatic(Device.GetId(DeviceId), 'IMMDevice.GetId');
  try
    if Assigned(DeviceId) then
      Result := DeviceId
    else
      Result := '';
  finally
    if Assigned(DeviceId) then
      CoTaskMemFree(DeviceId);
  end;
end;

function TAudioOutputWASAPI.Open(SampleRate, Channels, BitsPerSample: Integer): Boolean;
const
  BUFFER_DURATION_HNS = 200 * 10000;
var
  MixFormat: PWAVEFORMATEX;
  RequestedDeviceId: WideString;
  TempInterface: Pointer;
begin
  Close;

  MixFormat := nil;
  CheckHR(CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_ALL, IID_IMMDeviceEnumerator, FEnumerator), 'CoCreateInstance(MMDeviceEnumerator)');
  if FDeviceId <> '' then
  begin
    RequestedDeviceId := FDeviceId;
    CheckHR(FEnumerator.GetDevice(PWideChar(RequestedDeviceId), FDevice), 'GetDevice');
  end
  else
    CheckHR(FEnumerator.GetDefaultAudioEndpoint(eRender, eMultimedia, FDevice), 'GetDefaultAudioEndpoint');

  TempInterface := nil;
  CheckHR(FDevice.Activate(IID_IAudioClient, CLSCTX_ALL, nil, TempInterface), 'IMMDevice.Activate(IAudioClient)');
  FAudioClient := IAudioClient(TempInterface);

  CheckHR(FAudioClient.GetMixFormat(MixFormat), 'IAudioClient.GetMixFormat');
  try
    AdoptWaveFormat(MixFormat);
    CheckHR(FAudioClient.Initialize(AUDCLNT_SHAREMODE_SHARED, 0, BUFFER_DURATION_HNS, 0, MixFormat, nil), 'IAudioClient.Initialize');
  finally
    if Assigned(MixFormat) then
      CoTaskMemFree(MixFormat);
  end;

  CheckHR(FAudioClient.GetBufferSize(FBufferFrameCount), 'IAudioClient.GetBufferSize');
  CheckHR(FAudioClient.GetStreamLatency(FLatencyHns), 'IAudioClient.GetStreamLatency');

  TempInterface := nil;
  CheckHR(FAudioClient.GetService(IID_IAudioRenderClient, TempInterface), 'IAudioClient.GetService(IAudioRenderClient)');
  FRenderClient := IAudioRenderClient(TempInterface);

  TempInterface := nil;
  if Succeeded(FAudioClient.GetService(IID_ISimpleAudioVolume, TempInterface)) then
    FSimpleVolume := ISimpleAudioVolume(TempInterface)
  else
    FSimpleVolume := nil;

  TempInterface := nil;
  if Succeeded(FDevice.Activate(IID_IAudioEndpointVolume, CLSCTX_ALL, nil, TempInterface)) then
    FEndpointVolume := IAudioEndpointVolume(TempInterface)
  else
    FEndpointVolume := nil;

  ApplyVolume;
  Result := True;
end;

procedure TAudioOutputWASAPI.SetMuted(const Value: Boolean);
begin
  inherited SetMuted(Value);
  ApplyVolume;
end;

procedure TAudioOutputWASAPI.SetVolume(const Value: Single);
begin
  inherited SetVolume(Value);
  ApplyVolume;
end;

procedure TAudioOutputWASAPI.SetVolumeMode(const Value: TRadioWASAPIVolumeMode);
begin
  FVolumeMode := Value;
  ApplyVolume;
end;

procedure TAudioOutputWASAPI.Start;
begin
  if Assigned(FAudioClient) and not FStarted then
  begin
    CheckHR(FAudioClient.Start(), 'IAudioClient.Start');
    FStarted := True;
  end;
end;

procedure TAudioOutputWASAPI.Stop;
begin
  if Assigned(FAudioClient) and FStarted then
  begin
    FAudioClient.Stop();
    FAudioClient.Reset();
    FStarted := False;
  end;
end;

function TAudioOutputWASAPI.Write(Buffer: PByte; ByteCount: Integer): Integer;
var
  AvailableFrames: UINT32;
  DataBuffer: PByte;
  PaddingFrames: UINT32;
  RemainingFrames: UINT32;
  TotalFrames: UINT32;
  WriteFrames: UINT32;
  WrittenFrames: UINT32;
begin
  Result := 0;
  if not Assigned(FAudioClient) or not Assigned(FRenderClient) or not Assigned(Buffer) or (ByteCount <= 0) then
    Exit;

  if BytesPerFrame <= 0 then
    Exit;

  TotalFrames := ByteCount div BytesPerFrame;
  WrittenFrames := 0;

  while WrittenFrames < TotalFrames do
  begin
    CheckHR(FAudioClient.GetCurrentPadding(PaddingFrames), 'IAudioClient.GetCurrentPadding');
    AvailableFrames := FBufferFrameCount - PaddingFrames;
    if AvailableFrames = 0 then
    begin
      Sleep(2);
      Continue;
    end;

    RemainingFrames := TotalFrames - WrittenFrames;
    if RemainingFrames < AvailableFrames then
      WriteFrames := RemainingFrames
    else
      WriteFrames := AvailableFrames;

    CheckHR(FRenderClient.GetBuffer(WriteFrames, DataBuffer), 'IAudioRenderClient.GetBuffer');
    Move(Buffer[Integer(WrittenFrames) * BytesPerFrame], DataBuffer^,
      Integer(WriteFrames) * BytesPerFrame);
    CheckHR(FRenderClient.ReleaseBuffer(WriteFrames, 0), 'IAudioRenderClient.ReleaseBuffer');

    Inc(WrittenFrames, WriteFrames);
  end;

  Result := Integer(WrittenFrames) * BytesPerFrame;
end;

end.
