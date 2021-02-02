unit UGitHub;

interface

procedure CheckGitHubUpdate(const Repository, CurrentVersion: string);

implementation

uses System.Net.HttpClient, System.JSON, Vcl.Dialogs, Vcl.Graphics,
  System.SysUtils, System.UITypes, System.Classes, Vcl.ExtActns,
  System.IOUtils, System.Zip, Winapi.ShellAPI, Winapi.Windows,
  UFrm, UCommon, Vcl.Forms;

const URL_GITHUB = 'https://api.github.com/repos/%s/releases/latest';

type
  TThCheck = class(TThread)
  protected
    procedure Execute; override;
  private
    Repository: string;
    CurrentVersion: string;

    procedure Check;
    procedure Download(const URL: string);
    procedure Log(const A: string; bBold: Boolean = True; Color: TColor = clBlack);
  end;

procedure TThCheck.Execute;
begin
  try
    Check;
  except
    on E: Exception do
      Log('ERROR: '+E.Message, True, clRed);
  end;

  Synchronize(
    procedure
    begin
      Frm.SetButtons(True);
    end);
end;

procedure TThCheck.Log(const A: string; bBold: Boolean = True; Color: TColor = clBlack);
begin
  Synchronize(
    procedure
    begin
      Frm.Log(A, bBold, Color);
    end);
end;

procedure TThCheck.Check;
var
  H: THTTPClient;
  Res, tag_url, tag_version, tag_zip: string;
  data: TJSONObject;
  Confirm: Boolean;
begin
  Log('Checking for component update...');

  H := THTTPClient.Create;
  try
    Res := H.Get(Format(URL_GITHUB, [Repository])).ContentAsString;
  finally
    H.Free;
  end;

  data := TJSONObject.ParseJSONValue(Res) as TJSONObject;
  try
    if data.GetValue('id')=nil then
      raise Exception.Create('No releases found on GitHub');

    tag_version := data.GetValue('tag_name').Value;
    tag_url := data.GetValue('html_url').Value;
    tag_zip := data.GetValue('zipball_url').Value;
  finally
    data.Free;
  end;

  if tag_version.StartsWith('v', True) then Delete(tag_version, 1, 1);

  if CurrentVersion<>tag_version then
  begin
    Log(Format('New version "%s" available.', [tag_version]), True, clPurple);

    Synchronize(
      procedure
      begin
        Confirm := MessageDlg(Format(
          'There is a new version "%s" of the component available at GitHub.'+
          ' Do you want to update it automatically?'+#13#13+
          'The contents of the component''s current folder will be kept'+
          ' in a new folder with the current date and time suffix.', [tag_version]),
          mtInformation, mbYesNo, 0) = mrYes;
      end);

    if Confirm then
      Download(tag_zip);
  end else
    Log('Your version is already updated.', True, clGreen);
end;

procedure TThCheck.Download(const URL: string);
var Dw: TDownLoadURL;
  TmpPath, TmpFile: string;
  Z: TZipFile;
  ZInternalFile: string;
  ZInternalFileFound: Boolean;
begin
  Log('Downloading new version...');

  TmpPath := ChangeFileExt(TPath.GetTempFileName, string.Empty);
  if not CreateDir(TmpPath) then
    raise Exception.Create('Could not create temporary folder');

  TmpFile := TPath.Combine(TmpPath, 'data.zip');

  Dw := TDownLoadURL.Create(nil);
  try
    Dw.URL := URL;
    Dw.Filename := TmpFile;
    Dw.ExecuteTarget(nil);
  finally
    Dw.Free;
  end;

  Log('Extracting new Component Install app...');

  Z := TZipFile.Create;
  try
    Z.Open(TmpFile, zmRead);

    ZInternalFileFound := False;

    for ZInternalFile in Z.FileNames do
      if SameText(NormalizeAndRemoveFirstDir(ZInternalFile), COMPINST_EXE) then
      begin
        ZInternalFileFound := True;
        Z.Extract(ZInternalFile, TmpPath, False);
        Break;
      end;

    if not ZInternalFileFound then
      raise Exception.Create('Component Installer not found in zip file');
  finally
    Z.Free;
  end;

  //***FOR TEST ONLY
  if FileExists(TPath.Combine(AppDir, 'NO_UPD_CI_APP.TXT')) then
  begin
    TFile.Copy(Application.ExeName, TPath.Combine(TmpPath, COMPINST_EXE), True);
  end;
  //***

  Log('Running new app...');

  SetEnvironmentVariable('UPD_PATH', PChar(AppDir));
  ShellExecute(0, '', PChar(TPath.Combine(TmpPath, COMPINST_EXE)), '/upd', '', SW_SHOWNORMAL);

  Synchronize(Application.Terminate);
end;

procedure CheckGitHubUpdate(const Repository, CurrentVersion: string);
var C: TThCheck;
begin
  if Repository.IsEmpty then Exit;  

  Frm.SetButtons(False);

  C := TThCheck.Create(True);
  C.Repository := Repository;
  C.CurrentVersion := CurrentVersion;
  C.Start;
end;

end.
