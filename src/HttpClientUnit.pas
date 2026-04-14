// Lightweight HTTP helper based on WinInet.
// Used by the BugTraq provider to call external issue tracker endpoints.
unit HttpClientUnit;

interface

uses System.SysUtils, System.Classes, Winapi.WinInet, Winapi.Windows;

type
  // Parsed URL components used to initialize WinInet requests.
  TUrl = record
    Scheme: DWORD;
    Port: INTERNET_PORT;
    Host: string;
    Site: string;
  end;

  TWorkBeginEvent = procedure(ASender: TObject; AWorkCountMax: Int64) of object;
  TWorkEndEvent = procedure(ASender: TObject) of object;
  TWorkEvent = procedure(ASender: TObject; AWorkCount: Int64) of object;

  THttpClientHelper = class
  private
    FUserAgent: string;
    FAuthUserName: string;
    FAuthUserPassword: string;
    FIgnoreInvalidCert: boolean;
    FUrlRecord: TUrl;

    FInternetHandle: HINTERNET;
    FConnectionHandle: HINTERNET;
    FRequestHandle: HINTERNET;

    FFlags: DWORD;
    FSendTimeout: integer;
    FConnectTimeout: integer;
    FReceiveTimeout: integer;
    FHTTPCode: DWORD;
    FOnWorkBegin: TWorkBeginEvent;
    FOnWorkEnd: TWorkEndEvent;
    FOnWork: TWorkEvent;

    procedure ParseUrl(const AUrl: string);

    procedure SetOptions(FHandle: HINTERNET);

    procedure OpenService;
    procedure CloseService;

    procedure ConnectToHost;
    procedure CloseConnection;

    procedure OpenRequest(const Method: string);
    procedure CloseRequest;

    function ReadData(AStream: TStream = nil): string;

  public
    property UserAgent: string read FUserAgent write FUserAgent;
    property IgnoreInvalidCert: boolean read FIgnoreInvalidCert write FIgnoreInvalidCert;

    property AuthUserName: string read FAuthUserName write FAuthUserName;
    property AuthUserPassword: string read FAuthUserPassword write FAuthUserPassword;

    property ConnectTimeout: integer read FConnectTimeout write FConnectTimeout;
    property SendTimeout: integer read FSendTimeout write FSendTimeout;
    property ReceiveTimeout: integer read FReceiveTimeout write FReceiveTimeout;

    property OnWork: TWorkEvent read FOnWork write FOnWork;
    property OnWorkBegin: TWorkBeginEvent read FOnWorkBegin write FOnWorkBegin;
    property OnWorkEnd: TWorkEndEvent read FOnWorkEnd write FOnWorkEnd;

    property HTTPCode: DWORD read FHTTPCode;

    constructor Create;
    destructor Destroy; override;

    function Get(const AUrl: string; ADataList: TStringList = nil; AStream: TStream = nil): string;

    class function SimpleGet(const AUrl: string): string;
  end;

implementation

function WinInetErrorMsg(Err: DWORD): string;
var
  ErrMsg: array of Char;
  ErrLen: DWORD;
begin
  if Err = ERROR_INTERNET_EXTENDED_ERROR then
  begin
    ErrLen := 0;
    InternetGetLastResponseInfo(Err, nil, ErrLen);
    if GetLastError() = ERROR_INSUFFICIENT_BUFFER then
    begin
      SetLength(ErrMsg, ErrLen);
      InternetGetLastResponseInfo(Err, PChar(ErrMsg), ErrLen);
      SetString(Result, PChar(ErrMsg), ErrLen);
    end else begin
      Result := 'Unknown WinInet error';
    end;
  end else
    Result := SysErrorMessage(Err);
end;


{ THttpClientHelper }

constructor THttpClientHelper.Create;
begin
  FUserAgent := 'SVNBugTraqDelphi';
  FIgnoreInvalidCert := True; // DEBUG
  FConnectTimeout := 0;
  FSendTimeout := 120 * 1000;
  FReceiveTimeout := 120 * 1000;
end;

destructor THttpClientHelper.Destroy;
begin
  CloseService;
  inherited;
end;

// Convenience helper for one-shot HTTP GET requests.
class function THttpClientHelper.SimpleGet(const AUrl: string): string;
begin
  with THttpClientHelper.Create do
  try
    Result := Get(AUrl, nil);
  finally
    Free;
  end;
end;

// Parses an HTTP or HTTPS URL into WinInet connection components.
procedure THttpClientHelper.ParseUrl(const AUrl: string);
var
  URLComp: TURLComponents;
  P: PChar;
begin
  if AUrl = '' then
    exit;

  FillChar(URLComp, SizeOf(URLComp), 0);
  URLComp.dwStructSize := SizeOf(URLComp);
  URLComp.dwSchemeLength := 1;
  URLComp.dwHostNameLength := 1;
  URLComp.dwURLPathLength := 1;
  P := PChar(AUrl);
  if not InternetCrackUrl(P, 0, 0, URLComp) then
    raise Exception.CreateFmt('Failed to parse URL: %s', [AUrl]);

  if not (URLComp.nScheme in [INTERNET_SCHEME_HTTP, INTERNET_SCHEME_HTTPS]) then
    raise Exception.CreateFmt('Invalid URL: %s', [AUrl]);

  FUrlRecord.Scheme := URLComp.nScheme;
  FUrlRecord.Port := URLComp.nPort;
  FUrlRecord.Host := Copy(AUrl, URLComp.lpszHostName - P + 1, URLComp.dwHostNameLength);
  FUrlRecord.Site := Copy(AUrl, URLComp.lpszUrlPath - P + 1, URLComp.dwUrlPathLength);
  if FUrlRecord.Site = '' then
    FUrlRecord.Site := '/';
end;

// Opens the root WinInet session handle and initializes request flags.
procedure THttpClientHelper.OpenService;
begin
  if FInternetHandle <> nil then
    exit;

  // Check whether a network connection is available.
  if InternetAttemptConnect(0) <> ERROR_SUCCESS then
    raise Exception.Create('Internet connection is not available.');

  // Initialize the WinInet session handle.
  FInternetHandle := InternetOpen(PChar(FUserAgent), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if not Assigned(FInternetHandle) then
    raise Exception.Create('InternetOpen failed. ' + WinInetErrorMsg(GetLastError()));

  FFlags := INTERNET_FLAG_DONT_CACHE;
  if FUrlRecord.Scheme = INTERNET_SCHEME_HTTPS then
  begin
    FFlags := FFlags or INTERNET_FLAG_SECURE;
    if (FIgnoreInvalidCert) then
      FFlags := FFlags or (INTERNET_FLAG_IGNORE_CERT_CN_INVALID or
                         INTERNET_FLAG_IGNORE_CERT_DATE_INVALID or
                         SECURITY_FLAG_IGNORE_UNKNOWN_CA or
                         SECURITY_FLAG_IGNORE_REVOCATION);
  end;
end;

procedure THttpClientHelper.CloseService;
begin
  CloseRequest;
  CloseConnection;

  if Assigned(FInternetHandle) then
  begin
    InternetCloseHandle(FInternetHandle);
    FInternetHandle := nil;
  end;
end;

procedure THttpClientHelper.ConnectToHost;
begin
  if FConnectionHandle <> nil then
    exit;

  if not Assigned(FInternetHandle) then
    OpenService;

  FConnectionHandle := InternetConnect(FInternetHandle, PChar(FUrlRecord.Host), FUrlRecord.Port, PChar(FAuthUserName),
    PChar(FAuthUserPassword), INTERNET_SERVICE_HTTP, 0, 0);

  if not Assigned(FConnectionHandle) then
  begin
    CloseService;
    raise Exception.Create('InternetConnect failed. ' + WinInetErrorMsg(GetLastError()));
  end;
end;

procedure THttpClientHelper.CloseConnection;
begin
  if FConnectionHandle <> nil then
  begin
    InternetCloseHandle(FConnectionHandle);
    FConnectionHandle := nil;
  end;
end;

procedure THttpClientHelper.CloseRequest;
begin
  if FRequestHandle <> nil then
  begin
    InternetCloseHandle(FRequestHandle);
    FRequestHandle := nil;
  end;
end;

procedure THttpClientHelper.OpenRequest(const Method: string);
const
  AcceptTypes: array[0..1] of PChar = ('*/*', nil);
begin
  if not Assigned(FConnectionHandle) then
    ConnectToHost;

  FRequestHandle := HttpOpenRequest(FConnectionHandle, PChar(Method), PChar(FUrlRecord.Site), nil, nil, @AcceptTypes, FFlags, 1);

  if not Assigned(FRequestHandle) then
    raise Exception.Create('HttpOpenRequest failed. ' + WinInetErrorMsg(GetLastError()));

  SetOptions(FRequestHandle);
end;


function THttpClientHelper.Get(const AUrl: string; ADataList: TStringList = nil; AStream: TStream = nil): string;
var
  QS: string;
  H: string;
begin
  Result := '';

  if (ADataList <> nil) and (ADataList.Count > 0) then
  begin
    ADataList.LineBreak := '&';
    ADataList.NameValueSeparator := '=';
    QS := ADataList.Text;
    QS := StringReplace(QS, sLineBreak, '', [rfReplaceAll]);

    if Pos('?', AUrl) > 0 then
      ParseUrl(AUrl + '&' + QS)
    else
      ParseUrl(AUrl + '?' + QS);
  end
  else
    ParseUrl(AUrl);

  OpenRequest('GET');

  try

    H :=
      'User-Agent: ' + FUserAgent + #13#10 +
      'Accept: */*' + #13#10;

    if not HttpAddRequestHeaders(
      FRequestHandle,
      PChar(H),
      Length(H),
      HTTP_ADDREQ_FLAG_ADD
    ) then
      raise Exception.Create('Failed to add request headers. ' + WinInetErrorMsg(GetLastError()));

    if not HttpSendRequest(FRequestHandle, nil, 0, nil, 0) then
      raise Exception.CreateFmt('HttpSendRequest failed. (%d, %s)', [GetLastError(), AUrl]);

    Result := ReadData(AStream);
  finally
    CloseRequest;
  end;
end;


// Reads the full HTTP response into a string or an output stream.
function THttpClientHelper.ReadData(AStream: TStream = nil): string;
const
  MaxStatusText = 4096;
var
  FLength, FIndex: DWORD;
  FContentLength: DWORD;
  FError: string;

  FSize, FDownloaded: DWord;
  FBuffer: TBytes;
  FStream: TStream;
  FFullSize: int64;
begin
  FFullSize := 0;
  FLength := SizeOf(FHTTPCode);
  FIndex := 0;

   // Handle HTTP status errors before reading the response body.
  if HttpQueryInfo(FRequestHandle, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @FHTTPCode, FLength, FIndex) and
     (FHTTPCode >= 300) then
  begin

    FIndex := 0;
    FSize := MaxStatusText;
    SetLength(FError, FSize);
    if HttpQueryInfo(FRequestHandle, HTTP_QUERY_STATUS_TEXT, @FError[1], FSize, FIndex) then
    begin
      SetLength(FError, FSize div SizeOf(Char));
      raise Exception.CreateFmt('%s (%d) - ''%s''', [FError, FHTTPCode, FUrlRecord.Host]);
    end;
  end

  else if Assigned(FOnWorkBegin) then
  begin
    FIndex := 0;
    FSize := SizeOf(FContentLength);
    if HttpQueryInfo(FRequestHandle, HTTP_QUERY_CONTENT_LENGTH or HTTP_QUERY_FLAG_NUMBER, @FContentLength, FSize, FIndex) then
      FOnWorkBegin(Self, FContentLength)
    else
      FOnWorkBegin(Self, -1);
  end;

  if AStream <> nil then
    FStream := AStream
  else
    FStream := TStringStream.Create('', TEncoding.UTF8);

  try
    repeat
      if not InternetQueryDataAvailable(FRequestHandle, FSize, 0, 0) then
        raise Exception.Create('InternetQueryDataAvailable failed. ' + WinInetErrorMsg(GetLastError()));

      if FSize > 0 then
      begin
        SetLength(FBuffer, FSize);
        if not InternetReadFile(FRequestHandle, @FBuffer[0], FSize, FDownloaded) then
          raise Exception.Create('InternetReadFile failed. ' + WinInetErrorMsg(GetLastError()));

        if FDownloaded > 0 then
          FStream.Write(FBuffer[0], FDownloaded);

        if Assigned(FOnWork) then
        begin
          FFullSize := FFullSize + FDownloaded;
          FOnWork(Self, FFullSize);
        end;
      end;
    until FSize = 0;

    if Assigned(FOnWorkEnd) then
      FOnWorkEnd(Self);

    if AStream = nil then
      Result := (FStream as TStringStream).DataString
    else
      Result := '';
  finally
    if AStream = nil then
      FStream.Free;
  end;
end;

procedure THttpClientHelper.SetOptions(FHandle: HINTERNET);
begin
  if FConnectTimeout > 0 then
    InternetSetOption(FHandle, INTERNET_OPTION_CONNECT_TIMEOUT, Pointer(@FConnectTimeout), SizeOf(FConnectTimeout));

  if FSendTimeout > 0 then
    InternetSetOption(FHandle, INTERNET_OPTION_SEND_TIMEOUT, Pointer(@FSendTimeout), SizeOf(FSendTimeout));

  if FReceiveTimeout > 0 then
    InternetSetOption(FHandle, INTERNET_OPTION_RECEIVE_TIMEOUT, Pointer(@FReceiveTimeout), SizeOf(FReceiveTimeout));
end;

end.
