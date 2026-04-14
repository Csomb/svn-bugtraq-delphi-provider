// Issue selection dialog used by the BugTraq provider.
// It loads issue data from the configured endpoint and lets the user select one item.
unit SelectTicketFormUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Data.DB, Vcl.StdCtrls,
  Vcl.Grids, Vcl.DBGrids, Datasnap.DBClient;

type
  TSelectTicketForm = class(TForm)
    ListaDS: TDataSource;
    OKBtn: TButton;
    CDS: TClientDataSet;
    CDSPARTNER: TStringField;
    CDSID: TIntegerField;
    CDSDESCRIPTION: TStringField;
    Grid: TDBGrid;
    procedure OKBtnClick(Sender: TObject);
  private
    FUrl: string;
    FSelectedTitle: string;
    FSelectedTicketId: string;
    procedure LoadTickets;
    procedure SetUrl(const Value: string);
  public
    property Url: string write SetUrl;
    property SelectedTicketId: string read FSelectedTicketId write FSelectedTicketId;
    property SelectedTitle: string read FSelectedTitle write FSelectedTitle;
  end;

implementation

uses
  Data.DBXJSON, HttpClientUnit;

{$R *.dfm}

// Returns the string value of a named property from a JSON object.
// Returns an empty string if the property is missing.
function JsonValueOf(AObject: TJSONObject; const AName: string): string;
var
  I: Integer;
  Pair: TJSONPair;
begin
  Result := '';
  if AObject = nil then
    Exit;

  for I := 0 to AObject.Size - 1 do
  begin
    Pair := AObject.Get(I);
    if Assigned(Pair) and SameText(Pair.JsonString.Value, AName) then
    begin
      if Assigned(Pair.JsonValue) then
        Result := Pair.JsonValue.Value;
      Exit;
    end;
  end;
end;

// Loads the issue list from the configured HTTP endpoint
// and populates the in-memory dataset displayed in the grid.
procedure TSelectTicketForm.LoadTickets;
var
  S: string;
  JsonValue: TJSONValue;
  JsonArray: TJSONArray;
  JsonObject: TJSONObject;
  I: Integer;
  PartnerStr: string;
  IdStr: string;
  DescStr: string;
begin
  if Trim(FUrl) = '' then
    raise Exception.Create('Provider URL is not configured.');

  if not CDS.Active then
    CDS.CreateDataSet
  else
    CDS.EmptyDataSet;

  S := THttpClientHelper.SimpleGet(FUrl);

  JsonValue := TJSONObject.ParseJSONValue(S);
  if not Assigned(JsonValue) then
    raise Exception.Create('Invalid JSON response.');

  try
    if not (JsonValue is TJSONArray) then
      raise Exception.Create('The JSON response is not an array.');

    JsonArray := TJSONArray(JsonValue);

    for I := 0 to JsonArray.Size - 1 do
    begin
      if not (JsonArray.Get(I) is TJSONObject) then
        Continue;

      JsonObject := TJSONObject(JsonArray.Get(I));

      PartnerStr := JsonValueOf(JsonObject, 'partner');
      IdStr := JsonValueOf(JsonObject, 'id');
      DescStr := JsonValueOf(JsonObject, 'desc');

      CDS.AppendRecord([PartnerStr, StrToIntDef(IdStr, 0), DescStr]);
    end;
  finally
    JsonValue.Free;
  end;
end;

// Returns the currently selected issue back to the provider.
procedure TSelectTicketForm.OKBtnClick(Sender: TObject);
begin
  if not CDS.IsEmpty then
  begin
    SelectedTicketId := CDSID.AsString;
    SelectedTitle := CDSDESCRIPTION.AsString;
    ModalResult := mrOk;
  end;
end;

procedure TSelectTicketForm.SetUrl(const Value: string);
begin
  FUrl := Value;
  LoadTickets;
end;

end.
