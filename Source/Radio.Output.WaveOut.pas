unit Radio.Output.WaveOut;

interface

uses
{$IF CompilerVersion >= 23.0}
  Winapi.Windows,
  Winapi.MMSystem,
{$ELSE}
  Windows,
  MMSystem,
{$IFEND}
  System.SysUtils,
  Radio.Output;

type
  TAudioOutputWaveOut = class(TAudioOutput)
  private const
    NUM_WAVE_BUFS = 12;
    WAVE_BUF_BYTES = 8192;
  private
    type
      TWaveBuf = record
        Hdr: TWaveHdr;
        Data: array[0..WAVE_BUF_BYTES - 1] of Byte;
      end;
  private
    FHandle: HWAVEOUT;
    FWaveBufs: array[0..NUM_WAVE_BUFS - 1] of TWaveBuf;
    FBufIdx: Integer;
    FAvgBytesPerSec: Integer;
    procedure CheckMMResult(Code: MMRESULT; const Action: string);
    procedure ApplyVolume;
  public
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
  end;

implementation

procedure TAudioOutputWaveOut.ApplyVolume;
var
  Scalar: Single;
  Value16: Cardinal;
  PackedValue: DWORD;
begin
  if FHandle = 0 then
    Exit;

  if Muted then
    Scalar := 0
  else
    Scalar := Volume;

  Value16 := Round(Scalar * $FFFF);
  PackedValue := Value16 or (Value16 shl 16);
  waveOutSetVolume(FHandle, PackedValue);
end;

procedure TAudioOutputWaveOut.CheckMMResult(Code: MMRESULT; const Action: string);
begin
  if Code <> MMSYSERR_NOERROR then
    raise EAudioOutputError.CreateFmt('%s failed (%d)', [Action, Code]);
end;

procedure TAudioOutputWaveOut.Close;
var
  I: Integer;
begin
  if FHandle = 0 then
    Exit;

  waveOutReset(FHandle);
  for I := 0 to NUM_WAVE_BUFS - 1 do
    waveOutUnprepareHeader(FHandle, @FWaveBufs[I].Hdr, SizeOf(TWaveHdr));
  waveOutClose(FHandle);
  FHandle := 0;
  FBufIdx := 0;
end;

destructor TAudioOutputWaveOut.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TAudioOutputWaveOut.GetBufferedBytes: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to NUM_WAVE_BUFS - 1 do
    if (FWaveBufs[I].Hdr.dwFlags and WHDR_INQUEUE) <> 0 then
      Inc(Result, FWaveBufs[I].Hdr.dwBufferLength);
end;

function TAudioOutputWaveOut.GetLatencyMS: Integer;
begin
  if FAvgBytesPerSec > 0 then
    Result := (GetBufferedBytes * 1000) div FAvgBytesPerSec
  else
    Result := 0;
end;

function TAudioOutputWaveOut.Open(SampleRate, Channels, BitsPerSample: Integer): Boolean;
var
  WFX: TWaveFormatEx;
  I: Integer;
begin
  Close;

  Self.SampleRate := SampleRate;
  Self.Channels := Channels;
  Self.BitsPerSample := BitsPerSample;
  Self.SampleType := astInt16;

  FillChar(WFX, SizeOf(WFX), 0);
  WFX.wFormatTag := WAVE_FORMAT_PCM;
  WFX.nChannels := Channels;
  WFX.nSamplesPerSec := SampleRate;
  WFX.wBitsPerSample := BitsPerSample;
  WFX.nBlockAlign := Channels * (BitsPerSample div 8);
  WFX.nAvgBytesPerSec := WFX.nSamplesPerSec * WFX.nBlockAlign;
  FAvgBytesPerSec := WFX.nAvgBytesPerSec;

  CheckMMResult(waveOutOpen(@FHandle, WAVE_MAPPER, @WFX, 0, 0, CALLBACK_NULL), 'waveOutOpen');

  FillChar(FWaveBufs, SizeOf(FWaveBufs), 0);
  for I := 0 to NUM_WAVE_BUFS - 1 do
  begin
    FWaveBufs[I].Hdr.lpData := @FWaveBufs[I].Data[0];
    FWaveBufs[I].Hdr.dwBufferLength := WAVE_BUF_BYTES;
    CheckMMResult(waveOutPrepareHeader(FHandle, @FWaveBufs[I].Hdr, SizeOf(TWaveHdr)), 'waveOutPrepareHeader');
  end;

  ApplyVolume;
  Result := True;
end;

procedure TAudioOutputWaveOut.SetMuted(const Value: Boolean);
begin
  inherited SetMuted(Value);
  ApplyVolume;
end;

procedure TAudioOutputWaveOut.SetVolume(const Value: Single);
begin
  inherited SetVolume(Value);
  ApplyVolume;
end;

procedure TAudioOutputWaveOut.Start;
begin
end;

procedure TAudioOutputWaveOut.Stop;
begin
  if FHandle <> 0 then
    waveOutReset(FHandle);
end;

function TAudioOutputWaveOut.Write(Buffer: PByte; ByteCount: Integer): Integer;
var
  Chunk: Integer;
  Written: Integer;
begin
  Result := 0;
  if (FHandle = 0) or not Assigned(Buffer) or (ByteCount <= 0) then
    Exit;

  Written := 0;
  while Written < ByteCount do
  begin
    while (FWaveBufs[FBufIdx].Hdr.dwFlags and WHDR_INQUEUE) <> 0 do
      Sleep(2);

    Chunk := ByteCount - Written;
    if Chunk > WAVE_BUF_BYTES then
      Chunk := WAVE_BUF_BYTES;

    Move(Buffer[Written], FWaveBufs[FBufIdx].Data[0], Chunk);
    FWaveBufs[FBufIdx].Hdr.dwBufferLength := Chunk;
    CheckMMResult(waveOutWrite(FHandle, @FWaveBufs[FBufIdx].Hdr, SizeOf(TWaveHdr)), 'waveOutWrite');

    Inc(Written, Chunk);
    FBufIdx := (FBufIdx + 1) mod NUM_WAVE_BUFS;
  end;

  Result := Written;
end;

end.
