[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('inspect-window','verify-chatgpt-surface','read-tail','set-input','invoke-button','wait-reply-complete','copy-latest-reply','send-round')]
    [string]$Action,

    [string]$TitleLike = '*Google Chrome*',
    [string]$UrlHint,
    [string]$TabHint,
    [string]$Text,
    [string]$Name,
    [int]$Count = 40,
    [int]$TimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName PresentationCore
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CodexUser32 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  public const uint LEFTDOWN = 0x0002;
  public const uint LEFTUP = 0x0004;
}
'@

function New-UiText {
    param([int[]]$Codes)
    return (-join ($Codes | ForEach-Object { [char]$_ }))
}

$UiInputName = New-UiText @(19982,32,67,104,97,116,71,80,84,32,32842,22825)
$UiSendButton = New-UiText @(21457,36865,25552,31034)
$UiCopyReply = New-UiText @(22797,21046,22238,22797)
$UiModelSwitch = New-UiText @(20999,25442,27169,22411)
$UiModelSelector = New-UiText @(27169,22411,36873,25321,22120)
$UiStopStreaming = New-UiText @(20572,27490,27969,24335,20256,36755)

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

    $best = $candidates |
        Sort-Object @{Expression = { Get-WindowScore -Process $_ }; Descending = $true }, Id |
        Select-Object -First 1

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

function Get-ElementInfo {
    param(
        $Element,
        [int]$Index = -1
    )

    $rect = $Element.Current.BoundingRectangle
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
        name = $Element.Current.Name
        type = if ($Element.Current.ControlType -and $Element.Current.ControlType.ProgrammaticName) { $Element.Current.ControlType.ProgrammaticName.Replace('ControlType.','') } else { 'Unknown' }
        automation_id = $Element.Current.AutomationId
        class_name = $Element.Current.ClassName
        enabled = $Element.Current.IsEnabled
        offscreen = $Element.Current.IsOffscreen
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
    if ($buttons.Count -eq 0) { return $null }
    $buttons.Item($buttons.Count - 1)
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

function Get-Tail {
    param(
        $Window,
        [int]$TailCount
    )

    $all = Get-AllDescendants -Window $Window
    $tail = New-Object System.Collections.Generic.List[object]
    for ($i = [Math]::Max(0, $all.Count - $TailCount); $i -lt $all.Count; $i++) {
        $element = $all.Item($i)
        if ([string]::IsNullOrWhiteSpace($element.Current.Name)) { continue }
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
    $send = Get-LatestButtonByName -Window $Window -ButtonName $UiSendButton
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
        [int]$Seconds
    )

    $seenStreaming = $false
    $deadline = (Get-Date).AddSeconds($Seconds)
    $lastTail = ''

    do {
        $tail = Get-Tail -Window $Window -TailCount 120
        $tailText = Get-TailText -Tail $tail
        $lastTail = $tailText
        $hasStop = $tailText -match [regex]::Escape($UiStopStreaming)
        $hasCopy = $tailText -match [regex]::Escape($UiCopyReply)
        if ($hasStop) { $seenStreaming = $true }

        if ($seenStreaming -and -not $hasStop -and $hasCopy) {
            return [pscustomobject]@{
                completed = $true
                seen_streaming = $seenStreaming
                tail_text = $lastTail
            }
        }

        if (-not $seenStreaming -and -not $hasStop -and $hasCopy) {
            return [pscustomobject]@{
                completed = $true
                seen_streaming = $seenStreaming
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
        if ([string]::IsNullOrWhiteSpace($after)) {
            $after = Get-LatestReplyTextFromTail -Window $window
            if (-not [string]::IsNullOrWhiteSpace($after)) {
                $source = 'uia-tail-extract'
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

    'send-round' {
        if ([string]::IsNullOrEmpty($Text)) {
            throw "Action 'send-round' requires -Text."
        }

        $input = Get-InputElement -Window $window
        if (-not $input) {
            throw "Could not find the ChatGPT input box."
        }

        $inputPattern = $input.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $inputPattern.SetValue($Text)
        Start-Sleep -Milliseconds 250

        $send = Get-LatestButtonByName -Window $window -ButtonName $UiSendButton
        if (-not $send) {
            throw "Could not find the latest send button."
        }

        $sendMode = Invoke-Element -Element $send
        Start-Sleep -Seconds 1
        $inputAfterSend = Get-InputValue -InputElement $input
        $fallbackMode = $null

        if ($inputAfterSend -eq $Text) {
            $fallbackMode = Invoke-ElementNativeClick -Element $send
            Start-Sleep -Seconds 1
            $inputAfterSend = Get-InputValue -InputElement $input
        }

        $messageSent = ($inputAfterSend -ne $Text)
        $waitResult = $null
        if ($messageSent) {
            $waitResult = Wait-ReplyComplete -Window $window -Seconds $TimeoutSec
        }

        New-Result @{
            action = $Action
            matched_title = $process.MainWindowTitle
            process_id = $process.Id
            send_mode = $sendMode
            fallback_mode = $fallbackMode
            message_sent = $messageSent
            input_after_send = $inputAfterSend
            wait_result = $waitResult
        }
        break
    }
}
