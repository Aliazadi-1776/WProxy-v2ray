param([switch]$Show)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = Split-Path -Parent $PSScriptRoot
$script:Ctl = Join-Path $script:Root 'cli\wproxyctl.py'
$pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $pythonCommand) { $pythonCommand = Get-Command python -ErrorAction SilentlyContinue }
if (-not $pythonCommand) {
    [System.Windows.Forms.MessageBox]::Show('Python 3 is required. Re-run install-windows.ps1 after installing Python.', 'WProxy') | Out-Null
    exit 2
}
$script:Python = $pythonCommand.Source
$script:RoutingLoading = $false
$script:Exiting = $false

function Invoke-Ctl([string[]]$Arguments) {
    $output = & $script:Python $script:Ctl @Arguments 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output.Trim() }
}

function Show-Error([string]$Message) {
    if (-not $Message) { $Message = 'The operation failed.' }
    [System.Windows.Forms.MessageBox]::Show($Message, 'WProxy', 'OK', 'Error') | Out-Null
}

function Invoke-AdminCtl([string[]]$Arguments) {
    $quotedCtl = '"' + $script:Ctl + '"'
    $argumentList = @($quotedCtl) + $Arguments
    try {
        $process = Start-Process -FilePath $script:Python -ArgumentList $argumentList -Verb RunAs -Wait -PassThru
        return $process.ExitCode
    } catch {
        Show-Error $_.Exception.Message
        return 1
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'WProxy 2.4.1'
$form.Size = New-Object System.Drawing.Size(760, 620)
$form.MinimumSize = New-Object System.Drawing.Size(640, 480)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$form.ForeColor = [System.Drawing.Color]::WhiteSmoke

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

$nodesTab = New-Object System.Windows.Forms.TabPage
$nodesTab.Text = 'Nodes'
$nodesTab.BackColor = $form.BackColor
$nodesTab.ForeColor = $form.ForeColor
$tabs.TabPages.Add($nodesTab)

$nodeList = New-Object System.Windows.Forms.ListView
$nodeList.Dock = 'Fill'
$nodeList.View = 'Details'
$nodeList.FullRowSelect = $true
$nodeList.MultiSelect = $false
$nodeList.Columns.Add('Server', 430) | Out-Null
$nodeList.Columns.Add('Latency', 100) | Out-Null
$nodesTab.Controls.Add($nodeList)

$nodeButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$nodeButtons.Dock = 'Bottom'
$nodeButtons.Height = 48
$nodeButtons.Padding = New-Object System.Windows.Forms.Padding(8)
$nodesTab.Controls.Add($nodeButtons)
foreach ($definition in @(@('Refresh', 'Refresh'), @('Ping all', 'Ping'), @('Connect', 'Connect'), @('Disconnect', 'Disconnect'))) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $definition[0]
    $button.Name = $definition[1]
    $button.AutoSize = $true
    $nodeButtons.Controls.Add($button)
}

$addTab = New-Object System.Windows.Forms.TabPage
$addTab.Text = 'Add'
$addTab.BackColor = $form.BackColor
$addTab.ForeColor = $form.ForeColor
$tabs.TabPages.Add($addTab)
$addPanel = New-Object System.Windows.Forms.TableLayoutPanel
$addPanel.Dock = 'Fill'
$addPanel.Padding = New-Object System.Windows.Forms.Padding(16)
$addPanel.ColumnCount = 1
$addPanel.RowCount = 8
$addPanel.AutoScroll = $true
$addTab.Controls.Add($addPanel)

$uriLabel = New-Object System.Windows.Forms.Label
$uriLabel.Text = 'VLESS, VMess, Trojan or Shadowsocks share link'
$uriLabel.AutoSize = $true
$uriBox = New-Object System.Windows.Forms.TextBox
$uriBox.Dock = 'Top'
$uriBox.UseSystemPasswordChar = $true
$addNodeButton = New-Object System.Windows.Forms.Button
$addNodeButton.Text = 'Add configuration'
$addNodeButton.AutoSize = $true
$subLabel = New-Object System.Windows.Forms.Label
$subLabel.Text = 'Subscription URL'
$subLabel.AutoSize = $true
$subBox = New-Object System.Windows.Forms.TextBox
$subBox.Dock = 'Top'
$subBox.UseSystemPasswordChar = $true
$addSubButton = New-Object System.Windows.Forms.Button
$addSubButton.Text = 'Add and update subscription'
$addSubButton.AutoSize = $true
foreach ($control in @($uriLabel, $uriBox, $addNodeButton, $subLabel, $subBox, $addSubButton)) { $addPanel.Controls.Add($control) }

$routingTab = New-Object System.Windows.Forms.TabPage
$routingTab.Text = 'Routing'
$routingTab.BackColor = $form.BackColor
$routingTab.ForeColor = $form.ForeColor
$tabs.TabPages.Add($routingTab)
$routingPanel = New-Object System.Windows.Forms.TableLayoutPanel
$routingPanel.Dock = 'Fill'
$routingPanel.Padding = New-Object System.Windows.Forms.Padding(16)
$routingPanel.ColumnCount = 2
$routingPanel.RowCount = 7
$routingPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$routingPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50)))
$routingTab.Controls.Add($routingPanel)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = 'Traffic mode'
$modeLabel.AutoSize = $true
$routingPanel.Controls.Add($modeLabel, 0, 0)
$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.DropDownStyle = 'DropDownList'
$modeCombo.Items.AddRange(@('All traffic through VPN', 'Bypass listed sites/apps', 'Only listed sites/apps use VPN'))
$modeCombo.Dock = 'Fill'
$routingPanel.SetColumnSpan($modeCombo, 2)
$routingPanel.Controls.Add($modeCombo, 0, 1)

$domainLabel = New-Object System.Windows.Forms.Label
$domainLabel.Text = 'Sites (hostname or URL)'
$domainLabel.AutoSize = $true
$appLabel = New-Object System.Windows.Forms.Label
$appLabel.Text = 'Applications (process or absolute path)'
$appLabel.AutoSize = $true
$routingPanel.Controls.Add($domainLabel, 0, 2)
$routingPanel.Controls.Add($appLabel, 1, 2)
$domainList = New-Object System.Windows.Forms.ListBox
$domainList.Dock = 'Fill'
$appList = New-Object System.Windows.Forms.ListBox
$appList.Dock = 'Fill'
$routingPanel.Controls.Add($domainList, 0, 3)
$routingPanel.Controls.Add($appList, 1, 3)
$domainBox = New-Object System.Windows.Forms.TextBox
$domainBox.Dock = 'Fill'
$appBox = New-Object System.Windows.Forms.TextBox
$appBox.Dock = 'Fill'
$routingPanel.Controls.Add($domainBox, 0, 4)
$routingPanel.Controls.Add($appBox, 1, 4)
$domainButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$domainButtons.Dock = 'Fill'
$addDomainButton = New-Object System.Windows.Forms.Button
$addDomainButton.Text = 'Add site'
$removeDomainButton = New-Object System.Windows.Forms.Button
$removeDomainButton.Text = 'Remove selected'
$domainButtons.Controls.Add($addDomainButton); $domainButtons.Controls.Add($removeDomainButton)
$appButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$appButtons.Dock = 'Fill'
$addAppButton = New-Object System.Windows.Forms.Button
$addAppButton.Text = 'Add app'
$removeAppButton = New-Object System.Windows.Forms.Button
$removeAppButton.Text = 'Remove selected'
$appButtons.Controls.Add($addAppButton); $appButtons.Controls.Add($removeAppButton)
$routingPanel.Controls.Add($domainButtons, 0, 5)
$routingPanel.Controls.Add($appButtons, 1, 5)
$routingNote = New-Object System.Windows.Forms.Label
$routingNote.Text = 'Reconnect after changes. Process matching is case-sensitive; encrypted DNS may limit site-only matching.'
$routingNote.AutoSize = $true
$routingPanel.SetColumnSpan($routingNote, 2)
$routingPanel.Controls.Add($routingNote, 0, 6)

$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Disconnected'
$statusBar.Items.Add($statusLabel) | Out-Null
$form.Controls.Add($statusBar)

$tray = New-Object System.Windows.Forms.NotifyIcon
$iconPath = Join-Path $script:Root 'icons\wproxy.ico'
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
    $routing = $result.Output | ConvertFrom-Json
    $script:RoutingLoading = $true
    $modeCombo.SelectedIndex = @{ all = 0; bypass = 1; only = 2 }[$routing.mode]
    $domainList.Items.Clear()
    foreach ($domain in $routing.domains) { $domainList.Items.Add([string]$domain) | Out-Null }
    $appList.Items.Clear()
    foreach ($app in $routing.apps) { $appList.Items.Add([string]$app) | Out-Null }
    $script:RoutingLoading = $false
}

function Refresh-Nodes([hashtable]$Latencies) {
    $result = Invoke-Ctl @('node', 'list', '--json')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $nodeList.Items.Clear()
    $nodes = @($result.Output | ConvertFrom-Json)
    foreach ($node in $nodes) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$node.name)
        $item.Tag = [string]$node.id
        $latency = ''
        if ($Latencies -and $Latencies.ContainsKey([string]$node.id)) { $latency = $Latencies[[string]$node.id] }
        $item.SubItems.Add($latency) | Out-Null
        $nodeList.Items.Add($item) | Out-Null
    }
}

function Refresh-Status {
    $result = Invoke-Ctl @('windows', 'status', '--json')
    if ($result.Code -ne 0) { return }
    $status = $result.Output | ConvertFrom-Json
    if ($status.active) {
        $statusLabel.Text = 'Connected: ' + $status.name
        $tray.Text = ('WProxy - Connected: ' + $status.name).Substring(0, [Math]::Min(63, ('WProxy - Connected: ' + $status.name).Length))
    } else {
        $statusLabel.Text = 'Disconnected'
        $tray.Text = 'WProxy - Disconnected'
    }
}

function Refresh-All { Refresh-Nodes @{}; Refresh-Routing; Refresh-Status }

$nodeButtons.Controls['Refresh'].Add_Click({ Refresh-All })
$nodeButtons.Controls['Ping'].Add_Click({
    $statusLabel.Text = 'Pinging…'
    $result = Invoke-Ctl @('node', 'ping', '--all', '--json', '--timeout', '2')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $latencies = @{}
    foreach ($row in @($result.Output | ConvertFrom-Json)) {
        $latencies[[string]$row.id] = if ($null -eq $row.latency_ms) { 'timeout' } else { [string]$row.latency_ms + ' ms' }
    }
    Refresh-Nodes $latencies
    $statusLabel.Text = 'Ping complete'
})
$nodeButtons.Controls['Connect'].Add_Click({
    if ($nodeList.SelectedItems.Count -ne 1) { Show-Error 'Select one server first.'; return }
    $statusLabel.Text = 'Connecting…'
    if ((Invoke-AdminCtl @('windows', 'up', [string]$nodeList.SelectedItems[0].Tag)) -eq 0) { Refresh-Status }
})
$nodeButtons.Controls['Disconnect'].Add_Click({ if ((Invoke-AdminCtl @('windows', 'down')) -eq 0) { Refresh-Status } })

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
    $subBox.Clear(); Refresh-Nodes @{}
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
$form.Add_FormClosing({ param($sender, $eventArgs); if (-not $script:Exiting) { $eventArgs.Cancel = $true; $form.Hide() } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Refresh-Status })
$timer.Start()
Refresh-All
if ($Show) { $form.Show() }
[System.Windows.Forms.Application]::Run()
$tray.Dispose()
