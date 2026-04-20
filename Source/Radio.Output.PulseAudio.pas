unit Radio.Output.PulseAudio;

interface

uses
{$IFDEF FPC}
  SysUtils,
{$ELSE}
  System.SysUtils,
{$ENDIF}
  Radio.Output;

type
  pa_sample_format_t = Integer;
  pa_stream_direction_t = Integer;
  pa_usec_t = QWord;

  Ppa_sample_spec = ^Tpa_sample_spec;
  Tpa_sample_spec = packed record
    format: pa_sample_format_t;
    rate: LongWord;
    channels: Byte;
  end;

  Ppa_simple = Pointer;

const
  PULSE_SIMPLE_LIBNAME = 'libpulse-simple.so.0';
  PULSE_LIBNAME = 'libpulse.so.0';

  PA_SAMPLE_S16NE = 3;
  PA_STREAM_PLAYBACK = 1;

function pa_simple_new(server, name: PAnsiChar; dir: pa_stream_direction_t; dev,
  stream_name: PAnsiChar; const ss: Ppa_sample_spec; map, attr: Pointer;
  error: PInteger): Ppa_simple; cdecl; external PULSE_SIMPLE_LIBNAME name 'pa_simple_new';
procedure pa_simple_free(s: Ppa_simple); cdecl; external PULSE_SIMPLE_LIBNAME name 'pa_simple_free';
function pa_simple_write(s: Ppa_simple; const data: Pointer; bytes: SizeUInt;
  error: PInteger): Integer; cdecl; external PULSE_SIMPLE_LIBNAME name 'pa_simple_write';
function pa_simple_drain(s: Ppa_simple; error: PInteger): Integer; cdecl; external PULSE_SIMPLE_LIBNAME name 'pa_simple_drain';
function pa_simple_flush(s: Ppa_simple; error: PInteger): Integer; cdecl; external PULSE_SIMPLE_LIBNAME name 'pa_simple_flush';
function pa_simple_get_latency(s: Ppa_simple; error: PInteger): pa_usec_t; cdecl; external PULSE_SIMPLE_LIBNAME name 'pa_simple_get_latency';
function pa_strerror(error: Integer): PAnsiChar; cdecl; external PULSE_LIBNAME name 'pa_strerror';

type
  TAudioOutputPulseAudio = class(TAudioOutput)
  private
    FConnection: Ppa_simple;
    FSampleSpec: Tpa_sample_spec;
    FTempBuffer: TBytes;
    procedure ApplySoftwareVolume(Source: PByte; ByteCount: Integer; out Data: PByte);
    procedure RaisePulseError(Code: Integer; const Action: string);
  public
    destructor Destroy; override;
    function Open(SampleRate, Channels, BitsPerSample: Integer): Boolean; override;
    procedure Close; override;
    procedure Start; override;
    procedure Stop; override;
    function Write(Buffer: PByte; ByteCount: Integer): Integer; override;
    function GetBufferedBytes: Integer; override;
    function GetLatencyMS: Integer; override;
  end;

implementation

procedure TAudioOutputPulseAudio.ApplySoftwareVolume(Source: PByte; ByteCount: Integer; out Data: PByte);
var
  I: Integer;
  SampleCount: Integer;
  SourceSamples: PSmallInt;
  TargetSamples: PSmallInt;
  Value: Integer;
begin
  if Muted or (Volume < 0.999) then
  begin
    SetLength(FTempBuffer, ByteCount);
    SourceSamples := PSmallInt(Source);
    TargetSamples := PSmallInt(@FTempBuffer[0]);
    SampleCount := ByteCount div SizeOf(SmallInt);
    for I := 0 to SampleCount - 1 do
    begin
      if Muted then
        Value := 0
      else
        Value := Round(SourceSamples^ * Volume);

      if Value > High(SmallInt) then
        Value := High(SmallInt)
      else if Value < Low(SmallInt) then
        Value := Low(SmallInt);

      TargetSamples^ := SmallInt(Value);
      Inc(SourceSamples);
      Inc(TargetSamples);
    end;
    Data := @FTempBuffer[0];
  end
  else
    Data := Source;
end;

procedure TAudioOutputPulseAudio.Close;
begin
  if Assigned(FConnection) then
  begin
    pa_simple_free(FConnection);
    FConnection := nil;
  end;
end;

destructor TAudioOutputPulseAudio.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TAudioOutputPulseAudio.GetBufferedBytes: Integer;
begin
  Result := 0;
end;

function TAudioOutputPulseAudio.GetLatencyMS: Integer;
var
  ErrorCode: Integer;
  LatencyUsec: pa_usec_t;
begin
  Result := 0;
  if not Assigned(FConnection) then
    Exit;

  ErrorCode := 0;
  LatencyUsec := pa_simple_get_latency(FConnection, @ErrorCode);
  if ErrorCode = 0 then
    Result := Integer(LatencyUsec div 1000);
end;

function TAudioOutputPulseAudio.Open(SampleRate, Channels, BitsPerSample: Integer): Boolean;
var
  ErrorCode: Integer;
begin
  Close;

  if BitsPerSample <> 16 then
    raise EAudioOutputError.CreateFmt('PulseAudio backend only supports 16-bit PCM, got %d bits', [BitsPerSample]);

  Self.SampleRate := SampleRate;
  Self.Channels := Channels;
  Self.BitsPerSample := BitsPerSample;
  Self.SampleType := astInt16;

  FillChar(FSampleSpec, SizeOf(FSampleSpec), 0);
  FSampleSpec.format := PA_SAMPLE_S16NE;
  FSampleSpec.rate := SampleRate;
  FSampleSpec.channels := Channels;

  ErrorCode := 0;
  FConnection := pa_simple_new(nil, 'TRadioPlayer', PA_STREAM_PLAYBACK, nil,
    'Radio Playback', @FSampleSpec, nil, nil, @ErrorCode);
  if not Assigned(FConnection) then
    RaisePulseError(ErrorCode, 'pa_simple_new');

  Result := True;
end;

procedure TAudioOutputPulseAudio.RaisePulseError(Code: Integer; const Action: string);
var
  ErrorText: string;
begin
  ErrorText := '';
  if Code <> 0 then
    ErrorText := string(AnsiString(pa_strerror(Code)));
  if ErrorText <> '' then
    raise EAudioOutputError.CreateFmt('%s failed: %s (%d)', [Action, ErrorText, Code])
  else
    raise EAudioOutputError.CreateFmt('%s failed (%d)', [Action, Code]);
end;

procedure TAudioOutputPulseAudio.Start;
begin
end;

procedure TAudioOutputPulseAudio.Stop;
var
  ErrorCode: Integer;
begin
  if not Assigned(FConnection) then
    Exit;

  ErrorCode := 0;
  if pa_simple_flush(FConnection, @ErrorCode) < 0 then
    RaisePulseError(ErrorCode, 'pa_simple_flush');
end;

function TAudioOutputPulseAudio.Write(Buffer: PByte; ByteCount: Integer): Integer;
var
  Data: PByte;
  ErrorCode: Integer;
begin
  Result := 0;
  if not Assigned(Buffer) or (ByteCount <= 0) or not Assigned(FConnection) then
    Exit;

  ApplySoftwareVolume(Buffer, ByteCount, Data);
  ErrorCode := 0;
  if pa_simple_write(FConnection, Data, ByteCount, @ErrorCode) < 0 then
    RaisePulseError(ErrorCode, 'pa_simple_write');
  Result := ByteCount;
end;

end.
