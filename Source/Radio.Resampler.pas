unit Radio.Resampler;

interface

uses
{$IFDEF FPC}
  SysUtils,
{$ELSE}
  System.SysUtils,
{$ENDIF}
  libavcodec,
  libavutil,
  libavutil_channel_layout,
  libavutil_error,
  libavutil_frame,
  libavutil_samplefmt,
  libswresample,
  Radio.FFmpeg.Resample;

type
  TAudioResampler = class
  private
    FSwrContext: PSwrContext;
    FOutputLayout: TAVChannelLayout;
    FOutputSampleRate: Integer;
    FOutputChannels: Integer;
    FOutputSampleFormat: TAVSampleFormat;
    FBuffer: PByte;
    FBufferCapacity: Integer;
    procedure EnsureBufferCapacity(RequiredBytes: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    function OpenFromCodec(CodecContext: PAVCodecContext; OutputSampleRate, OutputChannels: Integer;
      OutputSampleFormat: TAVSampleFormat): Integer;
    procedure Close;
    function ConvertFrame(Frame: PAVFrame; out Buffer: PByte; out ByteCount: Integer): Integer;
    function Flush(out Buffer: PByte; out ByteCount: Integer): Integer;
    function BytesPerSecond: Integer;

    property OutputSampleRate: Integer read FOutputSampleRate;
    property OutputChannels: Integer read FOutputChannels;
    property OutputSampleFormat: TAVSampleFormat read FOutputSampleFormat;
  end;

implementation

procedure TAudioResampler.Close;
begin
  TFFmpegResampleApi.FreeContext(FSwrContext);
  TFFmpegResampleApi.UninitChannelLayout(FOutputLayout);
  TFFmpegResampleApi.FreeAudioBuffer(FBuffer, FBufferCapacity);
end;

function TAudioResampler.ConvertFrame(Frame: PAVFrame; out Buffer: PByte; out ByteCount: Integer): Integer;
var
  OutBytes: Integer;
  OutSamples: Integer;
begin
  Buffer := nil;
  ByteCount := 0;
  if not Assigned(FSwrContext) then
    Exit(AVERROR_EINVAL);

  OutSamples := TFFmpegResampleApi.GetOutSamples(FSwrContext, Frame^.nb_samples);
  OutBytes := TFFmpegResampleApi.GetBufferSize(FOutputChannels, OutSamples, FOutputSampleFormat);
  if OutBytes < 0 then
    Exit(OutBytes);

  EnsureBufferCapacity(OutBytes);
  Result := TFFmpegResampleApi.Convert(FSwrContext, @FBuffer, OutSamples,
    Frame^.extended_data, Frame^.nb_samples);
  if Result < 0 then
    Exit;

  ByteCount := TFFmpegResampleApi.GetBufferSize(FOutputChannels, Result, FOutputSampleFormat);
  Buffer := FBuffer;
end;

constructor TAudioResampler.Create;
begin
  inherited Create;
  FOutputSampleFormat := AV_SAMPLE_FMT_S16;
end;

destructor TAudioResampler.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TAudioResampler.EnsureBufferCapacity(RequiredBytes: Integer);
begin
  TFFmpegResampleApi.EnsureAudioBufferCapacity(FBuffer, FBufferCapacity, RequiredBytes);
end;

function TAudioResampler.BytesPerSecond: Integer;
begin
  Result := FOutputSampleRate * FOutputChannels *
    TFFmpegResampleApi.BytesPerSample(FOutputSampleFormat);
end;

function TAudioResampler.Flush(out Buffer: PByte; out ByteCount: Integer): Integer;
var
  OutSamples: Integer;
  OutBytes: Integer;
begin
  Buffer := nil;
  ByteCount := 0;
  if not Assigned(FSwrContext) then
    Exit(AVERROR_EINVAL);

  OutSamples := TFFmpegResampleApi.GetOutSamples(FSwrContext, 0);
  OutBytes := TFFmpegResampleApi.GetBufferSize(FOutputChannels, OutSamples, FOutputSampleFormat);
  if OutBytes > 0 then
    EnsureBufferCapacity(OutBytes);

  Result := TFFmpegResampleApi.Flush(FSwrContext, @FBuffer, OutSamples);
  if Result < 0 then
    Exit;

  ByteCount := TFFmpegResampleApi.GetBufferSize(FOutputChannels, Result, FOutputSampleFormat);
  Buffer := FBuffer;
end;

function TAudioResampler.OpenFromCodec(CodecContext: PAVCodecContext; OutputSampleRate, OutputChannels: Integer;
  OutputSampleFormat: TAVSampleFormat): Integer;
begin
  Close;

  FOutputSampleRate := OutputSampleRate;
  FOutputChannels := OutputChannels;
  FOutputSampleFormat := OutputSampleFormat;
  TFFmpegResampleApi.DefaultChannelLayout(FOutputLayout, OutputChannels);

  FSwrContext := TFFmpegResampleApi.AllocContext;
  if not Assigned(FSwrContext) then
    Exit(AVERROR_ENOMEM);

  Result := TFFmpegResampleApi.ConfigureFromCodecContext(FSwrContext, CodecContext,
    FOutputLayout, OutputSampleRate, FOutputSampleFormat);
  if Result < 0 then
  begin
    Close;
    Exit;
  end;

  Result := TFFmpegResampleApi.Init(FSwrContext);
  if Result < 0 then
    Close;
end;

end.
