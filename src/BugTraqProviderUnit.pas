// COM provider implementation for TortoiseSVN BugTraq integration.
// This unit registers the provider class, exposes the required interfaces,
// and handles configuration and issue selection dialogs.
unit BugTraqProviderUnit;

{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Winapi.Windows,
  Winapi.ActiveX,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  ComObj,
  ComServ;

const
  // TortoiseSVN BugTraq provider category.
  // The provider must register itself under this COM category
  // so TortoiseSVN can discover it as a BugTraq plugin.
  CATID_BugTraqProvider: TGUID = '{3494FA92-B139-4730-9591-01135D5E7831}';

type
  // TortoiseSVN BugTraq provider interfaces.
  // These interface IDs are defined by TortoiseSVN and must not be changed.
  IBugTraqProvider = interface(IUnknown)
    ['{298B927C-7220-423C-B7B4-6E241F00CD93}']
    function ValidateParameters(hParentWnd: HWND; parameters: PWideChar; out valid: WordBool): HResult; stdcall;
    function GetLinkText(hParentWnd: HWND; parameters: PWideChar; out linkText: WideString): HResult; stdcall;
    function GetCommitMessage(hParentWnd: HWND; parameters: PWideChar; commonRoot: PWideChar; pathList: PSafeArray;
      originalMessage: PWideChar; out newMessage: WideString): HResult; stdcall;
  end;

  // Extended interface used by newer TortoiseSVN integrations.
  IBugTraqProvider2 = interface(IBugTraqProvider)
    ['{C5C85E31-2F9B-4916-A7BA-8E27D481EE83}']
    function GetCommitMessage2(hParentWnd: HWND; parameters: PWideChar; commonURL: PWideChar; commonRoot: PWideChar;
      pathList: PSafeArray; originalMessage: PWideChar; bugID: PWideChar; out bugIDOut: WideString;
      out revPropNames: PSafeArray; out revPropValues: PSafeArray; out newMessage: WideString): HResult; stdcall;

    function CheckCommit(hParentWnd: HWND; parameters: PWideChar; commonURL: PWideChar; commonRoot: PWideChar;
      pathList: PSafeArray; commitMessage: PWideChar; out errorMessage: WideString): HResult; stdcall;

    function OnCommitFinished(hParentWnd: HWND; commonRoot: PWideChar; pathList: PSafeArray; logMessage: PWideChar;
      revision: ULONG; out error: WideString): HResult; stdcall;

    function HasOptions(out ret: WordBool): HResult; stdcall;
    function ShowOptionsDialog(hParentWnd: HWND; parameters: PWideChar; out newparameters: WideString): HResult; stdcall;
  end;

type
  // COM class implementing the TortoiseSVN BugTraq provider interfaces.
  TBugTraqProvider = class(TComObject, IBugTraqProvider, IBugTraqProvider2)
  public
    procedure Initialize; override;
  protected
    // IBugTraqProvider
    function ValidateParameters(hParentWnd: HWND; parameters: PWideChar; out valid: WordBool): HResult; stdcall;
    function GetLinkText(hParentWnd: HWND; parameters: PWideChar; out linkText: WideString): HResult; stdcall;
    function GetCommitMessage(hParentWnd: HWND; parameters, commonRoot: PWideChar; pathList: PSafeArray;
      originalMessage: PWideChar; out newMessage: WideString): HResult; stdcall;

    // IBugTraqProvider2
    function GetCommitMessage2(hParentWnd: HWND; parameters, commonURL, commonRoot: PWideChar; pathList: PSafeArray;
      originalMessage, bugID: PWideChar; out bugIDOut: WideString; out revPropNames, revPropValues: PSafeArray;
      out newMessage: WideString): HResult; stdcall;

    function CheckCommit(hParentWnd: HWND; parameters, commonURL, commonRoot: PWideChar; pathList: PSafeArray;
      commitMessage: PWideChar; out errorMessage: WideString): HResult; stdcall;

    function OnCommitFinished(hParentWnd: HWND; commonRoot: PWideChar; pathList: PSafeArray; logMessage: PWideChar;
      revision: ULONG; out error: WideString): HResult; stdcall;

    function HasOptions(out ret: WordBool): HResult; stdcall;
    function ShowOptionsDialog(hParentWnd: HWND; parameters: PWideChar; out newparameters: WideString): HResult; stdcall;
  end;

  TBugTraqProviderFactory = class(TComObjectFactory)
  public
    procedure UpdateRegistry(Register: Boolean); override;
  end;

implementation

uses
  SelectTicketFormUnit, System.UITypes, OptionsUnit;

const
  // CLSID of the COM provider class.
  // This GUID identifies the provider registration in the Windows registry.
  CLASS_BugTraqProvider: TGUID = '{184E70C3-9F1F-4F00-AAF3-69F307A658E7}';

// Extracts the provider URL from the TortoiseSVN parameter string.
// Current format: "url=https://example.com/..."
// Additional parameters can be added later if needed.
function ExtractUrl(const Params: string): string;
const
  Prefix = 'url=';
var
  S: string;
begin
  Result := '';
  S := Trim(Params);
  if SameText(Copy(S, 1, Length(Prefix)), Prefix) then
    Result := Trim(Copy(S, Length(Prefix) + 1, MaxInt));
end;


{ TBugTraqProvider }

function TBugTraqProvider.ValidateParameters(hParentWnd: HWND; parameters: PWideChar; out valid: WordBool): HResult;
var
  Url: string;
begin
  Url := ExtractUrl(string(parameters));
  valid := Url <> '';
  Result := S_OK;
end;

function TBugTraqProvider.GetLinkText(hParentWnd: HWND; parameters: PWideChar; out linkText: WideString): HResult;
begin
  linkText := 'Select issue';
  Result := S_OK;
end;

function TBugTraqProvider.GetCommitMessage(hParentWnd: HWND; parameters, commonRoot: PWideChar; pathList: PSafeArray;
  originalMessage: PWideChar; out newMessage: WideString): HResult;
begin
  // Legacy fallback for clients using the older IBugTraqProvider method.
  newMessage := WideString(originalMessage);
  Result := S_OK;
end;

function TBugTraqProvider.GetCommitMessage2(hParentWnd: HWND; parameters, commonURL, commonRoot: PWideChar;
  pathList: PSafeArray; originalMessage, bugID: PWideChar; out bugIDOut: WideString; out revPropNames, revPropValues: PSafeArray;
  out newMessage: WideString): HResult;
var
  F: TSelectTicketForm;
begin
  F := TSelectTicketForm.Create(nil);
  try
    // Attach the dialog to the TortoiseSVN parent window
    // so it behaves as a child modal dialog of the host UI.
    SetWindowLongPtr(F.Handle, GWLP_HWNDPARENT, hParentWnd);
    F.Url := ExtractUrl(string(parameters));


    if F.ShowModal = mrOk then
    begin
      bugIDOut := F.SelectedTicketId;

      newMessage := WideString(originalMessage);
      if newMessage <> '' then
        newMessage := newMessage + sLineBreak;

      newMessage := newMessage + F.SelectedTitle;
    end
    else
    begin
      bugIDOut := WideString(bugID);
      newMessage := WideString(originalMessage);
    end;

    revPropNames := nil;
    revPropValues := nil;
    Result := S_OK;

  finally
    F.Free;
  end;

end;

function TBugTraqProvider.CheckCommit(hParentWnd: HWND; parameters, commonURL, commonRoot: PWideChar;
  pathList: PSafeArray; commitMessage: PWideChar; out errorMessage: WideString): HResult;
begin
  // No additional commit validation is performed by this implementation.
  errorMessage := '';
  Result := S_OK;
end;

function TBugTraqProvider.OnCommitFinished(hParentWnd: HWND; commonRoot: PWideChar; pathList: PSafeArray;
  logMessage: PWideChar; revision: ULONG; out error: WideString): HResult;
begin
  // No post-commit action is performed by this implementation.
  error := '';
  Result := S_OK;
end;

function TBugTraqProvider.HasOptions(out ret: WordBool): HResult;
begin
  // Enable the Options button in the TortoiseSVN integration settings.
  ret := True;
  Result := S_OK;
end;

procedure TBugTraqProvider.Initialize;
begin
  inherited;
end;


function TBugTraqProvider.ShowOptionsDialog(
  hParentWnd: HWND;
  parameters: PWideChar;
  out newparameters: WideString
): HResult;
var
  F: TOptionsForm;
begin
  F := TOptionsForm.Create(nil);
  try
    // Attach the dialog to the TortoiseSVN parent window
    // so it behaves as a child modal dialog of the host UI.
    SetWindowLongPtr(F.Handle, GWLP_HWNDPARENT, hParentWnd);
    F.Url := ExtractUrl(string(parameters));

    if F.ShowModal = mrOk then
    begin
      newparameters := 'url=' + Trim(F.Url);
      Result := S_OK;
    end
    else
    begin
      newparameters := parameters;
      Result := S_FALSE;
    end;
  finally
    F.Free;
  end;
end;

{ TBugTraqProviderFactory }

// Register the provider under the TortoiseSVN BugTraq COM category
// so it appears in the issue tracker plugin list.
procedure TBugTraqProviderFactory.UpdateRegistry(Register: Boolean);
var
  Reg: TRegistry;
  Key: string;
begin
  inherited UpdateRegistry(Register);

  Key := Format('CLSID\%s\Implemented Categories\%s',
    [GUIDToString(CLASS_BugTraqProvider), GUIDToString(CATID_BugTraqProvider)]);

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CLASSES_ROOT;
    if Register then
    begin
      Reg.OpenKey(Key, True);
      Reg.CloseKey;
    end
    else
      Reg.DeleteKey(Key);
  finally
    Reg.Free;
  end;
end;

initialization
  TBugTraqProviderFactory.Create(
    ComServer,
    TBugTraqProvider,
    CLASS_BugTraqProvider,
    'SVNBugTraqDelphi.Provider',
    'SVN BugTraq Delphi Provider',
    ciMultiInstance,
    tmApartment
  );


end.
