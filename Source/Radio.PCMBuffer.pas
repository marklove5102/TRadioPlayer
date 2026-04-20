unit Radio.PCMBuffer;

interface

uses
{$IFDEF FPC}
  SyncObjs,
  SysUtils;
{$ELSE}
  System.SyncObjs,
  System.SysUtils;
{$ENDIF}

type
  TRadioPCMBuffer = class
  private
    FBuffer: TBytes;
    FCapacity: Integer;
    FClosed: Boolean;
    FDataEvent: TEvent;
    FLock: TCriticalSection;
    FReadPos: Integer;
    FSize: Integer;
    FSpaceEvent: TEvent;
    FWritePos: Integer;
    procedure UpdateEventsLocked;
  public
    constructor Create(CapacityBytes: Integer);
    destructor Destroy; override;
    function BufferedBytes: Integer;
    procedure Clear;
    procedure CloseInput;
    function IsClosed: Boolean;
    function Read(Destination: PByte; MaxBytes: Integer; TimeoutMS: Cardinal;
      StopEvent: TEvent): Integer;
    function Write(Source: PByte; ByteCount: Integer; StopEvent: TEvent): Integer;
    property Capacity: Integer read FCapacity;
  end;

implementation

constructor TRadioPCMBuffer.Create(CapacityBytes: Integer);
begin
  inherited Create;
  if CapacityBytes < 1024 then
    CapacityBytes := 1024;

  FCapacity := CapacityBytes;
  SetLength(FBuffer, FCapacity);
  FLock := TCriticalSection.Create;
  FDataEvent := TEvent.Create(nil, True, False, '');
  FSpaceEvent := TEvent.Create(nil, True, True, '');
end;

destructor TRadioPCMBuffer.Destroy;
begin
  FDataEvent.Free;
  FSpaceEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

function TRadioPCMBuffer.BufferedBytes: Integer;
begin
  FLock.Acquire;
  try
    Result := FSize;
  finally
    FLock.Release;
  end;
end;

procedure TRadioPCMBuffer.Clear;
begin
  FLock.Acquire;
  try
    FReadPos := 0;
    FWritePos := 0;
    FSize := 0;
    FClosed := False;
    UpdateEventsLocked;
  finally
    FLock.Release;
  end;
end;

procedure TRadioPCMBuffer.CloseInput;
begin
  FLock.Acquire;
  try
    FClosed := True;
    UpdateEventsLocked;
  finally
    FLock.Release;
  end;
end;

function TRadioPCMBuffer.IsClosed: Boolean;
begin
  FLock.Acquire;
  try
    Result := FClosed;
  finally
    FLock.Release;
  end;
end;

function TRadioPCMBuffer.Read(Destination: PByte; MaxBytes: Integer; TimeoutMS: Cardinal;
  StopEvent: TEvent): Integer;
var
  FirstChunk: Integer;
  ReadBytes: Integer;
  WaitSlice: Cardinal;
begin
  Result := 0;
  if (MaxBytes <= 0) or not Assigned(Destination) then
    Exit;

  while Result = 0 do
  begin
    if Assigned(StopEvent) and (StopEvent.WaitFor(0) = wrSignaled) then
      Exit;

    FLock.Acquire;
    try
      if FSize > 0 then
      begin
        ReadBytes := MaxBytes;
        if ReadBytes > FSize then
          ReadBytes := FSize;

        FirstChunk := ReadBytes;
        if FirstChunk > FCapacity - FReadPos then
          FirstChunk := FCapacity - FReadPos;

        Move(FBuffer[FReadPos], Destination^, FirstChunk);
        FReadPos := (FReadPos + FirstChunk) mod FCapacity;

        if ReadBytes > FirstChunk then
        begin
          Move(FBuffer[FReadPos], Destination[FirstChunk], ReadBytes - FirstChunk);
          FReadPos := (FReadPos + (ReadBytes - FirstChunk)) mod FCapacity;
        end;

        Dec(FSize, ReadBytes);
        Result := ReadBytes;
        UpdateEventsLocked;
        Exit;
      end;

      if FClosed then
        Exit;
    finally
      FLock.Release;
    end;

    WaitSlice := TimeoutMS;
    if WaitSlice = 0 then
      WaitSlice := 20
    else if WaitSlice > 20 then
      WaitSlice := 20;
    FDataEvent.WaitFor(WaitSlice);
  end;
end;

procedure TRadioPCMBuffer.UpdateEventsLocked;
begin
  if (FSize > 0) or FClosed then
    FDataEvent.SetEvent
  else
    FDataEvent.ResetEvent;

  if (FSize < FCapacity) or FClosed then
    FSpaceEvent.SetEvent
  else
    FSpaceEvent.ResetEvent;
end;

function TRadioPCMBuffer.Write(Source: PByte; ByteCount: Integer; StopEvent: TEvent): Integer;
var
  FirstChunk: Integer;
  FreeBytes: Integer;
  WriteBytes: Integer;
begin
  Result := 0;
  if (ByteCount <= 0) or not Assigned(Source) then
    Exit;

  while Result < ByteCount do
  begin
    if Assigned(StopEvent) and (StopEvent.WaitFor(0) = wrSignaled) then
      Exit;

    FLock.Acquire;
    try
      if FClosed then
        Exit;

      FreeBytes := FCapacity - FSize;
      if FreeBytes > 0 then
      begin
        WriteBytes := ByteCount - Result;
        if WriteBytes > FreeBytes then
          WriteBytes := FreeBytes;

        FirstChunk := WriteBytes;
        if FirstChunk > FCapacity - FWritePos then
          FirstChunk := FCapacity - FWritePos;

        Move(Source[Result], FBuffer[FWritePos], FirstChunk);
        FWritePos := (FWritePos + FirstChunk) mod FCapacity;

        if WriteBytes > FirstChunk then
        begin
          Move(Source[Result + FirstChunk], FBuffer[FWritePos], WriteBytes - FirstChunk);
          FWritePos := (FWritePos + (WriteBytes - FirstChunk)) mod FCapacity;
        end;

        Inc(FSize, WriteBytes);
        Inc(Result, WriteBytes);
        UpdateEventsLocked;
      end;
    finally
      FLock.Release;
    end;

    if Result < ByteCount then
      FSpaceEvent.WaitFor(20);
  end;
end;

end.
