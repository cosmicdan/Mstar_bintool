#NoTrayIcon
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Change2CUI=y
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <FileConstants.au3>
#include <String.au3>
#include <Array.au3>
#include <File.au3>
#include "inc\Binary.au3"
#include "inc\Common.au3"

Global Const $MEM_ADDR = "20200000"
Global Const $FILE_PART_CMD = "filepartload " & $MEM_ADDR & " MstarUpgrade.bin"

Global $aPartOffset[0]
Global $aPartSize[0]
Global $aPartLabel[0]
Global $aPartType[0]
Global $aPartMulti[0]

Global $iCRC32_unknown
Global $sFooterCmd

Global $iLastPos ; temp val for storing current operating position in binary file
Global $iChunkPart ; temp val for storing current index/order of "multi-volume" lzo archives

If Not FileExists(@ScriptDir & "\MstarUpgrade.bin") Then
	ConsoleWrite("[!] MstarUpgrade.bin not found in current folder" & @CRLF)
	Exit
EndIf

If FileExists(@ScriptDir & "\unpacked") Then
	ConsoleWrite("[!] Folder 'unpacked' already exists. Remove or rename it first." & @CRLF)
	Exit
	;DirRemove(@ScriptDir & "\unpacked", 1)
EndIf

ConsoleWrite("[i] MstarUpgrade.bin found" & @CRLF)
$hFile = FileOpen(@ScriptDir & "\MstarUpgrade.bin", $FO_BINARY)
ConsoleWrite("[#] Reading and parsing firmware bundle... please be patient!" & @CRLF)
$sFileContents = FileRead($hFile)
FileClose($hFile)

ripHeaderScript()
processChunkInfo()
extractChunks()
dumpInfo()
ConsoleWrite("[i] All done!" & @CRLF)

Func ripHeaderScript()
	Local $sFooterText = ("% <-this is end of file symbol" & @LF)
	Local $xFooterText = StringToBinary($sFooterText)
	$iPos = _BinaryInBin($sFileContents, $xFooterText) - 1 ;remember - first pos is 1 in autoit, but 0 in hex editors
	If $iPos < 1 Then
		ConsoleWrite("[!] Could not find header!" & @CRLF)
		Exit
	EndIf
	Local $hOutput = FileOpen(@ScriptDir & "\~bundle_script", $FO_OVERWRITE)
	FileWrite($hOutput, BinaryToString(_BinaryLeft($sFileContents, $iPos + StringLen($sFooterText))))
	FileClose($hOutput)
	$iLastPos = $iPos + StringLen($sFooterText)
EndFunc

Func processChunkInfo()
	ConsoleWrite("[#] Parsing chunks..." & @CRLF)
	Local $aFileLines
	_FileReadToArray(@ScriptDir & "\~bundle_script", $aFileLines)
	For $i = 1 To $aFileLines[0]
		$sMatchPattern = $FILE_PART_CMD & " "
		If _StringContains($aFileLines[$i], $sMatchPattern) Then
			$sLine = StringReplace($aFileLines[$i], $sMatchPattern, "")
			$aOffsetAndSize = StringSplit($sLine, " ")
			_ArrayAdd($aPartOffset, $aOffsetAndSize[1])
			_ArrayAdd($aPartSize, $aOffsetAndSize[2])
			_ArrayAdd($aPartMulti, "0") ; false is default
			; try and determine the label for this chunk
			If _StringContains($aFileLines[$i + 1], "mmc write.p " & $MEM_ADDR & " ") Then
				$sLine = StringReplace($aFileLines[$i + 1], "mmc write.p " & $MEM_ADDR & " ", "")
				$aSplit = StringSplit($sLine, " ")
				_ArrayAdd($aPartLabel, $aSplit[1])
				_ArrayAdd($aPartType, $PART_TYPE_RAW)
			ElseIf _StringContains($aFileLines[$i + 1], "store_secure_info ") Then
				$sLine = StringReplace($aFileLines[$i + 1], "store_secure_info ", "")
				$aSplit = StringSplit($sLine, " ")
				_ArrayAdd($aPartLabel, $aSplit[1])
				_ArrayAdd($aPartType, $PART_TYPE_SEC)
			ElseIf _StringContains($aFileLines[$i + 1], "mmc erase.p ") Then
				$sLine = StringReplace($aFileLines[$i + 1], "mmc erase.p ", "")
				$aSplit = StringSplit($sLine, " ")
				_ArrayAdd($aPartLabel, $aSplit[1])
				_ArrayAdd($aPartType, $PART_TYPE_RAW)
			ElseIf _StringContains($aFileLines[$i + 1], "store_nuttx_config ") Then
				$sLine = StringReplace($aFileLines[$i + 1], "store_nuttx_config ", "")
				$aSplit = StringSplit($sLine, " ")
				_ArrayAdd($aPartLabel, $aSplit[1])
				_ArrayAdd($aPartType, $PART_TYPE_NUTTX)
			ElseIf _StringContains($aFileLines[$i + 1], "mmc unlzo " & $MEM_ADDR & " ") Then
				; reset the lzo "volume index"
				$iChunkPart = 0
				$sLine = StringReplace($aFileLines[$i + 1], "mmc unlzo " & $MEM_ADDR & " ", "")
				$aSplit = StringSplit($sLine, " ")
				_ArrayAdd($aPartLabel, $aSplit[2] & "." & $iChunkPart)
				_ArrayAdd($aPartType, $PART_TYPE_LZO)
			ElseIf _StringContains($aFileLines[$i + 1], "mmc unlzo.cont " & $MEM_ADDR & " ") Then
				; increment the lzo "volume index"
				$iChunkPart += 1
				$sLine = StringReplace($aFileLines[$i + 1], "mmc unlzo.cont " & $MEM_ADDR & " ", "")
				$aSplit = StringSplit($sLine, " ")
				_ArrayAdd($aPartLabel, $aSplit[2] & "." & $iChunkPart)
				_ArrayAdd($aPartType, $PART_TYPE_LZO)
				; set the "multi" flag to true for this chunk
				$aPartMulti[UBound($aPartMulti) - 1] = 1
				; also set the first-index of the multi to true, if necessary (i.e. when second 'volume' is detected, update the last one)
				If $iChunkPart = 1 Then
					$aPartMulti[UBound($aPartMulti) - 2] = 1
				EndIf
			ElseIf _StringContains($aFileLines[$i + 1], "mmc write.boot ") Then
				_ArrayAdd($aPartLabel, "misc")
				_ArrayAdd($aPartType, $PART_TYPE_MISC)
			Else
				ConsoleWrite(@CRLF)
				ConsoleWrite("    [!] Error - could not determine partition label/type for data chunk @ line " & $i & @CRLF)
				Exit
			EndIf
			; update the last position for next run
			$iLastPos = Dec($aOffsetAndSize[1]) + Dec($aOffsetAndSize[2])
			ConsoleWrite("    [i] Chunk " & UBound($aPartLabel) & ": " & $aPartLabel[(UBound($aPartLabel) - 1)] & " = " & $aOffsetAndSize[2] & "@" & $aOffsetAndSize[1] & @CRLF)
		EndIf
	Next
	; process the last-chunk padding

	Local $xMagicFooter = Binary("0xFFFFFFFF") & StringToBinary($MAGIC_FOOTER)
	$iPos = _BinaryInBin($sFileContents, $xMagicFooter, 1, $iLastPos) - 1 ;remember - first pos is 1 in autoit, but 0 in hex editors
	If $iPos < 1 Then
		; try again with a different dummy. Possibly unsafe, be sure to verify
		$xMagicFooter = Binary("0x00") & StringToBinary($MAGIC_FOOTER)
		$iPos = _BinaryInBin($sFileContents, $xMagicFooter, 1, $iLastPos) - 1
		If $iPos < 1 Then
			ConsoleWrite(@CRLF & "[!] Could not find magic footer!" & @CRLF)
			Exit
		EndIf
		$iPos += 1; skip over the one byte of dummy data we prepended to magic
	Else
		$iPos += 4; skip over the four bytes of dummy data we prepended to magic
	EndIf
	; skip-over the magic numbers
	$iPos += 8
	; get the second CRC32, whatever it is
	$iCRC32_unknown = _BinaryReverse((BinaryMid($sFileContents, $iPos + 5, 4))) ; remember - autoit is 1-based byte offsets
	; get the footer command (or whatever it is)
	$sFooterCmd = BinaryMid($sFileContents, $iPos + 1 + 8)
	ConsoleWrite("[i] Footer command (raw binary) = " & $sFooterCmd & @CRLF)
	ConsoleWrite("[i] Footer command (plain text): " & @CRLF)
	ConsoleWrite(BinaryToString($sFooterCmd) & @CRLF)
	ConsoleWrite("[!] Be sure to verify the above footer command was correctly extracted! If it's not right, the extraction and/or rebuild will likely fail!" & @CRLF)
EndFunc

Func extractChunks()
	DirCreate(@ScriptDir & "\unpacked")
	$iTotalChunks = UBound($aPartLabel)
	For $i = 1 To $iTotalChunks
		$sExtension = _getChunkExtensionByType($aPartType[$i - 1])
		$sFilename = $aPartLabel[($i - 1)] & $sExtension
		If $sExtension = ".lzo" Then
			ConsoleWrite("[#] Writing-out and decompressing chunk " & $i & "/" & $iTotalChunks & " (" & $sFilename & ")..." & @CRLF)
		Else
			ConsoleWrite("[#] Writing-out chunk " & $i & "/" & $iTotalChunks & " (" & $sFilename & ")..." & @CRLF)
		EndIf
		$hOutput = FileOpen(@ScriptDir & "\unpacked\" & $sFilename, $FO_OVERWRITE)
		$iOffset = Dec($aPartOffset[$i-1]) + 1
		$iSize = Dec($aPartSize[$i-1])
		$xData = BinaryMid($sFileContents, $iOffset, $iSize)
		FileWrite($hOutput, $xData)
		FileClose($hOutput) ; FileClose will flush buffers automatically
		; extract lzo-compressed images
		If $sExtension = ".lzo" Then
			RunWait(@ComSpec & ' /c ' & @ScriptDir & '\inc\lzop -x < ' & @ScriptDir & "\unpacked\" & $sFilename, @ScriptDir & "\unpacked", @SW_HIDE, $STDOUT_CHILD)
			FileDelete(@ScriptDir & "\unpacked\" & $sFilename)
		EndIf
	Next
	; join any "multi-volume" images
	$hSearch1 = FileFindFirstFile(@ScriptDir & "\unpacked\*.imgaa")
	Local $sImgFiles[0]
	If $hSearch1 <> -1 Then
		While 1
			$sFilename = FileFindNextFile($hSearch1)
			If @error Then ExitLoop
			_ArrayAdd($sImgFiles, $sFilename)
		WEnd
		For $i = 1 To UBound($sImgFiles)
			Local $sTmp
			$aTmp = _PathSplit($sImgFiles[$i -1], $sTmp, $sTmp, $sTmp, $sTmp)
			$sOutputImageName = $aTmp[3]
			ConsoleWrite("[#] Re-assembling " & $sOutputImageName & ".img..." & @CRLF)
			$hOutputImage = FileOpen(@ScriptDir & "\unpacked\" & $sOutputImageName & ".img", $FO_APPEND + $FO_BINARY)
			$hSearch2 = FileFindFirstFile(@ScriptDir & "\unpacked\" & $sOutputImageName & ".imga?")
			While 1
				$sFilename = FileFindNextFile($hSearch2)
				If @error Then ExitLoop
				FileWrite($hOutputImage, FileRead(@ScriptDir & "\unpacked\" & $sFilename))
				FileFlush($hOutputImage)
				FileDelete(@ScriptDir & "\unpacked\" & $sFilename)
			WEnd
		Next
	Else
		ConsoleWrite("[i] No multi-volume images found" & @CRLF)
	EndIf
EndFunc

Func dumpInfo()
	ConsoleWrite("[#] Moving header script..." & @CRLF)
	FileMove(@ScriptDir & "\~bundle_script", @ScriptDir & "\unpacked\~bundle_script", $FC_OVERWRITE)
	ConsoleWrite("[#] Writing-out bundle information..." & @CRLF)
	IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "crc32_unknown", $iCRC32_unknown)
	IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "footer_cmd", $sFooterCmd)
	FileWriteLine(@ScriptDir & "\unpacked\~bundle_info.ini", "; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
	FileWriteLine(@ScriptDir & "\unpacked\~bundle_info.ini", "; NOTICE! Do NOT change the offset/size values of the chunks - they need to match the")
	FileWriteLine(@ScriptDir & "\unpacked\~bundle_info.ini", "; existing values in ~bundle_script. The repack script will update them automatically.")
	FileWriteLine(@ScriptDir & "\unpacked\~bundle_info.ini", "; ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
	For $i = 1 To UBound($aPartLabel)
		; write out the padding info for each chunk
		IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i, "label", $aPartLabel[$i - 1])
		IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i, "type", $aPartType[$i - 1])
		IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i, "offset", $aPartOffset[$i - 1])
		IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i, "size", $aPartSize[$i - 1])
		IniWrite(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i, "multi", $aPartMulti[$i - 1])
		FileWriteLine(@ScriptDir & "\unpacked\~bundle_info.ini", "")
	Next
EndFunc

