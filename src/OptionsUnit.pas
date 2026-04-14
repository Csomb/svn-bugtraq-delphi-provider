// Simple options dialog for configuring the BugTraq provider.
// Currently only stores the issue tracker endpoint URL.
unit OptionsUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TOptionsForm = class(TForm)
    URLEdit: TLabeledEdit;
    OK: TButton;
    procedure OKClick(Sender: TObject);
  private
    function GetUrl: string;
    procedure SetUrl(const Value: string);
  public
    property Url: string read GetUrl write SetUrl;
  end;

implementation

{$R *.dfm}

function TOptionsForm.GetUrl: string;
begin
  Result := URLEdit.Text;
end;

procedure TOptionsForm.OKClick(Sender: TObject);
begin
  if URLEdit.Text = '' then
  begin
    URLEdit.SetFocus;
    raise Exception.Create('Please enter a valid URL.');
  end;

  ModalResult := mrOK;
end;

procedure TOptionsForm.SetUrl(const Value: string);
begin
  URLEdit.Text := Value;
end;

end.
