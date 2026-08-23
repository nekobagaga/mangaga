$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Caption = "mangaga",

        [System.Windows.MessageBoxImage]$Image = [System.Windows.MessageBoxImage]::Information
    )

    [System.Windows.MessageBox]::Show($Message, $Caption, [System.Windows.MessageBoxButton]::OK, $Image) | Out-Null
}

function Confirm-AppMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Caption = "mangaga"
    )

    $result = [System.Windows.MessageBox]::Show($Message, $Caption, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    return $result -eq [System.Windows.MessageBoxResult]::Yes
}

$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptRoot
$DataDir = Join-Path $ProjectRoot "data"
$LibraryPath = Join-Path $DataDir "library.json"
$SettingsPath = Join-Path $DataDir "settings.json"
$ScannerPath = Join-Path $ScriptRoot "manga_scanner.py"

function Get-PythonPath {
    $bundled = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    if (Test-Path -LiteralPath $bundled) {
        return $bundled
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return $python.Source
    }

    return $null
}

$PythonPath = Get-PythonPath
if (-not $PythonPath) {
    Show-AppMessage -Message "未找到 Python。请安装 Python 和 Pillow，或在 Codex 本地运行时中启动。" -Image ([System.Windows.MessageBoxImage]::Error)
    exit 1
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Write-AppLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Detail = ""
    )

    try {
        $logDir = Join-Path $DataDir "logs"
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $logPath = Join-Path $logDir "app.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add("[$timestamp] $Message") | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $lines.Add($Detail.Trim()) | Out-Null
        }
        $lines.Add("") | Out-Null
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value $lines
    }
    catch {
    }
}

$Script:AppSettings = @{}
$Script:AppSettingsLoaded = $false

function Ensure-AppSettingsLoaded {
    if ($Script:AppSettingsLoaded) {
        return
    }

    $Script:AppSettings = @{}
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $SettingsPath
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $data = $raw | ConvertFrom-Json
                if ($null -ne $data) {
                    foreach ($property in $data.PSObject.Properties) {
                        $Script:AppSettings[[string]$property.Name] = $property.Value
                    }
                }
            }
        }
        catch {
            Write-AppLog -Message "读取设置失败" -Detail $_.Exception.ToString()
        }
    }

    $Script:AppSettingsLoaded = $true
}

function Save-AppSettings {
    Ensure-AppSettingsLoaded
    try {
        New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
        $ordered = [ordered]@{}
        foreach ($key in @($Script:AppSettings.Keys | Sort-Object)) {
            $ordered[[string]$key] = $Script:AppSettings[$key]
        }
        ($ordered | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    }
    catch {
        Write-AppLog -Message "保存设置失败" -Detail $_.Exception.ToString()
    }
}

function Get-AppSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Default = ""
    )

    Ensure-AppSettingsLoaded
    if ($Script:AppSettings.ContainsKey($Name)) {
        return $Script:AppSettings[$Name]
    }
    return $Default
}

function Set-AppSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Value
    )

    Ensure-AppSettingsLoaded
    if ($null -eq $Value) {
        $Script:AppSettings.Remove($Name) | Out-Null
    }
    else {
        $Script:AppSettings[$Name] = $Value
    }
    Save-AppSettings
}

function New-SolidBrush([string]$Color) {
    return [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
}

$BrushWindow = New-SolidBrush "#111316"
$BrushCard = New-SolidBrush "#20232A"
$BrushCardHover = New-SolidBrush "#2A2E37"
$BrushCover = New-SolidBrush "#272B34"
$BrushText = New-SolidBrush "#ECEFF4"
$BrushMuted = New-SolidBrush "#9AA3B2"
$BrushAccent = New-SolidBrush "#D8B45F"
$BrushTransparent = New-SolidBrush "#00000000"
$BrushSelectedBack = New-SolidBrush "#181B20"
$BrushReaderPanel = New-SolidBrush "#CC111316"
$BrushSidebar = New-SolidBrush "#181B20"
$BrushSidebarItem = New-SolidBrush "#00000000"
$BrushSidebarItemHover = New-SolidBrush "#242833"
$BrushSidebarItemSelected = New-SolidBrush "#2E3440"
$BrushBadge = New-SolidBrush "#CC111316"

function Show-ChoiceDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [object[]]$Choices
    )

    $dialog = New-Object System.Windows.Window
    $dialog.Title = $Title
    $dialog.Width = 560
    $dialog.SizeToContent = "Height"
    $dialog.MinHeight = 220
    $dialog.MaxHeight = 560
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Background = $BrushWindow
    $dialog.Foreground = $BrushText
    $dialog.ResizeMode = "NoResize"
    try {
        if ($null -ne $Window -and $Window.IsVisible) {
            $dialog.Owner = $Window
        }
    }
    catch {
    }

    $panel = New-Object System.Windows.Controls.DockPanel
    $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 20
    $dialog.Content = $panel

    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = $Message
    $body.TextWrapping = "Wrap"
    $body.Foreground = $BrushText
    $body.FontSize = 14
    $body.LineHeight = 21
    $body.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 20
    [System.Windows.Controls.DockPanel]::SetDock($body, "Top")
    $panel.Children.Add($body) | Out-Null

    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = "Horizontal"
    $buttonPanel.HorizontalAlignment = "Right"
    [System.Windows.Controls.DockPanel]::SetDock($buttonPanel, "Bottom")
    $panel.Children.Add($buttonPanel) | Out-Null

    $state = @{ Choice = "" }
    foreach ($choice in $Choices) {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = [string]$choice.Text
        $button.MinWidth = 118
        $button.Height = 32
        $button.Margin = New-Object System.Windows.Thickness -ArgumentList 8, 0, 0, 0
        $button.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 0, 10, 0
        $button.BorderBrush = $BrushTransparent
        $button.Cursor = [System.Windows.Input.Cursors]::Hand
        if ([bool]$choice.Primary) {
            $button.Background = $BrushAccent
            $button.Foreground = $BrushWindow
            $button.IsDefault = $true
        }
        else {
            $button.Background = $BrushSidebarItemSelected
            $button.Foreground = $BrushText
        }
        $choiceValue = [string]$choice.Value
        $button.Add_Click({
            $state["Choice"] = $choiceValue
            $dialog.DialogResult = $true
            $dialog.Close()
        }.GetNewClosure())
        $buttonPanel.Children.Add($button) | Out-Null
    }

    $dialog.ShowDialog() | Out-Null
    return [string]$state["Choice"]
}

$EhTagTranslationNoticeText = "mangaga 可选使用 EhTagTranslation 的标签翻译数据库。该数据库不随软件本体内置；用户可在首次使用 Tag 翻译功能时自行选择下载。EhTagTranslation Database 由 EhTagTranslation 项目及其贡献者维护，数据库文本内容除另有声明外采用 Creative Commons BY-NC-SA 3.0 协议。`nSource: https://github.com/EhTagTranslation/Database"

$Window = New-Object System.Windows.Window
$Window.Title = "mangaga"
$Window.Width = 1240
$Window.Height = 720
$Window.MinWidth = 780
$Window.MinHeight = 420
$Window.WindowStartupLocation = "CenterScreen"
$Window.Background = $BrushWindow
$Window.AllowDrop = $true

$MainGrid = New-Object System.Windows.Controls.Grid
$MainGrid.Background = $BrushWindow

$SidebarColumn = New-Object System.Windows.Controls.ColumnDefinition
$SidebarColumn.Width = New-Object System.Windows.GridLength -ArgumentList 190
$ContentColumn = New-Object System.Windows.Controls.ColumnDefinition
$ContentColumn.Width = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
$StatusColumn = New-Object System.Windows.Controls.ColumnDefinition
$StatusColumn.Width = New-Object System.Windows.GridLength -ArgumentList 300
$MainGrid.ColumnDefinitions.Add($SidebarColumn) | Out-Null
$MainGrid.ColumnDefinitions.Add($ContentColumn) | Out-Null
$MainGrid.ColumnDefinitions.Add($StatusColumn) | Out-Null

$SidebarBorder = New-Object System.Windows.Controls.Border
$SidebarBorder.Background = $BrushSidebar
$SidebarBorder.BorderBrush = New-SolidBrush "#272B34"
$SidebarBorder.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 0, 0, 1, 0
[System.Windows.Controls.Grid]::SetColumn($SidebarBorder, 0)

$CategoryPanel = New-Object System.Windows.Controls.StackPanel
$CategoryPanel.Margin = New-Object System.Windows.Thickness -ArgumentList 12, 18, 12, 12

$CategoryScrollViewer = New-Object System.Windows.Controls.ScrollViewer
$CategoryScrollViewer.VerticalScrollBarVisibility = "Auto"
$CategoryScrollViewer.HorizontalScrollBarVisibility = "Disabled"
$CategoryScrollViewer.Background = $BrushSidebar
$CategoryScrollViewer.AllowDrop = $true
$CategoryScrollViewer.Content = $CategoryPanel
$SidebarBorder.Child = $CategoryScrollViewer

$ContentDock = New-Object System.Windows.Controls.DockPanel
$ContentDock.LastChildFill = $true
[System.Windows.Controls.Grid]::SetColumn($ContentDock, 1)

$StatusBorder = New-Object System.Windows.Controls.Border
$StatusBorder.Background = $BrushSidebar
$StatusBorder.BorderBrush = New-SolidBrush "#272B34"
$StatusBorder.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 1, 0, 0, 0
[System.Windows.Controls.Grid]::SetColumn($StatusBorder, 2)

$StatusDock = New-Object System.Windows.Controls.DockPanel
$StatusDock.LastChildFill = $true

$StatusHeader = New-Object System.Windows.Controls.TextBlock
$StatusHeader.Text = "状态"
$StatusHeader.Foreground = $BrushText
$StatusHeader.FontSize = 14
$StatusHeader.FontWeight = "SemiBold"
$StatusHeader.Margin = New-Object System.Windows.Thickness -ArgumentList 12, 12, 12, 8
[System.Windows.Controls.DockPanel]::SetDock($StatusHeader, "Top")

$StatusConsole = New-Object System.Windows.Controls.TextBox
$StatusConsole.IsReadOnly = $true
$StatusConsole.AcceptsReturn = $true
$StatusConsole.AcceptsTab = $false
$StatusConsole.TextWrapping = "Wrap"
$StatusConsole.VerticalScrollBarVisibility = "Auto"
$StatusConsole.HorizontalScrollBarVisibility = "Disabled"
$StatusConsole.Background = $BrushSidebar
$StatusConsole.Foreground = $BrushMuted
$StatusConsole.BorderBrush = $BrushTransparent
$StatusConsole.FontFamily = New-Object System.Windows.Media.FontFamily -ArgumentList "Consolas"
$StatusConsole.FontSize = 12
$StatusConsole.Padding = New-Object System.Windows.Thickness -ArgumentList 12, 4, 12, 12
$StatusConsole.Cursor = [System.Windows.Input.Cursors]::IBeam

$StatusDock.Children.Add($StatusHeader) | Out-Null
$StatusDock.Children.Add($StatusConsole) | Out-Null
$StatusBorder.Child = $StatusDock

$RecognitionBar = New-Object System.Windows.Controls.Border
$RecognitionBar.Height = 62
$RecognitionBar.Background = $BrushSidebar
$RecognitionBar.BorderBrush = New-SolidBrush "#272B34"
$RecognitionBar.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 0, 1, 0, 0
$RecognitionBar.Visibility = "Collapsed"
[System.Windows.Controls.DockPanel]::SetDock($RecognitionBar, "Bottom")

$RecognitionGrid = New-Object System.Windows.Controls.Grid
$RecognitionGrid.Margin = New-Object System.Windows.Thickness -ArgumentList 18, 10, 18, 10
$RecognitionTextColumn = New-Object System.Windows.Controls.ColumnDefinition
$RecognitionTextColumn.Width = New-Object System.Windows.GridLength -ArgumentList 230
$RecognitionProgressColumn = New-Object System.Windows.Controls.ColumnDefinition
$RecognitionProgressColumn.Width = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
$RecognitionButtonColumn = New-Object System.Windows.Controls.ColumnDefinition
$RecognitionButtonColumn.Width = New-Object System.Windows.GridLength -ArgumentList 178
$RecognitionGrid.ColumnDefinitions.Add($RecognitionTextColumn) | Out-Null
$RecognitionGrid.ColumnDefinitions.Add($RecognitionProgressColumn) | Out-Null
$RecognitionGrid.ColumnDefinitions.Add($RecognitionButtonColumn) | Out-Null

$RecognitionStatusText = New-Object System.Windows.Controls.TextBlock
$RecognitionStatusText.Foreground = $BrushText
$RecognitionStatusText.FontSize = 13
$RecognitionStatusText.VerticalAlignment = "Center"
$RecognitionStatusText.TextTrimming = "CharacterEllipsis"
[System.Windows.Controls.Grid]::SetColumn($RecognitionStatusText, 0)

$RecognitionProgress = New-Object System.Windows.Controls.ProgressBar
$RecognitionProgress.Height = 10
$RecognitionProgress.Minimum = 0
$RecognitionProgress.Maximum = 1
$RecognitionProgress.Value = 0
$RecognitionProgress.VerticalAlignment = "Center"
$RecognitionProgress.Margin = New-Object System.Windows.Thickness -ArgumentList 8, 0, 16, 0
$RecognitionProgress.Foreground = $BrushAccent
$RecognitionProgress.Background = $BrushCover
[System.Windows.Controls.Grid]::SetColumn($RecognitionProgress, 1)

$RecognitionButtons = New-Object System.Windows.Controls.StackPanel
$RecognitionButtons.Orientation = "Horizontal"
$RecognitionButtons.HorizontalAlignment = "Right"
$RecognitionButtons.VerticalAlignment = "Center"
[System.Windows.Controls.Grid]::SetColumn($RecognitionButtons, 2)

$RecognitionStartButton = New-Object System.Windows.Controls.Button
$RecognitionStartButton.Content = "开始识别"
$RecognitionStartButton.Width = 82
$RecognitionStartButton.Height = 32
$RecognitionStartButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
$RecognitionStartButton.Background = $BrushAccent
$RecognitionStartButton.Foreground = $BrushWindow
$RecognitionStartButton.BorderBrush = $BrushTransparent
$RecognitionStartButton.Cursor = [System.Windows.Input.Cursors]::Hand

$RecognitionPauseButton = New-Object System.Windows.Controls.Button
$RecognitionPauseButton.Content = "暂停识别"
$RecognitionPauseButton.Width = 82
$RecognitionPauseButton.Height = 32
$RecognitionPauseButton.Background = $BrushSidebarItemSelected
$RecognitionPauseButton.Foreground = $BrushText
$RecognitionPauseButton.BorderBrush = $BrushTransparent
$RecognitionPauseButton.Cursor = [System.Windows.Input.Cursors]::Hand

$RecognitionButtons.Children.Add($RecognitionStartButton) | Out-Null
$RecognitionButtons.Children.Add($RecognitionPauseButton) | Out-Null
$RecognitionGrid.Children.Add($RecognitionStatusText) | Out-Null
$RecognitionGrid.Children.Add($RecognitionProgress) | Out-Null
$RecognitionGrid.Children.Add($RecognitionButtons) | Out-Null
$RecognitionBar.Child = $RecognitionGrid

$ContentDock.Children.Add($RecognitionBar) | Out-Null

$ShelfToolbar = New-Object System.Windows.Controls.DockPanel
$ShelfToolbar.Height = 42
$ShelfToolbar.Margin = New-Object System.Windows.Thickness -ArgumentList 22, 16, 22, 0
$ShelfToolbar.LastChildFill = $false
[System.Windows.Controls.DockPanel]::SetDock($ShelfToolbar, "Top")

$SortPanel = New-Object System.Windows.Controls.StackPanel
$SortPanel.Orientation = "Horizontal"
$SortPanel.HorizontalAlignment = "Right"
$SortPanel.VerticalAlignment = "Center"
[System.Windows.Controls.DockPanel]::SetDock($SortPanel, "Right")

$SortLabel = New-Object System.Windows.Controls.TextBlock
$SortLabel.Text = "排序"
$SortLabel.Foreground = $BrushMuted
$SortLabel.FontSize = 13
$SortLabel.VerticalAlignment = "Center"
$SortLabel.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0

$SortComboBox = New-Object System.Windows.Controls.ComboBox
$SortComboBox.Width = 128
$SortComboBox.Height = 30
$SortComboBox.Background = $BrushCard
$SortComboBox.Foreground = $BrushText
$SortComboBox.BorderBrush = $BrushMuted
$SortComboBox.Cursor = [System.Windows.Input.Cursors]::Hand
$SortComboBox.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $BrushCard
$SortComboBox.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $BrushCard
$SortComboBox.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $BrushText
$SortComboBox.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $BrushSidebarItemSelected
$SortComboBox.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $BrushText

function Add-SortOptionItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $item = New-Object System.Windows.Controls.ComboBoxItem
    $item.Content = $Label
    $item.Tag = $Key
    $item.Background = $BrushCard
    $item.Foreground = $BrushText
    $item.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 5, 10, 5
    $item.MinHeight = 28
    $item.Add_MouseEnter({
        param($sender, $eventArgs)
        $sender.Background = $BrushCardHover
        $sender.Foreground = $BrushText
    })
    $item.Add_MouseLeave({
        param($sender, $eventArgs)
        $sender.Background = $BrushCard
        $sender.Foreground = $BrushText
    })
    $SortComboBox.Items.Add($item) | Out-Null
}

Add-SortOptionItem -Key "default" -Label "当前顺序"
Add-SortOptionItem -Key "name" -Label "名称"
Add-SortOptionItem -Key "pageCount" -Label "页数"
Add-SortOptionItem -Key "addedAt" -Label "添加时间"
$SortComboBox.SelectedIndex = 0

$SortPanel.Children.Add($SortLabel) | Out-Null
$SortPanel.Children.Add($SortComboBox) | Out-Null
$ShelfToolbar.Children.Add($SortPanel) | Out-Null
$ContentDock.Children.Add($ShelfToolbar) | Out-Null

$ShelfScrollViewer = New-Object System.Windows.Controls.ScrollViewer
$ShelfScrollViewer.Background = $BrushWindow
$ShelfScrollViewer.VerticalScrollBarVisibility = "Auto"
$ShelfScrollViewer.HorizontalScrollBarVisibility = "Disabled"
$ShelfScrollViewer.CanContentScroll = $false

$ShelfSelectionHost = New-Object System.Windows.Controls.Grid
$ShelfSelectionHost.Margin = New-Object System.Windows.Thickness -ArgumentList 22, 8, 22, 22
$ShelfSelectionHost.ClipToBounds = $true

$ShelfStackPanel = New-Object System.Windows.Controls.StackPanel
$ShelfStackPanel.Orientation = "Vertical"

$ShelfTopSpacer = New-Object System.Windows.Controls.Border
$ShelfTopSpacer.Height = 0

$ShelfPanel = New-Object System.Windows.Controls.WrapPanel
$ShelfPanel.HorizontalAlignment = "Left"
$ShelfPanel.ItemWidth = 176
$ShelfPanel.ItemHeight = 288

$ShelfBottomSpacer = New-Object System.Windows.Controls.Border
$ShelfBottomSpacer.Height = 0

$ShelfStackPanel.Children.Add($ShelfTopSpacer) | Out-Null
$ShelfStackPanel.Children.Add($ShelfPanel) | Out-Null
$ShelfStackPanel.Children.Add($ShelfBottomSpacer) | Out-Null
$ShelfScrollViewer.Content = $ShelfStackPanel

$ShelfSelectionBox = New-Object System.Windows.Controls.Border
$ShelfSelectionBox.Background = New-SolidBrush "#33D8B45F"
$ShelfSelectionBox.BorderBrush = $BrushAccent
$ShelfSelectionBox.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 1
$ShelfSelectionBox.HorizontalAlignment = "Left"
$ShelfSelectionBox.VerticalAlignment = "Top"
$ShelfSelectionBox.Visibility = "Collapsed"
$ShelfSelectionBox.IsHitTestVisible = $false
[System.Windows.Controls.Panel]::SetZIndex($ShelfSelectionBox, 10)

$ShelfSelectionHost.Children.Add($ShelfScrollViewer) | Out-Null
$ShelfSelectionHost.Children.Add($ShelfSelectionBox) | Out-Null
$ContentDock.Children.Add($ShelfSelectionHost) | Out-Null
$ScrollViewer = $ShelfScrollViewer

$MainGrid.Children.Add($SidebarBorder) | Out-Null
$MainGrid.Children.Add($ContentDock) | Out-Null
$MainGrid.Children.Add($StatusBorder) | Out-Null
$Window.Content = $MainGrid
$Window.Dispatcher.Add_UnhandledException({
    param($sender, $eventArgs)

    $message = "操作失败。"
    if ($eventArgs.Exception) {
        $message = Get-UserFacingErrorMessage -RawMessage ([string]$eventArgs.Exception.Message)
        Write-AppLog -Message "界面操作异常" -Detail $eventArgs.Exception.ToString()
    }

    try {
        Add-StatusLine -Message "界面操作异常：$message"
        Show-AppMessage -Message $message -Caption "操作失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    catch {
    }

    $eventArgs.Handled = $true
})

$LibraryItems = @()
$AllLibraryItems = @()
$AllLibraryItemById = @{}
$LibraryCategories = @()
$SelectedIds = New-Object 'System.Collections.Generic.HashSet[string]'
$CardById = @{}
$CoverBitmapCache = @{}
$CoverBitmapCacheOrder = New-Object 'System.Collections.Generic.List[string]'
$CoverBitmapCacheMax = 500
$CategoryButtons = @{}
$CategoryCountByName = @{}
$CategoryItemsByName = @{}
$ShelfMetadataDirty = $true
$ShelfColumnCount = 1
$ShelfRenderVersion = 0
$ShelfRenderedCategory = ""
$ShelfBatchSize = 50
$ShelfBufferBatches = 1
$ShelfRenderStartIndex = -1
$ShelfRenderEndIndex = -1
$ShelfElementByIndex = @{}
$ShelfPlaceholderCount = 0
$ShelfIsRendering = $false
$ShelfBuildQueue = New-Object 'System.Collections.Generic.Queue[int]'
$ShelfQueuedBuildIndexes = New-Object 'System.Collections.Generic.HashSet[int]'
$ShelfBuildBatchSize = 3
$ShelfPreheatQueue = New-Object 'System.Collections.Generic.Queue[int]'
$ShelfQueuedPreheatIndexes = New-Object 'System.Collections.Generic.HashSet[int]'
$ShelfPreheatBatchSize = 1
$ShelfScrollJumpThreshold = 864
$ShelfRefreshQueued = $false
$RemovalViewRefreshIds = New-Object 'System.Collections.Generic.HashSet[string]'
$RemovalViewRefreshQueued = $false
$CardWidth = 176
$CardHeight = 288
$ReaderPrefetchCount = 25
$StatusLines = New-Object 'System.Collections.Generic.List[string]'
$StatusMaxLines = 500
$LibraryLoaded = $false
$LastSelectedIndex = -1
$SelectionVisualUpdatePending = $false
$ShelfDragSelectArmed = $false
$ShelfDragSelectActive = $false
$ShelfDragSelectStartPoint = $null
$ShelfDragSelectLastPoint = $null
$ShelfDragSelectAppend = $false
$ShelfDragSelectBaseIds = New-Object 'System.Collections.Generic.HashSet[string]'
$SessionId = [System.Guid]::NewGuid().ToString("N")
$CurrentCategory = "全部"
$CurrentSortMode = "default"
$CategoryDragFormat = "mangagaCategory"
$CategoryDragStartPoint = $null
$CategoryDragDidStart = $false
$FavoriteCategory = "喜爱"
$PendingCategory = "待确认"
$RecognizingCategory = "识别中"
$NeedPasswordCategory = "需要密码"
$TagNotFoundCategory = "tag未找到"
$DuplicateCategory = "重复项"
$TitleStatusRecognizing = "recognizing"
$TitleStatusPending = "pending"
$TagStatusNotFound = "not_found"
$DuplicateResultsPath = Join-Path $DataDir "duplicates.json"
$PendingRemovalPath = Join-Path $DataDir "pending-removals.json"
$PendingRemovalIds = New-Object 'System.Collections.Generic.HashSet[string]'
$PendingRemovalsLoaded = $false
$DuplicateItemIds = New-Object 'System.Collections.Generic.HashSet[string]'
$VersionGroupByItemId = @{}
$VersionGroupMembersById = @{}
$VersionGroupItemsById = @{}
$RecognitionRunning = $false
$RecognitionPaused = $true
$RecognitionProcess = $null
$RecognitionCurrentId = ""
$RecognitionCurrentName = ""
$RecognitionProgressPath = ""
$RecognitionPausePath = ""
$RecognitionLastStatus = ""
$RecognitionDetailText = ""
$RecognitionItemProgress = 0
$RecognitionItemTotal = 0
$RecognitionTotal = 0
$RecognitionCompleted = 0
$AddRunning = $false
$AddProcess = $null
$AddQueue = New-Object 'System.Collections.Generic.List[string]'
$AddResultPath = ""
$AddPathsPath = ""
$AddProgressPath = ""
$AddProgressPosition = [int64]0
$AddProgressRemainder = ""
$AddBatchCount = 0
$AddPendingVisualRefresh = $false
$AddLastVisualRefreshAt = [DateTime]::MinValue
$TagRunning = $false
$TagProcess = $null
$TagResultPath = ""
$TagProgressPath = ""
$TagProgressPosition = [int64]0
$TagProgressRemainder = ""
$TagBatchCount = 0
$TagShowSummary = $false
$DuplicateRunning = $false
$DuplicateProcess = $null
$DuplicateResultPath = ""
$DuplicateIdsPath = ""
$DuplicateProgressPath = ""
$DuplicateProgressPosition = [int64]0
$DuplicateProgressRemainder = ""
$DuplicateBatchCount = 0
$RemoveRunning = $false
$RemoveProcess = $null
$RemoveResultPath = ""
$RemoveIdsPath = ""
$RemoveBatchCount = 0
$RemoveCurrentIds = @()
$RemovePendingIds = New-Object 'System.Collections.Generic.HashSet[string]'
$RemoveDeferredIds = New-Object 'System.Collections.Generic.HashSet[string]'
$RemoveStartQueued = $false

function Resolve-CoverPath($Item) {
    if (-not $Item.cover) {
        return $null
    }

    $cover = [string]$Item.cover
    if ([System.IO.Path]::IsPathRooted($cover)) {
        return $cover
    }

    return Join-Path $DataDir $cover
}

function Get-CoverBitmap([string]$CoverPath) {
    if ([string]::IsNullOrWhiteSpace($CoverPath) -or -not (Test-Path -LiteralPath $CoverPath)) {
        return $null
    }

    $cacheKey = [string]$CoverPath
    if ($CoverBitmapCache.ContainsKey($cacheKey)) {
        return $CoverBitmapCache[$cacheKey]
    }

    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object System.Uri -ArgumentList $CoverPath
        $bitmap.EndInit()
        $bitmap.Freeze()

        $Script:CoverBitmapCache[$cacheKey] = $bitmap
        $CoverBitmapCacheOrder.Add($cacheKey) | Out-Null
        while ($CoverBitmapCacheOrder.Count -gt $CoverBitmapCacheMax) {
            $oldKey = [string]$CoverBitmapCacheOrder[0]
            $CoverBitmapCacheOrder.RemoveAt(0)
            if ($Script:CoverBitmapCache.ContainsKey($oldKey)) {
                $Script:CoverBitmapCache.Remove($oldKey)
            }
        }

        return $bitmap
    }
    catch {
        return $null
    }
}

function New-CoverImage([string]$CoverPath) {
    $image = New-Object System.Windows.Controls.Image
    $image.Stretch = "UniformToFill"
    $image.HorizontalAlignment = "Center"
    $image.VerticalAlignment = "Center"

    $bitmap = Get-CoverBitmap $CoverPath
    if ($bitmap) {
        $image.Source = $bitmap
    }

    return $image
}

function Test-SourceMissingError([string]$Message) {
    $text = [string]$Message
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    return $text -match "原始(压缩包|文件夹)不存在|原文件不存在|不存在或无法访问|No such file|does not exist|FileNotFoundError"
}

function Get-UserFacingErrorMessage {
    param(
        [string]$RawMessage,

        [string]$Fallback = "操作失败，详情已记录到日志。"
    )

    $text = ([string]$RawMessage).Trim()
    if (Test-SourceMissingError $text) {
        return "原文件不存在"
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Fallback
    }

    if ($text -match "Traceback|usage:|Exception|Error:|RuntimeError|ValueError|FileNotFoundError") {
        return $Fallback
    }

    $line = (($text -split "(\r?\n)+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $Fallback
    }

    if ($line.Length -gt 80) {
        return $Fallback
    }
    return [string]$line
}

function Invoke-ScannerJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$ErrorCaption = "操作失败"
    )

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $PythonPath
        $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $process.Dispose()
    }
    catch {
        $detail = $_.Exception.ToString()
        Write-AppLog -Message "$ErrorCaption：启动扫描器失败" -Detail $detail
        Add-StatusLine -Message "$ErrorCaption：操作失败，详情已记录"
        Show-AppMessage -Message "操作失败，详情已记录到日志。" -Caption $ErrorCaption -Image ([System.Windows.MessageBoxImage]::Error)
        return $null
    }

    $text = ([string]$stdout).Trim()
    $errorText = ([string]$stderr).Trim()

    if ($exitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($errorText)) {
            $text = $errorText
        }
        elseif ([string]::IsNullOrWhiteSpace($text)) {
            $text = "扫描器异常退出。"
        }
        $detail = "ExitCode: $exitCode`r`nArguments: $($Arguments -join ' ')`r`nSTDOUT:`r`n$stdout`r`nSTDERR:`r`n$stderr"
        Write-AppLog -Message "$ErrorCaption：扫描器异常退出" -Detail $detail
        $userMessage = Get-UserFacingErrorMessage -RawMessage $text
        Add-StatusLine -Message "$ErrorCaption：$userMessage"
        Show-AppMessage -Message $userMessage -Caption $ErrorCaption -Image ([System.Windows.MessageBoxImage]::Error)
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return $text | ConvertFrom-Json
    }
    catch {
        $detail = "Arguments: $($Arguments -join ' ')`r`nParseError: $($_.Exception.ToString())`r`nOutput:`r`n$text"
        Write-AppLog -Message "$ErrorCaption：扫描器返回内容无法解析" -Detail $detail
        Add-StatusLine -Message "$ErrorCaption：结果解析失败，详情已记录"
        Show-AppMessage -Message "操作失败，详情已记录到日志。" -Caption $ErrorCaption -Image ([System.Windows.MessageBoxImage]::Error)
        return $null
    }
}

function Clear-SessionCache {
    param(
        [string]$TargetSessionId = ""
    )

    if ([string]::IsNullOrWhiteSpace($TargetSessionId)) {
        $arguments = @($ScannerPath, "clear-session-cache", "--data-dir", $DataDir)
    }
    else {
        $arguments = @($ScannerPath, "clear-session-cache", "--data-dir", $DataDir, "--session-id", $TargetSessionId)
    }

    Invoke-ScannerJson -Arguments $arguments -ErrorCaption "清理缓存失败" | Out-Null
}

function Ensure-PendingRemovalsLoaded {
    if ($PendingRemovalsLoaded) {
        return
    }

    $set = New-SelectedIdSet
    if (-not [string]::IsNullOrWhiteSpace($PendingRemovalPath) -and (Test-Path -LiteralPath $PendingRemovalPath)) {
        try {
            $data = Get-Content -LiteralPath $PendingRemovalPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $rawIds = @()
            if ($null -ne $data.ids) {
                $rawIds = @($data.ids)
            }
            elseif ($null -ne $data.items) {
                $rawIds = @($data.items | ForEach-Object {
                    if ($null -ne $_.id) { $_.id } else { $_ }
                })
            }
            else {
                $rawIds = @($data)
            }

            foreach ($rawId in $rawIds) {
                $itemId = ([string]$rawId).Trim()
                if (-not [string]::IsNullOrWhiteSpace($itemId)) {
                    $set.Add($itemId) | Out-Null
                }
            }
        }
        catch {
            Write-AppLog -Message "读取待完成移除记录失败" -Detail $_.Exception.ToString()
        }
    }

    $Script:PendingRemovalIds = $set
    $Script:PendingRemovalsLoaded = $true
}

function Get-PendingRemovalIdArray {
    Ensure-PendingRemovalsLoaded
    return [string[]]@($PendingRemovalIds | ForEach-Object { [string]$_ })
}

function Save-PendingRemovals {
    Ensure-PendingRemovalsLoaded

    [string[]]$ids = @(Get-PendingRemovalIdArray | Sort-Object -Unique)
    $tmpPath = ""
    try {
        if ($ids.Count -eq 0) {
            if (Test-Path -LiteralPath $PendingRemovalPath) {
                Remove-Item -LiteralPath $PendingRemovalPath -Force
            }
            return $true
        }

        $payload = [ordered]@{
            version = 1
            updatedAt = (Get-Date).ToUniversalTime().ToString("o")
            ids = @($ids)
        }
        $dir = Split-Path -Parent $PendingRemovalPath
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $tmpPath = Join-Path $dir ("pending-removals.{0}.tmp" -f [System.Guid]::NewGuid().ToString("N"))
        ConvertTo-Json -InputObject $payload -Depth 5 | Set-Content -LiteralPath $tmpPath -Encoding UTF8
        Move-Item -LiteralPath $tmpPath -Destination $PendingRemovalPath -Force
        return $true
    }
    catch {
        Write-AppLog -Message "保存待完成移除记录失败" -Detail $_.Exception.ToString()
        if (-not [string]::IsNullOrWhiteSpace($tmpPath) -and (Test-Path -LiteralPath $tmpPath)) {
            try {
                Remove-Item -LiteralPath $tmpPath -Force
            }
            catch {
            }
        }
        return $false
    }
}

function Add-PendingRemovals {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    Ensure-PendingRemovalsLoaded
    $added = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rawId in @($Ids)) {
        $itemId = ([string]$rawId).Trim()
        if ([string]::IsNullOrWhiteSpace($itemId)) {
            continue
        }
        if ($PendingRemovalIds.Add($itemId)) {
            $added.Add($itemId) | Out-Null
        }
    }

    if ($added.Count -eq 0) {
        return $true
    }

    if (Save-PendingRemovals) {
        return $true
    }

    foreach ($itemId in @($added)) {
        $PendingRemovalIds.Remove([string]$itemId) | Out-Null
    }
    return $false
}

function Clear-PendingRemovals {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    Ensure-PendingRemovalsLoaded
    $removed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rawId in @($Ids)) {
        $itemId = ([string]$rawId).Trim()
        if ([string]::IsNullOrWhiteSpace($itemId)) {
            continue
        }
        if ($PendingRemovalIds.Remove($itemId)) {
            $removed.Add($itemId) | Out-Null
        }
    }

    if ($removed.Count -eq 0) {
        return $true
    }

    if (Save-PendingRemovals) {
        return $true
    }

    foreach ($itemId in @($removed)) {
        $PendingRemovalIds.Add([string]$itemId) | Out-Null
    }
    return $false
}

function Hide-PendingRemovalItems {
    param(
        [Parameter(Mandatory = $true)]
        $Library
    )

    Ensure-PendingRemovalsLoaded
    if ($PendingRemovalIds.Count -eq 0 -or $null -eq $Library.items) {
        return $Library
    }

    $Library.items = @($Library.items | Where-Object {
        $itemId = ([string]$_.id).Trim()
        [string]::IsNullOrWhiteSpace($itemId) -or -not $PendingRemovalIds.Contains($itemId)
    })
    return $Library
}

function Item-IsPendingRemoval($Item) {
    if ($null -eq $Item) {
        return $false
    }

    Ensure-PendingRemovalsLoaded
    if ($PendingRemovalIds.Count -eq 0) {
        return $false
    }

    $itemId = ([string]$Item.id).Trim()
    return (-not [string]::IsNullOrWhiteSpace($itemId) -and $PendingRemovalIds.Contains($itemId))
}

function Get-LibraryData {
    $data = Invoke-ScannerJson -Arguments @($ScannerPath, "list", "--data-dir", $DataDir) -ErrorCaption "读取书架失败"
    if ($null -eq $data) {
        return (Hide-PendingRemovalItems -Library ([pscustomobject]@{
            version = 1
            items = @()
            categories = @("热血", "恋爱", "悬疑")
        }))
    }
    return (Hide-PendingRemovalItems -Library $data)
}

function Is-SystemCategoryName([string]$Category) {
    $name = ([string]$Category).Trim()
    return $name -eq "全部" -or
        $name -eq "未分类" -or
        $name -eq $FavoriteCategory -or
        $name -eq $PendingCategory -or
        $name -eq $RecognizingCategory -or
        $name -eq $NeedPasswordCategory -or
        $name -eq $TagNotFoundCategory -or
        $name -eq $DuplicateCategory
}

function Refresh-DuplicateItemCache {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    if (-not [string]::IsNullOrWhiteSpace($DuplicateResultsPath) -and (Test-Path -LiteralPath $DuplicateResultsPath)) {
        try {
            $data = Get-Content -LiteralPath $DuplicateResultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $ids = @()
            $hasGroups = $false
            if ($null -ne $data.groups) {
                $hasGroups = @($data.groups).Count -gt 0
                foreach ($group in @($data.groups)) {
                    if ([string]$group.kind -eq "exact") {
                        $ids += @($group.itemIds)
                    }
                }
            }
            if ($ids.Count -eq 0 -and $null -ne $data.summary -and $null -ne $data.summary.exactItemIds) {
                $ids = @($data.summary.exactItemIds)
            }
            elseif ($ids.Count -eq 0 -and -not $hasGroups -and $null -ne $data.summary -and $null -ne $data.summary.itemIds) {
                $ids = @($data.summary.itemIds)
            }

            foreach ($itemId in $ids) {
                $value = ([string]$itemId).Trim()
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $set.Add($value) | Out-Null
                }
            }
        }
        catch {
        }
    }

    $Script:DuplicateItemIds = $set
}

function Item-IsDuplicateResult($Item) {
    if ($null -eq $Item) {
        return $false
    }
    return $DuplicateItemIds.Contains([string]$Item.id)
}

function Get-StableShortHash([string]$Value) {
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha1.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 16)
    }
    finally {
        $sha1.Dispose()
    }
}

function Rebuild-AllLibraryItemIndex {
    $index = @{}
    foreach ($item in @($AllLibraryItems)) {
        $itemId = ([string]$item.id).Trim()
        if (-not [string]::IsNullOrWhiteSpace($itemId)) {
            $index[$itemId] = $item
        }
    }
    $Script:AllLibraryItemById = $index
}

function Get-AllLibraryItemById([string]$ItemId) {
    $key = ([string]$ItemId).Trim()
    if (-not [string]::IsNullOrWhiteSpace($key) -and $AllLibraryItemById.ContainsKey($key)) {
        return $AllLibraryItemById[$key]
    }
    return $null
}

function New-SelectedIdSet {
    param(
        [object[]]$Ids = @()
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($rawId in @($Ids)) {
        $itemId = ([string]$rawId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($itemId)) {
            $set.Add($itemId) | Out-Null
        }
    }
    return ,$set
}

function Ensure-SelectedIdsHashSet {
    if ($SelectedIds -is [System.Collections.Generic.HashSet[string]]) {
        return
    }

    $Script:SelectedIds = New-SelectedIdSet -Ids @($SelectedIds)
}

function Get-SelectedSingleRealItem {
    $ids = @(Resolve-RealItemIds -Ids @($SelectedIds))
    if ($ids.Count -ne 1) {
        return $null
    }

    return Get-AllLibraryItemById ([string]$ids[0])
}

function Get-ItemSourcePath($Item) {
    if ($null -eq $Item -or [bool]$Item.isVersionGroup) {
        return ""
    }

    if ([string]$Item.kind -eq "folder") {
        return ([string]$Item.comicPath).Trim()
    }

    if ([string]$Item.kind -eq "archive") {
        return ([string]$Item.sourcePath).Trim()
    }

    $sourcePath = ([string]$Item.sourcePath).Trim()
    if (-not [string]::IsNullOrWhiteSpace($sourcePath)) {
        return $sourcePath
    }
    return ([string]$Item.comicPath).Trim()
}

function Open-ItemSourceLocation($Item) {
    $path = Get-ItemSourcePath $Item
    if ([string]::IsNullOrWhiteSpace($path)) {
        Show-AppMessage -Message "没有找到这个作品的原文件路径。" -Caption "打开原文件位置" -Image ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    if (-not [System.IO.File]::Exists($path) -and -not [System.IO.Directory]::Exists($path)) {
        Write-AppLog -Message "打开原文件位置：原文件不存在" -Detail $path
        Add-StatusLine -Message "打开原文件位置：原文件不存在"
        Show-AppMessage -Message "原文件不存在" -Caption "打开原文件位置" -Image ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "explorer.exe"
        $psi.Arguments = "/select,`"$path`""
        $psi.UseShellExecute = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }
    catch {
        Write-AppLog -Message "打开资源管理器失败" -Detail $_.Exception.ToString()
        Add-StatusLine -Message "打开原文件位置失败，详情已记录"
        Show-AppMessage -Message "操作失败，详情已记录到日志。" -Caption "打开原文件位置" -Image ([System.Windows.MessageBoxImage]::Error)
    }
}

function Normalize-SortMode([string]$Mode) {
    $modeKey = ([string]$Mode).Trim()
    if ($modeKey -in @("default", "name", "pageCount", "addedAt")) {
        return $modeKey
    }
    return "default"
}

function Get-EffectiveSortMode {
    $mode = Normalize-SortMode $CurrentSortMode
    if ($mode -eq "default" -and $CurrentCategory -eq $DuplicateCategory) {
        return "name"
    }
    return $mode
}

function Get-ItemSortName($Item) {
    return ([string]$Item.name).Trim()
}

function Get-ItemSortPageCount($Item) {
    $pageCount = 0
    [int]::TryParse([string]$Item.pageCount, [ref]$pageCount) | Out-Null
    return $pageCount
}

function Get-ItemSortAddedTicks($Item) {
    $value = ([string]$Item.addedAt).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return [int64]0
    }

    try {
        return [DateTimeOffset]::Parse($value).UtcTicks
    }
    catch {
        return [int64]0
    }
}

function Apply-LibrarySort {
    param(
        [object[]]$Items
    )

    $itemsToSort = @($Items)
    $mode = Get-EffectiveSortMode
    if ($mode -eq "default") {
        return $itemsToSort
    }

    if ($mode -eq "name") {
        return @($itemsToSort | Sort-Object @{ Expression = { Get-ItemSortName $_ }; Ascending = $true }, @{ Expression = { [string]$_.id }; Ascending = $true })
    }

    if ($mode -eq "pageCount") {
        return @($itemsToSort | Sort-Object @{ Expression = { Get-ItemSortPageCount $_ }; Ascending = $true }, @{ Expression = { Get-ItemSortName $_ }; Ascending = $true }, @{ Expression = { [string]$_.id }; Ascending = $true })
    }

    if ($mode -eq "addedAt") {
        return @($itemsToSort | Sort-Object @{ Expression = { Get-ItemSortAddedTicks $_ }; Descending = $true }, @{ Expression = { Get-ItemSortName $_ }; Ascending = $true }, @{ Expression = { [string]$_.id }; Ascending = $true })
    }

    return $itemsToSort
}

function Set-LibrarySortMode([string]$Mode) {
    $mode = Normalize-SortMode $Mode
    if ($CurrentSortMode -eq $mode) {
        return
    }

    $Script:CurrentSortMode = $mode
    $Script:LastSelectedIndex = -1
    $ShelfScrollViewer.ScrollToVerticalOffset(0)
    Render-Library -Reload:$false -PreservePage:$true -RefreshMetadata:$false
}

function Refresh-VersionGroupCache {
    $Script:VersionGroupByItemId = @{}
    $Script:VersionGroupMembersById = @{}
    $Script:VersionGroupItemsById = @{}

    if ([string]::IsNullOrWhiteSpace($DuplicateResultsPath) -or -not (Test-Path -LiteralPath $DuplicateResultsPath)) {
        return
    }

    $existingIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $itemOrder = @{}
    for ($index = 0; $index -lt @($AllLibraryItems).Count; $index++) {
        if (Item-IsPendingRemoval $AllLibraryItems[$index]) {
            continue
        }
        $itemId = [string]$AllLibraryItems[$index].id
        if (-not [string]::IsNullOrWhiteSpace($itemId)) {
            $existingIds.Add($itemId) | Out-Null
            $itemOrder[$itemId] = $index
        }
    }

    if ($existingIds.Count -eq 0) {
        return
    }

    $components = New-Object 'System.Collections.Generic.List[object]'
    try {
        $data = Get-Content -LiteralPath $DuplicateResultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $exactIds = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($group in @($data.groups)) {
            if ([string]$group.kind -ne "exact") {
                continue
            }

            foreach ($rawId in @($group.itemIds)) {
                $itemId = ([string]$rawId).Trim()
                if (-not [string]::IsNullOrWhiteSpace($itemId) -and $existingIds.Contains($itemId)) {
                    $exactIds.Add($itemId) | Out-Null
                }
            }
        }

        foreach ($group in @($data.groups)) {
            $groupKind = [string]$group.kind
            if ($groupKind -ne "similar" -and $groupKind -ne "series") {
                continue
            }

            $ids = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($rawId in @($group.itemIds)) {
                $itemId = ([string]$rawId).Trim()
                if (-not [string]::IsNullOrWhiteSpace($itemId) -and $existingIds.Contains($itemId) -and -not $exactIds.Contains($itemId)) {
                    $ids.Add($itemId) | Out-Null
                }
            }
            if ($ids.Count -lt 2) {
                continue
            }

            $overlapIndexes = New-Object 'System.Collections.Generic.List[int]'
            for ($componentIndex = 0; $componentIndex -lt $components.Count; $componentIndex++) {
                $component = $components[$componentIndex]
                foreach ($itemId in $ids) {
                    if ($component.Ids.Contains($itemId)) {
                        $overlapIndexes.Add($componentIndex) | Out-Null
                        break
                    }
                }
            }

            if ($overlapIndexes.Count -eq 0) {
                $components.Add([pscustomobject]@{
                    Ids = $ids
                    HasSeries = ($groupKind -eq "series")
                }) | Out-Null
                continue
            }

            $target = $components[$overlapIndexes[0]]
            foreach ($itemId in $ids) {
                $target.Ids.Add($itemId) | Out-Null
            }
            if ($groupKind -eq "series") {
                $target.HasSeries = $true
            }
            for ($i = $overlapIndexes.Count - 1; $i -ge 1; $i--) {
                $mergeIndex = [int]$overlapIndexes[$i]
                foreach ($itemId in $components[$mergeIndex].Ids) {
                    $target.Ids.Add($itemId) | Out-Null
                }
                if ([bool]$components[$mergeIndex].HasSeries) {
                    $target.HasSeries = $true
                }
                $components.RemoveAt($mergeIndex)
            }
        }
    }
    catch {
        return
    }

    foreach ($component in $components) {
        if ($component.Ids.Count -lt 2) {
            continue
        }

        $members = @($component.Ids | Sort-Object {
            $key = [string]$_
            if ($itemOrder.ContainsKey($key)) {
                [int]$itemOrder[$key]
            }
            else {
                [int]::MaxValue
            }
        })
        if ($members.Count -lt 2) {
            continue
        }

        $groupId = "__versions__:" + (Get-StableShortHash (($members | Sort-Object) -join "|"))
        $representative = Get-AllLibraryItemById ([string]$members[0])
        if ($null -eq $representative) {
            continue
        }

        $displaySet = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($itemId in $members) {
            $memberItem = Get-AllLibraryItemById ([string]$itemId)
            if ($null -eq $memberItem) {
                continue
            }
            foreach ($category in @(Get-DisplayCategories $memberItem)) {
                $categoryName = ([string]$category).Trim()
                if (-not [string]::IsNullOrWhiteSpace($categoryName)) {
                    $displaySet.Add($categoryName) | Out-Null
                }
            }
        }
        $displayCategories = @($displaySet | Sort-Object)
        $groupLabel = if ([bool]$component.HasSeries) { "连载" } else { "版本" }

        $versionItem = [pscustomobject]@{
            id = $groupId
            name = [string]$representative.name
            cover = [string]$representative.cover
            pageCount = $representative.pageCount
            addedAt = [string]$representative.addedAt
            categories = @($representative.categories)
            titleStatus = [string]$representative.titleStatus
            requiresPassword = [bool]$representative.requiresPassword
            isVersionGroup = $true
            versionCount = $members.Count
            versionIds = @($members)
            versionGroupLabel = $groupLabel
            versionGroupKind = if ([bool]$component.HasSeries) { "series" } else { "similar" }
            displayCategories = $displayCategories
        }

        $Script:VersionGroupMembersById[$groupId] = @($members)
        $Script:VersionGroupItemsById[$groupId] = $versionItem
        foreach ($itemId in $members) {
            $Script:VersionGroupByItemId[[string]$itemId] = $groupId
        }
    }
}

function Collapse-VersionGroups {
    param(
        [object[]]$Items
    )

    $result = New-Object 'System.Collections.Generic.List[object]'
    $emittedGroups = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in @($Items)) {
        $itemId = [string]$item.id
        if ($VersionGroupByItemId.ContainsKey($itemId)) {
            $groupId = [string]$VersionGroupByItemId[$itemId]
            if ($emittedGroups.Add($groupId) -and $VersionGroupItemsById.ContainsKey($groupId)) {
                $result.Add($VersionGroupItemsById[$groupId]) | Out-Null
            }
        }
        else {
            $result.Add($item) | Out-Null
        }
    }
    return $result.ToArray()
}

function Resolve-RealItemIds {
    param(
        [object[]]$Ids
    )

    $resolved = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($rawId in @($Ids)) {
        $itemId = ([string]$rawId).Trim()
        if ([string]::IsNullOrWhiteSpace($itemId)) {
            continue
        }

        if ($VersionGroupMembersById.ContainsKey($itemId)) {
            foreach ($memberId in @($VersionGroupMembersById[$itemId])) {
                $member = ([string]$memberId).Trim()
                if (-not [string]::IsNullOrWhiteSpace($member) -and $seen.Add($member)) {
                    $resolved.Add($member) | Out-Null
                }
            }
        }
        elseif ($seen.Add($itemId)) {
            $resolved.Add($itemId) | Out-Null
        }
    }
    return $resolved.ToArray()
}

function Get-VersionGroupMembers {
    param(
        [string]$GroupId
    )

    if (-not $VersionGroupMembersById.ContainsKey($GroupId)) {
        return @()
    }

    $items = @()
    foreach ($itemId in @($VersionGroupMembersById[$GroupId])) {
        $item = Get-AllLibraryItemById ([string]$itemId)
        if ($null -ne $item) {
            $items += $item
        }
    }
    return $items
}

function Get-ItemCategories($Item) {
    if ($null -eq $Item -or $null -eq $Item.categories) {
        return @()
    }
    return @($Item.categories | Where-Object {
        $category = [string]$_
        -not [string]::IsNullOrWhiteSpace($category) -and
            $category -ne $PendingCategory -and
            $category -ne $RecognizingCategory
    })
}

function Set-ItemPropertyValue($Item, [string]$Name, $Value) {
    if ($null -eq $Item -or [string]::IsNullOrWhiteSpace($Name)) {
        return
    }

    if ($null -eq $Item.PSObject.Properties[$Name]) {
        Add-Member -InputObject $Item -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    else {
        $Item.$Name = $Value
    }
}

function Apply-CategoryChangeToMemory {
    param(
        [string[]]$Ids,

        [string]$Category,

        [string]$Action
    )

    $idSet = New-SelectedIdSet -Ids @($Ids)
    if ($idSet.Count -eq 0 -or [string]::IsNullOrWhiteSpace($Category)) {
        return
    }

    foreach ($itemId in @($idSet)) {
        $item = Get-AllLibraryItemById ([string]$itemId)
        if ($null -eq $item) {
            continue
        }

        $nextCategories = New-Object 'System.Collections.Generic.List[string]'
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($rawCategory in @(Get-ItemCategories $item)) {
            $categoryName = ([string]$rawCategory).Trim()
            if ([string]::IsNullOrWhiteSpace($categoryName)) {
                continue
            }
            if ($Action -eq "remove" -and $categoryName -eq $Category) {
                continue
            }
            if ($seen.Add($categoryName)) {
                $nextCategories.Add($categoryName) | Out-Null
            }
        }

        if ($Action -eq "add" -and -not $seen.Contains($Category)) {
            $nextCategories.Add($Category) | Out-Null
        }

        Set-ItemPropertyValue $item "categories" $nextCategories.ToArray()
        if ($Action -eq "add" -and $Category -ne $FavoriteCategory) {
            Set-ItemPropertyValue $item "tagStatus" ""
        }
    }

    Mark-ShelfMetadataDirty
}

function Item-HasCategory($Item, [string]$Category) {
    if ($Category -eq $RecognizingCategory) {
        return ([string]$Item.titleStatus -eq $TitleStatusRecognizing)
    }
    if ($Category -eq $PendingCategory) {
        return ([string]$Item.titleStatus -eq $TitleStatusPending)
    }
    if ($Category -eq $NeedPasswordCategory) {
        return [bool]$Item.requiresPassword
    }
    if ($Category -eq $TagNotFoundCategory) {
        return ([string]$Item.tagStatus -eq $TagStatusNotFound)
    }

    foreach ($itemCategory in @(Get-ItemCategories $Item)) {
        if ([string]$itemCategory -eq $Category) {
            return $true
        }
    }
    return $false
}

function Item-MatchesCurrentCategory($Item) {
    if (Item-IsPendingRemoval $Item) {
        return $false
    }

    if ($CurrentCategory -eq "全部") {
        return $true
    }

    if ($CurrentCategory -eq $DuplicateCategory) {
        return Item-IsDuplicateResult $Item
    }

    $categories = @(Get-ItemCategories $Item)
    if ($CurrentCategory -eq "未分类") {
        return $categories.Count -eq 0 -and
            -not (Item-HasCategory $Item $RecognizingCategory) -and
            -not (Item-HasCategory $Item $PendingCategory) -and
            -not (Item-HasCategory $Item $NeedPasswordCategory) -and
            -not (Item-HasCategory $Item $TagNotFoundCategory)
    }

    return Item-HasCategory $Item $CurrentCategory
}

function Get-DisplayCategories($Item) {
    if ($null -eq $Item) {
        return @()
    }

    if ([bool]$Item.isVersionGroup) {
        $categories = @("多版本")
        if ($null -ne $Item.displayCategories) {
            $categories += @($Item.displayCategories)
        }

        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $displayCategories = @()
        foreach ($category in $categories) {
            $categoryName = ([string]$category).Trim()
            if (-not [string]::IsNullOrWhiteSpace($categoryName) -and $seen.Add($categoryName)) {
                $displayCategories += $categoryName
            }
        }
        return $displayCategories
    }

    $categories = @()
    if ([string]$Item.titleStatus -eq $TitleStatusRecognizing) {
        $categories += $RecognizingCategory
    }
    elseif ([string]$Item.titleStatus -eq $TitleStatusPending) {
        $categories += $PendingCategory
    }
    if ([bool]$Item.requiresPassword) {
        $categories += $NeedPasswordCategory
    }
    if ([string]$Item.tagStatus -eq $TagStatusNotFound) {
        $categories += $TagNotFoundCategory
    }

    $categories += @(Get-ItemCategories $Item)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $displayCategories = @()
    foreach ($category in $categories) {
        $categoryName = [string]$category
        if ([string]::IsNullOrWhiteSpace($categoryName)) {
            continue
        }
        if ($seen.Add($categoryName)) {
            $displayCategories += $categoryName
        }
    }

    if ($displayCategories.Count -eq 0) {
        return @("未分类")
    }
    return $displayCategories
}

function Get-SelectedLibraryItems {
    $items = @()
    $realIds = Resolve-RealItemIds -Ids @($SelectedIds)
    foreach ($itemId in $realIds) {
        $item = Get-AllLibraryItemById ([string]$itemId)
        if ($null -ne $item) {
            $items += $item
        }
    }
    return $items
}

function Selected-Items-AllHaveCategory([string]$Category) {
    $items = @(Get-SelectedLibraryItems)
    if ($items.Count -eq 0) {
        return $false
    }

    foreach ($item in $items) {
        if (-not (Item-HasCategory $item $Category)) {
            return $false
        }
    }
    return $true
}

function Get-SelectedCategoryCheckMap {
    param(
        [object[]]$Categories
    )

    $result = @{}
    $remaining = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($category in @($Categories)) {
        $categoryName = ([string]$category).Trim()
        if (-not [string]::IsNullOrWhiteSpace($categoryName)) {
            $result[$categoryName] = $false
            $remaining.Add($categoryName) | Out-Null
        }
    }

    if ($remaining.Count -eq 0) {
        return $result
    }

    $realIds = Resolve-RealItemIds -Ids @($SelectedIds)
    if ($realIds.Count -eq 0) {
        return $result
    }

    $itemCount = 0
    foreach ($itemId in $realIds) {
        if ($remaining.Count -eq 0) {
            break
        }

        $item = Get-AllLibraryItemById ([string]$itemId)
        if ($null -eq $item) {
            continue
        }

        $itemCount++
        $seenOnItem = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($category in @($item.categories)) {
            $categoryName = ([string]$category).Trim()
            if ([string]::IsNullOrWhiteSpace($categoryName) -or -not $remaining.Contains($categoryName)) {
                continue
            }
            $seenOnItem.Add($categoryName) | Out-Null
        }

        foreach ($categoryName in @($remaining)) {
            if (-not $seenOnItem.Contains($categoryName)) {
                $remaining.Remove($categoryName) | Out-Null
            }
        }
    }

    if ($itemCount -gt 0) {
        foreach ($categoryName in @($remaining)) {
            $result[$categoryName] = $true
        }
    }

    return $result
}

function Prompt-NewCategory {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("分类名称", "新建分类", "")
    $name = [string]$name
    $name = $name.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $null
    }
    if ($name -eq "收藏") {
        $name = $FavoriteCategory
    }
    if (Is-SystemCategoryName $name) {
        Show-AppMessage -Message "全部、未分类、喜爱、识别中、待确认、需要密码、tag未找到和重复项是系统分类，不能作为自定义分类。" -Caption "新建分类" -Image ([System.Windows.MessageBoxImage]::Warning)
        return $null
    }

    $result = Invoke-ScannerJson -Arguments @($ScannerPath, "add-category", "--data-dir", $DataDir, "--name", $name, "--summary-only") -ErrorCaption "新建分类失败"
    if ($null -eq $result) {
        return $null
    }
    $category = [string]$result.category
    if (-not [string]::IsNullOrWhiteSpace($category) -and -not (@($LibraryCategories) -contains $category)) {
        $Script:LibraryCategories = @($LibraryCategories) + $category
        Mark-ShelfMetadataDirty
    }
    return $category
}

function Add-NewCategory {
    $category = Prompt-NewCategory
    if ([string]::IsNullOrWhiteSpace($category)) {
        return
    }

    $Script:CurrentCategory = $category
    Clear-Selection
    Render-Library -Reload:$false
}

function Rename-Category {
    param(
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($Category)) {
        return
    }
    if (Is-SystemCategoryName $Category) {
        return
    }

    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("新的分类名称", "重命名分类", $Category)
    $newName = ([string]$newName).Trim()
    if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $Category) {
        return
    }

    $result = Invoke-ScannerJson -Arguments @($ScannerPath, "rename-category", "--data-dir", $DataDir, "--name", $Category, "--new-name", $newName) -ErrorCaption "重命名分类失败"
    if ($null -eq $result) {
        return
    }

    if ($CurrentCategory -eq $Category) {
        $Script:CurrentCategory = [string]$result.category
    }
    Render-Library
}

function Delete-Category {
    param(
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($Category)) {
        Show-AppMessage -Message "分类名称为空，无法删除。" -Caption "删除分类" -Image ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    if (Is-SystemCategoryName $Category) {
        return
    }

    $message = "要删除分类「$Category」吗？`r`n漫画不会被删除，只会移除这个分类。"
    if (-not (Confirm-AppMessage -Message $message -Caption "删除分类")) {
        return
    }

    $result = Invoke-ScannerJson -Arguments @($ScannerPath, "delete-category", "--data-dir", $DataDir, "--name", $Category) -ErrorCaption "删除分类失败"
    if ($null -eq $result) {
        return
    }

    if ($CurrentCategory -eq $Category) {
        $Script:CurrentCategory = "全部"
    }
    Clear-Selection
    Render-Library
}

function Blacklist-Category {
    param(
        [string]$Category
    )

    $targetCategory = [string]$Category
    if ([string]::IsNullOrWhiteSpace($targetCategory)) {
        Show-AppMessage -Message "分类名称为空，无法加入黑名单。" -Caption "加入黑名单" -Image ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    if (Is-SystemCategoryName $targetCategory) {
        return
    }

    $message = "要把分类「$targetCategory」加入 Tag 黑名单吗？`r`n该分类会从书架中移除，之后自动识别到同一个 EH Tag 时也不会再创建。"
    if (-not (Confirm-AppMessage -Message $message -Caption "加入黑名单")) {
        return
    }

    $result = Invoke-ScannerJson -Arguments @($ScannerPath, "blacklist-category", "--data-dir", $DataDir, "--name", $targetCategory) -ErrorCaption "加入黑名单失败"
    if ($null -eq $result) {
        return
    }

    if ($CurrentCategory -eq $targetCategory) {
        $Script:CurrentCategory = "全部"
    }
    Clear-Selection
    Render-Library
}

function Merge-Category {
    param(
        [string]$SourceCategory,
        [string]$TargetCategory
    )

    $source = ([string]$SourceCategory).Trim()
    $target = ([string]$TargetCategory).Trim()
    if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($target) -or $source -eq $target) {
        return
    }
    if (Is-SystemCategoryName $source) {
        return
    }
    if (Is-SystemCategoryName $target) {
        return
    }

    $message = "要把分类「$source」合并到「$target」吗？`r`n「$source」会消失，已有漫画会转入「$target」。之后自动识别到「$source」对应的 Tag 时，也会自动归入「$target」。"
    if (-not (Confirm-AppMessage -Message $message -Caption "合并分类")) {
        return
    }

    $result = Invoke-ScannerJson -Arguments @($ScannerPath, "merge-category", "--data-dir", $DataDir, "--source", $source, "--target", $target) -ErrorCaption "合并分类失败"
    if ($null -eq $result) {
        return
    }

    if ($CurrentCategory -eq $source) {
        $Script:CurrentCategory = $target
    }
    Clear-Selection
    Render-Library
}

function Show-CategoryManagerWindow {
    if ($ShelfMetadataDirty -or $CategoryItemsByName.Count -eq 0) {
        Refresh-DuplicateItemCache
        Refresh-VersionGroupCache
        Rebuild-CategoryCountCache
    }

    $library = Get-LibraryData
    if ($null -eq $library) {
        return
    }

    $recordsByCategory = @{}
    foreach ($record in @($library.categoryRecords)) {
        $recordName = ([string]$record.name).Trim()
        if (-not [string]::IsNullOrWhiteSpace($recordName) -and -not $recordsByCategory.ContainsKey($recordName)) {
            $recordsByCategory[$recordName] = $record
        }
    }

    $aliasesByCategory = @{}
    foreach ($alias in @($library.categoryAliases)) {
        $targetName = ([string]$alias.targetName).Trim()
        if ([string]::IsNullOrWhiteSpace($targetName)) {
            continue
        }
        if (-not $aliasesByCategory.ContainsKey($targetName)) {
            $aliasesByCategory[$targetName] = New-Object 'System.Collections.Generic.List[object]'
        }
        $aliasesByCategory[$targetName].Add($alias) | Out-Null
    }

    $managerItems = New-Object 'System.Collections.Generic.List[object]'
    $categoryOrderIndex = 0
    foreach ($category in @($LibraryCategories)) {
        $categoryName = ([string]$category).Trim()
        if ([string]::IsNullOrWhiteSpace($categoryName) -or (Is-SystemCategoryName $categoryName)) {
            continue
        }

        $record = $null
        if ($recordsByCategory.ContainsKey($categoryName)) {
            $record = $recordsByCategory[$categoryName]
        }
        $aliases = @()
        if ($aliasesByCategory.ContainsKey($categoryName)) {
            $aliases = @($aliasesByCategory[$categoryName].ToArray())
        }

        $sourceLabel = "手动"
        $originalTag = ""
        if ($null -ne $record -and [string]$record.kind -eq "tag") {
            $source = ([string]$record.source).Trim()
            if ([string]::IsNullOrWhiteSpace($source)) {
                $source = "tag"
            }
            $sourceLabel = $source
            $namespace = ([string]$record.sourceNamespace).Trim()
            $sourceTag = ([string]$record.sourceTag).Trim()
            if (-not [string]::IsNullOrWhiteSpace($namespace) -or -not [string]::IsNullOrWhiteSpace($sourceTag)) {
                $originalTag = "$namespace`:$sourceTag"
            }
        }

        $managerItems.Add([pscustomobject]@{
            OriginalName = $categoryName
            Name = $categoryName
            OrderIndex = $categoryOrderIndex
            Count = (Get-CategoryCount $categoryName)
            SourceLabel = $sourceLabel
            OriginalTag = $originalTag
            Aliases = @($aliases)
            IsDeleted = $false
            IsBlacklisted = $false
            MergeTargetOriginal = ""
        }) | Out-Null
        $categoryOrderIndex++
    }

    $managerWindow = New-Object System.Windows.Window
    $managerWindow.Title = "分类管理"
    $managerWindow.Width = 900
    $managerWindow.Height = 620
    $managerWindow.MinWidth = 720
    $managerWindow.MinHeight = 480
    $managerWindow.Owner = $Window
    $managerWindow.WindowStartupLocation = "CenterOwner"
    $managerWindow.Background = $BrushBackground

    $root = New-Object System.Windows.Controls.DockPanel
    $root.LastChildFill = $true
    $managerWindow.Content = $root

    $header = New-Object System.Windows.Controls.TextBlock
    $header.Text = "分类管理"
    $header.Foreground = $BrushText
    $header.FontSize = 18
    $header.FontWeight = "SemiBold"
    $header.Margin = New-Object System.Windows.Thickness -ArgumentList 18, 16, 18, 8
    [System.Windows.Controls.DockPanel]::SetDock($header, "Top")
    $root.Children.Add($header) | Out-Null

    $managerToolbar = New-Object System.Windows.Controls.DockPanel
    $managerToolbar.Height = 38
    $managerToolbar.Margin = New-Object System.Windows.Thickness -ArgumentList 18, 0, 18, 4
    $managerToolbar.LastChildFill = $false
    [System.Windows.Controls.DockPanel]::SetDock($managerToolbar, "Top")
    $root.Children.Add($managerToolbar) | Out-Null

    $managerSortPanel = New-Object System.Windows.Controls.StackPanel
    $managerSortPanel.Orientation = "Horizontal"
    $managerSortPanel.HorizontalAlignment = "Right"
    $managerSortPanel.VerticalAlignment = "Center"
    [System.Windows.Controls.DockPanel]::SetDock($managerSortPanel, "Right")

    $managerSortLabel = New-Object System.Windows.Controls.TextBlock
    $managerSortLabel.Text = "排序"
    $managerSortLabel.Foreground = $BrushMuted
    $managerSortLabel.FontSize = 13
    $managerSortLabel.VerticalAlignment = "Center"
    $managerSortLabel.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0

    $managerSortComboBox = New-Object System.Windows.Controls.ComboBox
    $managerSortComboBox.Width = 118
    $managerSortComboBox.Height = 30
    $managerSortComboBox.Background = $BrushCard
    $managerSortComboBox.Foreground = $BrushText
    $managerSortComboBox.BorderBrush = $BrushMuted
    $managerSortComboBox.Cursor = [System.Windows.Input.Cursors]::Hand
    $managerSortComboBox.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $BrushCard
    $managerSortComboBox.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $BrushCard
    $managerSortComboBox.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $BrushText
    $managerSortComboBox.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $BrushSidebarItemSelected
    $managerSortComboBox.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $BrushText

    function Add-ManagerSortOptionItem {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Key,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $Label
        $item.Tag = $Key
        $item.Background = $BrushCard
        $item.Foreground = $BrushText
        $item.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 5, 10, 5
        $item.MinHeight = 28
        $item.Add_MouseEnter({
            param($sender, $eventArgs)
            $sender.Background = $BrushCardHover
            $sender.Foreground = $BrushText
        })
        $item.Add_MouseLeave({
            param($sender, $eventArgs)
            $sender.Background = $BrushCard
            $sender.Foreground = $BrushText
        })
        $managerSortComboBox.Items.Add($item) | Out-Null
    }

    Add-ManagerSortOptionItem -Key "created" -Label "创建顺序"
    Add-ManagerSortOptionItem -Key "name" -Label "分类名字"
    $managerSortComboBox.SelectedIndex = 1
    $managerSortPanel.Children.Add($managerSortLabel) | Out-Null
    $managerSortPanel.Children.Add($managerSortComboBox) | Out-Null
    $managerToolbar.Children.Add($managerSortPanel) | Out-Null

    $footer = New-Object System.Windows.Controls.DockPanel
    $footer.LastChildFill = $true
    $footer.Margin = New-Object System.Windows.Thickness -ArgumentList 18, 8, 18, 14
    [System.Windows.Controls.DockPanel]::SetDock($footer, "Bottom")
    $root.Children.Add($footer) | Out-Null

    $closeButton = New-Object System.Windows.Controls.Button
    $closeButton.Content = "关闭"
    $closeButton.Width = 92
    $closeButton.Height = 32
    $closeButton.Margin = New-Object System.Windows.Thickness -ArgumentList 12, 0, 0, 0
    [System.Windows.Controls.DockPanel]::SetDock($closeButton, "Right")
    $footer.Children.Add($closeButton) | Out-Null

    $summaryText = New-Object System.Windows.Controls.TextBlock
    $summaryText.Foreground = $BrushMuted
    $summaryText.FontSize = 13
    $summaryText.VerticalAlignment = "Center"
    $footer.Children.Add($summaryText) | Out-Null

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.Margin = New-Object System.Windows.Thickness -ArgumentList 14, 4, 14, 4
    $scroll.VerticalScrollBarVisibility = "Auto"
    $scroll.HorizontalScrollBarVisibility = "Disabled"
    $scroll.Background = $BrushBackground
    $root.Children.Add($scroll) | Out-Null

    $panel = New-Object System.Windows.Controls.WrapPanel
    $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 4
    $panel.Background = $BrushBackground
    $scroll.Content = $panel

    $dragFormat = "mangagaCategoryManager"
    $managerState = @{
        SelectedOriginals = New-Object 'System.Collections.Generic.HashSet[string]'
        LastSelectedOriginal = ""
        DragStartPoint = $null
        ApplyingChanges = $false
        TileByOriginal = @{}
        SortMode = "name"
    }
    $updateManagerTileSelectionVisuals = {
        param($State)

        if ($null -eq $State -or $null -eq $State["TileByOriginal"] -or $null -eq $State["SelectedOriginals"]) {
            return
        }

        foreach ($entry in @($State["TileByOriginal"].GetEnumerator())) {
            $tile = $entry.Value
            if ($null -eq $tile) {
                continue
            }

            if ($State["SelectedOriginals"].Contains([string]$entry.Key)) {
                $tile.Background = $BrushSelectedBack
                $tile.BorderBrush = $BrushAccent
            }
            else {
                $tile.Background = $BrushTransparent
                $tile.BorderBrush = $BrushTransparent
            }
        }
    }.GetNewClosure()

    function Find-ManagerItem([string]$OriginalName) {
        $key = ([string]$OriginalName).Trim()
        foreach ($item in @($managerItems.ToArray())) {
            if ([string]$item.OriginalName -eq $key) {
                return $item
            }
        }
        return $null
    }

    function Test-ManagerItemActive($Item) {
        return ($null -ne $Item -and
            -not [bool]$Item.IsDeleted -and
            -not [bool]$Item.IsBlacklisted -and
            [string]::IsNullOrWhiteSpace([string]$Item.MergeTargetOriginal))
    }

    function Test-ManagerHasOwnBlacklistSource($Item) {
        if ($null -eq $Item) {
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Item.OriginalTag)) {
            return $true
        }
        foreach ($alias in @($Item.Aliases)) {
            if ([string]$alias.sourceKind -eq "tag" -and -not [string]::IsNullOrWhiteSpace([string]$alias.sourceTag)) {
                return $true
            }
        }
        return $false
    }

    function Get-ManagerUltimateTarget($Item) {
        $current = $Item
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        while ($null -ne $current -and -not [string]::IsNullOrWhiteSpace([string]$current.MergeTargetOriginal)) {
            if (-not $seen.Add([string]$current.OriginalName)) {
                return $null
            }
            $current = Find-ManagerItem ([string]$current.MergeTargetOriginal)
        }
        return $current
    }

    function Test-ManagerCanBlacklistItem($Item) {
        if (-not (Test-ManagerItemActive $Item)) {
            return $false
        }
        if (Test-ManagerHasOwnBlacklistSource $Item) {
            return $true
        }
        foreach ($source in @($managerItems.ToArray())) {
            if ($null -eq $source -or [string]$source.OriginalName -eq [string]$Item.OriginalName) {
                continue
            }
            if (-not (Test-ManagerHasOwnBlacklistSource $source)) {
                continue
            }
            $target = Get-ManagerUltimateTarget $source
            if ($null -ne $target -and [string]$target.OriginalName -eq [string]$Item.OriginalName) {
                return $true
            }
        }
        return $false
    }

    function Get-ActiveManagerItems {
        $active = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in @($managerItems.ToArray())) {
            if (Test-ManagerItemActive $item) {
                $active.Add($item) | Out-Null
            }
        }
        if ([string]$managerState["SortMode"] -eq "created") {
            return @($active.ToArray() | Sort-Object @{ Expression = { [int]$_.OrderIndex }; Ascending = $true }, @{ Expression = { [string]$_.Name }; Ascending = $true })
        }
        return @($active.ToArray() | Sort-Object @{ Expression = { [string]$_.Name }; Ascending = $true }, @{ Expression = { [int]$_.OrderIndex }; Ascending = $true })
    }

    function Get-ManagerItemIndexInView([string]$OriginalName) {
        $key = ([string]$OriginalName).Trim()
        $items = @(Get-ActiveManagerItems)
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ([string]$items[$i].OriginalName -eq $key) {
                return $i
            }
        }
        return -1
    }

    function Clear-ManagerSelection {
        $managerState["SelectedOriginals"].Clear()
        $managerState["LastSelectedOriginal"] = ""
        Update-ManagerTileSelectionVisuals
    }

    function Select-AllManagerItems {
        $managerState["SelectedOriginals"].Clear()
        $items = @(Get-ActiveManagerItems)
        foreach ($item in $items) {
            $managerState["SelectedOriginals"].Add([string]$item.OriginalName) | Out-Null
        }
        if ($items.Count -gt 0) {
            $managerState["LastSelectedOriginal"] = [string]$items[$items.Count - 1].OriginalName
        }
        Update-ManagerTileSelectionVisuals
        Update-ManagerSummary
    }

    function Select-ManagerItem {
        param(
            $Item,

            [bool]$Ctrl = $false,

            [bool]$Shift = $false
        )

        if ($null -eq $Item) {
            return
        }

        $name = [string]$Item.OriginalName
        $index = Get-ManagerItemIndexInView $name
        if ($index -lt 0) {
            return
        }

        if ($Shift -and -not [string]::IsNullOrWhiteSpace([string]$managerState["LastSelectedOriginal"])) {
            $anchorIndex = Get-ManagerItemIndexInView ([string]$managerState["LastSelectedOriginal"])
            if ($anchorIndex -lt 0) {
                $anchorIndex = $index
            }
            if (-not $Ctrl) {
                $managerState["SelectedOriginals"].Clear()
            }

            $items = @(Get-ActiveManagerItems)
            $start = [Math]::Min($anchorIndex, $index)
            $end = [Math]::Max($anchorIndex, $index)
            for ($i = $start; $i -le $end; $i++) {
                $managerState["SelectedOriginals"].Add([string]$items[$i].OriginalName) | Out-Null
            }
        }
        elseif ($Ctrl) {
            if ($managerState["SelectedOriginals"].Contains($name)) {
                $managerState["SelectedOriginals"].Remove($name) | Out-Null
            }
            else {
                $managerState["SelectedOriginals"].Add($name) | Out-Null
            }
            $managerState["LastSelectedOriginal"] = $name
        }
        else {
            $managerState["SelectedOriginals"].Clear()
            $managerState["SelectedOriginals"].Add($name) | Out-Null
            $managerState["LastSelectedOriginal"] = $name
        }

        Update-ManagerTileSelectionVisuals
        Update-ManagerSummary
    }

    function Ensure-ManagerItemSelectedForContext($Item) {
        if ($null -eq $Item) {
            return
        }
        $name = [string]$Item.OriginalName
        if (-not $managerState["SelectedOriginals"].Contains($name)) {
            $managerState["SelectedOriginals"].Clear()
            $managerState["SelectedOriginals"].Add($name) | Out-Null
            $managerState["LastSelectedOriginal"] = $name
        }
        Update-ManagerTileSelectionVisuals
        Update-ManagerSummary
    }

    function Get-SelectedManagerItems {
        $items = New-Object 'System.Collections.Generic.List[object]'
        foreach ($item in @(Get-ActiveManagerItems)) {
            if ($managerState["SelectedOriginals"].Contains([string]$item.OriginalName)) {
                $items.Add($item) | Out-Null
            }
        }
        return @($items.ToArray())
    }

    function Get-ManagerDragNames([string]$SourceName) {
        $source = ([string]$SourceName).Trim()
        $names = New-Object 'System.Collections.Generic.List[string]'
        if (-not [string]::IsNullOrWhiteSpace($source) -and $managerState["SelectedOriginals"].Contains($source)) {
            foreach ($item in @(Get-SelectedManagerItems)) {
                $names.Add([string]$item.OriginalName) | Out-Null
            }
        }
        if ($names.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($source)) {
            $names.Add($source) | Out-Null
        }
        return @($names.ToArray())
    }

    function Get-ManagerDragNamesFromData([string]$DataText) {
        return @(([string]$DataText -split "`n") | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }

    function Test-ManagerEventSourceIsTile($Source) {
        $current = $Source
        while ($null -ne $current) {
            if ($current -is [System.Windows.Controls.Primitives.ScrollBar] -or
                $current -is [System.Windows.Controls.Primitives.Thumb] -or
                $current -is [System.Windows.Controls.Primitives.RepeatButton]) {
                return $true
            }
            if ($current -is [System.Windows.Controls.Border] -and $null -ne $current.Tag) {
                $originalName = ([string]$current.Tag.OriginalName).Trim()
                if (-not [string]::IsNullOrWhiteSpace($originalName) -and $managerState["TileByOriginal"].ContainsKey($originalName)) {
                    return $true
                }
            }
            if ($current -eq $panel) {
                return $false
            }
            try {
                $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
            }
            catch {
                return $false
            }
        }
        return $false
    }

    function Test-ManagerCategoryNameAvailable([string]$Name, $ExceptItem) {
        $candidate = ([string]$Name).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate) -or (Is-SystemCategoryName $candidate)) {
            return $false
        }
        foreach ($item in @(Get-ActiveManagerItems)) {
            if ($null -ne $ExceptItem -and [string]$item.OriginalName -eq [string]$ExceptItem.OriginalName) {
                continue
            }
            if ([string]$item.Name -eq $candidate) {
                return $false
            }
        }
        return $true
    }

    function Get-MergeDepth($Item) {
        $depth = 0
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $current = $Item
        while ($null -ne $current -and -not [string]::IsNullOrWhiteSpace([string]$current.MergeTargetOriginal)) {
            if (-not $seen.Add([string]$current.OriginalName)) {
                break
            }
            $depth++
            $current = Find-ManagerItem ([string]$current.MergeTargetOriginal)
        }
        return $depth
    }

    function Get-FinalBlacklistNames {
        $blacklisted = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($item in @($managerItems.ToArray())) {
            if ([bool]$item.IsBlacklisted) {
                $blacklisted.Add([string]$item.OriginalName) | Out-Null
            }
        }

        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($item in @($managerItems.ToArray())) {
                $target = ([string]$item.MergeTargetOriginal).Trim()
                if ([string]::IsNullOrWhiteSpace($target)) {
                    continue
                }
                if ($blacklisted.Contains($target) -and -not $blacklisted.Contains([string]$item.OriginalName)) {
                    $blacklisted.Add([string]$item.OriginalName) | Out-Null
                    $changed = $true
                }
            }
        }

        $names = New-Object 'System.Collections.Generic.List[string]'
        foreach ($name in $blacklisted) {
            $names.Add([string]$name) | Out-Null
        }
        return @($names.ToArray() | Sort-Object)
    }

    function Test-ManagerHasPendingChanges {
        foreach ($item in @($managerItems.ToArray())) {
            if ([bool]$item.IsDeleted -or [bool]$item.IsBlacklisted -or
                -not [string]::IsNullOrWhiteSpace([string]$item.MergeTargetOriginal) -or
                [string]$item.Name -ne [string]$item.OriginalName) {
                return $true
            }
        }
        return $false
    }

    function Get-PendingSummary {
        $renameCount = 0
        $mergeCount = 0
        $deleteCount = 0
        foreach ($item in @($managerItems.ToArray())) {
            if ([bool]$item.IsDeleted) {
                $deleteCount++
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$item.MergeTargetOriginal)) {
                $mergeCount++
            }
            if ((Test-ManagerItemActive $item) -and [string]$item.Name -ne [string]$item.OriginalName) {
                $renameCount++
            }
        }
        $blacklistCount = @(Get-FinalBlacklistNames).Count
        $selectedCount = 0
        if ($null -ne $managerState["SelectedOriginals"]) {
            $selectedCount = [int]$managerState["SelectedOriginals"].Count
        }
        return "已选中 $selectedCount；待执行：重命名 $renameCount，合并 $mergeCount，删除 $deleteCount，黑名单 $blacklistCount"
    }

    function Update-ManagerSummary {
        if (Test-ManagerHasPendingChanges) {
            $summaryText.Text = Get-PendingSummary
        }
        elseif ($null -ne $managerState["SelectedOriginals"] -and [int]$managerState["SelectedOriginals"].Count -gt 0) {
            $summaryText.Text = "已选中 $([int]$managerState["SelectedOriginals"].Count)"
        }
        else {
            $summaryText.Text = "没有待执行操作"
        }
    }

    function Show-CategoryProperties($Item) {
        if ($null -eq $Item) {
            return
        }
        $aliasLines = @()
        foreach ($alias in @($Item.Aliases)) {
            $sourceName = ([string]$alias.sourceName).Trim()
            $sourceTag = ([string]$alias.sourceTag).Trim()
            if (-not [string]::IsNullOrWhiteSpace($sourceTag)) {
                $aliasLines += "$sourceName ($sourceTag)"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($sourceName)) {
                $aliasLines += $sourceName
            }
        }
        if ($aliasLines.Count -gt 0) {
            $aliasText = $aliasLines -join "、"
        }
        else {
            $aliasText = "无"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Item.OriginalTag)) {
            $tagText = [string]$Item.OriginalTag
        }
        else {
            $tagText = "无"
        }
        $message = @(
            "名称：$($Item.Name)",
            "作品数量：$($Item.Count)",
            "来源：$($Item.SourceLabel)",
            "原始 Tag：$tagText",
            "合并别名：$aliasText"
        ) -join [Environment]::NewLine
        Show-AppMessage -Message $message -Caption "分类属性"
    }

    function Prompt-MergeTarget {
        param(
            $SourceItems
        )

        $sourceKeys = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($sourceItem in @($SourceItems)) {
            if ($null -ne $sourceItem) {
                $sourceKeys.Add([string]$sourceItem.OriginalName) | Out-Null
            }
        }
        $targets = @(Get-ActiveManagerItems | Where-Object { -not $sourceKeys.Contains([string]$_.OriginalName) })
        if ($targets.Count -eq 0) {
            Show-AppMessage -Message "没有可合并到的目标分类。" -Caption "合并分类" -Image ([System.Windows.MessageBoxImage]::Warning)
            return $null
        }

        $dialog = New-Object System.Windows.Window
        $dialog.Title = "合并到"
        $dialog.Width = 360
        $dialog.Height = 150
        $dialog.ResizeMode = "NoResize"
        $dialog.Owner = $managerWindow
        $dialog.WindowStartupLocation = "CenterOwner"
        $dialog.Background = $BrushBackground

        $dock = New-Object System.Windows.Controls.DockPanel
        $dock.Margin = New-Object System.Windows.Thickness -ArgumentList 14
        $dialog.Content = $dock

        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = "选择目标分类"
        $label.Foreground = $BrushText
        $label.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 8
        [System.Windows.Controls.DockPanel]::SetDock($label, "Top")
        $dock.Children.Add($label) | Out-Null

        $buttons = New-Object System.Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"
        $buttons.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 12, 0, 0
        [System.Windows.Controls.DockPanel]::SetDock($buttons, "Bottom")
        $dock.Children.Add($buttons) | Out-Null

        $ok = New-Object System.Windows.Controls.Button
        $ok.Content = "确定"
        $ok.Width = 76
        $ok.Height = 28
        $ok.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
        $cancel = New-Object System.Windows.Controls.Button
        $cancel.Content = "取消"
        $cancel.Width = 76
        $cancel.Height = 28
        $buttons.Children.Add($ok) | Out-Null
        $buttons.Children.Add($cancel) | Out-Null

        $combo = New-Object System.Windows.Controls.ComboBox
        $combo.IsEditable = $true
        foreach ($target in $targets) {
            $combo.Items.Add([string]$target.Name) | Out-Null
        }
        if ($combo.Items.Count -gt 0) {
            $combo.SelectedIndex = 0
        }
        $dock.Children.Add($combo) | Out-Null

        $selected = $null
        $ok.Add_Click({
            param($sender, $eventArgs)
            $name = ([string]$combo.Text).Trim()
            foreach ($target in $targets) {
                if ([string]$target.Name -eq $name) {
                    $selected = $target
                    $dialog.DialogResult = $true
                    return
                }
            }
            Show-AppMessage -Message "目标分类不存在。" -Caption "合并分类" -Image ([System.Windows.MessageBoxImage]::Warning)
        }.GetNewClosure())
        $cancel.Add_Click({
            param($sender, $eventArgs)
            $dialog.DialogResult = $false
        })

        if ($dialog.ShowDialog() -eq $true) {
            return $selected
        }
        return $null
    }

    function Merge-ManagerItems($SourceItem, $TargetItem) {
        if (-not (Test-ManagerItemActive $SourceItem) -or -not (Test-ManagerItemActive $TargetItem)) {
            return
        }
        if ([string]$SourceItem.OriginalName -eq [string]$TargetItem.OriginalName) {
            return
        }
        $SourceItem.MergeTargetOriginal = [string]$TargetItem.OriginalName
        $TargetItem.Count = [int]$TargetItem.Count + [int]$SourceItem.Count
        if ($managerState["SelectedOriginals"].Contains([string]$SourceItem.OriginalName)) {
            $managerState["SelectedOriginals"].Clear()
            $managerState["SelectedOriginals"].Add([string]$TargetItem.OriginalName) | Out-Null
            $managerState["LastSelectedOriginal"] = [string]$TargetItem.OriginalName
        }
        Refresh-ManagerView
    }

    function Merge-ManagerItemsBatch {
        param(
            $SourceItems,

            $TargetItem
        )

        if (-not (Test-ManagerItemActive $TargetItem)) {
            return
        }

        $changed = $false
        foreach ($sourceItem in @($SourceItems)) {
            if (-not (Test-ManagerItemActive $sourceItem)) {
                continue
            }
            if ([string]$sourceItem.OriginalName -eq [string]$TargetItem.OriginalName) {
                continue
            }
            $sourceItem.MergeTargetOriginal = [string]$TargetItem.OriginalName
            $TargetItem.Count = [int]$TargetItem.Count + [int]$sourceItem.Count
            $changed = $true
        }

        if ($changed) {
            $managerState["SelectedOriginals"].Clear()
            $managerState["SelectedOriginals"].Add([string]$TargetItem.OriginalName) | Out-Null
            $managerState["LastSelectedOriginal"] = [string]$TargetItem.OriginalName
            Refresh-ManagerView
        }
    }

    function Delete-ManagerItemsBatch {
        param(
            $Items
        )

        $changed = $false
        foreach ($item in @($Items)) {
            if (Test-ManagerItemActive $item) {
                $item.IsDeleted = $true
                $changed = $true
            }
        }
        if ($changed) {
            $managerState["SelectedOriginals"].Clear()
            $managerState["LastSelectedOriginal"] = ""
            Refresh-ManagerView
        }
    }

    function Blacklist-ManagerItemsBatch {
        param(
            $Items
        )

        $changed = $false
        foreach ($item in @($Items)) {
            if (Test-ManagerItemActive $item) {
                $item.IsBlacklisted = $true
                $changed = $true
            }
        }
        if ($changed) {
            $managerState["SelectedOriginals"].Clear()
            $managerState["LastSelectedOriginal"] = ""
            Refresh-ManagerView
        }
    }

    function Rename-ManagerItem($Item) {
        $oldName = [string]$Item.Name
        $newName = [Microsoft.VisualBasic.Interaction]::InputBox("新的分类名称", "重命名分类", $oldName)
        $newName = ([string]$newName).Trim()
        if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $oldName) {
            return
        }
        if (-not (Test-ManagerCategoryNameAvailable -Name $newName -ExceptItem $Item)) {
            Show-AppMessage -Message "分类名称为空、属于系统分类，或已经被其他分类使用。" -Caption "重命名分类" -Image ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        $Item.Name = $newName
        Refresh-ManagerView
    }

    function Build-CategoryManagerContextMenu($Item) {
        $selectedItems = @(Get-SelectedManagerItems)
        if ($selectedItems.Count -eq 0 -and $null -ne $Item) {
            $selectedItems = @($Item)
        }
        $selectedCount = $selectedItems.Count
        $canBlacklistSelected = ($selectedCount -gt 0)

        $menu = New-Object System.Windows.Controls.ContextMenu
        $rename = New-Object System.Windows.Controls.MenuItem
        $rename.Header = "重命名"
        $rename.IsEnabled = ($selectedCount -eq 1)
        $rename.Add_Click({ Rename-ManagerItem $Item }.GetNewClosure())
        $merge = New-Object System.Windows.Controls.MenuItem
        $merge.Header = if ($selectedCount -gt 1) { "合并选中到..." } else { "合并到..." }
        $merge.IsEnabled = ($selectedCount -gt 0)
        $merge.Add_Click({
            $targets = @(Get-SelectedManagerItems)
            if ($targets.Count -eq 0 -and $null -ne $Item) {
                $targets = @($Item)
            }
            $target = Prompt-MergeTarget -SourceItems $targets
            if ($null -ne $target) {
                Merge-ManagerItemsBatch -SourceItems $targets -TargetItem $target
            }
        }.GetNewClosure())
        $blacklist = New-Object System.Windows.Controls.MenuItem
        $blacklist.Header = if ($selectedCount -gt 1) { "选中项加入黑名单" } else { "加入黑名单" }
        $blacklist.IsEnabled = $canBlacklistSelected
        $blacklist.Add_Click({
            $targets = @(Get-SelectedManagerItems)
            if ($targets.Count -eq 0 -and $null -ne $Item) {
                $targets = @($Item)
            }
            Blacklist-ManagerItemsBatch -Items $targets
        }.GetNewClosure())
        $delete = New-Object System.Windows.Controls.MenuItem
        $delete.Header = if ($selectedCount -gt 1) { "删除选中项" } else { "删除" }
        $delete.IsEnabled = ($selectedCount -gt 0)
        $delete.Add_Click({
            $targets = @(Get-SelectedManagerItems)
            if ($targets.Count -eq 0 -and $null -ne $Item) {
                $targets = @($Item)
            }
            Delete-ManagerItemsBatch -Items $targets
        }.GetNewClosure())
        $properties = New-Object System.Windows.Controls.MenuItem
        $properties.Header = "属性"
        $properties.IsEnabled = ($selectedCount -eq 1)
        $properties.Add_Click({ Show-CategoryProperties $Item }.GetNewClosure())
        $menu.Items.Add($rename) | Out-Null
        $menu.Items.Add($merge) | Out-Null
        $menu.Items.Add($blacklist) | Out-Null
        $menu.Items.Add($delete) | Out-Null
        $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
        $menu.Items.Add($properties) | Out-Null
        return $menu
    }

    function Update-ManagerTileSelectionVisuals {
        & $updateManagerTileSelectionVisuals $managerState
    }

    function New-CategoryManagerTile($Item) {
        $tile = New-Object System.Windows.Controls.Border
        $tile.Width = 130
        $tile.Height = 132
        $tile.Margin = New-Object System.Windows.Thickness -ArgumentList 8
        $tile.Padding = New-Object System.Windows.Thickness -ArgumentList 8
        $tile.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 6
        if ($managerState["SelectedOriginals"].Contains([string]$Item.OriginalName)) {
            $tile.Background = $BrushSelectedBack
            $tile.BorderBrush = $BrushAccent
        }
        else {
            $tile.Background = $BrushTransparent
            $tile.BorderBrush = $BrushTransparent
        }
        $tile.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 1
        $tile.Cursor = [System.Windows.Input.Cursors]::Hand
        $tile.Tag = $Item
        $tile.AllowDrop = $true
        $managerState["TileByOriginal"][[string]$Item.OriginalName] = $tile
        $tileState = $managerState
        $tileManagerWindow = $managerWindow
        $tileDragFormat = $dragFormat
        $tileUpdateSelectionVisuals = $updateManagerTileSelectionVisuals

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.HorizontalAlignment = "Center"
        $stack.VerticalAlignment = "Center"
        $tile.Child = $stack

        $canvas = New-Object System.Windows.Controls.Canvas
        $canvas.Width = 58
        $canvas.Height = 46
        $canvas.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 8
        $tab = New-Object System.Windows.Controls.Border
        $tab.Width = 24
        $tab.Height = 12
        $tab.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 3, 3, 0, 0
        $tab.Background = New-SolidBrush "#C99835"
        [System.Windows.Controls.Canvas]::SetLeft($tab, 4)
        [System.Windows.Controls.Canvas]::SetTop($tab, 5)
        $body = New-Object System.Windows.Controls.Border
        $body.Width = 56
        $body.Height = 34
        $body.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 4
        $body.Background = New-SolidBrush "#E2B84C"
        [System.Windows.Controls.Canvas]::SetLeft($body, 1)
        [System.Windows.Controls.Canvas]::SetTop($body, 12)
        $canvas.Children.Add($tab) | Out-Null
        $canvas.Children.Add($body) | Out-Null
        $stack.Children.Add($canvas) | Out-Null

        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = [string]$Item.Name
        $name.Foreground = $BrushText
        $name.FontSize = 13
        $name.TextAlignment = "Center"
        $name.TextWrapping = "Wrap"
        $name.TextTrimming = "CharacterEllipsis"
        $name.MaxHeight = 38
        $stack.Children.Add($name) | Out-Null

        $count = New-Object System.Windows.Controls.TextBlock
        $count.Text = "$($Item.Count) 本"
        $count.Foreground = $BrushMuted
        $count.FontSize = 11
        $count.TextAlignment = "Center"
        $count.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 4, 0, 0
        $stack.Children.Add($count) | Out-Null

        $handleManagerTileLeftDown = {
            param($sender, $eventArgs)
            $mods = [System.Windows.Input.Keyboard]::Modifiers
            $ctrl = (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0)
            $shift = (($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0)
            $sourceName = [string]$sender.Tag.OriginalName
            $isSelectedBefore = ($null -ne $tileState["SelectedOriginals"] -and $tileState["SelectedOriginals"].Contains($sourceName))
            if (-not $ctrl -and -not $shift -and $isSelectedBefore -and [int]$tileState["SelectedOriginals"].Count -gt 1) {
                $tileState["LastSelectedOriginal"] = $sourceName
                & $tileUpdateSelectionVisuals $tileState
            }
            else {
                Select-ManagerItem -Item $sender.Tag -Ctrl $ctrl -Shift $shift
            }
            $tileState["DragStartPoint"] = $eventArgs.GetPosition($tileManagerWindow)
            $eventArgs.Handled = $true
        }.GetNewClosure()
        $tile.Add_PreviewMouseLeftButtonDown($handleManagerTileLeftDown)
        $tile.Add_PreviewMouseMove({
            param($sender, $eventArgs)
            if ($eventArgs.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed -or $null -eq $tileState["DragStartPoint"]) {
                return
            }
            $position = $eventArgs.GetPosition($tileManagerWindow)
            $dragStartPoint = $tileState["DragStartPoint"]
            $dx = [Math]::Abs($position.X - $dragStartPoint.X)
            $dy = [Math]::Abs($position.Y - $dragStartPoint.Y)
            if ($dx -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -and $dy -lt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
                return
            }
            $data = New-Object System.Windows.DataObject
            $dragNames = @(Get-ManagerDragNames ([string]$sender.Tag.OriginalName))
            $data.SetData($tileDragFormat, ($dragNames -join "`n"))
            [System.Windows.DragDrop]::DoDragDrop($sender, $data, [System.Windows.DragDropEffects]::Move) | Out-Null
            $tileState["DragStartPoint"] = $null
        }.GetNewClosure())
        $tile.Add_DragOver({
            param($sender, $eventArgs)
            if ($eventArgs.Data.GetDataPresent($tileDragFormat)) {
                $sourceNames = @(Get-ManagerDragNamesFromData ([string]$eventArgs.Data.GetData($tileDragFormat)))
                $targetName = [string]$sender.Tag.OriginalName
                $hasMergeSource = @($sourceNames | Where-Object { [string]$_ -ne $targetName }).Count -gt 0
                if ($hasMergeSource) {
                    $eventArgs.Effects = [System.Windows.DragDropEffects]::Move
                }
                else {
                    $eventArgs.Effects = [System.Windows.DragDropEffects]::None
                }
                $eventArgs.Handled = $true
            }
        }.GetNewClosure())
        $tile.Add_Drop({
            param($sender, $eventArgs)
            if ($eventArgs.Data.GetDataPresent($tileDragFormat)) {
                $sourceItems = New-Object 'System.Collections.Generic.List[object]'
                foreach ($sourceName in @(Get-ManagerDragNamesFromData ([string]$eventArgs.Data.GetData($tileDragFormat)))) {
                    $source = Find-ManagerItem ([string]$sourceName)
                    if ($null -ne $source) {
                        $sourceItems.Add($source) | Out-Null
                    }
                }
                $target = $sender.Tag
                Merge-ManagerItemsBatch -SourceItems @($sourceItems.ToArray()) -TargetItem $target
                $eventArgs.Handled = $true
            }
        }.GetNewClosure())
        $tile.Add_PreviewMouseRightButtonDown({
            param($sender, $eventArgs)
            Ensure-ManagerItemSelectedForContext $sender.Tag
            $sender.ContextMenu = Build-CategoryManagerContextMenu $sender.Tag
            $sender.ContextMenu.PlacementTarget = $sender
            $sender.ContextMenu.IsOpen = $true
            $eventArgs.Handled = $true
        }.GetNewClosure())

        return $tile
    }

    function Refresh-ManagerView {
        $managerState["TileByOriginal"].Clear()
        $panel.Children.Clear()
        $activeItems = @(Get-ActiveManagerItems)
        if ($activeItems.Count -eq 0) {
            $empty = New-Object System.Windows.Controls.TextBlock
            $empty.Text = "没有用户分类"
            $empty.Foreground = $BrushMuted
            $empty.FontSize = 14
            $empty.Margin = New-Object System.Windows.Thickness -ArgumentList 12
            $panel.Children.Add($empty) | Out-Null
        }
        else {
            foreach ($item in $activeItems) {
                $panel.Children.Add((New-CategoryManagerTile $item)) | Out-Null
            }
        }
        Update-ManagerSummary
    }

    function Cleanup-EmptyManagerCategories {
        $changed = $false
        foreach ($item in @(Get-ActiveManagerItems)) {
            if ([int]$item.Count -le 0) {
                $item.IsDeleted = $true
                $changed = $true
            }
        }
        if ($changed) {
            Refresh-ManagerView
        }
    }

    function Resolve-CurrentCategoryAfterManagerChanges {
        if (Is-SystemCategoryName $CurrentCategory) {
            return [string]$CurrentCategory
        }
        $item = Find-ManagerItem ([string]$CurrentCategory)
        if ($null -eq $item) {
            return [string]$CurrentCategory
        }
        $blacklisted = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($name in @(Get-FinalBlacklistNames)) {
            $blacklisted.Add([string]$name) | Out-Null
        }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        while ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.MergeTargetOriginal)) {
            if (-not $seen.Add([string]$item.OriginalName)) {
                return "全部"
            }
            $item = Find-ManagerItem ([string]$item.MergeTargetOriginal)
        }
        if ($null -eq $item -or [bool]$item.IsDeleted -or [bool]$item.IsBlacklisted -or $blacklisted.Contains([string]$item.OriginalName)) {
            return "全部"
        }
        return [string]$item.Name
    }

    function Invoke-CategoryManagerChanges {
        $blacklistedNames = @(Get-FinalBlacklistNames)
        $blacklisted = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($name in @($blacklistedNames)) {
            $blacklisted.Add([string]$name) | Out-Null
        }
        $blacklistedWithoutOwnSource = New-Object 'System.Collections.Generic.HashSet[string]'

        foreach ($name in @($blacklistedNames)) {
            $blacklistItem = Find-ManagerItem ([string]$name)
            if (-not (Test-ManagerHasOwnBlacklistSource $blacklistItem)) {
                $blacklistedWithoutOwnSource.Add([string]$name) | Out-Null
                continue
            }
            Add-StatusLine -Message "分类管理：加入黑名单 $name"
            $result = Invoke-ScannerJson -Arguments @($ScannerPath, "blacklist-category", "--data-dir", $DataDir, "--name", $name, "--summary-only") -ErrorCaption "分类管理失败"
            if ($null -eq $result) {
                return $false
            }
        }

        $mergeItems = @($managerItems.ToArray() | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.MergeTargetOriginal) -and
            -not $blacklisted.Contains([string]$_.OriginalName) -and
            -not $blacklisted.Contains([string]$_.MergeTargetOriginal)
        } | Sort-Object @{ Expression = { Get-MergeDepth $_ }; Descending = $true })

        foreach ($item in $mergeItems) {
            Add-StatusLine -Message "分类管理：合并 $($item.OriginalName) -> $($item.MergeTargetOriginal)"
            $result = Invoke-ScannerJson -Arguments @($ScannerPath, "merge-category", "--data-dir", $DataDir, "--source", ([string]$item.OriginalName), "--target", ([string]$item.MergeTargetOriginal), "--summary-only") -ErrorCaption "分类管理失败"
            if ($null -eq $result) {
                return $false
            }
        }

        foreach ($item in @($managerItems.ToArray() | Where-Object {
            ([bool]$_.IsDeleted -or $blacklistedWithoutOwnSource.Contains([string]$_.OriginalName)) -and
            (-not $blacklisted.Contains([string]$_.OriginalName) -or $blacklistedWithoutOwnSource.Contains([string]$_.OriginalName))
        })) {
            Add-StatusLine -Message "分类管理：删除 $($item.OriginalName)"
            $result = Invoke-ScannerJson -Arguments @($ScannerPath, "delete-category", "--data-dir", $DataDir, "--name", ([string]$item.OriginalName), "--summary-only") -ErrorCaption "分类管理失败"
            if ($null -eq $result) {
                return $false
            }
        }

        foreach ($item in @($managerItems.ToArray() | Where-Object {
            (Test-ManagerItemActive $_) -and
            -not $blacklisted.Contains([string]$_.OriginalName) -and
            [string]$_.Name -ne [string]$_.OriginalName
        })) {
            Add-StatusLine -Message "分类管理：重命名 $($item.OriginalName) -> $($item.Name)"
            $result = Invoke-ScannerJson -Arguments @($ScannerPath, "rename-category", "--data-dir", $DataDir, "--name", ([string]$item.OriginalName), "--new-name", ([string]$item.Name), "--summary-only") -ErrorCaption "分类管理失败"
            if ($null -eq $result) {
                return $false
            }
        }

        return $true
    }

    function Get-ManagerConfirmationText {
        $blacklistedNames = @(Get-FinalBlacklistNames)
        $renames = @($managerItems.ToArray() | Where-Object { (Test-ManagerItemActive $_) -and [string]$_.Name -ne [string]$_.OriginalName } | ForEach-Object { "$($_.OriginalName) -> $($_.Name)" })
        $merges = @($managerItems.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.MergeTargetOriginal) } | ForEach-Object { "$($_.OriginalName) -> $($_.MergeTargetOriginal)" })
        $deletes = @($managerItems.ToArray() | Where-Object { [bool]$_.IsDeleted } | ForEach-Object { [string]$_.OriginalName })

        $lines = @("要应用这些分类管理操作吗？")
        if ($renames.Count -gt 0) { $lines += "重命名：$((@($renames | Select-Object -First 8)) -join '、')" }
        if ($merges.Count -gt 0) { $lines += "合并：$((@($merges | Select-Object -First 8)) -join '、')" }
        if ($deletes.Count -gt 0) { $lines += "删除：$((@($deletes | Select-Object -First 8)) -join '、')" }
        if ($blacklistedNames.Count -gt 0) { $lines += "加入黑名单：$((@($blacklistedNames | Select-Object -First 8)) -join '、')" }
        $lines += ""
        $lines += "选择「是」应用，「否」放弃，「取消」返回继续编辑。"
        return ($lines -join [Environment]::NewLine)
    }

    foreach ($functionName in @(
        "Find-ManagerItem",
        "Test-ManagerItemActive",
        "Test-ManagerHasOwnBlacklistSource",
        "Get-ManagerUltimateTarget",
        "Test-ManagerCanBlacklistItem",
        "Get-ActiveManagerItems",
        "Get-ManagerItemIndexInView",
        "Clear-ManagerSelection",
        "Select-AllManagerItems",
        "Select-ManagerItem",
        "Ensure-ManagerItemSelectedForContext",
        "Get-SelectedManagerItems",
        "Get-ManagerDragNames",
        "Get-ManagerDragNamesFromData",
        "Test-ManagerEventSourceIsTile",
        "Test-ManagerCategoryNameAvailable",
        "Get-MergeDepth",
        "Get-FinalBlacklistNames",
        "Test-ManagerHasPendingChanges",
        "Get-PendingSummary",
        "Update-ManagerSummary",
        "Show-CategoryProperties",
        "Prompt-MergeTarget",
        "Merge-ManagerItems",
        "Merge-ManagerItemsBatch",
        "Delete-ManagerItemsBatch",
        "Blacklist-ManagerItemsBatch",
        "Rename-ManagerItem",
        "Build-CategoryManagerContextMenu",
        "Update-ManagerTileSelectionVisuals",
        "New-CategoryManagerTile",
        "Refresh-ManagerView",
        "Cleanup-EmptyManagerCategories",
        "Resolve-CurrentCategoryAfterManagerChanges",
        "Invoke-CategoryManagerChanges",
        "Get-ManagerConfirmationText"
    )) {
        $command = Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            Set-Item -Path "Function:\Script:$functionName" -Value ($command.ScriptBlock.GetNewClosure())
        }
    }

    $managerSortComboBox.Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($null -eq $sender.SelectedItem) {
            return
        }
        $managerState["SortMode"] = [string]$sender.SelectedItem.Tag
        Refresh-ManagerView
    }.GetNewClosure())

    $managerWindow.Add_KeyDown({
        param($sender, $eventArgs)
        $mods = [System.Windows.Input.Keyboard]::Modifiers
        if (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0 -and $eventArgs.Key -eq [System.Windows.Input.Key]::A) {
            Select-AllManagerItems
            $eventArgs.Handled = $true
            return
        }
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            Clear-ManagerSelection
            $eventArgs.Handled = $true
        }
    }.GetNewClosure())

    $blankMenu = New-Object System.Windows.Controls.ContextMenu
    $selectAllItem = New-Object System.Windows.Controls.MenuItem
    $selectAllItem.Header = "全选"
    $selectAllItem.Add_Click({ Select-AllManagerItems }.GetNewClosure())
    $clearSelectionItem = New-Object System.Windows.Controls.MenuItem
    $clearSelectionItem.Header = "取消选择"
    $clearSelectionItem.Add_Click({ Clear-ManagerSelection }.GetNewClosure())
    $cleanupItem = New-Object System.Windows.Controls.MenuItem
    $cleanupItem.Header = "清理空分类"
    $cleanupItem.Add_Click({ Cleanup-EmptyManagerCategories }.GetNewClosure())
    $blankMenu.Items.Add($selectAllItem) | Out-Null
    $blankMenu.Items.Add($clearSelectionItem) | Out-Null
    $blankMenu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $blankMenu.Items.Add($cleanupItem) | Out-Null
    $panel.ContextMenu = $blankMenu
    $scroll.Add_PreviewMouseLeftButtonDown({
        param($sender, $eventArgs)
        if (-not (Test-ManagerEventSourceIsTile $eventArgs.OriginalSource)) {
            Clear-ManagerSelection
            $eventArgs.Handled = $true
        }
    }.GetNewClosure())

    $closeButton.Add_Click({
        param($sender, $eventArgs)
        $managerWindow.Close()
    })

    $managerWindow.Add_Closing({
        param($sender, $eventArgs)
        if ([bool]$managerState["ApplyingChanges"] -or -not (Test-ManagerHasPendingChanges)) {
            return
        }

        $choice = [System.Windows.MessageBox]::Show(
            $managerWindow,
            (Get-ManagerConfirmationText),
            "应用分类管理",
            [System.Windows.MessageBoxButton]::YesNoCancel,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($choice -eq [System.Windows.MessageBoxResult]::Cancel) {
            $eventArgs.Cancel = $true
            return
        }
        if ($choice -eq [System.Windows.MessageBoxResult]::No) {
            return
        }

        $nextCurrentCategory = Resolve-CurrentCategoryAfterManagerChanges
        $managerState["ApplyingChanges"] = $true
        if (-not (Invoke-CategoryManagerChanges)) {
            $managerState["ApplyingChanges"] = $false
            $eventArgs.Cancel = $true
            return
        }
        $Script:CurrentCategory = $nextCurrentCategory
        Clear-Selection
        Mark-ShelfMetadataDirty
        Render-Library -Reload:$true
        Add-StatusLine -Message "分类管理：已应用更改"
    }.GetNewClosure())

    Refresh-ManagerView
    $managerWindow.ShowDialog() | Out-Null
}

function Show-TagMappingManagerWindow {
    $managerWindow = New-Object System.Windows.Window
    $managerWindow.Title = "Tag管理"
    $managerWindow.Width = 980
    $managerWindow.Height = 640
    $managerWindow.MinWidth = 780
    $managerWindow.MinHeight = 480
    $managerWindow.WindowStartupLocation = "CenterOwner"
    $managerWindow.Owner = $Window
    $managerWindow.Background = $BrushWindow

    $state = @{
        Rows = @()
        TargetCategories = @()
        Filter = "all"
        Search = ""
    }

    function Set-TagManagerComboBoxTheme {
        param(
            [Parameter(Mandatory = $true)]
            [System.Windows.Controls.ComboBox]$ComboBox
        )

        $ComboBox.Background = $BrushCard
        $ComboBox.Foreground = $BrushText
        $ComboBox.BorderBrush = New-SolidBrush "#3A3F4B"
        $ComboBox.Cursor = [System.Windows.Input.Cursors]::Hand
        $ComboBox.Resources[[System.Windows.SystemColors]::WindowBrushKey] = $BrushCard
        $ComboBox.Resources[[System.Windows.SystemColors]::ControlBrushKey] = $BrushCard
        $ComboBox.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = $BrushText
        $ComboBox.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = $BrushSidebarItemSelected
        $ComboBox.Resources[[System.Windows.SystemColors]::HighlightTextBrushKey] = $BrushText
    }

    function New-TagManagerComboBoxItem {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Label,

            [Parameter(Mandatory = $true)]
            $TagValue
        )

        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $Label
        $item.Tag = $TagValue
        $item.Background = $BrushCard
        $item.Foreground = $BrushText
        $item.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 5, 10, 5
        $item.MinHeight = 28
        $item.Add_MouseEnter({
            param($sender, $eventArgs)
            $sender.Background = $BrushCardHover
            $sender.Foreground = $BrushText
        })
        $item.Add_MouseLeave({
            param($sender, $eventArgs)
            $sender.Background = $BrushCard
            $sender.Foreground = $BrushText
        })
        return $item
    }

    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = New-Object System.Windows.Thickness -ArgumentList 18
    $rowHeader = New-Object System.Windows.Controls.RowDefinition
    $rowHeader.Height = New-Object System.Windows.GridLength -ArgumentList 42
    $rowTools = New-Object System.Windows.Controls.RowDefinition
    $rowTools.Height = New-Object System.Windows.GridLength -ArgumentList 44
    $rowSummary = New-Object System.Windows.Controls.RowDefinition
    $rowSummary.Height = New-Object System.Windows.GridLength -ArgumentList 30
    $rowGrid = New-Object System.Windows.Controls.RowDefinition
    $rowGrid.Height = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
    $rowBottom = New-Object System.Windows.Controls.RowDefinition
    $rowBottom.Height = New-Object System.Windows.GridLength -ArgumentList 50
    $root.RowDefinitions.Add($rowHeader) | Out-Null
    $root.RowDefinitions.Add($rowTools) | Out-Null
    $root.RowDefinitions.Add($rowSummary) | Out-Null
    $root.RowDefinitions.Add($rowGrid) | Out-Null
    $root.RowDefinitions.Add($rowBottom) | Out-Null

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Tag管理"
    $title.Foreground = $BrushText
    $title.FontSize = 22
    $title.FontWeight = "SemiBold"
    $title.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $root.Children.Add($title) | Out-Null

    $tools = New-Object System.Windows.Controls.DockPanel
    $tools.LastChildFill = $true
    [System.Windows.Controls.Grid]::SetRow($tools, 1)

    $filterBox = New-Object System.Windows.Controls.ComboBox
    $filterBox.Width = 130
    $filterBox.Height = 30
    $filterBox.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 10, 0
    Set-TagManagerComboBoxTheme -ComboBox $filterBox
    foreach ($entry in @(
        @("all", "全部"),
        @("unmapped", "未映射"),
        @("mapped", "已映射"),
        @("manual", "手动映射"),
        @("blacklisted", "黑名单")
    )) {
        $comboItem = New-TagManagerComboBoxItem -Label ([string]$entry[1]) -TagValue ([string]$entry[0])
        $filterBox.Items.Add($comboItem) | Out-Null
    }
    $filterBox.SelectedIndex = 0
    [System.Windows.Controls.DockPanel]::SetDock($filterBox, "Left")
    $tools.Children.Add($filterBox) | Out-Null

    $searchBox = New-Object System.Windows.Controls.TextBox
    $searchBox.Height = 30
    $searchBox.Padding = New-Object System.Windows.Thickness -ArgumentList 8, 4, 8, 4
    $searchBox.Background = $BrushCard
    $searchBox.Foreground = $BrushText
    $searchBox.BorderBrush = New-SolidBrush "#3A3F4B"
    $searchBox.ToolTip = "搜索 raw tag 或分类名"
    $tools.Children.Add($searchBox) | Out-Null
    $root.Children.Add($tools) | Out-Null

    $summaryText = New-Object System.Windows.Controls.TextBlock
    $summaryText.Foreground = $BrushMuted
    $summaryText.FontSize = 12
    $summaryText.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetRow($summaryText, 2)
    $root.Children.Add($summaryText) | Out-Null

    $grid = New-Object System.Windows.Controls.DataGrid
    $grid.AutoGenerateColumns = $false
    $grid.IsReadOnly = $true
    $grid.SelectionMode = "Extended"
    $grid.SelectionUnit = "FullRow"
    $grid.HeadersVisibility = "Column"
    $grid.GridLinesVisibility = "None"
    $grid.RowBackground = $BrushCard
    $grid.AlternatingRowBackground = New-SolidBrush "#242832"
    $grid.Background = $BrushWindow
    $grid.Foreground = $BrushText
    $grid.BorderBrush = New-SolidBrush "#303642"
    $grid.HorizontalGridLinesBrush = $BrushTransparent
    $grid.VerticalGridLinesBrush = $BrushTransparent
    $grid.CanUserAddRows = $false
    $grid.CanUserDeleteRows = $false
    $grid.CanUserReorderColumns = $false
    $grid.EnableRowVirtualization = $true
    $grid.EnableColumnVirtualization = $true
    $grid.ColumnHeaderHeight = 30
    $grid.ColumnHeaderStyle = [System.Windows.Markup.XamlReader]::Parse(@"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type DataGridColumnHeader}">
    <Setter Property="Background" Value="#20232A"/>
    <Setter Property="Foreground" Value="#ECEFF4"/>
    <Setter Property="BorderBrush" Value="#303642"/>
    <Setter Property="BorderThickness" Value="0,0,1,1"/>
    <Setter Property="Padding" Value="10,0,10,0"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="HorizontalContentAlignment" Value="Left"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
</Style>
"@)

    function Add-TagGridTextColumn {
        param(
            [string]$Header,
            [string]$Path,
            [double]$Width = 120
        )

        $column = New-Object System.Windows.Controls.DataGridTextColumn
        $column.Header = $Header
        $column.Binding = New-Object System.Windows.Data.Binding -ArgumentList $Path
        $column.Width = New-Object System.Windows.Controls.DataGridLength -ArgumentList $Width
        $grid.Columns.Add($column) | Out-Null
    }

    Add-TagGridTextColumn -Header "状态" -Path "statusText" -Width 86
    Add-TagGridTextColumn -Header "来源" -Path "source" -Width 72
    Add-TagGridTextColumn -Header "原始Tag" -Path "rawTag" -Width 160
    Add-TagGridTextColumn -Header "目标分类" -Path "targetCategory" -Width 200
    Add-TagGridTextColumn -Header "作品数" -Path "itemCount" -Width 70
    Add-TagGridTextColumn -Header "作品示例" -Path "sampleText" -Width 360

    [System.Windows.Controls.Grid]::SetRow($grid, 3)
    $root.Children.Add($grid) | Out-Null

    $bottom = New-Object System.Windows.Controls.DockPanel
    $bottom.LastChildFill = $false
    [System.Windows.Controls.Grid]::SetRow($bottom, 4)

    $tagManagerButtonStyle = [System.Windows.Markup.XamlReader]::Parse(@"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type Button}">
    <Setter Property="Background" Value="#2E3440"/>
    <Setter Property="Foreground" Value="#ECEFF4"/>
    <Setter Property="BorderBrush" Value="#00000000"/>
    <Setter Property="Padding" Value="10,0,10,0"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="{x:Type Button}">
                <Border x:Name="ButtonBorder"
                        Background="{TemplateBinding Background}"
                        BorderBrush="{TemplateBinding BorderBrush}"
                        BorderThickness="{TemplateBinding BorderThickness}"
                        CornerRadius="4">
                    <ContentPresenter HorizontalAlignment="Center"
                                      VerticalAlignment="Center"
                                      RecognizesAccessKey="True"/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="ButtonBorder" Property="Background" Value="#3A4150"/>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True">
                        <Setter TargetName="ButtonBorder" Property="Background" Value="#20232A"/>
                    </Trigger>
                    <Trigger Property="IsEnabled" Value="False">
                        <Setter Property="Foreground" Value="#9AA3B2"/>
                        <Setter TargetName="ButtonBorder" Property="Background" Value="#20232A"/>
                        <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.72"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
"@)

    function New-TagManagerButton {
        param(
            [string]$Text,
            [double]$Width = 112
        )

        $button = New-Object System.Windows.Controls.Button
        $button.Content = $Text
        $button.Width = $Width
        $button.Height = 32
        $button.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 8, 8, 0
        $button.Background = $BrushSidebarItemSelected
        $button.Foreground = $BrushText
        $button.BorderBrush = $BrushTransparent
        $button.Cursor = [System.Windows.Input.Cursors]::Hand
        $button.Style = $tagManagerButtonStyle
        return $button
    }

    $mapButton = New-TagManagerButton -Text "映射到分类" -Width 118
    $blacklistButton = New-TagManagerButton -Text "加入黑名单" -Width 110
    $keepButton = New-TagManagerButton -Text "保留自定义" -Width 110
    $refreshButton = New-TagManagerButton -Text "刷新" -Width 78
    $closeButton = New-TagManagerButton -Text "关闭" -Width 78
    $closeButton.Background = $BrushAccent
    $closeButton.Foreground = $BrushWindow

    $bottom.Children.Add($mapButton) | Out-Null
    $bottom.Children.Add($blacklistButton) | Out-Null
    $bottom.Children.Add($keepButton) | Out-Null
    $bottom.Children.Add($refreshButton) | Out-Null
    [System.Windows.Controls.DockPanel]::SetDock($closeButton, "Right")
    $bottom.Children.Add($closeButton) | Out-Null
    $root.Children.Add($bottom) | Out-Null

    $managerWindow.Content = $root

    function Get-TagSelectedRows {
        return @($grid.SelectedItems | Where-Object { $null -ne $_ })
    }

    function Update-TagActionState {
        $hasSelection = @(Get-TagSelectedRows).Count -gt 0
        $mapButton.IsEnabled = $hasSelection -and @($state["TargetCategories"]).Count -gt 0
        $blacklistButton.IsEnabled = $hasSelection
        $keepButton.IsEnabled = $hasSelection
    }

    function Refresh-TagMappingView {
        $filter = [string]$state["Filter"]
        $search = ([string]$state["Search"]).Trim()
        $rows = @($state["Rows"])
        if ($filter -ne "all") {
            $rows = @($rows | Where-Object { [string]$_.status -eq $filter })
        }
        if (-not [string]::IsNullOrWhiteSpace($search)) {
            $needle = $search.ToLowerInvariant()
            $rows = @($rows | Where-Object {
                (([string]$_.rawTag).ToLowerInvariant().Contains($needle)) -or
                (([string]$_.targetCategory).ToLowerInvariant().Contains($needle))
            })
        }

        foreach ($row in @($rows)) {
            $samples = @($row.sampleItems)
            $row | Add-Member -NotePropertyName sampleText -NotePropertyValue (($samples | Select-Object -First 2) -join "；") -Force
        }
        $grid.ItemsSource = @($rows)

        $counts = @{
            all = @($state["Rows"]).Count
            mapped = 0
            manual = 0
            unmapped = 0
            blacklisted = 0
        }
        foreach ($row in @($state["Rows"])) {
            $status = [string]$row.status
            if ($counts.ContainsKey($status)) {
                $counts[$status] = [int]$counts[$status] + 1
            }
        }
        $summaryText.Text = "全部 $($counts.all)；已映射 $($counts.mapped)；手动映射 $($counts.manual)；未映射 $($counts.unmapped)；黑名单 $($counts.blacklisted)"
        Update-TagActionState
    }

    function Load-TagMappingData {
        $result = Invoke-ScannerJson -Arguments @($ScannerPath, "tag-mappings", "--data-dir", $DataDir) -ErrorCaption "读取Tag映射失败"
        if ($null -eq $result) {
            return $false
        }
        $state["Rows"] = @($result.rows)
        $state["TargetCategories"] = @($result.targetCategories)
        Refresh-TagMappingView
        return $true
    }

    function Prompt-TagTargetCategory {
        $dialog = New-Object System.Windows.Window
        $dialog.Title = "选择目标分类"
        $dialog.Width = 520
        $dialog.Height = 180
        $dialog.WindowStartupLocation = "CenterOwner"
        $dialog.Owner = $managerWindow
        $dialog.Background = $BrushWindow
        $dialog.ResizeMode = "NoResize"

        $panel = New-Object System.Windows.Controls.StackPanel
        $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 18

        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = "选择一个已有 tag 分类作为映射目标"
        $label.Foreground = $BrushText
        $label.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 10
        $panel.Children.Add($label) | Out-Null

        $combo = New-Object System.Windows.Controls.ComboBox
        $combo.Height = 32
        Set-TagManagerComboBoxTheme -ComboBox $combo
        foreach ($target in @($state["TargetCategories"])) {
            $labelText = [string]$target.label
            if ([string]::IsNullOrWhiteSpace($labelText)) {
                $labelText = [string]$target.category
            }
            $combo.Items.Add((New-TagManagerComboBoxItem -Label $labelText -TagValue $target)) | Out-Null
        }
        if ($combo.Items.Count -gt 0) {
            $combo.SelectedIndex = 0
        }
        $panel.Children.Add($combo) | Out-Null

        $buttons = New-Object System.Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"
        $buttons.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 16, 0, 0
        $ok = New-TagManagerButton -Text "确定" -Width 76
        $cancel = New-TagManagerButton -Text "取消" -Width 76
        $buttons.Children.Add($ok) | Out-Null
        $buttons.Children.Add($cancel) | Out-Null
        $panel.Children.Add($buttons) | Out-Null

        $selected = @{ Item = $null }
        $ok.Add_Click({
            if ($null -ne $combo.SelectedItem) {
                $selected["Item"] = $combo.SelectedItem.Tag
                $dialog.DialogResult = $true
            }
        }.GetNewClosure())
        $cancel.Add_Click({ $dialog.DialogResult = $false }.GetNewClosure())

        $dialog.Content = $panel
        if ($dialog.ShowDialog() -eq $true) {
            return $selected["Item"]
        }
        return $null
    }

    function Invoke-TagRulesChanged {
        param(
            [string]$Message
        )

        Add-StatusLine -Message $Message
        Load-TagMappingData | Out-Null
        $Script:LibraryLoaded = $false
        Mark-ShelfMetadataDirty
        Render-Library -Reload:$true
    }

    $filterBox.Add_SelectionChanged({
        if ($null -ne $filterBox.SelectedItem) {
            $state["Filter"] = [string]$filterBox.SelectedItem.Tag
            Refresh-TagMappingView
        }
    }.GetNewClosure())

    $searchBox.Add_TextChanged({
        $state["Search"] = [string]$searchBox.Text
        Refresh-TagMappingView
    }.GetNewClosure())

    $grid.Add_SelectionChanged({ Update-TagActionState }.GetNewClosure())

    $mapButton.Add_Click({
        $rows = @(Get-TagSelectedRows)
        if ($rows.Count -eq 0) {
            return
        }
        $target = Prompt-TagTargetCategory
        if ($null -eq $target) {
            return
        }
        $targetCategory = [string]$target.category
        foreach ($row in $rows) {
            Invoke-ScannerJson -Arguments @($ScannerPath, "map-raw-tag", "--data-dir", $DataDir, "--source", ([string]$row.source), "--raw", ([string]$row.rawTag), "--target-category", $targetCategory, "--summary-only") -ErrorCaption "映射Tag失败" | Out-Null
        }
        Invoke-TagRulesChanged -Message "Tag管理：已映射 $($rows.Count) 个 raw tag 到 $targetCategory"
    }.GetNewClosure())

    $blacklistButton.Add_Click({
        $rows = @(Get-TagSelectedRows)
        if ($rows.Count -eq 0) {
            return
        }
        if (-not (Confirm-AppMessage -Caption "加入黑名单" -Message "要把选中的 $($rows.Count) 个 raw tag 加入黑名单吗？")) {
            return
        }
        foreach ($row in $rows) {
            Invoke-ScannerJson -Arguments @($ScannerPath, "blacklist-raw-tag", "--data-dir", $DataDir, "--source", ([string]$row.source), "--raw", ([string]$row.rawTag), "--summary-only") -ErrorCaption "加入黑名单失败" | Out-Null
        }
        Invoke-TagRulesChanged -Message "Tag管理：已加入黑名单 $($rows.Count) 个 raw tag"
    }.GetNewClosure())

    $keepButton.Add_Click({
        $rows = @(Get-TagSelectedRows)
        if ($rows.Count -eq 0) {
            return
        }
        if ($rows.Count -eq 1) {
            $defaultName = [string]$rows[0].rawTag
            $categoryName = [Microsoft.VisualBasic.Interaction]::InputBox("输入要创建或使用的分类名", "保留为自定义分类", $defaultName)
            if ([string]::IsNullOrWhiteSpace($categoryName)) {
                return
            }
            Invoke-ScannerJson -Arguments @($ScannerPath, "keep-raw-tag-category", "--data-dir", $DataDir, "--source", ([string]$rows[0].source), "--raw", ([string]$rows[0].rawTag), "--category", $categoryName, "--summary-only") -ErrorCaption "保留自定义分类失败" | Out-Null
        }
        else {
            if (-not (Confirm-AppMessage -Caption "保留自定义分类" -Message "要把选中的 $($rows.Count) 个 raw tag 分别保留为同名自定义分类吗？")) {
                return
            }
            foreach ($row in $rows) {
                Invoke-ScannerJson -Arguments @($ScannerPath, "keep-raw-tag-category", "--data-dir", $DataDir, "--source", ([string]$row.source), "--raw", ([string]$row.rawTag), "--summary-only") -ErrorCaption "保留自定义分类失败" | Out-Null
            }
        }
        Invoke-TagRulesChanged -Message "Tag管理：已保留自定义分类 $($rows.Count) 个 raw tag"
    }.GetNewClosure())

    $refreshButton.Add_Click({ Load-TagMappingData | Out-Null }.GetNewClosure())
    $closeButton.Add_Click({ $managerWindow.Close() }.GetNewClosure())

    Load-TagMappingData | Out-Null
    $managerWindow.ShowDialog() | Out-Null
}

function Show-TagClassificationSummary($Result) {
    if ($null -eq $Result) {
        return
    }

    $updatedItems = @($Result.updated)
    $classifiedCount = @($updatedItems | Where-Object { [int]$_.categoryCount -gt 0 }).Count
    $emptyCount = $updatedItems.Count - $classifiedCount
    $notFoundCount = @($Result.notFound).Count
    $errorCount = @($Result.errors).Count
    $skippedCount = @($Result.skipped).Count

    if ($notFoundCount -gt 0 -or $errorCount -gt 0 -or $emptyCount -gt 0 -or $skippedCount -gt 0) {
        $parts = @("已分类 $classifiedCount 本")
        if ($emptyCount -gt 0) {
            $parts += "$emptyCount 本匹配成功但没有生成中文分类"
        }
        if ($notFoundCount -gt 0) {
            $parts += "$notFoundCount 本已加入 tag未找到"
        }
        if ($skippedCount -gt 0) {
            $parts += "$skippedCount 本已跳过"
        }
        if ($errorCount -gt 0) {
            $parts += "$errorCount 本未能识别Tag"
        }
        Show-AppMessage -Message (($parts -join "，") + "。") -Caption "Tag识别" -Image ([System.Windows.MessageBoxImage]::Warning)
    }
    else {
        Show-AppMessage -Message "已分类 $classifiedCount 本。" -Caption "Tag识别"
    }
}

function Invoke-TagClassification {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids,

        [bool]$ShowSummary = $false
    )

    $validIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($validIds.Count -eq 0) {
        return $null
    }

    if ($TagRunning) {
        Add-StatusLine -Message "Tag识别正在运行，已忽略新的启动请求。"
        return $null
    }

    if (-not (Ensure-TagTranslationPreference)) {
        return $null
    }
    $translationMode = Get-TagTranslationModeForProcess

    $workerDir = Join-Path $DataDir "tag-worker"
    New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
    $runId = [System.Guid]::NewGuid().ToString("N")
    $Script:TagResultPath = Join-Path $workerDir "$runId.result.json"
    $Script:TagProgressPath = Join-Path $workerDir "$runId.progress.jsonl"
    $Script:TagProgressPosition = [int64]0
    $Script:TagProgressRemainder = ""
    $Script:TagBatchCount = $validIds.Count
    $Script:TagShowSummary = $ShowSummary

    $arguments = @($ScannerPath, "classify-tags", "--data-dir", $DataDir, "--delay-ms", "3000", "--delay-max-ms", "5000", "--summary-only", "--output-file", $TagResultPath, "--progress-file", $TagProgressPath)
    $arguments += $validIds

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonPath
    $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $true
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables["MANGAGA_TAG_TRANSLATION_MODE"] = $translationMode

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        $Script:TagProcess = $process
        $Script:TagRunning = $true
        $TagTimer.Start()
        Add-StatusLine -Message "已启动后台 Tag 识别：$($validIds.Count) 本"
        return $true
    }
    catch {
        $Script:TagProcess = $null
        $Script:TagRunning = $false
        $Script:TagResultPath = ""
        $Script:TagProgressPath = ""
        $Script:TagProgressPosition = [int64]0
        $Script:TagProgressRemainder = ""
        $Script:TagBatchCount = 0
        Show-AppMessage -Message "启动 Tag 识别失败：$($_.Exception.Message)" -Caption "Tag识别失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return $null
    }
}

function Invoke-DuplicateCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids,

        [string]$ScopeLabel = "选中项目"
    )

    $validIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($validIds.Count -eq 0) {
        Add-StatusLine -Message "查重：没有可检查的漫画。"
        return $null
    }

    if ($DuplicateRunning) {
        Add-StatusLine -Message "查重正在运行，已忽略新的启动请求。"
        return $null
    }

    $workerDir = Join-Path $DataDir "duplicate-worker"
    New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
    $runId = [System.Guid]::NewGuid().ToString("N")
    $Script:DuplicateResultPath = $DuplicateResultsPath
    $Script:DuplicateIdsPath = Join-Path $workerDir "$runId.ids.json"
    $Script:DuplicateProgressPath = Join-Path $workerDir "$runId.progress.jsonl"
    $Script:DuplicateProgressPosition = [int64]0
    $Script:DuplicateProgressRemainder = ""
    $Script:DuplicateBatchCount = $validIds.Count

    try {
        ConvertTo-Json -InputObject @($validIds) -Depth 3 | Set-Content -LiteralPath $DuplicateIdsPath -Encoding UTF8
    }
    catch {
        $Script:DuplicateResultPath = ""
        if (-not [string]::IsNullOrWhiteSpace($DuplicateIdsPath) -and (Test-Path -LiteralPath $DuplicateIdsPath)) {
            try {
                Remove-Item -LiteralPath $DuplicateIdsPath -Force
            }
            catch {
            }
        }
        $Script:DuplicateIdsPath = ""
        $Script:DuplicateProgressPath = ""
        $Script:DuplicateProgressPosition = [int64]0
        $Script:DuplicateProgressRemainder = ""
        $Script:DuplicateBatchCount = 0
        Show-AppMessage -Message "写入查重任务清单失败：$($_.Exception.Message)" -Caption "查重失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return $null
    }

    $arguments = @($ScannerPath, "find-duplicates", "--data-dir", $DataDir, "--output-file", $DuplicateResultPath, "--progress-file", $DuplicateProgressPath, "--ids-file", $DuplicateIdsPath)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonPath
    $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $true
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        $Script:DuplicateProcess = $process
        $Script:DuplicateRunning = $true
        $DuplicateTimer.Start()
        Add-StatusLine -Message "已启动后台查重：$ScopeLabel，共 $($validIds.Count) 本"
        return $true
    }
    catch {
        $Script:DuplicateProcess = $null
        $Script:DuplicateRunning = $false
        $Script:DuplicateResultPath = ""
        if (-not [string]::IsNullOrWhiteSpace($DuplicateIdsPath) -and (Test-Path -LiteralPath $DuplicateIdsPath)) {
            try {
                Remove-Item -LiteralPath $DuplicateIdsPath -Force
            }
            catch {
            }
        }
        $Script:DuplicateIdsPath = ""
        $Script:DuplicateProgressPath = ""
        $Script:DuplicateProgressPosition = [int64]0
        $Script:DuplicateProgressRemainder = ""
        $Script:DuplicateBatchCount = 0
        Show-AppMessage -Message "启动查重失败：$($_.Exception.Message)" -Caption "查重失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return $null
    }
}

function Toggle-SelectedCategory {
    param(
        [string]$Category
    )

    if ([string]::IsNullOrWhiteSpace($Category)) {
        Show-AppMessage -Message "分类名称为空，无法设置。" -Caption "设置分类" -Image ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    $ids = Resolve-RealItemIds -Ids @($SelectedIds)
    if ($ids.Count -eq 0) {
        return
    }

    $allHaveCategory = Selected-Items-AllHaveCategory $Category
    if ($allHaveCategory) {
        $arguments = @($ScannerPath, "unassign-category", "--data-dir", $DataDir, "--name", $Category, "--summary-only")
    }
    else {
        $arguments = @($ScannerPath, "assign-category", "--data-dir", $DataDir, "--name", $Category, "--summary-only")
        if ($Category -eq $FavoriteCategory) {
            $arguments += "--explicit-favorite"
        }
    }
    $arguments += $ids

    $result = Invoke-ScannerJson -Arguments $arguments -ErrorCaption "设置分类失败"
    if ($null -eq $result) {
        return
    }

    $updatedIds = @($result.updated | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($updatedIds.Count -gt 0) {
        $resultCategory = [string]$result.category
        $resultAction = [string]$result.action
        Apply-CategoryChangeToMemory -Ids ([string[]]$updatedIds) -Category $resultCategory -Action $resultAction
    }
    Render-Library -Reload:$false -PreservePage:$true -RefreshMetadata:($updatedIds.Count -gt 0)
}

function Invoke-CategoryDragAutoScroll {
    param(
        $EventArgs
    )

    if ($null -eq $EventArgs -or $null -eq $CategoryScrollViewer) {
        return
    }
    if (-not $EventArgs.Data.GetDataPresent($CategoryDragFormat)) {
        return
    }

    $height = [double]$CategoryScrollViewer.ActualHeight
    $scrollableHeight = [double]$CategoryScrollViewer.ScrollableHeight
    if ($height -le 0 -or $scrollableHeight -le 0) {
        return
    }

    $position = $EventArgs.GetPosition($CategoryScrollViewer)
    $edge = [Math]::Min(56.0, [Math]::Max(28.0, $height * 0.18))
    $offset = [double]$CategoryScrollViewer.VerticalOffset
    $targetOffset = $offset

    if ($position.Y -lt $edge) {
        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, ($edge - $position.Y) / $edge))
        $targetOffset = [Math]::Max(0.0, $offset - (8.0 + (34.0 * $ratio)))
    }
    elseif ($position.Y -gt ($height - $edge)) {
        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, ($position.Y - ($height - $edge)) / $edge))
        $targetOffset = [Math]::Min($scrollableHeight, $offset + (8.0 + (34.0 * $ratio)))
    }

    if ([Math]::Abs($targetOffset - $offset) -gt 0.1) {
        $CategoryScrollViewer.ScrollToVerticalOffset($targetOffset)
    }
}

function New-SidebarActionButton {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ClickAction
    )

    $border = New-Object System.Windows.Controls.Border
    $border.Height = 34
    $border.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 2, 0, 2
    $border.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 0, 10, 0
    $border.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 6
    $border.Background = $BrushSidebarItem
    $border.Cursor = [System.Windows.Input.Cursors]::Hand

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Text
    $label.Foreground = $BrushAccent
    $label.FontSize = 14
    $label.VerticalAlignment = "Center"
    $label.TextTrimming = "CharacterEllipsis"
    $border.Child = $label

    $border.Add_MouseEnter({
        param($sender, $eventArgs)
        $sender.Background = $BrushSidebarItemHover
    })
    $border.Add_MouseLeave({
        param($sender, $eventArgs)
        $sender.Background = $BrushSidebarItem
    })
    $border.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        & $ClickAction
        $eventArgs.Handled = $true
    }.GetNewClosure())

    return $border
}

$CategoryScrollViewer.Add_DragOver({
    param($sender, $eventArgs)
    if ($eventArgs.Data.GetDataPresent($CategoryDragFormat)) {
        Invoke-CategoryDragAutoScroll -EventArgs $eventArgs
        $eventArgs.Effects = [System.Windows.DragDropEffects]::Move
        $eventArgs.Handled = $true
    }
})

function New-CategoryButton {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [bool]$IsSystem = $false,

        [bool]$IsAddButton = $false,

        [int]$Count = -1
    )

    $border = New-Object System.Windows.Controls.Border
    $border.Height = 34
    $border.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 2, 0, 2
    $border.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 0, 10, 0
    $border.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 6
    $border.Background = if ($CurrentCategory -eq $Category -and -not $IsAddButton) { $BrushSidebarItemSelected } else { $BrushSidebarItem }
    $border.Cursor = [System.Windows.Input.Cursors]::Hand
    $border.Tag = $Category

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = if ($IsAddButton) { "+ 新建分类" } elseif ($Count -ge 0) { "$Category ($Count)" } else { $Category }
    $label.Foreground = if ($IsAddButton) { $BrushAccent } else { $BrushText }
    $label.FontSize = 14
    $label.VerticalAlignment = "Center"
    $label.TextTrimming = "CharacterEllipsis"
    $border.Child = $label

    $border.Add_MouseEnter({
        param($sender, $eventArgs)
        if ([string]$sender.Tag -ne $CurrentCategory) {
            $sender.Background = $BrushSidebarItemHover
        }
    })

    $border.Add_MouseLeave({
        param($sender, $eventArgs)
        if ([string]$sender.Tag -eq $CurrentCategory -and [string]$sender.Tag -ne "__add__") {
            $sender.Background = $BrushSidebarItemSelected
        }
        else {
            $sender.Background = $BrushSidebarItem
        }
    })

    if ($IsAddButton) {
        $border.Tag = "__add__"
        $border.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            Add-NewCategory
            $eventArgs.Handled = $true
        })
    }
    else {
        $border.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            if ($CategoryDragDidStart) {
                $Script:CategoryDragDidStart = $false
                $Script:CategoryDragStartPoint = $null
                $eventArgs.Handled = $true
                return
            }
            $Script:CurrentCategory = [string]$sender.Tag
            Clear-Selection
            Render-Library -Reload:$false -RefreshMetadata:$false
            $eventArgs.Handled = $true
        })

        if (-not $IsSystem) {
            $border.AllowDrop = $true
            $border.Add_PreviewMouseLeftButtonDown({
                param($sender, $eventArgs)
                $Script:CategoryDragStartPoint = $eventArgs.GetPosition($Window)
                $Script:CategoryDragDidStart = $false
            })
            $border.Add_MouseMove({
                param($sender, $eventArgs)
                if ($eventArgs.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
                    return
                }
                if ($null -eq $CategoryDragStartPoint) {
                    return
                }

                $position = $eventArgs.GetPosition($Window)
                $dx = [Math]::Abs($position.X - $CategoryDragStartPoint.X)
                $dy = [Math]::Abs($position.Y - $CategoryDragStartPoint.Y)
                if ($dx -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -and $dy -lt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
                    return
                }

                $data = New-Object System.Windows.DataObject
                $data.SetData($CategoryDragFormat, [string]$sender.Tag)
                $Script:CategoryDragDidStart = $true
                [System.Windows.DragDrop]::DoDragDrop($sender, $data, [System.Windows.DragDropEffects]::Move) | Out-Null
                $eventArgs.Handled = $true
            })
            $border.Add_DragOver({
                param($sender, $eventArgs)
                Invoke-CategoryDragAutoScroll -EventArgs $eventArgs
                if ($eventArgs.Data.GetDataPresent($CategoryDragFormat)) {
                    $source = [string]$eventArgs.Data.GetData($CategoryDragFormat)
                    $target = [string]$sender.Tag
                    if (-not [string]::IsNullOrWhiteSpace($source) -and $source -ne $target) {
                        $eventArgs.Effects = [System.Windows.DragDropEffects]::Move
                    }
                    else {
                        $eventArgs.Effects = [System.Windows.DragDropEffects]::None
                    }
                }
                else {
                    $eventArgs.Effects = [System.Windows.DragDropEffects]::None
                }
                $eventArgs.Handled = $true
            })
            $border.Add_Drop({
                param($sender, $eventArgs)
                if ($eventArgs.Data.GetDataPresent($CategoryDragFormat)) {
                    $source = [string]$eventArgs.Data.GetData($CategoryDragFormat)
                    $target = [string]$sender.Tag
                    Merge-Category -SourceCategory $source -TargetCategory $target
                    $eventArgs.Handled = $true
                }
            })
            $border.Add_MouseRightButtonUp({
                param($sender, $eventArgs)
                $menu = New-Object System.Windows.Controls.ContextMenu
                $rename = New-Object System.Windows.Controls.MenuItem
                $rename.Header = "重命名分类"
                $rename.Tag = [string]$sender.Tag
                $rename.Add_Click({
                    param($menuSender, $menuEventArgs)
                    Rename-Category -Category ([string]$menuSender.Tag)
                })

                $delete = New-Object System.Windows.Controls.MenuItem
                $delete.Header = "删除分类"
                $delete.Tag = [string]$sender.Tag
                $delete.Add_Click({
                    param($menuSender, $menuEventArgs)
                    Delete-Category -Category ([string]$menuSender.Tag)
                })
                $blacklist = New-Object System.Windows.Controls.MenuItem
                $blacklist.Header = "加入黑名单"
                $blacklist.Tag = [string]$sender.Tag
                $blacklist.Add_Click({
                    param($menuSender, $menuEventArgs)
                    Blacklist-Category -Category ([string]$menuSender.Tag)
                })
                $menu.Items.Add($rename) | Out-Null
                $menu.Items.Add($blacklist) | Out-Null
                $menu.Items.Add($delete) | Out-Null
                $sender.ContextMenu = $menu
                $menu.IsOpen = $true
                $eventArgs.Handled = $true
            })
        }
    }

    return $border
}

function Add-CategoryCount([hashtable]$Counts, [string]$Category) {
    if ([string]::IsNullOrWhiteSpace($Category)) {
        return
    }

    if (-not $Counts.ContainsKey($Category)) {
        $Counts[$Category] = 0
    }
    $Counts[$Category] = [int]$Counts[$Category] + 1
}

function Add-CategoryIndexedItem([hashtable]$ItemsByCategory, [string]$Category, $Item) {
    if ([string]::IsNullOrWhiteSpace($Category) -or $null -eq $Item) {
        return
    }

    if (-not $ItemsByCategory.ContainsKey($Category)) {
        $ItemsByCategory[$Category] = New-Object 'System.Collections.Generic.List[object]'
    }
    $ItemsByCategory[$Category].Add($Item) | Out-Null
}

function Mark-ShelfMetadataDirty {
    $Script:ShelfMetadataDirty = $true
}

function Rebuild-CategoryCountCache {
    $counts = @{}
    $itemsByCategory = @{}
    $visibleItems = @($AllLibraryItems | Where-Object { -not (Item-IsPendingRemoval $_) })
    $counts["全部"] = $visibleItems.Count
    $counts["未分类"] = 0
    $counts[$DuplicateCategory] = 0

    foreach ($item in $visibleItems) {
        Add-CategoryIndexedItem -ItemsByCategory $itemsByCategory -Category "全部" -Item $item

        if (Item-IsDuplicateResult $item) {
            $counts[$DuplicateCategory] = [int]$counts[$DuplicateCategory] + 1
            Add-CategoryIndexedItem -ItemsByCategory $itemsByCategory -Category $DuplicateCategory -Item $item
        }

        $categories = @(Get-ItemCategories $item)
        if ($categories.Count -eq 0 -and
            -not (Item-HasCategory $item $RecognizingCategory) -and
            -not (Item-HasCategory $item $PendingCategory) -and
            -not (Item-HasCategory $item $NeedPasswordCategory) -and
            -not (Item-HasCategory $item $TagNotFoundCategory)) {
            $counts["未分类"] = [int]$counts["未分类"] + 1
            Add-CategoryIndexedItem -ItemsByCategory $itemsByCategory -Category "未分类" -Item $item
        }

        foreach ($category in @(Get-DisplayCategories $item)) {
            $categoryName = [string]$category
            if ($categoryName -eq "未分类") {
                continue
            }
            Add-CategoryCount -Counts $counts -Category $categoryName
            Add-CategoryIndexedItem -ItemsByCategory $itemsByCategory -Category $categoryName -Item $item
        }
    }

    $Script:CategoryCountByName = $counts
    $Script:CategoryItemsByName = $itemsByCategory
    $Script:ShelfMetadataDirty = $false
}

function Update-CategoryCountLabels {
    foreach ($category in @($CategoryButtons.Keys)) {
        if ([string]$category -eq "__add__") {
            continue
        }

        $button = $CategoryButtons[$category]
        if ($null -eq $button -or $null -eq $button.Child) {
            continue
        }

        $button.Child.Text = "$category ($(Get-CategoryCount ([string]$category)))"
    }
}

function Decrement-CategoryCount {
    param(
        [string]$Category,

        [int]$Amount = 1
    )

    if ([string]::IsNullOrWhiteSpace($Category) -or $Amount -le 0) {
        return
    }

    if (-not $CategoryCountByName.ContainsKey($Category)) {
        $CategoryCountByName[$Category] = 0
        return
    }

    $CategoryCountByName[$Category] = [Math]::Max(0, [int]$CategoryCountByName[$Category] - $Amount)
}

function Update-CategoryCountsForRemovedItems {
    param(
        $RemovedItems
    )

    $removed = @($RemovedItems | ForEach-Object { $_ })
    if ($removed.Count -eq 0) {
        return
    }

    Decrement-CategoryCount -Category "全部" -Amount $removed.Count
    foreach ($item in $removed) {
        if (Item-IsDuplicateResult $item) {
            Decrement-CategoryCount -Category $DuplicateCategory
        }

        $categories = @(Get-ItemCategories $item)
        if ($categories.Count -eq 0 -and
            -not (Item-HasCategory $item $RecognizingCategory) -and
            -not (Item-HasCategory $item $PendingCategory) -and
            -not (Item-HasCategory $item $NeedPasswordCategory) -and
            -not (Item-HasCategory $item $TagNotFoundCategory)) {
            Decrement-CategoryCount -Category "未分类"
        }

        foreach ($category in @(Get-DisplayCategories $item)) {
            $categoryName = ([string]$category).Trim()
            if ([string]::IsNullOrWhiteSpace($categoryName) -or $categoryName -eq "未分类") {
                continue
            }
            Decrement-CategoryCount -Category $categoryName
        }
    }

    Update-CategoryCountLabels
}

function Get-CategoryCount([string]$Category) {
    if ($CategoryCountByName.ContainsKey($Category)) {
        return [int]$CategoryCountByName[$Category]
    }
    return 0
}

function Render-Categories {
    $CategoryPanel.Children.Clear()
    $Script:CategoryButtons = @{}

    $manageButton = New-SidebarActionButton -Text "分类管理" -ClickAction { Show-CategoryManagerWindow }
    $tagManageButton = New-SidebarActionButton -Text "Tag管理" -ClickAction { Show-TagMappingManagerWindow }
    $CategoryPanel.Children.Add($manageButton) | Out-Null
    $CategoryPanel.Children.Add($tagManageButton) | Out-Null

    $systemCategories = @("全部", "未分类", $FavoriteCategory, $RecognizingCategory, $PendingCategory, $NeedPasswordCategory, $TagNotFoundCategory, $DuplicateCategory)
    foreach ($category in $systemCategories) {
        $button = New-CategoryButton -Category $category -IsSystem $true -Count (Get-CategoryCount $category)
        $CategoryPanel.Children.Add($button) | Out-Null
        $Script:CategoryButtons[$category] = $button
    }

    $separator = New-Object System.Windows.Controls.Border
    $separator.Height = 1
    $separator.Margin = New-Object System.Windows.Thickness -ArgumentList 2, 12, 2, 10
    $separator.Background = New-SolidBrush "#2A2E37"
    $CategoryPanel.Children.Add($separator) | Out-Null

    foreach ($category in $LibraryCategories) {
        $categoryName = [string]$category
        $button = New-CategoryButton -Category $categoryName -Count (Get-CategoryCount $categoryName)
        $CategoryPanel.Children.Add($button) | Out-Null
        $Script:CategoryButtons[[string]$category] = $button
    }

    $addButton = New-CategoryButton -Category "__add__" -IsAddButton $true
    $CategoryPanel.Children.Add($addButton) | Out-Null
}

function Update-CategorySelectionVisuals {
    foreach ($category in @($CategoryButtons.Keys)) {
        if ([string]$category -eq "__add__") {
            continue
        }

        $button = $CategoryButtons[$category]
        if ($null -eq $button) {
            continue
        }

        $button.Background = if ([string]$category -eq [string]$CurrentCategory) { $BrushSidebarItemSelected } else { $BrushSidebarItem }
    }
}

function Get-CurrentCategoryItems {
    if ($CategoryItemsByName.ContainsKey($CurrentCategory)) {
        return @($CategoryItemsByName[$CurrentCategory].ToArray())
    }

    return @()
}

function Get-ItemIndexById([string]$ItemId) {
    for ($i = 0; $i -lt $LibraryItems.Count; $i++) {
        if ([string]$LibraryItems[$i].id -eq $ItemId) {
            return $i
        }
    }
    return -1
}

function Get-LibraryItemById([string]$ItemId) {
    foreach ($item in $LibraryItems) {
        if ([string]$item.id -eq $ItemId) {
            return $item
        }
    }
    return $null
}

function Find-LibraryItemById($Library, [string]$ItemId) {
    if ($null -eq $Library -or $null -eq $Library.items) {
        return $null
    }

    foreach ($item in @($Library.items)) {
        if ([string]$item.id -eq $ItemId) {
            return $item
        }
    }
    return $null
}

function Get-CurrentFavoriteState([string]$ItemId) {
    $library = Get-LibraryData
    $item = Find-LibraryItemById $library $ItemId
    if ($null -eq $item) {
        return $false
    }
    return (Item-HasCategory $item $FavoriteCategory)
}

function Update-SelectionVisuals {
    Ensure-SelectedIdsHashSet

    foreach ($itemId in $CardById.Keys) {
        $parts = $CardById[$itemId]
        if ($SelectedIds.Contains([string]$itemId)) {
            $parts.Root.Background = $BrushSelectedBack
            $parts.Root.BorderBrush = $BrushAccent
        }
        else {
            $parts.Root.Background = $BrushTransparent
            $parts.Root.BorderBrush = $BrushTransparent
        }
    }
}

function Request-SelectionVisualUpdate {
    if ($SelectionVisualUpdatePending) {
        return
    }

    $Script:SelectionVisualUpdatePending = $true
    $Window.Dispatcher.BeginInvoke(
        [Action]{
            $Script:SelectionVisualUpdatePending = $false
            Update-SelectionVisuals
        },
        [System.Windows.Threading.DispatcherPriority]::Background
    ) | Out-Null
}

function Clear-Selection {
    Ensure-SelectedIdsHashSet

    $SelectedIds.Clear()
    $Script:LastSelectedIndex = -1
    Update-SelectionVisuals
}

function Select-AllComics {
    $nextSelectedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in $LibraryItems) {
        $nextSelectedIds.Add([string]$item.id) | Out-Null
    }
    $Script:SelectedIds = $nextSelectedIds
    if ($LibraryItems.Count -gt 0) {
        $Script:LastSelectedIndex = $LibraryItems.Count - 1
    }
    Update-SelectionVisuals
}

function Select-Comic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemId,

        [bool]$Ctrl = $false,

        [bool]$Shift = $false
    )

    $index = Get-ItemIndexById $ItemId
    if ($index -lt 0) {
        return
    }

    Ensure-SelectedIdsHashSet

    if ($Shift -and $LastSelectedIndex -ge 0) {
        if (-not $Ctrl) {
            $SelectedIds.Clear()
        }

        $start = [Math]::Min($LastSelectedIndex, $index)
        $end = [Math]::Max($LastSelectedIndex, $index)
        for ($i = $start; $i -le $end; $i++) {
            $SelectedIds.Add([string]$LibraryItems[$i].id) | Out-Null
        }
    }
    elseif ($Ctrl) {
        if ($SelectedIds.Contains($ItemId)) {
            $SelectedIds.Remove($ItemId) | Out-Null
        }
        else {
            $SelectedIds.Add($ItemId) | Out-Null
        }
        $Script:LastSelectedIndex = $index
    }
    else {
        $SelectedIds.Clear()
        $SelectedIds.Add($ItemId) | Out-Null
        $Script:LastSelectedIndex = $index
    }

    Update-SelectionVisuals
}

function Is-ShelfInteractiveElement($Source) {
    $current = $Source
    while ($null -ne $current -and $current -ne $ScrollViewer) {
        if ($current -is [System.Windows.FrameworkElement]) {
            if ($current.Cursor -eq [System.Windows.Input.Cursors]::Hand) {
                return $true
            }
        }

        if ($current -is [System.Windows.Controls.Primitives.ScrollBar] -or
            $current -is [System.Windows.Controls.Primitives.Thumb] -or
            $current -is [System.Windows.Controls.Primitives.RepeatButton] -or
            $current -is [System.Windows.Controls.Primitives.ButtonBase] -or
            $current -is [System.Windows.Controls.Primitives.TextBoxBase]) {
            return $true
        }

        if ($current -isnot [System.Windows.DependencyObject]) {
            break
        }

        try {
            $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
        }
        catch {
            break
        }
    }
    return $false
}

function New-ShelfSelectionRect {
    param(
        [System.Windows.Point]$StartPoint,
        [System.Windows.Point]$EndPoint
    )

    $x = [Math]::Min([double]$StartPoint.X, [double]$EndPoint.X)
    $y = [Math]::Min([double]$StartPoint.Y, [double]$EndPoint.Y)
    $width = [Math]::Abs([double]$EndPoint.X - [double]$StartPoint.X)
    $height = [Math]::Abs([double]$EndPoint.Y - [double]$StartPoint.Y)
    return (New-Object System.Windows.Rect -ArgumentList $x, $y, $width, $height)
}

function Test-RectIntersects {
    param(
        [System.Windows.Rect]$Left,
        [System.Windows.Rect]$Right
    )

    if ($Left.Width -le 0 -or $Left.Height -le 0 -or $Right.Width -le 0 -or $Right.Height -le 0) {
        return $false
    }

    return (
        $Left.Left -lt $Right.Right -and
        $Left.Right -gt $Right.Left -and
        $Left.Top -lt $Right.Bottom -and
        $Left.Bottom -gt $Right.Top
    )
}

function Set-ShelfSelectionBoxRect {
    param(
        [System.Windows.Rect]$Rect
    )

    $ShelfSelectionBox.Margin = New-Object System.Windows.Thickness -ArgumentList $Rect.X, $Rect.Y, 0, 0
    $ShelfSelectionBox.Width = [Math]::Max(1.0, [double]$Rect.Width)
    $ShelfSelectionBox.Height = [Math]::Max(1.0, [double]$Rect.Height)
    $ShelfSelectionBox.Visibility = "Visible"
}

function Hide-ShelfSelectionBox {
    $ShelfSelectionBox.Visibility = "Collapsed"
    $ShelfSelectionBox.Width = 0
    $ShelfSelectionBox.Height = 0
}

function Update-ShelfDragSelection {
    if (-not $ShelfDragSelectActive -or $null -eq $ShelfDragSelectStartPoint -or $null -eq $ShelfDragSelectLastPoint) {
        return
    }

    $selectionRect = New-ShelfSelectionRect -StartPoint $ShelfDragSelectStartPoint -EndPoint $ShelfDragSelectLastPoint
    Set-ShelfSelectionBoxRect -Rect $selectionRect

    $nextSelectedIds = New-SelectedIdSet -Ids @($ShelfDragSelectBaseIds)
    $lastHitIndex = -1
    $cardRectSource = New-Object System.Windows.Rect -ArgumentList 0, 0, 0, 0

    foreach ($itemId in @($CardById.Keys)) {
        $parts = $CardById[$itemId]
        if ($null -eq $parts -or $null -eq $parts.Root) {
            continue
        }
        if (-not $parts.Root.IsVisible) {
            continue
        }

        $width = [double]$parts.Root.ActualWidth
        $height = [double]$parts.Root.ActualHeight
        if ($width -le 0 -or $height -le 0) {
            continue
        }

        try {
            $cardRectSource = New-Object System.Windows.Rect -ArgumentList 0, 0, $width, $height
            $cardRect = $parts.Root.TransformToAncestor($ShelfSelectionHost).TransformBounds($cardRectSource)
        }
        catch {
            continue
        }

        if (Test-RectIntersects -Left $selectionRect -Right $cardRect) {
            $nextSelectedIds.Add([string]$itemId) | Out-Null
            $itemIndex = Get-ItemIndexById ([string]$itemId)
            if ($itemIndex -gt $lastHitIndex) {
                $lastHitIndex = $itemIndex
            }
        }
    }

    $Script:SelectedIds = $nextSelectedIds
    if ($lastHitIndex -ge 0) {
        $Script:LastSelectedIndex = $lastHitIndex
    }
    Update-SelectionVisuals
}

function Invoke-ShelfDragSelectionAutoScroll {
    if (-not $ShelfDragSelectActive -or $null -eq $ShelfDragSelectLastPoint) {
        return
    }

    $height = [double]$ShelfSelectionHost.ActualHeight
    $scrollableHeight = [double]$ShelfScrollViewer.ScrollableHeight
    if ($height -le 0 -or $scrollableHeight -le 0) {
        return
    }

    $point = $ShelfDragSelectLastPoint
    $edge = [Math]::Min(72.0, [Math]::Max(36.0, $height * 0.16))
    $offset = [double]$ShelfScrollViewer.VerticalOffset
    $targetOffset = $offset

    if ($point.Y -lt $edge) {
        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, ($edge - $point.Y) / $edge))
        $targetOffset = [Math]::Max(0.0, $offset - (10.0 + (42.0 * $ratio)))
    }
    elseif ($point.Y -gt ($height - $edge)) {
        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, ($point.Y - ($height - $edge)) / $edge))
        $targetOffset = [Math]::Min($scrollableHeight, $offset + (10.0 + (42.0 * $ratio)))
    }

    if ([Math]::Abs($targetOffset - $offset) -gt 0.1) {
        $ShelfScrollViewer.ScrollToVerticalOffset($targetOffset)
        Update-ShelfDragSelection
    }
}

function Reset-ShelfDragSelection {
    $Script:ShelfDragSelectArmed = $false
    $Script:ShelfDragSelectActive = $false
    $Script:ShelfDragSelectStartPoint = $null
    $Script:ShelfDragSelectLastPoint = $null
    $Script:ShelfDragSelectAppend = $false
    $Script:ShelfDragSelectBaseIds = New-SelectedIdSet
    Hide-ShelfSelectionBox
    if ($ShelfDragSelectTimer) {
        $ShelfDragSelectTimer.Stop()
    }
    if ($ShelfScrollViewer.IsMouseCaptured) {
        $ShelfScrollViewer.ReleaseMouseCapture()
    }
}

function Get-TitleCandidates($Item) {
    if ($null -eq $Item -or $null -eq $Item.titleCandidates) {
        return @()
    }

    $candidates = @()
    foreach ($candidate in @($Item.titleCandidates)) {
        $name = ""
        $pageLabel = ""

        if ($candidate -is [string]) {
            $name = [string]$candidate
        }
        elseif ($null -ne $candidate.PSObject.Properties["name"]) {
            $name = [string]$candidate.name
            if ($null -ne $candidate.PSObject.Properties["pageLabel"]) {
                $pageLabel = [string]$candidate.pageLabel
            }
        }

        $name = $name.Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $candidates += [pscustomobject]@{
                Name = $name
                PageLabel = $pageLabel
            }
        }
    }

    return $candidates
}

function Select-TitleCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemId,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($ItemId) -or [string]::IsNullOrWhiteSpace($Name)) {
        return
    }

    $result = Invoke-ScannerJson -Arguments @($ScannerPath, "select-title", "--data-dir", $DataDir, "--id", $ItemId, "--name", $Name) -ErrorCaption "选择作品名失败"
    if ($null -eq $result) {
        return
    }

    Render-Library
}

function New-ComicCategoryOverlay {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $categoryOverlay = New-Object System.Windows.Controls.Border
    $categoryOverlay.HorizontalAlignment = "Stretch"
    $categoryOverlay.VerticalAlignment = "Bottom"
    $categoryOverlay.MaxHeight = 96
    $categoryOverlay.Padding = New-Object System.Windows.Thickness -ArgumentList 8, 6, 8, 6
    $categoryOverlay.Background = New-SolidBrush "#B0111316"
    $categoryOverlay.Visibility = "Collapsed"

    $categoryText = New-Object System.Windows.Controls.TextBlock
    $categoryText.Text = $Text
    $categoryText.Foreground = $BrushText
    $categoryText.FontSize = 12
    $categoryText.LineHeight = 16
    $categoryText.TextWrapping = "Wrap"
    $categoryText.TextTrimming = "CharacterEllipsis"
    $categoryOverlay.Child = $categoryText

    [System.Windows.Controls.Panel]::SetZIndex($categoryOverlay, 1)
    return $categoryOverlay
}

function Ensure-ComicCategoryOverlay($Parts) {
    if ($null -eq $Parts -or $null -eq $Parts.CoverGrid) {
        return $null
    }
    if ($Parts.CategoryOverlay) {
        return $Parts.CategoryOverlay
    }

    $overlay = New-ComicCategoryOverlay -Text ([string]$Parts.CategoryText)
    if ($null -eq $overlay) {
        return $null
    }

    $Parts.CategoryOverlay = $overlay
    $Parts.CoverGrid.Children.Add($overlay) | Out-Null
    return $overlay
}

function New-ComicCard($Item) {
    $itemId = [string]$Item.id

    $outer = New-Object System.Windows.Controls.Border
    $outer.Width = 176
    $outer.Height = 288
    $outer.Margin = New-Object System.Windows.Thickness -ArgumentList 0
    $outer.Background = $BrushTransparent
    $outer.BorderBrush = $BrushTransparent
    $outer.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 2
    $outer.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 8
    $outer.Cursor = [System.Windows.Input.Cursors]::Hand
    $outer.Tag = $itemId

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Width = 172
    $stack.Height = 284
    $stack.Margin = New-Object System.Windows.Thickness -ArgumentList 0

    $coverBorder = New-Object System.Windows.Controls.Border
    $coverBorder.Width = 160
    $coverBorder.Height = 228
    $coverBorder.Margin = New-Object System.Windows.Thickness -ArgumentList 6, 4, 6, 0
    $coverBorder.Background = $BrushCover
    $coverBorder.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 6
    $coverBorder.SnapsToDevicePixels = $true
    $coverBorder.ClipToBounds = $true

    $coverGrid = New-Object System.Windows.Controls.Grid
    $coverGrid.Children.Add((New-CoverImage (Resolve-CoverPath $Item))) | Out-Null

    if ([bool]$Item.requiresPassword -and [string]::IsNullOrWhiteSpace([string]$Item.cover)) {
        $passwordHint = New-Object System.Windows.Controls.TextBlock
        $passwordHint.Text = "需要密码"
        $passwordHint.Foreground = $BrushAccent
        $passwordHint.FontSize = 18
        $passwordHint.FontWeight = "SemiBold"
        $passwordHint.HorizontalAlignment = "Center"
        $passwordHint.VerticalAlignment = "Center"
        $passwordHint.TextAlignment = "Center"
        [System.Windows.Controls.Panel]::SetZIndex($passwordHint, 1)
        $coverGrid.Children.Add($passwordHint) | Out-Null
    }

    $categoryOverlay = $null
    $categoryTextValue = (@(Get-DisplayCategories $Item) -join "、")

    $pageCount = 0
    if ($null -ne $Item.pageCount) {
        [int]::TryParse([string]$Item.pageCount, [ref]$pageCount) | Out-Null
    }

    if ($pageCount -gt 0) {
        $pageBadge = New-Object System.Windows.Controls.Border
        $pageBadge.HorizontalAlignment = "Right"
        $pageBadge.VerticalAlignment = "Bottom"
        $pageBadge.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 6, 6
        $pageBadge.Padding = New-Object System.Windows.Thickness -ArgumentList 6, 2, 6, 2
        $pageBadge.Background = $BrushBadge
        $pageBadge.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 5

        $pageBadgeText = New-Object System.Windows.Controls.TextBlock
        $pageBadgeText.Text = "$pageCount 页"
        $pageBadgeText.Foreground = $BrushText
        $pageBadgeText.FontSize = 12
        $pageBadgeText.FontWeight = "SemiBold"
        $pageBadgeText.TextAlignment = "Center"
        $pageBadge.Child = $pageBadgeText

        [System.Windows.Controls.Panel]::SetZIndex($pageBadge, 2)
        $coverGrid.Children.Add($pageBadge) | Out-Null
    }

    if ([bool]$Item.isVersionGroup) {
        $versionCount = 0
        [int]::TryParse([string]$Item.versionCount, [ref]$versionCount) | Out-Null
        if ($versionCount -gt 1) {
            $versionBadge = New-Object System.Windows.Controls.Border
            $versionBadge.HorizontalAlignment = "Right"
            $versionBadge.VerticalAlignment = "Top"
            $versionBadge.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 6, 6, 0
            $versionBadge.Padding = New-Object System.Windows.Thickness -ArgumentList 6, 2, 6, 2
            $versionBadge.Background = $BrushAccent
            $versionBadge.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 5

            $versionBadgeText = New-Object System.Windows.Controls.TextBlock
            $groupLabel = ([string]$Item.versionGroupLabel).Trim()
            if ([string]::IsNullOrWhiteSpace($groupLabel)) {
                $groupLabel = "版本"
            }
            $versionBadgeText.Text = "$versionCount $groupLabel"
            $versionBadgeText.Foreground = $BrushWindow
            $versionBadgeText.FontSize = 12
            $versionBadgeText.FontWeight = "SemiBold"
            $versionBadgeText.TextAlignment = "Center"
            $versionBadge.Child = $versionBadgeText

            [System.Windows.Controls.Panel]::SetZIndex($versionBadge, 2)
            $coverGrid.Children.Add($versionBadge) | Out-Null
        }
    }

    $titleCandidates = @(Get-TitleCandidates $Item)
    $selectButton = $null
    if ($CurrentCategory -eq $PendingCategory -and $titleCandidates.Count -gt 0) {
        $selectButton = New-Object System.Windows.Controls.Button
        $selectButton.Width = 58
        $selectButton.Height = 24
        $selectButton.HorizontalAlignment = "Left"
        $selectButton.VerticalAlignment = "Top"
        $selectButton.Margin = New-Object System.Windows.Thickness -ArgumentList 6, 6, 0, 0
        $selectButton.Padding = New-Object System.Windows.Thickness -ArgumentList 0
        $selectButton.FontSize = 12
        $selectButton.FontWeight = "SemiBold"
        $selectButton.Cursor = [System.Windows.Input.Cursors]::Hand
        $isClassified = -not [string]::IsNullOrWhiteSpace([string]$Item.tagClassifiedAt)
        $selectButton.Content = if ($isClassified) { "已分类" } elseif ([bool]$Item.titleSelected) { "已选择" } else { "未选择" }
        $selectButton.Foreground = if ($isClassified -or [bool]$Item.titleSelected) { $BrushText } else { $BrushWindow }
        $selectButton.Background = if ($isClassified) { $BrushAccent } elseif ([bool]$Item.titleSelected) { $BrushSidebarItemSelected } else { $BrushAccent }
        $selectButton.BorderBrush = $BrushTransparent
        $selectButton.Tag = $itemId
        $selectButton.Visibility = "Visible"

        $candidateMenu = New-Object System.Windows.Controls.ContextMenu
        foreach ($candidate in $titleCandidates) {
            $candidateName = [string]$candidate.Name
            if ([string]::IsNullOrWhiteSpace($candidateName)) {
                continue
            }

            $candidateItem = New-Object System.Windows.Controls.MenuItem
            $candidateItem.Header = if ([string]::IsNullOrWhiteSpace([string]$candidate.PageLabel)) { $candidateName } else { "$candidateName  $($candidate.PageLabel)" }
            $candidateItem.Tag = [pscustomobject]@{
                ItemId = $itemId
                Name = $candidateName
            }
            $candidateItem.Add_Click({
                param($sender, $eventArgs)
                $tag = $sender.Tag
                Select-TitleCandidate -ItemId ([string]$tag.ItemId) -Name ([string]$tag.Name)
                $eventArgs.Handled = $true
            })
            $candidateMenu.Items.Add($candidateItem) | Out-Null
        }

        $selectButton.ContextMenu = $candidateMenu
        $selectButton.Add_Click({
            param($sender, $eventArgs)
            if ($sender.ContextMenu) {
                $sender.ContextMenu.PlacementTarget = $sender
                $sender.ContextMenu.IsOpen = $true
            }
            $eventArgs.Handled = $true
        })
        [System.Windows.Controls.Panel]::SetZIndex($selectButton, 3)
        $coverGrid.Children.Add($selectButton) | Out-Null
    }

    $coverBorder.Child = $coverGrid

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = [string]$Item.name
    $title.Foreground = $BrushText
    $title.FontSize = 13
    $title.LineHeight = 17
    $title.TextWrapping = "Wrap"
    $title.TextAlignment = "Center"
    $title.Width = 160
    $title.Height = 42
    $title.Margin = New-Object System.Windows.Thickness -ArgumentList 6, 8, 6, 0
    $title.TextTrimming = "CharacterEllipsis"

    $stack.Children.Add($coverBorder) | Out-Null
    $stack.Children.Add($title) | Out-Null
    $outer.Child = $stack

    $outer.Add_MouseEnter({
        param($sender, $eventArgs)

        $parts = $Script:CardById[[string]$sender.Tag]
        $overlay = Ensure-ComicCategoryOverlay $parts
        if ($overlay) {
            $overlay.Visibility = "Visible"
        }
    })

    $outer.Add_MouseLeave({
        param($sender, $eventArgs)

        $parts = $Script:CardById[[string]$sender.Tag]
        if ($parts -and $parts.CategoryOverlay) {
            $parts.CategoryOverlay.Visibility = "Collapsed"
        }
    })

    $outer.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)

        $id = [string]$sender.Tag
        if ($eventArgs.ClickCount -ge 2) {
            Select-Comic -ItemId $id
            Open-Reader -ItemId $id
            $eventArgs.Handled = $true
            return
        }

        $mods = [System.Windows.Input.Keyboard]::Modifiers
        $ctrl = (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0)
        $shift = (($mods -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0)
        Select-Comic -ItemId $id -Ctrl $ctrl -Shift $shift
        $eventArgs.Handled = $true
    })

    $outer.Add_MouseRightButtonUp({
        param($sender, $eventArgs)

        $id = [string]$sender.Tag
        if (-not $SelectedIds.Contains($id)) {
            Select-Comic -ItemId $id
        }
        Show-ComicMenu -Target $sender
        $eventArgs.Handled = $true
    })

    $Script:CardById[$itemId] = [pscustomobject]@{
        Root = $outer
        Cover = $coverBorder
        CoverGrid = $coverGrid
        Title = $title
        CategoryOverlay = $categoryOverlay
        CategoryText = $categoryTextValue
        TitleSelectButton = $selectButton
    }

    return $outer
}

function Update-ComicCardForCategory($Parts) {
    if ($null -eq $Parts) {
        return
    }

    if ($Parts.TitleSelectButton) {
        $Parts.TitleSelectButton.Visibility = if ($CurrentCategory -eq $PendingCategory) { "Visible" } else { "Collapsed" }
    }
}

function Show-AddMenu([System.Windows.Controls.Border]$Target) {
    $menu = New-Object System.Windows.Controls.ContextMenu

    $addArchive = New-Object System.Windows.Controls.MenuItem
    $addArchive.Header = "添加压缩包"
    $addArchive.Add_Click({
        param($sender, $eventArgs)
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "选择漫画压缩包"
        $dialog.Filter = "漫画压缩包 (*.zip;*.rar;*.7z)|*.zip;*.rar;*.7z|所有文件 (*.*)|*.*"
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog($Window) -eq $true) {
            Add-Paths -Paths ([string[]]$dialog.FileNames)
        }
    })

    $addFolder = New-Object System.Windows.Controls.MenuItem
    $addFolder.Header = "添加文件夹"
    $addFolder.Add_Click({
        param($sender, $eventArgs)
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "选择漫画文件夹"
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Add-Paths -Paths @($dialog.SelectedPath)
        }
    })

    $menu.Items.Add($addArchive) | Out-Null
    $menu.Items.Add($addFolder) | Out-Null
    $Target.ContextMenu = $menu
    $menu.IsOpen = $true
}

function New-AddCard {
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Width = 176
    $stack.Height = 288
    $stack.Margin = New-Object System.Windows.Thickness -ArgumentList 0

    $border = New-Object System.Windows.Controls.Border
    $border.Width = 160
    $border.Height = 228
    $border.Margin = New-Object System.Windows.Thickness -ArgumentList 8, 6, 8, 0
    $border.Background = $BrushCard
    $border.BorderBrush = $BrushMuted
    $border.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 1
    $border.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 6
    $border.Cursor = [System.Windows.Input.Cursors]::Hand

    $plus = New-Object System.Windows.Controls.TextBlock
    $plus.Text = "+"
    $plus.Foreground = $BrushAccent
    $plus.FontSize = 58
    $plus.FontWeight = "Light"
    $plus.HorizontalAlignment = "Center"
    $plus.VerticalAlignment = "Center"
    $plus.TextAlignment = "Center"
    $border.Child = $plus

    $border.Add_MouseEnter({
        param($sender, $eventArgs)
        $sender.Background = $BrushCardHover
    })
    $border.Add_MouseLeave({
        param($sender, $eventArgs)
        $sender.Background = $BrushCard
    })
    $border.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        Show-AddMenu $sender
    })

    $spacer = New-Object System.Windows.Controls.TextBlock
    $spacer.Text = ""
    $spacer.Width = 160
    $spacer.Height = 42
    $spacer.Margin = New-Object System.Windows.Thickness -ArgumentList 8, 8, 8, 0

    $stack.Children.Add($border) | Out-Null
    $stack.Children.Add($spacer) | Out-Null

    return $stack
}

function Get-ShelfColumnCount {
    $width = [double]$ShelfScrollViewer.ViewportWidth
    if ($width -le 0) {
        $width = [double]$ShelfScrollViewer.ActualWidth
    }
    if ($width -le 0) {
        $width = [Math]::Max($CardWidth, [double]$Window.ActualWidth - 520)
    }

    $available = [Math]::Max($CardWidth, $width - 24)
    return [Math]::Max(1, [int][Math]::Floor($available / $CardWidth))
}

function Should-ShowShelfAddCard {
    return -not (
        $CurrentCategory -eq $RecognizingCategory -or
        $CurrentCategory -eq $PendingCategory -or
        $CurrentCategory -eq $NeedPasswordCategory -or
        $CurrentCategory -eq $TagNotFoundCategory -or
        $CurrentCategory -eq $DuplicateCategory
    )
}

function Get-ShelfVirtualCount {
    $itemCount = @($LibraryItems).Count
    if (Should-ShowShelfAddCard) {
        return ($itemCount + 1)
    }
    return $itemCount
}

function Get-ShelfRowCount {
    param(
        [int]$Count,
        [int]$Columns,
        [bool]$AtLeastOne = $false
    )

    if ($Count -le 0) {
        if ($AtLeastOne) {
            return 1
        }
        return 0
    }
    return [int][Math]::Ceiling([double]$Count / [double][Math]::Max(1, $Columns))
}

function New-ShelfPlaceholder {
    $placeholder = New-Object System.Windows.Controls.Border
    $placeholder.Width = $CardWidth
    $placeholder.Height = $CardHeight
    $placeholder.Opacity = 0
    $placeholder.IsHitTestVisible = $false
    return $placeholder
}

function New-ShelfVirtualElement {
    param(
        [int]$Index
    )

    $itemCount = @($LibraryItems).Count
    if ($Index -lt $itemCount) {
        $card = New-ComicCard $LibraryItems[$Index]
        $parts = $Script:CardById[[string]$LibraryItems[$Index].id]
        Update-ComicCardForCategory $parts
        return $card
    }

    if (Should-ShowShelfAddCard) {
        return New-AddCard
    }

    return New-ShelfPlaceholder
}

function New-ShelfLoadingCard {
    param(
        [int]$Index
    )

    $outer = New-Object System.Windows.Controls.Border
    $outer.Width = $CardWidth
    $outer.Height = $CardHeight
    $outer.Background = $BrushTransparent
    $outer.BorderBrush = $BrushTransparent
    $outer.BorderThickness = New-Object System.Windows.Thickness -ArgumentList 2
    $outer.Tag = "loading:$Index"

    $cover = New-Object System.Windows.Controls.Border
    $cover.Width = 160
    $cover.Height = 228
    $cover.Margin = New-Object System.Windows.Thickness -ArgumentList 8, 6, 8, 0
    $cover.Background = $BrushCover
    $cover.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 6
    $cover.Opacity = 0.55
    $outer.Child = $cover

    return $outer
}

function Clear-ShelfBuildQueue {
    $ShelfBuildQueue.Clear()
    $ShelfQueuedBuildIndexes.Clear()
    if ($ShelfBuildTimer) {
        $ShelfBuildTimer.Stop()
    }
}

function Queue-ShelfElementBuild {
    param(
        [int]$Index
    )

    if ($ShelfQueuedBuildIndexes.Add($Index)) {
        $ShelfBuildQueue.Enqueue($Index)
    }
    if ($ShelfBuildTimer -and -not $ShelfBuildTimer.IsEnabled) {
        $ShelfBuildTimer.Start()
    }
}

function Process-ShelfBuildQueue {
    $processed = 0
    while ($ShelfBuildQueue.Count -gt 0 -and $processed -lt $ShelfBuildBatchSize) {
        $index = [int]$ShelfBuildQueue.Dequeue()
        $ShelfQueuedBuildIndexes.Remove($index) | Out-Null

        if (-not $ShelfElementByIndex.ContainsKey($index)) {
            continue
        }

        $currentElement = $ShelfElementByIndex[$index]
        if ([string]$currentElement.Tag -ne "loading:$index") {
            continue
        }

        $position = $ShelfPanel.Children.IndexOf($currentElement)
        if ($position -lt 0) {
            continue
        }

        $actualElement = New-ShelfVirtualElement -Index $index
        $ShelfPanel.Children.RemoveAt($position)
        $ShelfPanel.Children.Insert($position, $actualElement)
        $Script:ShelfElementByIndex[$index] = $actualElement
        $processed += 1
    }

    if ($ShelfBuildQueue.Count -eq 0 -and $ShelfBuildTimer) {
        $ShelfBuildTimer.Stop()
    }

    Update-SelectionVisuals
}

function Clear-ShelfPreheatQueue {
    $ShelfPreheatQueue.Clear()
    $ShelfQueuedPreheatIndexes.Clear()
    if ($ShelfPreheatTimer) {
        $ShelfPreheatTimer.Stop()
    }
}

function Queue-ShelfCoverPreheat {
    param(
        [int]$Index
    )

    $itemCount = @($LibraryItems).Count
    if ($Index -lt 0 -or $Index -ge $itemCount) {
        return
    }

    if ($ShelfQueuedPreheatIndexes.Add($Index)) {
        $ShelfPreheatQueue.Enqueue($Index)
    }

    if ($ShelfPreheatTimer -and -not $ShelfPreheatTimer.IsEnabled) {
        $ShelfPreheatTimer.Start()
    }
}

function Queue-ShelfCoverPreheatRange {
    param(
        [int]$StartIndex,
        [int]$EndIndex
    )

    $itemCount = @($LibraryItems).Count
    $start = [Math]::Max(0, $StartIndex)
    $end = [Math]::Min($itemCount, $EndIndex)
    for ($index = $start; $index -lt $end; $index++) {
        Queue-ShelfCoverPreheat -Index $index
    }
}

function Process-ShelfPreheatQueue {
    $processed = 0
    while ($ShelfPreheatQueue.Count -gt 0 -and $processed -lt $ShelfPreheatBatchSize) {
        $index = [int]$ShelfPreheatQueue.Dequeue()
        $ShelfQueuedPreheatIndexes.Remove($index) | Out-Null

        $itemCount = @($LibraryItems).Count
        if ($index -lt 0 -or $index -ge $itemCount) {
            continue
        }

        $coverPath = Resolve-CoverPath $LibraryItems[$index]
        if ($coverPath) {
            Get-CoverBitmap $coverPath | Out-Null
        }
        $processed += 1
    }

    if ($ShelfPreheatQueue.Count -eq 0 -and $ShelfPreheatTimer) {
        $ShelfPreheatTimer.Stop()
    }
}

function Add-ShelfVirtualElement {
    param(
        [int]$Index,
        [int]$InsertAt = -1,
        [bool]$Deferred = $false
    )

    if ($Deferred) {
        $element = New-ShelfLoadingCard -Index $Index
    }
    else {
        $element = New-ShelfVirtualElement -Index $Index
    }

    $Script:ShelfElementByIndex[$Index] = $element
    if ($InsertAt -ge 0 -and $InsertAt -lt $ShelfPanel.Children.Count) {
        $ShelfPanel.Children.Insert($InsertAt, $element)
    }
    else {
        $ShelfPanel.Children.Add($element) | Out-Null
    }

    if ($Deferred) {
        Queue-ShelfElementBuild -Index $Index
    }
}

function Remove-ShelfVirtualElement {
    param(
        [int]$Index
    )

    if (-not $ShelfElementByIndex.ContainsKey($Index)) {
        return
    }

    $element = $ShelfElementByIndex[$Index]
    $ShelfPanel.Children.Remove($element)
    $ShelfElementByIndex.Remove($Index)

    $itemCount = @($LibraryItems).Count
    if ($Index -lt $itemCount) {
        $itemId = [string]$LibraryItems[$Index].id
        if ($Script:CardById.ContainsKey($itemId)) {
            $Script:CardById.Remove($itemId)
        }
    }
}

function Clear-ShelfPlaceholders {
    for ($slot = 0; $slot -lt $ShelfPlaceholderCount; $slot++) {
        if ($ShelfPanel.Children.Count -gt 0) {
            $ShelfPanel.Children.RemoveAt(0)
        }
    }
    $Script:ShelfPlaceholderCount = 0
}

function Add-ShelfPlaceholders {
    param(
        [int]$Count
    )

    for ($slot = 0; $slot -lt $Count; $slot++) {
        $ShelfPanel.Children.Insert($slot, (New-ShelfPlaceholder))
    }
    $Script:ShelfPlaceholderCount = $Count
}

function Render-ShelfWindow {
    param(
        [bool]$Force = $false
    )

    if ($ShelfIsRendering) {
        return
    }

    $Script:ShelfIsRendering = $true
    try {
        $columns = Get-ShelfColumnCount
        $virtualCount = Get-ShelfVirtualCount
        $lastBatch = [Math]::Max(0, [int][Math]::Floor(([double][Math]::Max(0, $virtualCount - 1)) / [double]$ShelfBatchSize))
        $firstVisibleRow = [Math]::Max(0, [int][Math]::Floor([double]$ShelfScrollViewer.VerticalOffset / [double]$CardHeight))
        $firstVisibleIndex = [Math]::Min([Math]::Max(0, $firstVisibleRow * $columns), [Math]::Max(0, $virtualCount - 1))
        $currentBatch = [Math]::Min($lastBatch, [Math]::Max(0, [int][Math]::Floor([double]$firstVisibleIndex / [double]$ShelfBatchSize)))
        $startBatch = [Math]::Max(0, $currentBatch - $ShelfBufferBatches)
        $endBatch = [Math]::Min($lastBatch, $currentBatch + $ShelfBufferBatches)

        $rawStart = $startBatch * $ShelfBatchSize
        $rawEnd = [Math]::Min($virtualCount, (($endBatch + 1) * $ShelfBatchSize))
        $renderStart = $rawStart
        $renderEnd = $rawEnd
        Queue-ShelfCoverPreheatRange -StartIndex (($endBatch + 1) * $ShelfBatchSize) -EndIndex (($endBatch + 2) * $ShelfBatchSize)
        Queue-ShelfCoverPreheatRange -StartIndex (($startBatch - 1) * $ShelfBatchSize) -EndIndex ($startBatch * $ShelfBatchSize)

        $oldStart = $ShelfRenderStartIndex
        $oldEnd = $ShelfRenderEndIndex
        $oldColumns = $ShelfColumnCount

        if (-not $Force -and
            $renderStart -eq $ShelfRenderStartIndex -and
            $renderEnd -eq $ShelfRenderEndIndex -and
            $columns -eq $ShelfColumnCount) {
            Update-SelectionVisuals
            return
        }

        $panelWidth = [Math]::Max($CardWidth, $columns * $CardWidth)
        $ShelfPanel.Width = $panelWidth
        $ShelfTopSpacer.Width = $panelWidth
        $ShelfBottomSpacer.Width = $panelWidth

        $topRows = [int][Math]::Floor([double]$renderStart / [double]$columns)
        $startColumn = $renderStart % $columns
        $renderRows = Get-ShelfRowCount -Count ($startColumn + ($renderEnd - $renderStart)) -Columns $columns
        $totalRows = Get-ShelfRowCount -Count $virtualCount -Columns $columns -AtLeastOne $true
        $bottomRows = [Math]::Max(0, $totalRows - $topRows - $renderRows)

        $ShelfTopSpacer.Height = $topRows * $CardHeight
        $ShelfBottomSpacer.Height = $bottomRows * $CardHeight

        $hasOverlap = ($oldStart -ge 0 -and $oldEnd -gt $oldStart -and $oldStart -lt $renderEnd -and $renderStart -lt $oldEnd)
        $fullRebuild = $Force -or $oldColumns -ne $columns -or -not $hasOverlap

        if ($fullRebuild) {
            Clear-ShelfBuildQueue
            $ShelfPanel.Children.Clear()
            $Script:ShelfElementByIndex = @{}
            $Script:CardById = @{}
            $Script:ShelfPlaceholderCount = 0
            Add-ShelfPlaceholders -Count $startColumn
            for ($index = $renderStart; $index -lt $renderEnd; $index++) {
                Add-ShelfVirtualElement -Index $index -Deferred:$true
            }
        }
        else {
            Clear-ShelfPlaceholders

            foreach ($key in @($ShelfElementByIndex.Keys)) {
                $index = [int]$key
                if ($index -lt $renderStart -or $index -ge $renderEnd) {
                    Remove-ShelfVirtualElement -Index $index
                }
            }

            $prependStart = $renderStart
            $prependEnd = [Math]::Min($oldStart, $renderEnd)
            for ($index = $prependEnd - 1; $index -ge $prependStart; $index--) {
                if (-not $ShelfElementByIndex.ContainsKey($index)) {
                    Add-ShelfVirtualElement -Index $index -InsertAt 0 -Deferred:$true
                }
            }

            $appendStart = [Math]::Max($oldEnd, $renderStart)
            for ($index = $appendStart; $index -lt $renderEnd; $index++) {
                if (-not $ShelfElementByIndex.ContainsKey($index)) {
                    Add-ShelfVirtualElement -Index $index -Deferred:$true
                }
            }

            Add-ShelfPlaceholders -Count $startColumn
        }

        $Script:ShelfColumnCount = $columns
        $Script:ShelfRenderStartIndex = $renderStart
        $Script:ShelfRenderEndIndex = $renderEnd

        Update-SelectionVisuals
    }
    finally {
        $Script:ShelfIsRendering = $false
    }
}

function Refresh-CurrentLibraryItemsFromAll {
    Refresh-VersionGroupCache
    Rebuild-CategoryCountCache
    Update-CategoryCountLabels

    $filteredItems = @(Get-CurrentCategoryItems)
    if ($CurrentCategory -eq $DuplicateCategory) {
        $Script:LibraryItems = @(Apply-LibrarySort -Items $filteredItems)
    }
    else {
        $displayItems = @(Collapse-VersionGroups -Items $filteredItems)
        $Script:LibraryItems = @(Apply-LibrarySort -Items $displayItems)
    }

    $validIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in @($LibraryItems)) {
        $itemId = ([string]$item.id).Trim()
        if (-not [string]::IsNullOrWhiteSpace($itemId)) {
            $validIds.Add($itemId) | Out-Null
        }
    }

    $retainedSelectedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($selectedId in @($SelectedIds)) {
        $selectedKey = ([string]$selectedId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($selectedKey) -and $validIds.Contains($selectedKey)) {
            $retainedSelectedIds.Add($selectedKey) | Out-Null
        }
    }
    $Script:SelectedIds = $retainedSelectedIds
}

function Test-VisibleVersionGroupAffected {
    param(
        $RemovedIdSet
    )

    foreach ($item in @($LibraryItems)) {
        if (-not [bool]$item.isVersionGroup) {
            continue
        }

        foreach ($memberId in @($item.versionIds)) {
            $value = ([string]$memberId).Trim()
            if (-not [string]::IsNullOrWhiteSpace($value) -and $RemovedIdSet.Contains($value)) {
                return $true
            }
        }
    }

    return $false
}

function Remove-CurrentLibraryItemsById {
    param(
        $RemovedIdSet
    )

    $nextItems = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in @($LibraryItems)) {
        $itemId = ([string]$item.id).Trim()
        if (-not [string]::IsNullOrWhiteSpace($itemId) -and $RemovedIdSet.Contains($itemId)) {
            continue
        }
        $nextItems.Add($item) | Out-Null
    }
    $Script:LibraryItems = $nextItems.ToArray()

    $retainedSelectedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($selectedId in @($SelectedIds)) {
        $selectedKey = ([string]$selectedId).Trim()
        if ([string]::IsNullOrWhiteSpace($selectedKey) -or $RemovedIdSet.Contains($selectedKey)) {
            continue
        }
        $retainedSelectedIds.Add($selectedKey) | Out-Null
    }
    $Script:SelectedIds = $retainedSelectedIds
}

function Refresh-ShelfWindowPreservingCards {
    if ($ShelfIsRendering) {
        return
    }

    if ($ShelfRenderStartIndex -lt 0 -or $ShelfRenderEndIndex -lt $ShelfRenderStartIndex) {
        Render-ShelfWindow -Force:$true
        return
    }

    $Script:ShelfIsRendering = $true
    try {
        Clear-ShelfBuildQueue
        Clear-ShelfPreheatQueue

        $columns = Get-ShelfColumnCount
        if ($columns -ne $ShelfColumnCount) {
            $Script:ShelfIsRendering = $false
            Render-ShelfWindow -Force:$true
            return
        }

        $virtualCount = Get-ShelfVirtualCount
        $lastBatch = [Math]::Max(0, [int][Math]::Floor(([double][Math]::Max(0, $virtualCount - 1)) / [double]$ShelfBatchSize))
        $firstVisibleRow = [Math]::Max(0, [int][Math]::Floor([double]$ShelfScrollViewer.VerticalOffset / [double]$CardHeight))
        $firstVisibleIndex = [Math]::Min([Math]::Max(0, $firstVisibleRow * $columns), [Math]::Max(0, $virtualCount - 1))
        $currentBatch = [Math]::Min($lastBatch, [Math]::Max(0, [int][Math]::Floor([double]$firstVisibleIndex / [double]$ShelfBatchSize)))
        $startBatch = [Math]::Max(0, $currentBatch - $ShelfBufferBatches)
        $endBatch = [Math]::Min($lastBatch, $currentBatch + $ShelfBufferBatches)
        $renderStart = $startBatch * $ShelfBatchSize
        $renderEnd = [Math]::Min($virtualCount, (($endBatch + 1) * $ShelfBatchSize))

        Queue-ShelfCoverPreheatRange -StartIndex (($endBatch + 1) * $ShelfBatchSize) -EndIndex (($endBatch + 2) * $ShelfBatchSize)
        Queue-ShelfCoverPreheatRange -StartIndex (($startBatch - 1) * $ShelfBatchSize) -EndIndex ($startBatch * $ShelfBatchSize)

        $panelWidth = [Math]::Max($CardWidth, $columns * $CardWidth)
        $ShelfPanel.Width = $panelWidth
        $ShelfTopSpacer.Width = $panelWidth
        $ShelfBottomSpacer.Width = $panelWidth

        $startColumn = $renderStart % $columns
        $topRows = [int][Math]::Floor([double]$renderStart / [double]$columns)
        $renderRows = Get-ShelfRowCount -Count ($startColumn + ($renderEnd - $renderStart)) -Columns $columns
        $totalRows = Get-ShelfRowCount -Count $virtualCount -Columns $columns -AtLeastOne $true
        $bottomRows = [Math]::Max(0, $totalRows - $topRows - $renderRows)
        $ShelfTopSpacer.Height = $topRows * $CardHeight
        $ShelfBottomSpacer.Height = $bottomRows * $CardHeight

        $oldElementsById = @{}
        foreach ($element in @($ShelfPanel.Children)) {
            $tag = ""
            try {
                $tag = ([string]$element.Tag).Trim()
            }
            catch {
                $tag = ""
            }

            if ([string]::IsNullOrWhiteSpace($tag) -or $tag.StartsWith("loading:") -or $tag -eq "__add__") {
                continue
            }
            if (-not $oldElementsById.ContainsKey($tag)) {
                $oldElementsById[$tag] = $element
            }
        }

        $oldCardById = $Script:CardById
        $nextCardById = @{}
        $nextElementByIndex = @{}
        $desiredElements = New-Object 'System.Collections.Generic.List[System.Windows.UIElement]'

        for ($slot = 0; $slot -lt $startColumn; $slot++) {
            $desiredElements.Add((New-ShelfPlaceholder)) | Out-Null
        }

        $itemCount = @($LibraryItems).Count
        for ($index = $renderStart; $index -lt $renderEnd; $index++) {
            $element = $null
            if ($index -lt $itemCount) {
                $itemId = ([string]$LibraryItems[$index].id).Trim()
                if (-not [string]::IsNullOrWhiteSpace($itemId) -and $oldElementsById.ContainsKey($itemId)) {
                    $element = $oldElementsById[$itemId]
                    if ($oldCardById.ContainsKey($itemId)) {
                        $nextCardById[$itemId] = $oldCardById[$itemId]
                    }
                }
            }

            if ($null -eq $element) {
                $element = New-ShelfLoadingCard -Index $index
                Queue-ShelfElementBuild -Index $index
            }

            $desiredElements.Add($element) | Out-Null
            $nextElementByIndex[$index] = $element
        }

        $ShelfPanel.Children.Clear()
        foreach ($element in $desiredElements) {
            $ShelfPanel.Children.Add($element) | Out-Null
        }

        $Script:CardById = $nextCardById
        $Script:ShelfElementByIndex = $nextElementByIndex
        $Script:ShelfPlaceholderCount = $startColumn
        $Script:ShelfRenderStartIndex = $renderStart
        $Script:ShelfRenderEndIndex = $renderEnd
        $Script:ShelfColumnCount = $columns

        Update-SelectionVisuals
    }
    finally {
        $Script:ShelfIsRendering = $false
    }
}

function Remove-VisibleCardsById {
    param(
        $RemovedIdSet
    )

    foreach ($rawId in @($RemovedIdSet | ForEach-Object { [string]$_ })) {
        $itemId = ([string]$rawId).Trim()
        if ([string]::IsNullOrWhiteSpace($itemId) -or -not $CardById.ContainsKey($itemId)) {
            continue
        }

        $parts = $CardById[$itemId]
        if ($parts -and $parts.Root) {
            $ShelfPanel.Children.Remove($parts.Root) | Out-Null
        }
        $CardById.Remove($itemId)
    }
}

function Queue-ShelfPreservingRefresh {
    if ($ShelfRefreshQueued) {
        return
    }

    $Script:ShelfRefreshQueued = $true
    $Window.Dispatcher.BeginInvoke(
        [Action]{
            $Script:ShelfRefreshQueued = $false
            Refresh-ShelfWindowPreservingCards
        },
        [System.Windows.Threading.DispatcherPriority]::ApplicationIdle
    ) | Out-Null
}

function Invoke-DismissDuplicateMembership {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids,

        [string]$ErrorCaption = "移出集合失败"
    )

    $validIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($validIds.Count -eq 0) {
        return $null
    }

    $workerDir = Join-Path $DataDir "duplicate-worker"
    $idsPath = ""
    try {
        New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
        $idsPath = Join-Path $workerDir ("dismiss-{0}.ids.json" -f [System.Guid]::NewGuid().ToString("N"))
        ConvertTo-Json -InputObject @($validIds) -Depth 3 | Set-Content -LiteralPath $idsPath -Encoding UTF8
        return (Invoke-ScannerJson -Arguments @($ScannerPath, "dismiss-duplicates", "--data-dir", $DataDir, "--ids-file", $idsPath) -ErrorCaption $ErrorCaption)
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($idsPath) -and (Test-Path -LiteralPath $idsPath)) {
            try {
                Remove-Item -LiteralPath $idsPath -Force
            }
            catch {
            }
        }
    }
}

function Dismiss-SelectedDuplicates {
    Ensure-SelectedIdsHashSet

    if ($CurrentCategory -ne $DuplicateCategory) {
        return
    }

    $ids = Resolve-RealItemIds -Ids @($SelectedIds)
    if ($ids.Count -eq 0) {
        return
    }

    $result = Invoke-DismissDuplicateMembership -Ids ([string[]]$ids) -ErrorCaption "移出重复项失败"
    if ($null -eq $result) {
        return
    }

    $removedCount = 0
    if ($null -ne $result.removedCount) {
        [int]::TryParse([string]$result.removedCount, [ref]$removedCount) | Out-Null
    }
    if ($removedCount -le 0 -and $null -ne $result.removed) {
        $removedCount = @($result.removed).Count
    }

    Refresh-DuplicateItemCache
    Refresh-CurrentLibraryItemsFromAll
    $Script:SelectedIds = New-SelectedIdSet
    $Script:LastSelectedIndex = -1
    Refresh-ShelfWindowPreservingCards
    Add-StatusLine -Message "已移出重复项：$removedCount 本"
}

function Show-ComicMenu {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.Border]$Target
    )

    $menu = New-Object System.Windows.Controls.ContextMenu
    $singleSourceItem = if ($SelectedIds.Count -eq 1) { Get-SelectedSingleRealItem } else { $null }

    $removeItem = New-Object System.Windows.Controls.MenuItem
    $removeItem.Header = "从书架移除"
    $removeItem.IsEnabled = $SelectedIds.Count -gt 0
    $removeItem.Add_Click({
        param($sender, $eventArgs)
        Remove-SelectedComics
    })

    $dismissDuplicateItem = New-Object System.Windows.Controls.MenuItem
    $dismissDuplicateItem.Header = "移出重复项"
    $dismissDuplicateItem.IsEnabled = ($CurrentCategory -eq $DuplicateCategory -and $SelectedIds.Count -gt 0)
    $dismissDuplicateItem.Add_Click({
        param($sender, $eventArgs)
        Dismiss-SelectedDuplicates
    })

    $openLocationItem = New-Object System.Windows.Controls.MenuItem
    $openLocationItem.Header = "打开原文件位置"
    $openLocationItem.Tag = $singleSourceItem
    $openLocationItem.IsEnabled = $null -ne $singleSourceItem
    $openLocationItem.Add_Click({
        param($sender, $eventArgs)
        Open-ItemSourceLocation $sender.Tag
    })

    $tagItem = New-Object System.Windows.Controls.MenuItem
    $tagItem.Header = "自动识别Tag"
    $tagItem.IsEnabled = $SelectedIds.Count -gt 0
    $tagItem.Add_Click({
        param($sender, $eventArgs)
        $ids = Resolve-RealItemIds -Ids @($SelectedIds)
        Invoke-TagClassification -Ids ([string[]]$ids) -ShowSummary $true | Out-Null
    })

    $duplicateItem = New-Object System.Windows.Controls.MenuItem
    $duplicateItem.Header = "一键查重"
    $duplicateItem.IsEnabled = $SelectedIds.Count -gt 0 -and -not $DuplicateRunning
    $duplicateItem.Add_Click({
        param($sender, $eventArgs)
        $ids = Resolve-RealItemIds -Ids @($SelectedIds)
        Invoke-DuplicateCheck -Ids ([string[]]$ids) -ScopeLabel "选中项目" | Out-Null
    })

    $categoryMenu = New-Object System.Windows.Controls.MenuItem
    $categoryMenu.Header = "设置分类"
    $categoryMenu.IsEnabled = $SelectedIds.Count -gt 0
    $categoryMenu.Tag = "pending"

    $placeholderItem = New-Object System.Windows.Controls.MenuItem
    $placeholderItem.Header = "打开时加载分类..."
    $placeholderItem.IsEnabled = $false
    $categoryMenu.Items.Add($placeholderItem) | Out-Null

    $categoryMenu.Add_SubmenuOpened({
        param($sender, $eventArgs)

        if ([string]$sender.Tag -eq "built") {
            return
        }

        $sender.Items.Clear()
        $assignableCategories = @($FavoriteCategory) + @($LibraryCategories)
        $selectedCategoryCheckMap = Get-SelectedCategoryCheckMap -Categories $assignableCategories

        if ($assignableCategories.Count -eq 0) {
            $emptyItem = New-Object System.Windows.Controls.MenuItem
            $emptyItem.Header = "无自定义分类"
            $emptyItem.IsEnabled = $false
            $sender.Items.Add($emptyItem) | Out-Null
        }

        foreach ($category in $assignableCategories) {
            $categoryName = [string]$category
            $categoryItem = New-Object System.Windows.Controls.MenuItem
            $categoryItem.Header = $categoryName
            $categoryItem.Tag = $categoryName
            $categoryItem.IsCheckable = $true
            $categoryItem.IsChecked = ($selectedCategoryCheckMap.ContainsKey($categoryName) -and [bool]$selectedCategoryCheckMap[$categoryName])
            $categoryItem.Add_Click({
                param($sender, $eventArgs)
                Toggle-SelectedCategory -Category ([string]$sender.Tag)
            })
            $sender.Items.Add($categoryItem) | Out-Null
        }

        $newCategoryItem = New-Object System.Windows.Controls.MenuItem
        $newCategoryItem.Header = "新建分类..."
        $newCategoryItem.Add_Click({
            param($sender, $eventArgs)
            $category = Prompt-NewCategory
            if (-not [string]::IsNullOrWhiteSpace($category)) {
                $ids = @(Resolve-RealItemIds -Ids @($SelectedIds))
                if ($ids.Count -gt 0) {
                    $arguments = @($ScannerPath, "assign-category", "--data-dir", $DataDir, "--name", $category, "--summary-only")
                    $arguments += $ids
                    $result = Invoke-ScannerJson -Arguments $arguments -ErrorCaption "设置分类失败"
                    if ($null -ne $result) {
                        $updatedIds = @($result.updated | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        if ($updatedIds.Count -gt 0) {
                            Apply-CategoryChangeToMemory -Ids ([string[]]$updatedIds) -Category ([string]$result.category) -Action ([string]$result.action)
                        }
                    }
                }
                $Script:CurrentCategory = $category
                Render-Library -Reload:$false
            }
        })
        $sender.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
        $sender.Items.Add($newCategoryItem) | Out-Null
        $sender.Tag = "built"
    })

    $menu.Items.Add($removeItem) | Out-Null
    if ($CurrentCategory -eq $DuplicateCategory) {
        $menu.Items.Add($dismissDuplicateItem) | Out-Null
    }
    $menu.Items.Add($openLocationItem) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $menu.Items.Add($tagItem) | Out-Null
    $menu.Items.Add($duplicateItem) | Out-Null
    $menu.Items.Add($categoryMenu) | Out-Null
    $Target.ContextMenu = $menu
    $menu.IsOpen = $true
}

function Show-ShelfBlankMenu {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.FrameworkElement]$Target
    )

    $menu = New-Object System.Windows.Controls.ContextMenu

    $selectAllItem = New-Object System.Windows.Controls.MenuItem
    $selectAllItem.Header = "全选"
    $selectAllItem.IsEnabled = $LibraryItems.Count -gt 0
    $selectAllItem.Add_Click({
        param($sender, $eventArgs)
        Select-AllComics
    })

    $clearItem = New-Object System.Windows.Controls.MenuItem
    $clearItem.Header = "取消选择"
    $clearItem.IsEnabled = $SelectedIds.Count -gt 0
    $clearItem.Add_Click({
        param($sender, $eventArgs)
        Clear-Selection
    })

    $duplicateCurrentItem = New-Object System.Windows.Controls.MenuItem
    $duplicateCurrentItem.Header = "查重当前分类"
    $duplicateCurrentItem.IsEnabled = $LibraryItems.Count -gt 0 -and -not $DuplicateRunning
    $duplicateCurrentItem.Add_Click({
        param($sender, $eventArgs)
        $ids = Resolve-RealItemIds -Ids @($LibraryItems | ForEach-Object { [string]$_.id })
        Invoke-DuplicateCheck -Ids ([string[]]$ids) -ScopeLabel "当前分类「$CurrentCategory」" | Out-Null
    })

    $menu.Items.Add($selectAllItem) | Out-Null
    $menu.Items.Add($clearItem) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $menu.Items.Add($duplicateCurrentItem) | Out-Null

    $Target.ContextMenu = $menu
    $menu.IsOpen = $true
}

function Prewarm-ComicContextMenu {
    try {
        $target = New-Object System.Windows.Controls.Border
        Show-ComicMenu -Target $target
        if ($target.ContextMenu) {
            $target.ContextMenu.IsOpen = $false
            $target.ContextMenu.Items.Clear()
            $target.ContextMenu = $null
        }
    }
    catch {
    }
}

function Apply-RemovedItemsToShelfData {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    $idSet = New-SelectedIdSet -Ids @($Ids)
    if ($idSet.Count -eq 0) {
        return
    }

    $nextItems = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in @($AllLibraryItems)) {
        $itemId = ([string]$item.id).Trim()
        if ([string]::IsNullOrWhiteSpace($itemId) -or -not $idSet.Contains($itemId)) {
            $nextItems.Add($item) | Out-Null
        }
    }

    $Script:AllLibraryItems = $nextItems.ToArray()
    Rebuild-AllLibraryItemIndex
    $Script:LastSelectedIndex = -1

    if ($VersionGroupMembersById.Count -gt 0 -and (Test-VisibleVersionGroupAffected -RemovedIdSet $idSet)) {
        Refresh-CurrentLibraryItemsFromAll
    }
    else {
        Rebuild-CategoryCountCache
        Update-CategoryCountLabels
        Remove-CurrentLibraryItemsById -RemovedIdSet $idSet
    }

    Clear-ShelfBuildQueue
    Clear-ShelfPreheatQueue
    Remove-VisibleCardsById -RemovedIdSet $idSet
    Queue-ShelfPreservingRefresh
}

function Queue-RemovalViewDataRefresh {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    foreach ($rawId in @($Ids)) {
        $itemId = ([string]$rawId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($itemId)) {
            $RemovalViewRefreshIds.Add($itemId) | Out-Null
        }
    }

    if ($RemovalViewRefreshQueued) {
        return
    }

    $Script:RemovalViewRefreshQueued = $true
    $Window.Dispatcher.BeginInvoke(
        [Action]{
            [string[]]$idsToRefresh = @($Script:RemovalViewRefreshIds | ForEach-Object { [string]$_ })
            $Script:RemovalViewRefreshIds.Clear()
            $Script:RemovalViewRefreshQueued = $false
            if ($idsToRefresh.Count -gt 0) {
                Apply-RemovedItemsToShelfData -Ids $idsToRefresh
            }
        },
        [System.Windows.Threading.DispatcherPriority]::ApplicationIdle
    ) | Out-Null
}

function Remove-ItemsFromShelfView {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    $idSet = New-SelectedIdSet -Ids @($Ids)
    if ($idSet.Count -eq 0) {
        return
    }

    $Script:SelectedIds = New-SelectedIdSet
    $Script:LastSelectedIndex = -1
    Remove-VisibleCardsById -RemovedIdSet $idSet
    Queue-RemovalViewDataRefresh -Ids ([string[]]$Ids)
}

function Start-RemoveWorker {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    $validIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($validIds.Count -eq 0) {
        return $false
    }

    if ($RemoveRunning) {
        foreach ($itemId in $validIds) {
            $RemovePendingIds.Add([string]$itemId) | Out-Null
        }
        Add-StatusLine -Message "后台移除正在运行，已排队：$($validIds.Count) 本"
        return $true
    }

    $workerDir = Join-Path $DataDir "remove-worker"
    $runId = [System.Guid]::NewGuid().ToString("N")
    $Script:RemoveResultPath = Join-Path $workerDir "$runId.result.json"
    $Script:RemoveIdsPath = Join-Path $workerDir "$runId.ids.json"
    $Script:RemoveBatchCount = $validIds.Count
    $Script:RemoveCurrentIds = @($validIds)

    try {
        New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
        ConvertTo-Json -InputObject @($validIds) -Depth 3 | Set-Content -LiteralPath $RemoveIdsPath -Encoding UTF8
    }
    catch {
        $detail = $_.Exception.ToString()
        Write-AppLog -Message "后台移除：写入任务清单失败" -Detail $detail
        $Script:RemoveResultPath = ""
        $Script:RemoveIdsPath = ""
        $Script:RemoveBatchCount = 0
        $Script:RemoveCurrentIds = @()
        Add-StatusLine -Message "从书架移除失败：任务清单写入失败"
        Show-AppMessage -Message "从书架移除失败，详情已记录到日志。" -Caption "删除失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return $false
    }

    $arguments = @($ScannerPath, "remove", "--data-dir", $DataDir, "--summary-only", "--output-file", $RemoveResultPath, "--ids-file", $RemoveIdsPath)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonPath
    $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $true
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null

        $Script:RemoveProcess = $process
        $Script:RemoveRunning = $true
        $RemoveTimer.Start()
        Add-StatusLine -Message "已启动后台移除：$($validIds.Count) 本"
        return $true
    }
    catch {
        $detail = $_.Exception.ToString()
        Write-AppLog -Message "后台移除：启动失败" -Detail $detail
        if (-not [string]::IsNullOrWhiteSpace($RemoveIdsPath) -and (Test-Path -LiteralPath $RemoveIdsPath)) {
            try {
                Remove-Item -LiteralPath $RemoveIdsPath -Force
            }
            catch {
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($RemoveResultPath) -and (Test-Path -LiteralPath $RemoveResultPath)) {
            try {
                Remove-Item -LiteralPath $RemoveResultPath -Force
            }
            catch {
            }
        }
        $Script:RemoveProcess = $null
        $Script:RemoveRunning = $false
        $Script:RemoveResultPath = ""
        $Script:RemoveIdsPath = ""
        $Script:RemoveBatchCount = 0
        $Script:RemoveCurrentIds = @()
        Add-StatusLine -Message "从书架移除失败：后台进程启动失败"
        Show-AppMessage -Message "从书架移除失败，详情已记录到日志。" -Caption "删除失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return $false
    }
}

function Queue-RemoveWorkerStart {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    [string[]]$queuedIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($queuedIds.Count -eq 0) {
        return
    }

    foreach ($itemId in $queuedIds) {
        $RemoveDeferredIds.Add([string]$itemId) | Out-Null
    }

    if ($RemoveStartQueued) {
        return
    }

    $Script:RemoveStartQueued = $true
    $Window.Dispatcher.BeginInvoke(
        [Action]{
            [string[]]$idsToStart = @($Script:RemoveDeferredIds | ForEach-Object { [string]$_ })
            $Script:RemoveDeferredIds.Clear()
            $Script:RemoveStartQueued = $false
            if ($idsToStart.Count -gt 0) {
                Start-RemoveWorker -Ids $idsToStart | Out-Null
            }
        },
        [System.Windows.Threading.DispatcherPriority]::ApplicationIdle
    ) | Out-Null
}

function Remove-SelectedComics {
    Ensure-SelectedIdsHashSet

    $selectedIds = @($SelectedIds)
    $ids = Resolve-RealItemIds -Ids $selectedIds
    if ($ids.Count -eq 0) {
        return
    }

    if ($selectedIds.Count -eq 1) {
        $item = Get-LibraryItemById ([string]$selectedIds[0])
        $name = if ($item) { [string]$item.name } else { "选中的项目" }
        if ($ids.Count -gt 1) {
            $message = "要从书架移除「$name」的 $($ids.Count) 个版本吗？`r`n原始文件不会被删除。"
        }
        else {
            $message = "要从书架移除「$name」吗？`r`n原始文件不会被删除。"
        }
    }
    else {
        $message = "要从书架移除选中的 $($ids.Count) 个项目吗？`r`n原始文件不会被删除。"
    }

    if (-not (Confirm-AppMessage -Message $message -Caption "从书架移除")) {
        return
    }

    if (-not (Add-PendingRemovals -Ids ([string[]]$ids))) {
        Add-StatusLine -Message "从书架移除失败：无法记录待完成任务"
        Show-AppMessage -Message "从书架移除失败，详情已记录到日志。" -Caption "删除失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return
    }

    Remove-ItemsFromShelfView -Ids ([string[]]$ids)
    Queue-RemoveWorkerStart -Ids ([string[]]$ids)
}

function Set-ImageSourceFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Controls.Image]$Image,

        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object System.Uri -ArgumentList $ImagePath
    $bitmap.EndInit()
    $bitmap.Freeze()
    $Image.Source = $bitmap
}

function Show-VersionSelectionDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId
    )

    $members = @(Get-VersionGroupMembers -GroupId $GroupId)
    if ($members.Count -eq 0) {
        return $null
    }
    if ($members.Count -eq 1) {
        return [string]$members[0].id
    }

    $groupItem = if ($VersionGroupItemsById.ContainsKey($GroupId)) { $VersionGroupItemsById[$GroupId] } else { $null }
    $groupLabel = if ($null -ne $groupItem) { ([string]$groupItem.versionGroupLabel).Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($groupLabel)) {
        $groupLabel = "版本"
    }

    $result = [pscustomobject]@{ ItemId = "" }

    $dialog = New-Object System.Windows.Window
    $dialog.Title = "选择$groupLabel"
    $dialog.Width = 620
    $dialog.Height = 420
    $dialog.MinWidth = 480
    $dialog.MinHeight = 320
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Owner = $Window
    $dialog.Background = $BrushWindow

    $root = New-Object System.Windows.Controls.DockPanel
    $root.Margin = New-Object System.Windows.Thickness -ArgumentList 16

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "选择要阅读的$groupLabel"
    $title.Foreground = $BrushText
    $title.FontSize = 16
    $title.FontWeight = "SemiBold"
    $title.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 12
    [System.Windows.Controls.DockPanel]::SetDock($title, "Top")
    $root.Children.Add($title) | Out-Null

    $buttonPanel = New-Object System.Windows.Controls.StackPanel
    $buttonPanel.Orientation = "Horizontal"
    $buttonPanel.HorizontalAlignment = "Right"
    $buttonPanel.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 12, 0, 0
    [System.Windows.Controls.DockPanel]::SetDock($buttonPanel, "Bottom")

    $openButton = New-Object System.Windows.Controls.Button
    $openButton.Content = "打开"
    $openButton.MinWidth = 76
    $openButton.Height = 30
    $openButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
    $openButton.Background = $BrushAccent
    $openButton.Foreground = $BrushWindow
    $openButton.BorderBrush = $BrushTransparent
    $openButton.IsDefault = $true

    $openLocationButton = New-Object System.Windows.Controls.Button
    $openLocationButton.Content = "打开位置"
    $openLocationButton.MinWidth = 86
    $openLocationButton.Height = 30
    $openLocationButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
    $openLocationButton.Background = $BrushCard
    $openLocationButton.Foreground = $BrushText
    $openLocationButton.BorderBrush = $BrushMuted

    $removeFromGroupButton = New-Object System.Windows.Controls.Button
    $removeFromGroupButton.Content = "移出集合"
    $removeFromGroupButton.MinWidth = 86
    $removeFromGroupButton.Height = 30
    $removeFromGroupButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
    $removeFromGroupButton.Background = $BrushCard
    $removeFromGroupButton.Foreground = $BrushText
    $removeFromGroupButton.BorderBrush = $BrushMuted

    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = "取消"
    $cancelButton.MinWidth = 76
    $cancelButton.Height = 30
    $cancelButton.Background = $BrushCard
    $cancelButton.Foreground = $BrushText
    $cancelButton.BorderBrush = $BrushMuted
    $cancelButton.IsCancel = $true

    $buttonPanel.Children.Add($openButton) | Out-Null
    $buttonPanel.Children.Add($openLocationButton) | Out-Null
    $buttonPanel.Children.Add($removeFromGroupButton) | Out-Null
    $buttonPanel.Children.Add($cancelButton) | Out-Null
    $root.Children.Add($buttonPanel) | Out-Null

    $listBox = New-Object System.Windows.Controls.ListBox
    $listBox.Background = $BrushCard
    $listBox.Foreground = $BrushText
    $listBox.BorderBrush = $BrushMuted
    $listBox.HorizontalContentAlignment = "Stretch"

    foreach ($item in $members) {
        $listItem = New-Object System.Windows.Controls.ListBoxItem
        $listItem.Tag = [string]$item.id
        $listItem.Padding = New-Object System.Windows.Thickness -ArgumentList 8
        $listItem.HorizontalContentAlignment = "Stretch"

        $row = New-Object System.Windows.Controls.DockPanel
        $row.LastChildFill = $true

        $thumb = New-Object System.Windows.Controls.Border
        $thumb.Width = 54
        $thumb.Height = 76
        $thumb.Background = $BrushCover
        $thumb.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 4
        $thumb.ClipToBounds = $true
        $thumb.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 10, 0
        $thumbImage = New-CoverImage (Resolve-CoverPath $item)
        $thumbImage.Width = 54
        $thumbImage.Height = 76
        $thumb.Child = $thumbImage
        [System.Windows.Controls.DockPanel]::SetDock($thumb, "Left")
        $row.Children.Add($thumb) | Out-Null

        $textStack = New-Object System.Windows.Controls.StackPanel
        $textStack.VerticalAlignment = "Center"

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = [string]$item.name
        $nameText.Foreground = $BrushText
        $nameText.FontSize = 14
        $nameText.FontWeight = "SemiBold"
        $nameText.TextTrimming = "CharacterEllipsis"

        $pageCount = 0
        [int]::TryParse([string]$item.pageCount, [ref]$pageCount) | Out-Null
        $kindText = if ([string]$item.kind -eq "archive") { "压缩包" } else { "文件夹" }
        $metaText = New-Object System.Windows.Controls.TextBlock
        $metaText.Text = "$kindText  ·  $pageCount 页"
        $metaText.Foreground = $BrushMuted
        $metaText.FontSize = 12
        $metaText.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 4, 0, 0

        $sourcePath = if ([string]$item.kind -eq "archive") { [string]$item.sourcePath } else { [string]$item.comicPath }
        $pathText = New-Object System.Windows.Controls.TextBlock
        $pathText.Text = $sourcePath
        $pathText.Foreground = $BrushMuted
        $pathText.FontSize = 11
        $pathText.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 4, 0, 0
        $pathText.TextTrimming = "CharacterEllipsis"

        $textStack.Children.Add($nameText) | Out-Null
        $textStack.Children.Add($metaText) | Out-Null
        $textStack.Children.Add($pathText) | Out-Null
        $row.Children.Add($textStack) | Out-Null

        $listItem.Content = $row
        $listBox.Items.Add($listItem) | Out-Null
    }

    if ($listBox.Items.Count -gt 0) {
        $listBox.SelectedIndex = 0
    }

    $updateVersionButtons = {
        $hasSelection = ($null -ne $listBox.SelectedItem)
        $openButton.IsEnabled = $hasSelection
        $openLocationButton.IsEnabled = $hasSelection
        $removeFromGroupButton.IsEnabled = $hasSelection
    }
    & $updateVersionButtons

    $confirmSelection = {
        if ($null -eq $listBox.SelectedItem) {
            return
        }
        $result.ItemId = [string]$listBox.SelectedItem.Tag
        $dialog.DialogResult = $true
    }

    $openButton.Add_Click({
        param($sender, $eventArgs)
        & $confirmSelection
    })

    $openLocationButton.Add_Click({
        param($sender, $eventArgs)
        if ($null -eq $listBox.SelectedItem) {
            return
        }

        $selectedItem = Get-AllLibraryItemById ([string]$listBox.SelectedItem.Tag)
        if ($null -ne $selectedItem) {
            Open-ItemSourceLocation $selectedItem
        }
    })

    $removeFromGroupButton.Add_Click({
        param($sender, $eventArgs)
        if ($null -eq $listBox.SelectedItem) {
            return
        }

        $selectedIndex = [int]$listBox.SelectedIndex
        $selectedId = [string]$listBox.SelectedItem.Tag
        $dismissResult = Invoke-DismissDuplicateMembership -Ids @($selectedId) -ErrorCaption "移出集合失败"
        if ($null -eq $dismissResult) {
            return
        }

        $removedCount = 0
        if ($null -ne $dismissResult.removedCount) {
            [int]::TryParse([string]$dismissResult.removedCount, [ref]$removedCount) | Out-Null
        }
        if ($removedCount -le 0 -and $null -ne $dismissResult.removed) {
            $removedCount = @($dismissResult.removed).Count
        }

        Refresh-DuplicateItemCache
        Refresh-VersionGroupCache
        $listBox.Items.Remove($listBox.SelectedItem)
        Add-StatusLine -Message "已从$groupLabel集合移出：$removedCount 本"

        if ($listBox.Items.Count -le 1) {
            $dialog.DialogResult = $false
            $dialog.Close()
            return
        }

        if ($selectedIndex -ge $listBox.Items.Count) {
            $selectedIndex = $listBox.Items.Count - 1
        }
        $listBox.SelectedIndex = [Math]::Max(0, $selectedIndex)
        & $updateVersionButtons
    })

    $listBox.Add_SelectionChanged({
        param($sender, $eventArgs)
        & $updateVersionButtons
    })

    $listBox.Add_MouseDoubleClick({
        param($sender, $eventArgs)
        & $confirmSelection
    })

    $root.Children.Add($listBox) | Out-Null
    $dialog.Content = $root

    if ($dialog.ShowDialog() -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$result.ItemId)) {
        return [string]$result.ItemId
    }
    return $null
}

function Prompt-ArchivePassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Message = "该压缩包需要密码。"
    )

    $dialog = New-Object System.Windows.Window
    $dialog.Title = "输入压缩包密码"
    $dialog.Width = 420
    $dialog.Height = 190
    $dialog.MinWidth = 360
    $dialog.MinHeight = 180
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Owner = $Window
    $dialog.Background = $BrushWindow
    $dialog.ResizeMode = "NoResize"

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 18

    $messageText = New-Object System.Windows.Controls.TextBlock
    $messageText.Text = "$Message`r`n$Name"
    $messageText.Foreground = $BrushText
    $messageText.FontSize = 13
    $messageText.TextWrapping = "Wrap"
    $messageText.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 12

    $passwordBox = New-Object System.Windows.Controls.PasswordBox
    $passwordBox.Height = 30
    $passwordBox.Background = $BrushCard
    $passwordBox.Foreground = $BrushText
    $passwordBox.BorderBrush = $BrushMuted
    $passwordBox.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 0, 14

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = "Horizontal"
    $buttons.HorizontalAlignment = "Right"

    $okButton = New-Object System.Windows.Controls.Button
    $okButton.Content = "确定"
    $okButton.Width = 74
    $okButton.Height = 30
    $okButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
    $okButton.Background = $BrushAccent
    $okButton.Foreground = $BrushWindow
    $okButton.BorderBrush = $BrushTransparent
    $okButton.IsDefault = $true

    $cancelButton = New-Object System.Windows.Controls.Button
    $cancelButton.Content = "取消"
    $cancelButton.Width = 74
    $cancelButton.Height = 30
    $cancelButton.Background = $BrushSidebarItemSelected
    $cancelButton.Foreground = $BrushText
    $cancelButton.BorderBrush = $BrushTransparent
    $cancelButton.IsCancel = $true

    $result = [pscustomobject]@{ Password = $null }
    $okButton.Add_Click({
        param($sender, $eventArgs)
        $result.Password = $passwordBox.Password
        $dialog.DialogResult = $true
    })
    $cancelButton.Add_Click({
        param($sender, $eventArgs)
        $dialog.DialogResult = $false
    })

    $buttons.Children.Add($okButton) | Out-Null
    $buttons.Children.Add($cancelButton) | Out-Null
    $panel.Children.Add($messageText) | Out-Null
    $panel.Children.Add($passwordBox) | Out-Null
    $panel.Children.Add($buttons) | Out-Null
    $dialog.Content = $panel
    $dialog.Add_ContentRendered({
        $passwordBox.Focus() | Out-Null
    })

    if ($dialog.ShowDialog() -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$result.Password)) {
        return [string]$result.Password
    }
    return $null
}

function Open-Reader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemId
    )

    if ($VersionGroupMembersById.ContainsKey($ItemId)) {
        $selectedVersionId = Show-VersionSelectionDialog -GroupId $ItemId
        if ([string]::IsNullOrWhiteSpace($selectedVersionId)) {
            return
        }
        $ItemId = $selectedVersionId
    }

    $sourceItem = Get-AllLibraryItemById $ItemId
    if ($null -ne $sourceItem) {
        $sourcePath = Get-ItemSourcePath $sourceItem
        if (-not [string]::IsNullOrWhiteSpace($sourcePath) -and
            -not [System.IO.File]::Exists($sourcePath) -and
            -not [System.IO.Directory]::Exists($sourcePath)) {
            Write-AppLog -Message "打开阅读器：原文件不存在" -Detail $sourcePath
            Add-StatusLine -Message "打开阅读器失败：原文件不存在"
            Show-AppMessage -Message "原文件不存在" -Caption "打开阅读器失败" -Image ([System.Windows.MessageBoxImage]::Warning)
            return
        }
    }

    $oldTitle = $Window.Title
    $Window.Title = "mangaga - 准备阅读缓存"
    $passwordForRetry = $null
    $usedPassword = $false

    try {
        while ($true) {
            $infoArgs = @($ScannerPath, "prepare-reader", "--data-dir", $DataDir, "--id", $ItemId, "--session-id", $SessionId)
            if (-not [string]::IsNullOrWhiteSpace($passwordForRetry)) {
                $infoArgs += @("--password", $passwordForRetry)
            }

            $info = Invoke-ScannerJson -Arguments $infoArgs -ErrorCaption "打开阅读器失败"
            if ($null -eq $info) {
                return
            }

            if ([bool]$info.needsPassword) {
                $passwordForRetry = Prompt-ArchivePassword -Name ([string]$info.name) -Message ([string]$info.message)
                if ([string]::IsNullOrWhiteSpace($passwordForRetry)) {
                    return
                }
                $usedPassword = $true
                continue
            }

            break
        }
    }
    finally {
        $Window.Title = $oldTitle
    }

    if ($usedPassword -or [bool]$info.unlockedPasswordItem) {
        Add-StatusLine -Message "压缩包密码已保存，并已补全封面。"
        Render-Library
    }

    $pageCount = [int]$info.pageCount
    if ($pageCount -le 0) {
        Show-AppMessage -Message "该漫画没有可阅读的图片。" -Caption "打开阅读器失败" -Image ([System.Windows.MessageBoxImage]::Warning)
        return
    }

    $readerWindow = New-Object System.Windows.Window
    $readerWindow.Title = [string]$info.name
    $readerWindow.Width = 980
    $readerWindow.Height = 760
    $readerWindow.MinWidth = 520
    $readerWindow.MinHeight = 420
    $readerWindow.WindowStartupLocation = "CenterOwner"
    $readerWindow.Owner = $Window
    $readerWindow.Background = $BrushWindow

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Background = $BrushWindow

    $image = New-Object System.Windows.Controls.Image
    $image.Stretch = "Uniform"
    $image.HorizontalAlignment = "Stretch"
    $image.VerticalAlignment = "Stretch"
    $image.RenderTransformOrigin = New-Object System.Windows.Point -ArgumentList 0.5, 0.5
    $imageScale = New-Object System.Windows.Media.ScaleTransform
    $imageScale.ScaleX = 1.0
    $imageScale.ScaleY = 1.0
    $image.RenderTransform = $imageScale
    $grid.Children.Add($image) | Out-Null

    $topBar = New-Object System.Windows.Controls.Border
    $topBar.Height = 42
    $topBar.VerticalAlignment = "Top"
    $topBar.Background = $BrushReaderPanel

    $topGrid = New-Object System.Windows.Controls.Grid
    $topGrid.Margin = New-Object System.Windows.Thickness -ArgumentList 14, 0, 14, 0
    $titleColumn = New-Object System.Windows.Controls.ColumnDefinition
    $titleColumn.Width = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
    $controlsColumn = New-Object System.Windows.Controls.ColumnDefinition
    $controlsColumn.Width = New-Object System.Windows.GridLength -ArgumentList 0, ([System.Windows.GridUnitType]::Auto)
    $topGrid.ColumnDefinitions.Add($titleColumn) | Out-Null
    $topGrid.ColumnDefinitions.Add($controlsColumn) | Out-Null

    $titleText = New-Object System.Windows.Controls.TextBlock
    $titleText.Text = [string]$info.name
    $titleText.Foreground = $BrushText
    $titleText.FontSize = 14
    $titleText.TextTrimming = "CharacterEllipsis"
    $titleText.VerticalAlignment = "Center"
    $titleText.HorizontalAlignment = "Left"
    $titleText.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 12, 0

    $rightPanel = New-Object System.Windows.Controls.StackPanel
    $rightPanel.Orientation = "Horizontal"
    $rightPanel.HorizontalAlignment = "Right"
    $rightPanel.VerticalAlignment = "Center"

    $intervalPanel = New-Object System.Windows.Controls.StackPanel
    $intervalPanel.Orientation = "Horizontal"
    $intervalPanel.VerticalAlignment = "Center"
    $intervalPanel.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 10, 0

    $intervalMinusButton = New-Object System.Windows.Controls.Button
    $intervalMinusButton.Content = "-"
    $intervalMinusButton.Foreground = $BrushText
    $intervalMinusButton.Background = $BrushTransparent
    $intervalMinusButton.BorderBrush = $BrushTransparent
    $intervalMinusButton.FontSize = 16
    $intervalMinusButton.FontWeight = "SemiBold"
    $intervalMinusButton.MinWidth = 26
    $intervalMinusButton.Height = 26
    $intervalMinusButton.Padding = New-Object System.Windows.Thickness -ArgumentList 0
    $intervalMinusButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 4, 0
    $intervalMinusButton.Focusable = $false
    $intervalMinusButton.IsDefault = $false
    $intervalMinusButton.IsCancel = $false

    $intervalLabel = New-Object System.Windows.Controls.TextBlock
    $intervalLabel.Text = "间隔"
    $intervalLabel.Foreground = $BrushText
    $intervalLabel.FontSize = 13
    $intervalLabel.VerticalAlignment = "Center"

    $intervalBox = New-Object System.Windows.Controls.TextBox
    $intervalBox.Text = "3.0"
    $intervalBox.Foreground = $BrushText
    $intervalBox.Background = $BrushCard
    $intervalBox.BorderBrush = $BrushMuted
    $intervalBox.Width = 44
    $intervalBox.Height = 24
    $intervalBox.Padding = New-Object System.Windows.Thickness -ArgumentList 4, 1, 4, 1
    $intervalBox.Margin = New-Object System.Windows.Thickness -ArgumentList 3, 0, 3, 0
    $intervalBox.VerticalContentAlignment = "Center"
    $intervalBox.TextAlignment = "Center"
    $intervalBox.ToolTip = "自动播放间隔，单位秒"

    $intervalUnit = New-Object System.Windows.Controls.TextBlock
    $intervalUnit.Text = "秒"
    $intervalUnit.Foreground = $BrushText
    $intervalUnit.FontSize = 13
    $intervalUnit.VerticalAlignment = "Center"

    $intervalPlusButton = New-Object System.Windows.Controls.Button
    $intervalPlusButton.Content = "+"
    $intervalPlusButton.Foreground = $BrushText
    $intervalPlusButton.Background = $BrushTransparent
    $intervalPlusButton.BorderBrush = $BrushTransparent
    $intervalPlusButton.FontSize = 16
    $intervalPlusButton.FontWeight = "SemiBold"
    $intervalPlusButton.MinWidth = 26
    $intervalPlusButton.Height = 26
    $intervalPlusButton.Padding = New-Object System.Windows.Thickness -ArgumentList 0
    $intervalPlusButton.Margin = New-Object System.Windows.Thickness -ArgumentList 4, 0, 0, 0
    $intervalPlusButton.Focusable = $false
    $intervalPlusButton.IsDefault = $false
    $intervalPlusButton.IsCancel = $false

    $prevButton = New-Object System.Windows.Controls.Button
    $prevButton.Content = "‹"
    $prevButton.Foreground = $BrushText
    $prevButton.Background = $BrushCard
    $prevButton.BorderBrush = $BrushMuted
    $prevButton.FontSize = 18
    $prevButton.MinWidth = 32
    $prevButton.Height = 28
    $prevButton.Padding = New-Object System.Windows.Thickness -ArgumentList 0
    $prevButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 4, 0
    $prevButton.Focusable = $false
    $prevButton.IsDefault = $false
    $prevButton.IsCancel = $false

    $playButton = New-Object System.Windows.Controls.Button
    $playButton.Content = "▶"
    $playButton.Foreground = $BrushText
    $playButton.Background = $BrushCard
    $playButton.BorderBrush = $BrushMuted
    $playButton.FontSize = 14
    $playButton.MinWidth = 36
    $playButton.Height = 28
    $playButton.Padding = New-Object System.Windows.Thickness -ArgumentList 0
    $playButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 4, 0
    $playButton.Focusable = $false
    $playButton.IsDefault = $false
    $playButton.IsCancel = $false

    $nextButton = New-Object System.Windows.Controls.Button
    $nextButton.Content = "›"
    $nextButton.Foreground = $BrushText
    $nextButton.Background = $BrushCard
    $nextButton.BorderBrush = $BrushMuted
    $nextButton.FontSize = 18
    $nextButton.MinWidth = 32
    $nextButton.Height = 28
    $nextButton.Padding = New-Object System.Windows.Thickness -ArgumentList 0
    $nextButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 10, 0
    $nextButton.Focusable = $false
    $nextButton.IsDefault = $false
    $nextButton.IsCancel = $false

    $homeButton = New-Object System.Windows.Controls.Button
    $homeButton.Content = "首页"
    $homeButton.Foreground = $BrushText
    $homeButton.Background = $BrushCard
    $homeButton.BorderBrush = $BrushMuted
    $homeButton.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 3, 10, 3
    $homeButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 8, 0
    $homeButton.Focusable = $false
    $homeButton.IsDefault = $false
    $homeButton.IsCancel = $false

    $favoriteButton = New-Object System.Windows.Controls.Button
    $favoriteButton.Foreground = $BrushText
    $favoriteButton.Background = $BrushCard
    $favoriteButton.BorderBrush = $BrushMuted
    $favoriteButton.Padding = New-Object System.Windows.Thickness -ArgumentList 10, 3, 10, 3
    $favoriteButton.Margin = New-Object System.Windows.Thickness -ArgumentList 0, 0, 12, 0
    $favoriteButton.Focusable = $false
    $favoriteButton.IsDefault = $false
    $favoriteButton.IsCancel = $false

    $counterText = New-Object System.Windows.Controls.TextBlock
    $counterText.Foreground = $BrushMuted
    $counterText.FontSize = 13
    $counterText.VerticalAlignment = "Center"
    $counterText.MinWidth = 56
    $counterText.TextAlignment = "Right"

    $intervalPanel.Children.Add($intervalMinusButton) | Out-Null
    $intervalPanel.Children.Add($intervalLabel) | Out-Null
    $intervalPanel.Children.Add($intervalBox) | Out-Null
    $intervalPanel.Children.Add($intervalUnit) | Out-Null
    $intervalPanel.Children.Add($intervalPlusButton) | Out-Null
    $rightPanel.Children.Add($intervalPanel) | Out-Null
    $rightPanel.Children.Add($prevButton) | Out-Null
    $rightPanel.Children.Add($playButton) | Out-Null
    $rightPanel.Children.Add($nextButton) | Out-Null
    $rightPanel.Children.Add($homeButton) | Out-Null
    $rightPanel.Children.Add($favoriteButton) | Out-Null
    $rightPanel.Children.Add($counterText) | Out-Null

    [System.Windows.Controls.Grid]::SetColumn($titleText, 0)
    [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)
    $topGrid.Children.Add($titleText) | Out-Null
    $topGrid.Children.Add($rightPanel) | Out-Null
    $topBar.Child = $topGrid
    $grid.Children.Add($topBar) | Out-Null

    $readerWindow.Content = $grid

    $state = [pscustomobject]@{
        CurrentIndex = [int]$info.progressIndex
        PageCount = $pageCount
        ItemId = $ItemId
        IsFavorite = $false
        FavoriteChanged = $false
        Zoom = 1.0
        AutoPlay = $false
        AutoPlayInterval = 3.0
        PrefetchProcess = $null
        PrefetchTargetIndex = -1
        PrefetchRequestedIndex = -1
        ReaderClosed = $false
    }
    $pages = @($info.pages)

    $state.IsFavorite = Get-CurrentFavoriteState $ItemId

    $autoPlayTimer = New-Object System.Windows.Threading.DispatcherTimer
    $hideControlsTimer = New-Object System.Windows.Threading.DispatcherTimer
    $hideControlsTimer.Interval = [TimeSpan]::FromSeconds(3)
    $prefetchTimer = New-Object System.Windows.Threading.DispatcherTimer
    $prefetchTimer.Interval = [TimeSpan]::FromMilliseconds(700)

    $showReaderControls = {
        $topBar.Visibility = "Visible"
        $hideControlsTimer.Stop()
        $hideControlsTimer.Start()
    }

    $hideControlsTimer.Add_Tick({
        param($sender, $eventArgs)
        $hideControlsTimer.Stop()
        $topBar.Visibility = "Collapsed"
    })

    $setZoom = {
        param([double]$Zoom)

        $nextZoom = [Math]::Max(0.25, [Math]::Min(5.0, $Zoom))
        $state.Zoom = $nextZoom
        $imageScale.ScaleX = $nextZoom
        $imageScale.ScaleY = $nextZoom
    }

    $formatInterval = {
        param([double]$Value)

        if ([Math]::Abs($Value - [Math]::Round($Value)) -lt 0.01) {
            return ("{0:0}" -f $Value)
        }
        return ("{0:0.0}" -f $Value)
    }

    $setAutoPlayInterval = {
        param([double]$Value)

        $nextValue = [Math]::Max(0.1, [Math]::Min(999.9, $Value))
        $nextValue = [Math]::Round($nextValue, 1)
        $state.AutoPlayInterval = $nextValue
        $intervalBox.Text = (& $formatInterval $nextValue)
        $autoPlayTimer.Interval = [TimeSpan]::FromSeconds($nextValue)
    }

    $commitIntervalInput = {
        $raw = ([string]$intervalBox.Text).Trim().Replace("秒", "").Replace("s", "").Replace("S", "").Replace(",", ".")
        if ([string]::IsNullOrWhiteSpace($raw)) {
            & $setAutoPlayInterval $state.AutoPlayInterval
            return
        }

        try {
            $parsed = [double]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture)
            & $setAutoPlayInterval $parsed
        }
        catch {
            & $setAutoPlayInterval $state.AutoPlayInterval
        }
    }

    $updatePlayButton = {
        if ($state.AutoPlay) {
            $playButton.Content = "||"
        }
        else {
            $playButton.Content = "▶"
        }
    }

    $toggleAutoPlay = {
        $state.AutoPlay = -not [bool]$state.AutoPlay
        if ($state.AutoPlay) {
            $autoPlayTimer.Start()
        }
        else {
            $autoPlayTimer.Stop()
        }
        & $updatePlayButton
    }

    $updateFavoriteButton = {
        if ($state.IsFavorite) {
            $favoriteButton.Content = "已喜爱"
            $favoriteButton.Foreground = $BrushAccent
        }
        else {
            $favoriteButton.Content = "喜爱"
            $favoriteButton.Foreground = $BrushText
        }
    }

    $toggleFavorite = {
        $state.IsFavorite = Get-CurrentFavoriteState $state.ItemId
        $wasFavorite = [bool]$state.IsFavorite

        if ($wasFavorite) {
            $favoriteArgs = @($ScannerPath, "unassign-category", "--data-dir", $DataDir, "--name", $FavoriteCategory, $state.ItemId)
        }
        else {
            $favoriteArgs = @($ScannerPath, "assign-category", "--data-dir", $DataDir, "--name", $FavoriteCategory, "--explicit-favorite", $state.ItemId)
        }

        $result = Invoke-ScannerJson -Arguments $favoriteArgs -ErrorCaption "设置喜爱失败"
        if ($null -eq $result) {
            return
        }

        $updatedItem = Find-LibraryItemById $result.library $state.ItemId
        if ($null -ne $updatedItem) {
            $state.IsFavorite = Item-HasCategory $updatedItem $FavoriteCategory
        }
        else {
            $state.IsFavorite = Get-CurrentFavoriteState $state.ItemId
        }
        $state.FavoriteChanged = $true
        & $updateFavoriteButton
    }

    $saveProgress = {
        $progressArgs = @($ScannerPath, "progress", "--data-dir", $DataDir, "--id", $state.ItemId, "--index", [string]$state.CurrentIndex)
        Invoke-ScannerJson -Arguments $progressArgs -ErrorCaption "保存阅读进度失败" | Out-Null
    }

    $updateCachedPages = {
        param($Result)

        if ($null -eq $Result) {
            return
        }

        foreach ($cachedPage in @($Result.cached)) {
            $cachedIndex = -1
            [int]::TryParse([string]$cachedPage.index, [ref]$cachedIndex) | Out-Null
            if ($cachedIndex -ge 0 -and $cachedIndex -lt $pages.Count) {
                $pages[$cachedIndex] = $cachedPage
            }
        }
        if ($null -ne $Result.page) {
            $cachedIndex = -1
            [int]::TryParse([string]$Result.page.index, [ref]$cachedIndex) | Out-Null
            if ($cachedIndex -ge 0 -and $cachedIndex -lt $pages.Count) {
                $pages[$cachedIndex] = $Result.page
            }
        }
    }

    $isPageCached = {
        param([int]$Index)

        if ($Index -lt 0 -or $Index -ge $pages.Count) {
            return $false
        }

        $page = $pages[$Index]
        if ($null -eq $page -or [string]::IsNullOrWhiteSpace([string]$page.viewPath)) {
            return $false
        }
        return (Test-Path -LiteralPath ([string]$page.viewPath))
    }

    $prepareSinglePage = {
        param([int]$Index)

        $pageArgs = @($ScannerPath, "prepare-reader-page", "--data-dir", $DataDir, "--id", $state.ItemId, "--session-id", $SessionId, "--index", [string]$Index)
        $result = Invoke-ScannerJson -Arguments $pageArgs -ErrorCaption "读取页面失败"
        if ($null -eq $result) {
            return $false
        }
        if ([bool]$result.needsPassword) {
            Show-AppMessage -Message ([string]$result.message) -Caption "读取页面失败" -Image ([System.Windows.MessageBoxImage]::Warning)
            return $false
        }
        & $updateCachedPages $result
        return (& $isPageCached $Index)
    }

    $launchPrefetch = {
        param([int]$StartIndex)

        if ($state.ReaderClosed) {
            return
        }

        $arguments = @($ScannerPath, "prepare-reader-window", "--data-dir", $DataDir, "--id", $state.ItemId, "--session-id", $SessionId, "--index", [string]$StartIndex, "--count", [string]$ReaderPrefetchCount)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $PythonPath
        $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        try {
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null
            $state.PrefetchProcess = $process
            $state.PrefetchTargetIndex = $StartIndex
            $prefetchTimer.Start()
        }
        catch {
            Add-StatusLine -Message "阅读缓存预取启动失败：$($_.Exception.Message)"
            $state.PrefetchProcess = $null
            $state.PrefetchTargetIndex = -1
        }
    }

    $isIndexInPrefetchWindow = {
        param(
            [int]$Index,
            [int]$StartIndex
        )

        if ($state.PageCount -le 0 -or $StartIndex -lt 0) {
            return $false
        }

        $count = [Math]::Min($ReaderPrefetchCount, $state.PageCount)
        for ($offset = 0; $offset -lt $count; $offset++) {
            $candidate = ($StartIndex + $offset) % $state.PageCount
            if ($candidate -eq $Index) {
                return $true
            }
        }
        return $false
    }

    $stopPrefetch = {
        param(
            [bool]$ClearRequested = $false
        )

        if ($null -ne $state.PrefetchProcess) {
            if (-not $state.PrefetchProcess.HasExited) {
                try {
                    $state.PrefetchProcess.Kill()
                }
                catch {
                }
            }
            try {
                $state.PrefetchProcess.Dispose()
            }
            catch {
            }
        }

        $state.PrefetchProcess = $null
        $state.PrefetchTargetIndex = -1
        if ($ClearRequested) {
            $state.PrefetchRequestedIndex = -1
        }
        $prefetchTimer.Stop()
    }

    $requestPrefetch = {
        param([int]$StartIndex)

        if ($state.ReaderClosed -or $state.PageCount -le 0) {
            return
        }

        if ($StartIndex -lt 0) {
            $StartIndex = 0
        }
        elseif ($StartIndex -ge $state.PageCount) {
            $StartIndex = $StartIndex % $state.PageCount
        }

        $state.PrefetchRequestedIndex = $StartIndex
        if ($null -ne $state.PrefetchProcess) {
            if (-not $state.PrefetchProcess.HasExited) {
                if (-not (& $isIndexInPrefetchWindow $StartIndex ([int]$state.PrefetchTargetIndex))) {
                    & $stopPrefetch
                }
                else {
                    return
                }
            }
            else {
                $completedTarget = [int]$state.PrefetchTargetIndex
                & $completePrefetch
                if ($completedTarget -eq $StartIndex -or $null -ne $state.PrefetchProcess) {
                    return
                }
            }
        }

        & $launchPrefetch $StartIndex
    }

    $completePrefetch = {
        if ($null -eq $state.PrefetchProcess) {
            $prefetchTimer.Stop()
            return
        }

        if (-not $state.PrefetchProcess.HasExited) {
            return
        }

        $process = $state.PrefetchProcess
        $targetIndex = [int]$state.PrefetchTargetIndex
        $stdout = ""
        $stderr = ""
        try {
            $stdout = $process.StandardOutput.ReadToEnd().Trim()
            $stderr = $process.StandardError.ReadToEnd().Trim()
        }
        catch {
            $stderr = $_.Exception.Message
        }
        $exitCode = $process.ExitCode
        $process.Dispose()
        $state.PrefetchProcess = $null
        $state.PrefetchTargetIndex = -1

        if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdout)) {
            try {
                $result = $stdout | ConvertFrom-Json
                & $updateCachedPages $result
            }
            catch {
                Add-StatusLine -Message "阅读缓存预取结果解析失败：$($_.Exception.Message)"
            }
        }
        elseif ($exitCode -ne 0) {
            if ([string]::IsNullOrWhiteSpace($stderr)) {
                $stderr = "预取进程异常退出。"
            }
            Write-AppLog -Message "阅读缓存预取失败" -Detail $stderr
            Add-StatusLine -Message ("阅读缓存预取失败：" + (Get-UserFacingErrorMessage -RawMessage $stderr))
        }

        if (-not $state.ReaderClosed -and [int]$state.PrefetchRequestedIndex -ge 0 -and [int]$state.PrefetchRequestedIndex -ne $targetIndex) {
            & $launchPrefetch ([int]$state.PrefetchRequestedIndex)
        }
        elseif ($null -eq $state.PrefetchProcess) {
            $prefetchTimer.Stop()
        }
    }

    $prefetchTimer.Add_Tick({
        param($sender, $eventArgs)
        & $completePrefetch
    })

    $loadPage = {
        param([int]$NextIndex)

        if ($state.PageCount -le 0) {
            return
        }

        if ($NextIndex -lt 0) {
            $NextIndex = $state.PageCount - 1
        }
        elseif ($NextIndex -ge $state.PageCount) {
            $NextIndex = 0
        }

        if (-not (& $isPageCached $NextIndex)) {
            if ($null -ne $state.PrefetchProcess -and -not $state.PrefetchProcess.HasExited -and -not (& $isIndexInPrefetchWindow $NextIndex ([int]$state.PrefetchTargetIndex))) {
                $state.PrefetchRequestedIndex = $NextIndex
                & $stopPrefetch
            }

            if (-not (& $prepareSinglePage $NextIndex)) {
                return
            }
        }

        $page = $pages[$NextIndex]
        if ($null -eq $page -or [string]::IsNullOrWhiteSpace([string]$page.viewPath) -or -not (Test-Path -LiteralPath ([string]$page.viewPath))) {
            Show-AppMessage -Message "页面缓存路径无效。" -Caption "读取页面失败" -Image ([System.Windows.MessageBoxImage]::Error)
            return
        }

        Set-ImageSourceFromPath -Image $image -ImagePath ([string]$page.viewPath)
        $state.CurrentIndex = $NextIndex
        $counterText.Text = ("{0} / {1}" -f ($state.CurrentIndex + 1), $state.PageCount)
        & $requestPrefetch $state.CurrentIndex
    }

    $autoPlayTimer.Add_Tick({
        param($sender, $eventArgs)
        & $loadPage ($state.CurrentIndex + 1)
    })

    $readerWindow.Add_Closed({
        param($sender, $eventArgs)
        $state.ReaderClosed = $true
        $autoPlayTimer.Stop()
        $hideControlsTimer.Stop()
        $prefetchTimer.Stop()
        if ($null -ne $state.PrefetchProcess -and -not $state.PrefetchProcess.HasExited) {
            try {
                $state.PrefetchProcess.Kill()
            }
            catch {
            }
        }
        if ($null -ne $state.PrefetchProcess) {
            $state.PrefetchProcess.Dispose()
            $state.PrefetchProcess = $null
        }
        & $saveProgress
        if ($state.FavoriteChanged) {
            Render-Library
        }
    })

    $intervalMinusButton.Add_Click({
        param($sender, $eventArgs)
        & $setAutoPlayInterval ($state.AutoPlayInterval - 1.0)
        & $showReaderControls
    })

    $intervalPlusButton.Add_Click({
        param($sender, $eventArgs)
        & $setAutoPlayInterval ($state.AutoPlayInterval + 1.0)
        & $showReaderControls
    })

    $intervalBox.Add_LostFocus({
        param($sender, $eventArgs)
        & $commitIntervalInput
    })

    $intervalBox.Add_TextChanged({
        param($sender, $eventArgs)
        & $showReaderControls
    })

    $intervalBox.Add_GotKeyboardFocus({
        param($sender, $eventArgs)
        & $showReaderControls
    })

    $intervalBox.Add_KeyDown({
        param($sender, $eventArgs)
        & $showReaderControls
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
            & $commitIntervalInput
            [System.Windows.Input.Keyboard]::ClearFocus() | Out-Null
            $eventArgs.Handled = $true
        }
    })

    $prevButton.Add_Click({
        param($sender, $eventArgs)
        & $loadPage ($state.CurrentIndex - 1)
        & $showReaderControls
    })

    $playButton.Add_Click({
        param($sender, $eventArgs)
        & $toggleAutoPlay
        & $showReaderControls
    })

    $nextButton.Add_Click({
        param($sender, $eventArgs)
        & $loadPage ($state.CurrentIndex + 1)
        & $showReaderControls
    })

    $homeButton.Add_Click({
        param($sender, $eventArgs)
        & $loadPage 0
        & $showReaderControls
    })

    $favoriteButton.Add_Click({
        param($sender, $eventArgs)
        & $toggleFavorite
        & $showReaderControls
    })

    $readerWindow.Add_KeyDown({
        param($sender, $eventArgs)

        & $showReaderControls

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            $readerWindow.Close()
            $eventArgs.Handled = $true
            return
        }

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Home) {
            & $loadPage 0
            $eventArgs.Handled = $true
            return
        }

        $mods = [System.Windows.Input.Keyboard]::Modifiers
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::F -and $mods -eq [System.Windows.Input.ModifierKeys]::None) {
            & $toggleFavorite
            $eventArgs.Handled = $true
            return
        }

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Right -or
            $eventArgs.Key -eq [System.Windows.Input.Key]::Down -or
            $eventArgs.Key -eq [System.Windows.Input.Key]::PageDown -or
            $eventArgs.Key -eq [System.Windows.Input.Key]::Space) {
            & $loadPage ($state.CurrentIndex + 1)
            $eventArgs.Handled = $true
            return
        }

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Left -or
            $eventArgs.Key -eq [System.Windows.Input.Key]::Up -or
            $eventArgs.Key -eq [System.Windows.Input.Key]::PageUp) {
            & $loadPage ($state.CurrentIndex - 1)
            $eventArgs.Handled = $true
        }
    })

    $readerWindow.Add_MouseMove({
        param($sender, $eventArgs)
        & $showReaderControls
    })

    $readerWindow.Add_MouseWheel({
        param($sender, $eventArgs)

        if ($eventArgs.Delta -gt 0) {
            & $setZoom ($state.Zoom * 1.1)
        }
        else {
            & $setZoom ($state.Zoom / 1.1)
        }
        & $showReaderControls
        $eventArgs.Handled = $true
    })

    & $setAutoPlayInterval $state.AutoPlayInterval
    & $setZoom $state.Zoom
    & $updatePlayButton
    & $updateFavoriteButton
    & $loadPage $state.CurrentIndex
    & $showReaderControls

    $readerWindow.ShowDialog() | Out-Null
}

function Get-LibraryItems {
    $library = Get-LibraryData
    return @($library.items)
}

function Get-RecognizingItems {
    $library = Get-LibraryData
    return @($library.items | Where-Object { Item-HasCategory $_ $RecognizingCategory })
}

function ConvertTo-ProcessArgument {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value.Replace('"', '\"')) + '"'
}

function Add-StatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] $Message"
    $StatusLines.Add($line) | Out-Null
    $needsFullRewrite = $false
    while ($StatusLines.Count -gt $StatusMaxLines) {
        $StatusLines.RemoveAt(0)
        $needsFullRewrite = $true
    }
    if ($needsFullRewrite) {
        $StatusConsole.Text = ([string]::Join([Environment]::NewLine, $StatusLines) + [Environment]::NewLine)
    }
    else {
        $StatusConsole.AppendText($line + [Environment]::NewLine)
    }
    $StatusConsole.ScrollToEnd()
}

function Show-OcrSetupDialog {
    $message = "mangaga 需要本地 OCR 才能从封面或样张识别作品名。OCR 使用 PaddleOCR，在本机运行，不会上传图片。`n`n首次使用需要安装 Python 依赖并初始化模型文件，模型会缓存在软件 data 目录内。"
    return Show-ChoiceDialog -Title "OCR 初始化" -Message $message -Choices @(
        [pscustomobject]@{ Text = "初始化 OCR"; Value = "initialize"; Primary = $true },
        [pscustomobject]@{ Text = "稍后再说"; Value = "later"; Primary = $false },
        [pscustomobject]@{ Text = "不使用 OCR"; Value = "disable"; Primary = $false }
    )
}

function Get-OcrStatus {
    param(
        [bool]$Initialize = $false
    )

    $arguments = @($ScannerPath, "ocr-status", "--data-dir", $DataDir)
    if ($Initialize) {
        $arguments += "--initialize"
    }
    return Invoke-ScannerJson -Arguments $arguments -ErrorCaption "检查OCR失败"
}

function Show-OcrInstallInstructions {
    param($Status)

    $command = ""
    if ($null -ne $Status) {
        $command = [string]$Status.installCommand
    }
    if ([string]::IsNullOrWhiteSpace($command)) {
        $command = "`"$PythonPath`" -m pip install paddleocr paddlepaddle"
    }
    try {
        [System.Windows.Clipboard]::SetText($command)
    }
    catch {
    }
    Show-AppMessage -Caption "需要安装 OCR" -Image ([System.Windows.MessageBoxImage]::Information) -Message ("未检测到 PaddleOCR。请先运行以下命令安装，命令已复制到剪贴板：`n`n{0}" -f $command)
}

function Ensure-OcrReadyForTitleRecognition {
    $mode = [string](Get-AppSetting -Name "ocrMode" -Default "")
    if ($mode -eq "ready") {
        return $true
    }
    if ($mode -eq "disabled") {
        $enableAgain = Confirm-AppMessage -Caption "OCR 已禁用" -Message "OCR 已禁用。要重新显示 OCR 初始化选项吗？"
        if ($enableAgain) {
            Set-AppSetting -Name "ocrMode" -Value ""
        }
        else {
            Add-StatusLine -Message "作品名识别：OCR 已禁用。"
            return $false
        }
    }

    $choice = Show-OcrSetupDialog
    if ($choice -eq "disable") {
        Set-AppSetting -Name "ocrMode" -Value "disabled"
        Add-StatusLine -Message "作品名识别：已设置为不使用 OCR。"
        return $false
    }
    if ($choice -ne "initialize") {
        Set-AppSetting -Name "ocrMode" -Value "later"
        Add-StatusLine -Message "作品名识别：已暂缓 OCR 初始化。"
        return $false
    }

    Add-StatusLine -Message "OCR：正在检查并初始化 PaddleOCR。"
    $status = Get-OcrStatus -Initialize $true
    if ($null -eq $status) {
        return $false
    }
    if ([bool]$status.available -and [bool]$status.initialized) {
        Set-AppSetting -Name "ocrMode" -Value "ready"
        Add-StatusLine -Message "OCR：PaddleOCR 已初始化完成。"
        Show-AppMessage -Caption "OCR 初始化" -Message "OCR 初始化完成，可以开始识别作品名。"
        return $true
    }
    if (-not [bool]$status.installed) {
        Set-AppSetting -Name "ocrMode" -Value "later"
        Show-OcrInstallInstructions -Status $status
        return $false
    }

    $message = [string]$status.message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string]$status.error
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "OCR 初始化失败，详细信息已写入日志。"
    }
    Write-AppLog -Message "OCR 初始化失败" -Detail ([string]$status.error)
    Show-AppMessage -Caption "OCR 初始化失败" -Image ([System.Windows.MessageBoxImage]::Warning) -Message $message
    return $false
}

function Show-TagTranslationSetupDialog {
    $message = "首次使用 Tag 翻译时需要选择翻译方式。`n`n$EhTagTranslationNoticeText"
    return Show-ChoiceDialog -Title "Tag 翻译设置" -Message $message -Choices @(
        [pscustomobject]@{ Text = "下载翻译库"; Value = "download"; Primary = $true },
        [pscustomobject]@{ Text = "使用在线翻译"; Value = "online"; Primary = $false },
        [pscustomobject]@{ Text = "不翻译"; Value = "none"; Primary = $false }
    )
}

function Get-EhTagTranslationStatus {
    return Invoke-ScannerJson -Arguments @($ScannerPath, "ehtag-translation-status", "--data-dir", $DataDir) -ErrorCaption "检查Tag翻译库失败"
}

function Ensure-TagTranslationPreference {
    $mode = [string](Get-AppSetting -Name "tagTranslationMode" -Default "")
    $status = Get-EhTagTranslationStatus
    if ($null -eq $status) {
        return $false
    }

    if ([bool]$status.available) {
        if ([string]::IsNullOrWhiteSpace($mode)) {
            Set-AppSetting -Name "tagTranslationMode" -Value "ehtag"
        }
        return $true
    }

    if ($mode -eq "online" -or $mode -eq "none") {
        return $true
    }

    $choice = Show-TagTranslationSetupDialog
    if ($choice -eq "online") {
        Set-AppSetting -Name "tagTranslationMode" -Value "online"
        Add-StatusLine -Message "Tag翻译：已设置为使用在线翻译。"
        return $true
    }
    if ($choice -eq "none") {
        Set-AppSetting -Name "tagTranslationMode" -Value "none"
        Add-StatusLine -Message "Tag翻译：已设置为不翻译。"
        return $true
    }
    if ($choice -ne "download") {
        return $false
    }

    Add-StatusLine -Message "Tag翻译：正在下载 EhTagTranslation 翻译库。"
    $download = Invoke-ScannerJson -Arguments @($ScannerPath, "download-ehtag-translation", "--data-dir", $DataDir) -ErrorCaption "下载Tag翻译库失败"
    if ($null -eq $download) {
        return $false
    }
    if ([bool]$download.available) {
        Set-AppSetting -Name "tagTranslationMode" -Value "ehtag"
        Add-StatusLine -Message ("Tag翻译：EhTagTranslation 已保存到 {0}" -f ([string]$download.path))
        return $true
    }

    Show-AppMessage -Caption "Tag翻译库下载失败" -Image ([System.Windows.MessageBoxImage]::Warning) -Message "未能下载 EhTagTranslation 翻译库，详细信息已写入日志。"
    return $false
}

function Get-TagTranslationModeForProcess {
    $mode = [string](Get-AppSetting -Name "tagTranslationMode" -Default "")
    if ($mode -eq "online" -or $mode -eq "none") {
        return $mode
    }
    return "ehtag"
}

function Merge-AddProgressItemsIntoLibrary {
    param(
        [object[]]$Items
    )

    if (-not $LibraryLoaded -or $null -eq $Items -or $Items.Count -eq 0) {
        return $false
    }

    $nextItems = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in @($AllLibraryItems)) {
        $nextItems.Add($item) | Out-Null
    }

    $changed = $false
    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }
        $itemId = ([string]$item.id).Trim()
        if ([string]::IsNullOrWhiteSpace($itemId)) {
            continue
        }
        if ($AllLibraryItemById.ContainsKey($itemId)) {
            continue
        }

        $nextItems.Add($item) | Out-Null
        $Script:AllLibraryItemById[$itemId] = $item
        $changed = $true
    }

    if (-not $changed) {
        return $false
    }

    $Script:AllLibraryItems = $nextItems.ToArray()
    return $true
}

function Request-AddVisualRefresh {
    param(
        [bool]$Force = $false
    )

    if (-not $LibraryLoaded) {
        return
    }

    $now = Get-Date
    $elapsedMs = if ($AddLastVisualRefreshAt -eq [DateTime]::MinValue) { [double]::PositiveInfinity } else { ($now - $AddLastVisualRefreshAt).TotalMilliseconds }
    if (-not $Force -and $elapsedMs -lt 1000) {
        $Script:AddPendingVisualRefresh = $true
        return
    }

    $Script:AddPendingVisualRefresh = $false
    $Script:AddLastVisualRefreshAt = $now
    Refresh-CurrentLibraryItemsFromAll
    Render-ShelfWindow -Force:$true
    Update-RecognitionBar
}

function Flush-PendingAddVisualRefresh {
    if (-not $AddPendingVisualRefresh) {
        return
    }
    Request-AddVisualRefresh
}

function Read-AddProgress {
    if ([string]::IsNullOrWhiteSpace($AddProgressPath) -or -not (Test-Path -LiteralPath $AddProgressPath)) {
        return $false
    }

    $text = ""
    try {
        $stream = [System.IO.File]::Open($AddProgressPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $stream.Seek($AddProgressPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                $text = $reader.ReadToEnd()
                $Script:AddProgressPosition = [int64]$stream.Position
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $false
    }

    if ([string]::IsNullOrEmpty($text)) {
        return $false
    }

    $combined = $AddProgressRemainder + $text
    $endsWithNewLine = $combined.EndsWith("`n")
    $parts = $combined -split '\r?\n'
    if ($endsWithNewLine) {
        $Script:AddProgressRemainder = ""
        $lines = @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        $Script:AddProgressRemainder = [string]$parts[-1]
        if ($parts.Count -le 1) {
            return $false
        }
        $lines = @($parts[0..($parts.Count - 2)] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $progressItems = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in $lines) {
        try {
            $event = $line | ConvertFrom-Json
        }
        catch {
            continue
        }

        $message = [string]$event.message
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            Add-StatusLine -Message $message
        }

        if ([string]$event.type -eq "added" -or [string]$event.type -eq "needs_password") {
            if ($null -ne $event.item) {
                $progressItems.Add($event.item) | Out-Null
            }
        }
    }

    return (Merge-AddProgressItemsIntoLibrary -Items $progressItems.ToArray())
}

function Read-TagProgress {
    if ([string]::IsNullOrWhiteSpace($TagProgressPath) -or -not (Test-Path -LiteralPath $TagProgressPath)) {
        return $false
    }

    $text = ""
    try {
        $stream = [System.IO.File]::Open($TagProgressPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $stream.Seek($TagProgressPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                $text = $reader.ReadToEnd()
                $Script:TagProgressPosition = [int64]$stream.Position
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $false
    }

    if ([string]::IsNullOrEmpty($text)) {
        return $false
    }

    $combined = $TagProgressRemainder + $text
    $endsWithNewLine = $combined.EndsWith("`n")
    $parts = $combined -split '\r?\n'
    if ($endsWithNewLine) {
        $Script:TagProgressRemainder = ""
        $lines = @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        $Script:TagProgressRemainder = [string]$parts[-1]
        if ($parts.Count -le 1) {
            return $false
        }
        $lines = @($parts[0..($parts.Count - 2)] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $sawEvent = $false
    foreach ($line in $lines) {
        try {
            $event = $line | ConvertFrom-Json
        }
        catch {
            continue
        }

        $message = [string]$event.message
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            Add-StatusLine -Message $message
            $sawEvent = $true
        }
    }

    return $sawEvent
}

function Stop-TagProcess {
    if ($TagTimer) {
        $TagTimer.Stop()
    }

    if ($null -ne $TagProcess -and -not $TagProcess.HasExited) {
        try {
            $TagProcess.Kill()
        }
        catch {
        }
    }

    if ($null -ne $TagProcess) {
        $TagProcess.Dispose()
    }

    $Script:TagProcess = $null
    $Script:TagRunning = $false
    $Script:TagResultPath = ""
    $Script:TagProgressPath = ""
    $Script:TagProgressPosition = [int64]0
    $Script:TagProgressRemainder = ""
    $Script:TagBatchCount = 0
}

function Complete-TagProcess {
    if (-not $TagRunning -or $null -eq $TagProcess) {
        return
    }

    Read-TagProgress | Out-Null

    if (-not $TagProcess.HasExited) {
        return
    }

    Read-TagProgress | Out-Null

    $process = $TagProcess
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $stderr = ""
    try {
        $stderr = $process.StandardError.ReadToEnd().Trim()
    }
    catch {
        $stderr = ""
    }
    $process.Dispose()

    $resultPath = $TagResultPath
    $progressPath = $TagProgressPath
    $showSummary = $TagShowSummary

    $Script:TagProcess = $null
    $Script:TagRunning = $false
    $Script:TagResultPath = ""
    $Script:TagProgressPath = ""
    $Script:TagProgressPosition = [int64]0
    $Script:TagProgressRemainder = ""
    $Script:TagBatchCount = 0
    $Script:TagShowSummary = $false
    $TagTimer.Stop()

    if ($exitCode -ne 0) {
        $message = $stderr
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "Tag 识别进程异常退出。"
        }
        Add-StatusLine -Message "Tag识别失败"
        Show-AppMessage -Message $message -Caption "Tag识别失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($showSummary) {
                Show-TagClassificationSummary $result
            }
        }
        catch {
            Show-AppMessage -Message "Tag识别结果无法解析：$($_.Exception.Message)" -Caption "Tag识别失败" -Image ([System.Windows.MessageBoxImage]::Error)
        }
    }
    else {
        Show-AppMessage -Message "Tag识别进程结束，但没有生成结果文件。" -Caption "Tag识别失败" -Image ([System.Windows.MessageBoxImage]::Warning)
    }

    if (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            Remove-Item -LiteralPath $resultPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($progressPath) -and (Test-Path -LiteralPath $progressPath)) {
        try {
            Remove-Item -LiteralPath $progressPath -Force
        }
        catch {
        }
    }

    Render-Library
}

function Read-DuplicateProgress {
    if ([string]::IsNullOrWhiteSpace($DuplicateProgressPath) -or -not (Test-Path -LiteralPath $DuplicateProgressPath)) {
        return $false
    }

    $text = ""
    try {
        $stream = [System.IO.File]::Open($DuplicateProgressPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $stream.Seek($DuplicateProgressPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                $text = $reader.ReadToEnd()
                $Script:DuplicateProgressPosition = [int64]$stream.Position
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $false
    }

    if ([string]::IsNullOrEmpty($text)) {
        return $false
    }

    $combined = $DuplicateProgressRemainder + $text
    $endsWithNewLine = $combined.EndsWith("`n")
    $parts = $combined -split '\r?\n'
    if ($endsWithNewLine) {
        $Script:DuplicateProgressRemainder = ""
        $lines = @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        $Script:DuplicateProgressRemainder = [string]$parts[-1]
        if ($parts.Count -le 1) {
            return $false
        }
        $lines = @($parts[0..($parts.Count - 2)] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $sawEvent = $false
    foreach ($line in $lines) {
        try {
            $event = $line | ConvertFrom-Json
        }
        catch {
            continue
        }

        $message = [string]$event.message
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            Add-StatusLine -Message $message
            $sawEvent = $true
        }
    }

    return $sawEvent
}

function Stop-DuplicateProcess {
    if ($DuplicateTimer) {
        $DuplicateTimer.Stop()
    }

    if ($null -ne $DuplicateProcess -and -not $DuplicateProcess.HasExited) {
        try {
            $DuplicateProcess.Kill()
        }
        catch {
        }
    }

    if ($null -ne $DuplicateProcess) {
        $DuplicateProcess.Dispose()
    }

    $Script:DuplicateProcess = $null
    $Script:DuplicateRunning = $false
    $Script:DuplicateResultPath = ""
    if (-not [string]::IsNullOrWhiteSpace($DuplicateIdsPath) -and (Test-Path -LiteralPath $DuplicateIdsPath)) {
        try {
            Remove-Item -LiteralPath $DuplicateIdsPath -Force
        }
        catch {
        }
    }
    $Script:DuplicateIdsPath = ""
    $Script:DuplicateProgressPath = ""
    $Script:DuplicateProgressPosition = [int64]0
    $Script:DuplicateProgressRemainder = ""
    $Script:DuplicateBatchCount = 0
}

function Complete-DuplicateProcess {
    if (-not $DuplicateRunning -or $null -eq $DuplicateProcess) {
        return
    }

    Read-DuplicateProgress | Out-Null

    if (-not $DuplicateProcess.HasExited) {
        return
    }

    Read-DuplicateProgress | Out-Null

    $process = $DuplicateProcess
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $stderr = ""
    try {
        $stderr = $process.StandardError.ReadToEnd().Trim()
    }
    catch {
        $stderr = ""
    }
    $process.Dispose()

    $resultPath = $DuplicateResultPath
    $idsPath = $DuplicateIdsPath
    $progressPath = $DuplicateProgressPath

    $Script:DuplicateProcess = $null
    $Script:DuplicateRunning = $false
    $Script:DuplicateResultPath = ""
    $Script:DuplicateIdsPath = ""
    $Script:DuplicateProgressPath = ""
    $Script:DuplicateProgressPosition = [int64]0
    $Script:DuplicateProgressRemainder = ""
    $Script:DuplicateBatchCount = 0
    $DuplicateTimer.Stop()

    $shouldSwitchToDuplicates = $false
    if ($exitCode -ne 0) {
        $message = $stderr
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "查重进程异常退出。"
        }
        Add-StatusLine -Message "查重失败"
        Show-AppMessage -Message $message -Caption "查重失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $summary = $result.summary
            $exactGroups = 0
            $similarGroups = 0
            $seriesGroups = 0
            $duplicateItems = 0
            $similarItems = 0
            $seriesItems = 0
            if ($null -ne $summary) {
                if ($null -ne $summary.exactGroups) {
                    $exactGroups = [int]$summary.exactGroups
                }
                if ($null -ne $summary.similarGroups) {
                    $similarGroups = [int]$summary.similarGroups
                }
                if ($null -ne $summary.seriesGroups) {
                    $seriesGroups = [int]$summary.seriesGroups
                }
                if ($null -ne $summary.duplicateItems) {
                    $duplicateItems = [int]$summary.duplicateItems
                }
                elseif ($null -ne $summary.exactItemIds) {
                    $duplicateItems = @($summary.exactItemIds).Count
                }
                if ($null -ne $summary.similarItems) {
                    $similarItems = [int]$summary.similarItems
                }
                elseif ($null -ne $summary.similarItemIds) {
                    $similarItems = @($summary.similarItemIds).Count
                }
                if ($null -ne $summary.seriesItems) {
                    $seriesItems = [int]$summary.seriesItems
                }
                elseif ($null -ne $summary.seriesItemIds) {
                    $seriesItems = @($summary.seriesItemIds).Count
                }
            }
            if ($duplicateItems -eq 0 -and $null -ne $result.groups) {
                $exactIds = New-Object 'System.Collections.Generic.HashSet[string]'
                foreach ($group in @($result.groups)) {
                    if ([string]$group.kind -ne "exact") {
                        continue
                    }
                    foreach ($itemId in @($group.itemIds)) {
                        $value = ([string]$itemId).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($value)) {
                            $exactIds.Add($value) | Out-Null
                        }
                    }
                }
                $duplicateItems = $exactIds.Count
            }
            Add-StatusLine -Message "查重结果：完全重复 $exactGroups 组，重复项 $duplicateItems 本；相似版本 $similarGroups 组，涉及 $similarItems 本；连载/系列 $seriesGroups 组，涉及 $seriesItems 本"
            $shouldSwitchToDuplicates = $duplicateItems -gt 0
        }
        catch {
            Show-AppMessage -Message "查重结果无法解析：$($_.Exception.Message)" -Caption "查重失败" -Image ([System.Windows.MessageBoxImage]::Error)
        }
    }
    else {
        Show-AppMessage -Message "查重进程结束，但没有生成结果文件。" -Caption "查重失败" -Image ([System.Windows.MessageBoxImage]::Warning)
    }

    if (-not [string]::IsNullOrWhiteSpace($progressPath) -and (Test-Path -LiteralPath $progressPath)) {
        try {
            Remove-Item -LiteralPath $progressPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($idsPath) -and (Test-Path -LiteralPath $idsPath)) {
        try {
            Remove-Item -LiteralPath $idsPath -Force
        }
        catch {
        }
    }

    Refresh-DuplicateItemCache
    if ($shouldSwitchToDuplicates) {
        $Script:CurrentCategory = $DuplicateCategory
        Clear-Selection
    }
    Render-Library -Reload:$false
}

function Complete-RemoveProcess {
    if (-not $RemoveRunning -or $null -eq $RemoveProcess) {
        return
    }

    if (-not $RemoveProcess.HasExited) {
        return
    }

    $process = $RemoveProcess
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $stderr = ""
    try {
        $stderr = $process.StandardError.ReadToEnd().Trim()
    }
    catch {
        $stderr = ""
    }
    $process.Dispose()

    $resultPath = $RemoveResultPath
    $idsPath = $RemoveIdsPath
    $batchCount = $RemoveBatchCount
    [string[]]$currentIds = @($RemoveCurrentIds)

    $Script:RemoveProcess = $null
    $Script:RemoveRunning = $false
    $Script:RemoveResultPath = ""
    $Script:RemoveIdsPath = ""
    $Script:RemoveBatchCount = 0
    $Script:RemoveCurrentIds = @()
    $RemoveTimer.Stop()

    if ($exitCode -ne 0) {
        $detail = "ExitCode: $exitCode`r`nSTDERR:`r`n$stderr"
        Write-AppLog -Message "后台移除：扫描器异常退出" -Detail $detail
        $userMessage = Get-UserFacingErrorMessage -RawMessage $stderr -Fallback "从书架移除失败，详情已记录到日志。"
        Add-StatusLine -Message "从书架移除失败：$userMessage"
        Show-AppMessage -Message $userMessage -Caption "删除失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $removedCount = @($result.removed).Count
            if ($removedCount -eq 0) {
                $removedCount = $batchCount
            }

            $cleanupErrors = @($result.cleanupErrors)
            if ($cleanupErrors.Count -gt 0) {
                $detail = $cleanupErrors | ConvertTo-Json -Depth 6
                Write-AppLog -Message "后台移除：部分缓存清理失败" -Detail $detail
                Add-StatusLine -Message "书架移除完成：$removedCount 本；部分缓存稍后自动清理"
            }
            else {
                Add-StatusLine -Message "书架移除完成：$removedCount 本"
            }
            if ($currentIds.Count -gt 0 -and -not (Clear-PendingRemovals -Ids $currentIds)) {
                Add-StatusLine -Message "待完成移除记录清理失败；下次启动会重新核对"
            }
        }
        catch {
            $detail = $_.Exception.ToString()
            Write-AppLog -Message "后台移除：结果文件无法解析" -Detail $detail
            Add-StatusLine -Message "书架移除完成；结果解析失败，详情已记录"
        }
    }
    else {
        Write-AppLog -Message "后台移除：未生成结果文件" -Detail "ResultPath: $resultPath"
        Add-StatusLine -Message "书架移除进程结束，但没有生成结果文件。"
    }

    if (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            Remove-Item -LiteralPath $resultPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($idsPath) -and (Test-Path -LiteralPath $idsPath)) {
        try {
            Remove-Item -LiteralPath $idsPath -Force
        }
        catch {
        }
    }

    if ($RemovePendingIds.Count -gt 0) {
        [string[]]$pendingIds = @($RemovePendingIds | ForEach-Object { [string]$_ })
        $RemovePendingIds.Clear()
        Start-RemoveWorker -Ids $pendingIds | Out-Null
    }
}

function Start-PendingRemovalRecovery {
    [string[]]$pendingIds = Get-PendingRemovalIdArray
    if ($pendingIds.Count -eq 0) {
        return
    }

    Add-StatusLine -Message "发现未完成移除任务：$($pendingIds.Count) 本，正在后台继续处理"
    Queue-RemoveWorkerStart -Ids $pendingIds
}

function Update-RecognitionBar {
    if ($CurrentCategory -eq $RecognizingCategory) {
        $RecognitionBar.Visibility = "Visible"
    }
    else {
        $RecognitionBar.Visibility = "Collapsed"
        return
    }

    $queueCount = @($LibraryItems).Count
    $maximum = if ($RecognitionTotal -gt 0) { $RecognitionTotal } else { [Math]::Max(1, $queueCount) }
    if ($RecognitionRunning -and $RecognitionItemTotal -gt 0) {
        $RecognitionProgress.Maximum = [Math]::Max(1, $RecognitionItemTotal)
        $RecognitionProgress.Value = [Math]::Min($RecognitionProgress.Maximum, [Math]::Max(0, $RecognitionItemProgress))
        $RecognitionProgress.IsIndeterminate = $false
    }
    else {
        $RecognitionProgress.Maximum = [Math]::Max(1, $maximum)
        $RecognitionProgress.Value = [Math]::Min($RecognitionProgress.Maximum, [Math]::Max(0, $RecognitionCompleted))
        $RecognitionProgress.IsIndeterminate = $RecognitionRunning
    }

    $detailText = ""
    if (-not [string]::IsNullOrWhiteSpace($RecognitionDetailText)) {
        $detailText = "  $RecognitionDetailText"
    }

    if ($RecognitionRunning) {
        if ($RecognitionPaused) {
            $RecognitionStatusText.Text = "当前完成后暂停：$RecognitionCurrentName  $RecognitionCompleted/$RecognitionTotal$detailText"
        }
        else {
            $RecognitionStatusText.Text = "正在识别：$RecognitionCurrentName  $RecognitionCompleted/$RecognitionTotal$detailText"
        }
    }
    elseif ($RecognitionLastStatus -eq "paused") {
        $RecognitionStatusText.Text = "已暂停：$RecognitionCompleted/$RecognitionTotal"
    }
    elseif ($RecognitionLastStatus -eq "done") {
        $RecognitionStatusText.Text = "识别完成"
    }
    elseif ($RecognitionLastStatus -eq "error") {
        $RecognitionStatusText.Text = "识别失败"
    }
    elseif ($queueCount -gt 0) {
        $RecognitionStatusText.Text = "待识别：$queueCount 本"
    }
    else {
        $RecognitionStatusText.Text = "没有待识别漫画"
    }

    $RecognitionStartButton.IsEnabled = (($queueCount -gt 0 -and -not $RecognitionRunning) -or ($RecognitionRunning -and $RecognitionPaused))
    $RecognitionPauseButton.IsEnabled = ($RecognitionRunning -and -not $RecognitionPaused)
}

function Start-TitleRecognitionQueue {
    if ($RecognitionRunning) {
        if ($RecognitionPaused -and -not [string]::IsNullOrWhiteSpace($RecognitionPausePath) -and (Test-Path -LiteralPath $RecognitionPausePath)) {
            Remove-Item -LiteralPath $RecognitionPausePath -Force
        }
        $Script:RecognitionPaused = $false
        Update-RecognitionBar
        return
    }

    $queue = @(Get-RecognizingItems)
    if ($queue.Count -eq 0) {
        Update-RecognitionBar
        return
    }

    if (-not (Ensure-OcrReadyForTitleRecognition)) {
        Update-RecognitionBar
        return
    }

    $Script:RecognitionPaused = $false
    $Script:RecognitionTotal = $queue.Count
    $Script:RecognitionCompleted = 0
    $Script:RecognitionCurrentId = ""
    $Script:RecognitionCurrentName = ""
    $Script:RecognitionLastStatus = ""
    $Script:RecognitionDetailText = ""
    $Script:RecognitionItemProgress = 0
    $Script:RecognitionItemTotal = 0

    $workerDir = Join-Path $DataDir "recognition-worker"
    New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
    $runId = [System.Guid]::NewGuid().ToString("N")
    $Script:RecognitionProgressPath = Join-Path $workerDir "$runId.progress.json"
    $Script:RecognitionPausePath = Join-Path $workerDir "$runId.pause"
    if (Test-Path -LiteralPath $RecognitionProgressPath) {
        Remove-Item -LiteralPath $RecognitionProgressPath -Force
    }
    if (Test-Path -LiteralPath $RecognitionPausePath) {
        Remove-Item -LiteralPath $RecognitionPausePath -Force
    }

    $ids = @($queue | ForEach-Object { [string]$_.id })
    $arguments = @($ScannerPath, "recognize-batch", "--data-dir", $DataDir, "--progress-file", $RecognitionProgressPath, "--pause-file", $RecognitionPausePath)
    $arguments += $ids

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonPath
    $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        $Script:RecognitionProcess = $process
        $Script:RecognitionRunning = $true
        $RecognitionTimer.Start()
        Add-StatusLine -Message "已启动作品名识别：$($queue.Count) 本"
    }
    catch {
        $Script:RecognitionRunning = $false
        $Script:RecognitionProcess = $null
        Show-AppMessage -Message "启动识别失败：$($_.Exception.Message)" -Caption "识别失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }

    Update-RecognitionBar
}

function Pause-TitleRecognitionQueue {
    $Script:RecognitionPaused = $true
    if (-not [string]::IsNullOrWhiteSpace($RecognitionPausePath)) {
        New-Item -ItemType File -Force -Path $RecognitionPausePath | Out-Null
    }
    Add-StatusLine -Message "已请求暂停作品名识别"
    Update-RecognitionBar
}

function Read-RecognitionProgress {
    if ([string]::IsNullOrWhiteSpace($RecognitionProgressPath) -or -not (Test-Path -LiteralPath $RecognitionProgressPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $RecognitionProgressPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Apply-RecognitionProgress($ProgressData) {
    if ($null -eq $ProgressData) {
        return $false
    }

    $oldCompleted = $RecognitionCompleted
    $oldStatus = $RecognitionLastStatus

    if ($null -ne $ProgressData.total) {
        [int]::TryParse([string]$ProgressData.total, [ref]$Script:RecognitionTotal) | Out-Null
    }
    if ($null -ne $ProgressData.completed) {
        [int]::TryParse([string]$ProgressData.completed, [ref]$Script:RecognitionCompleted) | Out-Null
    }
    if ($null -ne $ProgressData.currentId) {
        $Script:RecognitionCurrentId = [string]$ProgressData.currentId
    }
    if ($null -ne $ProgressData.currentName) {
        $Script:RecognitionCurrentName = [string]$ProgressData.currentName
    }
    if ($null -ne $ProgressData.status) {
        $Script:RecognitionLastStatus = [string]$ProgressData.status
    }
    if ($null -ne $ProgressData.itemProgress) {
        [int]::TryParse([string]$ProgressData.itemProgress, [ref]$Script:RecognitionItemProgress) | Out-Null
    }
    if ($null -ne $ProgressData.itemTotal) {
        [int]::TryParse([string]$ProgressData.itemTotal, [ref]$Script:RecognitionItemTotal) | Out-Null
    }
    if ($null -ne $ProgressData.message) {
        $Script:RecognitionDetailText = [string]$ProgressData.message
    }

    return ($oldCompleted -ne $RecognitionCompleted -or $oldStatus -ne $RecognitionLastStatus)
}

function Stop-RecognitionProcess {
    $Script:RecognitionPaused = $true
    if ($RecognitionTimer) {
        $RecognitionTimer.Stop()
    }

    if ($null -ne $RecognitionProcess -and -not $RecognitionProcess.HasExited) {
        try {
            $RecognitionProcess.Kill()
        }
        catch {
        }
    }

    if ($null -ne $RecognitionProcess) {
        $RecognitionProcess.Dispose()
    }

    $Script:RecognitionProcess = $null
    $Script:RecognitionRunning = $false
}

function Complete-RecognitionProcess {
    $progressData = Read-RecognitionProgress
    $changed = Apply-RecognitionProgress $progressData
    if ($changed) {
        Render-Library
    }
    else {
        Update-RecognitionBar
    }

    if ($null -eq $RecognitionProcess -or -not $RecognitionProcess.HasExited) {
        return
    }

    $process = $RecognitionProcess
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $exitCode = $process.ExitCode
    $process.Dispose()

    $Script:RecognitionProcess = $null
    $Script:RecognitionRunning = $false
    $progressData = Read-RecognitionProgress
    Apply-RecognitionProgress $progressData | Out-Null

    if ($exitCode -ne 0) {
        $Script:RecognitionPaused = $true
        $message = ($stderr + [Environment]::NewLine + $stdout).Trim()
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "识别进程异常退出。"
        }
        Add-StatusLine -Message "作品名识别失败"
        Show-AppMessage -Message $message -Caption "识别失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    elseif ($progressData -and [string]$progressData.status -eq "error") {
        $Script:RecognitionPaused = $true
        $message = [string]$progressData.message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "作品名识别失败。"
        }
        Add-StatusLine -Message "作品名识别失败：$message"
        Show-AppMessage -Message $message -Caption "识别失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    elseif ($progressData -and [string]$progressData.status -eq "done") {
        Add-StatusLine -Message "作品名识别完成"
    }
    elseif ($progressData -and [string]$progressData.status -eq "paused") {
        Add-StatusLine -Message "作品名识别已暂停"
    }

    $RecognitionTimer.Stop()
    Render-Library
    Update-RecognitionBar
}

$RecognitionTimer = New-Object System.Windows.Threading.DispatcherTimer
$RecognitionTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$RecognitionTimer.Add_Tick({
    Complete-RecognitionProcess
})

$RecognitionStartButton.Add_Click({
    Start-TitleRecognitionQueue
})

$RecognitionPauseButton.Add_Click({
    Pause-TitleRecognitionQueue
})

function Render-Library {
    param(
        [bool]$Reload = $true,
        [bool]$PreservePage = $false,
        [bool]$RefreshMetadata = $true
    )

    $Script:CardById = @{}
    Clear-ShelfBuildQueue
    Clear-ShelfPreheatQueue

    if ($Reload -or -not $LibraryLoaded) {
        $library = Get-LibraryData
        $Script:LibraryCategories = @($library.categories)
        $allItems = @($library.items)
        $Script:AllLibraryItems = $allItems
        Rebuild-AllLibraryItemIndex
        $Script:LibraryLoaded = $true
    }
    else {
        $allItems = @($AllLibraryItems)
    }

    $metadataNeedsRefresh = ($Reload -or $RefreshMetadata -or $ShelfMetadataDirty -or $CategoryItemsByName.Count -eq 0)
    if ($metadataNeedsRefresh) {
        Refresh-DuplicateItemCache
        Refresh-VersionGroupCache
        Rebuild-CategoryCountCache
    }

    $categoryStillExists = Is-SystemCategoryName $CurrentCategory
    if (-not $categoryStillExists) {
        foreach ($category in $LibraryCategories) {
            if ([string]$category -eq $CurrentCategory) {
                $categoryStillExists = $true
                break
            }
        }
    }
    if (-not $categoryStillExists) {
        $Script:CurrentCategory = "全部"
    }

    $categoryChanged = ([string]$ShelfRenderedCategory -ne [string]$CurrentCategory)
    $Script:ShelfRenderedCategory = [string]$CurrentCategory

    if ($metadataNeedsRefresh) {
        Render-Categories
    }
    else {
        Update-CategorySelectionVisuals
    }

    $filteredItems = @(Get-CurrentCategoryItems)
    if ($CurrentCategory -eq $DuplicateCategory) {
        $Script:LibraryItems = @(Apply-LibrarySort -Items $filteredItems)
    }
    else {
        $displayItems = @(Collapse-VersionGroups -Items $filteredItems)
        $Script:LibraryItems = @(Apply-LibrarySort -Items $displayItems)
    }

    $validIds = @{}
    foreach ($item in $LibraryItems) {
        $validIds[[string]$item.id] = $true
    }

    $retainedSelectedIds = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($selectedId in @($SelectedIds)) {
        $selectedKey = ([string]$selectedId).Trim()
        if (-not [string]::IsNullOrWhiteSpace($selectedKey) -and $validIds.ContainsKey($selectedKey)) {
            $retainedSelectedIds.Add($selectedKey) | Out-Null
        }
    }
    $Script:SelectedIds = $retainedSelectedIds

    $Script:ShelfRenderVersion = $Script:ShelfRenderVersion + 1
    $Script:ShelfRenderStartIndex = -1
    $Script:ShelfRenderEndIndex = -1
    if ($categoryChanged -and -not $PreservePage) {
        $ShelfScrollViewer.ScrollToVerticalOffset(0)
    }
    Render-ShelfWindow -Force:$true
    Update-RecognitionBar
}

function Show-ScanResult($Result) {
    $errors = @($Result.errors | Where-Object {
        $message = [string]$_.message
        -not [string]::IsNullOrWhiteSpace($message) -and
            $message -notlike "只支持文件夹和*"
    })
    if ($errors.Count -gt 0) {
        $lines = $errors | Select-Object -First 8 | ForEach-Object {
            if ($_.path) {
                "$($_.path)：$($_.message)"
            }
            else {
                "$($_.message)"
            }
        }
        if ($errors.Count -gt 8) {
            $lines += "另有 $($errors.Count - 8) 个问题未显示。"
        }

        Show-AppMessage -Message ($lines -join [Environment]::NewLine) -Caption "部分项目未能添加" -Image ([System.Windows.MessageBoxImage]::Warning)
    }
}

function Clear-FavoriteFromAddedItems($Result) {
    if ($null -eq $Result -or $null -eq $Result.added) {
        return
    }

    $ids = @($Result.added | ForEach-Object { [string]$_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -eq 0) {
        return
    }

    $arguments = @($ScannerPath, "unassign-category", "--data-dir", $DataDir, "--name", $FavoriteCategory)
    $arguments += $ids
    Invoke-ScannerJson -Arguments $arguments -ErrorCaption "清理新增喜爱状态失败" | Out-Null
}

function Get-AddCandidatePaths {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $archiveExts = @(".zip", ".rar", ".7z")
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $candidates = New-Object 'System.Collections.Generic.List[string]'

    foreach ($rawPath in $Paths) {
        $path = [string]$rawPath
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $path = $path.Trim()
        $shouldAdd = $false
        try {
            if (Test-Path -LiteralPath $path -PathType Container) {
                $shouldAdd = $true
            }
            elseif (Test-Path -LiteralPath $path -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
                $shouldAdd = $archiveExts -contains $ext
            }
            else {
                $shouldAdd = $true
            }
        }
        catch {
            $shouldAdd = $false
        }

        if ($shouldAdd -and $seen.Add($path)) {
            $candidates.Add($path) | Out-Null
        }
    }

    return [string[]]$candidates.ToArray()
}

function Update-AddTitle {
    if ($AddRunning) {
        $queuedText = if ($AddQueue.Count -gt 0) { "，另有 $($AddQueue.Count) 项排队" } else { "" }
        $Window.Title = "mangaga - 后台添加中（$AddBatchCount 项$queuedText）"
    }
    else {
        $Window.Title = "mangaga"
    }
}

function Start-AddQueue {
    if ($AddRunning) {
        Update-AddTitle
        return
    }

    if ($AddQueue.Count -eq 0) {
        Update-AddTitle
        return
    }

    [string[]]$batch = $AddQueue.ToArray()
    $AddQueue.Clear()
    $Script:AddBatchCount = $batch.Count

    $workerDir = Join-Path $DataDir "add-worker"
    New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
    $runId = [System.Guid]::NewGuid().ToString("N")
    $Script:AddResultPath = Join-Path $workerDir "$runId.result.json"
    $Script:AddPathsPath = Join-Path $workerDir "$runId.paths.json"
    $Script:AddProgressPath = Join-Path $workerDir "$runId.progress.jsonl"
    $Script:AddProgressPosition = [int64]0
    $Script:AddProgressRemainder = ""
    $Script:AddPendingVisualRefresh = $false
    $Script:AddLastVisualRefreshAt = [DateTime]::MinValue
    if (Test-Path -LiteralPath $AddResultPath) {
        Remove-Item -LiteralPath $AddResultPath -Force
    }
    if (Test-Path -LiteralPath $AddPathsPath) {
        Remove-Item -LiteralPath $AddPathsPath -Force
    }
    if (Test-Path -LiteralPath $AddProgressPath) {
        Remove-Item -LiteralPath $AddProgressPath -Force
    }

    try {
        ConvertTo-Json -InputObject @($batch) -Depth 2 | Set-Content -LiteralPath $AddPathsPath -Encoding UTF8
    }
    catch {
        $Script:AddResultPath = ""
        $Script:AddPathsPath = ""
        $Script:AddProgressPath = ""
        $Script:AddProgressPosition = [int64]0
        $Script:AddProgressRemainder = ""
        $Script:AddPendingVisualRefresh = $false
        $Script:AddLastVisualRefreshAt = [DateTime]::MinValue
        $Script:AddBatchCount = 0
        Update-AddTitle
        Show-AppMessage -Message "创建批量添加清单失败：$($_.Exception.Message)" -Caption "添加失败" -Image ([System.Windows.MessageBoxImage]::Error)
        return
    }

    $arguments = @($ScannerPath, "add", "--data-dir", $DataDir, "--protect-favorite", "--summary-only", "--output-file", $AddResultPath, "--paths-file", $AddPathsPath, "--progress-file", $AddProgressPath)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonPath
    $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $true
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi

        $process.Start() | Out-Null

        $Script:AddProcess = $process
        $Script:AddRunning = $true
        $AddTimer.Start()
        Add-StatusLine -Message "已启动后台添加：$($batch.Count) 项"
        Update-AddTitle
    }
    catch {
        $Script:AddRunning = $false
        $Script:AddProcess = $null
        if (-not [string]::IsNullOrWhiteSpace($AddPathsPath) -and (Test-Path -LiteralPath $AddPathsPath)) {
            try {
                Remove-Item -LiteralPath $AddPathsPath -Force
            }
            catch {
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($AddResultPath) -and (Test-Path -LiteralPath $AddResultPath)) {
            try {
                Remove-Item -LiteralPath $AddResultPath -Force
            }
            catch {
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($AddProgressPath) -and (Test-Path -LiteralPath $AddProgressPath)) {
            try {
                Remove-Item -LiteralPath $AddProgressPath -Force
            }
            catch {
            }
        }
        $Script:AddResultPath = ""
        $Script:AddPathsPath = ""
        $Script:AddProgressPath = ""
        $Script:AddProgressPosition = [int64]0
        $Script:AddProgressRemainder = ""
        $Script:AddPendingVisualRefresh = $false
        $Script:AddLastVisualRefreshAt = [DateTime]::MinValue
        $Script:AddBatchCount = 0
        Update-AddTitle
        Show-AppMessage -Message "启动添加失败：$($_.Exception.Message)" -Caption "添加失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
}

function Complete-AddProcess {
    if (-not $AddRunning -or $null -eq $AddProcess) {
        return
    }

    $progressChanged = Read-AddProgress
    if ($progressChanged) {
        Request-AddVisualRefresh
    }
    else {
        Flush-PendingAddVisualRefresh
    }

    if (-not $AddProcess.HasExited) {
        Update-AddTitle
        return
    }

    $progressChanged = Read-AddProgress
    if ($progressChanged) {
        Request-AddVisualRefresh -Force:$true
    }
    else {
        Flush-PendingAddVisualRefresh
    }

    $process = $AddProcess
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $stderr = ""
    try {
        $stderr = $process.StandardError.ReadToEnd().Trim()
    }
    catch {
        $stderr = ""
    }
    $process.Dispose()

    $resultPath = $AddResultPath
    $pathsPath = $AddPathsPath
    $progressPath = $AddProgressPath
    $Script:AddProcess = $null
    $Script:AddRunning = $false
    $Script:AddResultPath = ""
    $Script:AddPathsPath = ""
    $Script:AddProgressPath = ""
    $Script:AddProgressPosition = [int64]0
    $Script:AddProgressRemainder = ""
    $Script:AddPendingVisualRefresh = $false
    $Script:AddLastVisualRefreshAt = [DateTime]::MinValue
    $Script:AddBatchCount = 0

    if ($exitCode -ne 0) {
        $message = $stderr
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "扫描器异常退出。"
        }
        Show-AppMessage -Message $message -Caption "添加失败" -Image ([System.Windows.MessageBoxImage]::Error)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Show-ScanResult $result
        }
        catch {
            Show-AppMessage -Message "扫描器返回内容无法解析：$($_.Exception.Message)" -Caption "添加失败" -Image ([System.Windows.MessageBoxImage]::Error)
        }
    }
    elseif ($exitCode -eq 0) {
        Show-AppMessage -Message "添加进程结束，但没有生成结果文件。" -Caption "添加失败" -Image ([System.Windows.MessageBoxImage]::Warning)
    }

    if (-not [string]::IsNullOrWhiteSpace($resultPath) -and (Test-Path -LiteralPath $resultPath)) {
        try {
            Remove-Item -LiteralPath $resultPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($pathsPath) -and (Test-Path -LiteralPath $pathsPath)) {
        try {
            Remove-Item -LiteralPath $pathsPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($progressPath) -and (Test-Path -LiteralPath $progressPath)) {
        try {
            Remove-Item -LiteralPath $progressPath -Force
        }
        catch {
        }
    }

    $SelectedIds.Clear()
    $Script:LastSelectedIndex = -1
    Render-Library

    if ($AddQueue.Count -gt 0) {
        Start-AddQueue
    }
    else {
        $AddTimer.Stop()
        Update-AddTitle
    }
}

function Stop-AddProcess {
    if ($AddTimer) {
        $AddTimer.Stop()
    }

    if ($null -ne $AddProcess -and -not $AddProcess.HasExited) {
        try {
            $AddProcess.Kill()
        }
        catch {
        }
    }

    if ($null -ne $AddProcess) {
        $AddProcess.Dispose()
    }

    if (-not [string]::IsNullOrWhiteSpace($AddResultPath) -and (Test-Path -LiteralPath $AddResultPath)) {
        try {
            Remove-Item -LiteralPath $AddResultPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($AddPathsPath) -and (Test-Path -LiteralPath $AddPathsPath)) {
        try {
            Remove-Item -LiteralPath $AddPathsPath -Force
        }
        catch {
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($AddProgressPath) -and (Test-Path -LiteralPath $AddProgressPath)) {
        try {
            Remove-Item -LiteralPath $AddProgressPath -Force
        }
        catch {
        }
    }

    $Script:AddProcess = $null
    $Script:AddRunning = $false
    $Script:AddResultPath = ""
    $Script:AddPathsPath = ""
    $Script:AddProgressPath = ""
    $Script:AddProgressPosition = [int64]0
    $Script:AddProgressRemainder = ""
    $Script:AddPendingVisualRefresh = $false
    $Script:AddLastVisualRefreshAt = [DateTime]::MinValue
    $Script:AddBatchCount = 0
    $AddQueue.Clear()
}

function Add-Paths {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $validPaths = @(Get-AddCandidatePaths -Paths $Paths)
    if ($validPaths.Count -eq 0) {
        return
    }

    foreach ($path in $validPaths) {
        $AddQueue.Add([string]$path) | Out-Null
    }

    if ($AddRunning) {
        Add-StatusLine -Message "已加入添加队列：$($validPaths.Count) 项"
    }

    Start-AddQueue
}

$AddTimer = New-Object System.Windows.Threading.DispatcherTimer
$AddTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$AddTimer.Add_Tick({
    Complete-AddProcess
})

$TagTimer = New-Object System.Windows.Threading.DispatcherTimer
$TagTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$TagTimer.Add_Tick({
    Complete-TagProcess
})

$DuplicateTimer = New-Object System.Windows.Threading.DispatcherTimer
$DuplicateTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$DuplicateTimer.Add_Tick({
    Complete-DuplicateProcess
})

$RemoveTimer = New-Object System.Windows.Threading.DispatcherTimer
$RemoveTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$RemoveTimer.Add_Tick({
    Complete-RemoveProcess
})

$ShelfBuildTimer = New-Object System.Windows.Threading.DispatcherTimer
$ShelfBuildTimer.Interval = [TimeSpan]::FromMilliseconds(16)
$ShelfBuildTimer.Add_Tick({
    Process-ShelfBuildQueue
})

$ShelfPreheatTimer = New-Object System.Windows.Threading.DispatcherTimer
$ShelfPreheatTimer.Interval = [TimeSpan]::FromMilliseconds(32)
$ShelfPreheatTimer.Add_Tick({
    Process-ShelfPreheatQueue
})

$ShelfScrollRenderTimer = New-Object System.Windows.Threading.DispatcherTimer
$ShelfScrollRenderTimer.Interval = [TimeSpan]::FromMilliseconds(90)
$ShelfScrollRenderTimer.Add_Tick({
    $ShelfScrollRenderTimer.Stop()
    Render-ShelfWindow
})

$ShelfDragSelectTimer = New-Object System.Windows.Threading.DispatcherTimer
$ShelfDragSelectTimer.Interval = [TimeSpan]::FromMilliseconds(32)
$ShelfDragSelectTimer.Add_Tick({
    Invoke-ShelfDragSelectionAutoScroll
})

$Window.Add_DragOver({
    param($sender, $eventArgs)
    if ($eventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $eventArgs.Effects = [System.Windows.DragDropEffects]::Copy
    }
    else {
        $eventArgs.Effects = [System.Windows.DragDropEffects]::None
    }
    $eventArgs.Handled = $true
})

$Window.Add_Drop({
    param($sender, $eventArgs)
    if ($eventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $paths = [string[]]$eventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
        Add-Paths -Paths $paths
    }
    $eventArgs.Handled = $true
})

$Window.Add_KeyDown({
    param($sender, $eventArgs)

    $mods = [System.Windows.Input.Keyboard]::Modifiers
    $ctrl = (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0)

    if ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::A) {
        Select-AllComics
        $eventArgs.Handled = $true
        return
    }

    if ($eventArgs.Key -eq [System.Windows.Input.Key]::Delete) {
        Remove-SelectedComics
        $eventArgs.Handled = $true
        return
    }

    if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
        Clear-Selection
        $eventArgs.Handled = $true
    }
})

$SortComboBox.Add_SelectionChanged({
    param($sender, $eventArgs)

    if ($null -eq $sender.SelectedItem) {
        return
    }

    Set-LibrarySortMode ([string]$sender.SelectedItem.Tag)
})

$ShelfResizeTimer = New-Object System.Windows.Threading.DispatcherTimer
$ShelfResizeTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$ShelfResizeTimer.Add_Tick({
    $ShelfResizeTimer.Stop()
    $nextColumns = Get-ShelfColumnCount
    if ($nextColumns -ne $ShelfColumnCount) {
        $Script:ShelfRenderStartIndex = -1
        $Script:ShelfRenderEndIndex = -1
        Render-ShelfWindow -Force:$true
    }
})

$ScrollViewer.Add_PreviewMouseLeftButtonDown({
    param($sender, $eventArgs)

    if (-not (Is-ShelfInteractiveElement $eventArgs.OriginalSource)) {
        $mods = [System.Windows.Input.Keyboard]::Modifiers
        $Script:ShelfDragSelectAppend = (($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0)
        $Script:ShelfDragSelectBaseIds = if ($ShelfDragSelectAppend) { New-SelectedIdSet -Ids @($SelectedIds) } else { New-SelectedIdSet }
        if (-not $ShelfDragSelectAppend) {
            Clear-Selection
        }
        $Script:ShelfDragSelectArmed = $true
        $Script:ShelfDragSelectActive = $false
        $Script:ShelfDragSelectStartPoint = $eventArgs.GetPosition($ShelfSelectionHost)
        $Script:ShelfDragSelectLastPoint = $ShelfDragSelectStartPoint
        Hide-ShelfSelectionBox
        $ShelfScrollViewer.CaptureMouse() | Out-Null
        $eventArgs.Handled = $true
    }
})

$ScrollViewer.Add_MouseMove({
    param($sender, $eventArgs)

    if (-not $ShelfDragSelectArmed -or $eventArgs.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) {
        return
    }

    $Script:ShelfDragSelectLastPoint = $eventArgs.GetPosition($ShelfSelectionHost)
    if (-not $ShelfDragSelectActive) {
        $dx = [Math]::Abs([double]$ShelfDragSelectLastPoint.X - [double]$ShelfDragSelectStartPoint.X)
        $dy = [Math]::Abs([double]$ShelfDragSelectLastPoint.Y - [double]$ShelfDragSelectStartPoint.Y)
        if ($dx -lt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -and $dy -lt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
            $eventArgs.Handled = $true
            return
        }

        $Script:ShelfDragSelectActive = $true
        if ($ShelfDragSelectTimer -and -not $ShelfDragSelectTimer.IsEnabled) {
            $ShelfDragSelectTimer.Start()
        }
    }

    Update-ShelfDragSelection
    Invoke-ShelfDragSelectionAutoScroll
    $eventArgs.Handled = $true
})

$ScrollViewer.Add_MouseLeftButtonUp({
    param($sender, $eventArgs)

    if ($ShelfDragSelectArmed -or $ShelfDragSelectActive) {
        if ($ShelfDragSelectActive) {
            $Script:ShelfDragSelectLastPoint = $eventArgs.GetPosition($ShelfSelectionHost)
            Update-ShelfDragSelection
        }
        Reset-ShelfDragSelection
        $eventArgs.Handled = $true
    }
})

$ScrollViewer.Add_MouseRightButtonUp({
    param($sender, $eventArgs)

    Show-ShelfBlankMenu -Target $ScrollViewer
    $eventArgs.Handled = $true
})

$ShelfScrollViewer.Add_ScrollChanged({
    param($sender, $eventArgs)
    if ($ShelfIsRendering) {
        return
    }

    if ([Math]::Abs([double]$eventArgs.VerticalChange) -gt $ShelfScrollJumpThreshold) {
        $ShelfScrollRenderTimer.Stop()
        Clear-ShelfBuildQueue
        Clear-ShelfPreheatQueue
        $Script:ShelfRenderStartIndex = -1
        $Script:ShelfRenderEndIndex = -1
        $ShelfScrollRenderTimer.Start()
    }
    else {
        Render-ShelfWindow
    }

    if ($ShelfDragSelectActive) {
        Update-ShelfDragSelection
    }
})

$ShelfScrollViewer.Add_SizeChanged({
    param($sender, $eventArgs)
    $nextColumns = Get-ShelfColumnCount
    if ($nextColumns -ne $ShelfColumnCount) {
        $ShelfResizeTimer.Stop()
        $ShelfResizeTimer.Start()
    }
})

$Window.Add_Closed({
    param($sender, $eventArgs)
    if ($ShelfBuildTimer) {
        $ShelfBuildTimer.Stop()
    }
    if ($ShelfPreheatTimer) {
        $ShelfPreheatTimer.Stop()
    }
    if ($ShelfScrollRenderTimer) {
        $ShelfScrollRenderTimer.Stop()
    }
    if ($ShelfDragSelectTimer) {
        $ShelfDragSelectTimer.Stop()
    }
    Stop-RecognitionProcess
    Stop-AddProcess
    Stop-TagProcess
    Stop-DuplicateProcess
    if ($RemoveTimer) {
        $RemoveTimer.Stop()
    }
    if ($null -ne $RemoveProcess -and $RemoveProcess.HasExited) {
        try {
            $RemoveProcess.Dispose()
        }
        catch {
        }
    }
    Clear-SessionCache -TargetSessionId $SessionId
})

Clear-SessionCache
Render-Library
Start-PendingRemovalRecovery
Prewarm-ComicContextMenu
$Window.ShowDialog() | Out-Null
























