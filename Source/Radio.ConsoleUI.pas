unit Radio.ConsoleUI;

interface

uses
{$IFDEF FPC}
  BaseUnix,
  Classes,
  Generics.Collections,
  Math,
  SyncObjs,
  StrUtils,
  SysUtils,
  Termio,
{$ELSE}
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.SyncObjs,
  System.StrUtils,
  System.SysUtils,
  {$IF CompilerVersion >= 23.0}
  Winapi.Windows,
  {$ELSE}
  Windows,
  {$IFEND}
{$ENDIF}
  Radio.Logging,
  Radio.Platform,
  Radio.Player,
  Radio.Types;

type
  TStringArray = array of string;

  TRadioConsoleUI = class;

  TRadioConsoleUIKeyEvent = procedure(Sender: TObject; Key: Word; Ch: Char;
    var Handled: Boolean) of object;

  TRadioConsoleUILogger = class(TInterfacedObject, IRadioLogger)
  private
    FOwner: TRadioConsoleUI;
  public
    constructor Create(AOwner: TRadioConsoleUI);
    procedure Log(Level: TRadioLogLevel; const MessageText: string);
  end;

  TRadioConsoleUI = class
  private const
    DEFAULT_RENDER_INTERVAL_MS = 100;
    MAX_LOG_LINES = 12;
    SPECTRUM_ROWS = 8;
{$IFDEF FPC}
    UNIX_STDIN_FD = 0;
    UNIX_STDOUT_FD = 1;
    KEY_ESCAPE = 27;
    KEY_UP = 38;
    KEY_DOWN = 40;
    TIOCGWINSZ_IOCTL = 21523;
{$ELSE}
    KEY_ESCAPE = VK_ESCAPE;
    KEY_UP = VK_UP;
    KEY_DOWN = VK_DOWN;
{$ENDIF}
  private
    FDeviceLabel: string;
    FFooterText: string;
{$IFDEF FPC}
    FInputFlags: LongInt;
    FInputTermios: TTermios;
    FInputTermiosValid: Boolean;
{$ELSE}
    FInputHandle: THandle;
    FInputMode: DWORD;
{$ENDIF}
    FLastRenderedLines: TStringArray;
    FLastRenderTick: Cardinal;
    FLayoutWidth: Integer;
    FLock: TCriticalSection;
    FLogger: IRadioLogger;
    FLogLines: TQueue<string>;
    FNeedsFullRedraw: Boolean;
    FOnKey: TRadioConsoleUIKeyEvent;
    FPlayer: TRadioPlayer;
    FQuitRequested: Boolean;
    FRenderIntervalMS: Cardinal;
    FScreenHeight: Integer;
    FScreenWidth: Integer;
    FShowCursorRestored: Boolean;
    FStatusText: string;
    FStdoutHandle: THandle;
    FTitle: string;
    FURL: string;
    FUseVT100: Boolean;
    function BoolText(Value: Boolean): string;
    function BoxContent(const Text: string): string;
    function BoxLine(LeftChar, FillChar, RightChar: Char): string;
    function FormatDuration(Milliseconds: Cardinal): string;
    function PadRight(const Text: string; Width: Integer): string;
{$IFDEF FPC}
    function ReadUnixKey(out Key: Word; out Ch: Char): Boolean;
{$ENDIF}
    function RenderLevelBar(Value: Single; Width: Integer): string;
    function RenderSpectrumRow(const Spectrum: TRadioSpectrumData; Row, Rows: Integer): string;
    function StateName(State: TRadioPlayerState): string;
    procedure AddLog(const Line: string);
    procedure ProcessKey(Key: Word; Ch: Char);
    procedure RenderDiff(const Lines: TStringArray);
    procedure RenderFooter(var Lines: TStringArray; var Index: Integer; const FooterText: string);
    procedure RenderHeader(var Lines: TStringArray; var Index: Integer; const State: TRadioPlayerState;
      const Metadata: TStreamMetadata; const Stats: TRadioBufferStats; const Spectrum: TRadioSpectrumData;
      Volume: Single; Muted: Boolean);
    procedure RenderLogs(var Lines: TStringArray; var Index: Integer);
    procedure RenderMetadata(var Lines: TStringArray; var Index: Integer; const Metadata: TStreamMetadata);
    procedure RenderSpectrum(var Lines: TStringArray; var Index: Integer; const Spectrum: TRadioSpectrumData);
    procedure RenderStats(var Lines: TStringArray; var Index: Integer; const Stats: TRadioBufferStats);
    procedure ToggleMute;
    procedure UpdateConsoleSize;
    procedure UpdateVolume(Delta: Single);
    procedure SetDeviceLabel(const Value: string);
    procedure SetFooterText(const Value: string);
    procedure SetStatusText(const Value: string);
    procedure SetTitle(const Value: string);
    procedure SetURL(const Value: string);
  public
    constructor Create(APlayer: TRadioPlayer);
    destructor Destroy; override;
    procedure ConfigureConsole;
    procedure EnqueueLog(Level: TRadioLogLevel; const MessageText: string);
    procedure Invalidate;
    procedure PollInput;
    procedure Pump(ForceRender: Boolean = False);
    procedure Render;
    procedure RestoreConsole;
    property DeviceLabel: string read FDeviceLabel write SetDeviceLabel;
    property FooterText: string read FFooterText write SetFooterText;
    property Logger: IRadioLogger read FLogger;
    property OnKey: TRadioConsoleUIKeyEvent read FOnKey write FOnKey;
    property Player: TRadioPlayer read FPlayer;
    property QuitRequested: Boolean read FQuitRequested;
    property RenderIntervalMS: Cardinal read FRenderIntervalMS write FRenderIntervalMS;
    property StatusText: string read FStatusText write SetStatusText;
    property Title: string read FTitle write SetTitle;
    property URL: string read FURL write SetURL;
    property UseVT100: Boolean read FUseVT100;
  end;

implementation

{$IFNDEF FPC}
function CtrlHandler(CtrlType: DWORD): BOOL; stdcall;
begin
  Result := True;
end;
{$ENDIF}

constructor TRadioConsoleUILogger.Create(AOwner: TRadioConsoleUI);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TRadioConsoleUILogger.Log(Level: TRadioLogLevel; const MessageText: string);
begin
  FOwner.EnqueueLog(Level, MessageText);
end;

constructor TRadioConsoleUI.Create(APlayer: TRadioPlayer);
begin
  inherited Create;
  FPlayer := APlayer;
  FLock := TCriticalSection.Create;
  FLogLines := TQueue<string>.Create;
  FLogger := TRadioConsoleUILogger.Create(Self);
  FTitle := 'TRadioPlayer Console';
  FFooterText := 'q quit  m mute  +/- volume  r restart';
  FRenderIntervalMS := DEFAULT_RENDER_INTERVAL_MS;
{$IFNDEF FPC}
  FInputHandle := GetStdHandle(STD_INPUT_HANDLE);
  FStdoutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
{$ENDIF}
  FNeedsFullRedraw := True;
end;

destructor TRadioConsoleUI.Destroy;
begin
  RestoreConsole;
  FLogLines.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TRadioConsoleUI.AddLog(const Line: string);
begin
  FLock.Acquire;
  try
    while FLogLines.Count >= MAX_LOG_LINES do
      FLogLines.Dequeue;
    FLogLines.Enqueue(Line);
  finally
    FLock.Release;
  end;
end;

function TRadioConsoleUI.BoolText(Value: Boolean): string;
begin
  if Value then
    Result := 'yes'
  else
    Result := 'no';
end;

function TRadioConsoleUI.BoxContent(const Text: string): string;
begin
  Result := '|' + PadRight(Text, Max(1, FLayoutWidth - 2)) + '|';
end;

function TRadioConsoleUI.BoxLine(LeftChar, FillChar, RightChar: Char): string;
begin
  Result := LeftChar + StringOfChar(FillChar, Max(1, FLayoutWidth - 2)) + RightChar;
end;

procedure TRadioConsoleUI.ConfigureConsole;
{$IFDEF FPC}
var
  Flags: LongInt;
  RawTermios: TTermios;
{$ELSE}
var
  Mode: DWORD;
{$ENDIF}
begin
{$IFDEF FPC}
  FUseVT100 := True;
  FInputTermiosValid := tcgetattr(UNIX_STDIN_FD, FInputTermios) = 0;
  if FInputTermiosValid then
  begin
    RawTermios := FInputTermios;
    RawTermios.c_lflag := RawTermios.c_lflag and not (ICANON or ECHO);
    RawTermios.c_cc[VMIN] := 0;
    RawTermios.c_cc[VTIME] := 0;
    tcsetattr(UNIX_STDIN_FD, TCSANOW, RawTermios);
  end;

  Flags := fpFcntl(UNIX_STDIN_FD, F_GETFL, 0);
  if Flags >= 0 then
  begin
    FInputFlags := Flags;
    fpFcntl(UNIX_STDIN_FD, F_SETFL, Flags or O_NONBLOCK);
  end;

  Write(#27'[?25l');
  FShowCursorRestored := True;
{$ELSE}
  SetConsoleCtrlHandler(@CtrlHandler, True);
  FUseVT100 := False;
  if GetConsoleMode(FStdoutHandle, Mode) then
  begin
    Mode := Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    if SetConsoleMode(FStdoutHandle, Mode) then
      FUseVT100 := True;
  end;
  if (not FUseVT100) and (GetEnvironmentVariable('TERM') <> '') then
    FUseVT100 := True;

  if GetConsoleMode(FInputHandle, FInputMode) then
  begin
    Mode := FInputMode;
    Mode := Mode and not ENABLE_ECHO_INPUT;
    Mode := Mode and not ENABLE_LINE_INPUT;
    Mode := Mode and not ENABLE_MOUSE_INPUT;
    SetConsoleMode(FInputHandle, Mode);
  end;

  if FUseVT100 then
  begin
    Write(#27'[?25l');
    FShowCursorRestored := True;
  end;
{$ENDIF}

  UpdateConsoleSize;
  FNeedsFullRedraw := True;
end;

procedure TRadioConsoleUI.EnqueueLog(Level: TRadioLogLevel; const MessageText: string);
const
  LEVEL_NAMES: array[TRadioLogLevel] of string = ('DEBUG', 'INFO', 'WARN', 'ERROR');
begin
  AddLog(Format('[%s] %s', [LEVEL_NAMES[Level], MessageText]));
end;

function TRadioConsoleUI.FormatDuration(Milliseconds: Cardinal): string;
var
  Hours: Cardinal;
  Minutes: Cardinal;
  Seconds: Cardinal;
begin
  Seconds := Milliseconds div 1000;
  Hours := Seconds div 3600;
  Minutes := (Seconds mod 3600) div 60;
  Seconds := Seconds mod 60;
  Result := Format('%.2d:%.2d:%.2d', [Hours, Minutes, Seconds]);
end;

procedure TRadioConsoleUI.Invalidate;
begin
  FNeedsFullRedraw := True;
  FLastRenderTick := 0;
end;

function TRadioConsoleUI.PadRight(const Text: string; Width: Integer): string;
begin
  Result := Copy(Text, 1, Width);
  if Length(Result) < Width then
    Result := Result + StringOfChar(' ', Width - Length(Result));
end;

procedure TRadioConsoleUI.PollInput;
{$IFDEF FPC}
var
  Ch: Char;
  Key: Word;
begin
  while ReadUnixKey(Key, Ch) do
  begin
    ProcessKey(Key, Ch);
    if FQuitRequested then
      Exit;
  end;
end;
{$ELSE}
var
  EventCount: DWORD;
  InputRecord: TInputRecord;
  ReadCount: DWORD;
begin
  if FInputHandle = INVALID_HANDLE_VALUE then
    Exit;

  while GetNumberOfConsoleInputEvents(FInputHandle, EventCount) and (EventCount > 0) do
  begin
    if not ReadConsoleInput(FInputHandle, InputRecord, 1, ReadCount) then
      Exit;
    if (InputRecord.EventType = KEY_EVENT) and InputRecord.Event.KeyEvent.bKeyDown then
      ProcessKey(InputRecord.Event.KeyEvent.wVirtualKeyCode,
        Char(InputRecord.Event.KeyEvent.AsciiChar));
    if FQuitRequested then
      Exit;
  end;
end;
{$ENDIF}

{$IFDEF FPC}
function TRadioConsoleUI.ReadUnixKey(out Key: Word; out Ch: Char): Boolean;
var
  BytesRead: ssize_t;
  EscapeSeq: array[0..1] of Char;
begin
  Key := 0;
  Ch := #0;
  Result := False;

  BytesRead := fpRead(UNIX_STDIN_FD, Ch, 1);
  if BytesRead <= 0 then
    Exit;

  Result := True;
  if Ch = #27 then
  begin
    Key := KEY_ESCAPE;
    BytesRead := fpRead(UNIX_STDIN_FD, EscapeSeq[0], 2);
    if BytesRead = 2 then
      if EscapeSeq[0] = '[' then
        case EscapeSeq[1] of
          'A': Key := KEY_UP;
          'B': Key := KEY_DOWN;
        end;
    Ch := #0;
  end;
end;
{$ENDIF}

procedure TRadioConsoleUI.ProcessKey(Key: Word; Ch: Char);
var
  Handled: Boolean;
  CurrentURL: string;
begin
  Handled := False;
  case Key of
    KEY_ESCAPE:
      begin
        FQuitRequested := True;
        Handled := True;
      end;
    KEY_UP:
      begin
        UpdateVolume(0.05);
        Handled := True;
      end;
    KEY_DOWN:
      begin
        UpdateVolume(-0.05);
        Handled := True;
      end;
  end;

  if not Handled then
    case Ch of
      'q', 'Q':
        begin
          FQuitRequested := True;
          Handled := True;
        end;
      'm', 'M':
        begin
          ToggleMute;
          Handled := True;
        end;
      '+', '=':
        begin
          UpdateVolume(0.05);
          Handled := True;
        end;
      '-', '_':
        begin
          UpdateVolume(-0.05);
          Handled := True;
        end;
      'r', 'R':
        begin
          FLock.Acquire;
          try
            CurrentURL := Trim(FURL);
          finally
            FLock.Release;
          end;
          if (CurrentURL = '') and Assigned(FPlayer) then
            CurrentURL := Trim(FPlayer.URL);
          if (CurrentURL <> '') and Assigned(FPlayer) then
          begin
            AddLog('[INFO] manual restart requested');
            FPlayer.Stop;
            FPlayer.Play(CurrentURL);
          end;
          Handled := True;
        end;
    end;

  if (not Handled) and Assigned(FOnKey) then
    FOnKey(Self, Key, Ch, Handled);
end;

procedure TRadioConsoleUI.Pump(ForceRender: Boolean);
begin
  if Assigned(FPlayer) and (FPlayer.EventDispatchMode = redmMainThread) then
    TRadioPlayer.PumpMainThreadEvents(0);

  PollInput;
  if ForceRender or (GetTickCountMS - FLastRenderTick >= FRenderIntervalMS) then
  begin
    FLastRenderTick := GetTickCountMS;
    Render;
  end;
end;

procedure TRadioConsoleUI.Render;
var
  I: Integer;
  Index: Integer;
  Lines: TStringArray;
  LocalDeviceLabel: string;
  LocalFooterText: string;
  LocalStatusText: string;
  LocalTitle: string;
  LocalURL: string;
  Metadata: TStreamMetadata;
  Muted: Boolean;
  Spectrum: TRadioSpectrumData;
  State: TRadioPlayerState;
  Stats: TRadioBufferStats;
  Volume: Single;
begin
  if not Assigned(FPlayer) then
    Exit;

  State := FPlayer.State;
  Metadata := FPlayer.Metadata;
  Stats := FPlayer.Stats;
  Spectrum := FPlayer.LastSpectrum;
  Volume := FPlayer.Volume;
  Muted := FPlayer.Muted;

  FLock.Acquire;
  try
    LocalDeviceLabel := FDeviceLabel;
    LocalFooterText := FFooterText;
    LocalStatusText := FStatusText;
    LocalTitle := FTitle;
    LocalURL := FURL;
  finally
    FLock.Release;
  end;

  UpdateConsoleSize;
  SetLength(Lines, FScreenHeight);
  for I := 0 to High(Lines) do
    Lines[I] := '';

  Index := 0;
  RenderHeader(Lines, Index, State, Metadata, Stats, Spectrum, Volume, Muted);

  if Index <= High(Lines) then
  begin
    Lines[Index] := BoxLine('+', '=', '+');
    Inc(Index);
  end;
  if Index <= High(Lines) then
  begin
    Lines[Index] := BoxContent(PadRight(LocalTitle, FLayoutWidth - 2));
    Inc(Index);
  end;
  if Index <= High(Lines) then
  begin
    Lines[Index] := BoxContent('URL      : ' + LocalURL);
    Inc(Index);
  end;
  if Index <= High(Lines) then
  begin
    if LocalStatusText <> '' then
      Lines[Index] := BoxContent('Status   : ' + LocalStatusText)
    else
      Lines[Index] := BoxContent('Status   : ' + StateName(State));
    Inc(Index);
  end;
  if Index <= High(Lines) then
  begin
    Lines[Index] := BoxContent('Device   : ' + LocalDeviceLabel);
    Inc(Index);
  end;
  if Index <= High(Lines) then
  begin
    Lines[Index] := BoxLine('+', '=', '+');
    Inc(Index);
  end;

  RenderMetadata(Lines, Index, Metadata);
  RenderStats(Lines, Index, Stats);
  RenderSpectrum(Lines, Index, Spectrum);
  RenderLogs(Lines, Index);

  RenderFooter(Lines, Index, LocalFooterText);
  RenderDiff(Lines);
end;

procedure TRadioConsoleUI.RenderDiff(const Lines: TStringArray);
var
  I: Integer;
  LineText: string;
  PreviousCount: Integer;
begin
  if FUseVT100 then
  begin
    if FNeedsFullRedraw then
    begin
      Write(#27'[2J'#27'[H');
      FNeedsFullRedraw := False;
    end;

    PreviousCount := Length(FLastRenderedLines);
    for I := 0 to High(Lines) do
    begin
      LineText := PadRight(Lines[I], FScreenWidth);
      if (I >= PreviousCount) or (FLastRenderedLines[I] <> LineText) then
        Write(Format(#27'[%d;1H%s', [I + 1, LineText]));
    end;

    for I := Length(Lines) to PreviousCount - 1 do
      Write(Format(#27'[%d;1H%s', [I + 1, StringOfChar(' ', FScreenWidth)]));
  end
  else
  begin
    for I := 0 to High(Lines) do
      Writeln(Copy(Lines[I], 1, FScreenWidth));
  end;

  SetLength(FLastRenderedLines, Length(Lines));
  for I := 0 to High(Lines) do
    FLastRenderedLines[I] := PadRight(Lines[I], FScreenWidth);
end;

procedure TRadioConsoleUI.RenderFooter(var Lines: TStringArray; var Index: Integer;
  const FooterText: string);
begin
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '-', '+');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(FooterText);
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '=', '+');
end;

procedure TRadioConsoleUI.RenderHeader(var Lines: TStringArray; var Index: Integer;
  const State: TRadioPlayerState; const Metadata: TStreamMetadata; const Stats: TRadioBufferStats;
  const Spectrum: TRadioSpectrumData; Volume: Single; Muted: Boolean);
begin
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '=', '+');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'State %-10s  Backend %-7s  Mode %-8s  Volume %3d%%  Muted %-3s  Dispatch %s',
    [StateName(State),
     OutputBackendName(FPlayer.OutputBackend),
     WASAPIVolumeModeName(FPlayer.WasapiVolumeMode),
     Round(Volume * 100),
     BoolText(Muted),
     EventDispatchModeName(FPlayer.EventDispatchMode)]));
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'Codec %-10s  Rate %-6d  Channels %-2d  Uptime %s  Total latency %d ms',
    [Metadata.CodecName,
     Metadata.SampleRate,
     Metadata.Channels,
     FormatDuration(Stats.UptimeMS),
     Spectrum.TotalLatencyMS]));
  Inc(Index);
end;

procedure TRadioConsoleUI.RenderLogs(var Lines: TStringArray; var Index: Integer);
var
  BlankCount: Integer;
  I: Integer;
  Items: TStringArray;
{$IFNDEF FPC}
  QueueItems: TArray<string>;
{$ENDIF}
begin
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '-', '+');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Logs');
  Inc(Index);

  FLock.Acquire;
  try
{$IFDEF FPC}
    Items := FLogLines.ToArray;
{$ELSE}
    QueueItems := FLogLines.ToArray;
{$ENDIF}
  finally
    FLock.Release;
  end;

{$IFNDEF FPC}
  SetLength(Items, Length(QueueItems));
  for I := 0 to High(QueueItems) do
    Items[I] := QueueItems[I];
{$ENDIF}

  for I := 0 to High(Items) do
  begin
    if Index > High(Lines) then
      Break;
    Lines[Index] := BoxContent(Items[I]);
    Inc(Index);
  end;

  BlankCount := MAX_LOG_LINES - Length(Items);
  if BlankCount < 0 then
    BlankCount := 0;
  for I := 1 to BlankCount do
  begin
    if Index > High(Lines) then
      Break;
    Lines[Index] := BoxContent('');
    Inc(Index);
  end;
end;

procedure TRadioConsoleUI.RenderMetadata(var Lines: TStringArray; var Index: Integer;
  const Metadata: TStreamMetadata);
begin
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '-', '+');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Metadata');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Station  : ' + Metadata.StationName);
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Title    : ' + Metadata.StreamTitle);
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Genre    : ' + Metadata.Genre);
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Content  : ' + Metadata.ContentType);
  Inc(Index);
end;

procedure TRadioConsoleUI.RenderSpectrum(var Lines: TStringArray; var Index: Integer;
  const Spectrum: TRadioSpectrumData);
var
  Row: Integer;
begin
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '-', '+');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format('Spectrum  FFT=%d  bins=%d  bin=%.1f Hz',
    [Spectrum.FFTSize, Length(Spectrum.Bins), Spectrum.BinHz]));
  Inc(Index);

  for Row := SPECTRUM_ROWS - 1 downto 0 do
  begin
    if Index > High(Lines) then
      Break;
    Lines[Index] := BoxContent(RenderSpectrumRow(Spectrum, Row, SPECTRUM_ROWS));
    Inc(Index);
  end;
end;

procedure TRadioConsoleUI.RenderStats(var Lines: TStringArray; var Index: Integer;
  const Stats: TRadioBufferStats);
begin
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxLine('+', '-', '+');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent('Playback');
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'Packets %-8d (%4d/s)  Frames %-8d (%4d/s)  Underflows %d',
    [Stats.PacketsReceived, Stats.PacketRate, Stats.DecodedFrames, Stats.DecodeRate,
     Stats.UnderflowCount]));
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'Input %6d kbps avg %6d   Output %6d kbps avg %6d',
    [Stats.InputBitrate div 1000, Stats.AverageInputBitrate div 1000,
     Stats.OutputBitrate div 1000, Stats.AverageOutputBitrate div 1000]));
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'Queue %8d/%8d B (%5.1f%%)  Output %8d B  Total %8d B',
    [Stats.QueueBufferedBytes, Stats.BufferCapacityBytes, Stats.BufferFillPercent,
     Stats.OutputBufferedBytes, Stats.BufferedBytes]));
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'Timing queue %4d ms  output %4d ms  total %4d ms  prebuffer %8d B',
    [Stats.QueueDurationMS, Stats.OutputLatencyMS, Stats.LatencyMS, Stats.PrebufferBytes]));
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'Reconnects %4d  ok %4d  fail %4d  last error %s',
    [Stats.ReconnectCount, Stats.ReconnectSuccessCount, Stats.ReconnectFailureCount,
     Stats.LastError]));
  Inc(Index);
  if Index > High(Lines) then
    Exit;
  Lines[Index] := BoxContent(Format(
    'VU L [%s] %.2f/%.2f  R [%s] %.2f/%.2f',
    [RenderLevelBar(Stats.RMSLeft, 16), Stats.RMSLeft, Stats.PeakLeft,
     RenderLevelBar(Stats.RMSRight, 16), Stats.RMSRight, Stats.PeakRight]));
  Inc(Index);
end;

function TRadioConsoleUI.RenderLevelBar(Value: Single; Width: Integer): string;
var
  Filled: Integer;
begin
  Filled := Round(EnsureRange(Value, 0.0, 1.0) * Width);
  Result := StringOfChar('#', Filled) + StringOfChar('.', Width - Filled);
end;

function TRadioConsoleUI.RenderSpectrumRow(const Spectrum: TRadioSpectrumData; Row,
  Rows: Integer): string;
var
  Bin: Integer;
  Threshold: Single;
begin
  Result := '';
  if Length(Spectrum.Bins) = 0 then
  begin
    Result := StringOfChar(' ', 24);
    Exit;
  end;

  Threshold := (Row + 1) / Rows;
  for Bin := 0 to High(Spectrum.Bins) do
    if Spectrum.Bins[Bin] >= Threshold then
      Result := Result + '#'
    else
      Result := Result + ' ';
end;

procedure TRadioConsoleUI.RestoreConsole;
begin
{$IFDEF FPC}
  if FShowCursorRestored and FUseVT100 then
  begin
    Write(#27'[?25h');
    FShowCursorRestored := False;
  end;
  if FInputTermiosValid then
    tcsetattr(UNIX_STDIN_FD, TCSANOW, FInputTermios);
  fpFcntl(UNIX_STDIN_FD, F_SETFL, FInputFlags);
{$ELSE}
  if FShowCursorRestored and FUseVT100 then
  begin
    Write(#27'[?25h');
    FShowCursorRestored := False;
  end;
  if (FInputHandle <> INVALID_HANDLE_VALUE) and (FInputMode <> 0) then
    SetConsoleMode(FInputHandle, FInputMode);
{$ENDIF}
end;

procedure TRadioConsoleUI.SetDeviceLabel(const Value: string);
begin
  FLock.Acquire;
  try
    FDeviceLabel := Value;
  finally
    FLock.Release;
  end;
end;

procedure TRadioConsoleUI.SetFooterText(const Value: string);
begin
  FLock.Acquire;
  try
    FFooterText := Value;
  finally
    FLock.Release;
  end;
end;

procedure TRadioConsoleUI.SetStatusText(const Value: string);
begin
  FLock.Acquire;
  try
    FStatusText := Value;
  finally
    FLock.Release;
  end;
end;

procedure TRadioConsoleUI.SetTitle(const Value: string);
begin
  FLock.Acquire;
  try
    FTitle := Value;
  finally
    FLock.Release;
  end;
end;

procedure TRadioConsoleUI.SetURL(const Value: string);
begin
  FLock.Acquire;
  try
    FURL := Value;
  finally
    FLock.Release;
  end;
end;

function TRadioConsoleUI.StateName(State: TRadioPlayerState): string;
begin
  case State of
    rpsIdle: Result := 'Idle';
    rpsOpening: Result := 'Opening';
    rpsBuffering: Result := 'Buffering';
    rpsPlaying: Result := 'Playing';
    rpsReconnecting: Result := 'Reconnect';
    rpsStopping: Result := 'Stopping';
    rpsStopped: Result := 'Stopped';
    rpsError: Result := 'Error';
  else
    Result := 'Unknown';
  end;
end;

procedure TRadioConsoleUI.ToggleMute;
begin
  if not Assigned(FPlayer) then
    Exit;
  FPlayer.Muted := not FPlayer.Muted;
  AddLog(Format('[INFO] mute %s', [BoolText(FPlayer.Muted)]));
end;

procedure TRadioConsoleUI.UpdateConsoleSize;
{$IFDEF FPC}
type
  TWinsize = packed record
    ws_row: Word;
    ws_col: Word;
    ws_xpixel: Word;
    ws_ypixel: Word;
  end;
var
  WinSize: TWinsize;
{$ELSE}
var
  BufferInfo: TConsoleScreenBufferInfo;
{$ENDIF}
begin
  FScreenWidth := 100;
  FScreenHeight := 40;
{$IFDEF FPC}
  if fpIOCtl(UNIX_STDOUT_FD, TIOCGWINSZ_IOCTL, @WinSize) = 0 then
  begin
    if WinSize.ws_col > 0 then
      FScreenWidth := WinSize.ws_col;
    if WinSize.ws_row > 0 then
      FScreenHeight := WinSize.ws_row;
  end;
{$ELSE}
  if GetConsoleScreenBufferInfo(FStdoutHandle, BufferInfo) then
  begin
    FScreenWidth := BufferInfo.srWindow.Right - BufferInfo.srWindow.Left + 1;
    FScreenHeight := BufferInfo.srWindow.Bottom - BufferInfo.srWindow.Top + 1;
  end;
{$ENDIF}
  FLayoutWidth := Max(60, FScreenWidth - 1);
end;

procedure TRadioConsoleUI.UpdateVolume(Delta: Single);
var
  Value: Single;
begin
  if not Assigned(FPlayer) then
    Exit;
  Value := EnsureRange(FPlayer.Volume + Delta, 0.0, 1.0);
  FPlayer.Volume := Value;
  AddLog(Format('[INFO] volume set to %d%%', [Round(Value * 100)]));
end;

end.
