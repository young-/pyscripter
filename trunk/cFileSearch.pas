{-----------------------------------------------------------------------------
 Unit Name: cFileSearch
 Author:    Kiriakos Vlahos
 Date:      29-May-2005
 Purpose:
 History:   Based on GExperts (www.gexperts.org) unit and covered by its licence

GExperts License Agreement
GExperts is copyright 1996-2005 by GExperts, Inc, Erik Berry, and several other
authors who have submitted their code for inclusion. This license agreement only covers code written by GExperts, Inc and Erik Berry. You should contact the other authors concerning their respective copyrights and conditions.

The rules governing the use of GExperts and the GExperts source code are derived
from the official Open Source Definition, available at http://www.opensource.org.
The conditions and limitations are as follows:

    * Usage of GExperts binary distributions is permitted for all developers.
      You may not use the GExperts source code to develop proprietary or
      commercial products including plugins or libraries for those products.
      You may use the GExperts source code in an Open Source project, under the
      terms listed below.
    * You may not use the GExperts source code to create and distribute custom
      versions of GExperts under the "GExperts" name. If you do modify and
      distribute custom versions of GExperts, the binary distribution must be
      named differently and clearly marked so users can tell they are not using
      the official GExperts distribution. A visible and unmodified version of
      this license must appear in any modified distribution of GExperts.
    * Custom distributions of GExperts must include all of the custom changes
      as a patch file that can be applied to the original source code. This
      restriction is in place to protect the integrity of the original author's
      source code. No support for modified versions of GExperts will be provided
      by the original authors or on the GExperts mailing lists.
    * All works derived from GExperts must be distributed under a license
      compatible with this license and the official Open Source Definition,
      which can be obtained from http://www.opensource.org/.
    * Please note that GExperts, Inc. and the other contributing authors hereby
      state that this package is provided "as is" and without any express or
      implied warranties, including, but not without limitation, the implied
      warranties of merchantability and fitness for a particular purpose. In
      other words, we accept no liability for any damage that may result from
      using GExperts or programs that use the GExperts source code.
 -----------------------------------------------------------------------------}

unit cFileSearch;

interface

uses
  SysUtils, Classes, SynRegExpr, SynUnicode;

type

  TSearchOption = (soCaseSensitive, soWholeWord, soRegEx);

  TSearchOptions = set of TSearchOption;

  TFoundEvent = procedure(Sender: TObject; LineNo: Integer; const Line: WideString; SPos, EPos: Integer) of object;

//  ELineTooLong = class(Exception);

  // We separate the grep code from the file management code in TSearcher
  TBaseSearcher = class(TObject)
  private
  protected
    FOnFound: TFoundEvent;
    FOnStartSearch: TNotifyEvent;
    procedure SignalStartSearch; virtual;
    procedure SignalFoundMatch(LineNo: Integer; const Line: WideString; SPos, EPos: Integer); virtual;
  protected
    BLine: WideString; // The current search line,
    FLineNo: Integer;
    fSearchLines : TUnicodeStrings;
    FNoComments: Boolean;
    FSearchOptions: TSearchOptions;
    FPattern: WideString;
    FFileName: WideString;
    FRegExpr : TRegExpr;
    procedure DoSearch;
    procedure PatternMatch;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetPattern(const Value: WideString);
    property NoComments: Boolean read FNoComments write FNoComments;
    property Pattern: WideString read FPattern write SetPattern;
    property SearchOptions: TSearchOptions read FSearchOptions write FSearchOptions;
    property OnFound: TFoundEvent read FOnFound write FOnFound;
    property OnStartSearch: TNotifyEvent read FOnStartSearch write FOnStartSearch;
  end;

  TSearcher = class(TBaseSearcher)
  private
    procedure Reset;
  protected
    procedure SetFileName(const Value: WideString);
  protected
  public
    constructor Create(const SearchFileName: WideString);
    procedure Execute;
  published
    property FileName: WideString read FFileName write SetFileName;
  end;

implementation

uses
  Windows, uEditAppIntfs, Dialogs, StringResources,
  TntSysUtils, TntClasses, uCommonFunctions, WideStrUtils, gnugettext;

const
  SearchLineSize = 1024;

{ TSearcher }

constructor TSearcher.Create(const SearchFileName: WideString);
begin
  inherited Create;

  if SearchFileName <> '' then
    SetFileName(SearchFileName);
end;

procedure TSearcher.SetFileName(const Value: WideString);

  function GetFileInterface: Boolean;
  var
    Encoding : TFileSaveFormat;
  begin
    Result := False;
    if not WideFileExists(FFileName) then
      Exit;
    Result := LoadFileIntoWideStrings(fFileName, fSearchLines, Encoding);
  end;

  function GetModuleInterface: Boolean;
  var
    Editor : IEditor;
  begin
    Result := False;
    Editor := GI_EditorFactory.GetEditorByNameOrTitle(FFileName);
    if Assigned(Editor) then begin
      fSearchLines.Assign(Editor.SynEdit.Lines);
    //      FSearchStream := TStringStream.Create(Editor.SynEdit.Text);
      Result := True;
    end;
  end;

begin
  FFileName := Value;

  if not GetModuleInterface and not GetFileInterface then
    FFileName := '';
  if FFileName <> '' then
    Reset;
end;

procedure TSearcher.Reset;
begin
  FLineNo := 0;
end;

procedure TSearcher.Execute;
begin
  Reset;
  DoSearch;
end;


{ TBaseSearcher }

constructor TBaseSearcher.Create;
begin
  inherited Create;
  FSearchLines := TUnicodeStringList.Create;
  FRegExpr := nil;
end;

destructor TBaseSearcher.Destroy;
begin
  FreeAndNil(FSearchLines);
  FreeAndNil(FRegExpr);

  inherited Destroy;
end;

procedure TBaseSearcher.DoSearch;
//resourcestring
//  SLineLengthError = 'File Search detected a line longer than %d characters in:'+sLineBreak+
//                     '%s.' +sLineBreak+
//                     'Likely, this is an unsupported binary file type.';
var
  i: Integer;
  LPos: Integer;
  PPos : PWideChar;
begin
  SignalStartSearch;
  for i := 0 to fSearchLines.Count - 1 do begin
    BLine := fSearchLines[i];

    if BLine = '' then continue;

    if FNoComments then begin
      PPos := WStrScan(PWideChar(BLine), '#');
      if Assigned(PPos) then begin
        LPos := PPos - PWideChar(BLine) + 1;
        Delete(BLine, LPos, MaxInt);
      end;
      if BLine = '' then continue;
      if Length(BLine) > SearchLineSize then
      begin
        // Likely to be a binary file
         // Just ingnore Issue 74
        //MessageDlg(E.Message, mtWarning, [mbOK], 0);
        Exit;
      end;

    end;
    FLineNo := Succ(i);
    PatternMatch;
  end;
end;

procedure TBaseSearcher.SetPattern(const Value: WideString);
begin
  fPattern := Value;
  if soRegEx in SearchOptions then begin
    if not Assigned(fRegExpr) then
      fRegExpr := TRegExpr.Create();
    fRegExpr.ModifierI := soCaseSensitive in SearchOptions;
    fRegExpr.ModifierI := True;
    try
      fRegExpr.Expression := Value;
      fRegExpr.Compile;
    except
      on E: ERegExpr do
        raise Exception.CreateFmt(_(SInvalidRegularExpression), [E.Message]);
    end;
  end else begin
    if not(soCaseSensitive in SearchOptions) then
      fPattern := WideUpperCase(Value);
  end;
end;

procedure TBaseSearcher.PatternMatch;
{
  Use RegExpr if RegExpr soRegEx in SearchOptions.
  Else use JclFind or JclSearch depending on whether the search is
  case sensitive.
}
var
  LinePos: Integer;
  Found : Boolean;
  EndPos : integer;
  FoundPos : PWideChar;
  Len : integer;

  procedure IsFound;
  //  Deals with soWholeWord Search option
  var
    Start: Integer;
    TestChar: WideChar;
  begin
    if soWholeWord in SearchOptions then
    begin
      Start := LinePos - 1; // Point to previous character 
      if (Start >= 0) then
      begin
        TestChar := BLine[Start];
        if SynIsCharAlphaNumeric(TestChar) or (TestChar = '_') then
          Exit;
      end;
      TestChar := BLine[EndPos+1];  // Next Character
      if TestChar <> #0 then
      begin
        if SynIsCharAlphaNumeric(TestChar) or (TestChar = '_') then
          Exit;
      end;
    end;
    SignalFoundMatch(FLineNo, FSearchLines[FLineNo-1], LinePos, EndPos)
  end;

begin
  if soRegEx in SearchOptions then begin
    Found := fRegExpr.Exec(BLine);
    while Found do begin
      LinePos := fRegExpr.MatchPos[0];
      EndPos := LinePos + fRegExpr.MatchLen[0] - 1;
      IsFound;
      Found := fRegExpr.ExecNext;
    end;
  end else begin
    if not (soCaseSensitive in SearchOptions) then
      BLine := WideUpperCase(BLine);
    Len := Length(Pattern);
    EndPos := 0;
    FoundPos := PWideChar(BLine);
    Repeat
      FoundPos := WStrPos(FoundPos, PWideChar(fPattern));
      Found := Assigned(FoundPos);
      if Found then begin
        LinePos := FoundPos - PWideChar(BLine) + 1;
        EndPos := LinePos + Len - 1;
        Inc(FoundPos,  Len);
        IsFound;
      end;
    Until not Found;
  end;
end;

procedure TBaseSearcher.SignalStartSearch;
begin
  if Assigned(FOnStartSearch) then
    FOnStartSearch(Self);
end;

procedure TBaseSearcher.SignalFoundMatch(LineNo: Integer; const Line: WideString;
  SPos, EPos: Integer);
begin
  if Assigned(FOnFound) then
    FOnFound(Self, LineNo, Line, SPos, EPos);
end;

end.



