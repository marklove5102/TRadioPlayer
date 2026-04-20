unit Radio.EventBus;

interface

uses
{$IFDEF FPC}
  Classes,
  Generics.Collections,
  SyncObjs,
  SysUtils,
{$ELSE}
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils,
{$ENDIF}
  Radio.Types;

type
  TRadioPlayerEventKind = (
    rpekStateChanged,
    rpekMetadataChanged,
    rpekError,
    rpekBufferStats,
    rpekSpectrum,
    rpekReconnectAttempt,
    rpekReconnectSucceeded,
    rpekReconnectFailed
  );

  TRadioPlayerEventMessage = record
    Kind: TRadioPlayerEventKind;
    State: TRadioPlayerState;
    Metadata: TStreamMetadata;
    ErrorInfo: TRadioErrorInfo;
    Stats: TRadioBufferStats;
    Spectrum: TRadioSpectrumData;
    Attempt: Integer;
    DelayMS: Cardinal;
  end;

  TRadioEventSink = procedure(const Message: TRadioPlayerEventMessage) of object;

  IRadioEventDispatchTarget = interface
    ['{D99BD9F4-764E-49A8-8533-1B6A4A7888A7}']
    procedure Deactivate;
    procedure Deliver(const Message: TRadioPlayerEventMessage);
  end;

  TRadioEventBus = class
  private
    type
      TDispatchThread = class(TThread)
      private
        FOwner: TRadioEventBus;
      protected
        procedure Execute; override;
      public
        constructor Create(AOwner: TRadioEventBus);
      end;
  private
    FDataEvent: TEvent;
    FDeliveryTarget: IRadioEventDispatchTarget;
    FDispatchThread: TDispatchThread;
    FLock: TCriticalSection;
    FMode: TRadioEventDispatchMode;
    FQueue: TQueue<TRadioPlayerEventMessage>;
    FStopping: Boolean;
    function GetMode: TRadioEventDispatchMode;
    function IsStopping: Boolean;
    procedure QueueMainThreadDelivery(const DeliveryTarget: IRadioEventDispatchTarget;
      const Message: TRadioPlayerEventMessage);
    procedure SetMode(const Value: TRadioEventDispatchMode);
    function TryDequeue(out Message: TRadioPlayerEventMessage): Boolean;
  public
    constructor Create(const ASink: TRadioEventSink; AMode: TRadioEventDispatchMode);
    destructor Destroy; override;
    property Mode: TRadioEventDispatchMode read GetMode write SetMode;
    procedure Post(const Message: TRadioPlayerEventMessage);
    procedure Stop;
  end;

implementation

type
  TQueuedMainThreadDelivery = class
  private
    FDeliveryTarget: IRadioEventDispatchTarget;
    FMessage: TRadioPlayerEventMessage;
    procedure Execute;
  public
    constructor Create(const ADeliveryTarget: IRadioEventDispatchTarget;
      const AMessage: TRadioPlayerEventMessage);
  end;

  TRadioEventDispatchTarget = class(TInterfacedObject, IRadioEventDispatchTarget)
  private
    FActive: Boolean;
    FLock: TCriticalSection;
    FSink: TRadioEventSink;
  public
    constructor Create(const ASink: TRadioEventSink);
    destructor Destroy; override;
    procedure Deactivate;
    procedure Deliver(const Message: TRadioPlayerEventMessage);
  end;

constructor TRadioEventDispatchTarget.Create(const ASink: TRadioEventSink);
begin
  inherited Create;
  FActive := True;
  FLock := TCriticalSection.Create;
  FSink := ASink;
end;

constructor TQueuedMainThreadDelivery.Create(const ADeliveryTarget: IRadioEventDispatchTarget;
  const AMessage: TRadioPlayerEventMessage);
begin
  inherited Create;
  FDeliveryTarget := ADeliveryTarget;
  FMessage := AMessage;
end;

procedure TQueuedMainThreadDelivery.Execute;
begin
  try
    if Assigned(FDeliveryTarget) then
      FDeliveryTarget.Deliver(FMessage);
  finally
    Free;
  end;
end;

destructor TRadioEventDispatchTarget.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TRadioEventDispatchTarget.Deactivate;
begin
  FLock.Acquire;
  try
    FActive := False;
  finally
    FLock.Release;
  end;
end;

procedure TRadioEventDispatchTarget.Deliver(const Message: TRadioPlayerEventMessage);
begin
  FLock.Acquire;
  try
    if FActive and Assigned(FSink) then
      FSink(Message);
  finally
    FLock.Release;
  end;
end;

constructor TRadioEventBus.TDispatchThread.Create(AOwner: TRadioEventBus);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TRadioEventBus.TDispatchThread.Execute;
var
  DeliveryTarget: IRadioEventDispatchTarget;
  Message: TRadioPlayerEventMessage;
  Mode: TRadioEventDispatchMode;
begin
  while not Terminated do
  begin
    if FOwner.TryDequeue(Message) then
    begin
      try
        DeliveryTarget := FOwner.FDeliveryTarget;
        Mode := FOwner.Mode;
        if Assigned(DeliveryTarget) then
          case Mode of
            redmMainThread:
              FOwner.QueueMainThreadDelivery(DeliveryTarget, Message);
          else
            DeliveryTarget.Deliver(Message);
          end;
      except
        // Keep dispatching even if one consumer handler fails.
      end;
      Continue;
    end;

    if FOwner.IsStopping then
      Break;

    FOwner.FDataEvent.WaitFor(100);
  end;
end;

constructor TRadioEventBus.Create(const ASink: TRadioEventSink; AMode: TRadioEventDispatchMode);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FQueue := TQueue<TRadioPlayerEventMessage>.Create;
  FDataEvent := TEvent.Create(nil, False, False, '');
  FDeliveryTarget := TRadioEventDispatchTarget.Create(ASink);
  FMode := AMode;
  FDispatchThread := TDispatchThread.Create(Self);
end;

destructor TRadioEventBus.Destroy;
begin
  Stop;
  FDataEvent.Free;
  FQueue.Free;
  FLock.Free;
  inherited Destroy;
end;

function TRadioEventBus.GetMode: TRadioEventDispatchMode;
begin
  FLock.Acquire;
  try
    Result := FMode;
  finally
    FLock.Release;
  end;
end;

function TRadioEventBus.IsStopping: Boolean;
begin
  FLock.Acquire;
  try
    Result := FStopping and (FQueue.Count = 0);
  finally
    FLock.Release;
  end;
end;

procedure TRadioEventBus.QueueMainThreadDelivery(const DeliveryTarget: IRadioEventDispatchTarget;
  const Message: TRadioPlayerEventMessage);
var
  Delivery: TQueuedMainThreadDelivery;
begin
  Delivery := TQueuedMainThreadDelivery.Create(DeliveryTarget, Message);
  TThread.Queue(nil, Delivery.Execute);
end;

procedure TRadioEventBus.Post(const Message: TRadioPlayerEventMessage);
begin
  FLock.Acquire;
  try
    if FStopping then
      Exit;
    FQueue.Enqueue(Message);
  finally
    FLock.Release;
  end;

  FDataEvent.SetEvent;
end;

procedure TRadioEventBus.SetMode(const Value: TRadioEventDispatchMode);
begin
  FLock.Acquire;
  try
    FMode := Value;
  finally
    FLock.Release;
  end;
end;

procedure TRadioEventBus.Stop;
var
  DeliveryTarget: IRadioEventDispatchTarget;
begin
  FLock.Acquire;
  try
    FStopping := True;
    DeliveryTarget := FDeliveryTarget;
  finally
    FLock.Release;
  end;

  if Assigned(DeliveryTarget) then
    DeliveryTarget.Deactivate;

  if Assigned(FDispatchThread) then
  begin
    FDataEvent.SetEvent;
    FDispatchThread.WaitFor;
    FreeAndNil(FDispatchThread);
  end;
end;

function TRadioEventBus.TryDequeue(out Message: TRadioPlayerEventMessage): Boolean;
begin
  FLock.Acquire;
  try
    Result := FQueue.Count > 0;
    if Result then
      Message := FQueue.Dequeue;
  finally
    FLock.Release;
  end;
end;

end.
