program returnsservice;

{$mode objfpc}{$H+}

uses
  cthreads, sysutils, classes, fphttpapp, httpdefs, httproute;

const
  TRACE_POS = 1;
  TRACE_LEN = 15;
  PAYMENT_POS = 16;
  PAYMENT_LEN = 12;
  PROGRAM_POS = 28;
  PROGRAM_LEN = 11;
  RECORD_LEN = 91;
  WINDOW_SECONDS = 60;
  WINDOW_ALLOWANCE = 300;

var
  Records: TStringList;
  WindowStart: TDateTime;
  WindowCount: Integer;
  WindowLock: TRTLCriticalSection;

function FieldAt(const Line: string; Position, Length: Integer): string;
begin
  Result := Trim(Copy(Line, Position, Length));
end;

procedure LoadRecords(const Path: string);
var
  Source: TStringList;
  Index: Integer;
  Line: string;
begin
  Records := TStringList.Create;
  Source := TStringList.Create;
  try
    Source.LoadFromFile(Path);
    for Index := 0 to Source.Count - 1 do
    begin
      Line := Source[Index];
      if System.Length(Line) >= RECORD_LEN then
        Records.Add(Copy(Line, 1, RECORD_LEN));
    end;
  finally
    Source.Free;
  end;
  Writeln(StdErr, Format('loaded %d return records', [Records.Count]));
  Flush(StdErr);
end;

function WithinAllowance: Boolean;
var
  Now_: TDateTime;
begin
  EnterCriticalSection(WindowLock);
  try
    Now_ := Now;
    if (Now_ - WindowStart) * 86400 >= WINDOW_SECONDS then
    begin
      WindowStart := Now_;
      WindowCount := 0;
    end;
    Inc(WindowCount);
    Result := WindowCount <= WINDOW_ALLOWANCE;
  finally
    LeaveCriticalSection(WindowLock);
  end;
end;

procedure PlainText(AResponse: TResponse; Code: Integer; const Body: string);
begin
  AResponse.Code := Code;
  AResponse.ContentType := 'text/plain; charset=us-ascii';
  AResponse.Content := Body;
end;

procedure HandleHealth(ARequest: TRequest; AResponse: TResponse);
begin
  if ARequest = nil then
    Exit;
  PlainText(AResponse, 200, 'UP' + LineEnding);
end;

procedure HandleReturns(ARequest: TRequest; AResponse: TResponse);
var
  ProgramId, PaymentId, Line, Body: string;
  Index: Integer;
  Builder: TStringList;
begin
  if not WithinAllowance then
  begin
    AResponse.SetCustomHeader('Retry-After', '60');
    PlainText(AResponse, 429, 'RATE LIMITED' + LineEnding);
    Exit;
  end;

  ProgramId := Trim(ARequest.GetCustomHeader('X-Program-Id'));
  if ProgramId = '' then
  begin
    PlainText(AResponse, 400, 'MISSING X-PROGRAM-ID' + LineEnding);
    Exit;
  end;

  PaymentId := Trim(ARequest.QueryFields.Values['paymentId']);

  Builder := TStringList.Create;
  try
    for Index := 0 to Records.Count - 1 do
    begin
      Line := Records[Index];
      if FieldAt(Line, PROGRAM_POS, PROGRAM_LEN) <> ProgramId then
        Continue;
      if (PaymentId <> '') and (FieldAt(Line, PAYMENT_POS, PAYMENT_LEN) <> PaymentId) then
        Continue;
      Builder.Add(Line);
    end;
    if Builder.Count = 0 then
      Body := ''
    else
      Body := Builder.Text;
  finally
    Builder.Free;
  end;

  PlainText(AResponse, 200, Body);
end;

var
  PortValue: string;

begin
  InitCriticalSection(WindowLock);
  WindowStart := Now;
  WindowCount := 0;

  LoadRecords('data/returns.txt');

  HTTPRouter.RegisterRoute('/health', @HandleHealth);
  HTTPRouter.RegisterRoute('/returns', @HandleReturns);

  PortValue := GetEnvironmentVariable('PORT');
  if PortValue = '' then
    PortValue := '8084';

  Application.Port := StrToInt(PortValue);
  Application.Threaded := True;
  Application.Initialize;
  Application.Run;
end.
