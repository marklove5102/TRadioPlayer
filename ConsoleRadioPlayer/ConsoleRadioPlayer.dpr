program ConsoleRadioPlayer;

{$APPTYPE CONSOLE}

uses
{$IF CompilerVersion >= 23.0}
  System.SysUtils,
{$ELSE}
  SysUtils,
{$IFEND}
  ConsoleRadioPlayer.App in 'ConsoleRadioPlayer.App.pas';

var
  App: TConsoleRadioPlayerApp;

begin
  App := TConsoleRadioPlayerApp.Create;
  try
    Halt(App.Run);
  finally
    App.Free;
  end;
end.
