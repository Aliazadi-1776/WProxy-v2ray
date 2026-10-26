param([switch]$Show, [switch]$LayoutSmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [System.Windows.Forms.Application]::SetHighDpiMode(
        [System.Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null
} catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
try {
    Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace WProxy {
    public static class NativeTheme {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(
            IntPtr window, int attribute, ref int value, int size);
    }

    public sealed class SmoothButton : Control {
        private bool hovered;
        private bool pressed;

        public Color FillColor { get; set; }
        public Color HoverColor { get; set; }
        public Color PressedColor { get; set; }
        public Color BorderColor { get; set; }
        public int BorderSize { get; set; }
        public int CornerRadius { get; set; }
        public ContentAlignment TextAlign { get; set; }

        public SmoothButton() {
            SetStyle(ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw |
                     ControlStyles.UserPaint |
                     ControlStyles.SupportsTransparentBackColor, true);
            AccessibleRole = AccessibleRole.PushButton;
            BackColor = Color.Transparent;
            FillColor = Color.FromArgb(40, 43, 50);
            HoverColor = Color.FromArgb(48, 52, 61);
            PressedColor = Color.FromArgb(34, 37, 44);
            BorderColor = Color.Transparent;
            BorderSize = 0;
            CornerRadius = 12;
            TextAlign = ContentAlignment.MiddleCenter;
            TabStop = true;
        }

        private GraphicsPath RoundedPath(Rectangle bounds, int radius) {
            GraphicsPath path = new GraphicsPath();
            int diameter = Math.Max(2, Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height)));
            Rectangle arc = new Rectangle(bounds.Location, new Size(diameter, diameter));
            path.AddArc(arc, 180, 90);
            arc.X = bounds.Right - diameter;
            path.AddArc(arc, 270, 90);
            arc.Y = bounds.Bottom - diameter;
            path.AddArc(arc, 0, 90);
            arc.X = bounds.Left;
            path.AddArc(arc, 90, 90);
            path.CloseFigure();
            return path;
        }

        protected override void OnPaint(PaintEventArgs e) {
            Color parentColor = Parent == null ? Color.FromArgb(17, 19, 24) : Parent.BackColor;
            e.Graphics.Clear(parentColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle bounds = new Rectangle(1, 1, Math.Max(1, Width - 3), Math.Max(1, Height - 3));
            Color fill = pressed ? PressedColor : (hovered ? HoverColor : FillColor);
            if (!Enabled) {
                fill = Color.FromArgb(
                    (fill.R + parentColor.R * 2) / 3,
                    (fill.G + parentColor.G * 2) / 3,
                    (fill.B + parentColor.B * 2) / 3);
            }
            using (GraphicsPath path = RoundedPath(bounds, CornerRadius))
            using (SolidBrush brush = new SolidBrush(fill)) {
                e.Graphics.FillPath(brush, path);
                if (BorderSize > 0 && BorderColor.A > 0) {
                    using (Pen pen = new Pen(BorderColor, BorderSize)) {
                        pen.Alignment = PenAlignment.Inset;
                        e.Graphics.DrawPath(pen, path);
                    }
                }
                if (Focused && ShowFocusCues) {
                    using (Pen pen = new Pen(Color.FromArgb(150, ForeColor), 1)) {
                        pen.DashStyle = DashStyle.Dot;
                        Rectangle focus = Rectangle.Inflate(bounds, -4, -4);
                        using (GraphicsPath focusPath = RoundedPath(focus, Math.Max(4, CornerRadius - 4))) {
                            e.Graphics.DrawPath(pen, focusPath);
                        }
                    }
                }
            }

            Rectangle textBounds = new Rectangle(
                Padding.Left, Padding.Top,
                Math.Max(0, Width - Padding.Horizontal),
                Math.Max(0, Height - Padding.Vertical));
            TextFormatFlags flags = TextFormatFlags.SingleLine |
                TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis;
            if (TextAlign == ContentAlignment.MiddleLeft) flags |= TextFormatFlags.Left;
            else if (TextAlign == ContentAlignment.MiddleRight) flags |= TextFormatFlags.Right;
            else flags |= TextFormatFlags.HorizontalCenter;
            Color textColor = Enabled ? ForeColor : Color.FromArgb(105, 112, 124);
            TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, textColor, flags);
        }

        protected override void OnMouseEnter(EventArgs e) {
            hovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }
        protected override void OnMouseLeave(EventArgs e) {
            hovered = false;
            pressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }
        protected override void OnMouseDown(MouseEventArgs e) {
            if (e.Button == MouseButtons.Left) {
                pressed = true;
                Focus();
                Invalidate();
            }
            base.OnMouseDown(e);
        }
        protected override void OnMouseUp(MouseEventArgs e) {
            pressed = false;
            Invalidate();
            base.OnMouseUp(e);
        }
        protected override void OnKeyDown(KeyEventArgs e) {
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) {
                PerformClick();
                e.Handled = true;
            }
            base.OnKeyDown(e);
        }
        protected override void OnEnabledChanged(EventArgs e) {
            Invalidate();
            base.OnEnabledChanged(e);
        }
        public void PerformClick() {
            if (Enabled) OnClick(EventArgs.Empty);
        }
    }

    public sealed class SmoothPanel : Panel {
        public Color FillColor { get; set; }
        public Color BorderColor { get; set; }
        public int BorderSize { get; set; }
        public int CornerRadius { get; set; }

        public SmoothPanel() {
            SetStyle(ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw |
                     ControlStyles.UserPaint |
                     ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            FillColor = Color.FromArgb(31, 34, 40);
            BorderColor = Color.Transparent;
            BorderSize = 0;
            CornerRadius = 18;
        }

        protected override void OnPaintBackground(PaintEventArgs e) {
            Color parentColor = Parent == null ? Color.FromArgb(17, 19, 24) : Parent.BackColor;
            e.Graphics.Clear(parentColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle bounds = new Rectangle(1, 1, Math.Max(1, Width - 3), Math.Max(1, Height - 3));
            int diameter = Math.Max(2, Math.Min(CornerRadius * 2, Math.Min(bounds.Width, bounds.Height)));
            using (GraphicsPath path = new GraphicsPath()) {
                Rectangle arc = new Rectangle(bounds.Location, new Size(diameter, diameter));
                path.AddArc(arc, 180, 90);
                arc.X = bounds.Right - diameter;
                path.AddArc(arc, 270, 90);
                arc.Y = bounds.Bottom - diameter;
                path.AddArc(arc, 0, 90);
                arc.X = bounds.Left;
                path.AddArc(arc, 90, 90);
                path.CloseFigure();
                using (SolidBrush brush = new SolidBrush(FillColor)) e.Graphics.FillPath(brush, path);
                if (BorderSize > 0 && BorderColor.A > 0) {
                    using (Pen pen = new Pen(BorderColor, BorderSize)) {
                        pen.Alignment = PenAlignment.Inset;
                        e.Graphics.DrawPath(pen, path);
                    }
                }
            }
        }
    }
}
'@ -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll')
} catch {
    throw ('WProxy visual controls could not be compiled: ' + $_.Exception.Message)
}

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
$script:PreferencesLoading = $false

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

function Start-CtlDetached([string[]]$Arguments) {
    try {
        if ($script:UseExe) {
            Start-Process -FilePath $script:CtlExe -ArgumentList $Arguments -WindowStyle Hidden | Out-Null
        } else {
            $quotedCtl = '"' + $script:CtlPy + '"'
            Start-Process -FilePath $script:Python -ArgumentList (@($quotedCtl) + $Arguments) -WindowStyle Hidden | Out-Null
        }
        return $true
    } catch {
        return $false
    }
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
    Canvas = [System.Drawing.Color]::FromArgb(30, 30, 32)
    Sidebar = [System.Drawing.Color]::FromArgb(37, 37, 40)
    Surface = [System.Drawing.Color]::FromArgb(42, 42, 45)
    Raised = [System.Drawing.Color]::FromArgb(52, 52, 56)
    RaisedHover = [System.Drawing.Color]::FromArgb(65, 65, 69)
    Border = [System.Drawing.Color]::FromArgb(56, 56, 60)
    Accent = [System.Drawing.Color]::FromArgb(10, 132, 255)
    AccentHover = [System.Drawing.Color]::FromArgb(64, 156, 255)
    AccentSurface = [System.Drawing.Color]::FromArgb(21, 52, 83)
    OnAccent = [System.Drawing.Color]::White
    Blue = [System.Drawing.Color]::FromArgb(100, 168, 255)
    Online = [System.Drawing.Color]::FromArgb(48, 209, 88)
    Text = [System.Drawing.Color]::FromArgb(242, 242, 247)
    Muted = [System.Drawing.Color]::FromArgb(161, 161, 166)
    Danger = [System.Drawing.Color]::FromArgb(255, 105, 97)
    DangerSurface = [System.Drawing.Color]::FromArgb(67, 36, 43)
}
$script:Brushes = @{
    Canvas = New-Object System.Drawing.SolidBrush($script:Ui.Canvas)
    Surface = New-Object System.Drawing.SolidBrush($script:Ui.Surface)
    Raised = New-Object System.Drawing.SolidBrush($script:Ui.Raised)
    Accent = New-Object System.Drawing.SolidBrush($script:Ui.Accent)
}
$script:BodyFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$script:StrongFont = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Regular)
$script:TitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Regular)
$script:PageTitleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Regular)
$script:CaptionFont = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)

function Set-ActionButton {
    param(
        [WProxy.SmoothButton]$Button,
        [ValidateSet('Primary', 'Secondary', 'Danger', 'Navigation')][string]$Kind = 'Secondary'
    )
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Font = $script:StrongFont
    $Button.Height = 36
    $Button.AutoSize = $false
    $Button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    $Button.CornerRadius = 8
    $Button.BorderSize = 0
    $Button.BorderColor = [System.Drawing.Color]::Transparent
    switch ($Kind) {
        'Primary' {
            $Button.FillColor = $script:Ui.Accent
            $Button.HoverColor = $script:Ui.AccentHover
            $Button.PressedColor = [System.Drawing.Color]::FromArgb(143, 172, 248)
            $Button.ForeColor = $script:Ui.OnAccent
        }
        'Danger' {
            $Button.FillColor = $script:Ui.DangerSurface
            $Button.HoverColor = [System.Drawing.Color]::FromArgb(61, 39, 45)
            $Button.PressedColor = [System.Drawing.Color]::FromArgb(40, 28, 32)
            $Button.ForeColor = $script:Ui.Danger
        }
        'Navigation' {
            $Button.FillColor = $script:Ui.Sidebar
            $Button.HoverColor = $script:Ui.Raised
            $Button.PressedColor = $script:Ui.Surface
            $Button.ForeColor = $script:Ui.Muted
            $Button.TextAlign = 'MiddleLeft'
            $Button.Padding = New-Object System.Windows.Forms.Padding(18, 0, 10, 0)
            $Button.CornerRadius = 7
        }
        default {
            $Button.FillColor = $script:Ui.Raised
            $Button.HoverColor = $script:Ui.RaisedHover
            $Button.PressedColor = $script:Ui.Surface
            $Button.ForeColor = $script:Ui.Text
        }
    }
    $Button.Invalidate()
}

function Set-InputStyle([System.Windows.Forms.Control]$Control) {
    $Control.BackColor = $script:Ui.Surface
    $Control.ForeColor = $script:Ui.Text
    $Control.Font = $script:BodyFont
    if ($Control -is [System.Windows.Forms.TextBoxBase] -or
        $Control -is [System.Windows.Forms.ListBox]) {
        $Control.BorderStyle = 'FixedSingle'
    }
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
    $List.BorderStyle = 'None'
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
$form.Text = 'WProxy 2.7.0'
$form.Size = New-Object System.Drawing.Size(1080, 740)
$form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:Ui.Canvas
$form.ForeColor = $script:Ui.Text
$form.Font = $script:BodyFont
$form.AutoScaleMode = 'Dpi'
$form.KeyPreview = $true
$iconPath = Join-Path $script:Root 'icons\wproxy.ico'
if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
$form.Add_HandleCreated({ Enable-DarkTitleBar $form })

$shell = New-Object System.Windows.Forms.TableLayoutPanel
$shell.Name = 'AppShell'
$shell.Dock = 'Fill'
$shell.Margin = New-Object System.Windows.Forms.Padding(0)
$shell.Padding = New-Object System.Windows.Forms.Padding(0)
$shell.ColumnCount = 2
$shell.RowCount = 1
$shell.BackColor = $script:Ui.Canvas
$shell.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 200)))
$shell.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
$shell.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
$form.Controls.Add($shell)

$navigationRail = New-Object System.Windows.Forms.TableLayoutPanel
$navigationRail.Name = 'NavigationRail'
$navigationRail.Dock = 'Fill'
$navigationRail.Margin = New-Object System.Windows.Forms.Padding(0)
$navigationRail.Padding = New-Object System.Windows.Forms.Padding(14, 18, 14, 12)
$navigationRail.ColumnCount = 1
$navigationRail.RowCount = 3
$navigationRail.BackColor = $script:Ui.Sidebar
$navigationRail.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 102)))
$navigationRail.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
$navigationRail.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 72)))
$shell.Controls.Add($navigationRail, 0, 0)

$brandPanel = New-Object System.Windows.Forms.Panel
$brandPanel.Dock = 'Fill'
$brandPanel.BackColor = $script:Ui.Sidebar
$navigationRail.Controls.Add($brandPanel, 0, 0)
$brandMark = New-Object WProxy.SmoothPanel
$brandMark.FillColor = $script:Ui.Accent
$brandMark.BorderColor = [System.Drawing.Color]::Transparent
$brandMark.CornerRadius = 10
$brandMark.Size = New-Object System.Drawing.Size(44, 44)
$brandMark.Location = New-Object System.Drawing.Point(0, 0)
$brandMarkLabel = New-Object System.Windows.Forms.Label
$brandMarkLabel.Text = 'W'
$brandMarkLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Regular)
$brandMarkLabel.TextAlign = 'MiddleCenter'
$brandMarkLabel.BackColor = [System.Drawing.Color]::Transparent
$brandMarkLabel.ForeColor = $script:Ui.OnAccent
$brandMarkLabel.Dock = 'Fill'
$brandMark.Controls.Add($brandMarkLabel)
$brandPanel.Controls.Add($brandMark)
$brandTitle = New-Object System.Windows.Forms.Label
$brandTitle.Text = 'WProxy'
$brandTitle.Font = $script:StrongFont
$brandTitle.ForeColor = $script:Ui.Text
$brandTitle.AutoSize = $true
$brandTitle.Location = New-Object System.Drawing.Point(0, 54)
$brandPanel.Controls.Add($brandTitle)
$brandSubtitle = New-Object System.Windows.Forms.Label
$brandSubtitle.Text = 'Secure connection'
$brandSubtitle.Font = $script:CaptionFont
$brandSubtitle.ForeColor = $script:Ui.Muted
$brandSubtitle.AutoSize = $true
$brandSubtitle.Location = New-Object System.Drawing.Point(0, 76)
$brandPanel.Controls.Add($brandSubtitle)

$navigationButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$navigationButtons.Dock = 'Fill'
$navigationButtons.FlowDirection = 'TopDown'
$navigationButtons.WrapContents = $false
$navigationButtons.BackColor = $script:Ui.Sidebar
$navigationButtons.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
$navigationRail.Controls.Add($navigationButtons, 0, 1)
$script:NavButtons = @{}
foreach ($definition in @(
    @('servers', 'Home'),
    @('subscriptions', 'Subscriptions'),
    @('add', 'Add connection'),
    @('routing', 'Advanced')
)) {
    $button = New-Object WProxy.SmoothButton
    $button.Name = 'Nav' + $definition[0]
    $button.Tag = $definition[0]
    $button.Text = $definition[1]
    $button.Width = 168
    $button.Height = 40
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    Set-ActionButton $button 'Navigation'
    $button.Height = 40
    $button.Add_Click({ param($sender, $eventArgs) Show-Page ([string]$sender.Tag) })
    $navigationButtons.Controls.Add($button)
    $script:NavButtons[$definition[0]] = $button
}
$sidebarFooter = New-Object System.Windows.Forms.Panel
$sidebarFooter.Dock = 'Fill'
$sidebarFooter.BackColor = $script:Ui.Sidebar
$navigationRail.Controls.Add($sidebarFooter, 0, 2)
$autoUpdateCheck = New-Object System.Windows.Forms.CheckBox
$autoUpdateCheck.Text = 'Automatic updates'
$autoUpdateCheck.AutoSize = $true
$autoUpdateCheck.FlatStyle = 'Flat'
$autoUpdateCheck.Font = $script:CaptionFont
$autoUpdateCheck.ForeColor = $script:Ui.Muted
$autoUpdateCheck.Location = New-Object System.Drawing.Point(0, 0)
$sidebarFooter.Controls.Add($autoUpdateCheck)
$sidebarVersion = New-Object System.Windows.Forms.Label
$sidebarVersion.Text = 'WProxy 2.7.0'
$sidebarVersion.AutoSize = $true
$sidebarVersion.Location = New-Object System.Drawing.Point(0, 34)
$sidebarVersion.Font = $script:CaptionFont
$sidebarVersion.ForeColor = $script:Ui.Muted
$sidebarVersion.BackColor = $script:Ui.Sidebar
$sidebarFooter.Controls.Add($sidebarVersion)

$contentRoot = New-Object System.Windows.Forms.Panel
$contentRoot.Name = 'ContentRoot'
$contentRoot.Dock = 'Fill'
$contentRoot.Margin = New-Object System.Windows.Forms.Padding(0)
$contentRoot.BackColor = $script:Ui.Canvas
$shell.Controls.Add($contentRoot, 1, 0)

$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.Name = 'PageHost'
$pageHost.Dock = 'Fill'
$pageHost.Padding = New-Object System.Windows.Forms.Padding(22, 4, 22, 14)
$pageHost.BackColor = $script:Ui.Canvas
$contentRoot.Controls.Add($pageHost)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 116
$header.BackColor = $script:Ui.Canvas
$header.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 10)
$contentRoot.Controls.Add($header)

$connectionCard = New-Object WProxy.SmoothPanel
$connectionCard.Dock = 'Fill'
$connectionCard.FillColor = $script:Ui.Surface
$connectionCard.BorderColor = $script:Ui.Border
$connectionCard.BorderSize = 1
$connectionCard.CornerRadius = 12
$connectionCard.Add_Resize({
    param($sender, $eventArgs)
    $connectionState.Width = [Math]::Max(100, $sender.ClientSize.Width - 120)
    $connectionDetail.Width = [Math]::Max(100, $sender.ClientSize.Width - 120)
})
$connectionDotPanel = New-Object WProxy.SmoothPanel
$connectionDotPanel.Size = New-Object System.Drawing.Size(42, 42)
$connectionDotPanel.Location = New-Object System.Drawing.Point(18, 20)
$connectionDotPanel.FillColor = $script:Ui.AccentSurface
$connectionDotPanel.BorderColor = [System.Drawing.Color]::Transparent
$connectionDotPanel.CornerRadius = 9
$connectionCard.Controls.Add($connectionDotPanel)
$connectionDot = New-Object System.Windows.Forms.Label
$connectionDot.Text = [char]0x25CF
$connectionDot.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Regular)
$connectionDot.ForeColor = $script:Ui.Muted
$connectionDot.Dock = 'Fill'
$connectionDot.TextAlign = 'MiddleCenter'
$connectionDotPanel.Controls.Add($connectionDot)
$connectionEyebrow = New-Object System.Windows.Forms.Label
$connectionEyebrow.Text = 'VPN CONNECTION'
$connectionEyebrow.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8, [System.Drawing.FontStyle]::Regular)
$connectionEyebrow.ForeColor = $script:Ui.AccentHover
$connectionEyebrow.AutoSize = $true
$connectionEyebrow.Location = New-Object System.Drawing.Point(76, 15)
$connectionCard.Controls.Add($connectionEyebrow)
$connectionState = New-Object System.Windows.Forms.Label
$connectionState.Text = 'Not connected'
$connectionState.Font = $script:PageTitleFont
$connectionState.ForeColor = $script:Ui.Text
$connectionState.AutoEllipsis = $true
$connectionState.Size = New-Object System.Drawing.Size(640, 32)
$connectionState.Location = New-Object System.Drawing.Point(74, 32)
$connectionCard.Controls.Add($connectionState)
$connectionDetail = New-Object System.Windows.Forms.Label
$connectionDetail.Text = 'Choose a server or let WProxy pick the fastest one'
$connectionDetail.Font = $script:CaptionFont
$connectionDetail.ForeColor = $script:Ui.Muted
$connectionDetail.AutoEllipsis = $true
$connectionDetail.Size = New-Object System.Drawing.Size(640, 20)
$connectionDetail.Location = New-Object System.Drawing.Point(76, 65)
$connectionCard.Controls.Add($connectionDetail)
$header.Controls.Add($connectionCard)
$header.BringToFront()

$script:Pages = @{}
function Show-Page([string]$Name) {
    if (-not $script:Pages.ContainsKey($Name)) { return }
    foreach ($key in @($script:Pages.Keys)) { $script:Pages[$key].Visible = $false }
    foreach ($key in @($script:NavButtons.Keys)) {
        $active = ($key -eq $Name)
        $button = $script:NavButtons[$key]
        $button.FillColor = if ($active) { $script:Ui.Accent } else { $script:Ui.Sidebar }
        $button.HoverColor = if ($active) { $script:Ui.AccentHover } else { $script:Ui.Raised }
        $button.ForeColor = if ($active) { $script:Ui.OnAccent } else { $script:Ui.Muted }
        $button.Invalidate()
    }
    $page = $script:Pages[$Name]
    $page.Visible = $true
    $page.BringToFront()
}

$nodesTab = New-Object System.Windows.Forms.Panel
$nodesTab.Name = 'ServersPage'
$nodesTab.BackColor = $script:Ui.Canvas
$nodesTab.ForeColor = $script:Ui.Text
$nodesTab.Padding = New-Object System.Windows.Forms.Padding(0)
$nodesTab.Dock = 'Fill'
$nodesTab.Visible = $false
$pageHost.Controls.Add($nodesTab)
$script:Pages['servers'] = $nodesTab

$nodesHeader = New-PageHeader 'Connection' 'Pick a server, or use Quick connect for the lowest latency.'
$nodesHeader.Dock = 'Top'
$nodesHeader.Height = 64
$nodesHeader.BackColor = $script:Ui.Canvas
$nodesTab.Controls.Add($nodesHeader)

$nodeBody = New-Object System.Windows.Forms.Panel
$nodeBody.Dock = 'Fill'
$nodeBody.BackColor = $script:Ui.Canvas
$nodesTab.Controls.Add($nodeBody)

$nodeList = New-Object System.Windows.Forms.ListView
$nodeList.Dock = 'Fill'
$nodeList.View = 'Details'
$nodeList.FullRowSelect = $true
$nodeList.MultiSelect = $false
$nodeList.Columns.Add('SERVER', 360) | Out-Null
$nodeList.Columns.Add('SOURCE', 300) | Out-Null
$nodeList.Columns.Add('LATENCY', 120) | Out-Null
Set-ListStyle $nodeList
$nodeList.Add_Resize({
    $available = [Math]::Max(420, $nodeList.ClientSize.Width - 4)
    $nodeList.Columns[0].Width = [int]($available * 0.46)
    $nodeList.Columns[1].Width = [int]($available * 0.34)
    $nodeList.Columns[2].Width = [Math]::Max(92, $available - $nodeList.Columns[0].Width - $nodeList.Columns[1].Width)
})
$nodeBody.Controls.Add($nodeList)

$nodeEmpty = New-Object System.Windows.Forms.Panel
$nodeEmpty.Name = 'ServersEmptyState'
$nodeEmpty.Dock = 'Fill'
$nodeEmpty.BackColor = $script:Ui.Canvas
$nodeEmpty.Visible = $false
$emptyTitle = New-Object System.Windows.Forms.Label
$emptyTitle.Text = 'No servers yet'
$emptyTitle.Font = $script:PageTitleFont
$emptyTitle.ForeColor = $script:Ui.Text
$emptyTitle.AutoSize = $true
$nodeEmpty.Controls.Add($emptyTitle)
$emptyHint = New-Object System.Windows.Forms.Label
$emptyHint.Text = 'Add a connection link or subscription to get started.'
$emptyHint.Font = $script:CaptionFont
$emptyHint.ForeColor = $script:Ui.Muted
$emptyHint.AutoSize = $true
$nodeEmpty.Controls.Add($emptyHint)
$emptyAddButton = New-Object WProxy.SmoothButton
$emptyAddButton.Text = 'Add connection'
$emptyAddButton.Size = New-Object System.Drawing.Size(156, 40)
Set-ActionButton $emptyAddButton 'Primary'
$emptyAddButton.Height = 40
$emptyAddButton.Add_Click({ Show-Page 'add' })
$nodeEmpty.Controls.Add($emptyAddButton)
$nodeEmpty.Add_Resize({
    $centerX = [Math]::Max(0, [int](($nodeEmpty.ClientSize.Width - $emptyTitle.Width) / 2))
    $centerY = [Math]::Max(32, [int](($nodeEmpty.ClientSize.Height - 126) / 2))
    $emptyTitle.Location = New-Object System.Drawing.Point($centerX, $centerY)
    $emptyHint.Location = New-Object System.Drawing.Point(
        ([Math]::Max(0, [int](($nodeEmpty.ClientSize.Width - $emptyHint.Width) / 2))), ($centerY + 40))
    $emptyAddButton.Location = New-Object System.Drawing.Point(
        ([Math]::Max(0, [int](($nodeEmpty.ClientSize.Width - $emptyAddButton.Width) / 2))), ($centerY + 76))
})
$nodeBody.Controls.Add($nodeEmpty)

$nodeButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$nodeButtons.Dock = 'Top'
$nodeButtons.Height = 56
$nodeButtons.FlowDirection = 'LeftToRight'
$nodeButtons.WrapContents = $false
$nodeButtons.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 8)
$nodeButtons.BackColor = $script:Ui.Canvas
$nodesTab.Controls.Add($nodeButtons)
foreach ($definition in @(
    @('Quick connect', 'Best', 'Primary', 132),
    @('Connect', 'Connect', 'Secondary', 100),
    @('Disconnect', 'Disconnect', 'Danger', 108),
    @('Ping all', 'Ping', 'Secondary', 96),
    @('Refresh', 'Refresh', 'Secondary', 92),
    @('Remove', 'Remove', 'Secondary', 92)
)) {
    $button = New-Object WProxy.SmoothButton
    $button.Text = $definition[0]
    $button.Name = $definition[1]
    $button.Width = $definition[3]
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    Set-ActionButton $button $definition[2]
    $nodeButtons.Controls.Add($button)
}
$nodeButtons.BringToFront()
$nodesHeader.BringToFront()

$addTab = New-Object System.Windows.Forms.Panel
$addTab.Name = 'AddConnectionPage'
$addTab.BackColor = $script:Ui.Canvas
$addTab.ForeColor = $script:Ui.Text
$addTab.Dock = 'Fill'
$addTab.Visible = $false
$pageHost.Controls.Add($addTab)
$script:Pages['add'] = $addTab
$addPanel = New-Object System.Windows.Forms.TableLayoutPanel
$addPanel.Dock = 'Fill'
$addPanel.Padding = New-Object System.Windows.Forms.Padding(28, 22, 28, 22)
$addPanel.ColumnCount = 1
$addPanel.RowCount = 11
$addPanel.AutoScroll = $true
$addPanel.BackColor = $script:Ui.Canvas
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
$addNodeButton = New-Object WProxy.SmoothButton
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
$addSubButton = New-Object WProxy.SmoothButton
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

$subsTab = New-Object System.Windows.Forms.Panel
$subsTab.Name = 'SubscriptionsPage'
$subsTab.BackColor = $script:Ui.Canvas
$subsTab.ForeColor = $script:Ui.Text
$subsTab.Padding = New-Object System.Windows.Forms.Padding(0)
$subsTab.Dock = 'Fill'
$subsTab.Visible = $false
$pageHost.Controls.Add($subsTab)
$script:Pages['subscriptions'] = $subsTab
$subsHeader = New-PageHeader 'Subscriptions' 'Update providers independently and see how many servers each source owns.'
$subsHeader.Dock = 'Top'
$subsHeader.Height = 64
$subsHeader.BackColor = $script:Ui.Canvas
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
$subList.Add_Resize({
    $available = [Math]::Max(420, $subList.ClientSize.Width - 4)
    $subList.Columns[0].Width = [int]($available * 0.56)
    $subList.Columns[1].Width = [int]($available * 0.16)
    $subList.Columns[2].Width = [Math]::Max(120, $available - $subList.Columns[0].Width - $subList.Columns[1].Width)
})
$subsTab.Controls.Add($subList)
$subButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$subButtons.Dock = 'Bottom'
$subButtons.Height = 62
$subButtons.Padding = New-Object System.Windows.Forms.Padding(0, 13, 0, 8)
$subButtons.BackColor = $script:Ui.Canvas
$subsTab.Controls.Add($subButtons)
foreach ($definition in @(
    @('Update selected', 'UpdateSelected', 'Primary', 148),
    @('Update all', 'UpdateAll', 'Secondary', 112),
    @('Remove', 'RemoveSelected', 'Danger', 104)
)) {
    $button = New-Object WProxy.SmoothButton
    $button.Text = $definition[0]
    $button.Name = $definition[1]
    $button.Width = $definition[3]
    $button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    Set-ActionButton $button $definition[2]
    $subButtons.Controls.Add($button)
}

$routingTab = New-Object System.Windows.Forms.Panel
$routingTab.Name = 'SplitRoutingPage'
$routingTab.BackColor = $script:Ui.Canvas
$routingTab.ForeColor = $script:Ui.Text
$routingTab.Padding = New-Object System.Windows.Forms.Padding(0)
$routingTab.Dock = 'Fill'
$routingTab.Visible = $false
$pageHost.Controls.Add($routingTab)
$script:Pages['routing'] = $routingTab
$routingHeader = New-PageHeader 'Routing' 'Choose what uses the tunnel. Changes apply on the next connection.'
$routingHeader.Dock = 'Top'
$routingHeader.Height = 64
$routingHeader.BackColor = $script:Ui.Canvas
$routingTab.Controls.Add($routingHeader)
$routingPanel = New-Object System.Windows.Forms.TableLayoutPanel
$routingPanel.Dock = 'Fill'
$routingPanel.Padding = New-Object System.Windows.Forms.Padding(0)
$routingPanel.BackColor = $script:Ui.Canvas
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
$appLabel.Text = 'Applications'
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
$appHint = New-Object System.Windows.Forms.Label
$appHint.Text = 'Pick a running app or browse to its .exe file.'
$appHint.Dock = 'Fill'
$appHint.Margin = New-Object System.Windows.Forms.Padding(8, 3, 0, 5)
$appHint.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$appHint.TextAlign = 'MiddleLeft'
$appHint.Font = $script:CaptionFont
$appHint.ForeColor = $script:Ui.Muted
$appHint.BackColor = $script:Ui.Surface
$routingPanel.Controls.Add($domainBox, 0, 4)
$routingPanel.Controls.Add($appHint, 1, 4)
$domainButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$domainButtons.Dock = 'Fill'
$domainButtons.BackColor = $script:Ui.Canvas
$domainButtons.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$addDomainButton = New-Object WProxy.SmoothButton
$addDomainButton.Text = 'Add site'
$addDomainButton.Width = 104
Set-ActionButton $addDomainButton 'Primary'
$removeDomainButton = New-Object WProxy.SmoothButton
$removeDomainButton.Text = 'Remove'
$removeDomainButton.Width = 104
Set-ActionButton $removeDomainButton 'Secondary'
$domainButtons.Controls.Add($addDomainButton); $domainButtons.Controls.Add($removeDomainButton)
$appButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$appButtons.Dock = 'Fill'
$appButtons.BackColor = $script:Ui.Canvas
$appButtons.Padding = New-Object System.Windows.Forms.Padding(8, 4, 0, 0)
$appButtons.WrapContents = $false
$pickAppButton = New-Object WProxy.SmoothButton
$pickAppButton.Text = 'Choose application...'
$pickAppButton.Width = 164
Set-ActionButton $pickAppButton 'Primary'
$removeAppButton = New-Object WProxy.SmoothButton
$removeAppButton.Text = 'Remove'
$removeAppButton.Width = 92
Set-ActionButton $removeAppButton 'Secondary'
$appButtons.Controls.Add($pickAppButton); $appButtons.Controls.Add($removeAppButton)
$routingPanel.Controls.Add($domainButtons, 0, 5)
$routingPanel.Controls.Add($appButtons, 1, 5)
$routingNote = New-Object System.Windows.Forms.Label
$routingNote.Text = 'Reconnect after changes. Exact executable paths give the most reliable app matching.'
$routingNote.Font = $script:CaptionFont
$routingNote.ForeColor = $script:Ui.Muted
$routingNote.AutoSize = $true
$routingPanel.SetColumnSpan($routingNote, 2)
$routingPanel.Controls.Add($routingNote, 0, 6)

$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = 'Bottom'
$statusBar.Height = 30
$statusBar.BackColor = $script:Ui.Canvas
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Ready  |  Disconnected'
$statusLabel.Dock = 'Fill'
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(28, 0, 0, 0)
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Font = $script:CaptionFont
$statusLabel.ForeColor = $script:Ui.Muted
$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = 'Windows TUN'
$versionLabel.Dock = 'Right'
$versionLabel.Width = 126
$versionLabel.Padding = New-Object System.Windows.Forms.Padding(0, 0, 24, 0)
$versionLabel.TextAlign = 'MiddleRight'
$versionLabel.Font = $script:CaptionFont
$versionLabel.ForeColor = $script:Ui.Muted
$statusBar.Controls.Add($statusLabel)
$statusBar.Controls.Add($versionLabel)
$form.Controls.Add($statusBar)
$shell.SendToBack()
$statusBar.BringToFront()
$header.BringToFront()
$nodesHeader.BringToFront()
$subsHeader.BringToFront()
$routingHeader.BringToFront()
Show-Page 'servers'

if ($LayoutSmokeTest) {
    $form.CreateControl()
    $form.PerformLayout()
    $shell.PerformLayout()
    $navigationRail.PerformLayout()
    $contentRoot.PerformLayout()
    $pageHost.PerformLayout()
    if ($navigationRail.Width -lt 200) { throw 'Windows navigation rail collapsed during layout.' }
    if ($pageHost.Width -lt 500) { throw 'Windows page host collapsed during layout.' }
    if ($script:NavButtons.Count -ne 4 -or $script:Pages.Count -ne 4) {
        throw 'Windows navigation did not create all primary pages.'
    }
    if ($script:NavButtons['servers'].Height -lt 40) { throw 'Windows navigation targets are too small.' }
    Show-Page 'routing'
    $routingTab.PerformLayout()
    $routingPanel.PerformLayout()
    $appButtons.PerformLayout()
    if ($pickAppButton.Parent -ne $appButtons -or $pickAppButton.Width -lt 150) {
        throw 'Windows application picker is not usable in the routing layout.'
    }
    if (($pickAppButton.Right -gt $appButtons.ClientSize.Width) -or
        ($removeAppButton.Right -gt $appButtons.ClientSize.Width)) {
        throw 'Windows routing actions are clipped at the default window size.'
    }
    Write-Output ('Windows layout smoke test: PASS ({0}x{1} navigation, {2}x{3} content)' -f `
        $navigationRail.Width, $navigationRail.Height, $pageHost.Width, $pageHost.Height)
    $form.Dispose()
    foreach ($brush in $script:Brushes.Values) { $brush.Dispose() }
    exit 0
}

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
        if ($routing.mode -eq 'only' -and $routing.domains.Count -eq 0 -and $routing.apps.Count -eq 0) {
            $routingNote.Text = 'Nothing is listed, so all traffic stays direct. Add a site or application, then reconnect.'
            $routingNote.ForeColor = $script:Ui.Danger
        } else {
            $routingNote.Text = 'Reconnect after changes. Exact executable paths give the most reliable app matching.'
            $routingNote.ForeColor = $script:Ui.Muted
        }
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
    $browse = New-Object WProxy.SmoothButton; $browse.Text = 'Browse .exe...'; $browse.Width = 132
    $addSelected = New-Object WProxy.SmoothButton; $addSelected.Text = 'Add selected'; $addSelected.Width = 132
    $cancel = New-Object WProxy.SmoothButton; $cancel.Text = 'Cancel'; $cancel.Width = 96
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
    $hasNodes = ($nodes.Count -gt 0)
    $nodeList.Visible = $hasNodes
    $nodeEmpty.Visible = -not $hasNodes
    if (-not $hasNodes) { $nodeEmpty.BringToFront() }
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
        $connectionDot.ForeColor = $script:Ui.Online
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
        $connectionState.Text = 'Not connected'
        $connectionDetail.Text = 'Choose a server or let WProxy pick the fastest one'
        $connectionDot.ForeColor = $script:Ui.Muted
        $tray.Text = 'WProxy - Disconnected'
        $disconnectItem.Enabled = $false
    }
    $nodeList.Invalidate()
}

function Refresh-All { Refresh-Status; Refresh-Nodes @{}; Refresh-Subscriptions; Refresh-Routing }

function Start-AutomaticUpdate {
    if (-not $autoUpdateCheck.Checked) { return }
    if (-not (Start-CtlDetached @('update', 'auto', '--platform', 'windows', '--json'))) {
        $statusLabel.Text = 'Could not start the automatic update check'
    }
}

$script:PreferencesLoading = $true
$preferencesResult = Invoke-Ctl @('settings', 'show', '--json')
if ($preferencesResult.Code -eq 0) {
    try { $autoUpdateCheck.Checked = [bool]($preferencesResult.Output | ConvertFrom-Json).auto_update }
    catch { $autoUpdateCheck.Checked = $false }
}
$script:PreferencesLoading = $false
$autoUpdateCheck.Add_CheckedChanged({
    if ($script:PreferencesLoading) { return }
    $value = if ($autoUpdateCheck.Checked) { 'true' } else { 'false' }
    $result = Invoke-Ctl @('settings', 'set', 'auto_update', $value)
    if ($result.Code -ne 0) {
        Show-Error $result.Output
        $script:PreferencesLoading = $true
        $autoUpdateCheck.Checked = -not $autoUpdateCheck.Checked
        $script:PreferencesLoading = $false
        return
    }
    $statusLabel.Text = if ($autoUpdateCheck.Checked) { 'Automatic updates enabled' } else { 'Automatic updates disabled' }
    if ($autoUpdateCheck.Checked) { Start-AutomaticUpdate }
})

$nodeButtons.Controls['Refresh'].Add_Click({ Refresh-All })
$nodeButtons.Controls['Best'].Add_Click({
    $statusLabel.Text = 'Testing servers...'
    $result = Invoke-Ctl @('node', 'best', '--json', '--timeout', '1.5')
    if ($result.Code -ne 0) { Show-Error $result.Output; $statusLabel.Text = 'No reachable server'; return }
    try { $best = $result.Output | ConvertFrom-Json }
    catch { Show-Error 'WProxy could not read the fastest server result.'; return }
    $statusLabel.Text = ('Connecting to {0} ({1} ms)...' -f $best.name, $best.latency_ms)
    if ((Invoke-AdminCtl @('windows', 'up', [string]$best.id)) -eq 0) { Refresh-Status }
})
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
    $uriBox.Clear(); Refresh-Nodes @{}; Show-Page 'servers'
})
$addSubButton.Add_Click({
    if (-not $subBox.Text.Trim()) { return }
    $added = Invoke-Ctl @('sub', 'add', $subBox.Text.Trim())
    if ($added.Code -ne 0) { Show-Error $added.Output; return }
    $updated = Invoke-Ctl @('sub', 'update', $added.Output.Trim())
    if ($updated.Code -ne 0) { Show-Error $updated.Output; return }
    $subBox.Clear(); Refresh-Nodes @{}; Refresh-Subscriptions; Show-Page 'servers'
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
    else { Refresh-Routing }
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
$pickAppButton.Add_Click({ Show-AppPicker })
$removeAppButton.Add_Click({
    if ($null -eq $appList.SelectedItem) { return }
    $result = Invoke-Ctl @('routing', 'app', 'remove', [string]$appList.SelectedItem)
    if ($result.Code -ne 0) { Show-Error $result.Output; return }
    Refresh-Routing
})

$showWindow = {
    $form.Show()
    $form.WindowState = 'Normal'
    Refresh-All
    $timer.Start()
    $form.Activate()
}
$showItem.Add_Click($showWindow)
$tray.Add_DoubleClick($showWindow)
$disconnectItem.Add_Click({ if ((Invoke-AdminCtl @('windows', 'down')) -eq 0) { Refresh-Status } })
$exitItem.Add_Click({ $script:Exiting = $true; $tray.Visible = $false; $form.Close(); [System.Windows.Forms.Application]::ExitThread() })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if (-not $script:Exiting) {
        $eventArgs.Cancel = $true
        $timer.Stop()
        $form.Hide()
        $tray.ShowBalloonTip(1800, 'WProxy is still running', 'Double-click the tray icon to open it again.', 'Info')
    }
})
$form.Add_Resize({
    if ($form.WindowState -eq 'Minimized') { $timer.Stop(); $form.Hide() }
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
$timer.Interval = 15000
$timer.Add_Tick({
    try { Refresh-Status }
    catch {
        $statusLabel.Text = 'Status refresh failed'
        $connectionDot.ForeColor = $script:Ui.Danger
    }
})
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
        $timer.Start()
        Start-AutomaticUpdate
    })
    $form.Show()
} else {
    try { Refresh-All }
    catch { $tray.Text = 'WProxy - status unavailable' }
    Start-AutomaticUpdate
}
[System.Windows.Forms.Application]::Run()
$tray.Dispose()
$form.Dispose()
foreach ($brush in $script:Brushes.Values) { $brush.Dispose() }
