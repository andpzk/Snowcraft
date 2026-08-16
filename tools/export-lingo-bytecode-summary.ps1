param(
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$NamesOut = "reverse\lingo-names.csv",
  [string]$ScriptsOut = "reverse\lingo-scripts.csv",
  [string]$HandlersOut = "reverse\lingo-handlers.csv",
  [string]$ConstantsOut = "reverse\lingo-constants.csv",
  [string]$DisassemblyOut = "reverse\lingo-disassembly.csv",
  [string]$CallSitesOut = "reverse\lingo-call-sites.csv",
  [string]$EntityOpsOut = "reverse\lingo-entity-ops.csv",
  [string]$MemberAssignmentsOut = "reverse\lingo-member-assignments.csv",
  [string]$PseudoOut = "reverse\lingo-pseudocode.csv",
  [string]$BasicBlocksOut = "reverse\lingo-basic-blocks.csv",
  [string]$ControlFlowEdgesOut = "reverse\lingo-control-flow-edges.csv"
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

function New-Entity {
  param(
    [int]$Bank,
    [int]$FirstArg,
    [string]$Entity,
    [string]$Field,
    [bool]$Writable,
    [string]$ArgType
  )

  return [pscustomobject]@{
    Bank = $Bank
    FirstArg = $FirstArg
    Key = "{0}:{1}" -f $Bank,$FirstArg
    Entity = $Entity
    Field = $Field
    Writable = $Writable
    ArgType = $ArgType
  }
}

$opNames = @{
  0x01 = "return"
  0x02 = "return-value"
  0x03 = "push-zero"
  0x04 = "multiply"
  0x05 = "add"
  0x06 = "subtract"
  0x07 = "divide"
  0x08 = "mod"
  0x09 = "inverse"
  0x0A = "ampersand"
  0x0B = "concat"
  0x0C = "less-than"
  0x0D = "less-than-equal"
  0x0E = "not-equal"
  0x0F = "equal"
  0x10 = "greater-than"
  0x11 = "greater-than-equal"
  0x12 = "and"
  0x13 = "or"
  0x14 = "not"
  0x15 = "contains"
  0x16 = "starts"
  0x17 = "of"
  0x18 = "hilite"
  0x19 = "intersects"
  0x1A = "within"
  0x1B = "field"
  0x1C = "tell"
  0x1D = "tell-done"
  0x1E = "list"
  0x1F = "property-list"
  0x41 = "push-int8"
  0x42 = "push-arg-count-call"
  0x43 = "push-arg-count-call-return"
  0x44 = "push-constant"
  0x45 = "push-name"
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
  0x58 = "call-object"
  0x59 = "v4-assign"
  0x5A = "v4-assign2"
  0x5B = "delete"
  0x5C = "push-entity-property"
  0x5D = "assign-entity-property"
  0x5F = "push-the-property2"
  0x60 = "assign-the-property2"
  0x61 = "push-object-field"
  0x62 = "assign-object-field"
  0x63 = "tell-call"
  0x64 = "stack-peek"
  0x65 = "stack-drop"
  0x66 = "push-entity-name-property"
  0x67 = "object-call-d5"
  0x81 = "push-int16"
  0x82 = "push-arg-count-call16"
  0x83 = "push-arg-count-call-return16"
  0x84 = "push-constant16"
  0x85 = "push-name16"
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
  0x98 = "call-object16"
  0x99 = "v4-assign16"
  0x9A = "v4-assign2-16"
  0x9C = "push-entity-property16"
  0x9D = "assign-entity-property16"
  0x9F = "push-the-property2-16"
  0xA0 = "assign-the-property2-16"
  0xA1 = "push-object-field16"
  0xA2 = "assign-object-field16"
  0xA3 = "tell-call16"
  0xA4 = "stack-peek16"
  0xA5 = "stack-drop16"
  0xA6 = "push-entity-name-property16"
  0xA7 = "object-call-d5-16"
}

$entityMap = @{}
$entityRows = @(
  New-Entity 6 1 "sprite" "type" $true "item-id"
  New-Entity 6 2 "sprite" "backColor" $true "item-id"
  New-Entity 6 3 "sprite" "bottom" $true "item-id"
  New-Entity 6 4 "sprite" "castNum" $true "item-id"
  New-Entity 6 5 "sprite" "constraint" $true "item-id"
  New-Entity 6 6 "sprite" "cursor" $true "item-id"
  New-Entity 6 7 "sprite" "foreColor" $true "item-id"
  New-Entity 6 8 "sprite" "height" $true "item-id"
  New-Entity 6 9 "sprite" "immediate" $true "item-id"
  New-Entity 6 10 "sprite" "ink" $true "item-id"
  New-Entity 6 11 "sprite" "left" $true "item-id"
  New-Entity 6 12 "sprite" "lineSize" $true "item-id"
  New-Entity 6 13 "sprite" "locH" $true "item-id"
  New-Entity 6 14 "sprite" "locV" $true "item-id"
  New-Entity 6 15 "sprite" "movieRate" $true "item-id"
  New-Entity 6 16 "sprite" "movieTime" $true "item-id"
  New-Entity 6 17 "sprite" "pattern" $true "item-id"
  New-Entity 6 18 "sprite" "puppet" $true "item-id"
  New-Entity 6 19 "sprite" "right" $true "item-id"
  New-Entity 6 20 "sprite" "startTime" $true "item-id"
  New-Entity 6 21 "sprite" "stopTime" $true "item-id"
  New-Entity 6 22 "sprite" "stretch" $true "item-id"
  New-Entity 6 23 "sprite" "top" $true "item-id"
  New-Entity 6 24 "sprite" "trails" $true "item-id"
  New-Entity 6 25 "sprite" "visible" $true "item-id"
  New-Entity 6 26 "sprite" "volume" $true "item-id"
  New-Entity 6 27 "sprite" "width" $true "item-id"
  New-Entity 6 28 "sprite" "blend" $true "item-id"
  New-Entity 6 29 "sprite" "scriptNum" $true "item-id"
  New-Entity 6 30 "sprite" "moveableSprite" $true "item-id"
  New-Entity 6 31 "sprite" "editableText" $true "item-id"
  New-Entity 6 32 "sprite" "scoreColor" $true "item-id"
  New-Entity 6 33 "sprite" "loc" $true "item-id"
  New-Entity 6 34 "sprite" "rect" $true "item-id"
  New-Entity 6 35 "sprite" "memberNum" $true "item-id"
  New-Entity 6 36 "sprite" "castLibNum" $true "item-id"
  New-Entity 6 37 "sprite" "member" $true "item-id"
  New-Entity 6 38 "sprite" "scriptInstanceList" $true "item-id"
  New-Entity 6 39 "sprite" "currentTime" $true "item-id"
  New-Entity 6 40 "sprite" "mostRecentCuePoint" $true "item-id"
  New-Entity 6 41 "sprite" "tweened" $true "item-id"
  New-Entity 6 42 "sprite" "name" $true "item-id"
  New-Entity 7 14 "lastClick" "" $true "none"
  New-Entity 7 15 "lastEvent" "" $true "none"
  New-Entity 7 17 "lastKey" "" $true "none"
  New-Entity 7 18 "lastRoll" "" $true "none"
  New-Entity 7 19 "timeoutLapsed" "" $true "none"
  New-Entity 7 25 "soundEnabled" "" $true "none"
  New-Entity 7 26 "soundLevel" "" $true "none"
  New-Entity 7 31 "timeoutLength" "" $true "none"
  New-Entity 7 32 "timeoutMouse" "" $true "none"
  New-Entity 7 33 "timeoutPlay" "" $true "none"
  New-Entity 7 34 "timer" "" $true "none"
  New-Entity 9 1 "cast" "name" $true "item-id"
  New-Entity 9 2 "cast" "text" $true "item-id"
  New-Entity 9 3 "cast" "textStyle" $true "item-id"
  New-Entity 9 4 "cast" "textFont" $true "item-id"
  New-Entity 9 5 "cast" "textHeight" $true "item-id"
  New-Entity 9 6 "cast" "textAlign" $true "item-id"
  New-Entity 9 7 "cast" "textSize" $true "item-id"
  New-Entity 9 8 "cast" "picture" $true "item-id"
  New-Entity 9 9 "cast" "hilite" $true "item-id"
  New-Entity 9 10 "cast" "number" $true "item-id"
  New-Entity 9 11 "cast" "size" $true "item-id"
  New-Entity 9 17 "cast" "foreColor" $true "item-id"
  New-Entity 9 18 "cast" "backColor" $true "item-id"
  New-Entity 9 19 "cast" "type" $true "item-id"
)
foreach ($entity in $entityRows) {
  $entityMap[$entity.Key] = $entity
}

function New-Expr {
  param(
    [string]$Expr,
    [string]$Kind = "expr"
  )

  return [pscustomobject]@{
    Expr = $Expr
    Kind = $Kind
  }
}

function Pop-Expr {
  param([System.Collections.Generic.List[object]]$Stack)

  if ($Stack.Count -eq 0) {
    return New-Expr "<stack-empty>" "unknown"
  }

  $index = $Stack.Count - 1
  $value = $Stack[$index]
  $Stack.RemoveAt($index)
  return $value
}

function Push-Expr {
  param(
    [System.Collections.Generic.List[object]]$Stack,
    [string]$Expr,
    [string]$Kind = "expr"
  )

  $Stack.Add((New-Expr $Expr $Kind))
}

function Format-ConstantExpr {
  param([string]$Resolved)

  if ($Resolved -like "string:*") {
    $value = $Resolved.Substring(7).Replace('"', '\"')
    return '"' + $value + '"'
  }
  if ($Resolved -like "integer:*") {
    return $Resolved.Substring(8)
  }
  if ($Resolved) {
    return $Resolved
  }
  return "<constant>"
}

function Test-ZeroExpr {
  param([object]$Expr)

  return ($Expr.Expr -eq "0")
}

function Format-ChunkSelection {
  param(
    [string]$Kind,
    [object]$First,
    [object]$Last,
    [string]$Source
  )

  if (Test-ZeroExpr $First) {
    return $Source
  }

  if ((Test-ZeroExpr $Last) -or $Last.Expr -eq $First.Expr) {
    return "$Kind $($First.Expr) of $Source"
  }

  return "$Kind $($First.Expr) to $($Last.Expr) of $Source"
}

function Get-EntityStackInfo {
  param(
    [int]$Bank,
    [object]$FirstArg,
    [System.Collections.Generic.List[object]]$Stack
  )

  $entity = $null
  $key = "{0}:{1}" -f $Bank,[int]$FirstArg.Expr
  if ($entityMap.ContainsKey($key)) {
    $entity = $entityMap[$key]
  }

  $target = ""
  if ($entity) {
    if ($entity.ArgType -eq "item-id") {
      $id = Pop-Expr $Stack
      if ($entity.Entity -eq "cast") {
        $member = Pop-Expr $Stack
        if ($entity.Field) {
          $target = "the $($entity.Field) of cast $($member.Expr)"
        } else {
          $target = "the cast $($member.Expr)"
        }
        if ($id.Expr -ne "0") {
          $target += " of castLib $($id.Expr)"
        }
      } else {
        if ($entity.Field) {
          $target = "the $($entity.Field) of $($entity.Entity) $($id.Expr)"
        } else {
          $target = "the $($entity.Entity) $($id.Expr)"
        }
      }
    } else {
      $target = if ($entity.Field) { "the $($entity.Field) of $($entity.Entity)" } else { "the $($entity.Entity)" }
    }
  } else {
    $target = "the entity[$Bank,$($FirstArg.Expr)]"
  }

  return [pscustomobject]@{
    Entity = $entity
    Target = $target
  }
}

function Add-PseudoRow {
  param(
    [System.Collections.Generic.List[object]]$Rows,
    [object]$SourceRow,
    [string]$Kind,
    [string]$Statement,
    [int]$StackDepth,
    [string]$Confidence = "stack-simulated"
  )

  $Rows.Add([pscustomobject]@{
    ScriptResourceIndex = $SourceRow.ScriptResourceIndex
    ScriptOrdinal = $SourceRow.ScriptOrdinal
    LctxId = $SourceRow.LctxId
    AssemblyId = $SourceRow.AssemblyId
    Handler = $SourceRow.Handler
    HandlerOrdinal = $SourceRow.HandlerOrdinal
    BodyOffset = $SourceRow.BodyOffset
    Kind = $Kind
    Statement = $Statement
    StackDepth = $StackDepth
    Confidence = $Confidence
    File = $SourceRow.File
  })
}

function Convert-HexOffset {
  param([string]$Value)

  if (-not $Value) {
    return 0
  }
  return [Convert]::ToInt32(($Value -replace "^0x", ""), 16)
}

function Get-InstructionSize {
  param([object]$Row)

  if ($Row.OperandHex) {
    return 1 + (($Row.OperandHex.Length) / 2)
  }
  return 1
}

function Get-NextOffset {
  param([object]$Row)

  return (Convert-HexOffset $Row.BodyOffset) + (Get-InstructionSize $Row)
}

function Get-JumpTargetOffset {
  param([object]$Row)

  $current = Convert-HexOffset $Row.BodyOffset
  $operand = if ($Row.Operand -ne "") { [int]$Row.Operand } else { 0 }
  if ($Row.Mnemonic -in @("jump-back", "jump-back16")) {
    return $current - $operand
  }
  return $current + $operand
}

$operandOps = @(0x41,0x42,0x43,0x44,0x45,0x49,0x4A,0x4B,0x4C,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,0x5C,0x5D,0x5F,0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67)
$wideOperandOps = @(0x81,0x82,0x83,0x84,0x85,0x89,0x8A,0x8B,0x8C,0x8F,0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9C,0x9D,0x9F,0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7)

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

    if ($operand -is [int]) {
      switch ($opcode) {
        { $_ -in @(0x44, 0x84) } {
          $constant = Get-ConstantByTableOffset -Constants $Constants -TableOffset ([int]$operand)
          if ($constant) {
            $resolved = "$($constant.DecodedType):$($constant.DecodedValue)"
          }
          break
        }
        { $_ -in @(0x45, 0x85, 0x4A, 0x8A, 0x50, 0x90, 0x5F, 0x9F, 0x60, 0xA0, 0x61, 0xA1, 0x62, 0xA2, 0x63, 0xA3, 0x66, 0xA6, 0x67, 0xA7) } {
          $resolved = Get-Name -Names $Names -Index ([int]$operand)
          break
        }
        { $_ -in @(0x49, 0x89, 0x4F, 0x8F) } {
          $resolved = Get-Name -Names $Names -Index ([int]$operand)
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

$disassemblyArray = @($disassemblyRows)
$pseudoRows = [System.Collections.Generic.List[object]]::new()
$stack = [System.Collections.Generic.List[object]]::new()
$currentHandlerKey = ""
foreach ($row in $disassemblyArray) {
  $handlerKey = "$($row.ScriptResourceIndex):$($row.HandlerOrdinal)"
  if ($handlerKey -ne $currentHandlerKey) {
    $stack = [System.Collections.Generic.List[object]]::new()
    $currentHandlerKey = $handlerKey
  }

  switch ($row.Mnemonic) {
    "push-zero" {
      Push-Expr $stack "0" "literal"
      continue
    }
    { $_ -in @("push-int8", "push-int16") } {
      Push-Expr $stack ([string]$row.Operand) "literal"
      continue
    }
    { $_ -in @("push-constant", "push-constant16") } {
      Push-Expr $stack (Format-ConstantExpr $row.Resolved) "constant"
      continue
    }
    { $_ -in @("push-name", "push-name16") } {
      Push-Expr $stack $(if ($row.Resolved) { "#$($row.Resolved)" } else { "#$($row.Operand)" }) "name"
      continue
    }
    { $_ -in @("push-global", "push-global16") } {
      Push-Expr $stack $(if ($row.Resolved) { $row.Resolved } else { "global[$($row.Operand)]" }) "global"
      continue
    }
    { $_ -in @("assign-global", "assign-global16") } {
      $value = Pop-Expr $stack
      $target = if ($row.Resolved) { $row.Resolved } else { "global[$($row.Operand)]" }
      Add-PseudoRow $pseudoRows $row "assign" "set $target = $($value.Expr)" $stack.Count
      continue
    }
    { $_ -in @("push-the-property", "push-the-property16") } {
      Push-Expr $stack $(if ($row.Resolved) { $row.Resolved } else { "property[$($row.Operand)]" }) "property"
      continue
    }
    { $_ -in @("assign-the-property", "assign-the-property16") } {
      $value = Pop-Expr $stack
      $target = if ($row.Resolved) { $row.Resolved } else { "property[$($row.Operand)]" }
      Add-PseudoRow $pseudoRows $row "assign" "set $target = $($value.Expr)" $stack.Count
      continue
    }
    { $_ -in @("push-the-property2", "push-the-property2-16") } {
      Push-Expr $stack $(if ($row.Resolved) { "the $($row.Resolved)" } else { "movieProperty[$($row.Operand)]" }) "property"
      continue
    }
    { $_ -in @("assign-the-property2", "assign-the-property2-16") } {
      $value = Pop-Expr $stack
      $target = if ($row.Resolved) { "the $($row.Resolved)" } else { "movieProperty[$($row.Operand)]" }
      Add-PseudoRow $pseudoRows $row "assign" "set $target = $($value.Expr)" $stack.Count
      continue
    }
    { $_ -in @("push-argument-property", "push-argument-property16") } {
      Push-Expr $stack $(if ($row.Resolved) { $row.Resolved } else { "argOrProp[$($row.Operand)]" }) "variable"
      continue
    }
    { $_ -in @("assign-argument-property", "assign-argument-property16") } {
      $value = Pop-Expr $stack
      $target = if ($row.Resolved) { $row.Resolved } else { "argOrProp[$($row.Operand)]" }
      Add-PseudoRow $pseudoRows $row "assign" "set $target = $($value.Expr)" $stack.Count
      continue
    }
    { $_ -in @("push-local", "push-local16") } {
      Push-Expr $stack $(if ($row.Resolved) { $row.Resolved } else { "local[$($row.Operand)]" }) "local"
      continue
    }
    { $_ -in @("assign-local", "assign-local16") } {
      $value = Pop-Expr $stack
      $target = if ($row.Resolved) { $row.Resolved } else { "local[$($row.Operand)]" }
      Add-PseudoRow $pseudoRows $row "assign" "set $target = $($value.Expr)" $stack.Count
      continue
    }
    { $_ -in @("push-arg-count-call", "push-arg-count-call16", "push-arg-count-call-return", "push-arg-count-call-return16") } {
      $kind = if ($row.Mnemonic -like "*return*") { "argc-return" } else { "argc-no-return" }
      Push-Expr $stack ([string]$row.Operand) $kind
      continue
    }
    "inverse" {
      $value = Pop-Expr $stack
      Push-Expr $stack "(-$($value.Expr))"
      continue
    }
    "of" {
      $source = Pop-Expr $stack
      $lastLine = Pop-Expr $stack
      $firstLine = Pop-Expr $stack
      $lastItem = Pop-Expr $stack
      $firstItem = Pop-Expr $stack
      $lastWord = Pop-Expr $stack
      $firstWord = Pop-Expr $stack
      $lastChar = Pop-Expr $stack
      $firstChar = Pop-Expr $stack

      $expr = $source.Expr
      $expr = Format-ChunkSelection "line" $firstLine $lastLine $expr
      $expr = Format-ChunkSelection "item" $firstItem $lastItem $expr
      $expr = Format-ChunkSelection "word" $firstWord $lastWord $expr
      $expr = Format-ChunkSelection "char" $firstChar $lastChar $expr
      Push-Expr $stack $expr "chunk"
      continue
    }
    { $_ -in @("multiply", "add", "subtract", "divide", "mod", "ampersand", "concat", "less-than", "less-than-equal", "not-equal", "equal", "greater-than", "greater-than-equal", "and", "or", "contains", "starts", "intersects", "within") } {
      $right = Pop-Expr $stack
      $left = Pop-Expr $stack
      $operator = switch ($row.Mnemonic) {
        "multiply" { "*" }
        "add" { "+" }
        "subtract" { "-" }
        "divide" { "/" }
        "mod" { "mod" }
        "ampersand" { "&" }
        "concat" { "&&" }
        "less-than" { "<" }
        "less-than-equal" { "<=" }
        "not-equal" { "<>" }
        "equal" { "=" }
        "greater-than" { ">" }
        "greater-than-equal" { ">=" }
        "and" { "and" }
        "or" { "or" }
        "contains" { "contains" }
        "starts" { "starts" }
        "intersects" { "intersects" }
        "within" { "within" }
      }
      Push-Expr $stack "($($left.Expr) $operator $($right.Expr))"
      continue
    }
    "not" {
      $value = Pop-Expr $stack
      Push-Expr $stack "(not $($value.Expr))"
      continue
    }
    { $_ -in @("push-entity-property", "push-entity-property16") } {
      $firstArg = Pop-Expr $stack
      $info = Get-EntityStackInfo ([int]$row.Operand) $firstArg $stack
      Push-Expr $stack $info.Target "entity"
      continue
    }
    { $_ -in @("assign-entity-property", "assign-entity-property16") } {
      $firstArg = Pop-Expr $stack
      $value = Pop-Expr $stack
      $info = Get-EntityStackInfo ([int]$row.Operand) $firstArg $stack
      Add-PseudoRow $pseudoRows $row "assign" "set $($info.Target) = $($value.Expr)" $stack.Count
      continue
    }
    { $_ -in @("call-named", "call-named16", "call-local-handler", "call-local-handler16") } {
      $argc = Pop-Expr $stack
      $argCount = 0
      if ($argc.Kind -like "argc*") {
        $argCount = [int]$argc.Expr
      } else {
        Push-Expr $stack $argc.Expr $argc.Kind
      }
      $args = [System.Collections.Generic.List[string]]::new()
      for ($argIndex = 0; $argIndex -lt $argCount; $argIndex++) {
        $arg = Pop-Expr $stack
        $args.Insert(0, $arg.Expr)
      }
      $target = if ($row.Resolved) { $row.Resolved } else { "call[$($row.Operand)]" }
      $expr = "$target($($args -join ', '))"
      if ($argc.Kind -eq "argc-return") {
        Push-Expr $stack $expr "call-result"
        Add-PseudoRow $pseudoRows $row "call-return" $expr $stack.Count
      } else {
        Add-PseudoRow $pseudoRows $row "call" $expr $stack.Count
      }
      continue
    }
    { $_ -in @("jump", "jump16", "jump-back", "jump-back16") } {
      Add-PseudoRow $pseudoRows $row "jump" "jump $($row.Operand)" $stack.Count
      continue
    }
    { $_ -in @("jump-if-zero", "jump-if-zero16") } {
      $condition = Pop-Expr $stack
      Add-PseudoRow $pseudoRows $row "branch" "if not ($($condition.Expr)) jump $($row.Operand)" $stack.Count
      continue
    }
    { $_ -in @("return", "return-value") } {
      $statement = if ($row.Mnemonic -eq "return-value" -and $stack.Count -gt 0) {
        $value = Pop-Expr $stack
        "return $($value.Expr)"
      } else {
        "return"
      }
      Add-PseudoRow $pseudoRows $row "return" $statement $stack.Count
      continue
    }
    { $_ -in @("stack-drop", "stack-drop16") } {
      for ($dropIndex = 0; $dropIndex -lt [int]$row.Operand; $dropIndex++) {
        [void](Pop-Expr $stack)
      }
      Add-PseudoRow $pseudoRows $row "stack" "drop $($row.Operand)" $stack.Count "stack-maintenance"
      continue
    }
    { $_ -in @("stack-peek", "stack-peek16") } {
      if ([int]$row.Operand -lt $stack.Count) {
        $sourceIndex = $stack.Count - 1 - [int]$row.Operand
        Push-Expr $stack $stack[$sourceIndex].Expr $stack[$sourceIndex].Kind
      } else {
        Push-Expr $stack "<stack-peek:$($row.Operand)>" "unknown"
      }
      continue
    }
  }
}
$pseudoRows | Export-Csv -LiteralPath $PseudoOut -NoTypeInformation

$basicBlockRows = [System.Collections.Generic.List[object]]::new()
$controlFlowRows = [System.Collections.Generic.List[object]]::new()
$rowsByHandler = $disassemblyArray | Group-Object ScriptResourceIndex,HandlerOrdinal
foreach ($handlerGroup in $rowsByHandler) {
  $instructions = @($handlerGroup.Group | Sort-Object { Convert-HexOffset $_.BodyOffset })
  if ($instructions.Count -eq 0) {
    continue
  }

  $leaderSet = @{}
  $leaderSet[(Convert-HexOffset $instructions[0].BodyOffset)] = $true
  foreach ($instruction in $instructions) {
    if ($instruction.Mnemonic -in @("jump", "jump16", "jump-back", "jump-back16", "jump-if-zero", "jump-if-zero16")) {
      $target = Get-JumpTargetOffset $instruction
      $leaderSet[$target] = $true
      $next = Get-NextOffset $instruction
      if ($instruction.Mnemonic -in @("jump-if-zero", "jump-if-zero16")) {
        $leaderSet[$next] = $true
      } elseif ($instruction.Mnemonic -notin @("jump-back", "jump-back16", "jump", "jump16")) {
        $leaderSet[$next] = $true
      }
    } elseif ($instruction.Mnemonic -in @("return", "return-value")) {
      $leaderSet[(Get-NextOffset $instruction)] = $true
    }
  }

  $leaders = @($leaderSet.Keys | Sort-Object)
  $blockByStart = @{}
  for ($blockOrdinal = 0; $blockOrdinal -lt $leaders.Count; $blockOrdinal++) {
    $startOffset = [int]$leaders[$blockOrdinal]
    $endExclusive = if ($blockOrdinal + 1 -lt $leaders.Count) { [int]$leaders[$blockOrdinal + 1] } else { [int]::MaxValue }
    $blockInstructions = @($instructions | Where-Object {
      $offset = Convert-HexOffset $_.BodyOffset
      $offset -ge $startOffset -and $offset -lt $endExclusive
    })
    if ($blockInstructions.Count -eq 0) {
      continue
    }

    $actualStart = Convert-HexOffset $blockInstructions[0].BodyOffset
    $lastInstruction = $blockInstructions[-1]
    $actualEnd = Get-NextOffset $lastInstruction
    $blockId = "{0}:{1}:{2}" -f $blockInstructions[0].ScriptResourceIndex,$blockInstructions[0].HandlerOrdinal,("0x{0:X}" -f $actualStart)
    $blockByStart[$actualStart] = $blockId
    $pseudoStatements = @($pseudoRows | Where-Object {
      $_.ScriptResourceIndex -eq $blockInstructions[0].ScriptResourceIndex -and
      $_.HandlerOrdinal -eq $blockInstructions[0].HandlerOrdinal -and
      (Convert-HexOffset $_.BodyOffset) -ge $actualStart -and
      (Convert-HexOffset $_.BodyOffset) -lt $actualEnd
    } | Select-Object -ExpandProperty Statement)
    $memberStateStatements = @($pseudoStatements | Where-Object { $_ -match 'set the memberNum of sprite .+ = the number of cast "([^"]+)"' })
    $states = @($memberStateStatements | ForEach-Object {
      if ($_ -match 'set the memberNum of sprite .+ = the number of cast "([^"]+)"') {
        $Matches[1]
      }
    } | Select-Object -Unique)

    $basicBlockRows.Add([pscustomobject]@{
      BlockId = $blockId
      ScriptResourceIndex = $blockInstructions[0].ScriptResourceIndex
      ScriptOrdinal = $blockInstructions[0].ScriptOrdinal
      LctxId = $blockInstructions[0].LctxId
      AssemblyId = $blockInstructions[0].AssemblyId
      Handler = $blockInstructions[0].Handler
      HandlerOrdinal = $blockInstructions[0].HandlerOrdinal
      StartOffset = ("0x{0:X}" -f $actualStart)
      EndOffsetExclusive = ("0x{0:X}" -f $actualEnd)
      InstructionCount = $blockInstructions.Count
      LastMnemonic = $lastInstruction.Mnemonic
      LastOperand = $lastInstruction.Operand
      StateNames = ($states -join ",")
      PseudoStatements = ($pseudoStatements -join " | ")
      File = $blockInstructions[0].File
    })
  }

  foreach ($block in @($basicBlockRows | Where-Object { $_.ScriptResourceIndex -eq $instructions[0].ScriptResourceIndex -and $_.HandlerOrdinal -eq $instructions[0].HandlerOrdinal })) {
    $blockInstructions = @($instructions | Where-Object {
      $offset = Convert-HexOffset $_.BodyOffset
      $offset -ge (Convert-HexOffset $block.StartOffset) -and $offset -lt (Convert-HexOffset $block.EndOffsetExclusive)
    })
    if ($blockInstructions.Count -eq 0) {
      continue
    }

    $last = $blockInstructions[-1]
    $fromStart = Convert-HexOffset $block.StartOffset
    $next = Get-NextOffset $last
    $edgeCandidates = [System.Collections.Generic.List[object]]::new()
    if ($last.Mnemonic -in @("jump-if-zero", "jump-if-zero16")) {
      $target = Get-JumpTargetOffset $last
      $edgeCandidates.Add([pscustomobject]@{ Kind = "conditional-false"; Target = $target })
      $edgeCandidates.Add([pscustomobject]@{ Kind = "conditional-true"; Target = $next })
    } elseif ($last.Mnemonic -in @("jump", "jump16", "jump-back", "jump-back16")) {
      $target = Get-JumpTargetOffset $last
      $kind = if ($target -le $fromStart) { "loop-back" } else { "jump" }
      $edgeCandidates.Add([pscustomobject]@{ Kind = $kind; Target = $target })
    } elseif ($last.Mnemonic -in @("return", "return-value")) {
      $edgeCandidates.Add([pscustomobject]@{ Kind = "return"; Target = "" })
    } else {
      $edgeCandidates.Add([pscustomobject]@{ Kind = "fallthrough"; Target = $next })
    }

    foreach ($edge in $edgeCandidates) {
      $targetBlockId = ""
      if ($edge.Target -ne "" -and $blockByStart.ContainsKey([int]$edge.Target)) {
        $targetBlockId = $blockByStart[[int]$edge.Target]
      }
      $controlFlowRows.Add([pscustomobject]@{
        FromBlockId = $block.BlockId
        ToBlockId = $targetBlockId
        ScriptResourceIndex = $block.ScriptResourceIndex
        ScriptOrdinal = $block.ScriptOrdinal
        LctxId = $block.LctxId
        AssemblyId = $block.AssemblyId
        Handler = $block.Handler
        HandlerOrdinal = $block.HandlerOrdinal
        FromOffset = $block.StartOffset
        LastInstructionOffset = $last.BodyOffset
        LastMnemonic = $last.Mnemonic
        EdgeKind = $edge.Kind
        TargetOffset = if ($edge.Target -ne "") { "0x{0:X}" -f [int]$edge.Target } else { "" }
        Resolved = if ($targetBlockId) { "yes" } elseif ($edge.Kind -eq "return") { "terminal" } else { "no" }
        File = $block.File
      })
    }
  }
}
$basicBlockRows | Export-Csv -LiteralPath $BasicBlocksOut -NoTypeInformation
$controlFlowRows | Export-Csv -LiteralPath $ControlFlowEdgesOut -NoTypeInformation

$entityOpRows = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $disassemblyArray.Count; $i++) {
  $row = $disassemblyArray[$i]
  if ($row.Mnemonic -notin @("push-entity-property", "assign-entity-property", "push-entity-property16", "assign-entity-property16")) {
    continue
  }

  $propertySource = ""
  $propertyId = ""
  for ($j = $i - 1; $j -ge [Math]::Max(0, $i - 6); $j--) {
    $candidate = $disassemblyArray[$j]
    if ($candidate.ScriptResourceIndex -ne $row.ScriptResourceIndex -or $candidate.Handler -ne $row.Handler) {
      continue
    }
    if ($candidate.Mnemonic -in @("push-int8", "push-int16")) {
      $propertyId = [int]$candidate.Operand
      $propertySource = if ($j -eq ($i - 1)) { "previous-push-int" } else { "nearby-push-int" }
      break
    }
  }

  $bank = [int]$row.Operand
  $entity = $null
  if ($propertyId -ne "") {
    $entityKey = "{0}:{1}" -f $bank,$propertyId
    if ($entityMap.ContainsKey($entityKey)) {
      $entity = $entityMap[$entityKey]
    }
  }

  $context = [System.Collections.Generic.List[object]]::new()
  for ($j = [Math]::Max(0, $i - 8); $j -le [Math]::Min($disassemblyArray.Count - 1, $i + 4); $j++) {
    $candidate = $disassemblyArray[$j]
    if ($candidate.ScriptResourceIndex -eq $row.ScriptResourceIndex -and $candidate.Handler -eq $row.Handler) {
      $context.Add($candidate)
    }
  }

  $entityOpRows.Add([pscustomobject]@{
    ScriptResourceIndex = $row.ScriptResourceIndex
    ScriptOrdinal = $row.ScriptOrdinal
    LctxId = $row.LctxId
    AssemblyId = $row.AssemblyId
    Handler = $row.Handler
    HandlerOrdinal = $row.HandlerOrdinal
    BodyOffset = $row.BodyOffset
    Operation = if ($row.Mnemonic -like "assign-*") { "assign" } else { "push" }
    Opcode = $row.Opcode
    EntityBank = $bank
    EntityPropertyId = $propertyId
    EntityPropertySource = $propertySource
    Entity = if ($entity) { $entity.Entity } else { "" }
    Field = if ($entity) { $entity.Field } else { "" }
    Writable = if ($entity) { $entity.Writable } else { "" }
    ArgType = if ($entity) { $entity.ArgType } else { "" }
    ResolvedExpression = if ($entity) {
      if ($entity.Field) { "the $($entity.Field) of $($entity.Entity)" } else { "the $($entity.Entity)" }
    } else {
      ""
    }
    Context = (($context | ForEach-Object { "$($_.BodyOffset):$($_.Mnemonic):$($_.Operand):$($_.Resolved)" }) -join " | ")
    File = $row.File
  })
}
$entityOpRows | Export-Csv -LiteralPath $EntityOpsOut -NoTypeInformation

$memberAssignmentRows = [System.Collections.Generic.List[object]]::new()
foreach ($pseudo in $pseudoRows) {
  if ($pseudo.Kind -ne "assign" -or $pseudo.Statement -notlike "set the memberNum of sprite *") {
    continue
  }

  $targetExpression = ""
  $stateExpression = ""
  $stateName = ""
  if ($pseudo.Statement -match '^set the memberNum of sprite (.+?) = (.+)$') {
    $targetExpression = $Matches[1]
    $stateExpression = $Matches[2]
  }
  if ($stateExpression -match '^the number of cast "([^"]+)"(?: of castLib .+)?$') {
    $stateName = $Matches[1]
  }

  $memberAssignmentRows.Add([pscustomobject]@{
    ScriptResourceIndex = $pseudo.ScriptResourceIndex
    ScriptOrdinal = $pseudo.ScriptOrdinal
    LctxId = $pseudo.LctxId
    AssemblyId = $pseudo.AssemblyId
    Handler = $pseudo.Handler
    BodyOffset = $pseudo.BodyOffset
    TargetExpression = $targetExpression
    StateExpression = $stateExpression
    StateName = $stateName
    Assignment = $pseudo.Statement
    StackDepth = $pseudo.StackDepth
    Confidence = $pseudo.Confidence
    File = $pseudo.File
  })
}
$memberAssignmentRows | Export-Csv -LiteralPath $MemberAssignmentsOut -NoTypeInformation

$callRows = [System.Collections.Generic.List[object]]::new()
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
"Lingo pseudocode rows: $($pseudoRows.Count) -> $PseudoOut"
"Lingo basic blocks: $($basicBlockRows.Count) -> $BasicBlocksOut"
"Lingo control-flow edges: $($controlFlowRows.Count) -> $ControlFlowEdgesOut"
"Lingo call-site rows: $($callRows.Count) -> $CallSitesOut"
"Lingo entity/property ops: $($entityOpRows.Count) -> $EntityOpsOut"
"Lingo member assignments: $($memberAssignmentRows.Count) -> $MemberAssignmentsOut"
""
"Entity/property usage"
$entityOpRows |
  Group-Object Entity,Field,Operation |
  Sort-Object Count -Descending |
  Select-Object Count,Name |
  Format-Table -AutoSize

""
"Member assignment states"
$memberAssignmentRows |
  Where-Object { $_.StateName } |
  Group-Object ScriptResourceIndex,Handler,StateName |
  Sort-Object Count -Descending |
  Select-Object Count,Name |
  Format-Table -AutoSize

""
"Likely gameplay scripts"
$scriptRows |
  Where-Object { $_.StringConstants -match "G ready|R ready|snowball|GreenWin|Level|mailto|G windup" -or $_.Properties -match "myHits|gd|level" } |
  Format-Table ResourceIndex,LctxId,AssemblyId,Properties,Globals,FunctionsCount,StringConstants -AutoSize
