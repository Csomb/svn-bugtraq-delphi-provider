library SVNBugTraqDelphiProvider;

uses
  ComServ,
  BugTraqProviderUnit in 'BugTraqProviderUnit.pas' {BugTraqProvider: CoClass},
  SelectTicketFormUnit in 'SelectTicketFormUnit.pas' {SelectTicketForm},
  HttpClientUnit in 'HttpClientUnit.pas',
  OptionsUnit in 'OptionsUnit.pas' {OptionsForm};

exports
  DllGetClassObject,
  DllCanUnloadNow,
  DllRegisterServer,
  DllUnregisterServer;

{$R *.RES}

begin
end.
