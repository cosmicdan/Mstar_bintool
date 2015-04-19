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

Global Const $iChunkPadding = 4096
Global Const $iMultiSizePerVol = 157286400 ; how many bytes each "volume" (in multi-volume LZO chunks) should be
Global Const $sLzoCompression = "-5" ; -1 is faster, -9 is better

If Not FileExists(@ScriptDir & "\unpacked") Then
	ConsoleWrite("[!] Folder 'unpacked' does not exist. Unpack something first." & @CRLF)
	Exit
EndIf

If FileExists(@ScriptDir & "\MstarUpgrade.bin.out") Then
	ConsoleWrite("[!] A file named 'MstarUpgrade.bin.out' already exists. Remove or rename it first." & @CRLF)
	Exit
EndIf

Global $sOutput = @ScriptDir & "\MstarUpgrade.bin.out"
Global $sOutputTmpHeader = $sOutput & ".tmp.1"
Global $sOutputTmpChunks = $sOutput & ".tmp.2"

Global $hOutput = FileOpen($sOutput, $FO_APPEND + $FO_BINARY)
Global $hOutputTmpHeader = FileOpen($sOutputTmpHeader, $FO_APPEND + $FO_BINARY)
Global $hOutputTmpChunks = FileOpen($sOutputTmpChunks, $FO_APPEND + $FO_BINARY)

Global $iCRC32_script
Global $aHeaderScript

checkFiles()
readHeader()
writeChunks()
writeHeader()
joinHeaderAndChunks()
writeFooter()
cleanup()

Func checkFiles()
	$bOk = True
	If $hOutput = -1 Then $bOk = False
	If $hOutputTmpHeader = -1 Then $bOk = False
	If $hOutputTmpChunks = -1 Then $bOk = False
	If Not $bOk Then
		ConsoleWrite("[!] Unable to get write permissions in current folder. Running as admin?")
		Exit
	EndIf
EndFunc

Func readHeader()
	$aHeaderScript = FileReadToArray(@ScriptDir & "\unpacked\~bundle_script")
	;_ArrayDisplay($aHeaderScript)
EndFunc

Func writeChunks()
	$iTotalChunks = (IniReadSectionNames(@ScriptDir & "\unpacked\~bundle_info.ini"))[0] - 1 ; element 0 is the number of elements and [common] section is of no significance
	$sIntermediateMultiIndex = "a"
	For $i = 1 To $iTotalChunks
		; get INI info for this chunk
		$aChunkInfo = IniReadSection(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i)
		If @error Then
			ConsoleWrite("    [!] WARNING! Chunk info missing, skipping. Ensure this chunk is removed" & @CRLF)
			ConsoleWrite("        from the header script - otherwise flashing the device will fail!" & @CRLF)
			ContinueLoop
		EndIf
		$sName = $aChunkInfo[1][1]
		$sExtension = _getChunkExtensionByType($aChunkInfo[2][1])
		$sChunkFilename = $sName & $sExtension
		ConsoleWrite("[#] Adding chunk " & $i & "/" & $iTotalChunks & " (" & $sChunkFilename & ")...             " & @CRLF)
		$sNameBare = $aTmp[3]
		If $sExtension = ".lzo" Then
			Local $sTmp
			$aTmp = _PathSplit($sChunkFilename, $sTmp, $sTmp, $sTmp, $sTmp)
			$aTmp = _PathSplit($aTmp[3], $sTmp, $sTmp, $sTmp, $sTmp)
			$iIndex = StringReplace($aTmp[4], ".", "")
			If $aChunkInfo[5][1] = 1 Then
				ConsoleWrite("    [#] Splitting to volume index " & $iIndex & " and recompressing..." & @CRLF)
				; is a "multi-volume" LZO, dump the segment we need before compressing
				$hVolumeInput = FileOpen(@ScriptDir & "\unpacked\" & $sNameBare & ".img", $FO_BINARY)
				$sVolumeIntermediate = @ScriptDir & "\unpacked\" & $sNameBare & ".imga" & $sIntermediateMultiIndex
				$hVolumeIntermediate = FileOpen($sVolumeIntermediate, $FO_OVERWRITE + $FO_BINARY)
				FileWrite($hVolumeIntermediate, BinaryMid(FileRead($hVolumeInput), $iMultiSizePerVol * $iIndex + 1, $iMultiSizePerVol))
				FileClose($hVolumeInput)
				FileClose($hVolumeIntermediate)
				; recompress it
				RunWait(@ComSpec & ' /c ' & @ScriptDir & '\inc\lzop ' & $sLzoCompression & ' -o ' & @ScriptDir & "\unpacked\" & $sChunkFilename & ' < ' & $sVolumeIntermediate, @ScriptDir & "\unpacked", @SW_HIDE, $STDOUT_CHILD)
				; increment the intermediate "volume index" (letter rather than number)
				$sIntermediateMultiIndex = Chr(Asc($sIntermediateMultiIndex) + 1)
				; delete the intermediate volume now that we're done recompressing it
				FileDelete($sVolumeIntermediate)
			Else
				; not a multi-volume LZO, but still needs to be recompressed
				ConsoleWrite("    [#] Recompressing..." & @CRLF)
				;ConsoleWrite(@ComSpec & ' /c ' & @ScriptDir & '\inc\lzop ' & $sLzoCompression & ' -o ' & @ScriptDir & "\unpacked\" & $sChunkFilename & ' < ' & @ScriptDir & "\unpacked\" & $sNameBare & ".img")
				RunWait(@ComSpec & ' /c ' & @ScriptDir & '\inc\lzop ' & $sLzoCompression & ' -o ' & @ScriptDir & "\unpacked\" & $sChunkFilename & ' < ' & @ScriptDir & "\unpacked\" & $sNameBare & ".img", @ScriptDir & "\unpacked", @SW_HIDE, $STDOUT_CHILD)
				;ConsoleWrite("---" & @CRLF)
			EndIf
		EndIf
		If Not FileExists(@ScriptDir & "\unpacked\" & $sChunkFilename) Then
			ConsoleWrite("    [!] WARNING! Chunk file missing, skipping. Ensure this chunk is removed" & @CRLF)
			ConsoleWrite("        from the header script - otherwise flashing the device will fail!" & @CRLF)
			ContinueLoop
		EndIf
		; Update the header script with new size@offset values
		$sOldOffsetAndSize = StringReplace($aChunkInfo[3][1] & " " & $aChunkInfo[4][1], "0x", "")
		$iNewOffset = 16384 + FileGetSize($sOutputTmpChunks) ; returns 0 if file doesn't exist
		$iNewSize = FileGetSize(@ScriptDir & "\unpacked\" & $sChunkFilename)
		$sNewOffsetAndSize = _procHex(Hex($iNewOffset)) & " " & _procHex(Hex($iNewSize))
		For $j = 0 To UBound($aHeaderScript) - 1
			If StringInStr($aHeaderScript[$j], $sOldOffsetAndSize) > 0 Then
				; update the in-memory header script
				$aHeaderScript[$j] = StringReplace($aHeaderScript[$j], $sOldOffsetAndSize, $sNewOffsetAndSize)
				; update the size parameter for this chunk's extract/write command (always appears after the chunk's load command)
				$sOldSize = StringReplace($aChunkInfo[4][1], "0x", "")
				For $k = $j To UBound($aHeaderScript) - 1
					If StringInStr($aHeaderScript[$k], $sOldSize & " " & $sNameBare & " 1") > 0 Then
						; multi-volume LZO extraction commands
						$aHeaderScript[$k] = StringReplace($aHeaderScript[$k], ($sOldSize & " " & $sNameBare & " 1"), (_procHex(Hex($iNewSize)) & " " & $sNameBare & " 1"))
					ElseIf StringInStr($aHeaderScript[$k], $sNameBare & " " & $sOldSize & " 1") > 0 Then
						; mmc write commands
						$aHeaderScript[$k] = StringReplace($aHeaderScript[$k], ($sNameBare & " " & $sOldSize & " 1"), ($sNameBare & " " & _procHex(Hex($iNewSize)) & " 1"))
					EndIf
				Next
				; write-back changes to the INI
				$aChunkInfo[3][1] = _procHex(Hex($iNewOffset))
				$aChunkInfo[4][1] = _procHex(Hex($iNewSize))
				IniWriteSection(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i, $aChunkInfo)
			EndIf
		Next
		;ExitLoop
		; write-out this chunk
		$hInput = FileOpen(@ScriptDir & "\unpacked\" & $sChunkFilename, $FO_READ + $FO_BINARY)
		FileWrite($hOutputTmpChunks, FileRead($hInput))

		FileFlush($hOutputTmpChunks)
		FileClose($hInput)
		; pad the file to the next 8KB boundary
		$iFileSize = FileGetSize($sOutputTmpChunks)
		$iPadding = 0
		While 1
			If Mod(($iFileSize + $iPadding), $iChunkPadding) = 0 Then
				;ConsoleWrite("    [i] File size before padding = " & $iFileSize & @CRLF)
				For $l = 1 To $iPadding
					FileWrite($hOutputTmpChunks, Chr(0xFF))
				Next
				FileFlush($hOutputTmpChunks)
				;ConsoleWrite("    [i] File size after padding = " & FileGetSize($sOutputTmpChunks) & @CRLF)
				ExitLoop
			Else
				$iPadding = $iPadding + 1
			EndIf
		WEnd
		; delete the recompressed lzo file if necessary
		If $sExtension = ".lzo" Then
			FileDelete(@ScriptDir & "\unpacked\" & $sChunkFilename)
		EndIf
	Next
EndFunc

Func writeHeader()
	; write-out the header script
	ConsoleWrite("[#] Writing header..." & @CRLF)
	For $i = 0 To UBound($aHeaderScript) - 1
		FileWriteLine($hOutputTmpHeader, $aHeaderScript[$i] & @LF)
	Next
	FileFlush($hOutputTmpHeader)
	; also copy the new header script back to the unpacked folder
	FileCopy($sOutputTmpHeader, @ScriptDir & "\unpacked\~bundle_script", $FC_OVERWRITE)
	; pad the script to 16KB
	$iPadding = 16384 - FileGetSize($sOutputTmpHeader)
	For $i = 1 To $iPadding
		FileWrite($hOutputTmpHeader, Chr(0xFF))
	Next
	FileFlush($hOutputTmpHeader)
	; calculate the new script CRC for later
	$iPID = Run(@ComSpec & " /c " & @ScriptDir & '\inc\crc32 ' & $sOutputTmpHeader, @ScriptDir, @SW_HIDE, $STDERR_MERGED)
	$sCmdOutput = ""
	Do
		$sCmdOutput &= StdoutRead($iPID)
	Until @error
	$aResult = StringSplit($sCmdOutput, " ")
	If $aResult[0] <> 2 Then
		ConsoleWrite("[!] Error calculating CRC!" & @CRLF)
		Exit
	EndIf
	$iCRC32_script = StringReplace($aResult[1], "0x", "")
	ConsoleWrite("[i] Header script CRC32 = " & $iCRC32_script & @CRLF)
EndFunc

Func joinHeaderAndChunks()
	ConsoleWrite("[#] Joining header and chunks..." & @CRLF)
	FileFlush($hOutputTmpHeader)
	FileWrite($hOutput, FileRead($sOutputTmpHeader))
	FileFlush($hOutput)
	FileFlush($hOutputTmpChunks)
	FileWrite($hOutput, FileRead($sOutputTmpChunks))
	FileFlush($hOutput)
EndFunc

Func writeFooter()
	FileWrite($hOutput, $MAGIC_FOOTER)
	FileFlush($hOutput)
	FileWrite($hOutput, _BinaryReverse("0x" & $iCRC32_script))
	FileFlush($hOutput)
	$iCRC32_unknown = IniRead(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "crc32_unknown", 0)
	FileWrite($hOutput, _BinaryReverse($iCRC32_unknown))
	FileFlush($hOutput)
	$sFooterCmd = IniRead(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "footer_cmd", 0)
	;ConsoleWrite("'" & IniRead(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "footer_cmd", 0) & "'" & @CRLF)
	FileWrite($hOutput, $sFooterCmd)
	FileFlush($hOutput)
EndFunc

Func cleanup()
	;ConsoleWrite("[#] Cleaning up..." & @CRLF)
	If FileExists($sOutputTmpHeader) Then FileDelete($sOutputTmpHeader)
	If FileExists($sOutputTmpChunks) Then FileDelete($sOutputTmpChunks)
EndFunc