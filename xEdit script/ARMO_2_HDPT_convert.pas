// ***** BEGIN LICENSE BLOCK *****
//
//Copyright (c) 2021, yeahhowaboutnooo.
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.
//
// ***** END LICENSE BLOCK *****

unit UserScript;


function Initialize: integer;
begin
  Result := 0;
end;


function Process(eSource: IInterface): integer;
var
  armorAddon, eSourceAAs, extraParts: IwbElement;
  espFile, hdpt_entry, eTarget, extraTarget: IInterface;
  searchResultName, eTargetName, extraTargetName, nifFileName, extraPartDir, fullExtraPartDir, extraPartName, extraFileName: string;
  searchResult: TSearchRec;
  extraTargetCounter, aaCount, extraPartCntr: integer;
begin
  Result := 0;

  AddMessage('Processing: ' + Name(eSource));

  espfile := getfile(esource);

  hdpt_entry := Add(espFile, 'HDPT', true);

  eTarget := Add(hdpt_entry, 'HDPT', true);
  if not ProcessArmor(eSource, eTarget, hdpt_entry, 'Male') then Remove(eTarget);

  eTarget := Add(hdpt_entry, 'HDPT', true);
  if not ProcessArmor(eSource, eTarget, hdpt_entry, 'Female') then Remove(eTarget);
end;

function ProcessArmor(eSource, eTarget, hdpt_entry: IInterface; gender: string): boolean;
var
  armorAddon, eSourceAAs, extraParts: IwbElement;
  extraTarget: IInterface;
  genderModelString, searchResultName, eTargetName, extraTargetName, nifFileName, extraPartDir, fullExtraPartDir, extraPartName, extraFileName: string;
  searchResult: TSearchRec;
  extraTargetCounter, aaCount, extraPartCntr: integer;
  isGenderCompatible: boolean;
begin
  if gender = 'Female' then
  begin
    genderModelString := 'Female world model\MOD3 - Model FileName';
    eTargetName := 'HDPT_F_' + EditorID(eSource);
    isGenderCompatible := true;
  end;
  if gender = 'Male' then
  begin
    genderModelString := 'Male world model\MOD2 - Model FileName';
    eTargetName := 'HDPT_M_' + EditorID(eSource);
    isGenderCompatible := false;
  end;

  eSourceAAs := ElementByPath(eSource, 'Armature');
  //run through all armor addons twice:
  //first pass: check if we have all required meshes to create a headpart for the requested gender
  for aaCount := 0 to ElementCount(eSourceAAs) -1 do
  begin
    armorAddon := LinksTo(ElementByIndex(eSourceAAs, aaCount));

    //female headparts have a collision-body
    // -> a female armor has female world models for all of its corresponding armor addons
    //whereas a male armor only needs one male world model for any of its corresponding armor addons
    if gender = 'Female' then
    begin
      isGenderCompatible := isGenderCompatible and ElementExists(armorAddon, genderModelString);
    end;
    if gender = 'Male' then
    begin
      isGenderCompatible := isGenderCompatible or ElementExists(armorAddon, genderModelString);
    end;
  end;
  Result := False;
  if not isGenderCompatible then Exit;
  if (ElementCount(eSourceAAs) <= 0) then Exit;


  BeginUpdate(eTarget);
    SetEditorID(eTarget, eTargetName);

    Add(eTarget, 'NAME', true);
    SetElementEditValues(eTarget, 'FULL - Name', eTargetName);

    Add(eTarget, 'RNAM', true);
    SetElementEditValues(eTarget, 'RNAM - Valid Races', 'HeadPartsAllRacesMinusBeast [FLST:000A803F]');

    Add(eTarget, 'PNAM', true);
    SetElementEditValues(eTarget, 'PNAM - Type', 'Hair');

    //bit0: Playable, bit1: Male and bit2: Female
    if gender = 'Female' then SetElementEditValues(eTarget, 'DATA - Flags', '101');
    if gender = 'Male'   then SetElementEditValues(eTarget, 'DATA - Flags', '110');

    extraParts := ElementByName(eTarget, 'Extra Parts');
    RemoveElement(eTarget, extraParts);
    extraPartCntr := 0;


    //2nd pass through all armor addons: if we even got to this point -> we have all required meshes for the requested gender
    for aaCount := 0 to ElementCount(eSourceAAs) -1 do
    begin
      armorAddon := LinksTo(ElementByIndex(eSourceAAs, aaCount));
      if not ElementExists(armorAddon, genderModelString) then continue;

      //we need the nifFileName to get the extraPartDir
      //and first extrapart is the nifFile itself (so e.g. the bodyslide-built collision body is always being used)
      nifFileName := GetElementEditValues(armorAddon, genderModelString);
      extraPartDir := nifFileName + '__HDPT_extraParts';
      fullExtraPartDir := DataPath + 'meshes\' + extraPartDir;
      if ansipos('meshes\', ansilowercase(nifFileName)) = 1 then
        fullExtraPartDir := DataPath + extraPartDir;

      if not directoryexists(fullExtraPartDir) then
        raise Exception.Create('Fatal error: Could not find extra Parts directory ' + fullExtraPartDir + '!');
      if FindFirst(fullExtraPartDir + '\*.nif', faAnyFile, searchResult) = 0 then
      begin
        extraTargetCounter := 0;
        repeat
          if searchResult.Attr <> faDirectory then
          begin
            searchResultName := searchResult.name;
            Delete(searchResultName, 1, 4); //get rid of the index at the beginning of the file
            extraTargetCounter := extraTargetCounter + 1;
            extraTargetName := eTargetName + '_extraPart' + Format('%.3d', [extraPartCntr]);
            extraTarget := Add(hdpt_entry, 'HDPT', true);
            BeginUpdate(extraTarget);
              //get rid of the file extension and replace ; with :
              //(as windows filenames are not allowed to contain : but .nif-meshnames sometimes contain : )
              SetEditorID(extraTarget, StringReplace(ChangeFileExt(searchResultName, ''), ';', ':', [rfReplaceAll]));
              Add(extraTarget, 'NAME', true);
              SetElementEditValues(extraTarget, 'FULL - Name', extraTargetName);

              Add(extraTarget, 'MODL', true);
              SetElementEditValues(extraTarget, 'Model\MODL - Model FileName', extraPartDir + '\' + searchResult.name);

              //fix for cornflakes no-ring version of xing-hair:
              //uses the actual bodyslide-built collision body
              if (aaCount > 0) and (extraTargetCounter = 1) then
                SetElementEditValues(extraTarget, 'Model\MODL - Model FileName', nifFileName);

              Add(extraTarget, 'RNAM', true);
              //HeadPartsAllRacesMinusBeast [FLST:000A803F]
              SetElementEditValues(extraTarget, 'RNAM - Valid Races', 'HeadPartsAllRacesMinusBeast [FLST:000A803F]');

              Add(extraTarget, 'PNAM', true);
              SetElementEditValues(extraTarget, 'PNAM - Type', 'Misc');

              //bit0: Playable, bit1: Male, bit2: Female and bit3: isExtraPart
              if gender = 'Female' then SetElementEditValues(extraTarget, 'DATA - Flags', '1011');
              if gender = 'Male'   then SetElementEditValues(extraTarget, 'DATA - Flags', '1101');
            EndUpdate(extraTarget);

            extraParts := ElementByName(eTarget, 'Extra Parts');
            if not Assigned(extraParts) then
              SetEditValue( ElementByIndex(Add(eTarget, 'Extra Parts', True), 0), Name(extraTarget))
            else
              SetEditValue( ElementAssign(extraParts, HighInteger, nil, False), Name(extraTarget));
            extraPartCntr := extraPartCntr + 1;
          end;
        until FindNext(searchResult) <> 0;
        FindClose(searchResult);
      end;
    end;
  EndUpdate(eTarget);
  Result := True;
  Exit;
end;


function Finalize: integer;
begin
    Result := 1;
    exit;
end;

end.
