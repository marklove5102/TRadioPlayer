program ConsoleRadioPlayer;

{$APPTYPE CONSOLE}

uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
{$IFDEF FPC}
  SysUtils,
{$ELSE}
  {$IF CompilerVersion >= 23.0}
  System.SysUtils,
  {$ELSE}
  SysUtils,
  {$IFEND}
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
