param(
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$NamesOut = "reverse\lingo-names.csv",
  [string]$ScriptsOut = "reverse\lingo-scripts.csv",
  [string]$HandlersOut = "reverse\lingo-handlers.csv",
  [string]$ConstantsOut = "reverse\lingo-constants.csv",
  [string]$DisassemblyOut = "reverse\lingo-disassembly.csv",
  [string]$CallSitesOut = "reverse\lingo-call-sites.csv"
)

$ErrorActionPreference = "Stop"

function Read-U16BE {
  param([byte[]]$Bytes, [int]$Offset)
  return (([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1])
}

function Read-S16BE {
  param([byte[]]$Bytes, [int]$Offset)
  $value = Read-U16BE -Bytes $Bytes -Offset $Offset
  if ($value -ge 0x8000) {
    return $value - 0x10000
  }
  return $value
}

function Read-U32BE {
  param([byte[]]$Bytes, [int]$Offset)
  return (([uint32]$Bytes[$Offset] -shl 24) -bor
    ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
    ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
    [uint32]$Bytes[$Offset + 3])
}

function Read-Tag {
  param([byte[]]$Bytes)
  return [Text.Encoding]::ASCII.GetString($Bytes, 0, 4)
}

function Get-Name {
  param([string[]]$Names, [int]$Index)
  if ($Index -ge 0 -and $Index -lt $Names.Count) {
    return $Names[$Index]
  }
  return ""
}

function Join-Unique {
  param([object[]]$Values)
  $items = @($Values | Where-Object { $_ -ne $null -and "$_" -ne "" } | Select-Object -Unique)
  return ($items -join ",")
}

function Read-NameList {
  param([byte[]]$Bytes, [int]$BodyStart, [int]$Offset, [int]$Count, [string[]]$Names)

  $items = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $Count; $i++) {
    $nameIndex = Read-S16BE -Bytes $Bytes -Offset ($BodyStart + $Offset + ($i * 2))
    $name = Get-Name -Names $Names -Index $nameIndex
    if ($name) {
      $items.Add($name)
    } else {
      $items.Add("#$nameIndex")
    }
  }
  return @($items)
}

function Read-Constants {
  param(
    [byte[]]$Bytes,
    [int]$BodyStart,
    [int]$Count,
    [int]$ConstantOffset,
    [int]$StoreOffset
  )

  $items = [System.Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $Count; $i++) {
    $entryOffset = $BodyStart + $ConstantOffset + ($i * 8)
    $type = Read-U32BE -Bytes $Bytes -Offset $entryOffset
    $value = Read-U32BE -Bytes $Bytes -Offset ($entryOffset + 4)
    $decoded = ""
    $decodedType = "type-$type"

    if ($type -eq 1) {
      $decodedType = "string"
      $stringOffset = $BodyStart + $StoreOffset + [int]$value
      if ($stringOffset + 4 -le $Bytes.Length) {
        $length = [int](Read-U32BE -Bytes $Bytes -Offset $stringOffset)
        if ($length -ge 0 -and $stringOffset + 4 + $length -le $Bytes.Length) {
          $rawLength = $length
          if ($rawLength -gt 0 -and $Bytes[$stringOffset + 4 + $rawLength - 1] -eq 0) {
            $rawLength--
          }
          if ($rawLength -gt 0) {
            $decoded = [Text.Encoding]::ASCII.GetString($Bytes, $stringOffset + 4, $rawLength)
          }
        }
      }
    } elseif ($type -eq 4) {
      $decodedType = "integer"
      $decoded = [string]$value
    }

    $items.Add([pscustomobject]@{
      ConstantIndex = $i
      ConstantTableOffset = $i * 8
      Type = $type
      DecodedType = $decodedType
      Value = $value
      DecodedValue = $decoded
    })
  }
  return @($items)
}

function Get-ConstantByTableOffset {
  param([object[]]$Constants, [int]$TableOffset)
  foreach ($constant in $Constants) {
    if ([int]$constant.ConstantTableOffset -eq $TableOffset) {
      return $constant
    }
  }
  return $null
}

$opNames = @{
  0x01 = "return"
  0x02 = "return-value"
  0x03 = "push-zero"
  0x04 = "add"
  0x05 = "subtract"
  0x06 = "multiply"
  0x07 = "divide"
  0x08 = "mod"
  0x09 = "inverse"
  0x0A = "join-string"
  0x0B = "join-pad-string"
  0x0C = "less-than"
  0x0D = "less-than-equal"
  0x0E = "not-equal"
  0x0F = "equal"
  0x10 = "greater-than"
  0x11 = "greater-than-equal"
  0x12 = "and"
  0x13 = "or"
  0x14 = "not"
  0x41 = "push-int8"
  0x42 = "push-arg-count-call"
  0x43 = "push-arg-count-call-return"
  0x44 = "push-constant"
  0x49 = "push-global"
  0x4A = "push-the-property"
  0x4B = "push-argument-property"
  0x4C = "push-local"
  0x4F = "assign-global"
  0x50 = "assign-the-property"
  0x51 = "assign-argument-property"
  0x52 = "assign-local"
  0x53 = "jump"
  0x54 = "jump-back"
  0x55 = "jump-if-zero"
  0x56 = "call-local-handler"
  0x57 = "call-named"
  0x5C = "push-entity-property"
  0x5D = "assign-entity-property"
  0x81 = "push-int16"
  0x82 = "push-arg-count-call16"
  0x83 = "push-arg-count-call-return16"
  0x84 = "push-constant16"
  0x89 = "push-global16"
  0x8A = "push-the-property16"
  0x8B = "push-argument-property16"
  0x8C = "push-local16"
  0x8F = "assign-global16"
  0x90 = "assign-the-property16"
  0x91 = "assign-argument-property16"
  0x92 = "assign-local16"
  0x93 = "jump16"
  0x94 = "jump-back16"
  0x95 = "jump-if-zero16"
  0x96 = "call-local-handler16"
  0x97 = "call-named16"
  0x9C = "push-entity-property16"
  0x9D = "assign-entity-property16"
}

$operandOps = @(0x41,0x42,0x43,0x44,0x49,0x4A,0x4B,0x4C,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x5C,0x5D)
$wideOperandOps = @(0x81,0x82,0x83,0x84,0x89,0x8A,0x8B,0x8C,0x8F,0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x9C,0x9D)

function Export-DisassemblyRows {
  param(
    [byte[]]$Bytes,
    [int]$BodyStart,
    [object]$Script,
    [object]$Handler,
    [string[]]$Names,
    [object[]]$Constants,
    [string[]]$Properties,
    [string[]]$Globals,
    [string[]]$Args,
    [string[]]$Locals
  )

  $rows = [System.Collections.Generic.List[object]]::new()
  $start = $BodyStart + [int]$Handler.BytecodeStartOffset
  $end = $start + [int]$Handler.BytecodeLength
  $pos = $start

  while ($pos -lt $end -and $pos -lt $Bytes.Length) {
    $opOffset = $pos - $BodyStart
    $opcode = [int]$Bytes[$pos]
    $pos++
    $operand = ""
    $operandHex = ""
    $resolved = ""
    $mnemonic = if ($opNames.ContainsKey($opcode)) { $opNames[$opcode] } else { "op-0x{0:X2}" -f $opcode }

    if ($operandOps -contains $opcode) {
      if ($pos -ge $Bytes.Length) {
        break
      }
      $operand = [int]$Bytes[$pos]
      $operandHex = "{0:X2}" -f $operand
      $pos++
    } elseif ($wideOperandOps -contains $opcode) {
      if ($pos + 1 -ge $Bytes.Length) {
        break
      }
      $operand = Read-U16BE -Bytes $Bytes -Offset $pos
      $operandHex = "{0:X4}" -f $operand
      $pos += 2
    }

    if ($operand -ne "") {
      switch ($opcode) {
        { $_ -in @(0x44, 0x84) } {
          $constant = Get-ConstantByTableOffset -Constants $Constants -TableOffset ([int]$operand)
          if ($constant) {
            $resolved = "$($constant.DecodedType):$($constant.DecodedValue)"
          }
          break
        }
        { $_ -in @(0x49, 0x89, 0x4F, 0x8F) } {
          $resolved = if ([int]$operand -lt $Globals.Count) { $Globals[[int]$operand] } else { "" }
          break
        }
        { $_ -in @(0x4B, 0x8B, 0x51, 0x91) } {
          $resolved = if ([int]$operand -lt $Properties.Count) { $Properties[[int]$operand] } elseif ([int]$operand -lt $Args.Count) { $Args[[int]$operand] } else { "" }
          break
        }
        { $_ -in @(0x4C, 0x8C, 0x52, 0x92) } {
          $resolved = if ([int]$operand -lt $Locals.Count) { $Locals[[int]$operand] } else { "" }
          break
        }
        { $_ -in @(0x56, 0x96, 0x57, 0x97) } {
          $resolved = Get-Name -Names $Names -Index ([int]$operand)
          break
        }
      }
    }

    $rows.Add([pscustomobject]@{
      ScriptResourceIndex = $Script.ResourceIndex
      ScriptOrdinal = $Script.ScriptOrdinal
      LctxId = $Script.LctxId
      AssemblyId = $Script.AssemblyId
      Handler = $Handler.HandlerName
      HandlerOrdinal = $Handler.HandlerOrdinal
      BodyOffset = ("0x{0:X}" -f $opOffset)
      Opcode = ("0x{0:X2}" -f $opcode)
      Mnemonic = $mnemonic
      Operand = $operand
      OperandHex = $operandHex
      Resolved = $resolved
      File = $Script.File
    })
  }

  return @($rows)
}

if (-not (Test-Path -LiteralPath $ResourceManifest)) {
  throw "Resource manifest not found: $ResourceManifest. Run tools\export-director-resources.ps1 first."
}

$resources = @(Import-Csv -LiteralPath $ResourceManifest)
$lnam = @($resources | Where-Object { $_.Type -eq "Lnam" } | Select-Object -First 1)
if ($lnam.Count -eq 0) {
  throw "No Lnam resource found in $ResourceManifest"
}

$nameBytes = [IO.File]::ReadAllBytes($lnam[0].File)
if ((Read-Tag -Bytes $nameBytes) -ne "manL") {
  throw "Unexpected Lnam tag in $($lnam[0].File)"
}

$nameBody = 8
$namesOffset = Read-U16BE -Bytes $nameBytes -Offset ($nameBody + 0x10)
$namesCount = Read-U16BE -Bytes $nameBytes -Offset ($nameBody + 0x12)
$names = [System.Collections.Generic.List[string]]::new()
$nameRows = [System.Collections.Generic.List[object]]::new()
$namePos = $nameBody + $namesOffset
for ($i = 0; $i -lt $namesCount; $i++) {
  $length = [int]$nameBytes[$namePos]
  $value = ""
  if ($length -gt 0) {
    $value = [Text.Encoding]::ASCII.GetString($nameBytes, $namePos + 1, $length)
  }
  $names.Add($value)
  $nameRows.Add([pscustomobject]@{
    NameIndex = $i
    Name = $value
    Offset = ("0x{0:X}" -f ($namePos - $nameBody))
    ResourceIndex = $lnam[0].Index
    File = $lnam[0].File
  })
  $namePos += 1 + $length
}

$scriptRows = [System.Collections.Generic.List[object]]::new()
$handlerRows = [System.Collections.Generic.List[object]]::new()
$constantRows = [System.Collections.Generic.List[object]]::new()
$disassemblyRows = [System.Collections.Generic.List[object]]::new()
$scripts = @($resources | Where-Object { $_.Type -eq "Lscr" } | Sort-Object {[int]$_.Index})
$scriptOrdinal = 0

foreach ($resource in $scripts) {
  $bytes = [IO.File]::ReadAllBytes($resource.File)
  if ((Read-Tag -Bytes $bytes) -ne "rcsL") {
    throw "Unexpected Lscr tag in $($resource.File)"
  }

  $body = 8
  $length = Read-U32BE -Bytes $bytes -Offset ($body + 0x08)
  $lengthAgain = Read-U32BE -Bytes $bytes -Offset ($body + 0x0C)
  $codeStoreOffset = Read-U16BE -Bytes $bytes -Offset ($body + 0x10)
  $lctxId = Read-U16BE -Bytes $bytes -Offset ($body + 0x12)
  $parentNumber = Read-S16BE -Bytes $bytes -Offset ($body + 0x16)
  $scriptFlags = Read-U32BE -Bytes $bytes -Offset ($body + 0x26)
  $assemblyId = Read-S16BE -Bytes $bytes -Offset ($body + 0x2E)
  $factoryNameId = Read-S16BE -Bytes $bytes -Offset ($body + 0x30)
  $eventMapCount = Read-U16BE -Bytes $bytes -Offset ($body + 0x32)
  $eventMapOffset = Read-U32BE -Bytes $bytes -Offset ($body + 0x34)
  $eventMapFlags = Read-U32BE -Bytes $bytes -Offset ($body + 0x38)
  $propertiesCount = Read-U16BE -Bytes $bytes -Offset ($body + 0x3C)
  $propertiesOffset = Read-U32BE -Bytes $bytes -Offset ($body + 0x3E)
  $globalsCount = Read-U16BE -Bytes $bytes -Offset ($body + 0x42)
  $globalsOffset = Read-U32BE -Bytes $bytes -Offset ($body + 0x44)
  $functionsCount = Read-U16BE -Bytes $bytes -Offset ($body + 0x48)
  $functionsOffset = Read-U32BE -Bytes $bytes -Offset ($body + 0x4A)
  $constantsCount = Read-U16BE -Bytes $bytes -Offset ($body + 0x4E)
  $constantsOffset = Read-U32BE -Bytes $bytes -Offset ($body + 0x50)
  $constantsStoreCount = Read-U32BE -Bytes $bytes -Offset ($body + 0x54)
  $constantsStoreOffset = Read-U32BE -Bytes $bytes -Offset ($body + 0x58)

  $properties = Read-NameList -Bytes $bytes -BodyStart $body -Offset $propertiesOffset -Count $propertiesCount -Names $names.ToArray()
  $globals = Read-NameList -Bytes $bytes -BodyStart $body -Offset $globalsOffset -Count $globalsCount -Names $names.ToArray()
  $constants = Read-Constants -Bytes $bytes -BodyStart $body -Count $constantsCount -ConstantOffset $constantsOffset -StoreOffset $constantsStoreOffset
  $stringConstants = Join-Unique @($constants | Where-Object { $_.DecodedType -eq "string" } | Select-Object -ExpandProperty DecodedValue)
  $integerConstants = Join-Unique @($constants | Where-Object { $_.DecodedType -eq "integer" } | Select-Object -ExpandProperty DecodedValue)

  $scriptRow = [pscustomobject]@{
    ScriptOrdinal = $scriptOrdinal
    ResourceIndex = $resource.Index
    Relative = $resource.Relative
    Length = $length
    LengthAgain = $lengthAgain
    CodeStoreOffset = $codeStoreOffset
    LctxId = $lctxId
    ParentNumber = $parentNumber
    ScriptFlags = ("0x{0:X}" -f $scriptFlags)
    AssemblyId = $assemblyId
    FactoryNameId = $factoryNameId
    EventMapCount = $eventMapCount
    EventMapOffset = $eventMapOffset
    EventMapFlags = ("0x{0:X}" -f $eventMapFlags)
    PropertiesCount = $propertiesCount
    Properties = ($properties -join ",")
    GlobalsCount = $globalsCount
    Globals = ($globals -join ",")
    FunctionsCount = $functionsCount
    ConstantsCount = $constantsCount
    ConstantsStoreCount = $constantsStoreCount
    StringConstants = $stringConstants
    IntegerConstants = $integerConstants
    File = $resource.File
  }
  $scriptRows.Add($scriptRow)

  foreach ($constant in $constants) {
    $constantRows.Add([pscustomobject]@{
      ScriptResourceIndex = $resource.Index
      ScriptOrdinal = $scriptOrdinal
      LctxId = $lctxId
      AssemblyId = $assemblyId
      ConstantIndex = $constant.ConstantIndex
      ConstantTableOffset = $constant.ConstantTableOffset
      Type = $constant.Type
      DecodedType = $constant.DecodedType
      Value = $constant.Value
      DecodedValue = $constant.DecodedValue
      File = $resource.File
    })
  }

  $handlerObjects = [System.Collections.Generic.List[object]]::new()
  for ($handlerOrdinal = 0; $handlerOrdinal -lt $functionsCount; $handlerOrdinal++) {
    $handlerOffset = $body + $functionsOffset + ($handlerOrdinal * 42)
    $handlerNameIndex = Read-S16BE -Bytes $bytes -Offset $handlerOffset
    $handlerName = Get-Name -Names $names.ToArray() -Index $handlerNameIndex
    $bytecodeLength = Read-U32BE -Bytes $bytes -Offset ($handlerOffset + 4)
    $bytecodeStartOffset = Read-U32BE -Bytes $bytes -Offset ($handlerOffset + 8)
    $argCount = Read-U16BE -Bytes $bytes -Offset ($handlerOffset + 12)
    $argNameOffset = Read-U32BE -Bytes $bytes -Offset ($handlerOffset + 14)
    $varCount = Read-U16BE -Bytes $bytes -Offset ($handlerOffset + 18)
    $varNameOffset = Read-U32BE -Bytes $bytes -Offset ($handlerOffset + 20)
    $args = Read-NameList -Bytes $bytes -BodyStart $body -Offset $argNameOffset -Count $argCount -Names $names.ToArray()
    $locals = Read-NameList -Bytes $bytes -BodyStart $body -Offset $varNameOffset -Count $varCount -Names $names.ToArray()
    $handlerObject = [pscustomobject]@{
      HandlerOrdinal = $handlerOrdinal
      HandlerNameIndex = $handlerNameIndex
      HandlerName = $handlerName
      BytecodeLength = $bytecodeLength
      BytecodeStartOffset = $bytecodeStartOffset
      ArgCount = $argCount
      ArgNameOffset = $argNameOffset
      Args = ($args -join ",")
      VarCount = $varCount
      VarNameOffset = $varNameOffset
      Locals = ($locals -join ",")
    }
    $handlerObjects.Add($handlerObject)
    $handlerRows.Add([pscustomobject]@{
      ScriptResourceIndex = $resource.Index
      ScriptOrdinal = $scriptOrdinal
      LctxId = $lctxId
      AssemblyId = $assemblyId
      HandlerOrdinal = $handlerOrdinal
      HandlerNameIndex = $handlerNameIndex
      HandlerName = $handlerName
      BytecodeLength = $bytecodeLength
      BytecodeStartOffset = $bytecodeStartOffset
      BytecodeStartHex = ("0x{0:X}" -f $bytecodeStartOffset)
      ArgCount = $argCount
      Args = ($args -join ",")
      VarCount = $varCount
      Locals = ($locals -join ",")
      Properties = ($properties -join ",")
      Globals = ($globals -join ",")
      File = $resource.File
    })

    $disassemblyRows.AddRange((Export-DisassemblyRows -Bytes $bytes -BodyStart $body -Script $scriptRow -Handler $handlerObject -Names $names.ToArray() -Constants $constants -Properties $properties -Globals $globals -Args $args -Locals $locals))
  }

  $scriptOrdinal++
}

$nameRows | Export-Csv -LiteralPath $NamesOut -NoTypeInformation
$scriptRows | Export-Csv -LiteralPath $ScriptsOut -NoTypeInformation
$handlerRows | Export-Csv -LiteralPath $HandlersOut -NoTypeInformation
$constantRows | Export-Csv -LiteralPath $ConstantsOut -NoTypeInformation
$disassemblyRows | Export-Csv -LiteralPath $DisassemblyOut -NoTypeInformation

$callRows = [System.Collections.Generic.List[object]]::new()
$disassemblyArray = @($disassemblyRows)
for ($i = 0; $i -lt $disassemblyArray.Count; $i++) {
  $row = $disassemblyArray[$i]
  if ($row.Mnemonic -notin @("call-named", "call-named16", "call-local-handler", "call-local-handler16")) {
    continue
  }

  $context = [System.Collections.Generic.List[object]]::new()
  $start = [Math]::Max(0, $i - 12)
  for ($j = $start; $j -lt $i; $j++) {
    $candidate = $disassemblyArray[$j]
    if ($candidate.ScriptResourceIndex -eq $row.ScriptResourceIndex -and $candidate.Handler -eq $row.Handler) {
      $context.Add($candidate)
    }
  }

  $constants = @($context | Where-Object { $_.Resolved -like "string:*" -or $_.Resolved -like "integer:*" } | Select-Object -ExpandProperty Resolved)
  $argCounts = @($context | Where-Object { $_.Mnemonic -like "push-arg-count*" } | Select-Object -ExpandProperty Operand)
  $callRows.Add([pscustomobject]@{
    ScriptResourceIndex = $row.ScriptResourceIndex
    ScriptOrdinal = $row.ScriptOrdinal
    LctxId = $row.LctxId
    AssemblyId = $row.AssemblyId
    Handler = $row.Handler
    BodyOffset = $row.BodyOffset
    CallMnemonic = $row.Mnemonic
    CallTarget = $row.Resolved
    CallTargetOperand = $row.Operand
    LastArgCount = if ($argCounts.Count -gt 0) { $argCounts[-1] } else { "" }
    NearbyConstants = Join-Unique $constants
    LastNearbyConstant = if ($constants.Count -gt 0) { $constants[-1] } else { "" }
    Context = (($context | ForEach-Object { "$($_.BodyOffset):$($_.Mnemonic):$($_.Resolved)" }) -join " | ")
    File = $row.File
  })
}
$callRows | Export-Csv -LiteralPath $CallSitesOut -NoTypeInformation

"Lingo names: $($nameRows.Count) -> $NamesOut"
"Lingo scripts: $($scriptRows.Count) -> $ScriptsOut"
"Lingo handlers: $($handlerRows.Count) -> $HandlersOut"
"Lingo constants: $($constantRows.Count) -> $ConstantsOut"
"Lingo disassembly rows: $($disassemblyRows.Count) -> $DisassemblyOut"
"Lingo call-site rows: $($callRows.Count) -> $CallSitesOut"
""
"Likely gameplay scripts"
$scriptRows |
  Where-Object { $_.StringConstants -match "G ready|R ready|snowball|GreenWin|Level|mailto|G windup" -or $_.Properties -match "myHits|gd|level" } |
  Format-Table ResourceIndex,LctxId,AssemblyId,Properties,Globals,FunctionsCount,StringConstants -AutoSize
