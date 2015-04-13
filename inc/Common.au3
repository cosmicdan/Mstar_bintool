#Include-once

Global Const $PART_TYPE_RAW   = 0 ; raw partition image
Global Const $PART_TYPE_SEC   = 1 ; secure info
Global Const $PART_TYPE_NUTTX = 2 ; nuttx config
Global Const $PART_TYPE_LZO   = 3 ; lzo archive
Global Const $PART_TYPE_MISC  = 4 ; misc partition, identified only by the "mmc write.boot" command

Global Const $MAGIC_FOOTER = "12345678" ; random numbers that appears after the last chunk's post-padding and before the CRC32 + init command
										; I *think* this is to do with an 8-byte cylinder boundary

Func _getChunkExtensionByType($i)
	Switch $i
		Case $PART_TYPE_RAW
			Return ".img"
		Case $PART_TYPE_SEC
			Return ".sec"
		Case $PART_TYPE_NUTTX
			Return ".nuttx"
		Case $PART_TYPE_LZO
			Return ".lzo"
		Case $PART_TYPE_MISC
			Return ".img"
	EndSwitch
EndFunc

Func _StringContains($sString, $sSearch)
	If StringInStr($sString, $sSearch) > 0 Then
		Return True
	Else
		Return False
	EndIf
EndFunc