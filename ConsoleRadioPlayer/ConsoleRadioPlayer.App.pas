unit ConsoleRadioPlayer.App;

interface

uses
{$IF CompilerVersion >= 23.0}
  Winapi.Windows,
  System.IniFiles,
  System.IOUtils,
  System.Math,
  System.SysUtils,
{$ELSE}
  Windows,
  IniFiles,
  IOUtils,
  Math,
  SysUtils,
{$IFEND}
  Radio.ConsoleUI,
  Radio.Player,
  Radio.Types;

type
  TConsoleRadioPlayerApp = class
  private
    FConfigPath: string;
    FDeviceIndex: Integer;
    FDevices: TRadioWASAPIDeviceInfos;
    FPlayer: TRadioPlayer;
    FRecentURLs: TArray<string>;
    FUI: TRadioConsoleUI;
    FURL: string;
    function BackendName: string;
    function ConfigDir: string;
    function ControlHintText: string;
    function CurrentDeviceLabel: string;
    function DeviceShortLabel(const Device: TRadioWASAPIDeviceInfo): string;
    function LoadPresetURL(Index: Integer): string;
    function SavePresetURL(Index: Integer): Boolean;
    procedure AddRecentURL(const URL: string);
    procedure ApplyBackendByName(const Name: string);
    procedure ApplyDeviceIndex(Index: Integer);
    procedure ApplyVolumeModeByName(const Name: string);
    procedure HandleError(Sender: TObject; const ErrorInfo: TRadioErrorInfo);
    procedure HandleReconnectAttempt(Sender: TObject; Attempt: Integer; DelayMS: Cardinal);
    procedure HandleReconnectFailed(Sender: TObject; Attempt: Integer; const ErrorInfo: TRadioErrorInfo);
    procedure HandleReconnectSucceeded(Sender: TObject; Attempt: Integer);
    procedure HandleStateChanged(Sender: TObject; State: TRadioPlayerState);
    procedure HandleUIKey(Sender: TObject; Key: Word; Ch: Char; var Handled: Boolean);
    procedure ListDevices;
    procedure LoadConfig;
    procedure ParseArgs;
    procedure RefreshDeviceSelection;
    procedure RestartPlayback(const StatusText: string);
    procedure SaveConfig;
    procedure SetStatus(const Text: string);
    procedure ToggleBackend;
    procedure UpdateDeviceDelta(Delta: Integer);
    procedure UpdateVolumeMode;
  public
    constructor Create;
    destructor Destroy; override;
    function Run: Integer;
  end;

implementation

const
  DEFAULT_URL = 'https://stream.radio38.de/radio38-live/mp3-192';

constructor TConsoleRadioPlayerApp.Create;
begin
  inherited Create;
  FConfigPath := TPath.Combine(ConfigDir, 'ConsoleRadioPlayer.ini');
  FPlayer := TRadioPlayer.Create(nil);
  FPlayer.EventDispatchMode := redmMainThread;
  FPlayer.OutputSpectrumBinCount := 96;
  FPlayer.OnStateChangedData := HandleStateChanged;
  FPlayer.OnError := HandleError;
  FPlayer.OnReconnectAttempt := HandleReconnectAttempt;
  FPlayer.OnReconnectSucceeded := HandleReconnectSucceeded;
  FPlayer.OnReconnectFailed := HandleReconnectFailed;

  FUI := TRadioConsoleUI.Create(FPlayer);
  FUI.Title := 'ConsoleRadioPlayer';
  FUI.FooterText := ControlHintText;
  FUI.OnKey := HandleUIKey;

  FURL := DEFAULT_URL;
  FDeviceIndex := -1;

  if DirectoryExists(ConfigDir) or ForceDirectories(ConfigDir) then
    LoadConfig;

  RefreshDeviceSelection;
  FUI.URL := FURL;
  FUI.DeviceLabel := CurrentDeviceLabel;
  FUI.StatusText := 'Ready';
end;

destructor TConsoleRadioPlayerApp.Destroy;
begin
  SaveConfig;
  FUI.Free;
  FPlayer.Free;
  inherited Destroy;
end;

procedure TConsoleRadioPlayerApp.AddRecentURL(const URL: string);
var
  Count: Integer;
  I: Integer;
  NewItems: TArray<string>;
begin
  if Trim(URL) = '' then
    Exit;

  SetLength(NewItems, 0);
  SetLength(NewItems, 1);
  NewItems[0] := URL;
  Count := 1;

  for I := 0 to High(FRecentURLs) do
  begin
    if SameText(FRecentURLs[I], URL) then
      Continue;
    if Count >= 8 then
      Break;
    SetLength(NewItems, Count + 1);
    NewItems[Count] := FRecentURLs[I];
    Inc(Count);
  end;

  FRecentURLs := NewItems;
end;

procedure TConsoleRadioPlayerApp.ApplyBackendByName(const Name: string);
begin
  if SameText(Name, 'waveout') then
    FPlayer.OutputBackend := robWaveOut
  else
    FPlayer.OutputBackend := robWASAPI;
end;

procedure TConsoleRadioPlayerApp.ApplyDeviceIndex(Index: Integer);
begin
  FDevices := TRadioPlayer.EnumerateWASAPIDevices;
  if Length(FDevices) = 0 then
  begin
    FDeviceIndex := -1;
    FPlayer.WasapiDeviceId := '';
    FUI.DeviceLabel := '<default>';
    Exit;
  end;

  if Index < 0 then
    Index := 0
  else if Index > High(FDevices) then
    Index := High(FDevices);

  FDeviceIndex := Index;
  FPlayer.WasapiDeviceId := FDevices[FDeviceIndex].Id;
  FUI.DeviceLabel := DeviceShortLabel(FDevices[FDeviceIndex]);
end;

procedure TConsoleRadioPlayerApp.ApplyVolumeModeByName(const Name: string);
begin
  if SameText(Name, 'endpoint') then
    FPlayer.WasapiVolumeMode := rwvmEndpoint
  else
    FPlayer.WasapiVolumeMode := rwvmSession;
end;

function TConsoleRadioPlayerApp.BackendName: string;
begin
  case FPlayer.OutputBackend of
    robWaveOut:
      Result := 'waveout';
  else
    Result := 'wasapi';
  end;
end;

function TConsoleRadioPlayerApp.ConfigDir: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, '.console-radio-player');
end;

function TConsoleRadioPlayerApp.ControlHintText: string;
begin
  Result := 'q quit  m mute  +/- volume  r restart  b backend  d next-device  v volume-mode  1-5 load preset  !-%% save preset';
end;

function TConsoleRadioPlayerApp.CurrentDeviceLabel: string;
begin
  if (FDeviceIndex >= 0) and (FDeviceIndex <= High(FDevices)) then
    Result := DeviceShortLabel(FDevices[FDeviceIndex])
  else if Trim(FPlayer.WasapiDeviceId) <> '' then
    Result := FPlayer.WasapiDeviceId
  else
    Result := '<default>';
end;

function TConsoleRadioPlayerApp.DeviceShortLabel(const Device: TRadioWASAPIDeviceInfo): string;
begin
  Result := Device.FriendlyName;
  if Device.IsDefault then
    Result := Result + ' [default]';
end;

procedure TConsoleRadioPlayerApp.HandleError(Sender: TObject; const ErrorInfo: TRadioErrorInfo);
begin
  SetStatus('Error: ' + ErrorInfo.MessageText);
end;

procedure TConsoleRadioPlayerApp.HandleReconnectAttempt(Sender: TObject; Attempt: Integer;
  DelayMS: Cardinal);
begin
  SetStatus(Format('Reconnect attempt %d in %d ms', [Attempt, DelayMS]));
end;

procedure TConsoleRadioPlayerApp.HandleReconnectFailed(Sender: TObject; Attempt: Integer;
  const ErrorInfo: TRadioErrorInfo);
begin
  SetStatus(Format('Reconnect failed on attempt %d: %s', [Attempt, ErrorInfo.MessageText]));
end;

procedure TConsoleRadioPlayerApp.HandleReconnectSucceeded(Sender: TObject; Attempt: Integer);
begin
  SetStatus(Format('Reconnect succeeded on attempt %d', [Attempt]));
end;

procedure TConsoleRadioPlayerApp.HandleStateChanged(Sender: TObject; State: TRadioPlayerState);
begin
  case State of
    rpsOpening:
      SetStatus('Opening stream');
    rpsBuffering:
      SetStatus('Buffering audio');
    rpsPlaying:
      SetStatus('Playing');
    rpsReconnecting:
      SetStatus('Reconnecting');
    rpsStopping:
      SetStatus('Stopping');
    rpsStopped:
      SetStatus('Stopped');
    rpsError:
      SetStatus('Error');
  else
    SetStatus('Idle');
  end;
end;

procedure TConsoleRadioPlayerApp.HandleUIKey(Sender: TObject; Key: Word; Ch: Char;
  var Handled: Boolean);
begin
  case Ch of
    'b', 'B':
      begin
        ToggleBackend;
        Handled := True;
      end;
    'd', 'D':
      begin
        UpdateDeviceDelta(1);
        Handled := True;
      end;
    'v', 'V':
      begin
        UpdateVolumeMode;
        Handled := True;
      end;
    '1'..'5':
      begin
        FURL := LoadPresetURL(Ord(Ch) - Ord('0'));
        if Trim(FURL) <> '' then
          RestartPlayback(Format('Loaded preset %s', [Ch]))
        else
          SetStatus(Format('Preset %s is empty', [Ch]));
        Handled := True;
      end;
    '!', '@', '#', '$', '%':
      begin
        if SavePresetURL(Ord(Ch) - Ord('!') + 1) then
          SetStatus(Format('Saved preset %d', [Ord(Ch) - Ord('!') + 1]))
        else
          SetStatus('Preset save failed');
        Handled := True;
      end;
  end;
end;

procedure TConsoleRadioPlayerApp.ListDevices;
var
  Device: TRadioWASAPIDeviceInfo;
  Devices: TRadioWASAPIDeviceInfos;
  I: Integer;
begin
  Devices := TRadioPlayer.EnumerateWASAPIDevices;
  Writeln('WASAPI render devices');
  Writeln(StringOfChar('=', 72));
  for I := 0 to High(Devices) do
  begin
    Device := Devices[I];
    Writeln(Format('[%d] %s', [I, DeviceShortLabel(Device)]));
    Writeln('    state : ', Device.StateText);
    Writeln('    desc  : ', Device.DeviceDescription);
    Writeln('    iface : ', Device.InterfaceName);
    Writeln('    id    : ', Device.Id);
    Writeln;
  end;
end;

function TConsoleRadioPlayerApp.LoadPresetURL(Index: Integer): string;
var
  Ini: TMemIniFile;
begin
  Result := '';
  if not FileExists(FConfigPath) then
    Exit;

  Ini := TMemIniFile.Create(FConfigPath);
  try
    Result := Trim(Ini.ReadString('Presets', 'Preset' + IntToStr(Index), ''));
  finally
    Ini.Free;
  end;
end;

procedure TConsoleRadioPlayerApp.LoadConfig;
var
  I: Integer;
  Ini: TMemIniFile;
  PresetURL: string;
begin
  if not FileExists(FConfigPath) then
    Exit;

  Ini := TMemIniFile.Create(FConfigPath);
  try
    FURL := Ini.ReadString('Player', 'LastURL', FURL);
    ApplyBackendByName(Ini.ReadString('Player', 'Backend', BackendName));
    ApplyVolumeModeByName(Ini.ReadString('Player', 'VolumeMode',
      WASAPIVolumeModeName(FPlayer.WasapiVolumeMode)));
    FPlayer.BufferTimeMS := Ini.ReadInteger('Player', 'BufferTimeMS', FPlayer.BufferTimeMS);
    FPlayer.PrebufferTimeMS := Ini.ReadInteger('Player', 'PrebufferTimeMS', FPlayer.PrebufferTimeMS);
    FPlayer.Volume := EnsureRange(Ini.ReadFloat('Player', 'Volume', FPlayer.Volume), 0.0, 1.0);
    FPlayer.Muted := Ini.ReadBool('Player', 'Muted', False);
    FPlayer.WasapiDeviceId := Ini.ReadString('Player', 'DeviceId', '');

    SetLength(FRecentURLs, 0);
    for I := 1 to 8 do
    begin
      PresetURL := Trim(Ini.ReadString('History', 'Recent' + IntToStr(I), ''));
      if PresetURL <> '' then
      begin
        SetLength(FRecentURLs, Length(FRecentURLs) + 1);
        FRecentURLs[High(FRecentURLs)] := PresetURL;
      end;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TConsoleRadioPlayerApp.ParseArgs;
var
  I: Integer;
begin
  if (ParamCount >= 1) and SameText(ParamStr(1), '--help') then
  begin
    Writeln('ConsoleRadioPlayer');
    Writeln;
    Writeln('Usage:');
    Writeln('  ConsoleRadioPlayer.exe [url] [backend] [volume_mode] [device_id] [buffer_ms] [prebuffer_ms]');
    Writeln('  ConsoleRadioPlayer.exe --list-devices');
    Writeln;
    Writeln('Examples:');
    Writeln('  ConsoleRadioPlayer.exe');
    Writeln('  ConsoleRadioPlayer.exe https://stream.radio38.de/radio38-live/mp3-192 wasapi session');
    Writeln('  ConsoleRadioPlayer.exe https://stream.radio38.de/radio38-live/mp3-192 waveout');
    Halt(0);
  end;

  if (ParamCount >= 1) and SameText(ParamStr(1), '--list-devices') then
  begin
    ListDevices;
    Halt(0);
  end;

  if ParamCount >= 1 then
    FURL := ParamStr(1);
  if ParamCount >= 2 then
    ApplyBackendByName(ParamStr(2));
  if ParamCount >= 3 then
    ApplyVolumeModeByName(ParamStr(3));
  if (ParamCount >= 4) and (ParamStr(4) <> '-') then
    FPlayer.WasapiDeviceId := ParamStr(4);
  if ParamCount >= 5 then
    FPlayer.BufferTimeMS := StrToIntDef(ParamStr(5), FPlayer.BufferTimeMS);
  if ParamCount >= 6 then
    FPlayer.PrebufferTimeMS := StrToIntDef(ParamStr(6), FPlayer.PrebufferTimeMS);

  RefreshDeviceSelection;
  for I := 0 to High(FDevices) do
    if SameText(FDevices[I].Id, FPlayer.WasapiDeviceId) then
    begin
      FDeviceIndex := I;
      Break;
    end;

  FUI.URL := FURL;
  FUI.DeviceLabel := CurrentDeviceLabel;
end;

procedure TConsoleRadioPlayerApp.RefreshDeviceSelection;
begin
  FDevices := TRadioPlayer.EnumerateWASAPIDevices;
  FDeviceIndex := -1;
  if Trim(FPlayer.WasapiDeviceId) = '' then
  begin
    FUI.DeviceLabel := '<default>';
    Exit;
  end;
end;

procedure TConsoleRadioPlayerApp.RestartPlayback(const StatusText: string);
begin
  if Trim(FURL) = '' then
    Exit;

  AddRecentURL(FURL);
  FUI.URL := FURL;
  FUI.DeviceLabel := CurrentDeviceLabel;
  SetStatus(StatusText);
  FPlayer.Stop;
  FPlayer.Play(FURL);
end;

function TConsoleRadioPlayerApp.Run: Integer;
begin
  Result := 0;
  ParseArgs;
  FPlayer.Logger := FUI.Logger;
  FUI.ConfigureConsole;
  RestartPlayback('Starting playback');
  repeat
    FUI.Pump;
    Sleep(25);
  until FUI.QuitRequested;

  FPlayer.Stop;
  FUI.Pump(True);
end;

function TConsoleRadioPlayerApp.SavePresetURL(Index: Integer): Boolean;
var
  Ini: TMemIniFile;
begin
  Result := False;
  if (Index < 1) or (Index > 5) or (Trim(FURL) = '') then
    Exit;

  Ini := TMemIniFile.Create(FConfigPath);
  try
    Ini.WriteString('Presets', 'Preset' + IntToStr(Index), FURL);
    Ini.UpdateFile;
    Result := True;
  finally
    Ini.Free;
  end;
end;

procedure TConsoleRadioPlayerApp.SaveConfig;
var
  I: Integer;
  Ini: TMemIniFile;
begin
  if not (DirectoryExists(ConfigDir) or ForceDirectories(ConfigDir)) then
    Exit;

  Ini := TMemIniFile.Create(FConfigPath);
  try
    Ini.WriteString('Player', 'LastURL', FURL);
    Ini.WriteString('Player', 'Backend', BackendName);
    Ini.WriteString('Player', 'VolumeMode', WASAPIVolumeModeName(FPlayer.WasapiVolumeMode));
    Ini.WriteInteger('Player', 'BufferTimeMS', FPlayer.BufferTimeMS);
    Ini.WriteInteger('Player', 'PrebufferTimeMS', FPlayer.PrebufferTimeMS);
    Ini.WriteFloat('Player', 'Volume', FPlayer.Volume);
    Ini.WriteBool('Player', 'Muted', FPlayer.Muted);
    Ini.WriteString('Player', 'DeviceId', FPlayer.WasapiDeviceId);

    for I := 1 to 8 do
      Ini.DeleteKey('History', 'Recent' + IntToStr(I));
    for I := 0 to High(FRecentURLs) do
      Ini.WriteString('History', 'Recent' + IntToStr(I + 1), FRecentURLs[I]);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TConsoleRadioPlayerApp.SetStatus(const Text: string);
begin
  FUI.StatusText := Text;
end;

procedure TConsoleRadioPlayerApp.ToggleBackend;
begin
  case FPlayer.OutputBackend of
    robWaveOut:
      FPlayer.OutputBackend := robWASAPI;
  else
    FPlayer.OutputBackend := robWaveOut;
  end;

  if FPlayer.OutputBackend = robWaveOut then
    FUI.DeviceLabel := '<waveOut default>'
  else
    FUI.DeviceLabel := CurrentDeviceLabel;

  RestartPlayback('Backend: ' + BackendName);
end;

procedure TConsoleRadioPlayerApp.UpdateDeviceDelta(Delta: Integer);
var
  NewIndex: Integer;
begin
  FDevices := TRadioPlayer.EnumerateWASAPIDevices;
  if Length(FDevices) = 0 then
  begin
    SetStatus('No WASAPI render devices found');
    Exit;
  end;

  if FDeviceIndex < 0 then
    NewIndex := 0
  else
    NewIndex := (FDeviceIndex + Delta) mod Length(FDevices);

  if NewIndex < 0 then
    NewIndex := High(FDevices);

  ApplyDeviceIndex(NewIndex);
  RestartPlayback('Device: ' + CurrentDeviceLabel);
end;

procedure TConsoleRadioPlayerApp.UpdateVolumeMode;
begin
  case FPlayer.WasapiVolumeMode of
    rwvmEndpoint:
      FPlayer.WasapiVolumeMode := rwvmSession;
  else
    FPlayer.WasapiVolumeMode := rwvmEndpoint;
  end;
  SetStatus('Volume mode: ' + WASAPIVolumeModeName(FPlayer.WasapiVolumeMode));
end;

end.
