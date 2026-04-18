unit Radio.Decoder;

interface

uses
  System.SysUtils,
  libavcodec,
  libavcodec_codec,
  libavcodec_codec_par,
  libavcodec_codec_id,
  libavcodec_packet,
  libavutil_error,
  libavutil_frame,
  Radio.FFmpeg.Api,
  Radio.FFmpeg;

type
  TAudioDecodeWorker = class
  private
    FCodecContext: PAVCodecContext;
    FCodec: PAVCodec;
  public
    destructor Destroy; override;

    function Open(const ACodec: PAVCodec; const ACodecParameters: PAVCodecParameters): Integer;
    procedure Close;
    function SendPacket(const Packet: PAVPacket): Integer;
    function ReceiveFrame(Frame: PAVFrame): Integer;
    procedure Flush;

    property CodecContext: PAVCodecContext read FCodecContext;
    property Codec: PAVCodec read FCodec;
  end;

implementation

procedure TAudioDecodeWorker.Close;
begin
  if Assigned(FCodecContext) then
    TFFmpegApi.FreeDecoderContext(FCodecContext);
  FCodec := nil;
end;

destructor TAudioDecodeWorker.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TAudioDecodeWorker.Flush;
begin
  if Assigned(FCodecContext) then
    TFFmpegApi.SendFlushPacket(FCodecContext);
end;

function TAudioDecodeWorker.Open(const ACodec: PAVCodec; const ACodecParameters: PAVCodecParameters): Integer;
begin
  Close;
  FCodec := ACodec;
  FCodecContext := TFFmpegApi.AllocDecoderContext(ACodec);
  if not Assigned(FCodecContext) then
    Exit(AVERROR_ENOMEM);

  Result := TFFmpegApi.CopyCodecParameters(FCodecContext, ACodecParameters);
  if Result < 0 then
    Exit;

  Result := TFFmpegApi.OpenDecoder(FCodecContext, ACodec);
end;

function TAudioDecodeWorker.ReceiveFrame(Frame: PAVFrame): Integer;
begin
  Result := TFFmpegApi.ReceiveFrame(FCodecContext, Frame);
end;

function TAudioDecodeWorker.SendPacket(const Packet: PAVPacket): Integer;
begin
  Result := TFFmpegApi.SendPacket(FCodecContext, Packet);
end;

end.
