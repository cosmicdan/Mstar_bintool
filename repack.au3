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

Global $iCRC32_script

If Not FileExists(@ScriptDir & "\unpacked") Then
	ConsoleWrite("[!] Folder 'unpacked' does not exist. Unpack something first." & @CRLF)
	Exit
EndIf

If FileExists(@ScriptDir & "\MstarUpgrade.bin.out") Then
	;ConsoleWrite("[!] A file named 'MstarUpgrade.bin.out' already exists. Remove or rename it first." & @CRLF)
	;Exit
	FileDelete(@ScriptDir & "\MstarUpgrade.bin.out")
EndIf

Global $sOutput = @ScriptDir & "\MstarUpgrade.bin.out"
Global $sOutputTmpHeader = $sOutput & ".tmp.1"
Global $sOutputTmpChunks = $sOutput & ".tmp.2"

Global $hOutput = FileOpen($sOutput, $FO_APPEND + $FO_BINARY)
Global $hOutputTmpHeader = FileOpen($sOutput & ".tmp.1", $FO_OVERWRITE + $FO_BINARY)
Global $hOutputTmpChunks = FileOpen($sOutput & ".tmp.2", $FO_OVERWRITE + $FO_BINARY)

writeHeader()
;writeChunks()
joinHeaderAndChunks()
;writeFooter()

Func writeHeader()
	; write-out the header script
	ConsoleWrite("[#] Writing header..." & @CRLF)
	$hInput = FileOpen(@ScriptDir & "\unpacked\~bundle_script", $FO_READ + $FO_BINARY)
	FileWrite($hOutputTmpHeader, FileRead($hInput))
	FileFlush($hOutputTmpHeader)
	FileClose($hInput)
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
	If Not $aResult[0] = 2 Then
		ConsoleWrite("[!] Error calculating CRC!" & @CRLF)
		Exit
	EndIf
	$iCRC32_script = StringReplace($aResult[1], "0x", "")
	ConsoleWrite("[i] Header script CRC32 = " & $iCRC32_script & @CRLF)
EndFunc

Func writeChunks()
	$iTotalChunks = (IniReadSectionNames(@ScriptDir & "\unpacked\~bundle_info.ini"))[0] - 1 ; element 0 is the number of elements and [common] section is of no significance
	For $i = 1 To $iTotalChunks
		; get INI info for this chunk
		$aChunkInfo = IniReadSection(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i)
		$sName = $aChunkInfo[1][1]
		$sExtension = _getChunkExtensionByType($aChunkInfo[2][1])
		ConsoleWrite("[#] Adding chunk " & $i & "/" & $iTotalChunks & " (" & $sName & $sExtension & ")...             " & @CRLF)
		; calculate new offset and size for this chunk (for updating header script)
		$iOldOffset = Dec($aChunkInfo[3][1])
		$iOldSize = Dec($aChunkInfo[4][1])
		$iNewOffset = 16384 + FileGetSize($hOutputTmpChunks) ; returns 0 if file doesn't exist
		$iNewSize = FileGetSize(@ScriptDir & "\unpacked\" & $sName & $sExtension)
		;ConsoleWrite("    [i] Old size@offset = " & $iOldSize & "@" & $iOldOffset & @CRLF)
		;ConsoleWrite("    [i] New size@offset = " & $iNewSize & "@" & $iNewOffset & @CRLF)
		;ExitLoop
		; write-out this chunk
		$hInput = FileOpen(@ScriptDir & "\unpacked\" & $sName & $sExtension, $FO_READ + $FO_BINARY)
		FileWrite($hOutputTmpChunks, FileRead($hInput))
		FileFlush($hOutputTmpChunks)
		FileClose($hInput)
		; pad the file to the next 8KB boundary
		$iFileSize = FileGetSize($hOutputTmpChunks)
		$iPadding = 0
		While 1
			If Mod(($iFileSize + $iPadding), 8192) = 0 Then
				;ConsoleWrite("    [i] File size before padding = " & FileGetSize($sOutputTmpChunks & ".tmp.2") & @CRLF)
				For $j = 1 To $iPadding
					FileWrite($hOutputTmpChunks, Chr(0xFF))
				Next
				FileFlush($hOutputTmpChunks)
				;ConsoleWrite("    [i] Added padding of " & $iPadding & " bytes; new file size = " & FileGetSize($sOutputTmpChunks & ".tmp.2") & @CRLF)
				ExitLoop
			Else
				$iPadding = $iPadding + 1
			EndIf
		WEnd

	Next
EndFunc

Func joinHeaderAndChunks()
	; TODO
EndFunc

Func writeFooter()
	FileWrite($hOutput, $MAGIC_FOOTER)
	FileWrite($hOutput, _BinaryReverse("0x" & $iCRC32_script))
	$iCRC32_unknown = IniRead(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "crc32_unknown", 0)
	FileWrite($hOutput, _BinaryReverse($iCRC32_unknown))
	$sFooterCmd = IniRead(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "footer_cmd", 0)
	;ConsoleWrite("'" & IniRead(@ScriptDir & "\unpacked\~bundle_info.ini", "common", "footer_cmd", 0) & "'" & @CRLF)
	FileWrite($hOutput, $sFooterCmd)
EndFunc