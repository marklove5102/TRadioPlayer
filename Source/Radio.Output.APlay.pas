unit Radio.Output.APlay;

interface

uses
{$IFDEF FPC}
  Classes,
  Math,
  Process,
  SysUtils,
{$ELSE}
  System.Classes,
  System.Math,
  System.SysUtils,
{$ENDIF}
  Radio.Output;

type
  TAudioOutputAPlay = class(TAudioOutput)
  private
    FAvgBytesPerSec: Integer;
    FProcess: TProcess;
    FTempBuffer: TBytes;
    procedure ApplySoftwareVolume(Source: PByte; ByteCount: Integer; out Data: PByte);
    procedure CloseProcess;
    procedure EnsureProcess;
    function ResolveExecutable: string;
    procedure WriteAll(Buffer: PByte; ByteCount: Integer);
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

procedure TAudioOutputAPlay.ApplySoftwareVolume(Source: PByte; ByteCount: Integer; out Data: PByte);
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

procedure TAudioOutputAPlay.Close;
begin
  CloseProcess;
end;

procedure TAudioOutputAPlay.CloseProcess;
begin
  if not Assigned(FProcess) then
    Exit;

  try
    if FProcess.Running then
      FProcess.Terminate(0);
  except
    // Best effort shutdown only.
  end;

  FProcess.Free;
  FProcess := nil;
end;

destructor TAudioOutputAPlay.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TAudioOutputAPlay.EnsureProcess;
begin
  if Assigned(FProcess) then
    Exit;

  FProcess := TProcess.Create(nil);
  FProcess.Executable := ResolveExecutable;
  FProcess.Parameters.Add('-q');
  FProcess.Parameters.Add('-f');
  FProcess.Parameters.Add('S16_LE');
  FProcess.Parameters.Add('-r');
  FProcess.Parameters.Add(IntToStr(SampleRate));
  FProcess.Parameters.Add('-c');
  FProcess.Parameters.Add(IntToStr(Channels));
  FProcess.Options := [poUsePipes];
  FProcess.Execute;
end;

function TAudioOutputAPlay.GetBufferedBytes: Integer;
begin
  Result := 0;
end;

function TAudioOutputAPlay.GetLatencyMS: Integer;
begin
  if FAvgBytesPerSec > 0 then
    Result := 0
  else
    Result := 0;
end;

function TAudioOutputAPlay.Open(SampleRate, Channels, BitsPerSample: Integer): Boolean;
begin
  Close;

  if BitsPerSample <> 16 then
    raise EAudioOutputError.CreateFmt('aplay backend only supports 16-bit PCM, got %d bits', [BitsPerSample]);

  Self.SampleRate := SampleRate;
  Self.Channels := Channels;
  Self.BitsPerSample := BitsPerSample;
  Self.SampleType := astInt16;
  FAvgBytesPerSec := SampleRate * Channels * (BitsPerSample div 8);
  EnsureProcess;
  Result := True;
end;

function TAudioOutputAPlay.ResolveExecutable: string;
begin
  Result := GetEnvironmentVariable('APLAY_BIN');
  if Result <> '' then
    Exit;

  if FileExists('/usr/bin/aplay') then
    Result := '/usr/bin/aplay'
  else
    Result := 'aplay';
end;

procedure TAudioOutputAPlay.Start;
begin
end;

procedure TAudioOutputAPlay.Stop;
begin
end;

function TAudioOutputAPlay.Write(Buffer: PByte; ByteCount: Integer): Integer;
var
  Data: PByte;
begin
  Result := 0;
  if not Assigned(Buffer) or (ByteCount <= 0) then
    Exit;

  EnsureProcess;
  ApplySoftwareVolume(Buffer, ByteCount, Data);
  WriteAll(Data, ByteCount);
  Result := ByteCount;
end;

procedure TAudioOutputAPlay.WriteAll(Buffer: PByte; ByteCount: Integer);
var
  Remaining: Integer;
  Written: Integer;
begin
  Remaining := ByteCount;
  while Remaining > 0 do
  begin
    Written := FProcess.Input.Write(Buffer^, Remaining);
    if Written <= 0 then
      raise EAudioOutputError.Create('aplay pipe write failed');
    Inc(Buffer, Written);
    Dec(Remaining, Written);
  end;
end;

end.
