unit Radio.Output;

interface

uses
{$IFDEF FPC}
  SysUtils;
{$ELSE}
  System.SysUtils;
{$ENDIF}

type
  TAudioSampleType = (astInt16, astFloat32);

  EAudioOutputError = class(Exception);

  TAudioOutput = class
  private
    FSampleRate: Integer;
    FChannels: Integer;
    FBitsPerSample: Integer;
    FSampleType: TAudioSampleType;
    FVolume: Single;
    FMuted: Boolean;
  protected
    function ClampVolume(const Value: Single): Single;
  public
    constructor Create; virtual;

    function Open(SampleRate, Channels, BitsPerSample: Integer): Boolean; virtual; abstract;
    procedure Close; virtual; abstract;
    procedure Start; virtual; abstract;
    procedure Stop; virtual; abstract;
    function Write(Buffer: PByte; ByteCount: Integer): Integer; virtual; abstract;
    function GetBufferedBytes: Integer; virtual; abstract;
    function GetLatencyMS: Integer; virtual; abstract;
    procedure SetVolume(const Value: Single); virtual;
    procedure SetMuted(const Value: Boolean); virtual;
    function BytesPerFrame: Integer;

    property SampleRate: Integer read FSampleRate write FSampleRate;
    property Channels: Integer read FChannels write FChannels;
    property BitsPerSample: Integer read FBitsPerSample write FBitsPerSample;
    property SampleType: TAudioSampleType read FSampleType write FSampleType;
    property Volume: Single read FVolume;
    property Muted: Boolean read FMuted;
  end;

implementation

constructor TAudioOutput.Create;
begin
  inherited Create;
  FSampleType := astInt16;
  FVolume := 1.0;
end;

function TAudioOutput.BytesPerFrame: Integer;
begin
  Result := Channels * (BitsPerSample div 8);
end;

function TAudioOutput.ClampVolume(const Value: Single): Single;
begin
  if Value < 0 then
    Result := 0
  else if Value > 1 then
    Result := 1
  else
    Result := Value;
end;

procedure TAudioOutput.SetMuted(const Value: Boolean);
begin
  FMuted := Value;
end;

procedure TAudioOutput.SetVolume(const Value: Single);
begin
  FVolume := ClampVolume(Value);
end;

end.
