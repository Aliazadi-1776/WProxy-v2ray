param([switch]$Show)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace WProxy {
    public static class NativeTheme {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(
            IntPtr window, int attribute, ref int value, int size);
    }
}
'@
} catch { }

$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$global:OutputEncoding = $utf8
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$script:Root = Split-Path -Parent $PSScriptRoot
$script:CtlExe = Join-Path $script:Root 'wproxyctl.exe'
$script:CtlPy = Join-Path $script:Root 'cli\wproxyctl.py'
$script:UseExe = Test-Path $script:CtlExe
if (-not $script:UseExe) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $pythonCommand) { $pythonCommand = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $pythonCommand) {
        [System.Windows.Forms.MessageBox]::Show('The WProxy command engine is missing. Reinstall with WProxy Setup.', 'WProxy') | Out-Null
        exit 2
    }
    $script:Python = $pythonCommand.Source
}
$script:RoutingLoading = $false
$script:Exiting = $false
$script:ActiveNodeId = $null

function Invoke-Ctl([string[]]$Arguments) {
    # Windows PowerShell promotes native stderr to ErrorRecord. With the
    # script-wide Stop preference, a recoverable engine error used to close
    # the entire manager. Capture it as operation output instead.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($script:UseExe) { $lines = @(& $script:CtlExe @Arguments 2>&1) }
        else { $lines = @(& $script:Python $script:CtlPy @Arguments 2>&1) }
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        $text = @($lines | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message }
            else { [string]$_ }
        }) -join [Environment]::NewLine
        return [pscustomobject]@{ Code = $code; Output = $text.Trim() }
    } catch {
        return [pscustomobject]@{ Code = 1; Output = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Show-Error([string]$Message) {
    if (-not $Message) { $Message = 'The operation failed.' }
    [System.Windows.Forms.MessageBox]::Show($Message, 'WProxy', 'OK', 'Error') | Out-Null
}

function Invoke-AdminCtl([string[]]$Arguments) {
    try {
        if ($script:UseExe) {
            $process = Start-Process -FilePath $script:CtlExe -ArgumentList $Arguments -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        } else {
            $quotedCtl = '"' + $script:CtlPy + '"'
            $process = Start-Process -FilePath $script:Python -ArgumentList (@($quotedCtl) + $Arguments) -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        }
        if ($process.ExitCode -ne 0) {
            $errorFile = Join-Path $env:LOCALAPPDATA 'WProxy\run\last-error.txt'
            if (Test-Path $errorFile) { Show-Error (Get-Content $errorFile -Raw) }
            else { Show-Error 'The elevated WProxy operation failed.' }
        }
        return $process.ExitCode
    } catch {
        Show-Error $_.Exception.Message
        return 1
    }
}

$script:Ui = @{
    Canvas = [System.Drawing.Color]::FromArgb(11, 18, 32)
    Sidebar = [System.Drawing.Color]::FromArgb(15, 25, 43)
    Surface = [System.Drawing.Color]::FromArgb(17, 27, 46)
    Raised = [System.Drawing.Color]::FromArgb(24, 36, 58)
    Border = [System.Drawing.Color]::FromArgb(45, 59, 82)
    Accent = [System.Drawing.Color]::FromArgb(45, 212, 191)
    AccentHover = [System.Drawing.Color]::FromArgb(94, 234, 212)
    Blue = [System.Drawing.Color]::FromArgb(96, 165, 250)
    Text = [System.Drawing.Color]::FromArgb(248, 250, 252)
    Muted = [System.Drawing.Color]::FromArgb(148, 163, 184)
    Danger = [System.Drawing.Color]::FromArgb(248, 113, 113)
    DangerSurface = [System.Drawing.Color]::FromArgb(69, 31, 40)
}
$script:Brushes = @{
    Canvas = New-Object System.Drawing.SolidBrush($script:Ui.Canvas)
    Surface = New-Object System.Drawing.SolidBrush($script:Ui.Surface)
    Raised = New-Object System.Drawing.SolidBrush($script:Ui.Raised)
    Accent = New-Object System.Drawing.SolidBrush($script:Ui.Accent)
}
$script:BodyFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$script:StrongFont = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)
$script:TitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)
$script:PageTitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
$script:CaptionFont = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)

function Set-ActionButton {
    param(
        [System.Windows.Forms.Button]$Button,
        [ValidateSet('Primary', 'Secondary', 'Danger', 'Navigation')][string]$Kind = 'Secondary'
    )
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 1
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Font = $script:StrongFont
    $Button.Height = 36
    $Button.AutoSize = $false
    $Button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    switch ($Kind) {
        'Primary' {
            $Button.BackColor = $script:Ui.Accent
            $Button.ForeColor = $script:Ui.Canvas
            $Button.FlatAppearance.BorderColor = $script:Ui.Accent
            $Button.FlatAppearance.MouseOverBackColor = $script:Ui.AccentHover
        }
        'Danger' {
            $Button.BackColor = $script:Ui.DangerSurface
            $Button.ForeColor = $script:Ui.Danger
            $Button.FlatAppearance.BorderColor = $script:Ui.DangerSurface
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(88, 39, 48)
        }
        'Navigation' {
            $Button.BackColor = $script:Ui.Sidebar
            $Button.ForeColor = $script:Ui.Muted
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = $script:Ui.Raised
            $Button.TextAlign = 'MiddleLeft'
            $Button.Padding = New-Object System.Windows.Forms.Padding(16, 0, 8, 0)
        }
        default {
            $Button.BackColor = $script:Ui.Raised
            $Button.ForeColor = $script:Ui.Text
            $Button.FlatAppearance.BorderColor = $script:Ui.Border
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(34, 49, 73)
        }
    }
}

function Set-InputStyle([System.Windows.Forms.Control]$Control) {
    $Control.BackColor = $script:Ui.Canvas
    $Control.ForeColor = $script:Ui.Text
    $Control.Font = $script:BodyFont
}

function Enable-DarkTitleBar([System.Windows.Forms.Form]$Window) {
    if (-not ('WProxy.NativeTheme' -as [type])) { return }
    try {
        $enabled = 1
        $result = [WProxy.NativeTheme]::DwmSetWindowAttribute($Window.Handle, 20, [ref]$enabled, 4)
        if ($result -ne 0) {
            [void][WProxy.NativeTheme]::DwmSetWindowAttribute($Window.Handle, 19, [ref]$enabled, 4)
        }
    } catch { }
}

function Set-ListStyle([System.Windows.Forms.ListView]$List) {
    $List.BackColor = $script:Ui.Surface
    $List.ForeColor = $script:Ui.Text
    $List.BorderStyle = 'FixedSingle'
    $List.Font = $script:BodyFont
    $List.HideSelection = $false
    $List.OwnerDraw = $true
    $List.Add_DrawColumnHeader({
        param($sender, $eventArgs)
        $eventArgs.Graphics.FillRectangle($script:Brushes.Raised, $eventArgs.Bounds)
        [System.Windows.Forms.TextRenderer]::DrawText(
            $eventArgs.Graphics, $eventArgs.Header.Text, $script:StrongFont, $eventArgs.Bounds,
            $script:Ui.Muted, [System.Windows.Forms.TextFormatFlags]::Left -bor
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    })
    $List.Add_DrawItem({
        param($sender, $eventArgs)
        if ($sender.View -ne [System.Windows.Forms.View]::Details) { $eventArgs.DrawDefault = $true }
    })
    $List.Add_DrawSubItem({
        param($sender, $eventArgs)
        $selected = (($eventArgs.ItemState -band [System.Windows.Forms.ListViewItemStates]::Selected) -ne 0)
        $active = ($script:ActiveNodeId -and ([string]$eventArgs.Item.Tag -eq [string]$script:ActiveNodeId))
        $back = if ($selected) { $script:Ui.Raised } else { $script:Ui.Surface }
        $fore = if ($selected -or $active) { $script:Ui.AccentHover } else { $script:Ui.Text }
        $backBrush = if ($selected) { $script:Brushes.Raised } else { $script:Brushes.Surface }
        $eventArgs.Graphics.FillRectangle($backBrush, $eventArgs.Bounds)
        $bounds = New-Object System.Drawing.Rectangle(
            ($eventArgs.Bounds.X + 8), $eventArgs.Bounds.Y,
            ([Math]::Max(0, $eventArgs.Bounds.Width - 12)), $eventArgs.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText(
            $eventArgs.Graphics, $eventArgs.SubItem.Text, $sender.Font, $bounds, $fore,
            [System.Windows.Forms.TextFormatFlags]::Left -bor
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    })
}

function New-PageHeader([string]$Title, [string]$Subtitle) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Fill'
    $panel.BackColor = $script:Ui.Canvas
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Font = $script:PageTitleFont
    $titleLabel.ForeColor = $script:Ui.Text
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(0, 2)
    $panel.Controls.Add($titleLabel)
    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Text = $Subtitle
    $subtitleLabel.Font = $script:CaptionFont
    $subtitleLabel.ForeColor = $script:Ui.Muted
    $subtitleLabel.AutoSize = $true
    $subtitleLabel.Location = New-Object System.Drawing.Point(2, 34)
    $panel.Controls.Add($subtitleLabel)
    return $panel
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'WProxy 2.5.0'
$form.Size = New-Object System.Drawing.Size(980, 700)
$form.MinimumSize = New-Object System.Drawing.Size(820, 580)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:Ui.Canvas
$form.ForeColor = $script:Ui.Text
$form.Font = $script:BodyFont
$form.AutoScaleMode = 'Dpi'
$form.KeyPreview = $true
$iconPath = Join-Path $script:Root 'icons\wproxy.ico'
if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
$form.Add_HandleCreated({ Enable-DarkTitleBar $form })

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 94
$header.BackColor = $script:Ui.Canvas
$header.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 12)

$brandMark = New-Object System.Windows.Forms.Label
$brandMark.Text = 'W'
$brandMark.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold)
$brandMark.TextAlign = 'MiddleCenter'
$brandMark.BackColor = $script:Ui.Accent
$brandMark.ForeColor = $script:Ui.Canvas
$brandMark.Size = New-Object System.Drawing.Size(52, 52)
$brandMark.Location = New-Object System.Drawing.Point(22, 18)
$header.Controls.Add($brandMark)

$brandTitle = New-Object System.Windows.Forms.Label
$brandTitle.Text = 'WProxy'
$brandTitle.Font = $script:TitleFont
$brandTitle.ForeColor = $script:Ui.Text
$brandTitle.AutoSize = $true
$brandTitle.Location = New-Object System.Drawing.Point(88, 13)
$header.Controls.Add($brandTitle)
$brandSubtitle = New-Object System.Windows.Forms.Label
$brandSubtitle.Text = 'Servers, subscriptions and split routing in one place'
$brandSubtitle.Font = $script:CaptionFont
$brandSubtitle.ForeColor = $script:Ui.Muted
$brandSubtitle.AutoSize = $true
$brandSubtitle.Location = New-Object System.Drawing.Point(91, 51)
$header.Controls.Add($brandSubtitle)

$connectionCard = New-Object System.Windows.Forms.Panel
$connectionCard.Size = New-Object System.Drawing.Size(292, 54)
$connectionCard.Anchor = 'Top,Right'
$connectionCard.Location = New-Object System.Drawing.Point(658, 18)
$connectionCard.BackColor = $script:Ui.Raised
$connectionDot = New-Object System.Windows.Forms.Label
$connectionDot.Text = [char]0x25CF
$connectionDot.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Regular)
$connectionDot.ForeColor = $script:Ui.Muted
$connectionDot.AutoSize = $true
$connectionDot.Location = New-Object System.Drawing.Point(15, 15)
$connectionCard.Controls.Add($connectionDot)
$connectionState = New-Object System.Windows.Forms.Label
$connectionState.Text = 'Disconnected'
$connectionState.Font = $script:StrongFont
$connectionState.ForeColor = $script:Ui.Text
$connectionState.AutoEllipsis = $true
$connectionState.Size = New-Object System.Drawing.Size(235, 22)
$connectionState.Location = New-Object System.Drawing.Point(42, 9)
$connectionCard.Controls.Add($connectionState)
$connectionDetail = New-Object System.Windows.Forms.Label
$connectionDetail.Text = 'Select a server to start the tunnel'
$connectionDetail.Font = $script:CaptionFont
$connectionDetail.ForeColor = $script:Ui.Muted
$connectionDetail.AutoEllipsis = $true
$connectionDetail.Size = New-Object System.Drawing.Size(235, 18)
$connectionDetail.Location = New-Object System.Drawing.Point(42, 30)
$connectionCard.Controls.Add($connectionDetail)
$header.Controls.Add($connectionCard)
$header.Add_Resize({
    $connectionCard.Left = [Math]::Max(500, $header.ClientSize.Width - $connectionCard.Width - 24)
})

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Font = $script:StrongFont
$tabs.DrawMode = 'OwnerDrawFixed'
$tabs.SizeMode = 'Fixed'
$tabs.ItemSize = New-Object System.Drawing.Size(180, 42)
$tabs.Padding = New-Object System.Drawing.Point(20, 6)
$tabs.BackColor = $script:Ui.Canvas
$tabs.Add_DrawItem({
    param($sender, $eventArgs)
    $selected = ($eventArgs.Index -eq $sender.SelectedIndex)
    $bounds = $eventArgs.Bounds
    $back = if ($selected) { $script:Ui.Raised } else { $script:Ui.Canvas }
    $fore = if ($selected) { $script:Ui.AccentHover } else { $script:Ui.Muted }
    $backBrush = if ($selected) { $script:Brushes.Raised } else { $script:Brushes.Canvas }
    $eventArgs.Graphics.FillRectangle($backBrush, $bounds)
    if ($selected) {
        $accentBounds = New-Object System.Drawing.Rectangle($bounds.X, ($bounds.Bottom - 3), $bounds.Width, 3)
        $eventArgs.Graphics.FillRectangle($script:Brushes.Accent, $accentBounds)
    }
    [System.Windows.Forms.TextRenderer]::DrawText(
        $eventArgs.Graphics, $sender.TabPages[$eventArgs.Index].Text, $script:StrongFont,
        $bounds, $fore, [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
        [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
})
$form.Controls.Add($tabs)
$form.Controls.Add($header)

$nodesTab = New-Object System.Windows.Forms.TabPage
$nodesTab.Text = 'Servers'
$nodesTab.BackColor = $script:Ui.Surface
$nodesTab.ForeColor = $script:Ui.Text
$nodesTab.Padding = New-Object System.Windows.Forms.Padding(18, 16, 18, 12)
$tabs.TabPages.Add($nodesTab)

$nodeList = New-Object System.Windows.Forms.ListView
$nodeList.Dock = 'Fill'
$nodeList.View = 'Details'
$nodeList.FullRowSelect = $true
$nodeList.MultiSelect = $false
$nodeList.Columns.Add('SERVER', 360) | Out-Null
$nodeList.Columns.Add('SOURCE', 300) | Out-Null
$nodeList.Columns.Add('LATENCY', 120) | Out-Null
Set-ListStyle $nodeList
$nodesTab.Controls.Add($nodeList)

$nodeButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$nodeButtons.Dock = 'Bottom'
$nodeButtons.Height = 62
$nodeButtons.Padding = New-Object System.Windows.Forms.Padding(0, 13, 0, 8)
$nodeButtons.BackColor = $script:Ui.Surface
$nodesTab.Controls.Add($nodeButtons)
foreach ($definition in @(
    @('Refresh', 'Refresh', 'Secondary', 96),
    @('Ping all', 'Ping', 'Secondary', 104),
    @('Connect', 'Connect', 'Primary', 112),
    @('Disconnect', 'Disconnect', 'Danger', 112),
    @('Remove', 'Remove', 'Secondary', 96)
)) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $definition[0]
    $button.Name = $definition[1]
    $button.Width = $definition[3]
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    Set-ActionButton $button $definition[2]
    $nodeButtons.Controls.Add($button)
}

$addTab = New-Object System.Windows.Forms.TabPage
$addTab.Text = 'Add connection'
$addTab.BackColor = $script:Ui.Surface
$addTab.ForeColor = $script:Ui.Text
$tabs.TabPages.Add($addTab)
$addPanel = New-Object System.Windows.Forms.TableLayoutPanel
$addPanel.Dock = 'Fill'
$addPanel.Padding = New-Object System.Windows.Forms.Padding(28, 22, 28, 22)
$addPanel.ColumnCount = 1
$addPanel.RowCount = 11
$addPanel.AutoScroll = $true
$addPanel.BackColor = $script:Ui.Surface
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 42)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 34)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 42)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 52)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 32)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 30)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 42)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 52)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 34)))
$addPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
$addTab.Controls.Add($addPanel)

$addTitle = New-Object System.Windows.Forms.Label
$addTitle.Text = 'Add a connection'
$addTitle.Font = $script:PageTitleFont
$addTitle.ForeColor = $script:Ui.Text
$addTitle.AutoSize = $true
$addPanel.Controls.Add($addTitle, 0, 0)
$addIntro = New-Object System.Windows.Forms.Label
$addIntro.Text = 'Import one share link, or add a subscription that can update many servers.'
$addIntro.Font = $script:CaptionFont
$addIntro.ForeColor = $script:Ui.Muted
$addIntro.AutoSize = $true
$addPanel.Controls.Add($addIntro, 0, 1)

$uriLabel = New-Object System.Windows.Forms.Label
$uriLabel.Text = 'Single configuration - VLESS, VMess, Trojan or Shadowsocks'
$uriLabel.Font = $script:StrongFont
$uriLabel.ForeColor = $script:Ui.Text
$uriLabel.AutoSize = $true
$uriLabel.Anchor = 'Left,Bottom'
$addPanel.Controls.Add($uriLabel, 0, 2)
$uriBox = New-Object System.Windows.Forms.TextBox
$uriBox.Dock = 'Fill'
$uriBox.UseSystemPasswordChar = $true
$uriBox.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 5)
Set-InputStyle $uriBox
$addPanel.Controls.Add($uriBox, 0, 3)
$addNodeButton = New-Object System.Windows.Forms.Button
$addNodeButton.Text = 'Add configuration'
$addNodeButton.Width = 170
$addNodeButton.Anchor = 'Left,Top'
Set-ActionButton $addNodeButton 'Primary'
$addPanel.Controls.Add($addNodeButton, 0, 4)
$subLabel = New-Object System.Windows.Forms.Label
$subLabel.Text = 'Subscription URL'
$subLabel.Font = $script:StrongFont
$subLabel.ForeColor = $script:Ui.Text
$subLabel.AutoSize = $true
$subLabel.Anchor = 'Left,Bottom'
$addPanel.Controls.Add($subLabel, 0, 6)
$subBox = New-Object System.Windows.Forms.TextBox
$subBox.Dock = 'Fill'
$subBox.UseSystemPasswordChar = $true
$subBox.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 5)
Set-InputStyle $subBox
$addPanel.Controls.Add($subBox, 0, 7)
$addSubButton = New-Object System.Windows.Forms.Button
$addSubButton.Text = 'Add and update subscription'
$addSubButton.Width = 230
$addSubButton.Anchor = 'Left,Top'
Set-ActionButton $addSubButton 'Primary'
$addPanel.Controls.Add($addSubButton, 0, 8)
$showSecrets = New-Object System.Windows.Forms.CheckBox
$showSecrets.Text = 'Show pasted links on screen'
$showSecrets.Font = $script:CaptionFont
$showSecrets.ForeColor = $script:Ui.Muted
$showSecrets.AutoSize = $true
$showSecrets.FlatStyle = 'Flat'
$showSecrets.Add_CheckedChanged({
    $uriBox.UseSystemPasswordChar = -not $showSecrets.Checked
    $subBox.UseSystemPasswordChar = -not $showSecrets.Checked
})
$addPanel.Controls.Add($showSecrets, 0, 9)

$subsTab = New-Object System.Windows.Forms.TabPage
$subsTab.Text = 'Subscriptions'
$subsTab.BackColor = $script:Ui.Surface
$subsTab.ForeColor = $script:Ui.Text
$subsTab.Padding = New-Object System.Windows.Forms.Padding(18, 16, 18, 12)
$tabs.TabPages.Add($subsTab)
$subsHeader = New-PageHeader 'Subscriptions' 'Update providers independently and see how many servers each source owns.'
$subsHeader.Dock = 'Top'
$subsHeader.Height = 64
$subsHeader.BackColor = $script:Ui.Surface
$subsTab.Controls.Add($subsHeader)
$subList = New-Object System.Windows.Forms.ListView
$subList.Dock = 'Fill'
$subList.View = 'Details'
$subList.FullRowSelect = $true
$subList.MultiSelect = $false
$subList.Columns.Add('SUBSCRIPTION', 460) | Out-Null
$subList.Columns.Add('SERVERS', 110) | Out-Null
$subList.Columns.Add('REMAINING', 170) | Out-Null
Set-ListStyle $subList
$subsTab.Controls.Add($subList)
$subButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$subButtons.Dock = 'Bottom'
$subButtons.Height = 62
$subButtons.Padding = New-Object System.Windows.Forms.Padding(0, 13, 0, 8)
$subButtons.BackColor = $script:Ui.Surface
$subsTab.Controls.Add($subButtons)
foreach ($definition in @(
    @('Update selected', 'UpdateSelected', 'Primary', 148),
    @('Update all', 'UpdateAll', 'Secondary', 112),
    @('Remove', 'RemoveSelected', 'Danger', 104)
)) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $definition[0]
    $button.Name = $definition[1]
    $button.Width = $definition[3]
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    Set-ActionButton $button $definition[2]
    $subButtons.Controls.Add($button)
}

$routingTab = New-Object System.Windows.Forms.TabPage
$routingTab.Text = 'Split routing'
$routingTab.BackColor = $script:Ui.Surface
$routingTab.ForeColor = $script:Ui.Text
$routingTab.Padding = New-Object System.Windows.Forms.Padding(18, 16, 18, 12)
$tabs.TabPages.Add($routingTab)
$routingHeader = New-PageHeader 'Split routing' 'Decide which sites and Windows applications use the tunnel.'
$routingHeader.Dock = 'Top'
$routingHeader.Height = 64
$routingHeader.BackColor = $script:Ui.Surface
$routingTab.Controls.Add($routingHeader)
$routingPanel = New-Object System.Windows.Forms.TableLayoutPanel
$routingPanel.Dock = 'Fill'
$routingPanel.Padding = New-Object System.Windows.Forms.Padding(0)
$routingPanel.BackColor = $script:Ui.Surface
$routingPanel.ColumnCount = 2
$routingPanel.RowCount = 7
$routingPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$routingPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 28)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 46)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 32)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 42)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 52)))
$routingPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 34)))
$routingTab.Controls.Add($routingPanel)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = 'Traffic mode'
$modeLabel.Font = $script:StrongFont
$modeLabel.ForeColor = $script:Ui.Text
$modeLabel.AutoSize = $true
$modeLabel.Anchor = 'Left,Bottom'
$routingPanel.Controls.Add($modeLabel, 0, 0)
$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.DropDownStyle = 'DropDownList'
$modeCombo.Items.AddRange(@('All traffic through VPN', 'Bypass listed sites/apps', 'Only listed sites/apps use VPN'))
$modeCombo.Dock = 'Fill'
$modeCombo.FlatStyle = 'Flat'
$modeCombo.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 6)
Set-InputStyle $modeCombo
$routingPanel.SetColumnSpan($modeCombo, 2)
$routingPanel.Controls.Add($modeCombo, 0, 1)

$domainLabel = New-Object System.Windows.Forms.Label
$domainLabel.Text = 'Sites (hostname or URL)'
$domainLabel.Font = $script:StrongFont
$domainLabel.ForeColor = $script:Ui.Text
$domainLabel.AutoSize = $true
$domainLabel.Anchor = 'Left,Bottom'
$appLabel = New-Object System.Windows.Forms.Label
$appLabel.Text = 'Applications (process or absolute path)'
$appLabel.Font = $script:StrongFont
$appLabel.ForeColor = $script:Ui.Text
$appLabel.AutoSize = $true
$appLabel.Anchor = 'Left,Bottom'
$routingPanel.Controls.Add($domainLabel, 0, 2)
$routingPanel.Controls.Add($appLabel, 1, 2)
$domainList = New-Object System.Windows.Forms.ListBox
$domainList.Dock = 'Fill'
$domainList.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 6)
Set-InputStyle $domainList
$appList = New-Object System.Windows.Forms.ListBox
$appList.Dock = 'Fill'
$appList.Margin = New-Object System.Windows.Forms.Padding(8, 3, 0, 6)
Set-InputStyle $appList
$routingPanel.Controls.Add($domainList, 0, 3)
$routingPanel.Controls.Add($appList, 1, 3)
$domainBox = New-Object System.Windows.Forms.TextBox
$domainBox.Dock = 'Fill'
$domainBox.Margin = New-Object System.Windows.Forms.Padding(0, 3, 8, 5)
Set-InputStyle $domainBox
$appBox = New-Object System.Windows.Forms.TextBox
$appBox.Dock = 'Fill'
$appBox.Margin = New-Object System.Windows.Forms.Padding(8, 3, 0, 5)
Set-InputStyle $appBox
$routingPanel.Controls.Add($domainBox, 0, 4)
$routingPanel.Controls.Add($appBox, 1, 4)
$domainButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$domainButtons.Dock = 'Fill'
$domainButtons.BackColor = $script:Ui.Surface
$domainButtons.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$addDomainButton = New-Object System.Windows.Forms.Button
$addDomainButton.Text = 'Add site'
$addDomainButton.Width = 104
Set-ActionButton $addDomainButton 'Primary'
$removeDomainButton = New-Object System.Windows.Forms.Button
$removeDomainButton.Text = 'Remove'
$removeDomainButton.Width = 104
Set-ActionButton $removeDomainButton 'Secondary'
$domainButtons.Controls.Add($addDomainButton); $domainButtons.Controls.Add($removeDomainButton)
$appButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$appButtons.Dock = 'Fill'
$appButtons.BackColor = $script:Ui.Surface
$appButtons.Padding = New-Object System.Windows.Forms.Padding(8, 4, 0, 0)
$addAppButton = New-Object System.Windows.Forms.Button
$addAppButton.Text = 'Add app'
$addAppButton.Width = 96
Set-ActionButton $addAppButton 'Primary'
$pickAppButton = New-Object System.Windows.Forms.Button
$pickAppButton.Text = 'Choose apps...'
$pickAppButton.Width = 126
Set-ActionButton $pickAppButton 'Secondary'
$removeAppButton = New-Object System.Windows.Forms.Button
$removeAppButton.Text = 'Remove'
$removeAppButton.Width = 96
Set-ActionButton $removeAppButton 'Secondary'
$appButtons.Controls.Add($addAppButton); $appButtons.Controls.Add($pickAppButton); $appButtons.Controls.Add($removeAppButton)
$routingPanel.Controls.Add($domainButtons, 0, 5)
$routingPanel.Controls.Add($appButtons, 1, 5)
$routingNote = New-Object System.Windows.Forms.Label
$routingNote.Text = 'Reconnect after changes. Exact executable paths give the most reliable app matching.'
$routingNote.Font = $script:CaptionFont
$routingNote.ForeColor = $script:Ui.Muted
$routingNote.AutoSize = $true
$routingPanel.SetColumnSpan($routingNote, 2)
$routingPanel.Controls.Add($routingNote, 0, 6)

$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor = $script:Ui.Raised
$statusBar.ForeColor = $script:Ui.Muted
$statusBar.Font = $script:CaptionFont
$statusBar.SizingGrip = $false
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready  |  Disconnected'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
$statusBar.Items.Add($statusLabel) | Out-Null
$versionLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$versionLabel.Text = 'WProxy 2.5.0  |  Windows TUN'
$versionLabel.ForeColor = $script:Ui.Muted
$statusBar.Items.Add($versionLabel) | Out-Null
$form.Controls.Add($statusBar)
$header.BringToFront()
$statusBar.BringToFront()
$subsHeader.BringToFront()
$routingHeader.BringToFront()

$tray = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path $iconPath) { $tray.Icon = New-Object System.Drawing.Icon($iconPath) } else { $tray.Icon = [System.Drawing.SystemIcons]::Shield }
$tray.Text = 'WProxy'
$tray.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$showItem = $trayMenu.Items.Add('Open WProxy')
$disconnectItem = $trayMenu.Items.Add('Disconnect')
$exitItem = $trayMenu.Items.Add('Exit')
$tray.ContextMenuStrip = $trayMenu

function Refresh-Routing {
    $result = Invoke-Ctl @('routing', 'show', '--json')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    try {
        $routing = $result.Output | ConvertFrom-Json
        $script:RoutingLoading = $true
        $modeCombo.SelectedIndex = @{ all = 0; bypass = 1; only = 2 }[$routing.mode]
        $domainList.Items.Clear()
        foreach ($domain in $routing.domains) { $domainList.Items.Add([string]$domain) | Out-Null }
        $appList.Items.Clear()
        foreach ($app in $routing.apps) { $appList.Items.Add([string]$app) | Out-Null }
    } catch {
        Show-Error ('WProxy could not read the saved routing rules. ' + $_.Exception.Message)
    } finally {
        $script:RoutingLoading = $false
    }
}

function Refresh-Subscriptions {
    $result = Invoke-Ctl @('sub', 'list', '--json')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $subList.Items.Clear()
    try { $subscriptions = @($result.Output | ConvertFrom-Json) }
    catch { Show-Error ('WProxy could not read subscriptions. ' + $_.Exception.Message); return }
    foreach ($subscription in $subscriptions) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$subscription.name)
        $item.Tag = [string]$subscription.id
        $item.SubItems.Add([string]$subscription.node_count) | Out-Null
        $item.SubItems.Add([string]$subscription.remaining_human) | Out-Null
        $subList.Items.Add($item) | Out-Null
    }
}

function Show-AppPicker {
    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = 'Choose applications for routing'
    $picker.Size = New-Object System.Drawing.Size(820, 560)
    $picker.MinimumSize = New-Object System.Drawing.Size(660, 440)
    $picker.StartPosition = 'CenterParent'
    $picker.BackColor = $script:Ui.Canvas
    $picker.ForeColor = $script:Ui.Text
    $picker.Font = $script:BodyFont
    $picker.ShowInTaskbar = $false
    if ($form.Icon) { $picker.Icon = $form.Icon }
    $picker.Add_HandleCreated({ Enable-DarkTitleBar $picker })

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Choose running applications, or browse for an .exe file. Exact paths are the most reliable selectors.'
    $hint.Dock = 'Top'; $hint.Height = 62; $hint.Padding = New-Object System.Windows.Forms.Padding(18, 18, 18, 10)
    $hint.Font = $script:CaptionFont
    $hint.ForeColor = $script:Ui.Muted
    $hint.BackColor = $script:Ui.Canvas
    $picker.Controls.Add($hint)
    $choices = New-Object System.Windows.Forms.CheckedListBox
    $choices.Dock = 'Fill'; $choices.CheckOnClick = $true
    $choices.BackColor = $script:Ui.Surface
    $choices.ForeColor = $script:Ui.Text
    $choices.BorderStyle = 'FixedSingle'
    $choices.Font = $script:BodyFont
    $choices.IntegralHeight = $false
    $picker.Controls.Add($choices)
    $pathByLabel = @{}
    try {
        $processes = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath } | Sort-Object Name, ExecutablePath -Unique
        foreach ($process in $processes) {
            $path = ([string]$process.ExecutablePath).Replace('\', '/')
            $label = ([string]$process.Name) + ' - ' + $path
            if (-not $pathByLabel.ContainsKey($label)) {
                $pathByLabel[$label] = $path
                $choices.Items.Add($label) | Out-Null
            }
        }
    } catch {
        $hint.Text = 'Running-process discovery was limited. Use Browse to select an executable.'
    }

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'; $buttons.Height = 64; $buttons.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 10)
    $buttons.BackColor = $script:Ui.Canvas
    $picker.Controls.Add($buttons)
    $browse = New-Object System.Windows.Forms.Button; $browse.Text = 'Browse .exe...'; $browse.Width = 132
    $addSelected = New-Object System.Windows.Forms.Button; $addSelected.Text = 'Add selected'; $addSelected.Width = 132
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.Width = 96
    Set-ActionButton $browse 'Secondary'
    Set-ActionButton $addSelected 'Primary'
    Set-ActionButton $cancel 'Secondary'
    $buttons.Controls.Add($browse); $buttons.Controls.Add($addSelected); $buttons.Controls.Add($cancel)
    $browse.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'Windows applications (*.exe)|*.exe'
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog($picker) -eq 'OK') {
            foreach ($file in $dialog.FileNames) {
                $path = $file.Replace('\', '/')
                $label = [IO.Path]::GetFileName($file) + ' - ' + $path
                if (-not $pathByLabel.ContainsKey($label)) {
                    $pathByLabel[$label] = $path
                    $index = $choices.Items.Add($label)
                    $choices.SetItemChecked($index, $true)
                }
            }
        }
    })
    $addSelected.Add_Click({
        foreach ($label in @($choices.CheckedItems)) {
            $result = Invoke-Ctl @('routing', 'app', 'add', [string]$pathByLabel[[string]$label])
            if ($result.Code -ne 0) { Show-Error $result.Output; return }
        }
        $picker.DialogResult = 'OK'; $picker.Close()
    })
    $cancel.Add_Click({ $picker.DialogResult = 'Cancel'; $picker.Close() })
    $hint.BringToFront()
    $buttons.BringToFront()
    if ($picker.ShowDialog($form) -eq 'OK') { Refresh-Routing }
    $picker.Dispose()
}

function Refresh-Nodes([hashtable]$Latencies) {
    $result = Invoke-Ctl @('node', 'list', '--json')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $nodeList.Items.Clear()
    try { $nodes = @($result.Output | ConvertFrom-Json) }
    catch { Show-Error ('WProxy could not read servers. ' + $_.Exception.Message); return }
    foreach ($node in $nodes) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$node.name)
        $item.Tag = [string]$node.id
        $item.SubItems.Add([string]$node.source_name) | Out-Null
        $latency = ''
        if ($Latencies -and $Latencies.ContainsKey([string]$node.id)) { $latency = $Latencies[[string]$node.id] }
        $item.SubItems.Add($latency) | Out-Null
        $nodeList.Items.Add($item) | Out-Null
    }
}

function Refresh-Status {
    $result = Invoke-Ctl @('windows', 'status', '--json')
    if ($result.Code -ne 0) {
        $statusLabel.Text = 'Status unavailable'
        $connectionState.Text = 'Status unavailable'
        $connectionDetail.Text = 'Open the manager again or reinstall WProxy.'
        $connectionDot.ForeColor = $script:Ui.Danger
        return
    }
    try { $status = $result.Output | ConvertFrom-Json }
    catch {
        $statusLabel.Text = 'Status unavailable'
        $connectionState.Text = 'Status unavailable'
        $connectionDetail.Text = 'The command engine returned an unreadable response.'
        $connectionDot.ForeColor = $script:Ui.Danger
        return
    }
    if ($status.active -and $status.verified) {
        $script:ActiveNodeId = [string]$status.node_id
        $statusLabel.Text = 'Connected  |  ' + $status.name
        $connectionState.Text = 'Connected'
        $connectionDetail.Text = [string]$status.name
        $connectionDot.ForeColor = $script:Ui.Accent
        $tray.Text = ('WProxy - Connected: ' + $status.name).Substring(0, [Math]::Min(63, ('WProxy - Connected: ' + $status.name).Length))
        $disconnectItem.Enabled = $true
    } elseif ($status.active) {
        $script:ActiveNodeId = [string]$status.node_id
        $statusLabel.Text = 'Verifying tunnel...'
        $connectionState.Text = 'Verifying tunnel'
        $connectionDetail.Text = [string]$status.name
        $connectionDot.ForeColor = $script:Ui.Blue
        $tray.Text = 'WProxy - Starting...'
        $disconnectItem.Enabled = $true
    } else {
        $script:ActiveNodeId = $null
        $statusLabel.Text = 'Ready  |  Disconnected'
        $connectionState.Text = 'Disconnected'
        $connectionDetail.Text = 'Select a server to start the tunnel'
        $connectionDot.ForeColor = $script:Ui.Muted
        $tray.Text = 'WProxy - Disconnected'
        $disconnectItem.Enabled = $false
    }
    $nodeList.Invalidate()
}

function Refresh-All { Refresh-Status; Refresh-Nodes @{}; Refresh-Subscriptions; Refresh-Routing }

$nodeButtons.Controls['Refresh'].Add_Click({ Refresh-All })
$nodeButtons.Controls['Ping'].Add_Click({
    $statusLabel.Text = 'Pinging...'
    $result = Invoke-Ctl @('node', 'ping', '--all', '--json', '--timeout', '2')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $latencies = @{}
    try { $pingRows = @($result.Output | ConvertFrom-Json) }
    catch { Show-Error ('WProxy could not read latency results. ' + $_.Exception.Message); return }
    foreach ($row in $pingRows) {
        $latencies[[string]$row.id] = if ($null -eq $row.latency_ms) { 'timeout' } else { [string]$row.latency_ms + ' ms' }
    }
    Refresh-Nodes $latencies
    $statusLabel.Text = 'Ping complete'
})
$nodeButtons.Controls['Connect'].Add_Click({
    if ($nodeList.SelectedItems.Count -ne 1) { Show-Error 'Select one server first.'; return }
    $statusLabel.Text = 'Connecting...'
    if ((Invoke-AdminCtl @('windows', 'up', [string]$nodeList.SelectedItems[0].Tag)) -eq 0) { Refresh-Status }
})
$nodeButtons.Controls['Disconnect'].Add_Click({ if ((Invoke-AdminCtl @('windows', 'down')) -eq 0) { Refresh-Status } })
$nodeButtons.Controls['Remove'].Add_Click({
    if ($nodeList.SelectedItems.Count -ne 1) { Show-Error 'Select one server first.'; return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'Remove this server from WProxy?', 'WProxy', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    $result = Invoke-Ctl @('node', 'remove', [string]$nodeList.SelectedItems[0].Tag)
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Nodes @{}
})
$nodeList.Add_DoubleClick({
    if ($nodeList.SelectedItems.Count -eq 1) { $nodeButtons.Controls['Connect'].PerformClick() }
})

$addNodeButton.Add_Click({
    if (-not $uriBox.Text.Trim()) { return }
    $result = Invoke-Ctl @('node', 'add', $uriBox.Text.Trim())
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $uriBox.Clear(); Refresh-Nodes @{}
})
$addSubButton.Add_Click({
    if (-not $subBox.Text.Trim()) { return }
    $added = Invoke-Ctl @('sub', 'add', $subBox.Text.Trim())
    if ($added.Code -ne 0) { Show-Error $added.Output; return }
    $updated = Invoke-Ctl @('sub', 'update', $added.Output.Trim())
    if ($updated.Code -ne 0) { Show-Error $updated.Output; return }
    $subBox.Clear(); Refresh-Nodes @{}; Refresh-Subscriptions
})
$subButtons.Controls['UpdateSelected'].Add_Click({
    if ($subList.SelectedItems.Count -ne 1) { Show-Error 'Select one subscription first.'; return }
    $result = Invoke-Ctl @('sub', 'update', [string]$subList.SelectedItems[0].Tag)
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Nodes @{}; Refresh-Subscriptions
})
$subButtons.Controls['UpdateAll'].Add_Click({
    $result = Invoke-Ctl @('sub', 'update')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Nodes @{}; Refresh-Subscriptions
})
$subButtons.Controls['RemoveSelected'].Add_Click({
    if ($subList.SelectedItems.Count -ne 1) { Show-Error 'Select one subscription first.'; return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'Remove this subscription and only the servers imported from it?', 'WProxy', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    $result = Invoke-Ctl @('sub', 'remove', [string]$subList.SelectedItems[0].Tag)
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Nodes @{}; Refresh-Subscriptions
})

$modeCombo.Add_SelectedIndexChanged({
    if ($script:RoutingLoading -or $modeCombo.SelectedIndex -lt 0) { return }
    $mode = @('all', 'bypass', 'only')[$modeCombo.SelectedIndex]
    $result = Invoke-Ctl @('routing', 'mode', $mode)
    if ($result.Code -ne 0) { Show-Error $result.Output }
})
$addDomainButton.Add_Click({
    if (-not $domainBox.Text.Trim()) { return }
    $result = Invoke-Ctl @('routing', 'domain', 'add', $domainBox.Text.Trim())
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $domainBox.Clear(); Refresh-Routing
})
$removeDomainButton.Add_Click({
    if ($null -eq $domainList.SelectedItem) { return }
    $result = Invoke-Ctl @('routing', 'domain', 'remove', [string]$domainList.SelectedItem)
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Routing
})
$addAppButton.Add_Click({
    if (-not $appBox.Text.Trim()) { return }
    $result = Invoke-Ctl @('routing', 'app', 'add', $appBox.Text.Trim())
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $appBox.Clear(); Refresh-Routing
})
$pickAppButton.Add_Click({ Show-AppPicker })
$removeAppButton.Add_Click({
    if ($null -eq $appList.SelectedItem) { return }
    $result = Invoke-Ctl @('routing', 'app', 'remove', [string]$appList.SelectedItem)
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Routing
})

$showWindow = { $form.Show(); $form.WindowState = 'Normal'; $form.Activate() }
$showItem.Add_Click($showWindow)
$tray.Add_DoubleClick($showWindow)
$disconnectItem.Add_Click({ if ((Invoke-AdminCtl @('windows', 'down')) -eq 0) { Refresh-Status } })
$exitItem.Add_Click({ $script:Exiting = $true; $tray.Visible = $false; $form.Close(); [System.Windows.Forms.Application]::ExitThread() })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if (-not $script:Exiting) {
        $eventArgs.Cancel = $true
        $form.Hide()
        $tray.ShowBalloonTip(1800, 'WProxy is still running', 'Double-click the tray icon to open it again.', 'Info')
    }
})
$form.Add_Resize({
    if ($form.WindowState -eq 'Minimized') { $form.Hide() }
})
$form.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq 'F5') { Refresh-All; $eventArgs.SuppressKeyPress = $true }
    elseif ($eventArgs.Control -and $eventArgs.KeyCode -eq 'P') {
        $nodeButtons.Controls['Ping'].PerformClick(); $eventArgs.SuppressKeyPress = $true
    } elseif ($eventArgs.KeyCode -eq 'Escape') {
        $form.Hide(); $eventArgs.SuppressKeyPress = $true
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
    try { Refresh-Status }
    catch {
        $statusLabel.Text = 'Status refresh failed'
        $connectionDot.ForeColor = $script:Ui.Danger
    }
})
$timer.Start()
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    $statusLabel.Text = 'The last action failed; WProxy is still running.'
    $connectionState.Text = 'Action failed'
    $connectionDetail.Text = $eventArgs.Exception.Message
    $connectionDot.ForeColor = $script:Ui.Danger
})

if ($Show) {
    $form.Add_Shown({
        try { Refresh-All }
        catch {
            $statusLabel.Text = 'WProxy opened, but data could not be refreshed.'
            $connectionState.Text = 'Refresh failed'
            $connectionDetail.Text = $_.Exception.Message
            $connectionDot.ForeColor = $script:Ui.Danger
        }
    })
    $form.Show()
} else {
    try { Refresh-All }
    catch { $tray.Text = 'WProxy - status unavailable' }
}
[System.Windows.Forms.Application]::Run()
$tray.Dispose()
$form.Dispose()
foreach ($brush in $script:Brushes.Values) { $brush.Dispose() }
