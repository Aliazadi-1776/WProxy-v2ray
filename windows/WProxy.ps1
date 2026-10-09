param([switch]$Show)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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

function Invoke-Ctl([string[]]$Arguments) {
    if ($script:UseExe) { $output = & $script:CtlExe @Arguments 2>&1 | Out-String }
    else { $output = & $script:Python $script:CtlPy @Arguments 2>&1 | Out-String }
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output.Trim() }
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

$form = New-Object System.Windows.Forms.Form
$form.Text = 'WProxy 2.5.0'
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
$nodeList.Columns.Add('Server', 300) | Out-Null
$nodeList.Columns.Add('Subscription', 220) | Out-Null
$nodeList.Columns.Add('Latency', 90) | Out-Null
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

$subsTab = New-Object System.Windows.Forms.TabPage
$subsTab.Text = 'Subscriptions'
$subsTab.BackColor = $form.BackColor
$subsTab.ForeColor = $form.ForeColor
$tabs.TabPages.Add($subsTab)
$subList = New-Object System.Windows.Forms.ListView
$subList.Dock = 'Fill'
$subList.View = 'Details'
$subList.FullRowSelect = $true
$subList.MultiSelect = $false
$subList.Columns.Add('Subscription', 380) | Out-Null
$subList.Columns.Add('Servers', 90) | Out-Null
$subList.Columns.Add('Remaining', 140) | Out-Null
$subsTab.Controls.Add($subList)
$subButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$subButtons.Dock = 'Bottom'
$subButtons.Height = 48
$subButtons.Padding = New-Object System.Windows.Forms.Padding(8)
$subsTab.Controls.Add($subButtons)
foreach ($definition in @(@('Update selected', 'UpdateSelected'), @('Update all', 'UpdateAll'), @('Remove selected', 'RemoveSelected'))) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $definition[0]
    $button.Name = $definition[1]
    $button.AutoSize = $true
    $subButtons.Controls.Add($button)
}

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
$pickAppButton = New-Object System.Windows.Forms.Button
$pickAppButton.Text = 'Choose apps…'
$removeAppButton = New-Object System.Windows.Forms.Button
$removeAppButton.Text = 'Remove selected'
$appButtons.Controls.Add($addAppButton); $appButtons.Controls.Add($pickAppButton); $appButtons.Controls.Add($removeAppButton)
$routingPanel.Controls.Add($domainButtons, 0, 5)
$routingPanel.Controls.Add($appButtons, 1, 5)
$routingNote = New-Object System.Windows.Forms.Label
$routingNote.Text = 'Reconnect after changes. Choose apps by executable path for reliable Windows matching.'
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

function Refresh-Subscriptions {
    $result = Invoke-Ctl @('sub', 'list', '--json')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $subList.Items.Clear()
    foreach ($subscription in @($result.Output | ConvertFrom-Json)) {
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
    $picker.Size = New-Object System.Drawing.Size(760, 520)
    $picker.MinimumSize = New-Object System.Drawing.Size(620, 420)
    $picker.StartPosition = 'CenterParent'
    $picker.BackColor = $form.BackColor
    $picker.ForeColor = $form.ForeColor

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Select running applications, or browse to an .exe file. Exact paths are the most reliable selectors.'
    $hint.Dock = 'Top'; $hint.Height = 42; $hint.Padding = New-Object System.Windows.Forms.Padding(8)
    $picker.Controls.Add($hint)
    $choices = New-Object System.Windows.Forms.CheckedListBox
    $choices.Dock = 'Fill'; $choices.CheckOnClick = $true
    $picker.Controls.Add($choices)
    $pathByLabel = @{}
    try {
        $processes = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath } | Sort-Object Name, ExecutablePath -Unique
        foreach ($process in $processes) {
            $path = ([string]$process.ExecutablePath).Replace('\', '/')
            $label = ([string]$process.Name) + ' — ' + $path
            if (-not $pathByLabel.ContainsKey($label)) {
                $pathByLabel[$label] = $path
                $choices.Items.Add($label) | Out-Null
            }
        }
    } catch {
        $hint.Text = 'Running-process discovery was limited. Use Browse to select an executable.'
    }

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'; $buttons.Height = 52; $buttons.Padding = New-Object System.Windows.Forms.Padding(8)
    $picker.Controls.Add($buttons)
    $browse = New-Object System.Windows.Forms.Button; $browse.Text = 'Browse .exe…'; $browse.AutoSize = $true
    $addSelected = New-Object System.Windows.Forms.Button; $addSelected.Text = 'Add selected'; $addSelected.AutoSize = $true
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.AutoSize = $true
    $buttons.Controls.Add($browse); $buttons.Controls.Add($addSelected); $buttons.Controls.Add($cancel)
    $browse.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = 'Windows applications (*.exe)|*.exe'
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog($picker) -eq 'OK') {
            foreach ($file in $dialog.FileNames) {
                $path = $file.Replace('\', '/')
                $label = [IO.Path]::GetFileName($file) + ' — ' + $path
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
    if ($picker.ShowDialog($form) -eq 'OK') { Refresh-Routing }
    $picker.Dispose()
}

function Refresh-Nodes([hashtable]$Latencies) {
    $result = Invoke-Ctl @('node', 'list', '--json')
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    $nodeList.Items.Clear()
    $nodes = @($result.Output | ConvertFrom-Json)
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
    if ($result.Code -ne 0) { return }
    $status = $result.Output | ConvertFrom-Json
    if ($status.active -and $status.verified) {
        $statusLabel.Text = 'Connected: ' + $status.name
        $tray.Text = ('WProxy - Connected: ' + $status.name).Substring(0, [Math]::Min(63, ('WProxy - Connected: ' + $status.name).Length))
    } elseif ($status.active) {
        $statusLabel.Text = 'Starting tunnel verification…'
        $tray.Text = 'WProxy - Starting…'
    } else {
        $statusLabel.Text = 'Disconnected'
        $tray.Text = 'WProxy - Disconnected'
    }
}

function Refresh-All { Refresh-Nodes @{}; Refresh-Subscriptions; Refresh-Routing; Refresh-Status }

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
$form.Add_FormClosing({ param($sender, $eventArgs); if (-not $script:Exiting) { $eventArgs.Cancel = $true; $form.Hide() } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Refresh-Status })
$timer.Start()
Refresh-All
if ($Show) { $form.Show() }
[System.Windows.Forms.Application]::Run()
$tray.Dispose()
