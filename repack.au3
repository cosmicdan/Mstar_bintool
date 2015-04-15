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

Global $sOutputFile = @ScriptDir & "\MstarUpgrade.bin.out"

If Not FileExists(@ScriptDir & "\unpacked") Then
	ConsoleWrite("[!] Folder 'unpacked' does not exist. Unpack something first." & @CRLF)
	Exit
EndIf

If FileExists(@ScriptDir & "\MstarUpgrade.bin.out") Then
	;ConsoleWrite("[!] A file named 'MstarUpgrade.bin.out' already exists. Remove or rename it first." & @CRLF)
	;Exit
	FileDelete(@ScriptDir & "\MstarUpgrade.bin.out")
EndIf

Global $hOutput = FileOpen($sOutputFile, $FO_APPEND + $FO_BINARY)

writeHeader()
writeChunks()
writeFooter()

Func writeHeader()
	; write-out the header script
	ConsoleWrite("[#] Writing header..." & @CRLF)
	$hInput = FileOpen(@ScriptDir & "\unpacked\~bundle_script", $FO_READ + $FO_BINARY)
	FileWrite($hOutput, FileRead($hInput))
	FileClose($hInput)
	; calculate the new script CRC for later
	$iPID = Run(@ComSpec & " /c " & @ScriptDir & '\inc\crc32 ' & $sOutputFile, @ScriptDir, @SW_HIDE, $STDERR_MERGED)
	Local $sOutput = ""
	Do
		$sOutput &= StdoutRead($iPID)
	Until @error
	$aResult = StringSplit($sOutput, " ")
	If Not $aResult[0] = 2 Then
		ConsoleWrite("[!] Error calculating CRC!" & @CRLF)
		Exit
	EndIf
	$iCRC32_script = StringReplace($aResult[1], "0x", "")
	ConsoleWrite("[i] Header script CRC32 = " & $iCRC32_script & @CRLF)
	; pad the script to 16KB
	$iPadding = 16384 - FileGetSize($sOutputFile)
	For $i = 1 To $iPadding
		FileWrite($hOutput, Chr(0xFF))
	Next
EndFunc

Func writeChunks()
	$iTotalChunks = (IniReadSectionNames(@ScriptDir & "\unpacked\~bundle_info.ini"))[0] - 1 ; element 0 is the number of elements and [common] section is of no significance
	For $i = 1 To $iTotalChunks
		$aChunkInfo = IniReadSection(@ScriptDir & "\unpacked\~bundle_info.ini", "chunk" & $i)
		$sName = $aChunkInfo[1][1]
		$sExtension = _getChunkExtensionByType($aChunkInfo[2][1])
		;ConsoleWrite($sName & $sExtension & @CRLF)
		ConsoleWrite("[#] Adding chunk " & $i & "/" & $iTotalChunks & " (" & $sName & $sExtension & ")...             " & @CRLF)
		$hInput = FileOpen(@ScriptDir & "\unpacked\" & $sName & $sExtension, $FO_READ + $FO_BINARY)
		FileWrite($hOutput, FileRead($hInput))
		FileClose($hInput)
		$iPadding = $aChunkInfo[3][1]
		For $j = 1 To $iPadding
			FileWrite($hOutput, Chr(0xFF))
		Next
	Next
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