//--------------------------------------------------------------------------
// Test program: Demonstration of dEXIF module use
//    Has two modes: 1)  Dump all detail regarding a specific file
//                   2)  Show summary of all jpgs in directory tree
//
// Release history:
//   Gerry McGuire, March - April 7, 2001 - Initial Beta Release - 0.8
//   Gerry McGuire, September 3, 2001      - Second Beta Release - 0.9
//
//--------------------------------------------------------------------------
unit MainView;

{$IFDEF LCL}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  ExtDlgs, StdCtrls,
 {$IFDEF DELPHI}
  Jpeg,
 {$ENDIF}
  dExif, msData, ComCtrls, ExtCtrls, SHLObj, FileCtrl,
  dIPTC,mmsystem;

type
  TForm1 = class(TForm)
    btnLoad: TButton;
    pdlg: TOpenPictureDialog;
    Memo1: TMemo;
    StatusBar1: TStatusBar;
    cbClearOnLoad: TCheckBox;
    btnAbout: TButton;
    btnTree: TButton;
    PBar: TProgressBar;
    cbVerbose: TCheckBox;
    btnWrite: TButton;
    JpegOut: TSavePictureDialog;
    cbDecode: TCheckBox;
    btnCmt: TButton;
    Image1: TImage;
    procedure btnLoadClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnAboutClick(Sender: TObject);
    procedure btnTreeClick(Sender: TObject);
    procedure cbVerboseClick(Sender: TObject);
    procedure btnWriteClick(Sender: TObject);
    procedure cbDecodeClick(Sender: TObject);
    procedure btnCmtClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure dumpSections;
    procedure Memo(s: string);
    procedure dumpEXIF;
    procedure dumpMSpecific;
    procedure dumpThumb;
    procedure ReadExifDir(start:string;justcnt:boolean);
    procedure CleanupPreview;
    { Private declarations }
  public
    { Public declarations }
    exifBuffer: string;
    lastDir: string;
    jpgcnt: integer;
    scrar:real;
    flist:tstringlist;
    etime:longint;
    Verbose:boolean;
  end;

var
  Form1: TForm1;
  ImgData:TImgData;

implementation

{$IFDEF DELPHI}
 {$R *.dfm}
{$ENDIF}
{$IFDEF LCL}
 {$R *.lfm}
{$ENDIF}

uses About, ShellApi;
  const crlf = #13#10;
        progName = 'DExView';

  var DirBrowseName : string;

  // Direct call to undocumented Windows function
  PROCEDURE FreePIDL;  EXTERNAL 'Shell32.DLL'  INDEX 155;

  FUNCTION BrowseCallback(Wnd :  hWND;
                        MessageID:  UINT;
                        Param:  LPARAM;
                        Data:    LPARAM):  INTEGER STDCALL;
    VAR
      Name:  ARRAY[0..MAX_PATH] OF CHAR;
      pIDL:  pItemIDList;
      s   :  STRING;
  BEGIN
    CASE  MessageID OF
      BFFM_INITIALIZED: BEGIN
        IF (LENGTH(DirBrowseName) > 0) AND
          DirectoryExists(DirBrowseName) THEN
                SendMessage(Wnd, BFFM_SETSELECTION, Integer(TRUE),
                Integer( pChar(DirBrowseName) ) );
        END;
    ELSE      // ignore
    END;
    pIDL := Pointer(Param);
    s := '';
    IF   Assigned(PIDL) THEN
      SHGetPathFromIDList(pIDL, Name);
    RESULT := 0
  END; // BrowseCallback

  function BrowseForDir(handle:hwnd;dirname:string):string;
  VAR
    BrowseInfo :  TBrowseInfo;
    ItemIDList :  pItemIDList;   // some would use PIDL here
    DisplayName:  ARRAY[0..MAX_PATH] OF CHAR;
  begin
    result := '';
    DirBrowseName := ExcludeTrailingBackslash(DirName);
    BrowseInfo.hwndOwner := Handle;
    BrowseInfo.pidlRoot := NIL;
    BrowseInfo.pszDisplayName := @DisplayName[0];
    BrowseInfo.lpszTitle := 'Select Directory';
    BrowseInfo.ulFlags := BIF_RETURNONLYFSDIRS;
    BrowseInfo.lpfn := BrowseCallback;
    BrowseInfo.lParam := 0;
    BrowseInfo.iImage := 0;
    // Display browse folder set as the return value to itemlist
   {$IFDEF DELPHI}
    ItemIDList := SHBrowseForFolder(BrowseInfo);
   {$ENDIF}
   {$IFDEF LCL}
    ItemIDList := SHBrowseForFolder(@BrowseInfo);
   {$ENDIF}
    TRY // Get directory from the ItemIDList
      IF   Assigned(ItemIDList) THEN
        IF  SHGetPathFromIDList(ItemIDList, DisplayName) THEN
        BEGIN
          result := DisplayName;
        END;
    FINALLY
//      FreePIDL;  //  Causes crash if left in
    END
  end;

function clock:longint;
begin
  Clock := TimeGetTime;
end;

procedure TForm1.btnLoadClick(Sender: TObject);
var i:integer;
    ts:tstringlist;
    tmp:string;
    jpegThumb:tjpegimage;
begin
  btnWrite.enabled := false;
  btnCmt.enabled := false;
  if pdlg.Execute then
  begin
    CleanupPreview;
    StatusBar1.SimpleText  := 'Info for '+pdlg.FileName;
    if verbose
      then ExifTrace := 1
      else ExifTrace := 0;
    if cbClearOnLoad.Checked then
      memo1.Clear;

    ImgData.BuildList := GenAll;  // on by default anyway

    ImgData.ProcessFile(pdlg.FileName);

    if Verbose then
      dumpSections;

    dumpExif;

    if not ImgData.HasMetaData() then
      exit;

    if ImgData.HasEXIF and ImgData.ExifObj.msAvailable then
      dumpMSpecific;

    if ImgData.HasThumbnail then
    begin
      ImgData.ExifObj.ProcessThumbnail;
      dumpThumb;
    end
    else
      Memo('No Thumbnail');


    if ImgData.commentSegment <> nil then
    begin
      Memo(' ');
      Memo(' Comment Segment Available');
      Memo(ImgData.GetCommentStr());
    end;

    if ImgData.IPTCSegment <> nil then
    begin
      ts := ImgData.IptcObj.ParseIPTCStrings(ImgData.IPTCSegment^.Data);
      if ts.Count > 0 then
      begin
        Memo(crlf+' IPTC Segment Available!'+crlf);
        for i := 0 to ts.Count-1 do
        begin
          Memo(ts.strings[i]);
        end;
      end;
      ts.Free;
    end;

    if not ImgData.HasEXIF then
      exit;

    if ImgData.HasThumbnail then
    begin
      jpegThumb := imgData.ExtractThumbnailJpeg();
      image1.Picture.Assign(jpegThumb);
      jpegThumb := nil;
    end;

    try
    // ProcessHWSpecific(ImageInfo.MakerNote,Nikon1Table,8,MakerOffset);
      Memo(' ');
      Memo(' -- EXIF Summary -(short)--- ');
      Memo(ImgData.ExifObj.toString());
      Memo(' ');
      Memo(' -- EXIF Summary -(long)---- ');
      Memo(ImgData.ExifObj.toLongString());
    // only allow image to be written if no errors
      if ImgData.ErrStr = '<none>' then
        btnWrite.enabled := true;
      if ImgData.ExifObj.CommentPosn > 0 then
        btnCmt.enabled := true;
      Memo('');
    // An example of pulling some specific tags out of
    // the found items list.  I'll change the names
    // around a little just because...
      tmp := ImgData.ExifObj.LookupTagVal('MaxApertureValue');
      if tmp <> '' then
        Memo(' ** Widest Aperture is '+tmp);
      tmp := ImgData.ExifObj.LookupTagVal('ShutterSpeedValue');
      if tmp <> '' then
        Memo(' ** Response Time is '+tmp);
      tmp := ImgData.ExifObj.LookupTagVal('MeteringMode');
      if tmp <> '' then
        Memo(' ** Light Meter mode is '+tmp);
    finally
      if cbClearOnLoad.Checked then
            memo1.Perform(EM_LINESCROLL,0,-memo1.Lines.Count);
    end;
  end;
end;

procedure TForm1.Memo(s:string);
begin
  Memo1.Lines.Add(s);
end;

procedure TForm1.dumpSections;
var i:integer;
    sh:string;
begin
  Memo(' --------------------------- ');
  Memo('File = '+ImgData.Filename);
  Memo('Section count = '+inttostr(ImgData.SectionCnt));
  for i := 1 to ImgData.SectionCnt do
  begin
    sh := '    Section['+inttostr(i)+']';
    Memo(sh+'.type = $'+IntToHex(ImgData.Sections[i].dtype,2)
           +' - '+LookupType(ImgData.Sections[i].dtype) +' ('
           +IntToStr(ImgData.Sections[i].size)+')');
//    Memo(' Printable -> '+MakePrintable(
//        copy(ImgData.Sections[i].data,1,100)));
  end;
end;

procedure TForm1.dumpEXIF;
var item:TTagEntry;
begin
  Memo(' ');
  Memo('-- EXIF-Data -------------- ');
  Memo('ErrStr = '+ImgData.ErrStr);
  if not ImgData.HasEXIF() then
    exit;
  If ImgData.MotorolaOrder
    then Memo('Motorola Byte Order')
    else Memo('Intel Byte Order');
  // verbose data is only available in the trace strings
  if cbVerbose.Checked then
    Memo1.Lines.Add(ImgData.ExifObj.TraceStr)
  else
  begin
    ImgData.ExifObj.ResetIterator;
    while ImgData.ExifObj.IterateFoundTags(GenericEXIF ,item) do
      Memo(item.Desc+DexifDelim+item.Data);
  end;
end;

procedure TForm1.dumpMSpecific;
var item:TTagEntry;
begin
  Memo(' ');
  Memo(' -- Maker Specific Data ---- ');
  // verbose data is only available in the trace strings
  if cbVerbose.Checked then
    Memo1.Lines.Add(ImgData.ExifObj.msTraceStr)
  else
  begin
    ImgData.ExifObj.ResetIterator;
    while ImgData.ExifObj.IterateFoundTags(CustomEXIF,item) do
      Memo(item.Desc+DexifDelim+item.Data);
  end;
end;

procedure TForm1.dumpThumb;
var item:TTagEntry;
begin
  Memo(' ');
  Memo(' -- Thumbnail Data ---- ');
  Memo('Thumbnail Start = ' +inttostr(ImgData.ExifObj.ThumbStart));
  Memo('Thumbnail Length = '+inttostr(ImgData.ExifObj.ThumbLength));
  // verbose data is only available in the trace strings
  if cbVerbose.Checked then
    Memo1.Lines.Add(ImgData.ExifObj.ThumbTrace)
  else
  begin
    ImgData.ExifObj.ResetThumbIterator;
    while ImgData.ExifObj.IterateFoundThumbTags(GenericEXIF,item) do
      Memo(item.Desc+DexifDelim+item.Data);
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  ImgData := TimgData.Create;
  Verbose := false;
  constraints.MinHeight := height;
  constraints.MinWidth := width;
  fList := tStringList.Create;
  lastDir := GetCurrentDir;
  DoubleBuffered := true;
  memo1.DoubleBuffered := true;
end;

procedure TForm1.btnAboutClick(Sender: TObject);
begin
  AboutBox.FormSetup(ProgName,dEXIFVersion);
  AboutBox.ShowModal;
end;

procedure TForm1.CleanupPreview;
begin
  if image1.Picture.Bitmap <> nil then
  begin
    image1.Picture.Bitmap.FreeImage;
    image1.Picture.Bitmap := nil;
  end;
end;

procedure TForm1.btnTreeClick(Sender: TObject);
begin
  btnWrite.enabled := false;
  if cbClearOnLoad.Checked then
    memo1.Clear;
  Flist.Clear;
  CleanupPreview;
  JpgCnt := 0;
  PBar.Position := 0;
  Lastdir := BrowseForDir(Handle,lastDir);
  cursor := crHourglass;
  StatusBar1.SimpleText := 'Scanning Directory Structure';
  StatusBar1.Refresh;
  ReadExifDir(lastDir,true);        //  run through it just to count jpegs
  PBar.Max := JpgCnt;
  etime := clock();
  ReadExifDir(lastDir,false);
  StatusBar1.SimpleText :=
    format('Elapsed time (%d jpegs): %0.2f sec',
      [JpgCnt,(clock-etime)/1000]);
  Memo1.Lines.AddStrings(flist);
  cursor := crDefault;
end;

procedure TForm1.ReadExifDir(start:string;justcnt:boolean);
var s:tsearchrec;
    status:word;
    finfo:string;
begin
  refresh;                   // repaint the window now
  if start = '' then exit;   // in case user pressed <cancel>
  memo1.Lines.BeginUpdate;   // reduce repainting overhead
  status := FindFirst(start+'\*.*',faAnyFile,s);
  // ImgData.BuildList := GenNone;  // remove overhead but loose size
  while status = 0 do
  begin
    if not ((s.Name = '.') or (s.name = '..')) then
    if (s.Attr and fadirectory) <> 0 then
      ReadExifDir(start+'\'+s.Name,JustCnt)  // recurse into subdirs
    else
      if (uppercase(ExtractFileExt(s.Name)) = '.JPG') or
         (uppercase(ExtractFileExt(s.Name)) = '.NEF') or
         (uppercase(ExtractFileExt(s.Name)) = '.TIF') then
      if justCnt then
        inc(JpgCnt)
      else if ImgData.ProcessFile(start+'\'+s.name) then
      begin
        if ImgData.HasMetaData then
        begin
          if  ImgData.HasEXIF then
            finfo := ImgData.ExifObj.toString()    // Just so you know:
          else
            finfo := s.name;
          if ImgData.IPTCSegment <> nil then
            finfo := finfo+' + IPTC';
        end
        else
            finfo := s.name+' - No metadata';
        Memo1.lines.Add(finfo);            //   this will blow up if there
        PBar.StepIt;
        StatusBar1.SimpleText :=
          Format('%0.1f%% of %d files.',[Pbar.Position/JpgCnt*100,JpgCnt]);
        if pbar.Position mod 100 = 0 then   // too many refreshes will show
          application.ProcessMessages       // down the whole process
      end;
    status := FindNext(s);
  end;
  FindClose(s);
  memo1.Lines.EndUpdate;
end;

procedure TForm1.cbVerboseClick(Sender: TObject);
begin
  Verbose := cbVerbose.Checked;
end;

procedure TForm1.btnWriteClick(Sender: TObject);
var Orig,Smaller:tjpegimage;
    buffer:tbitmap;
    smallFname:string;
begin
  smallFname := copy(ImgData.Filename,1,length(ImgData.Filename)-4)
    +'_smaller.jpg';
  JpegOut.FileName := smallFName;
  if not JpegOut.Execute then
    exit;
  SmallFName := JPegOut.FileName;
  Buffer := tbitmap.Create;
  Orig := tjpegImage.Create;
  Smaller := tjpegimage.create;
  try
    Orig.LoadFromFile(ImgData.Filename);
   {$IFDEF DELPHI}
    Orig.DIBNeeded;
   {$ENDIF}
    Buffer.PixelFormat := pf24bit;
    Buffer.Width := orig.Width div 2;
    Buffer.Height := orig.Height div 2;
    // Simple resize
    Buffer.Canvas.StretchDraw(rect(0,0,Buffer.width,buffer.height),Orig);
    Smaller.Assign(Buffer);
    Smaller.CompressionQuality := 75;
   {$IFDEF DELPHI}
    Smaller.Compress;
   {$ENDIF}
    //  the following line removes the embedded thumbnail
    //  but breaks with some cameras (e.g. Nikon)
    //  ImgData.ExifObj.removeThumbnail;
    //
    //  Use the following to remove all metadata from an image
    ImgData.ClearSections;
    //
    //  The following allows a program to apply a correction
    //  to the DateTime fields in the EXIF.  This can compensate,
    //  for example, for an inaccurate clock in a camera.
    //  ImgData.ExifObj.AdjDateTime(-1,1,10,10);
    //
    // If dEXIF is built into a control then
    //   Smaller.SaveToFile(SmallFName);
    // Since it's not we use:
    ImgData.WriteEXIFjpeg(Smaller,SmallFName);
  finally // Cleanup
    Buffer.free;
    Orig.Free;
    SMaller.Free;
  end;
end;

procedure TForm1.cbDecodeClick(Sender: TObject);
begin
  // This variable will determine if the
  // tags are decoded into human-based terms
  DexifDecode := cbDecode.Checked;
end;

procedure TForm1.btnCmtClick(Sender: TObject);
var cmt:string;
begin
  if ImgData.ExifObj.CommentPosn = 0 then
    ShowMessage('No EXIF comment field detected')
  else
  begin
    cmt := InputBox('Enter EXIF comment:',
       'Enter a new comment (limited to '+
       inttostr(ImgData.ExifObj.CommentSize)+' characters )',
       ImgData.ExifObj.Comments);
    if ImgData.ExifObj.Comments <> cmt then
    begin
      ImgData.ExifObj.SetExifComment(cmt);
      Memo1.Lines.Add('Comment set to: '+cmt);
      ImgData.ExifObj.Comments := cmt;
    end;
  end;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if not memo1.DoubleBuffered then
      memo1.DoubleBuffered := true;
end;

end.