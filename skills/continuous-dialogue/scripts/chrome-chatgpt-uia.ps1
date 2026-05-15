[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('inspect-window','verify-chatgpt-surface','read-tail','set-input','invoke-button','wait-reply-complete','copy-latest-reply','count-reply-buttons','copy-reply-by-index','send-round')]
    [string]$Action,

    [string]$TitleLike = '*Google Chrome*',
    [string]$UrlHint,
    [string]$TabHint,
    [string]$Text,
    [string]$TextFile,
    [string]$Name,
    [int]$Count = 40,
    [int]$TimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CodexUser32 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
  public const uint KEYUP = 0x0002;
  public const byte VK_CONTROL = 0x11;
  public const byte VK_RETURN = 0x0D;
  public const byte VK_A = 0x41;
  public const byte VK_V = 0x56;
}
'@

function New-UiText {
    param([int[]]$Codes)
    return (-join ($Codes | ForEach-Object { [char]$_ }))
}

$UiInputName = New-UiText @(19982,32,67,104,97,116,71,80,84,32,32842,22825)
$UiSendButton = New-UiText @(21457,36865,25552,31034)
$UiCopyReply = New-UiText @(22797,21046,22238,22797)
$UiReplyOps = New-UiText @(22238,22797,25805,20316)
$UiModelSwitch = New-UiText @(20999,25442,27169,22411)
$UiModelSelector = New-UiText @(27169,22411,36873,25321,22120)
$UiStopStreaming = New-UiText @(20572,27490,27969,24335,20256,36755)
$UiStopResponse = New-UiText @(20572,27490,22238,31572)

function New-Result {
    param([hashtable]$Data)
    $Data | ConvertTo-Json -Depth 8
}

function Get-ChromeCandidates {
    $candidates = Get-Process chrome -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle) }

    if ($TitleLike) {
        $candidates = $candidates | Where-Object { $_.MainWindowTitle -like $TitleLike }
    }

    return @($candidates)
}

function Get-WindowScore {
    param($Process)

    $score = 0
    if ($TitleLike -and $Process.MainWindowTitle -like $TitleLike) { $score += 5 }
    if ($TabHint -and $Process.MainWindowTitle -like "*$TabHint*") { $score += 4 }
    if ($UrlHint -and $Process.MainWindowTitle -like "*$UrlHint*") { $score += 1 }
    return $score
}

function Get-TargetWindow {
    $candidates = @(Get-ChromeCandidates)
    if (-not $candidates -or $candidates.Count -eq 0) {
        throw "No Chrome window matched TitleLike '$TitleLike'."
    }

    $ranked = @($candidates |
        Sort-Object @{Expression = { Get-WindowScore -Process $_ }; Descending = $true }, Id |
        ForEach-Object { $_ })

    foreach ($candidate in $ranked) {
        $candidateWindow = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$candidate.MainWindowHandle)
        $candidateLooksLikeChatGPT = ($candidate.MainWindowTitle -like '*ChatGPT*' -or ($TabHint -and $candidate.MainWindowTitle -like "*$TabHint*"))

        if ($candidateWindow -and -not $candidateLooksLikeChatGPT) {
            Select-ChatGPTTab -Window $candidateWindow -Process $candidate | Out-Null
            $candidateWindow = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$candidate.MainWindowHandle)
            $candidateLooksLikeChatGPT = ($candidate.MainWindowTitle -like '*ChatGPT*' -or ($TabHint -and $candidate.MainWindowTitle -like "*$TabHint*"))
        }

        if ($candidateWindow -and $candidateLooksLikeChatGPT -and (Get-InputElement -Window $candidateWindow)) {
            return [pscustomobject]@{
                Process = $candidate
                Window = $candidateWindow
            }
        }

        if ($candidateWindow -and (Select-ChatGPTTab -Window $candidateWindow -Process $candidate)) {
            $candidateWindow = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$candidate.MainWindowHandle)
            if ($candidateWindow -and (Get-InputElement -Window $candidateWindow)) {
                return [pscustomobject]@{
                    Process = $candidate
                    Window = $candidateWindow
                }
            }
        }
    }

    $best = $ranked | Select-Object -First 1

    $window = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$best.MainWindowHandle)
    if (-not $window) {
        throw "Could not bind to Chrome window handle for '$($best.MainWindowTitle)'."
    }

    return [pscustomobject]@{
        Process = $best
        Window = $window
    }
}

function Get-AllDescendants {
    param($Window)
    ,($Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
}

function Get-UiaPropertyValue {
    param(
        $Element,
        $Property,
        $Default = $null
    )

    try {
        $value = $Element.GetCurrentPropertyValue($Property, $true)
        if ($value -eq [System.Windows.Automation.AutomationElement]::NotSupported) { return $Default }
        if ($null -eq $value) { return $Default }
        return $value
    } catch {
        return $Default
    }
}

function Get-ElementInfo {
    param(
        $Element,
        [int]$Index = -1
    )

    $rect = $Element.Current.BoundingRectangle
    $elementName = Get-UiaPropertyValue -Element $Element -Property ([System.Windows.Automation.AutomationElement]::NameProperty) -Default ''
    $controlType = Get-UiaPropertyValue -Element $Element -Property ([System.Windows.Automation.AutomationElement]::ControlTypeProperty) -Default $null
    $controlTypeName = 'Unknown'
    if ($controlType) {
        try {
            if ($controlType.ProgrammaticName) {
                $controlTypeName = $controlType.ProgrammaticName.Replace('ControlType.','')
            } else {
                $controlTypeName = $controlType.ToString().Replace('ControlType.','')
            }
        } catch {
            $controlTypeName = $controlType.ToString().Replace('ControlType.','')
        }
    }
    function Convert-BoundInt {
        param($Value)
        if ($null -eq $Value) { return 0 }
        $doubleValue = [double]$Value
        if ([double]::IsNaN($doubleValue) -or [double]::IsInfinity($doubleValue)) { return 0 }
        if ($doubleValue -gt [int]::MaxValue) { return [int]::MaxValue }
        if ($doubleValue -lt [int]::MinValue) { return [int]::MinValue }
        [int]$doubleValue
    }
    [pscustomobject]@{
        index = $Index
        name = $elementName
        type = $controlTypeName
        automation_id = Get-UiaPropertyValue -Element $Element -Property ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) -Default ''
        class_name = Get-UiaPropertyValue -Element $Element -Property ([System.Windows.Automation.AutomationElement]::ClassNameProperty) -Default ''
        enabled = Get-UiaPropertyValue -Element $Element -Property ([System.Windows.Automation.AutomationElement]::IsEnabledProperty) -Default $false
        offscreen = Get-UiaPropertyValue -Element $Element -Property ([System.Windows.Automation.AutomationElement]::IsOffscreenProperty) -Default $true
        bounds = @{
            x = Convert-BoundInt $rect.X
            y = Convert-BoundInt $rect.Y
            width = Convert-BoundInt $rect.Width
            height = Convert-BoundInt $rect.Height
        }
    }
}

function Find-ElementsByNameAndType {
    param(
        $Window,
        [string]$ElementName,
        [System.Windows.Automation.ControlType]$ControlType
    )

    $condition = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            $ElementName
        )),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            $ControlType
        ))
    )

    ,($Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))
}

function Find-ElementsByNameAnyType {
    param(
        $Window,
        [string]$ElementName
    )

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        $ElementName
    )
    ,($Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))
}

function Find-ElementsByAutomationId {
    param(
        $Window,
        [string]$AutomationId
    )

    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        $AutomationId
    )
    ,($Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))
}

function Get-InputElement {
    param($Window)
    $edits = Find-ElementsByNameAndType -Window $Window -ElementName $UiInputName -ControlType ([System.Windows.Automation.ControlType]::Edit)
    if ($edits.Count -eq 0) {
        $condition = New-Object System.Windows.Automation.AndCondition(
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
                'prompt-textarea'
            )),
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Edit
            ))
        )
        $edits = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
    }
    if ($edits.Count -eq 0) { return $null }
    $edits.Item(0)
}

function Get-LatestButtonByName {
    param(
        $Window,
        [string]$ButtonName
    )

    $buttons = Find-ElementsByNameAndType -Window $Window -ElementName $ButtonName -ControlType ([System.Windows.Automation.ControlType]::Button)
    if ($buttons.Count -gt 0) { return $buttons.Item($buttons.Count - 1) }

    $named = Find-ElementsByNameAnyType -Window $Window -ElementName $ButtonName
    if ($named.Count -eq 0) { return $null }

    for ($i = $named.Count - 1; $i -ge 0; $i--) {
        $candidate = $named.Item($i)
        try {
            $rect = $candidate.Current.BoundingRectangle
            if ($rect.Width -gt 0 -and $rect.Height -gt 0) { return $candidate }
        } catch {
        }
    }
    $named.Item($named.Count - 1)
}

function Get-ComposerSubmitButton {
    param($Window)

    $submitButtons = Find-ElementsByAutomationId -Window $Window -AutomationId 'composer-submit-button'
    for ($i = $submitButtons.Count - 1; $i -ge 0; $i--) {
        $candidate = $submitButtons.Item($i)
        $name = Get-UiaPropertyValue -Element $candidate -Property ([System.Windows.Automation.AutomationElement]::NameProperty) -Default ''
        if ($name -eq $UiStopStreaming -or $name -eq $UiStopResponse) { continue }
        return $candidate
    }

    $names = @(
        $UiSendButton,
        (New-UiText @(21457,36865,28040,24687)),
        'Send message',
        'Send prompt'
    )
    foreach ($name in $names) {
        $button = Get-LatestButtonByName -Window $Window -ButtonName $name
        if ($button) { return $button }
    }

    $null
}

function Select-ChatGPTTab {
    param(
        $Window,
        $Process
    )

    [CodexUser32]::SetForegroundWindow([IntPtr]$Process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 300

    $tabs = Find-ElementsByNameAndType -Window $Window -ElementName 'ChatGPT' -ControlType ([System.Windows.Automation.ControlType]::TabItem)
    if ($tabs.Count -eq 0) {
        $allTabs = $Window.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem
            ))
        )
        $matches = @()
        for ($i = 0; $i -lt $allTabs.Count; $i++) {
            $tab = $allTabs.Item($i)
            $tabName = Get-UiaPropertyValue -Element $tab -Property ([System.Windows.Automation.AutomationElement]::NameProperty) -Default ''
            if ($tabName -like '*ChatGPT*') { $matches += $tab }
        }
        $tabs = @($matches)
    }
    if ($tabs.Count -eq 0) { return $false }

    if ($tabs -is [System.Array]) {
        $tabToSelect = $tabs[$tabs.Count - 1]
    } else {
        $tabToSelect = $tabs.Item($tabs.Count - 1)
    }
    try {
        $pattern = $null
        if ($tabToSelect.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
            $pattern.Select()
        } else {
            Invoke-ElementNativeClick -Element $tabToSelect | Out-Null
        }
    } catch {
        Invoke-ElementNativeClick -Element $tabToSelect | Out-Null
    }

    Start-Sleep -Seconds 3
    $true
}

function Invoke-Element {
    param($Element)

    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        return 'invoke-pattern'
    }

    $rect = $Element.Current.BoundingRectangle
    Invoke-ElementNativeClick -Element $Element
}

function Invoke-ElementNativeClick {
    param($Element)

    $rect = $Element.Current.BoundingRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) {
        throw "Element has empty bounds and cannot be clicked."
    }

    $x = [int]($rect.X + ($rect.Width / 2))
    $y = [int]($rect.Y + ($rect.Height / 2))
    [CodexUser32]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 120
    [CodexUser32]::mouse_event([CodexUser32]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [CodexUser32]::mouse_event([CodexUser32]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    'native-click'
}

function Invoke-InputKeyboardSend {
    param($InputElement)
    try {
        $InputElement.SetFocus()
        Start-Sleep -Milliseconds 200
    } catch {
    }
    try {
        [System.Windows.Forms.SendKeys]::SendWait('^{ENTER}')
    } catch {
        [CodexUser32]::keybd_event([CodexUser32]::VK_CONTROL, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        [CodexUser32]::keybd_event([CodexUser32]::VK_RETURN, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
        [CodexUser32]::keybd_event([CodexUser32]::VK_RETURN, 0, [CodexUser32]::KEYUP, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        [CodexUser32]::keybd_event([CodexUser32]::VK_CONTROL, 0, [CodexUser32]::KEYUP, [UIntPtr]::Zero)
        Start-Sleep -Seconds 1
        return 'native-keyboard-ctrl-enter'
    }
    Start-Sleep -Seconds 1
    'keyboard-ctrl-enter'
}

function Invoke-NativeKeyChord {
    param(
        [byte]$Key,
        [string]$ModeName
    )
    [CodexUser32]::keybd_event([CodexUser32]::VK_CONTROL, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [CodexUser32]::keybd_event($Key, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 70
    [CodexUser32]::keybd_event($Key, 0, [CodexUser32]::KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [CodexUser32]::keybd_event([CodexUser32]::VK_CONTROL, 0, [CodexUser32]::KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    $ModeName
}

function Set-ClipboardText {
    param([string]$Value)
    $lastError = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        try {
            Set-Clipboard -Value $Value -ErrorAction Stop
            return ('set-clipboard-attempt-{0}' -f $attempt)
        } catch {
            $lastError = $_.Exception.Message
        }

        try {
            [System.Windows.Forms.Clipboard]::Clear()
            [System.Windows.Forms.Clipboard]::SetText($Value)
            return ('forms-clipboard-attempt-{0}' -f $attempt)
        } catch {
            $lastError = $_.Exception.Message
        }

        Start-Sleep -Milliseconds (150 * $attempt)
    }
    throw "Could not set clipboard text for browser paste after retries: $lastError"
}

function Invoke-InputClipboardPaste {
    param(
        $InputElement,
        [string]$Value
    )

    try {
        $InputElement.SetFocus()
        Start-Sleep -Milliseconds 250
    } catch {
    }
    try {
        Invoke-ElementNativeClick -Element $InputElement | Out-Null
        Start-Sleep -Milliseconds 250
    } catch {
    }

    try {
        $pattern = $InputElement.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $pattern.SetValue($Value)
        Start-Sleep -Milliseconds 350
        $afterSet = Get-InputValue -InputElement $InputElement
        if (Test-InputLooksLikeText -InputValue $afterSet -ExpectedText $Value) {
            return 'value-pattern'
        }
    } catch {
    }

    $clipboardMode = Set-ClipboardText -Value $Value
    Invoke-NativeKeyChord -Key ([CodexUser32]::VK_A) -ModeName 'native-keyboard-ctrl-a' | Out-Null
    Invoke-NativeKeyChord -Key ([CodexUser32]::VK_V) -ModeName 'native-keyboard-ctrl-v' | Out-Null
    Start-Sleep -Seconds 1
    "clipboard-paste:$clipboardMode"
}

function Test-InputLooksLikeText {
    param(
        [string]$InputValue,
        [string]$ExpectedText
    )
    if ([string]::IsNullOrWhiteSpace($InputValue) -or [string]::IsNullOrWhiteSpace($ExpectedText)) {
        return $false
    }
    $inputNorm = ($InputValue -replace "`r`n", "`n").Trim()
    $expectedNorm = ($ExpectedText -replace "`r`n", "`n").Trim()
    if ($inputNorm -eq $expectedNorm) { return $true }
    $prefixLen = [Math]::Min(160, $expectedNorm.Length)
    if ($prefixLen -le 0) { return $false }
    $prefix = $expectedNorm.Substring(0, $prefixLen)
    return ($inputNorm.Contains($prefix) -and $inputNorm.Length -ge [Math]::Min(200, [int]($expectedNorm.Length * 0.65)))
}

function Get-Tail {
    param(
        $Window,
        [int]$TailCount
    )

    $all = Get-AllDescendants -Window $Window
    $tail = New-Object System.Collections.Generic.List[object]
    for ($i = [Math]::Max(0, $all.Count - $TailCount); $i -lt $all.Count; $i++) {
        $element = $all.Item($i)
        $elementName = Get-UiaPropertyValue -Element $element -Property ([System.Windows.Automation.AutomationElement]::NameProperty) -Default ''
        if ([string]::IsNullOrWhiteSpace($elementName)) { continue }
        $tail.Add((Get-ElementInfo -Element $element -Index $i))
    }
    $tail
}

function Get-TailText {
    param(
        [System.Collections.Generic.List[object]]$Tail
    )

    ($Tail | ForEach-Object { "[{0}] {1} | {2}" -f $_.index, $_.type, $_.name }) -join "`n"
}

function Get-LatestReplyTextFromTail {
    param($Window)

    $tail = Get-Tail -Window $Window -TailCount 220
    $lastReplyOpsPos = -1
    for ($pos = $tail.Count - 1; $pos -ge 0; $pos--) {
        $entry = $tail[$pos]
        if ($entry.type -eq 'Group' -and $entry.name -eq (New-UiText @(22238,22797,25805,20316))) {
            $lastReplyOpsPos = $pos
            break
        }
    }

    if ($lastReplyOpsPos -lt 1) { return '' }

    $collected = New-Object System.Collections.Generic.List[string]
    for ($pos = $lastReplyOpsPos - 1; $pos -ge 0; $pos--) {
        $entry = $tail[$pos]

        if ($entry.type -eq 'Group' -or $entry.type -eq 'Edit') {
            if ($collected.Count -gt 0) { break }
            continue
        }

        if ($entry.type -eq 'Button') {
            if ($collected.Count -gt 0) { break }
            continue
        }

        if ($entry.type -in @('Text','Hyperlink','ListItem')) {
            if (-not [string]::IsNullOrWhiteSpace($entry.name)) {
                $collected.Add($entry.name)
            }
            continue
        }

        if ($collected.Count -gt 0) { break }
    }

    if ($collected.Count -eq 0) { return '' }

    $orderedSource = @($collected)
    [array]::Reverse($orderedSource)
    $ordered = [System.Collections.Generic.List[string]]::new()
    $last = $null
    foreach ($item in $orderedSource) {
        if ($item -ne $last) {
            $ordered.Add($item)
            $last = $item
        }
    }

    ($ordered -join "`n").Trim()
}

function Test-ChatGPTSurface {
    param($Window)

    $tail = Get-Tail -Window $Window -TailCount 120
    $tailText = Get-TailText -Tail $tail
    $input = Get-InputElement -Window $Window
    $send = Get-ComposerSubmitButton -Window $Window
    $copy = Get-LatestButtonByName -Window $Window -ButtonName $UiCopyReply
    $modelSwitch = Get-LatestButtonByName -Window $Window -ButtonName $UiModelSwitch
    if (-not $modelSwitch) {
        $modelSwitch = Get-LatestButtonByName -Window $Window -ButtonName $UiModelSelector
    }

    [pscustomobject]@{
        input_found = [bool]$input
        send_found = [bool]$send
        copy_found = [bool]$copy
        model_switch_found = [bool]$modelSwitch
        surface_ok = [bool]($input -and $send)
        tail_preview = $tailText
    }
}

function Get-ClipboardText {
    try {
        $clip = Get-Clipboard -Raw -ErrorAction Stop
        if ($null -ne $clip) { return [string]$clip }
    } catch {
    }

    try {
        [Windows.Clipboard]::GetText()
    } catch {
        ''
    }
}

function Get-InputValue {
    param($InputElement)
    $pattern = $InputElement.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $pattern.Current.Value
}

function Wait-ReplyComplete {
    param(
        $Window,
        [int]$Seconds,
        [int]$MinCopyReplyCount = 1
    )

    $seenStreaming = $false
    $deadline = (Get-Date).AddSeconds($Seconds)
    $lastTail = ''
    $stableTicks = 0

    do {
        $tail = Get-Tail -Window $Window -TailCount 120
        $tailText = Get-TailText -Tail $tail
        if ($tailText -eq $lastTail) {
            $stableTicks += 1
        } else {
            $stableTicks = 0
            $lastTail = $tailText
        }
        $hasStop = ($tailText -match [regex]::Escape($UiStopStreaming)) -or ($tailText -match [regex]::Escape($UiStopResponse))
        $replyOpsCount = (Find-ElementsByNameAnyType -Window $Window -ElementName $UiReplyOps).Count
        $copyCount = (Find-ElementsByNameAndType -Window $Window -ElementName $UiCopyReply -ControlType ([System.Windows.Automation.ControlType]::Button)).Count
        $copyAnyCount = (Find-ElementsByNameAnyType -Window $Window -ElementName $UiCopyReply).Count
        $hasNewReply = $replyOpsCount -ge $MinCopyReplyCount
        $hasAnyCopy = (($copyCount -gt 0) -or ($copyAnyCount -gt 0) -or ($tailText -match [regex]::Escape($UiCopyReply)))
        $hasCopy = $hasNewReply -and $hasAnyCopy
        if ($hasStop) { $seenStreaming = $true }

        if ($seenStreaming -and -not $hasStop -and ($hasCopy -or $stableTicks -ge 3)) {
            return [pscustomobject]@{
                completed = $true
                seen_streaming = $seenStreaming
                tail_text = $lastTail
            }
        }

        if (-not $seenStreaming -and -not $hasStop -and $hasNewReply -and ($hasCopy -or $stableTicks -ge 3)) {
            return [pscustomobject]@{
                completed = $true
                seen_streaming = $seenStreaming
                tail_text = $lastTail
            }
        }

        if (-not $hasStop -and $hasAnyCopy -and $stableTicks -ge 5) {
            return [pscustomobject]@{
                completed = $true
                seen_streaming = $seenStreaming
                relaxed_completion = $true
                tail_text = $lastTail
            }
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    [pscustomobject]@{
        completed = $false
        seen_streaming = $seenStreaming
        tail_text = $lastTail
    }
}

$target = Get-TargetWindow
$window = $target.Window
$process = $target.Process
[CodexUser32]::SetForegroundWindow([IntPtr]$process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 300

if ($TextFile) {
    $Text = [System.IO.File]::ReadAllText($TextFile, [System.Text.Encoding]::UTF8)
}

switch ($Action) {
    'inspect-window' {
        $tail = Get-Tail -Window $window -TailCount $Count
        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            selection_notes = @{
                title_like = $TitleLike
                tab_hint = $TabHint
                url_hint = $UrlHint
            }
            surface = Test-ChatGPTSurface -Window $window
            tail = $tail
        }
        break
    }

    'verify-chatgpt-surface' {
        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            verification = Test-ChatGPTSurface -Window $window
        }
        break
    }

    'read-tail' {
        $tail = Get-Tail -Window $window -TailCount $Count
        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            tail = $tail
            tail_text = Get-TailText -Tail $tail
        }
        break
    }

    'set-input' {
        if ([string]::IsNullOrEmpty($Text)) {
            throw "Action 'set-input' requires -Text."
        }

        $input = Get-InputElement -Window $window
        if (-not $input) {
            throw "Could not find the ChatGPT input box."
        }

        $pattern = $input.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $before = $pattern.Current.Value
        $pattern.SetValue($Text)
        Start-Sleep -Milliseconds 200
        $after = $pattern.Current.Value

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            before = $before
            after = $after
            input = Get-ElementInfo -Element $input
        }
        break
    }

    'invoke-button' {
        if ([string]::IsNullOrEmpty($Name)) {
            throw "Action 'invoke-button' requires -Name."
        }

        $button = Get-LatestButtonByName -Window $window -ButtonName $Name
        if (-not $button) {
            throw "Could not find button '$Name'."
        }

        $mode = Invoke-Element -Element $button
        Start-Sleep -Milliseconds 500

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            button = Get-ElementInfo -Element $button
            invoke_mode = $mode
        }
        break
    }

    'wait-reply-complete' {
        $result = Wait-ReplyComplete -Window $window -Seconds $TimeoutSec
        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            completed = $result.completed
            seen_streaming = $result.seen_streaming
            tail_text = $result.tail_text
        }
        break
    }

    'copy-latest-reply' {
        $button = Get-LatestButtonByName -Window $window -ButtonName $UiCopyReply
        if (-not $button) {
            throw "Could not find the latest copy-reply button."
        }

        $before = Get-ClipboardText
        $mode = Invoke-Element -Element $button
        Start-Sleep -Milliseconds 700
        $after = Get-ClipboardText
        $fallbackMode = $null

        if ([string]::IsNullOrWhiteSpace($after) -or $before -eq $after) {
            $fallbackMode = Invoke-ElementNativeClick -Element $button
            Start-Sleep -Milliseconds 900
            $after = Get-ClipboardText
        }

        $source = 'clipboard'
        if ([string]::IsNullOrWhiteSpace($after) -or $before -eq $after) {
            $tailReply = Get-LatestReplyTextFromTail -Window $window
            if (-not [string]::IsNullOrWhiteSpace($tailReply)) {
                $after = $tailReply
                $source = 'uia-tail-extract'
            } else {
                $after = ''
                $source = 'unavailable'
            }
        }

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            invoke_mode = $mode
            fallback_mode = $fallbackMode
            source = $source
            clipboard_changed = ($before -ne $after)
            clipboard_text = $after
        }
        break
    }

    'count-reply-buttons' {
        $buttons = Find-ElementsByNameAndType -Window $window -ElementName $UiCopyReply -ControlType ([System.Windows.Automation.ControlType]::Button)
        $items = @()
        for ($i = 0; $i -lt $buttons.Count; $i++) {
            $items += [pscustomobject]@{
                index = $i + 1
                element = Get-ElementInfo -Element $buttons.Item($i)
            }
        }

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            count = $buttons.Count
            buttons = $items
        }
        break
    }

    'copy-reply-by-index' {
        if ($Count -lt 1) {
            throw "Action 'copy-reply-by-index' requires -Count as a 1-based reply index."
        }

        $buttons = Find-ElementsByNameAndType -Window $window -ElementName $UiCopyReply -ControlType ([System.Windows.Automation.ControlType]::Button)
        if ($buttons.Count -lt $Count) {
            throw "Could not find copy-reply button index $Count. Found $($buttons.Count)."
        }

        $button = $buttons.Item($Count - 1)
        $before = Get-ClipboardText
        $mode = Invoke-Element -Element $button
        Start-Sleep -Milliseconds 700
        $after = Get-ClipboardText
        $fallbackMode = $null

        if ([string]::IsNullOrWhiteSpace($after) -or $before -eq $after) {
            $fallbackMode = Invoke-ElementNativeClick -Element $button
            Start-Sleep -Milliseconds 900
            $after = Get-ClipboardText
        }

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            index = $Count
            total = $buttons.Count
            invoke_mode = $mode
            fallback_mode = $fallbackMode
            clipboard_changed = ($before -ne $after)
            clipboard_text = $after
        }
        break
    }

    'send-round' {
        if ([string]::IsNullOrEmpty($Text)) {
            throw "Action 'send-round' requires -Text."
        }

        $preTailText = Get-TailText -Tail (Get-Tail -Window $window -TailCount 120)
        if (($preTailText -match [regex]::Escape($UiStopStreaming)) -or ($preTailText -match [regex]::Escape($UiStopResponse))) {
            Wait-ReplyComplete -Window $window -Seconds ([Math]::Min($TimeoutSec, 300)) | Out-Null
            $window = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$process.MainWindowHandle)
        }

        $input = Get-InputElement -Window $window
        if (-not $input) {
            throw "Could not find the ChatGPT input box."
        }

        $replyOpsCountBefore = (Find-ElementsByNameAnyType -Window $window -ElementName $UiReplyOps).Count
        $inputMode = Invoke-InputClipboardPaste -InputElement $input -Value $Text
        $inputAfterPaste = Get-InputValue -InputElement $input
        $pasteSucceeded = Test-InputLooksLikeText -InputValue $inputAfterPaste -ExpectedText $Text
        if (-not $pasteSucceeded) {
            New-Result @{
                action = $Action
                matched_title = $process.MainWindowTitle
                process_id = $process.Id
                input_mode = $inputMode
                send_mode = $null
                fallback_mode = $null
                message_sent = $false
                input_after_paste = $inputAfterPaste
                input_after_send = $inputAfterPaste
                wait_result = $null
                error = 'input paste did not populate the ChatGPT composer'
            }
            break
        }

        $send = Get-ComposerSubmitButton -Window $window
        if (-not $send) {
            $sendMode = Invoke-InputKeyboardSend -InputElement $input
            Start-Sleep -Seconds 1
            $inputAfterSend = Get-InputValue -InputElement $input
            if (Test-InputLooksLikeText -InputValue $inputAfterSend -ExpectedText $Text) {
                try {
                    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                    $fallbackMode = 'keyboard-enter'
                } catch {
                    [CodexUser32]::keybd_event([CodexUser32]::VK_RETURN, 0, 0, [UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 60
                    [CodexUser32]::keybd_event([CodexUser32]::VK_RETURN, 0, [CodexUser32]::KEYUP, [UIntPtr]::Zero)
                    $fallbackMode = 'native-keyboard-enter'
                }
                Start-Sleep -Seconds 1
                $inputAfterSend = Get-InputValue -InputElement $input
            } else {
                $fallbackMode = $null
            }
        } else {
            $sendMode = Invoke-Element -Element $send
            Start-Sleep -Seconds 1
            $inputAfterSend = Get-InputValue -InputElement $input
            $fallbackMode = $null

            if (Test-InputLooksLikeText -InputValue $inputAfterSend -ExpectedText $Text) {
                $fallbackMode = Invoke-ElementNativeClick -Element $send
                Start-Sleep -Seconds 1
                $inputAfterSend = Get-InputValue -InputElement $input
            }
        }

        $messageSent = (-not (Test-InputLooksLikeText -InputValue $inputAfterSend -ExpectedText $Text))
        $waitResult = $null
        if ($messageSent) {
            $waitResult = Wait-ReplyComplete -Window $window -Seconds $TimeoutSec -MinCopyReplyCount ($replyOpsCountBefore + 1)
        }

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            input_mode = $inputMode
            send_mode = $sendMode
            fallback_mode = $fallbackMode
            message_sent = $messageSent
            input_after_paste = $inputAfterPaste
            input_after_send = $inputAfterSend
            wait_result = $waitResult
        }
        break
    }
}
