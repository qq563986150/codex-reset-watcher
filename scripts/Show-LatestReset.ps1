[CmdletBinding()]
param(
    [switch]$StartCollapsed,
    [switch]$PreviewNotification,
    [switch]$CaptureDetail,
    [switch]$CaptureTucked,
    [switch]$AutomationVisible,
    [switch]$SelfTest,
    [string]$CapturePath = '',
    [double]$CaptureWidth = 0,
    [double]$CaptureHeight = 0,
    [int]$CaptureDelayMs = 1100
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing

if (-not ('CodexQuota.NativeWindow' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace CodexQuota {
    public static class NativeWindow {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);
        [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
    }
}
'@
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginDir = Split-Path -Parent $scriptDir
$logoPath = Join-Path $pluginDir 'assets\quota-mark.png'
$readerScript = Join-Path $scriptDir 'Get-LatestReset.ps1'
$usageScript = Join-Path $scriptDir 'Get-CodexUsage.ps1'
$analysisScript = Join-Path $scriptDir 'Get-CodexAnalysis.ps1'
$shellPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $shellPath) { $shellPath = (Get-Command powershell.exe).Source }

$cacheDir = Join-Path $env:LOCALAPPDATA 'CodexResetWatcher'
$latestPath = Join-Path $cacheDir 'latest.json'
$usagePath = Join-Path $cacheDir 'usage.json'
$analysisPath = Join-Path $cacheDir 'analysis.json'
$notificationPath = Join-Path $cacheDir 'notification-state.json'
$windowStatePath = Join-Path $cacheDir 'window-state.json'
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Codex 额度" Width="360" Height="430" WindowStyle="None" AllowsTransparency="True"
 Background="Transparent" ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False" ShowActivated="False"
 FontFamily="Microsoft YaHei UI, Segoe UI" UseLayoutRounding="True" SnapsToDevicePixels="True">
 <Window.Resources>
  <SolidColorBrush x:Key="Emerald" Color="#4FE180"/>
  <SolidColorBrush x:Key="EmeraldDim" Color="#244D34"/>
  <SolidColorBrush x:Key="TextMain" Color="#F3F3F3"/>
  <SolidColorBrush x:Key="TextBody" Color="#C9C9C9"/>
  <SolidColorBrush x:Key="TextMuted" Color="#888888"/>
  <SolidColorBrush x:Key="Divider" Color="#343434"/>
  <Style x:Key="IconButton" TargetType="Button">
   <Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/>
   <Setter Property="Margin" Value="2,0,0,0"/><Setter Property="Padding" Value="0"/>
   <Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/>
   <Setter Property="Foreground" Value="#A8A8A8"/><Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
   <Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="B" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#252525"/><Setter Property="Foreground" Value="#F0F0F0"/></Trigger>
     <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Background" Value="#303030"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="RowButton" TargetType="Button">
   <Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="0"/>
   <Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
    <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#242424"/></Trigger></ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="MenuButton" TargetType="Button" BasedOn="{StaticResource RowButton}">
   <Setter Property="Foreground" Value="#D2D2D2"/><Setter Property="FontSize" Value="12"/><Setter Property="Padding" Value="10,8"/>
  </Style>
 </Window.Resources>

 <Grid x:Name="Root">
  <Grid x:Name="ExpandedShell">
   <Grid.ColumnDefinitions><ColumnDefinition Width="284"/><ColumnDefinition Width="8"/><ColumnDefinition Width="68"/></Grid.ColumnDefinitions>
   <Border x:Name="DrawerCard" Grid.Column="0" CornerRadius="15" Background="#F01B1B1B" BorderBrush="#4B4B4B" BorderThickness="1" Padding="16,14" RenderTransformOrigin="0.5,0.5" Cursor="SizeAll" ToolTip="拖动窗口（按钮区域除外）">
    <Border.RenderTransform>
     <TransformGroup>
      <ScaleTransform x:Name="DrawerScale" ScaleX="1" ScaleY="1"/>
      <TranslateTransform x:Name="DrawerTranslate" X="0"/>
     </TransformGroup>
    </Border.RenderTransform>
    <Grid>
     <Grid x:Name="MainView">
      <Grid.RowDefinitions>
       <RowDefinition Height="42"/><RowDefinition Height="1"/><RowDefinition Height="122"/><RowDefinition Height="1"/>
       <RowDefinition Height="66"/><RowDefinition Height="1"/><RowDefinition Height="76"/><RowDefinition Height="1"/>
       <RowDefinition Height="47"/><RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Grid x:Name="Header" Grid.Row="0" Background="Transparent" Cursor="SizeAll" ToolTip="拖动窗口">
       <Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <Border x:Name="LogoHost" Width="24" Height="24" VerticalAlignment="Center"/>
       <StackPanel x:Name="TitleDragArea" Grid.Column="1" Margin="8,0,0,0" VerticalAlignment="Center">
        <TextBlock x:Name="TitleText" Text="Codex 额度" Foreground="{StaticResource TextMain}" FontWeight="SemiBold" FontSize="15"/>
        <StackPanel Orientation="Horizontal" Margin="0,2,0,0"><Ellipse Width="6" Height="6" Fill="{StaticResource Emerald}" VerticalAlignment="Center"/><TextBlock x:Name="ConnectedText" Margin="6,0,0,0" Text="已连接 Codex" Foreground="#9D9D9D" FontSize="9.5"/></StackPanel>
       </StackPanel>
       <Button x:Name="PinButton" Grid.Column="2" Style="{StaticResource IconButton}" Content="&#xE718;" ToolTip="固定展开"/>
       <Button x:Name="CloseButton" Grid.Column="3" Style="{StaticResource IconButton}" Content="&#xE8BB;" ToolTip="收回右侧窄条"/>
      </Grid>
      <Border Grid.Row="1" Background="{StaticResource Divider}"/>

      <Grid Grid.Row="2" Margin="0,13,0,10">
       <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
       <TextBlock x:Name="PredictionLabel" Text="预测刷新" Foreground="#8F8F8F" FontSize="11"/>
       <TextBlock x:Name="PredictionDate" Grid.Row="1" Text="读取中…" Foreground="{StaticResource Emerald}" FontSize="28" FontWeight="Light" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
       <TextBlock x:Name="PredictionCountdown" Grid.Row="2" Text="正在读取历史统计" Foreground="#B8B8B8" FontSize="12.5"/>
      </Grid>
      <Border Grid.Row="3" Background="{StaticResource Divider}"/>

      <Grid Grid.Row="4" Margin="0,9,0,7">
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <StackPanel VerticalAlignment="Center"><TextBlock x:Name="UsageLabel" Text="本周剩余" Foreground="#9A9A9A" FontSize="10.5"/><ProgressBar x:Name="UsageBar" Margin="0,8,16,0" Height="4" Minimum="0" Maximum="100" Foreground="{StaticResource Emerald}" Background="#343434" BorderThickness="0"/></StackPanel>
       <TextBlock x:Name="UsagePercent" Grid.Column="1" Text="--%" Foreground="{StaticResource TextMain}" FontSize="19" FontWeight="SemiBold" VerticalAlignment="Center"/>
      </Grid>
      <Border Grid.Row="5" Background="{StaticResource Divider}"/>

      <Button x:Name="AnnouncementButton" Grid.Row="6" Style="{StaticResource RowButton}" Padding="0,9">
       <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="24"/></Grid.ColumnDefinitions>
        <StackPanel><StackPanel Orientation="Horizontal"><Ellipse x:Name="AnnouncementDot" Width="6" Height="6" Fill="{StaticResource Emerald}" VerticalAlignment="Center"/><TextBlock x:Name="AnnouncementLabel" Margin="7,0,0,0" Text="最新公告" Foreground="#A0A0A0" FontSize="10.5"/></StackPanel><TextBlock x:Name="AnnouncementTime" Margin="13,7,0,0" Text="读取中…" Foreground="#D4D4D4" FontSize="12.5"/></StackPanel>
        <TextBlock Grid.Column="1" Text="&#xE76C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#8C8C8C" FontSize="12" VerticalAlignment="Center" HorizontalAlignment="Center"/>
       </Grid>
      </Button>
      <Border Grid.Row="7" Background="{StaticResource Divider}"/>

      <Button x:Name="DetailButton" Grid.Row="8" Style="{StaticResource RowButton}" Padding="0,8">
       <Grid><TextBlock x:Name="DetailButtonText" Text="查看详情" Foreground="#E7E7E7" FontSize="12.5" FontWeight="SemiBold"/><TextBlock HorizontalAlignment="Right" Text="&#xE72A;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#9A9A9A" FontSize="12"/></Grid>
      </Button>

      <Grid Grid.Row="9" VerticalAlignment="Bottom">
       <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
       <TextBlock x:Name="DisclaimerText" Text="本插件推算 · 非官方" Foreground="#747474" FontSize="9" VerticalAlignment="Center"/>
       <Button x:Name="MoreButton" Grid.Column="1" Style="{StaticResource IconButton}" Content="&#xE712;" ToolTip="更多"/>
      </Grid>
     </Grid>

     <Grid x:Name="DetailView" Visibility="Collapsed">
      <Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="1"/><RowDefinition Height="*"/><RowDefinition Height="36"/></Grid.RowDefinitions>
      <Grid x:Name="DetailHeader" Grid.Row="0" Background="Transparent" Cursor="SizeAll" ToolTip="拖动窗口">
       <Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/></Grid.ColumnDefinitions>
       <Button x:Name="BackButton" Style="{StaticResource IconButton}" Content="&#xE72B;" ToolTip="返回"/>
       <StackPanel Grid.Column="1" VerticalAlignment="Center"><TextBlock x:Name="DetailTitle" Text="公告详情" Foreground="{StaticResource TextMain}" FontWeight="SemiBold" FontSize="13"/><TextBlock x:Name="DetailTime" Text="" Foreground="#7F7F7F" FontSize="9"/></StackPanel>
       <Button x:Name="DetailCloseButton" Grid.Column="2" Style="{StaticResource IconButton}" Content="&#xE8BB;" ToolTip="收回"/>
      </Grid>
      <Border Grid.Row="1" Background="{StaticResource Divider}"/>
      <ScrollViewer Grid.Row="2" Margin="0,10,0,6" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
       <StackPanel>
        <TextBlock x:Name="AnalysisLabel" Text="重置分析" Foreground="{StaticResource Emerald}" FontSize="10.5" FontWeight="SemiBold"/>
        <TextBlock x:Name="AnalysisText" Margin="0,7,6,0" Text="正在读取 Codex 分析…" Foreground="#C7C7C7" FontSize="10.5" LineHeight="17" TextWrapping="Wrap"/>
        <Border Margin="0,12,6,10" Height="1" Background="{StaticResource Divider}"/>
        <TextBlock x:Name="PostLabel" Text="中文翻译" Foreground="#8B8B8B" FontSize="10"/>
        <TextBlock x:Name="PostText" Margin="0,7,6,0" Foreground="#D5D5D5" FontSize="10.5" LineHeight="18" TextWrapping="Wrap"/>
       </StackPanel>
      </ScrollViewer>
      <TextBlock x:Name="DetailDisclaimer" Grid.Row="3" Text="非官方预测 · 实际额度以 Codex 为准" Foreground="#777777" FontSize="8.8" VerticalAlignment="Center"/>
     </Grid>

     <Border x:Name="MoreMenu" Width="156" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,0,34" Padding="5" CornerRadius="10" Background="#FF252525" BorderBrush="#484848" BorderThickness="1" Visibility="Collapsed" Panel.ZIndex="30">
      <StackPanel>
       <Button x:Name="LanguageMenuButton" Style="{StaticResource MenuButton}" Content="显示英文"/>
       <Button x:Name="ResetPositionMenuButton" Style="{StaticResource MenuButton}" Content="恢复自动贴附"/>
       <Border Height="1" Background="#383838" Margin="5,2"/>
       <Button x:Name="ExitMenuButton" Style="{StaticResource MenuButton}" Foreground="#F09A9A" Content="退出插件"/>
      </StackPanel>
     </Border>
    </Grid>
   </Border>

   <Border x:Name="ExpandedRail" Grid.Column="2" Width="68" Height="240" VerticalAlignment="Center" CornerRadius="15" Background="#E81A1A1A" BorderBrush="#494949" BorderThickness="1" RenderTransformOrigin="0.5,0.5">
    <Border.RenderTransform><ScaleTransform x:Name="ExpandedRailScale" ScaleX="1" ScaleY="1"/></Border.RenderTransform>
    <Grid Margin="8,12"><Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="*"/><RowDefinition Height="34"/><RowDefinition Height="30"/></Grid.RowDefinitions>
     <Grid x:Name="ExpandedRailDragHandle" Background="Transparent" Cursor="SizeAll" ToolTip="拖动窗口">
      <Border x:Name="ExpandedRailNew" HorizontalAlignment="Right" VerticalAlignment="Top" Background="{StaticResource Emerald}" CornerRadius="5" Padding="3,1" Visibility="Collapsed"><TextBlock Text="N" Foreground="#111" FontSize="7" FontWeight="Bold"/></Border>
     </Grid>
     <Button x:Name="ExpandedRailOpenButton" Grid.Row="1" Grid.RowSpan="2" Style="{StaticResource RowButton}" Cursor="Hand" ToolTip="收起到窄轨">
      <Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="34"/></Grid.RowDefinitions>
       <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
        <TextBlock x:Name="ExpandedRailDay" Text="--日" Foreground="{StaticResource Emerald}" FontSize="14" FontWeight="SemiBold" HorizontalAlignment="Center"/>
        <TextBlock x:Name="ExpandedRailTime" Text="--:--" Foreground="{StaticResource Emerald}" FontSize="11" Margin="0,3,0,0" HorizontalAlignment="Center"/>
        <TextBlock x:Name="ExpandedRailRemaining" Text="读取中" Foreground="#B6B6B6" FontSize="9" Margin="0,9,0,0" TextAlignment="Center" TextWrapping="Wrap"/>
       </StackPanel>
       <TextBlock Grid.Row="1" Text="&#xE774;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="#868686" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Grid>
     </Button>
     <Button x:Name="ExpandedRailHideButton" Grid.Row="3" Style="{StaticResource IconButton}" Width="30" Height="28" Content="&#xE76B;" ToolTip="隐藏插件" HorizontalAlignment="Center"/>
    </Grid>
   </Border>
  </Grid>

  <Border x:Name="CollapsedRail" Width="68" Height="240" HorizontalAlignment="Right" VerticalAlignment="Center" CornerRadius="15" Background="#D91A1A1A" BorderBrush="#484848" BorderThickness="1" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
   <Border.RenderTransform><TransformGroup><ScaleTransform x:Name="CollapsedRailScale" ScaleX="1" ScaleY="1"/><TranslateTransform x:Name="CollapsedRailTranslate" X="0"/></TransformGroup></Border.RenderTransform>
   <Grid Margin="8,12"><Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="*"/><RowDefinition Height="34"/><RowDefinition Height="30"/></Grid.RowDefinitions>
    <Grid x:Name="CollapsedRailDragHandle" Background="Transparent" Cursor="SizeAll" ToolTip="拖动窗口">
     <Border x:Name="CollapsedRailNew" HorizontalAlignment="Right" VerticalAlignment="Top" Background="{StaticResource Emerald}" CornerRadius="5" Padding="3,1" Visibility="Collapsed"><TextBlock Text="N" Foreground="#111" FontSize="7" FontWeight="Bold"/></Border>
    </Grid>
    <Button x:Name="CollapsedRailOpenButton" Grid.Row="1" Grid.RowSpan="2" Style="{StaticResource RowButton}" Cursor="Hand" ToolTip="展开详情">
     <Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="34"/></Grid.RowDefinitions>
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
       <TextBlock x:Name="CollapsedRailDay" Text="--日" Foreground="{StaticResource Emerald}" FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Center"/>
       <TextBlock x:Name="CollapsedRailTime" Text="--:--" Foreground="{StaticResource Emerald}" FontSize="11" Margin="0,3,0,0" HorizontalAlignment="Center"/>
       <TextBlock x:Name="CollapsedRailRemaining" Text="读取中" Foreground="#B8B8B8" FontSize="9" Margin="0,10,0,0" TextAlignment="Center" TextWrapping="Wrap"/>
      </StackPanel>
      <Border Grid.Row="1" Width="42" Height="26" CornerRadius="8" Background="#242424" HorizontalAlignment="Center"><TextBlock x:Name="CollapsedRailUsage" Text="--%" Foreground="#DADADA" FontSize="9.5" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
     </Grid>
    </Button>
    <Button x:Name="CollapsedRailHideButton" Grid.Row="3" Style="{StaticResource IconButton}" Width="30" Height="28" Content="&#xE76B;" ToolTip="隐藏插件" HorizontalAlignment="Center"/>
   </Grid>
  </Border>

  <Border x:Name="TuckedHandle" Width="48" Height="126" HorizontalAlignment="Right" VerticalAlignment="Top" CornerRadius="13" Background="#F01A1A1A" BorderBrush="#4A4A4A" BorderThickness="1" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
   <Border.RenderTransform><ScaleTransform x:Name="TuckedHandleScale" ScaleX="1" ScaleY="1"/></Border.RenderTransform>
   <Grid Margin="5,5,5,6">
    <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Grid x:Name="TuckedDragHandle" Background="Transparent" Cursor="SizeAll" ToolTip="拖动窗口"/>
    <Button x:Name="TuckedRestoreButton" Grid.Row="1" Style="{StaticResource RowButton}" Cursor="Hand" ToolTip="展开额度窄轨">
     <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
      <TextBlock x:Name="TuckedDay" Text="--日" Foreground="{StaticResource Emerald}" FontSize="13" FontWeight="SemiBold" HorizontalAlignment="Center"/>
      <TextBlock x:Name="TuckedTime" Text="--:--" Foreground="#D8D8D8" FontSize="9.5" Margin="0,3,0,0" HorizontalAlignment="Center"/>
      <Border Width="26" Height="1" Margin="0,8,0,7" Background="#383838"/>
      <TextBlock Text="&#xE76B;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Foreground="{StaticResource Emerald}" FontSize="10" HorizontalAlignment="Center"/>
     </StackPanel>
    </Button>
   </Grid>
  </Border>

  <Border x:Name="NewPostToast" Width="260" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,8,76,0" CornerRadius="10" Background="#F2242424" BorderBrush="#4FE180" BorderThickness="1" Padding="10,8" Visibility="Collapsed" Panel.ZIndex="50">
   <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/><ColumnDefinition Width="26"/></Grid.ColumnDefinitions>
    <Ellipse Width="7" Height="7" Fill="{StaticResource Emerald}" VerticalAlignment="Center"/>
    <StackPanel Grid.Column="1" Margin="8,0"><TextBlock Text="发现新公告" Foreground="{StaticResource TextMain}" FontSize="10.5" FontWeight="SemiBold"/><TextBlock x:Name="ToastText" Margin="0,2,0,0" Text="点击查看详情" Foreground="#AFAFAF" FontSize="9" TextTrimming="CharacterEllipsis"/></StackPanel>
    <Button x:Name="DismissToastButton" Grid.Column="2" Style="{StaticResource IconButton}" Width="24" Height="24" Content="&#xE8BB;"/>
   </Grid>
  </Border>
 </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
if ($AutomationVisible) {
    $window.ShowInTaskbar = $true
    $window.ShowActivated = $true
}

if (Test-Path $logoPath) {
    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit(); $bitmap.CacheOption = 'OnLoad'; $bitmap.UriSource = [Uri]$logoPath; $bitmap.EndInit(); $bitmap.Freeze()
    $logoBrush = New-Object Windows.Media.ImageBrush
    $logoBrush.ImageSource = $bitmap
    $logoBrush.Stretch = 'UniformToFill'
    $logoBrush.ViewboxUnits = 'RelativeToBoundingBox'
    $logoBrush.Viewbox = New-Object Windows.Rect(0.23, 0.21, 0.75, 0.77)
    $window.FindName('LogoHost').Background = $logoBrush
}

$workArea = [System.Windows.SystemParameters]::WorkArea
$railWidth = 68.0; $railHeight = 240.0; $expandedWidth = 360.0; $expandedHeight = 430.0
$tuckedWidth = 48.0; $tuckedHeight = 126.0
$rightMargin = 12.0; $topMargin = 72.0
$isCaptureMode = -not [string]::IsNullOrWhiteSpace($CapturePath)
$state = [ordered]@{
    collapsed = [bool]$StartCollapsed
    pinned = $false
    language = 'zh'
    detail = $false
    exiting = $false
    switching = $false
    modeApplied = $false
    data = $null
    usage = $null
    analysis = $null
    postKey = ''
    aiStarted = $false
    animationTargetWidth = $expandedWidth
    animationTargetHeight = $expandedHeight
    animationTargetLeft = 0.0
    animationTargetTop = 0.0
    collapsePreloadedRail = $false
    codexHandle = [IntPtr]::Zero
    codexMisses = 0
    hiddenForOtherApp = $false
    userHidden = $false
    codexWasForeground = $false
    dragging = $false
    manualPosition = $false
    manualRight = 0.0
    manualCenterY = 0.0
}

if (Test-Path $windowStatePath) {
    try {
        $savedWindowState = Get-Content $windowStatePath -Raw | ConvertFrom-Json
        if ($savedWindowState.manual_position) {
            $state.manualPosition = $true
            $state.manualRight = [double]$savedWindowState.right
            $state.manualCenterY = [double]$savedWindowState.center_y
        }
    } catch {}
}

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.SystemIcons]::Information
$trayIcon.Text = 'Codex 额度'
$trayIcon.Visible = $false

function Set-ElementText([string]$name, [string]$text) {
    $element = $window.FindName($name)
    if ($element) { $element.Text = $text }
}

function Format-Remaining([TimeSpan]$span, [bool]$compact = $false) {
    if ($span.TotalSeconds -le 0) { return $(if ($state.language -eq 'zh') { '预测时间已到' } else { 'Prediction due' }) }
    $days = [math]::Floor($span.TotalDays)
    $hours = $span.Hours
    $minutes = $span.Minutes
    if ($compact) {
        if ($days -gt 0) { return $(if ($state.language -eq 'zh') { "$days`天`n$hours`时" } else { "$days`d`n$hours`h" }) }
        return $(if ($state.language -eq 'zh') { "$hours`时`n$minutes`分" } else { "$hours`h`n$minutes`m" })
    }
    if ($days -gt 0) { return $(if ($state.language -eq 'zh') { "约还有 $days`天$hours`小时" } else { "About $days days $hours hours" }) }
    return $(if ($state.language -eq 'zh') { "约还有 $hours`小时$minutes`分钟" } else { "About $hours hours $minutes minutes" })
}

function Get-PostKey($post) {
    if (-not $post) { return '' }
    $url = [string]$post.url
    $time = [string]$post.time_utc
    return ($url.Trim().TrimEnd('/').ToLowerInvariant() + '|' + $time.Trim())
}

function Read-NotificationBaseline {
    if (-not (Test-Path $notificationPath)) { return '' }
    try { return [string](Get-Content $notificationPath -Raw | ConvertFrom-Json).last_post_key } catch { return '' }
}

function Save-NotificationBaseline([string]$key) {
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    $payload = [ordered]@{ last_post_key = $key; updated_utc = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
    [IO.File]::WriteAllText($notificationPath, $payload, (New-Object Text.UTF8Encoding($false)))
}

function Set-NewBadge([bool]$visible) {
    $value = if ($visible) { 'Visible' } else { 'Collapsed' }
    $window.FindName('ExpandedRailNew').Visibility = $value
    $window.FindName('CollapsedRailNew').Visibility = $value
}

function Show-NewPost($post) {
    Set-NewBadge $true
    $time = try { ([DateTimeOffset]$post.time_utc).ToLocalTime().ToString('M月d日 HH:mm') } catch { '刚刚' }
    Set-ElementText 'ToastText' ($time + ' · 点击查看详情')
    $window.FindName('NewPostToast').Visibility = 'Visible'
    $toastTimer.Stop(); $toastTimer.Start()
    try {
        $trayIcon.Visible = $true
        $trayIcon.BalloonTipTitle = 'Codex 额度公告更新'
        $trayIcon.BalloonTipText = $time + ' · Tibo 发布了新的额度信息'
        $trayIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $trayIcon.ShowBalloonTip(7000)
        $trayHideTimer.Stop(); $trayHideTimer.Start()
    } catch {}
}

function Update-LanguageLabels {
    $zh = $state.language -eq 'zh'
    Set-ElementText 'TitleText' $(if ($zh) { 'Codex 额度' } else { 'Codex Quota' })
    Set-ElementText 'ConnectedText' $(if ($zh) { '已连接 Codex' } else { 'Connected to Codex' })
    Set-ElementText 'PredictionLabel' $(if ($zh) { '预测刷新' } else { 'Predicted reset' })
    Set-ElementText 'UsageLabel' $(if ($zh) { '本周剩余' } else { 'Weekly remaining' })
    Set-ElementText 'AnnouncementLabel' $(if ($zh) { '最新公告' } else { 'Latest announcement' })
    Set-ElementText 'DetailButtonText' $(if ($zh) { '查看详情' } else { 'View details' })
    Set-ElementText 'DisclaimerText' $(if ($zh) { '本插件推算 · 非官方' } else { 'Plugin estimate · Unofficial' })
    Set-ElementText 'DetailTitle' $(if ($zh) { '公告详情' } else { 'Announcement details' })
    Set-ElementText 'AnalysisLabel' $(if ($zh) { '重置分析' } else { 'Reset analysis' })
    Set-ElementText 'PostLabel' $(if ($zh) { '中文翻译' } else { 'Original post' })
    Set-ElementText 'DetailDisclaimer' $(if ($zh) { '非官方预测 · 实际额度以 Codex 为准' } else { 'Unofficial estimate · Check Codex for actual quota' })
    $window.FindName('LanguageMenuButton').Content = if ($zh) { '显示英文' } else { '显示中文' }
    $window.FindName('ResetPositionMenuButton').Content = if ($zh) { '恢复自动贴附' } else { 'Restore auto position' }
    Update-DataView
}

function Update-DataView {
    $data = $state.data; $usage = $state.usage
    if ($data -and $data.stats -and $data.stats.estimated_next_utc) {
        try {
            $predicted = ([DateTimeOffset]$data.stats.estimated_next_utc).ToLocalTime()
            $span = $predicted - [DateTimeOffset]::Now
            $dateText = if ($state.language -eq 'zh') { $predicted.ToString('M月d日 HH:mm') } else { $predicted.ToString('MMM d, HH:mm') }
            Set-ElementText 'PredictionDate' $dateText
            Set-ElementText 'PredictionCountdown' (Format-Remaining $span)
            foreach ($prefix in @('ExpandedRail','CollapsedRail')) {
                Set-ElementText ($prefix + 'Day') $(if ($state.language -eq 'zh') { $predicted.ToString('d日') } else { $predicted.ToString('dd') })
                Set-ElementText ($prefix + 'Time') $predicted.ToString('HH:mm')
                Set-ElementText ($prefix + 'Remaining') (Format-Remaining $span $true)
            }
            Set-ElementText 'TuckedDay' $(if ($state.language -eq 'zh') { $predicted.ToString('d日') } else { $predicted.ToString('dd') })
            Set-ElementText 'TuckedTime' $predicted.ToString('HH:mm')
        } catch {}
        $postTime = try { ([DateTimeOffset]$data.time_utc).ToLocalTime() } catch { $null }
        if ($postTime) {
            $postTimeText = if ($state.language -eq 'zh') { $postTime.ToString('M月d日 HH:mm') } else { $postTime.ToString('MMM d, HH:mm') }
            Set-ElementText 'AnnouncementTime' $postTimeText
            Set-ElementText 'DetailTime' $postTimeText
        }
    }
    if ($usage -and $usage.primary) {
        $remaining = [math]::Max(0, [math]::Min(100, [double]$usage.primary.remaining_percent))
        $window.FindName('UsageBar').Value = $remaining
        $percentText = ([math]::Round($remaining)).ToString() + '%'
        Set-ElementText 'UsagePercent' $percentText
        Set-ElementText 'CollapsedRailUsage' $percentText
    }
    if ($state.language -eq 'zh') {
        $post = if ($state.analysis -and $state.analysis.translated_zh) { [string]$state.analysis.translated_zh } elseif ($data) { [string]$data.text } else { '正在读取公告…' }
        $analysis = if ($state.analysis) { ([string]$state.analysis.summary_zh + "`n`n" + [string]$state.analysis.estimate_zh + "`n`n" + [string]$state.analysis.confidence_zh).Trim() } else { '正在等待 Codex 完成翻译与分析…' }
    } else {
        $post = if ($data) { [string]$data.text } else { 'Loading announcement…' }
        $analysis = if ($state.analysis -and $state.analysis.summary_zh) { 'AI analysis is currently available in Chinese. Switch to Chinese to read it.' } else { 'Waiting for Codex analysis…' }
    }
    Set-ElementText 'PostText' $post
    Set-ElementText 'AnalysisText' $analysis
}

function Load-Caches {
    try {
        if (Test-Path $latestPath) {
            $newData = Get-Content $latestPath -Raw | ConvertFrom-Json
            $newKey = Get-PostKey $newData
            if (-not $state.postKey) {
                $baseline = Read-NotificationBaseline
                $state.postKey = if ($baseline) { $baseline } else { $newKey }
                if (-not $baseline) { Save-NotificationBaseline $newKey }
            } elseif ($newKey -and $newKey -ne $state.postKey) {
                $state.postKey = $newKey; Save-NotificationBaseline $newKey; Show-NewPost $newData
            }
            $state.data = $newData
        }
        if (Test-Path $usagePath) { $state.usage = Get-Content $usagePath -Raw | ConvertFrom-Json }
        if (Test-Path $analysisPath) {
            $candidate = Get-Content $analysisPath -Raw | ConvertFrom-Json
            if (-not $state.data -or $candidate.url -eq $state.data.url) { $state.analysis = $candidate }
        }
        Update-DataView
        if ($state.data -and -not $state.analysis -and -not $state.aiStarted) {
            $state.aiStarted = $true
            Start-Process -FilePath $shellPath -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$analysisScript) -WindowStyle Hidden
        }
    } catch {}
}

function Start-BackgroundRefresh([bool]$includePost = $true) {
    if ($includePost) { Start-Process -FilePath $shellPath -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$readerScript,'-AsJson') -WindowStyle Hidden }
    Start-Process -FilePath $shellPath -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$usageScript,'-AsJson') -WindowStyle Hidden
}

function Get-CodexProcessIds {
    $allChatGpt = @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue)
    $confirmed = $false
    foreach ($process in $allChatGpt) {
        try {
            if ($process.Path -like '*OpenAI.Codex*') { $confirmed = $true; break }
        } catch {}
    }
    $ids = [Collections.Generic.HashSet[uint32]]::new()
    if ($confirmed) {
        foreach ($process in $allChatGpt) { [void]$ids.Add([uint32]$process.Id) }
    }
    return ,$ids
}

function Test-CodexForeground {
    if ($isCaptureMode -or $SelfTest) { return $true }
    $foreground = [CodexQuota.NativeWindow]::GetForegroundWindow()
    if ($foreground -eq [IntPtr]::Zero) { return $null }
    [uint32]$foregroundPid = 0
    [void][CodexQuota.NativeWindow]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
    if ($foregroundPid -eq [uint32]$PID) { return $true }
    $codexPids = Get-CodexProcessIds
    if ($codexPids.Contains($foregroundPid)) { return $true }
    try {
        $foregroundProcess = Get-Process -Id $foregroundPid -ErrorAction Stop
        if ($foregroundProcess.ProcessName -eq 'ApplicationFrameHost' -and $codexPids.Count -gt 0) {
            $titleBuffer = New-Object Text.StringBuilder 256
            [void][CodexQuota.NativeWindow]::GetWindowText($foreground, $titleBuffer, 256)
            if ($titleBuffer.ToString() -match 'Codex|ChatGPT') { return $true }
        }
    } catch {}
    return $false
}

function Save-ManualPosition {
    $state.manualPosition = $true
    $state.manualRight = [double]($window.Left + $window.Width)
    $state.manualCenterY = [double]($window.Top + ($window.Height / 2.0))
    $payload = [ordered]@{
        manual_position = $true
        right = [math]::Round($state.manualRight, 2)
        center_y = [math]::Round($state.manualCenterY, 2)
        updated_utc = [DateTimeOffset]::UtcNow.ToString('o')
    } | ConvertTo-Json
    try { [IO.File]::WriteAllText($windowStatePath, $payload, (New-Object Text.UTF8Encoding($false))) } catch {}
}

function Invoke-WindowDrag([string]$clickAction = 'none') {
    if ([Windows.Input.Mouse]::LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) { return }
    $startLeft = $window.Left; $startTop = $window.Top
    $state.dragging = $true
    try { $window.DragMove() } catch {}
    $moved = ([math]::Abs($window.Left - $startLeft) -gt 2 -or [math]::Abs($window.Top - $startTop) -gt 2)
    if ($moved) { Save-ManualPosition }
    $state.dragging = $false
    if (-not $moved) {
        if ($clickAction -eq 'expand') { Apply-Mode $false; $window.Activate() }
        elseif ($clickAction -eq 'main') { Show-MainView }
    }
}

function Test-ButtonSource($source) {
    $current = $source
    while ($current) {
        if ($current -is [Windows.Controls.Primitives.ButtonBase]) { return $true }
        try { $current = [Windows.Media.VisualTreeHelper]::GetParent($current) } catch { return $false }
    }
    return $false
}

function Hide-ByUser {
    Tuck-Widget
}

function Get-CodexWindowAnchor {
    if ($isCaptureMode) { return $null }
    $codexPids = Get-CodexProcessIds
    if ($codexPids.Count -eq 0) { return $null }

    $candidates = [Collections.Generic.List[object]]::new()
    $callback = [CodexQuota.NativeWindow+EnumWindowsProc]{
        param([IntPtr]$handle, [IntPtr]$lParam)
        if (-not [CodexQuota.NativeWindow]::IsWindowVisible($handle)) { return $true }
        [uint32]$processId = 0
        [void][CodexQuota.NativeWindow]::GetWindowThreadProcessId($handle, [ref]$processId)
        if (-not $codexPids.Contains($processId)) { return $true }
        $rect = New-Object CodexQuota.NativeWindow+RECT
        if (-not [CodexQuota.NativeWindow]::GetWindowRect($handle, [ref]$rect)) { return $true }
        $width = $rect.Right - $rect.Left; $height = $rect.Bottom - $rect.Top
        if ($width -lt 480 -or $height -lt 320) { return $true }
        $titleBuffer = New-Object Text.StringBuilder 256
        $classBuffer = New-Object Text.StringBuilder 128
        [void][CodexQuota.NativeWindow]::GetWindowText($handle, $titleBuffer, 256)
        [void][CodexQuota.NativeWindow]::GetClassName($handle, $classBuffer, 128)
        $candidates.Add([pscustomobject]@{
            Handle = $handle; Rect = $rect; Area = [double]$width * [double]$height
            Title = $titleBuffer.ToString(); ClassName = $classBuffer.ToString()
            Minimized = [CodexQuota.NativeWindow]::IsIconic($handle)
        })
        return $true
    }
    [void][CodexQuota.NativeWindow]::EnumWindows($callback, [IntPtr]::Zero)
    if ($candidates.Count -eq 0) { return $null }
    $candidate = $candidates | Sort-Object @{ Expression = { if ($_.Title -match 'Codex|ChatGPT') { 1 } else { 0 } }; Descending = $true }, @{ Expression = 'Area'; Descending = $true } | Select-Object -First 1
    $dpi = [CodexQuota.NativeWindow]::GetDpiForWindow($candidate.Handle)
    if ($dpi -le 0) { $dpi = 96 }
    $scale = [double]$dpi / 96.0
    return [pscustomobject]@{
        Handle = $candidate.Handle
        Left = [double]$candidate.Rect.Left / $scale
        Top = [double]$candidate.Rect.Top / $scale
        Right = [double]$candidate.Rect.Right / $scale
        Bottom = [double]$candidate.Rect.Bottom / $scale
        Minimized = [bool]$candidate.Minimized
    }
}

function Get-TargetPosition([double]$targetWidth, [double]$targetHeight) {
    if ($state.manualPosition) {
        $virtualLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
        $virtualTop = [System.Windows.SystemParameters]::VirtualScreenTop
        $virtualRight = $virtualLeft + [System.Windows.SystemParameters]::VirtualScreenWidth
        $virtualBottom = $virtualTop + [System.Windows.SystemParameters]::VirtualScreenHeight
        $left = [math]::Max($virtualLeft + 8, [math]::Min($state.manualRight - $targetWidth, $virtualRight - $targetWidth - 8))
        $top = [math]::Max($virtualTop + 8, [math]::Min($state.manualCenterY - ($targetHeight / 2.0), $virtualBottom - $targetHeight - 8))
        return [pscustomobject]@{ Hidden = $false; Left = $left; Top = $top }
    }
    $railOffset = if ($targetHeight -lt $expandedHeight) { ($expandedHeight - $targetHeight) / 2.0 } else { 0.0 }
    $anchor = Get-CodexWindowAnchor
    if ($anchor) {
        $state.codexHandle = $anchor.Handle; $state.codexMisses = 0
        if ($anchor.Minimized) { return [pscustomobject]@{ Hidden = $true; Left = 0.0; Top = 0.0 } }
        $rightEdge = [math]::Min($workArea.Right - $rightMargin, $anchor.Right - $rightMargin)
        $top = [math]::Max($workArea.Top + 12, $anchor.Top + $topMargin + $railOffset)
        $top = [math]::Min($top, $workArea.Bottom - $targetHeight - 12)
        return [pscustomobject]@{ Hidden = $false; Left = $rightEdge - $targetWidth; Top = $top }
    }
    $state.codexMisses++
    return [pscustomobject]@{ Hidden = $false; Left = $workArea.Right - $rightMargin - $targetWidth; Top = $workArea.Top + $topMargin + $railOffset }
}

function Sync-CodexAnchor {
    if ($isCaptureMode -or $state.switching -or $state.dragging -or -not $window.IsLoaded) { return }
    $isCodexForeground = Test-CodexForeground
    if ($isCodexForeground -eq $false) {
        $state.codexWasForeground = $false
        if (-not $state.userHidden) { Set-RailStateImmediate $false }
        $window.Topmost = $false
        if ($window.IsVisible) { $window.Hide() }
        $state.hiddenForOtherApp = $true
        return
    }
    if ($null -eq $isCodexForeground) { return }
    if ($state.userHidden) {
        $state.codexWasForeground = $true
        $window.Topmost = $true
        if (-not $window.IsVisible) { $window.Show(); $state.hiddenForOtherApp = $false }
        $position = Get-TargetPosition $tuckedWidth $tuckedHeight
        if ([math]::Abs($window.Left - $position.Left) -gt 0.75) { $window.Left = $position.Left }
        if ([math]::Abs($window.Top - $position.Top) -gt 0.75) { $window.Top = $position.Top }
        return
    }
    $state.codexWasForeground = $true
    $window.Topmost = $true
    $position = Get-TargetPosition $window.Width $window.Height
    if ($position.Hidden) {
        $window.Topmost = $false
        if ($window.IsVisible) { $window.Hide() }
        return
    }
    if (-not $window.IsVisible) { $window.Show(); $state.hiddenForOtherApp = $false }
    if ([math]::Abs($window.Left - $position.Left) -gt 0.75) { $window.Left = $position.Left }
    if ([math]::Abs($window.Top - $position.Top) -gt 0.75) { $window.Top = $position.Top }
}

function Pulse-CollapsedRail {
    $scale = $window.FindName('CollapsedRailScale')
    if (-not $scale) { return }
    $ease = New-Object Windows.Media.Animation.BackEase
    $ease.EasingMode = 'EaseOut'; $ease.Amplitude = 0.46
    $duration = [TimeSpan]::FromMilliseconds(190)
    $x = New-Object Windows.Media.Animation.DoubleAnimation(0.88, 1.0, $duration); $x.EasingFunction = $ease
    $y = New-Object Windows.Media.Animation.DoubleAnimation(0.88, 1.0, $duration); $y.EasingFunction = $ease
    $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $x)
    $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $y)
}

function Pulse-ExpandedRail {
    $scale = $window.FindName('ExpandedRailScale')
    if (-not $scale) { return }
    $ease = New-Object Windows.Media.Animation.BackEase
    $ease.EasingMode = 'EaseOut'; $ease.Amplitude = 0.52
    $duration = [TimeSpan]::FromMilliseconds(260)
    $x = New-Object Windows.Media.Animation.DoubleAnimation(0.90, 1.0, $duration); $x.EasingFunction = $ease
    $y = New-Object Windows.Media.Animation.DoubleAnimation(0.90, 1.0, $duration); $y.EasingFunction = $ease
    $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $x)
    $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $y)
}

function Pulse-TuckedHandle {
    $scale = $window.FindName('TuckedHandleScale')
    if (-not $scale) { return }
    $ease = New-Object Windows.Media.Animation.BackEase
    $ease.EasingMode = 'EaseOut'; $ease.Amplitude = 0.55
    $duration = [TimeSpan]::FromMilliseconds(230)
    $x = New-Object Windows.Media.Animation.DoubleAnimation(0.78, 1.0, $duration); $x.EasingFunction = $ease
    $y = New-Object Windows.Media.Animation.DoubleAnimation(0.78, 1.0, $duration); $y.EasingFunction = $ease
    $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $x)
    $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $y)
}

function Set-TuckedStateImmediate {
    $position = Get-TargetPosition $tuckedWidth $tuckedHeight
    $window.FindName('ExpandedShell').Visibility = 'Collapsed'
    $window.FindName('CollapsedRail').Visibility = 'Collapsed'
    $window.FindName('TuckedHandle').Visibility = 'Visible'
    $window.Width = $tuckedWidth; $window.Height = $tuckedHeight
    if (-not $position.Hidden) { $window.Left = $position.Left; $window.Top = $position.Top }
    $state.collapsed = $true; $state.modeApplied = $true; $state.switching = $false
}

function Tuck-Widget {
    if ($state.userHidden -or $state.switching) { return }
    if (-not $state.collapsed) { Show-MainView; Set-RailStateImmediate $true }
    $state.userHidden = $true; $state.codexWasForeground = $true; $state.switching = $true
    $rail = $window.FindName('CollapsedRail'); $translate = $window.FindName('CollapsedRailTranslate')
    $window.FindName('TuckedHandle').Visibility = 'Collapsed'
    $rail.Visibility = 'Visible'; $rail.Opacity = 1; $translate.X = 0
    $ease = New-Object Windows.Media.Animation.BackEase; $ease.EasingMode = 'EaseIn'; $ease.Amplitude = 0.32
    $fadeEase = New-Object Windows.Media.Animation.CubicEase; $fadeEase.EasingMode = 'EaseIn'
    $slide = New-Object Windows.Media.Animation.DoubleAnimation(0.0, 58.0, [TimeSpan]::FromMilliseconds(245)); $slide.EasingFunction = $ease
    $fade = New-Object Windows.Media.Animation.DoubleAnimation(1.0, 0.35, [TimeSpan]::FromMilliseconds(215)); $fade.EasingFunction = $fadeEase
    $slide.Add_Completed({
        $completedRail = $window.FindName('CollapsedRail'); $completedTranslate = $window.FindName('CollapsedRailTranslate')
        $completedRail.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $completedTranslate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
        $completedRail.Opacity = 1; $completedTranslate.X = 0
        Set-TuckedStateImmediate
        Pulse-TuckedHandle
    })
    $rail.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
    $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $slide)
}

function Restore-FromTuck {
    if (-not $state.userHidden -or $state.switching) { return }
    $state.userHidden = $false; $state.switching = $true
    $position = Get-TargetPosition $railWidth $railHeight
    $window.Width = $railWidth; $window.Height = $railHeight; $window.Left = $position.Left; $window.Top = $position.Top
    $window.FindName('TuckedHandle').Visibility = 'Collapsed'
    $window.FindName('ExpandedShell').Visibility = 'Collapsed'
    $rail = $window.FindName('CollapsedRail'); $translate = $window.FindName('CollapsedRailTranslate')
    $rail.Visibility = 'Visible'; $rail.Opacity = 0.45; $translate.X = 54
    $ease = New-Object Windows.Media.Animation.BackEase; $ease.EasingMode = 'EaseOut'; $ease.Amplitude = 0.56
    $fadeEase = New-Object Windows.Media.Animation.CubicEase; $fadeEase.EasingMode = 'EaseOut'
    $slide = New-Object Windows.Media.Animation.DoubleAnimation(54.0, 0.0, [TimeSpan]::FromMilliseconds(310)); $slide.EasingFunction = $ease
    $fade = New-Object Windows.Media.Animation.DoubleAnimation(0.45, 1.0, [TimeSpan]::FromMilliseconds(170)); $fade.EasingFunction = $fadeEase
    $slide.Add_Completed({
        $completedRail = $window.FindName('CollapsedRail'); $completedTranslate = $window.FindName('CollapsedRailTranslate')
        $completedRail.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $completedTranslate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
        $completedRail.Opacity = 1; $completedTranslate.X = 0
        $state.collapsed = $true; $state.modeApplied = $true; $state.switching = $false
        Pulse-CollapsedRail
    })
    $rail.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
    $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $slide)
}

function Set-RailStateImmediate([bool]$reposition = $true) {
    foreach ($property in @([Windows.Window]::WidthProperty,[Windows.Window]::HeightProperty,[Windows.Window]::LeftProperty,[Windows.Window]::TopProperty)) { $window.BeginAnimation($property, $null) }
    $state.switching = $false; $state.collapsed = $true; $state.modeApplied = $true; $state.detail = $false
    $window.FindName('MainView').Visibility = 'Visible'
    $window.FindName('DetailView').Visibility = 'Collapsed'
    $window.FindName('ExpandedShell').Visibility = 'Collapsed'
    $window.FindName('TuckedHandle').Visibility = 'Collapsed'
    $window.FindName('CollapsedRail').Visibility = 'Visible'
    $window.Width = $railWidth; $window.Height = $railHeight
    if ($reposition) {
        $position = Get-TargetPosition $railWidth $railHeight
        if (-not $position.Hidden) { $window.Left = $position.Left; $window.Top = $position.Top }
    }
}

function Apply-Mode([bool]$collapsed, [bool]$animate = $true) {
    if ($state.switching -or ($state.modeApplied -and $state.collapsed -eq $collapsed -and $window.IsLoaded)) {
        if (-not $window.IsLoaded) { $state.collapsed = $collapsed }
        return
    }
    $state.switching = $true; $state.collapsed = $collapsed
    $targetWidth = if ($collapsed) { $railWidth } else { $expandedWidth }
    $targetHeight = if ($collapsed) { $railHeight } else { $expandedHeight }
    $position = Get-TargetPosition $targetWidth $targetHeight
    $targetLeft = $position.Left
    $targetTop = $position.Top
    $state.animationTargetWidth = $targetWidth
    $state.animationTargetHeight = $targetHeight
    $state.animationTargetLeft = $targetLeft
    $state.animationTargetTop = $targetTop

    if (-not $animate -or -not $window.IsLoaded) {
        $window.BeginAnimation([Windows.Window]::WidthProperty, $null)
        $window.BeginAnimation([Windows.Window]::HeightProperty, $null)
        $window.BeginAnimation([Windows.Window]::LeftProperty, $null)
        $window.BeginAnimation([Windows.Window]::TopProperty, $null)
        $window.Width = $targetWidth; $window.Height = $targetHeight; $window.Left = $targetLeft; $window.Top = $targetTop
        $window.FindName('ExpandedShell').Visibility = if ($collapsed) { 'Collapsed' } else { 'Visible' }
        $window.FindName('CollapsedRail').Visibility = if ($collapsed) { 'Visible' } else { 'Collapsed' }
        $window.FindName('ExpandedRail').Visibility = 'Visible'
        $window.FindName('DrawerCard').Opacity = 1
        $window.FindName('DrawerTranslate').X = 0
        $window.FindName('DrawerScale').ScaleX = 1
        $window.FindName('DrawerScale').ScaleY = 1
        $state.modeApplied = $true
        $state.switching = $false
        return
    }

    $drawer = $window.FindName('DrawerCard')
    $translate = $window.FindName('DrawerTranslate')
    $drawerScale = $window.FindName('DrawerScale')
    if ($collapsed) {
        # Keep the rail rendered at its final screen position throughout collapse. Only the
        # drawer moves, avoiding the one-frame visual swap that flickers on transparent WPF windows.
        $window.FindName('CollapsedRail').Visibility = 'Visible'
        $window.FindName('ExpandedRail').Visibility = 'Collapsed'
        $state.collapsePreloadedRail = $true
        $ease = New-Object Windows.Media.Animation.CubicEase
        $ease.EasingMode = 'EaseIn'
        $opacityAnimation = New-Object Windows.Media.Animation.DoubleAnimation($drawer.Opacity, 0.0, [TimeSpan]::FromMilliseconds(135)); $opacityAnimation.EasingFunction = $ease
        $slideAnimation = New-Object Windows.Media.Animation.DoubleAnimation($translate.X, 28.0, [TimeSpan]::FromMilliseconds(170)); $slideAnimation.EasingFunction = $ease
        $slideAnimation.Add_Completed({
            $completedDrawer = $window.FindName('DrawerCard'); $completedTranslate = $window.FindName('DrawerTranslate'); $completedScale = $window.FindName('DrawerScale')
            $completedDrawer.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
            $completedTranslate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
            $completedDrawer.Opacity = 1; $completedTranslate.X = 0; $completedScale.ScaleX = 1; $completedScale.ScaleY = 1
            $window.Width = [double]$state.animationTargetWidth; $window.Height = [double]$state.animationTargetHeight
            $window.Left = [double]$state.animationTargetLeft; $window.Top = [double]$state.animationTargetTop
            $window.FindName('ExpandedShell').Visibility = 'Collapsed'
            $window.FindName('CollapsedRail').Visibility = 'Visible'
            $window.FindName('ExpandedRail').Visibility = 'Visible'
            $state.modeApplied = $true; $state.switching = $false
            Pulse-CollapsedRail
        })
        $drawer.BeginAnimation([Windows.UIElement]::OpacityProperty, $opacityAnimation)
        $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $slideAnimation)
    } else {
        $state.collapsePreloadedRail = $false
        $window.Width = $targetWidth; $window.Height = $targetHeight; $window.Left = $targetLeft; $window.Top = $targetTop
        $window.FindName('ExpandedRail').Visibility = 'Visible'
        $window.FindName('ExpandedShell').Visibility = 'Visible'
        $window.FindName('CollapsedRail').Visibility = 'Collapsed'
        $drawer.Opacity = 0; $translate.X = 52; $drawerScale.ScaleX = 0.91; $drawerScale.ScaleY = 0.91
        $fadeEase = New-Object Windows.Media.Animation.CubicEase; $fadeEase.EasingMode = 'EaseOut'
        $springEase = New-Object Windows.Media.Animation.BackEase; $springEase.EasingMode = 'EaseOut'; $springEase.Amplitude = 0.58
        $opacityAnimation = New-Object Windows.Media.Animation.DoubleAnimation(0.0, 1.0, [TimeSpan]::FromMilliseconds(155)); $opacityAnimation.EasingFunction = $fadeEase
        $slideAnimation = New-Object Windows.Media.Animation.DoubleAnimation(52.0, 0.0, [TimeSpan]::FromMilliseconds(360)); $slideAnimation.EasingFunction = $springEase
        $scaleXAnimation = New-Object Windows.Media.Animation.DoubleAnimation(0.91, 1.0, [TimeSpan]::FromMilliseconds(350)); $scaleXAnimation.EasingFunction = $springEase
        $scaleYAnimation = New-Object Windows.Media.Animation.DoubleAnimation(0.91, 1.0, [TimeSpan]::FromMilliseconds(350)); $scaleYAnimation.EasingFunction = $springEase
        $slideAnimation.Add_Completed({
            $completedDrawer = $window.FindName('DrawerCard'); $completedTranslate = $window.FindName('DrawerTranslate'); $completedScale = $window.FindName('DrawerScale')
            $completedDrawer.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
            $completedTranslate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
            $completedScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $completedScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $null)
            $completedDrawer.Opacity = 1; $completedTranslate.X = 0; $completedScale.ScaleX = 1; $completedScale.ScaleY = 1
            $state.modeApplied = $true; $state.switching = $false
        })
        $drawer.BeginAnimation([Windows.UIElement]::OpacityProperty, $opacityAnimation)
        $translate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $slideAnimation)
        $drawerScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $scaleXAnimation)
        $drawerScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $scaleYAnimation)
        Pulse-ExpandedRail
    }
}

function Show-MainView {
    $state.detail = $false
    $window.FindName('DetailView').Visibility = 'Collapsed'
    $window.FindName('MainView').Visibility = 'Visible'
    $window.FindName('MoreMenu').Visibility = 'Collapsed'
}

function Show-DetailView {
    $state.detail = $true
    Set-NewBadge $false
    $window.FindName('NewPostToast').Visibility = 'Collapsed'
    $window.FindName('MainView').Visibility = 'Collapsed'
    $window.FindName('DetailView').Visibility = 'Visible'
    $window.FindName('MoreMenu').Visibility = 'Collapsed'
}

function Save-WindowCapture([string]$path) {
    $directory = Split-Path -Parent $path
    if ($directory -and -not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $window.UpdateLayout()
    $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($window)
    $pixelWidth = [math]::Max(1, [int][math]::Ceiling($window.ActualWidth * $dpi.DpiScaleX))
    $pixelHeight = [math]::Max(1, [int][math]::Ceiling($window.ActualHeight * $dpi.DpiScaleY))
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($pixelWidth, $pixelHeight, $dpi.PixelsPerInchX, $dpi.PixelsPerInchY, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Open($path, [IO.FileMode]::Create)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

$autoCollapseTimer = New-Object Windows.Threading.DispatcherTimer
$autoCollapseTimer.Interval = [TimeSpan]::FromSeconds(4)
$autoCollapseTimer.Add_Tick({ $autoCollapseTimer.Stop(); if (-not $state.pinned -and -not $state.collapsed) { Show-MainView; Apply-Mode $true } })
$toastTimer = New-Object Windows.Threading.DispatcherTimer
$toastTimer.Interval = [TimeSpan]::FromSeconds(8)
$toastTimer.Add_Tick({ $toastTimer.Stop(); $window.FindName('NewPostToast').Visibility = 'Collapsed' })
$trayHideTimer = New-Object Windows.Threading.DispatcherTimer
$trayHideTimer.Interval = [TimeSpan]::FromSeconds(10)
$trayHideTimer.Add_Tick({ $trayHideTimer.Stop(); if (-not $state.userHidden) { $trayIcon.Visible = $false } })
$clockTimer = New-Object Windows.Threading.DispatcherTimer
$clockTimer.Interval = [TimeSpan]::FromSeconds(1)
$clockTimer.Add_Tick({ Update-DataView })
$cacheTimer = New-Object Windows.Threading.DispatcherTimer
$cacheTimer.Interval = [TimeSpan]::FromSeconds(2)
$cacheTimer.Add_Tick({ Load-Caches })
$usageTimer = New-Object Windows.Threading.DispatcherTimer
$usageTimer.Interval = [TimeSpan]::FromMinutes(1)
$usageTimer.Add_Tick({ Start-BackgroundRefresh $false })
$postTimer = New-Object Windows.Threading.DispatcherTimer
$postTimer.Interval = [TimeSpan]::FromMinutes(10)
$postTimer.Add_Tick({ Start-BackgroundRefresh $true })
$anchorTimer = New-Object Windows.Threading.DispatcherTimer
$anchorTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$anchorTimer.Add_Tick({ Sync-CodexAnchor })

$window.FindName('CollapsedRailOpenButton').Add_Click({ Apply-Mode $false; $window.Activate() })
$window.FindName('ExpandedRailOpenButton').Add_Click({ Show-MainView; Apply-Mode $true })
$window.FindName('CollapsedRailDragHandle').Add_MouseLeftButtonDown({ param($sender,$e) $e.Handled = $true; Invoke-WindowDrag 'none' })
$window.FindName('ExpandedRailDragHandle').Add_MouseLeftButtonDown({ param($sender,$e) $e.Handled = $true; Invoke-WindowDrag 'none' })
$window.FindName('TuckedDragHandle').Add_MouseLeftButtonDown({ param($sender,$e) $e.Handled = $true; Invoke-WindowDrag 'none' })
$window.FindName('DrawerCard').Add_MouseLeftButtonDown({ param($sender,$e) if (-not (Test-ButtonSource $e.OriginalSource)) { $e.Handled = $true; Invoke-WindowDrag 'none' } })
$window.FindName('CollapsedRailHideButton').Add_Click({ Hide-ByUser })
$window.FindName('ExpandedRailHideButton').Add_Click({ Hide-ByUser })
$window.FindName('TuckedRestoreButton').Add_Click({ Restore-FromTuck })
$window.FindName('CloseButton').Add_Click({ Show-MainView; Apply-Mode $true })
$window.FindName('DetailCloseButton').Add_Click({ Show-MainView; Apply-Mode $true })
$window.FindName('PinButton').Add_Click({
    $state.pinned = -not $state.pinned
    $window.FindName('PinButton').Foreground = if ($state.pinned) { [Windows.Media.Brushes]::LightGreen } else { New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#A8A8A8')) }
    $window.FindName('PinButton').ToolTip = if ($state.pinned) { '取消固定' } else { '固定展开' }
    if ($state.pinned) { $autoCollapseTimer.Stop() }
})
$window.FindName('AnnouncementButton').Add_Click({ Show-DetailView })
$window.FindName('DetailButton').Add_Click({ Show-DetailView })
$window.FindName('BackButton').Add_Click({ Show-MainView })
$window.FindName('MoreButton').Add_Click({ $window.FindName('MoreMenu').Visibility = if ($window.FindName('MoreMenu').Visibility -eq [Windows.Visibility]::Visible) { 'Collapsed' } else { 'Visible' } })
$window.FindName('LanguageMenuButton').Add_Click({ $state.language = if ($state.language -eq 'zh') { 'en' } else { 'zh' }; $window.FindName('MoreMenu').Visibility = 'Collapsed'; Update-LanguageLabels })
$window.FindName('ResetPositionMenuButton').Add_Click({
    $state.manualPosition = $false
    $state.manualRight = 0.0; $state.manualCenterY = 0.0
    $payload = [ordered]@{ manual_position = $false; updated_utc = [DateTimeOffset]::UtcNow.ToString('o') } | ConvertTo-Json
    try { [IO.File]::WriteAllText($windowStatePath, $payload, (New-Object Text.UTF8Encoding($false))) } catch {}
    $window.FindName('MoreMenu').Visibility = 'Collapsed'
    Sync-CodexAnchor
})
$window.FindName('ExitMenuButton').Add_Click({ $state.exiting = $true; $window.Close() })
$window.FindName('DismissToastButton').Add_Click({ $toastTimer.Stop(); $window.FindName('NewPostToast').Visibility = 'Collapsed' })
$window.Add_Deactivated({ if (-not $state.pinned -and -not $state.collapsed) { $autoCollapseTimer.Stop(); $autoCollapseTimer.Start() } })
$window.Add_Activated({ $autoCollapseTimer.Stop() })
$window.Add_MouseEnter({ $autoCollapseTimer.Stop() })
$window.Add_MouseLeave({ if (-not $state.pinned -and -not $state.collapsed) { $autoCollapseTimer.Stop(); $autoCollapseTimer.Start() } })
$window.Add_Closed({ [Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvokeShutdown([Windows.Threading.DispatcherPriority]::Background) })
$trayIcon.Add_DoubleClick({
    $window.Dispatcher.Invoke([Action]{
        $trayIcon.Visible = $false
        if ($state.userHidden) { Restore-FromTuck } else { Sync-CodexAnchor }
    })
})

$window.Add_Loaded({
    Apply-Mode ([bool]$StartCollapsed) $false
    Update-LanguageLabels
    Load-Caches
    if ($CaptureDetail) { Apply-Mode $false $false; Show-DetailView }
    if ($CaptureTucked) { $state.userHidden = $true; Set-TuckedStateImmediate }
    if ($SelfTest) {
        $script:selfTestResults = [ordered]@{}
        $script:selfTestStage = 0
        $script:selfTestTimer = New-Object Windows.Threading.DispatcherTimer
        $script:selfTestTimer.Interval = [TimeSpan]::FromMilliseconds(520)
        $script:selfTestTimer.Add_Tick({
            switch ($script:selfTestStage) {
                0 {
                    $script:selfTestResults.initial_rail = ($state.collapsed -and $window.FindName('CollapsedRail').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $railWidth) -lt 2)
                    $script:selfTestResults.collapsed_drag_target_large = ($window.FindName('CollapsedRailDragHandle').ActualWidth -ge 48 -and $window.FindName('CollapsedRailDragHandle').ActualHeight -ge 32)
                    $window.FindName('CollapsedRailOpenButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                }
                1 {
                    $script:selfTestResults.expanded = ((-not $state.collapsed) -and $window.FindName('ExpandedShell').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $expandedWidth) -lt 2)
                    $script:selfTestResults.expanded_drag_surface_large = ($window.FindName('DrawerCard').ActualWidth -ge 280 -and $window.FindName('DrawerCard').ActualHeight -ge 420 -and $window.FindName('ExpandedRailDragHandle').ActualHeight -ge 32)
                    $window.FindName('ExpandedRailOpenButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                }
                2 {
                    $script:selfTestResults.rail_center_toggle_collapses = ($state.collapsed -and $window.FindName('CollapsedRail').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $railWidth) -lt 2)
                    $script:selfTestResults.collapse_preloads_stable_rail = [bool]$state.collapsePreloadedRail
                    $window.FindName('CollapsedRailOpenButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                }
                3 {
                    $script:selfTestResults.toggle_reopens = ((-not $state.collapsed) -and $window.FindName('ExpandedShell').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $expandedWidth) -lt 2)
                    Show-DetailView
                }
                4 {
                    $script:selfTestResults.detail = ($state.detail -and $window.FindName('DetailView').Visibility -eq [Windows.Visibility]::Visible)
                    Show-MainView
                    $window.FindName('CloseButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                }
                5 {
                    $script:selfTestResults.close_returns_to_rail = ($state.collapsed -and $window.FindName('CollapsedRail').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $railWidth) -lt 2)
                    $window.FindName('CollapsedRailHideButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                }
                6 {
                    $script:selfTestResults.arrow_tucks = ($state.userHidden -and $window.IsVisible -and $window.FindName('TuckedHandle').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $tuckedWidth) -lt 2)
                    $script:selfTestResults.tucked_drag_area = ($window.FindName('TuckedDragHandle').ActualWidth -ge 36 -and $window.FindName('TuckedDragHandle').ActualHeight -ge 32)
                    $window.FindName('TuckedRestoreButton').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                }
                7 {
                    $script:selfTestResults.tucked_handle_restores = ((-not $state.userHidden) -and $window.FindName('CollapsedRail').Visibility -eq [Windows.Visibility]::Visible -and [math]::Abs($window.ActualWidth - $railWidth) -lt 2)
                    [Console]::Out.WriteLine(($script:selfTestResults | ConvertTo-Json -Compress))
                    $script:selfTestTimer.Stop(); $state.exiting = $true; $window.Close()
                }
            }
            $script:selfTestStage++
        })
        $script:selfTestTimer.Start()
    }
    $fade = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(180))
    $window.BeginAnimation([Windows.Window]::OpacityProperty, $fade)
    if ($PreviewNotification -and $state.data) { Show-NewPost $state.data }
    if ($isCaptureMode) {
        $captureTimer = New-Object Windows.Threading.DispatcherTimer
        $captureTimer.Interval = [TimeSpan]::FromMilliseconds([math]::Max(300, $CaptureDelayMs))
        $captureTimer.Add_Tick({ $captureTimer.Stop(); Save-WindowCapture $CapturePath; $state.exiting = $true; $window.Close() })
        $script:captureTimer = $captureTimer; $captureTimer.Start()
    }
})

$clockTimer.Start(); $cacheTimer.Start(); $usageTimer.Start(); $postTimer.Start(); $anchorTimer.Start()
Load-Caches
if (-not $isCaptureMode) { Start-BackgroundRefresh $true }
try {
    $window.Show()
    [Windows.Threading.Dispatcher]::Run()
}
finally {
    foreach ($timer in @($autoCollapseTimer,$toastTimer,$trayHideTimer,$clockTimer,$cacheTimer,$usageTimer,$postTimer,$anchorTimer,$script:selfTestTimer)) { if ($timer) { $timer.Stop() } }
    $trayIcon.Visible = $false; $trayIcon.Dispose()
}
