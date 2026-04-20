unit Radio.Platform;

interface

uses
{$IFDEF MSWINDOWS}
  {$IFDEF FPC}
  Windows,
  {$ELSE}
    {$IF CompilerVersion >= 23.0}
  Winapi.Windows,
    {$ELSE}
  Windows,
    {$IFEND}
  {$ENDIF}
{$ENDIF}
{$IFDEF FPC}
  SysUtils;
{$ELSE}
  System.SysUtils;
{$ENDIF}

function GetTickCountMS: Cardinal;

implementation

function GetTickCountMS: Cardinal;
begin
{$IFDEF MSWINDOWS}
  Result := GetTickCount;
{$ELSE}
  Result := Cardinal(GetTickCount64 and High(Cardinal));
{$ENDIF}
end;

end.
