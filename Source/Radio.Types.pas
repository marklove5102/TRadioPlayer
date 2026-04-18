unit Radio.Types;

interface

uses
  System.Classes;

type
  TRadioSpectrumBins = array of Single;

  TRadioPlayerState = (
    rpsIdle,
    rpsOpening,
    rpsBuffering,
    rpsPlaying,
    rpsReconnecting,
    rpsStopping,
    rpsStopped,
    rpsError
  );

  TStreamMetadata = record
    StationName: string;
    StreamTitle: string;
    Genre: string;
    Description: string;
    Url: string;
    ContentType: string;
    CodecName: string;
    Bitrate: Int64;
    SampleRate: Integer;
    Channels: Integer;
    ResolvedUrl: string;
  end;

  TRadioBufferStats = record
    PacketsReceived: Int64;
    PacketsDropped: Int64;
    DecodedFrames: Int64;
    BytesReceived: Int64;
    BytesWritten: Int64;
    BufferedBytes: Integer;
    QueueBufferedBytes: Integer;
    OutputBufferedBytes: Integer;
    BufferCapacityBytes: Integer;
    PrebufferBytes: Integer;
    BufferFillPercent: Single;
    LatencyMS: Integer;
    QueueDurationMS: Integer;
    OutputLatencyMS: Integer;
    PacketRate: Integer;
    DecodeRate: Integer;
    InputBitrate: Integer;
    OutputBitrate: Integer;
    AverageInputBitrate: Integer;
    AverageOutputBitrate: Integer;
    UnderflowCount: Integer;
    ReconnectCount: Integer;
    ReconnectSuccessCount: Integer;
    ReconnectFailureCount: Integer;
    UptimeMS: Cardinal;
    PeakLeft: Single;
    PeakRight: Single;
    RMSLeft: Single;
    RMSRight: Single;
    LastError: string;
    LastFFmpegError: Integer;
  end;

  TRadioErrorInfo = record
    Code: Integer;
    MessageText: string;
    FFmpegError: Integer;
    FFmpegErrorText: string;
    Recoverable: Boolean;
  end;

  TRadioSpectrumData = record
    CaptureTickMS: Cardinal;
    SampleRate: Integer;
    Channels: Integer;
    FFTSize: Integer;
    BinHz: Single;
    OutputLatencyMS: Integer;
    QueueDurationMS: Integer;
    TotalLatencyMS: Integer;
    Bins: TRadioSpectrumBins;
  end;

  TRadioReconnectPolicy = record
    Enabled: Boolean;
    InitialDelayMS: Cardinal;
    MaxDelayMS: Cardinal;
    OpenTimeoutMS: Cardinal;
  end;

  TRadioOutputBackend = (
    robWASAPI,
    robWaveOut
  );

  TRadioWASAPIVolumeMode = (
    rwvmSession,
    rwvmEndpoint
  );

  TRadioEventDispatchMode = (
    redmDedicatedThread,
    redmMainThread
  );

  TRadioWASAPIDeviceInfo = record
    Id: string;
    FriendlyName: string;
    InterfaceName: string;
    DeviceDescription: string;
    State: Cardinal;
    StateText: string;
    IsDefault: Boolean;
  end;

  TRadioWASAPIDeviceInfos = array of TRadioWASAPIDeviceInfo;

  TStateChangedEvent = procedure(Sender: TObject; State: TRadioPlayerState) of object;
  TMetadataChangedEvent = procedure(Sender: TObject; const Metadata: TStreamMetadata) of object;
  TRadioErrorEvent = procedure(Sender: TObject; const ErrorInfo: TRadioErrorInfo) of object;
  TBufferStatsEvent = procedure(Sender: TObject; const Stats: TRadioBufferStats) of object;
  TSpectrumEvent = procedure(Sender: TObject; const Spectrum: TRadioSpectrumData) of object;
  TReconnectAttemptEvent = procedure(Sender: TObject; Attempt: Integer; DelayMS: Cardinal) of object;
  TReconnectSucceededEvent = procedure(Sender: TObject; Attempt: Integer) of object;
  TReconnectFailedEvent = procedure(Sender: TObject; Attempt: Integer;
    const ErrorInfo: TRadioErrorInfo) of object;

function DefaultReconnectPolicy: TRadioReconnectPolicy;
function DefaultStreamMetadata: TStreamMetadata;
function DefaultBufferStats: TRadioBufferStats;
function EventDispatchModeName(Mode: TRadioEventDispatchMode): string;
function WASAPIVolumeModeName(Mode: TRadioWASAPIVolumeMode): string;

implementation

function DefaultReconnectPolicy: TRadioReconnectPolicy;
begin
  Result.Enabled := True;
  Result.InitialDelayMS := 1000;
  Result.MaxDelayMS := 30000;
  Result.OpenTimeoutMS := 15000;
end;

function DefaultStreamMetadata: TStreamMetadata;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function DefaultBufferStats: TRadioBufferStats;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function EventDispatchModeName(Mode: TRadioEventDispatchMode): string;
begin
  case Mode of
    redmMainThread:
      Result := 'main';
  else
    Result := 'threaded';
  end;
end;

function WASAPIVolumeModeName(Mode: TRadioWASAPIVolumeMode): string;
begin
  case Mode of
    rwvmEndpoint:
      Result := 'endpoint';
  else
    Result := 'session';
  end;
end;

end.
