# 灵感小宠物 — 无需安装的 Windows 桌面灵感收集器
# 平时是一个小圆球，点它展开成输入面板；Ctrl + Alt + I 随时唤出 / 收起
# 交互规则：小球可按住拖动；面板可按住空白处拖动；× 收起成球（宠物常驻屏幕）；
# 只有 Ctrl + Alt + I 能让整个宠物从屏幕消失 / 唤回
# 新版（2026-10-07）：标题 inspiration 手写体；新灵感默认进「未整理」；
# 收纳夹可自建 / 删除（删除后夹内灵感回到未整理）；垃圾桶 = 软删除，可恢复，
# 只有「真正删除」才永久移除。旧数据自动兼容：无 status 视为 active，旧夹子归入未整理。

# 进程保持系统 DPI 感知：WPF 按物理分辨率原生渲染，高 DPI 屏幕下文字不模糊。
# 拖拽代码会把鼠标物理坐标换算成 DIP 再移动窗口，坐标行为保持一致。
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DpiPin {
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
try { [DpiPin]::SetProcessDpiAwarenessContext([IntPtr](-2)) | Out-Null } catch {}
try { [DpiPin]::SetProcessDpiAwareness(1) | Out-Null } catch {}

# 启动后立即隐藏宿主控制台窗口：无论从 bat / 右键 / 命令行任何方式运行，都不显示 PowerShell 窗口
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ConHide {
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
$conHwnd = [ConHide]::GetConsoleWindow()
if ($conHwnd -ne [IntPtr]::Zero) { [void][ConHide]::ShowWindow($conHwnd, 0) }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$appDir = Split-Path -Parent $PSCommandPath
$dataDir = Join-Path $appDir 'data'
$ideasFile = Join-Path $dataDir 'ideas.jsonl'
$foldersFile = Join-Path $dataDir 'folders.json'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
if (-not (Test-Path $ideasFile)) { New-Item -ItemType File -Path $ideasFile | Out-Null }

# ================= 数据层 =================
function Get-Folders {
  if (Test-Path $foldersFile) {
    try {
      $parsed = [IO.File]::ReadAllText($foldersFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
      $list = @()
      foreach ($item in $parsed) {
        $name = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($name)) { $list += $name }
      }
      if ($list.Count -gt 0 -and $list -contains '未整理') { return ,$list }
    } catch {}
  }
  return ,@('未整理')
}
function Save-Folders {
  param([string[]]$folders)
  $json = ConvertTo-Json -InputObject @($folders) -Compress
  [IO.File]::WriteAllText($foldersFile, $json, (New-Object Text.UTF8Encoding $false))
}
function Read-Ideas {
  $all = @()
  if (Test-Path $ideasFile) {
    foreach ($line in [IO.File]::ReadAllLines($ideasFile, [Text.Encoding]::UTF8)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try { $o = $line | ConvertFrom-Json } catch { continue }
      if (-not $o.id) { $o | Add-Member -NotePropertyName id -NotePropertyValue ([guid]::NewGuid().ToString('N')) }
      if (-not $o.status) { $o | Add-Member -NotePropertyName status -NotePropertyValue 'active' }
      if (-not $o.folder) { $o | Add-Member -NotePropertyName folder -NotePropertyValue '未整理' }
      $all += $o
    }
  }
  return ,$all
}
function Write-Ideas {
  param([object[]]$items)
  $lines = @()
  foreach ($it in @($items)) {
    $e = [ordered]@{ created_at = [string]$it.created_at; folder = [string]$it.folder; idea = [string]$it.idea; status = [string]$it.status }
    if ($it.id) { $e['id'] = [string]$it.id }
    $lines += ($e | ConvertTo-Json -Compress)
  }
  if ($lines.Count -gt 0) { [IO.File]::WriteAllLines($ideasFile, $lines, (New-Object Text.UTF8Encoding $false)) }
  else { [IO.File]::WriteAllText($ideasFile, '', (New-Object Text.UTF8Encoding $false)) }
}
# 夹子已不存在的旧条目，一律按「未整理」展示
function Effective-Folder {
  param($o, [string[]]$folders)
  if ($folders -contains $o.folder) { return [string]$o.folder }
  return '未整理'
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PetHotkey {
  [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
  [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
'@

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="76" Height="76" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
  <Grid>
    <!-- 小球状态 -->
    <Border x:Name="BallButton" Width="56" Height="56" CornerRadius="28" HorizontalAlignment="Right" VerticalAlignment="Bottom"
            Margin="0,0,10,10" RenderTransformOrigin="0.5,0.5" Cursor="Hand"
            BorderBrush="#E2DCD0" BorderThickness="1.5">
      <Border.Style>
        <Style TargetType="Border">
          <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter Property="Opacity" Value="0.85"/>
            </Trigger>
          </Style.Triggers>
        </Style>
      </Border.Style>
      <Border.Background>
        <RadialGradientBrush>
          <GradientStop Color="#FFFFFFFF" Offset="0"/>
          <GradientStop Color="#FFFCFAF6" Offset="0.7"/>
          <GradientStop Color="#FFF1ECE2" Offset="1"/>
        </RadialGradientBrush>
      </Border.Background>
      <TextBlock Text="◕ ᴥ ◕" FontSize="16" Foreground="#7A5C40" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,2,0,0"/>
    </Border>
    <!-- 展开面板 -->
    <Border x:Name="Shell" Visibility="Collapsed" CornerRadius="22" Background="#FFFDF6" BorderBrush="#D9B478" BorderThickness="2" Padding="16">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="36"/></Grid.ColumnDefinitions>
        <StackPanel Grid.Row="0" Grid.Column="0" Orientation="Horizontal">
          <TextBlock Text="◕ ᴥ ◕" FontSize="28" Foreground="#835E33" VerticalAlignment="Center"/>
          <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="inspiration" FontFamily="Segoe Print" FontSize="26" FontWeight="Bold" Foreground="#4B3824"/>
            <TextBlock Text="把闪过的念头丢给我吧" FontSize="11" Foreground="#92775A"/>
          </StackPanel>
        </StackPanel>
        <Button x:Name="CloseButton" Grid.Row="0" Grid.Column="1" Content="×" FontSize="19" FontWeight="Bold" Foreground="#92775A" Background="Transparent" BorderThickness="0"/>
        <TextBox x:Name="IdeaBox" Grid.Row="1" Grid.ColumnSpan="2" Margin="0,10,0,10" Padding="10" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontSize="15" Foreground="#493727" Background="#FFF8E9" BorderBrush="#E5C58E" BorderThickness="1" ToolTip="写下一个 idea..."/>
        <StackPanel Grid.Row="2" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="HistoryButton" Content="看看以前的" Padding="10,5" Margin="0,0,8,0" Foreground="#6A5138" Background="Transparent" BorderBrush="#D9B478"/>
          <Button x:Name="SaveButton" Content="收下灵感  ↵" Padding="12,5" FontWeight="Bold" Foreground="White" Background="#BD7C3D" BorderThickness="0"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$ideaBox = $window.FindName('IdeaBox'); $save = $window.FindName('SaveButton')
$history = $window.FindName('HistoryButton'); $close = $window.FindName('CloseButton')
$ball = $window.FindName('BallButton'); $shell = $window.FindName('Shell')

# 屏幕优先的文字渲染：ClearType + Display 模式，小字号和手写体标题更锐利
[Windows.Media.TextOptions]::SetTextFormattingMode($window, 'Display')
[Windows.Media.TextOptions]::SetTextRenderingMode($window, 'ClearType')

# 两种状态的尺寸
$script:ballSize = 76
$script:panelW = 370
$script:panelH = 305
$script:parked = $false
$script:openDrawer = $null

# 切换窗口尺寸（瞬间完成，固定右下角；不用动画定时器，避免原生崩溃）
function Set-PetSize {
  param([double]$targetW, [double]$targetH, [scriptblock]$onDone)
  $wa = [Windows.SystemParameters]::WorkArea
  $curRight = $window.Left + $window.Width
  $curBottom = $window.Top + $window.Height
  $window.Width = $targetW
  $window.Height = $targetH
  $window.Left = [Math]::Max($wa.Left, [Math]::Min($curRight - $targetW, $wa.Right - $targetW))
  $window.Top = [Math]::Max($wa.Top, [Math]::Min($curBottom - $targetH, $wa.Bottom - $targetH))
  if ($onDone) { & $onDone }
}

function Expand-Pet {
  $shell.Visibility = 'Collapsed'
  $ball.Visibility = 'Visible'
  Set-PetSize $script:panelW $script:panelH {
    $ball.Visibility = 'Collapsed'
    $shell.Visibility = 'Visible'
    $null = $ideaBox.Focus()
  }
}

function Collapse-Pet {
  $shell.Visibility = 'Collapsed'
  $ball.Visibility = 'Visible'
  Set-PetSize $script:ballSize $script:ballSize { }
}

# 隐藏：把窗口移到屏幕外（不调用 Hide()，规避 WPF 透明窗口的原生崩溃）
function Hide-Pet {
  $wa = [Windows.SystemParameters]::WorkArea
  $window.Width = $script:ballSize; $window.Height = $script:ballSize
  $window.Left = $wa.Right + 30
  $window.Top = $wa.Top
  $script:parked = $true
}

# 唤出：先放回右下角小球位置，再展开成面板
function Show-Pet {
  $wa = [Windows.SystemParameters]::WorkArea
  $window.Width = $script:ballSize; $window.Height = $script:ballSize
  $window.Left = $wa.Right - $script:ballSize - 12
  $window.Top = $wa.Bottom - $script:ballSize - 12
  $script:parked = $false
  try { $null = $window.Activate() } catch {}
  Expand-Pet
}

function Save-Idea {
  $idea = $ideaBox.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($idea)) { return }
  $entry = [ordered]@{
    created_at = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    folder     = '未整理'
    idea       = $idea
    status     = 'active'
    id         = ([guid]::NewGuid().ToString('N'))
  } | ConvertTo-Json -Compress
  Add-Content -LiteralPath $ideasFile -Value $entry -Encoding UTF8
  $ideaBox.Text = ''
  $save.Content = '收好啦！ ✦'
  Start-Sleep -Milliseconds 650
  $save.Content = '收下灵感  ↵'
}

$save.Add_Click({ Save-Idea })
$ideaBox.Add_KeyDown({ if ($_.Key -eq 'Enter' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') { Save-Idea } })
$close.Add_Click({ Collapse-Pet })

# 把鼠标物理坐标换算成 DIP（高 DPI 屏幕下 Cursor.Position 是物理像素，Window.Left 是 DIP）
function Get-CursorDip {
  $d = [Windows.Media.VisualTreeHelper]::GetDpi($window)
  $inv = 1.0 / $d.DpiScaleX
  $c = [System.Windows.Forms.Cursor]::Position
  return @{ x = $c.X * $inv; y = $c.Y * $inv }
}

# 小球：按住移动=拖动窗口，原地点击=展开面板
$script:ballDrag = $null
$ball.Add_MouseLeftButtonDown({
  $c = Get-CursorDip
  $script:ballDrag = @{ sx = $c.x; sy = $c.y; wx = $window.Left; wy = $window.Top; dragging = $false }
  try { $ball.CaptureMouse() | Out-Null } catch {}
  $_.Handled = $true
})
$ball.Add_MouseMove({
  if ($script:ballDrag) {
    $c = Get-CursorDip
    $dx = $c.x - $script:ballDrag.sx; $dy = $c.y - $script:ballDrag.sy
    if (-not $script:ballDrag.dragging) {
      if ([Math]::Abs($dx) -ge 4 -or [Math]::Abs($dy) -ge 4) { $script:ballDrag.dragging = $true }
    }
    if ($script:ballDrag.dragging) {
      $window.Left = $script:ballDrag.wx + $dx
      $window.Top = $script:ballDrag.wy + $dy
    }
  }
})
$ball.Add_MouseLeftButtonUp({
  $wasDrag = $false
  if ($script:ballDrag) { $wasDrag = $script:ballDrag.dragging; $script:ballDrag = $null }
  if ($ball.IsMouseCaptured) { $ball.ReleaseMouseCapture() }
  if (-not $wasDrag) { Expand-Pet }
})

# ============ 收纳夹抽屉：脚本级辅助（异步事件里只能访问脚本级变量） ============

# 重建筛选下拉（各夹子 / 垃圾桶；「查看全部」用旁边的按钮）
function Reset-FilterCombo {
  param($ctl, $st)
  $ctl.Items.Clear()
  foreach ($f in $st.folders) { $null = $ctl.Items.Add($f) }
  $null = $ctl.Items.Add('垃圾桶')
  $idx = -1
  for ($i = 0; $i -lt $ctl.Items.Count; $i++) {
    if ([string]$ctl.Items[$i] -eq $st.filter) { $idx = $i; break }
  }
  if ($idx -lt 0) { $st.filter = '未整理'; $idx = 0 }
  $ctl.SelectedIndex = $idx
}

# 新建夹子输入框
function Show-FolderInput {
  param($ownerWin, $btnStyle2)
  $dlg = [Windows.Window]::new()
  $dlg.Title = '新建收纳夹'; $dlg.Width = 320
  $dlg.SizeToContent = [Windows.SizeToContent]::Height
  $dlg.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterOwner
  $dlg.Owner = $ownerWin; $dlg.ShowInTaskbar = $false
  $dlg.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFFDF6')
  $g = [Windows.Controls.Grid]::new(); $g.Margin = '18'
  $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
  $g.RowDefinitions[0].Height = 'Auto'
  $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
  $g.RowDefinitions[1].Height = '*'
  $g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null
  $g.RowDefinitions[2].Height = 'Auto'
  $lbl = [Windows.Controls.TextBlock]::new(); $lbl.Text = '新收纳夹的名字：'
  $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#4B3824'); $lbl.FontSize = 13
  [Windows.Controls.Grid]::SetRow($lbl, 0); $null = $g.Children.Add($lbl)
  $tb = [Windows.Controls.TextBox]::new(); $tb.Margin = '0,10,0,10'; $tb.FontSize = 14; $tb.MaxLength = 12
  [Windows.Controls.Grid]::SetRow($tb, 1); $null = $g.Children.Add($tb)
  $row = [Windows.Controls.StackPanel]::new(); $row.Orientation = 'Horizontal'; $row.HorizontalAlignment = 'Right'
  $ok = [Windows.Controls.Button]::new(); $ok.Content = '确定'; $ok.Padding = '16,7'; $ok.Margin = '0,0,8,0'
  $ok.FontSize = 13; $ok.FontWeight = 'Bold'; $ok.Foreground = 'White'
  $ok.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#BD7C3D')
  $ok.BorderThickness = '0'; $ok.Cursor = [Windows.Input.Cursors]::Hand; $ok.Style = $btnStyle2
  $cancel = [Windows.Controls.Button]::new(); $cancel.Content = '取消'; $cancel.Padding = '16,7'
  $cancel.FontSize = 13; $cancel.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6A5138')
  $cancel.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#F1E6CE')
  $cancel.BorderThickness = '0'; $cancel.Cursor = [Windows.Input.Cursors]::Hand; $cancel.Style = $btnStyle2
  $script:folderDlg = $dlg
  $ok.Add_Click({ $script:folderDlg.DialogResult = $true })
  $cancel.Add_Click({ $script:folderDlg.DialogResult = $false })
  $tb.Add_KeyDown({ if ($_.Key -eq 'Enter') { $script:folderDlg.DialogResult = $true } elseif ($_.Key -eq 'Escape') { $script:folderDlg.DialogResult = $false } })
  $null = $row.Children.Add($ok); $null = $row.Children.Add($cancel)
  [Windows.Controls.Grid]::SetRow($row, 2); $null = $g.Children.Add($row)
  $dlg.Content = $g
  $res = $dlg.ShowDialog()
  if ($res -eq $true) { return $tb.Text.Trim() }
  return $null
}

function Update-DrawerHeight {
  if ($null -eq $script:drDrawer -or $null -eq $script:drStack) { return }
  try {
    $script:drStack.Measure([Windows.Size]::new(452, [Double]::PositiveInfinity))
    $h0h = if ($script:drH0.ActualHeight -gt 0) { $script:drH0.ActualHeight } else { 40 }
    $h1h = if ($script:drH1.ActualHeight -gt 0) { $script:drH1.ActualHeight } else { 56 }
    $ch = [Math]::Ceiling($h0h + $h1h + $script:drStack.DesiredSize.Height + 48)
    if ($ch -lt 240) { $ch = 240 }
    if ($ch -gt 680) { $ch = 680 }
    if ($script:drDrawer.Height -ne $ch) { $script:drDrawer.Height = $ch }
  } catch {}
}

function Show-IdeaDrawer {
  # 打开收纳夹时先把主面板收成球：关掉抽屉就是球，不用再手动叉面板
  Collapse-Pet
  $state = @{
    items   = Read-Ideas
    folders = Get-Folders
    filter  = '未整理'
    allView = $false
  }

  $drawer = [Windows.Window]::new()
  $drawer.Title = '灵感收纳夹'
  $drawer.Width = 500; $drawer.MinWidth = 380; $drawer.MinHeight = 240; $drawer.MaxHeight = 680
  $drawer.Height = 600
  $drawer.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFFDF6')
  $drawer.Topmost = $true; $drawer.Owner = $window
  $script:openDrawer = $drawer
  $drawer.Add_Closed({ $script:openDrawer = $null })

  $grid = [Windows.Controls.Grid]::new(); $grid.Margin = '22,14,22,6'
  foreach ($h in @('Auto','Auto','Auto','*')) {
    $rd = [Windows.Controls.RowDefinition]::new(); $rd.Height = $h
    $null = $grid.RowDefinitions.Add($rd)
  }

  # 统一圆角按钮样式（圆角 + 悬停/按下反馈）
  $btnStyleXaml = @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
          </Trigger>
          <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="bd" Property="Opacity" Value="0.7"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@
  $btnStyle = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$btnStyleXaml)))

  # 行0：标题区（宠物脸 + 标题/副标题 + 新建夹子）
  $face = [Windows.Controls.TextBlock]::new()
  $face.Text = '◕ ᴥ ◕'; $face.FontSize = 26
  $face.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#835E33')
  $face.VerticalAlignment = 'Center'
  $title = [Windows.Controls.TextBlock]::new()
  $title.Text = '灵感收纳夹'; $title.FontSize = 20; $title.FontWeight = 'Bold'
  $title.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#4B3824')
  $titleCol = [Windows.Controls.StackPanel]::new(); $titleCol.Margin = '10,0,0,0'
  $titleCol.VerticalAlignment = 'Center'
  $null = $titleCol.Children.Add($title)
  $addBtn = [Windows.Controls.Button]::new()
  $addBtn.Content = '＋ 新建收纳夹'; $addBtn.FontSize = 13; $addBtn.FontWeight = 'Bold'
  $addBtn.Padding = '14,8'; $addBtn.Foreground = 'White'
  $addBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#BD7C3D')
  $addBtn.BorderThickness = '0'; $addBtn.Cursor = [Windows.Input.Cursors]::Hand
  $addBtn.Style = $btnStyle; $addBtn.VerticalAlignment = 'Center'
  $h0 = [Windows.Controls.Grid]::new()
  $null = $h0.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $null = $h0.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $h0.ColumnDefinitions[0].Width = '*'; $h0.ColumnDefinitions[1].Width = 'Auto'
  $h0L = [Windows.Controls.StackPanel]::new(); $h0L.Orientation = 'Horizontal'
  $null = $h0L.Children.Add($face); $null = $h0L.Children.Add($titleCol)
  [Windows.Controls.Grid]::SetColumn($h0L, 0); $null = $h0.Children.Add($h0L)
  [Windows.Controls.Grid]::SetColumn($addBtn, 1); $null = $h0.Children.Add($addBtn)
  [Windows.Controls.Grid]::SetRow($h0, 0); $null = $grid.Children.Add($h0)

  # 行1：筛选 + 查看全部 + 删除夹子（删除做成低调的文字按钮）
  $filter = [Windows.Controls.ComboBox]::new()
  $filter.Width = 170; $filter.Height = 24; $filter.FontSize = 12
  $filter.HorizontalAlignment = 'Left'; $filter.Padding = '6,0'; $filter.Background = 'White'
  $filter.VerticalContentAlignment = 'Center'
  $filter.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#D9C7A8')
  $allBtn = [Windows.Controls.Button]::new()
  $allBtn.Content = '查看全部'; $allBtn.FontSize = 12; $allBtn.FontWeight = 'Bold'; $allBtn.Padding = '10,6'
  $allBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6A5138')
  $allBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#F1E6CE')
  $allBtn.BorderThickness = '0'; $allBtn.Cursor = [Windows.Input.Cursors]::Hand; $allBtn.Style = $btnStyle
  $allBtn.Margin = '10,0,0,0'; $allBtn.VerticalAlignment = 'Center'
  $delFolderBtn = [Windows.Controls.Button]::new()
  $delFolderBtn.Content = '✕ 删除该夹'; $delFolderBtn.FontSize = 12
  $delFolderBtn.Padding = '8,4'; $delFolderBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#B4552D')
  $delFolderBtn.Background = 'Transparent'; $delFolderBtn.BorderThickness = '0'
  $delFolderBtn.Margin = '12,0,0,0'; $delFolderBtn.Cursor = [Windows.Input.Cursors]::Hand
  $delFolderBtn.Style = $btnStyle; $delFolderBtn.VerticalAlignment = 'Center'
  $h1 = [Windows.Controls.Grid]::new(); $h1.Margin = '0,12,0,0'
  $null = $h1.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $null = $h1.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $null = $h1.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
  $h1.ColumnDefinitions[0].Width = 'Auto'; $h1.ColumnDefinitions[1].Width = 'Auto'; $h1.ColumnDefinitions[2].Width = '*'
  [Windows.Controls.Grid]::SetColumn($filter, 0); $null = $h1.Children.Add($filter)
  [Windows.Controls.Grid]::SetColumn($allBtn, 1); $null = $h1.Children.Add($allBtn)
  [Windows.Controls.Grid]::SetColumn($delFolderBtn, 2); $null = $h1.Children.Add($delFolderBtn)
  $delFolderBtn.HorizontalAlignment = 'Right'
  [Windows.Controls.Grid]::SetRow($h1, 1); $null = $grid.Children.Add($h1)

  # 行2：列表
  $scroll = [Windows.Controls.ScrollViewer]::new(); $scroll.Margin = '0,10,0,0'
  $scroll.VerticalScrollBarVisibility = 'Auto'
  $stack = [Windows.Controls.StackPanel]::new(); $scroll.Content = $stack
  [Windows.Controls.Grid]::SetRow($scroll, 3); $null = $grid.Children.Add($scroll)

  $drawer.Content = $grid

  # 异步事件里只能访问脚本级变量：把抽屉状态与控件挂到脚本级别名上
  $script:dr = $state
  $script:drDrawer = $drawer
  $script:drBtnStyle = $btnStyle
  $script:drFilter = $filter
  $script:drAllBtn = $allBtn
  $script:drDelFolderBtn = $delFolderBtn
  $script:drStack = $stack
  $script:drH0 = $h0
  $script:drH1 = $h1

  # 全部视图里的小节标题
  $makeSection = {
    param($fname, $count)
    $sec = [Windows.Controls.StackPanel]::new(); $sec.Orientation = 'Horizontal'; $sec.Margin = '2,8,0,4'
    $dot = [Windows.Controls.TextBlock]::new(); $dot.Text = '◈'; $dot.FontSize = 11
    $dot.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#BD7C3D'); $dot.VerticalAlignment = 'Center'
    $lbl = [Windows.Controls.TextBlock]::new(); $lbl.Text = $fname + ' · ' + $count; $lbl.FontSize = 12
    $lbl.FontWeight = 'Bold'; $lbl.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#4B3824')
    $lbl.Margin = '6,0,0,0'; $lbl.VerticalAlignment = 'Center'
    $null = $sec.Children.Add($dot); $null = $sec.Children.Add($lbl)
    return $sec
  }

  # 构建单张卡片（inTrash 为真时是垃圾桶视图：恢复 / 真正删除）
  $makeCard = {
    param($it, $inTrash)
    $card = [Windows.Controls.Border]::new()
    $card.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFF9EC')
    $card.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#E8D9BA')
    $card.BorderThickness = '1'; $card.CornerRadius = '12'; $card.Padding = '14,10'; $card.Margin = '0,0,0,4'
    $card.Add_MouseEnter({ param($s, $e) $s.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#D9C7A8') })
    $card.Add_MouseLeave({ param($s, $e) $s.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#E8D9BA') })
    $content = [Windows.Controls.StackPanel]::new()
    $effF = Effective-Folder $it $script:dr.folders
    $meta = [Windows.Controls.StackPanel]::new(); $meta.Orientation = 'Horizontal'
    $tag = [Windows.Controls.Border]::new()
    $tag.CornerRadius = '6'; $tag.Padding = '8,2'
    $tagTxt = [Windows.Controls.TextBlock]::new()
    $tagTxt.FontSize = 11; $tagTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#8A5A2B')
    $tag.Child = $tagTxt
    $dateTxt = [Windows.Controls.TextBlock]::new()
    $dateTxt.FontSize = 11; $dateTxt.Margin = '8,0,0,0'
    $dateTxt.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#A08B6E')
    $body = [Windows.Controls.TextBlock]::new(); $body.Text = $it.idea; $body.TextWrapping = 'Wrap'
    $body.FontSize = 14; $body.LineHeight = 22
    $body.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#493727'); $body.Margin = '0,8,0,0'
    $acts = [Windows.Controls.StackPanel]::new(); $acts.Orientation = 'Horizontal'; $acts.Margin = '0,8,0,0'
    $acts.HorizontalAlignment = 'Right'
    if ($inTrash) {
      $tag.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#F5E7D2')
      $tagTxt.Text = '原来在「' + $effF + '」'
      $dateTxt.Text = $it.created_at
      $restore = [Windows.Controls.Button]::new(); $restore.Content = '恢复'; $restore.Padding = '12,4'; $restore.Margin = '0,0,8,0'
      $restore.FontSize = 12; $restore.FontWeight = 'Bold'
      $restore.Foreground = 'White'; $restore.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#BD7C3D')
      $restore.BorderThickness = '0'; $restore.Cursor = [Windows.Input.Cursors]::Hand; $restore.Style = $script:drBtnStyle
      $restore.Tag = $it
      $del = [Windows.Controls.Button]::new(); $del.Content = '真正删除'; $del.Padding = '12,4'
      $del.FontSize = 12; $del.Foreground = 'White'; $del.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#B4552D')
      $del.BorderThickness = '0'; $del.Cursor = [Windows.Input.Cursors]::Hand; $del.Style = $script:drBtnStyle
      $del.Tag = $it
      $restore.Add_Click({
        param($s, $e)
        $item = $s.Tag
        $item.status = 'active'
        if ($script:dr.folders -notcontains $item.folder) { $item.folder = '未整理' }
        Write-Ideas $script:dr.items
        & $script:drRender $script:drFilter.SelectedItem
      })
      $del.Add_Click({
        param($s, $e)
        $item = $s.Tag
        $r = [Windows.MessageBox]::Show($script:drDrawer, '真正删除后无法恢复，确定要删除这条灵感吗？', 'inspiration', [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Warning)
        if ($r -eq [Windows.MessageBoxResult]::Yes) {
          $script:dr.items = @($script:dr.items | Where-Object { $_ -ne $item })
          Write-Ideas $script:dr.items
          & $script:drRender $script:drFilter.SelectedItem
        }
      })
      $null = $acts.Children.Add($restore); $null = $acts.Children.Add($del)
    } else {
      $tag.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#F1E6CE')
      $tagTxt.Text = $effF
      $dateTxt.Text = $it.created_at
      $cat = [Windows.Controls.ComboBox]::new(); $cat.FontSize = 12; $cat.Margin = '0,0,6,0'; $cat.Width = 132
      $cat.Height = 22; $cat.Padding = '4,0'; $cat.Background = 'White'
      $cat.VerticalContentAlignment = 'Center'
      $cat.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#D9C7A8')
      foreach ($f in $script:dr.folders) { $null = $cat.Items.Add('放入「' + $f + '」') }
      $cat.Tag = $it
      $fi = [array]::IndexOf([string[]]$script:dr.folders, $effF)
      if ($fi -lt 0) { $fi = 0 }
      $cat.SelectedIndex = $fi
      $trashBtn = [Windows.Controls.Button]::new(); $trashBtn.Content = '垃圾桶'; $trashBtn.Padding = '12,4'
      $trashBtn.FontSize = 12; $trashBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#B4552D')
      $trashBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#F6E3D5')
      $trashBtn.BorderThickness = '0'; $trashBtn.Cursor = [Windows.Input.Cursors]::Hand; $trashBtn.Style = $script:drBtnStyle
      $trashBtn.Tag = $it
      $cat.Add_SelectionChanged({
        param($s, $e)
        $item = $s.Tag
        $f2 = $script:dr.folders[$s.SelectedIndex]
        if ($f2 -and $item.folder -ne $f2) {
          $item.folder = $f2
          Write-Ideas $script:dr.items
          & $script:drRender $script:drFilter.SelectedItem
        }
      })
      $trashBtn.Add_Click({
        param($s, $e)
        $item = $s.Tag
        $item.status = 'trashed'
        Write-Ideas $script:dr.items
        & $script:drRender $script:drFilter.SelectedItem
      })
      $null = $acts.Children.Add($cat); $null = $acts.Children.Add($trashBtn)
    }
    $null = $meta.Children.Add($tag); $null = $meta.Children.Add($dateTxt)
    $null = $content.Children.Add($meta); $null = $content.Children.Add($body); $null = $content.Children.Add($acts)
    $card.Child = $content
    return $card
  }

  # 渲染列表
  $render = {
    param($selected)
    $script:drStack.Children.Clear()
    $isTrash = ($selected -eq '垃圾桶')
    $script:drAllBtn.Visibility = if ($isTrash) { 'Collapsed' } else { 'Visible' }
    $script:drAllBtn.Content = if ($script:dr.allView) { '按夹子看' } else { '查看全部' }
    $script:drAllBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($script:dr.allView) { '#BD7C3D' } else { '#F1E6CE' }))
    $script:drAllBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($script:dr.allView) { 'White' } else { '#6A5138' }))
    if ($script:dr.allView) {
      # 全部视图：按夹子分组
      $script:drDelFolderBtn.Visibility = 'Collapsed'
      $groups = @{}
      $activeCount = 0
      foreach ($it in $script:dr.items) {
        if ($it.status -ne 'active') { continue }
        $activeCount++
        $eff = Effective-Folder $it $script:dr.folders
        if (-not $groups.ContainsKey($eff)) { $groups[$eff] = New-Object System.Collections.ArrayList }
        [void]$groups[$eff].Add($it)
      }
      if ($activeCount -eq 0) {
        $empty = [Windows.Controls.TextBlock]::new()
        $empty.Text = '还没有任何灵感。'
        $empty.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#92775A')
        $empty.Margin = '4'; $empty.FontSize = 13
        $null = $script:drStack.Children.Add($empty)
      } else {
        $order = @()
        foreach ($f in $script:dr.folders) { if ($groups.ContainsKey($f)) { $order += $f } }
        foreach ($k in $groups.Keys) { if ($order -notcontains $k) { $order += $k } }
        foreach ($fname in $order) {
          $null = $script:drStack.Children.Add((& $script:drMakeSection $fname $groups[$fname].Count))
          foreach ($it in $groups[$fname]) { $null = $script:drStack.Children.Add((& $script:drMakeCard $it $false)) }
        }
      }
    } else {
    $shown = @()
    foreach ($it in $script:dr.items) {
      if ($isTrash) { if ($it.status -eq 'trashed') { $shown += $it }; continue }
      if ($it.status -ne 'active') { continue }
      $eff = Effective-Folder $it $script:dr.folders
      if ($eff -eq $selected) { $shown += $it }
    }
    if ($isTrash) {
      $script:drDelFolderBtn.Visibility = 'Collapsed'
    } elseif ($selected -eq '未整理') {
      $script:drDelFolderBtn.Visibility = 'Collapsed'
    } else {
      $script:drDelFolderBtn.Visibility = 'Visible'
    }
    if ($shown.Count -eq 0) {
      $empty = [Windows.Controls.TextBlock]::new()
      $empty.Text = if ($isTrash) { '垃圾桶是空的。' } elseif ($selected -eq '未整理') { '「未整理」还是空的。' } else { '这个夹子还是空的。' }
      $empty.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#92775A')
      $empty.Margin = '4'; $empty.FontSize = 13; $empty.TextWrapping = 'Wrap'
      $null = $script:drStack.Children.Add($empty)
    } else {
      foreach ($it in $shown) { $null = $script:drStack.Children.Add((& $script:drMakeCard $it $isTrash)) }
    }
    }

    # 高度自适应：内容少时收紧、多时顶到 680；同步测量并设置（显示前设置无最小化风险，显示后由 StateChanged 守护兜底）
    Update-DrawerHeight
  }
  $script:drRender = $render
  $script:drMakeCard = $makeCard
  $script:drMakeSection = $makeSection

  $addBtn.Add_Click({
    $name = Show-FolderInput -ownerWin $script:drDrawer -btnStyle2 $script:drBtnStyle
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    if ($name -eq '垃圾桶' -or $name -eq '全部' -or $script:dr.folders -contains $name) {
      $null = [Windows.MessageBox]::Show($script:drDrawer, '已经有「' + $name + '」了，换个名字吧。', 'inspiration', [Windows.MessageBoxButton]::OK, [Windows.MessageBoxImage]::Information)
      return
    }
    $script:dr.folders = @($script:dr.folders + $name)
    Save-Folders $script:dr.folders
    $script:dr.filter = $name
    $script:dr.allView = $false
    Reset-FilterCombo -ctl $script:drFilter -st $script:dr
    & $script:drRender $script:drFilter.SelectedItem
  })

  $delFolderBtn.Add_Click({
    $name = [string]$script:drFilter.SelectedItem
    if ($name -eq '未整理' -or $name -eq '垃圾桶' -or $name -eq '') { return }
    $r = [Windows.MessageBox]::Show($script:drDrawer, '确定删除收纳夹「' + $name + '」？里面的灵感会回到「未整理」。', 'inspiration', [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Warning)
    if ($r -eq [Windows.MessageBoxResult]::Yes) {
      foreach ($it in $script:dr.items) { if ($it.status -eq 'active' -and $it.folder -eq $name) { $it.folder = '未整理' } }
      $script:dr.folders = @($script:dr.folders | Where-Object { $_ -ne $name })
      Save-Folders $script:dr.folders
      Write-Ideas $script:dr.items
      $script:dr.filter = '未整理'
      $script:dr.allView = $false
      Reset-FilterCombo -ctl $script:drFilter -st $script:dr
      & $script:drRender $script:drFilter.SelectedItem
    }
  })

  $allBtn.Add_Click({
    $script:dr.allView = -not $script:dr.allView
    & $script:drRender $script:drFilter.SelectedItem
  })

  $filter.Add_SelectionChanged({
    if ($script:drFilter.SelectedItem -ne $null) {
      $script:dr.filter = [string]$script:drFilter.SelectedItem
      $script:dr.allView = $false
      & $script:drRender $script:drFilter.SelectedItem
    }
  })

  Reset-FilterCombo -ctl $script:drFilter -st $script:dr
  & $script:drRender $script:dr.filter
  # 显示后改高度偶发触发 WPF 最小化竞态：一旦被最小化立刻恢复正常
  $drawer.Add_StateChanged({
    try {
      if ($script:drDrawer.WindowState -eq 'Minimized') { $script:drDrawer.WindowState = 'Normal' }
    } catch {}
  })
  $drawer.ShowDialog() | Out-Null
}
$history.Add_Click({ Show-IdeaDrawer })

$window.Add_SourceInitialized({
  $source = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
  [PetHotkey]::RegisterHotKey($source, 9001, 3, 0x49) | Out-Null # Ctrl + Alt + I
  $hwndSource = [System.Windows.Interop.HwndSource]::FromHwnd($source)
  $hwndSource.AddHook([System.Windows.Interop.HwndSourceHook]{ param($h,$m,$w,$l,[ref]$handled)
    try {
      if ($m -eq 0x0312 -and $w.ToInt32() -eq 9001) {
        if ($script:openDrawer -and $script:openDrawer.IsVisible) { $script:openDrawer.Close() }
        elseif ($script:parked) { Show-Pet }
        elseif ($shell.Visibility -eq 'Visible') { Hide-Pet }
        else { Expand-Pet }
        $handled.Value = $true
      }
    } catch {
      try { ('HOOK: ' + $_.Exception.ToString()) | Add-Content -LiteralPath (Join-Path $appDir 'pet_crash.log') -Encoding UTF8 } catch {}
    }
    return [IntPtr]::Zero
  })
})
$window.Dispatcher.Add_UnhandledException({
  param($s, $e)
  try { ('DISPATCHER: ' + $e.Exception.ToString()) | Add-Content -LiteralPath (Join-Path $appDir 'pet_crash.log') -Encoding UTF8 } catch {}
  $e.Handled = $true
})
$window.Add_Closed({ $source = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle; [PetHotkey]::UnregisterHotKey($source, 9001) | Out-Null })

# 面板区域拖动：按住空白处可拖动窗口（按钮、输入框自行处理点击，不冒泡到这里）
$script:panelDrag = $null
$window.Add_MouseLeftButtonDown({
  if ($shell.Visibility -eq 'Visible') {
    $c = Get-CursorDip
    $script:panelDrag = @{ sx = $c.x; sy = $c.y; wx = $window.Left; wy = $window.Top; dragging = $false }
    $_.Handled = $true
  }
})
$window.Add_MouseMove({
  if ($script:panelDrag) {
    $c = Get-CursorDip
    $dx = $c.x - $script:panelDrag.sx; $dy = $c.y - $script:panelDrag.sy
    if (-not $script:panelDrag.dragging) {
      if ([Math]::Abs($dx) -ge 4 -or [Math]::Abs($dy) -ge 4) { $script:panelDrag.dragging = $true }
    }
    if ($script:panelDrag.dragging) {
      $window.Left = $script:panelDrag.wx + $dx
      $window.Top = $script:panelDrag.wy + $dy
    }
  }
})
$window.Add_MouseLeftButtonUp({
  $script:panelDrag = $null
})

$window.Left = [Windows.SystemParameters]::WorkArea.Right - $script:ballSize - 12
$window.Top = [Windows.SystemParameters]::WorkArea.Bottom - $script:ballSize - 12
$window.ShowDialog() | Out-Null
