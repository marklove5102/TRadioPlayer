unit Radio.Logging;

interface

type
  TRadioLogLevel = (rllDebug, rllInfo, rllWarning, rllError);

  IRadioLogger = interface
    ['{D39F53AB-6EFC-4D42-92A9-9E07EE7D7D3A}']
    procedure Log(Level: TRadioLogLevel; const MessageText: string);
  end;

implementation

end.
