# 灵感小宠物 — 一个无需安装的 Windows 桌面灵感收集器
# 平时是一个小圆球，点它展开成输入面板；Ctrl + Alt + I 随时唤出 / 收起
# 交互规则：小球可按住拖动；面板可按住空白处拖动；× 收起成球（宠物常驻屏幕）；
# 只有 Ctrl + Alt + I 能让整个宠物从屏幕消失 / 唤回

# 固定进程为 DPI 无关（1:1 像素），保证窗口坐标、鼠标坐标、命中测试三者始终一致
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DpiPin {
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
try { [DpiPin]::SetProcessDpiAwareness(0) | Out-Null } catch {}
try { [DpiPin]::SetProcessDpiAwarenessContext([IntPtr](-1)) | Out-Null } catch {}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$appDir = Split-Path -Parent $PSCommandPath
$dataDir = Join-Path $appDir 'data'
$ideasFile = Join-Path $dataDir 'ideas.jsonl'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
if (-not (Test-Path $ideasFile)) { New-Item -ItemType File -Path $ideasFile | Out-Null }

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
          <StackPanel Margin="10,0,0,0"><TextBlock Text="灵感小宠物" FontWeight="Bold" FontSize="16" Foreground="#4B3824"/>
          <TextBlock Text="把闪过的念头丢给我吧" FontSize="11" Foreground="#92775A"/></StackPanel>
        </StackPanel>
        <Button x:Name="CloseButton" Grid.Row="0" Grid.Column="1" Content="×" FontSize="19" FontWeight="Bold" Foreground="#92775A" Background="Transparent" BorderThickness="0"/>
        <TextBox x:Name="IdeaBox" Grid.Row="1" Grid.ColumnSpan="2" Margin="0,14,0,10" Padding="10" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontSize="15" Foreground="#493727" Background="#FFF8E9" BorderBrush="#E5C58E" BorderThickness="1" ToolTip="写下一个 idea..."/>
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

# 两种状态的尺寸
$script:ballSize = 76
$script:panelW = 370
$script:panelH = 300
$script:parked = $false

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
  $entry = [ordered]@{ created_at = (Get-Date).ToString('yyyy-MM-dd HH:mm'); idea = $idea } | ConvertTo-Json -Compress
  Add-Content -LiteralPath $ideasFile -Value $entry -Encoding UTF8
  $ideaBox.Text = ''
  $save.Content = '收好啦！ ✦'
  Start-Sleep -Milliseconds 650
  $save.Content = '收下灵感  ↵'
}

$save.Add_Click({ Save-Idea })
$ideaBox.Add_KeyDown({ if ($_.Key -eq 'Enter' -and [System.Windows.Input.Keyboard]::Modifiers -eq 'Control') { Save-Idea } })
$close.Add_Click({ Collapse-Pet })

# 小球：按住移动=拖动窗口，原地点击=展开面板（光标与窗口同为 1:1 像素坐标）
$script:ballDrag = $null
$ball.Add_MouseLeftButtonDown({
  $c = [System.Windows.Forms.Cursor]::Position
  $script:ballDrag = @{ sx = $c.X; sy = $c.Y; wx = $window.Left; wy = $window.Top; dragging = $false }
  try { $ball.CaptureMouse() | Out-Null } catch {}
  $_.Handled = $true
})
$ball.Add_MouseMove({
  if ($script:ballDrag) {
    $c = [System.Windows.Forms.Cursor]::Position
    $dx = $c.X - $script:ballDrag.sx; $dy = $c.Y - $script:ballDrag.sy
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
$history.Add_Click({
  $all = Get-Content -LiteralPath $ideasFile -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Select-Object -Last 30
  $text = if ($all) { (($all | ForEach-Object { "[$($_.created_at)]`r`n$($_.idea)" }) -join "`r`n`r`n") } else { '还没有灵感。第一个点子正在等你。' }
  [System.Windows.MessageBox]::Show($text, '你的灵感盒子') | Out-Null
})

$window.Add_SourceInitialized({
  $source = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
  [PetHotkey]::RegisterHotKey($source, 9001, 3, 0x49) | Out-Null # Ctrl + Alt + I
  $hwndSource = [System.Windows.Interop.HwndSource]::FromHwnd($source)
  $hwndSource.AddHook([System.Windows.Interop.HwndSourceHook]{ param($h,$m,$w,$l,[ref]$handled)
    try {
      if ($m -eq 0x0312 -and $w.ToInt32() -eq 9001) {
        if ($script:parked) { Show-Pet }
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
    $c = [System.Windows.Forms.Cursor]::Position
    $script:panelDrag = @{ sx = $c.X; sy = $c.Y; wx = $window.Left; wy = $window.Top; dragging = $false }
    $_.Handled = $true
  }
})
$window.Add_MouseMove({
  if ($script:panelDrag) {
    $c = [System.Windows.Forms.Cursor]::Position
    $dx = $c.X - $script:panelDrag.sx; $dy = $c.Y - $script:panelDrag.sy
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
