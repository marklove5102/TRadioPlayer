unit Radio.StreamClient;

interface

uses
  System.SysUtils,
  libavcodec_codec,
  libavcodec_codec_par,
  libavcodec_packet,
  libavformat,
  libavutil,
  libavutil_dict,
  Radio.FFmpeg.Api,
  Radio.FFmpeg,
  Radio.Metadata,
  Radio.Types;

type
  TRadioStreamClient = class
  private
    FFormatContext: PAVFormatContext;
    FAudioStreamIndex: Integer;
    FCodec: PAVCodec;
    FURL: string;
    FMetadata: TStreamMetadata;
    function BuildOpenOptions(const ReconnectPolicy: TRadioReconnectPolicy): PAVDictionary;
    function ExtractMetadata: TStreamMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    function Open(const AURL: string; const ReconnectPolicy: TRadioReconnectPolicy): Integer;
    procedure Close;
    function ReadPacket(Packet: PAVPacket): Integer;
    function RefreshMetadata(out Changed: Boolean): TStreamMetadata;
    function SelectedStream: PAVStream;
    function CodecParameters: PAVCodecParameters;

    property FormatContext: PAVFormatContext read FFormatContext;
    property AudioStreamIndex: Integer read FAudioStreamIndex;
    property Codec: PAVCodec read FCodec;
    property URL: string read FURL;
    property Metadata: TStreamMetadata read FMetadata;
  end;

implementation

function TRadioStreamClient.BuildOpenOptions(const ReconnectPolicy: TRadioReconnectPolicy): PAVDictionary;
begin
  Result := nil;
  av_dict_set(@Result, 'icy', '1', 0);
  av_dict_set(@Result, 'user_agent', 'TRadioPlayer/1.0', 0);

  if ReconnectPolicy.Enabled then
  begin
    av_dict_set(@Result, 'reconnect', '1', 0);
    av_dict_set(@Result, 'reconnect_streamed', '1', 0);
    av_dict_set_int(@Result, 'reconnect_delay_max', ReconnectPolicy.MaxDelayMS div 1000, 0);
  end;

  if ReconnectPolicy.OpenTimeoutMS > 0 then
    av_dict_set_int(@Result, 'rw_timeout', Int64(ReconnectPolicy.OpenTimeoutMS) * 1000, 0);
end;

procedure TRadioStreamClient.Close;
begin
  if Assigned(FFormatContext) then
    avformat_close_input(@FFormatContext);
  FAudioStreamIndex := -1;
  FCodec := nil;
  FMetadata := DefaultStreamMetadata;
end;

function TRadioStreamClient.CodecParameters: PAVCodecParameters;
var
  Stream: PAVStream;
begin
  Stream := SelectedStream;
  if Assigned(Stream) then
    Result := Stream^.codecpar
  else
    Result := nil;
end;

constructor TRadioStreamClient.Create;
begin
  inherited Create;
  FAudioStreamIndex := -1;
  FMetadata := DefaultStreamMetadata;
end;

destructor TRadioStreamClient.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TRadioStreamClient.ExtractMetadata: TStreamMetadata;
var
  Stream: PAVStream;
begin
  Result := DefaultStreamMetadata;
  Result.ResolvedUrl := UTF8PtrToString(FFormatContext^.url);
  Result.Url := DictValue(FFormatContext^.metadata, 'icy-url');
  Result.StationName := DictValue(FFormatContext^.metadata, 'icy-name');
  Result.Description := DictValue(FFormatContext^.metadata, 'icy-description');
  Result.Genre := DictValue(FFormatContext^.metadata, 'icy-genre');
  Result.StreamTitle := DictValue(FFormatContext^.metadata, 'StreamTitle');
  if Result.StreamTitle = '' then
    Result.StreamTitle := DictValue(FFormatContext^.metadata, 'title');
  Result.ContentType := DictValue(FFormatContext^.metadata, 'content-type');
  Result.Bitrate := FFormatContext^.bit_rate;

  Stream := SelectedStream;
  if Assigned(Stream) then
  begin
    if Result.StreamTitle = '' then
      Result.StreamTitle := DictValue(Stream^.metadata, 'title');
    Result.SampleRate := Stream^.codecpar^.sample_rate;
    Result.Channels := Stream^.codecpar^.ch_layout.nb_channels;
  end;
end;

function TRadioStreamClient.Open(const AURL: string; const ReconnectPolicy: TRadioReconnectPolicy): Integer;
var
  Codec: PAVCodec;
  Options: PAVDictionary;
  Utf8URL: UTF8String;
begin
  Close;
  FURL := AURL;
  Utf8URL := StringToUTF8String(AURL);
  Options := BuildOpenOptions(ReconnectPolicy);
  try
    Result := TFFmpegApi.OpenInput(FFormatContext, Utf8URL, Options);
  finally
    av_dict_free(@Options);
  end;
  if Result < 0 then
    Exit;

  Result := TFFmpegApi.FindStreamInfo(FFormatContext);
  if Result < 0 then
    Exit;

  FAudioStreamIndex := TFFmpegApi.FindBestAudioStream(FFormatContext, Codec);
  if FAudioStreamIndex < 0 then
    Exit(FAudioStreamIndex);

  FCodec := Codec;
  FMetadata := ExtractMetadata;
  Result := 0;
end;

function TRadioStreamClient.ReadPacket(Packet: PAVPacket): Integer;
begin
  Result := TFFmpegApi.ReadFrame(FFormatContext, Packet);
end;

function TRadioStreamClient.RefreshMetadata(out Changed: Boolean): TStreamMetadata;
var
  NewMetadata: TStreamMetadata;
begin
  Changed := False;
  if not Assigned(FFormatContext) then
  begin
    Result := DefaultStreamMetadata;
    Exit;
  end;

  if (FFormatContext^.event_flags and AVFMT_EVENT_FLAG_METADATA_UPDATED) <> 0 then
    FFormatContext^.event_flags := FFormatContext^.event_flags and not AVFMT_EVENT_FLAG_METADATA_UPDATED;

  NewMetadata := ExtractMetadata;
  Changed := not StreamMetadataEquals(FMetadata, NewMetadata);
  if Changed then
    FMetadata := NewMetadata;
  Result := FMetadata;
end;

function TRadioStreamClient.SelectedStream: PAVStream;
begin
  if Assigned(FFormatContext) and (FAudioStreamIndex >= 0) then
    Result := PPtrIdx(FFormatContext^.streams, FAudioStreamIndex)
  else
    Result := nil;
end;

end.
