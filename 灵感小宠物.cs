using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using Shapes = System.Windows.Shapes;

public static class DpiPin {
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}

public static class PetHotkey {
  [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
  [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}

public class IdeaItem {
  public string id = "";
  public string created_at = "";
  public string folder = "未整理";
  public string idea = "";
  public string status = "active";
}

public class PetApp {
  private string appDir, dataDir, ideasFile, foldersFile;
  private Window window;
  private TextBox ideaBox;
  private Button save, history, close;
  private Border ball, shell;
  private double ballSize = 76, panelW = 370, panelH = 305;
  private bool parked = false;
  private Window openDrawer = null;
  private Dictionary<string, double> ballDrag = null, panelDrag = null;
  private JavaScriptSerializer js = new JavaScriptSerializer();
  private string xaml = @"<Window xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
        xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
        Width=""76"" Height=""76"" WindowStyle=""None"" AllowsTransparency=""True""
        Background=""Transparent"" Topmost=""True"" ShowInTaskbar=""False"" ResizeMode=""NoResize"">
  <Grid>
    <Border x:Name=""BallButton"" Width=""56"" Height=""56"" CornerRadius=""28"" HorizontalAlignment=""Right"" VerticalAlignment=""Bottom""
            Margin=""0,0,10,10"" RenderTransformOrigin=""0.5,0.5"" Cursor=""Hand""
            BorderBrush=""#E2DCD0"" BorderThickness=""1.5"">
      <Border.Style>
        <Style TargetType=""Border"">
          <Style.Triggers>
            <Trigger Property=""IsMouseOver"" Value=""True"">
              <Setter Property=""Opacity"" Value=""0.85""/>
            </Trigger>
          </Style.Triggers>
        </Style>
      </Border.Style>
      <Border.Background>
        <RadialGradientBrush>
          <GradientStop Color=""#FFFFFFFF"" Offset=""0""/>
          <GradientStop Color=""#FFFCFAF6"" Offset=""0.7""/>
          <GradientStop Color=""#FFF1ECE2"" Offset=""1""/>
        </RadialGradientBrush>
      </Border.Background>
      <TextBlock Text=""◕ ᴥ ◕"" FontSize=""16"" Foreground=""#7A5C40"" HorizontalAlignment=""Center"" VerticalAlignment=""Center"" Margin=""0,2,0,0""/>
    </Border>
    <Border x:Name=""Shell"" Visibility=""Collapsed"" CornerRadius=""22"" Background=""#FFFDF6"" BorderBrush=""#D9B478"" BorderThickness=""2"" Padding=""16"">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height=""Auto""/><RowDefinition Height=""*""/><RowDefinition Height=""Auto""/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions><ColumnDefinition Width=""*""/><ColumnDefinition Width=""36""/></Grid.ColumnDefinitions>
        <StackPanel Grid.Row=""0"" Grid.Column=""0"" Orientation=""Horizontal"">
          <TextBlock Text=""◕ ᴥ ◕"" FontSize=""28"" Foreground=""#835E33"" VerticalAlignment=""Center""/>
          <StackPanel Margin=""10,0,0,0"" VerticalAlignment=""Center"">
            <TextBlock Text=""inspiration"" FontFamily=""Segoe Print"" FontSize=""26"" FontWeight=""Bold"" Foreground=""#4B3824""/>
            <TextBlock Text=""把闪过的念头丢给我吧"" FontSize=""11"" Foreground=""#92775A""/>
          </StackPanel>
        </StackPanel>
        <Button x:Name=""CloseButton"" Grid.Row=""0"" Grid.Column=""1"" Content=""×"" FontSize=""19"" FontWeight=""Bold"" Foreground=""#92775A"" Background=""Transparent"" BorderThickness=""0""/>
        <TextBox x:Name=""IdeaBox"" Grid.Row=""1"" Grid.ColumnSpan=""2"" Margin=""0,10,0,10"" Padding=""10"" TextWrapping=""Wrap"" AcceptsReturn=""True"" VerticalScrollBarVisibility=""Auto"" FontSize=""15"" Foreground=""#493727"" Background=""#FFF8E9"" BorderBrush=""#E5C58E"" BorderThickness=""1"" ToolTip=""写下一个 idea...""/>
        <StackPanel Grid.Row=""2"" Grid.ColumnSpan=""2"" Orientation=""Horizontal"" HorizontalAlignment=""Right"">
          <Button x:Name=""HistoryButton"" Content=""看看以前的"" Padding=""10,5"" Margin=""0,0,8,0"" Foreground=""#6A5138"" Background=""Transparent"" BorderBrush=""#D9B478""/>
          <Button x:Name=""SaveButton"" Content=""收下灵感  ↵"" Padding=""12,5"" FontWeight=""Bold"" Foreground=""White"" Background=""#BD7C3D"" BorderThickness=""0""/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>";

  // ---------- 数据层 ----------
  private List<string> GetFolders() {
    if (File.Exists(foldersFile)) {
      try {
        var parsed = js.Deserialize<object[]>(File.ReadAllText(foldersFile, Encoding.UTF8));
        var list = new List<string>();
        foreach (var item in parsed) {
          string name = Convert.ToString(item);
          if (!string.IsNullOrWhiteSpace(name)) list.Add(name);
        }
        if (list.Count > 0 && list.Contains("未整理")) return list;
      } catch { }
    }
    return new List<string> { "未整理" };
  }
  private void SaveFolders(List<string> folders) {
    try { File.WriteAllText(foldersFile, js.Serialize(folders.ToArray()), new UTF8Encoding(false)); } catch { }
  }
  private List<IdeaItem> ReadIdeas() {
    var all = new List<IdeaItem>();
    if (File.Exists(ideasFile)) {
      foreach (var line in File.ReadAllLines(ideasFile, Encoding.UTF8)) {
        if (string.IsNullOrWhiteSpace(line)) continue;
        try {
          var o = js.Deserialize<Dictionary<string, object>>(line);
          var it = new IdeaItem();
          it.id = o.ContainsKey("id") ? Convert.ToString(o["id"]) : Guid.NewGuid().ToString("N");
          it.created_at = o.ContainsKey("created_at") ? Convert.ToString(o["created_at"]) : "";
          it.folder = o.ContainsKey("folder") ? Convert.ToString(o["folder"]) : "未整理";
          it.idea = o.ContainsKey("idea") ? Convert.ToString(o["idea"]) : "";
          it.status = o.ContainsKey("status") ? Convert.ToString(o["status"]) : "active";
          if (string.IsNullOrEmpty(it.id)) it.id = Guid.NewGuid().ToString("N");
          if (string.IsNullOrEmpty(it.status)) it.status = "active";
          if (string.IsNullOrEmpty(it.folder)) it.folder = "未整理";
          all.Add(it);
        } catch { }
      }
    }
    return all;
  }
  private Dictionary<string, object> ToDict(IdeaItem it) {
    var d = new Dictionary<string, object>();
    d["created_at"] = it.created_at;
    d["folder"] = it.folder;
    d["idea"] = it.idea;
    d["status"] = it.status;
    if (!string.IsNullOrEmpty(it.id)) d["id"] = it.id;
    return d;
  }
  private void WriteIdeas(List<IdeaItem> items) {
    try {
      var lines = new List<string>();
      foreach (var it in items) lines.Add(js.Serialize(ToDict(it)));
      if (lines.Count > 0) File.WriteAllLines(ideasFile, lines, new UTF8Encoding(false));
      else File.WriteAllText(ideasFile, "", new UTF8Encoding(false));
    } catch { }
  }
  private string EffectiveFolder(IdeaItem o, List<string> folders) {
    if (folders.Contains(o.folder)) return o.folder;
    return "未整理";
  }

  // ---------- 主窗口 ----------
  public void Run() {
    try { DpiPin.SetProcessDpiAwarenessContext(new IntPtr(-2)); } catch { }
    try { DpiPin.SetProcessDpiAwareness(1); } catch { }

    appDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
    dataDir = Path.Combine(appDir, "data");
    ideasFile = Path.Combine(dataDir, "ideas.jsonl");
    foldersFile = Path.Combine(dataDir, "folders.json");
    try { Directory.CreateDirectory(dataDir); } catch { }
    if (!File.Exists(ideasFile)) { try { File.WriteAllText(ideasFile, "", new UTF8Encoding(false)); } catch { } }

    window = (Window)XamlReader.Load(new System.Xml.XmlNodeReader(new System.Xml.XmlDocument() { InnerXml = xaml }));
    ideaBox = (TextBox)window.FindName("IdeaBox");
    save = (Button)window.FindName("SaveButton");
    history = (Button)window.FindName("HistoryButton");
    close = (Button)window.FindName("CloseButton");
    ball = (Border)window.FindName("BallButton");
    shell = (Border)window.FindName("Shell");

    TextOptions.SetTextFormattingMode(window, TextFormattingMode.Display);
    TextOptions.SetTextRenderingMode(window, TextRenderingMode.ClearType);

    save.Click += (s, e) => SaveIdea();
    ideaBox.KeyDown += (s, e) => { if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.Control) { SaveIdea(); e.Handled = true; } };
    close.Click += (s, e) => CollapsePet();
    history.Click += (s, e) => ShowIdeaDrawer();

    // 球：拖动 / 点击展开
    ball.MouseLeftButtonDown += (s, e) => {
      var c = GetCursorDip();
      ballDrag = new Dictionary<string, double> { { "sx", c[0] }, { "sy", c[1] }, { "wx", window.Left }, { "wy", window.Top }, { "dragging", 0 } };
      try { ball.CaptureMouse(); } catch { }
      e.Handled = true;
    };
    ball.MouseMove += (s, e) => {
      if (ballDrag != null) {
        var c = GetCursorDip();
        double dx = c[0] - ballDrag["sx"], dy = c[1] - ballDrag["sy"];
        if (ballDrag["dragging"] == 0 && (Math.Abs(dx) >= 4 || Math.Abs(dy) >= 4)) ballDrag["dragging"] = 1;
        if (ballDrag["dragging"] == 1) {
          window.Left = ballDrag["wx"] + dx;
          window.Top = ballDrag["wy"] + dy;
        }
      }
    };
    ball.MouseLeftButtonUp += (s, e) => {
      bool wasDrag = ballDrag != null && ballDrag["dragging"] == 1;
      ballDrag = null;
      try { if (ball.IsMouseCaptured) ball.ReleaseMouseCapture(); } catch { }
      if (!wasDrag) ExpandPet();
      e.Handled = true;
    };

    // 面板拖动
    window.MouseLeftButtonDown += (s, e) => {
      if (shell.Visibility == Visibility.Visible) {
        var c = GetCursorDip();
        panelDrag = new Dictionary<string, double> { { "sx", c[0] }, { "sy", c[1] }, { "wx", window.Left }, { "wy", window.Top }, { "dragging", 0 } };
        e.Handled = true;
      }
    };
    window.MouseMove += (s, e) => {
      if (panelDrag != null) {
        var c = GetCursorDip();
        double dx = c[0] - panelDrag["sx"], dy = c[1] - panelDrag["sy"];
        if (panelDrag["dragging"] == 0 && (Math.Abs(dx) >= 4 || Math.Abs(dy) >= 4)) panelDrag["dragging"] = 1;
        if (panelDrag["dragging"] == 1) {
          window.Left = panelDrag["wx"] + dx;
          window.Top = panelDrag["wy"] + dy;
        }
      }
    };
    window.MouseLeftButtonUp += (s, e) => { panelDrag = null; };

    // 热键
    window.SourceInitialized += (s, e) => {
      IntPtr hwnd = new WindowInteropHelper(window).Handle;
      PetHotkey.RegisterHotKey(hwnd, 9001, 3, 0x49);
      var src = HwndSource.FromHwnd(hwnd);
      src.AddHook(new HwndSourceHook(WindowHook));
    };
    window.Closed += (s, e) => {
      IntPtr hwnd = new WindowInteropHelper(window).Handle;
      PetHotkey.UnregisterHotKey(hwnd, 9001);
    };
    window.Dispatcher.UnhandledException += (s, e) => {
      try { File.AppendAllText(Path.Combine(appDir, "pet_crash.log"), "DISPATCHER: " + e.Exception + "\n", new UTF8Encoding(false)); } catch { }
      e.Handled = true;
    };

    var wa = SystemParameters.WorkArea;
    window.Left = wa.Right - ballSize - 12;
    window.Top = wa.Bottom - ballSize - 12;
    window.ShowDialog();
  }

  private IntPtr WindowHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
    try {
      if (msg == 0x0312 && wParam.ToInt32() == 9001) {
        if (openDrawer != null && openDrawer.IsVisible) openDrawer.Close();
        else if (parked) ShowPet();
        else if (shell.Visibility == Visibility.Visible) HidePet();
        else ExpandPet();
        handled = true;
      }
    } catch (Exception ex) {
      try { File.AppendAllText(Path.Combine(appDir, "pet_crash.log"), "HOOK: " + ex + "\n", new UTF8Encoding(false)); } catch { }
    }
    return IntPtr.Zero;
  }

  private double[] GetCursorDip() {
    double inv = 1.0 / VisualTreeHelper.GetDpi(window).DpiScaleX;
    var p = System.Windows.Forms.Cursor.Position;
    return new double[] { p.X * inv, p.Y * inv };
  }

  private void SetPetSize(double targetW, double targetH, Action onDone) {
    var wa = SystemParameters.WorkArea;
    double curRight = window.Left + window.Width;
    double curBottom = window.Top + window.Height;
    window.Width = targetW; window.Height = targetH;
    window.Left = Math.Max(wa.Left, Math.Min(curRight - targetW, wa.Right - targetW));
    window.Top = Math.Max(wa.Top, Math.Min(curBottom - targetH, wa.Bottom - targetH));
    if (onDone != null) onDone();
  }
  private void ExpandPet() {
    shell.Visibility = Visibility.Collapsed;
    ball.Visibility = Visibility.Visible;
    SetPetSize(panelW, panelH, () => {
      ball.Visibility = Visibility.Collapsed;
      shell.Visibility = Visibility.Visible;
      try { ideaBox.Focus(); } catch { }
    });
  }
  private void CollapsePet() {
    shell.Visibility = Visibility.Collapsed;
    ball.Visibility = Visibility.Visible;
    SetPetSize(ballSize, ballSize, null);
  }
  private void HidePet() {
    var wa = SystemParameters.WorkArea;
    window.Width = ballSize; window.Height = ballSize;
    window.Left = wa.Right + 30;
    window.Top = wa.Top;
    parked = true;
  }
  private void ShowPet() {
    var wa = SystemParameters.WorkArea;
    window.Width = ballSize; window.Height = ballSize;
    window.Left = wa.Right - ballSize - 12;
    window.Top = wa.Bottom - ballSize - 12;
    parked = false;
    try { window.Activate(); } catch { }
    ExpandPet();
  }

  private void SaveIdea() {
    string idea = ideaBox.Text.Trim();
    if (string.IsNullOrWhiteSpace(idea)) return;
    var it = new IdeaItem();
    it.created_at = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
    it.folder = "未整理";
    it.idea = idea;
    it.status = "active";
    it.id = Guid.NewGuid().ToString("N");
    try { File.AppendAllText(ideasFile, js.Serialize(ToDict(it)) + "\n", new UTF8Encoding(false)); } catch { }
    ideaBox.Text = "";
    save.Content = "收好啦！ ✦";
    var t = new DispatcherTimer();
    t.Interval = TimeSpan.FromMilliseconds(650);
    t.Tick += (s, e) => { t.Stop(); save.Content = "收下灵感  ↵"; };
    t.Start();
  }

  // ---------- 收纳夹抽屉 ----------
  private Style LoadBtnStyle() {
    string styleXaml = @"<Style xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml"" TargetType=""Button"">
  <Setter Property=""Template"">
    <Setter.Value>
      <ControlTemplate TargetType=""Button"">
        <Border x:Name=""bd"" Background=""{TemplateBinding Background}"" CornerRadius=""8"" Padding=""{TemplateBinding Padding}"">
          <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center""/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property=""IsMouseOver"" Value=""True""><Setter TargetName=""bd"" Property=""Opacity"" Value=""0.85""/></Trigger>
          <Trigger Property=""IsPressed"" Value=""True""><Setter TargetName=""bd"" Property=""Opacity"" Value=""0.7""/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>";
    return (Style)XamlReader.Load(new System.Xml.XmlNodeReader(new System.Xml.XmlDocument() { InnerXml = styleXaml }));
  }

  private string ShowFolderInput(Window owner) {
    var dlg = new Window();
    dlg.Title = "新建收纳夹"; dlg.Width = 320;
    dlg.SizeToContent = SizeToContent.Height;
    dlg.WindowStartupLocation = WindowStartupLocation.CenterOwner;
    dlg.Owner = owner; dlg.ShowInTaskbar = false;
    dlg.Background = (Brush)new BrushConverter().ConvertFromString("#FFFDF6");
    var g = new Grid(); g.Margin = new Thickness(18);
    g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
    g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
    g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
    var lbl = new TextBlock { Text = "新收纳夹的名字：", Foreground = (Brush)new BrushConverter().ConvertFromString("#4B3824"), FontSize = 13 };
    Grid.SetRow(lbl, 0); g.Children.Add(lbl);
    var tb = new TextBox { Margin = new Thickness(0, 10, 0, 10), FontSize = 14, MaxLength = 12 };
    Grid.SetRow(tb, 1); g.Children.Add(tb);
    var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
    var ok = new Button { Content = "确定", Padding = new Thickness(16, 7, 16, 7), Margin = new Thickness(0, 0, 8, 0), FontSize = 13, FontWeight = FontWeights.Bold, Foreground = Brushes.White, Background = (Brush)new BrushConverter().ConvertFromString("#BD7C3D"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand };
    var cancel = new Button { Content = "取消", Padding = new Thickness(16, 7, 16, 7), FontSize = 13, Foreground = (Brush)new BrushConverter().ConvertFromString("#6A5138"), Background = (Brush)new BrushConverter().ConvertFromString("#F1E6CE"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand };
    ok.Click += (s, e) => { dlg.DialogResult = true; };
    cancel.Click += (s, e) => { dlg.DialogResult = false; };
    tb.KeyDown += (s, e) => { if (e.Key == Key.Enter) dlg.DialogResult = true; else if (e.Key == Key.Escape) dlg.DialogResult = false; };
    row.Children.Add(ok); row.Children.Add(cancel);
    Grid.SetRow(row, 2); g.Children.Add(row);
    dlg.Content = g;
    bool? res = dlg.ShowDialog();
    if (res == true) return tb.Text.Trim();
    return null;
  }

  private void ShowIdeaDrawer() {
    CollapsePet();
    var state = new DrawerState();
    state.items = ReadIdeas();
    state.folders = GetFolders();
    state.filter = "未整理";

    var drawer = new Window();
    drawer.Title = "灵感收纳夹";
    drawer.Width = 500; drawer.MinWidth = 380; drawer.MinHeight = 240; drawer.MaxHeight = 680;
    drawer.Height = 600;
    drawer.Background = (Brush)new BrushConverter().ConvertFromString("#FFFDF6");
    drawer.Topmost = true; drawer.Owner = window;
    openDrawer = drawer;
    drawer.Closed += (s, e) => { openDrawer = null; };

    var grid = new Grid { Margin = new Thickness(22, 14, 22, 6) };
    foreach (string h in new[] { "Auto", "Auto", "Auto", "*" }) grid.RowDefinitions.Add(new RowDefinition { Height = h == "*" ? new GridLength(1, GridUnitType.Star) : GridLength.Auto });

    var btnStyle = LoadBtnStyle();
    var bc = new BrushConverter();

    // 行0：标题区（宠物脸 + 标题 + 新建夹子）
    var face = new TextBlock { Text = "◕ ᴥ ◕", FontSize = 26, Foreground = (Brush)bc.ConvertFromString("#835E33"), VerticalAlignment = VerticalAlignment.Center };
    var title = new TextBlock { Text = "灵感收纳夹", FontSize = 20, FontWeight = FontWeights.Bold, Foreground = (Brush)bc.ConvertFromString("#4B3824") };
    var titleCol = new StackPanel { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
    titleCol.Children.Add(title);
    var addBtn = new Button { Content = "＋ 新建收纳夹", FontSize = 13, FontWeight = FontWeights.Bold, Padding = new Thickness(14, 8, 14, 8), Foreground = Brushes.White, Background = (Brush)bc.ConvertFromString("#BD7C3D"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand, Style = btnStyle, VerticalAlignment = VerticalAlignment.Center };
    var h0 = new Grid();
    h0.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
    h0.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    var h0L = new StackPanel { Orientation = Orientation.Horizontal };
    h0L.Children.Add(face); h0L.Children.Add(titleCol);
    Grid.SetColumn(h0L, 0); h0.Children.Add(h0L);
    Grid.SetColumn(addBtn, 1); h0.Children.Add(addBtn);
    Grid.SetRow(h0, 0); grid.Children.Add(h0);

    // 行1：筛选 + 查看全部 + 删除夹子
    var filter = new ComboBox { Width = 170, Height = 24, FontSize = 12, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(6, 0, 6, 0), Background = Brushes.White, BorderBrush = (Brush)bc.ConvertFromString("#D9C7A8"), VerticalContentAlignment = VerticalAlignment.Center };
    var allBtn = new Button { Content = "查看全部", FontSize = 12, FontWeight = FontWeights.Bold, Padding = new Thickness(10, 6, 10, 6), Foreground = (Brush)bc.ConvertFromString("#6A5138"), Background = (Brush)bc.ConvertFromString("#F1E6CE"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand, Style = btnStyle, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
    var delFolderBtn = new Button { Content = "✕ 删除该夹", FontSize = 12, Padding = new Thickness(8, 4, 8, 4), Foreground = (Brush)bc.ConvertFromString("#B4552D"), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Margin = new Thickness(12, 0, 0, 0), Cursor = Cursors.Hand, Style = btnStyle, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
    var h1 = new Grid { Margin = new Thickness(0, 12, 0, 0) };
    h1.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    h1.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    h1.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
    Grid.SetColumn(filter, 0); h1.Children.Add(filter);
    Grid.SetColumn(allBtn, 1); h1.Children.Add(allBtn);
    Grid.SetColumn(delFolderBtn, 2); h1.Children.Add(delFolderBtn);
    Grid.SetRow(h1, 1); grid.Children.Add(h1);

    // 行3：列表
    var scroll = new ScrollViewer { Margin = new Thickness(0, 10, 0, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    var stack = new StackPanel();
    scroll.Content = stack;
    Grid.SetRow(scroll, 3); grid.Children.Add(scroll);

    drawer.Content = grid;

    // 高度自适应：内容少时收紧、多时顶到 680
    Action updateHeight = () => {
      try {
        stack.Measure(new Size(452, double.PositiveInfinity));
        double h0h = h0.ActualHeight > 0 ? h0.ActualHeight : 40;
        double h1h = h1.ActualHeight > 0 ? h1.ActualHeight : 56;
        double ch = Math.Ceiling(h0h + h1h + stack.DesiredSize.Height + 48);
        if (ch < 240) ch = 240;
        if (ch > 680) ch = 680;
        if (drawer.Height != ch) drawer.Height = ch;
      } catch { }
    };

    // 重建筛选下拉
    Action ResetFilterCombo = () => {
      filter.Items.Clear();
      foreach (var f in state.folders) filter.Items.Add(f);
      filter.Items.Add("垃圾桶");
      int idx = -1;
      for (int i = 0; i < filter.Items.Count; i++) {
        if (Convert.ToString(filter.Items[i]) == state.filter) { idx = i; break; }
      }
      if (idx < 0) { state.filter = "未整理"; idx = 0; }
      filter.SelectedIndex = idx;
    };

    // 全部视图里的小节标题
    Func<string, int, StackPanel> makeSection = (fname, count) => {
      var sec = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(2, 8, 0, 4) };
      var dot = new TextBlock { Text = "◈", FontSize = 11, Foreground = (Brush)bc.ConvertFromString("#BD7C3D"), VerticalAlignment = VerticalAlignment.Center };
      var lbl = new TextBlock { Text = fname + " · " + count, FontSize = 12, FontWeight = FontWeights.Bold, Foreground = (Brush)bc.ConvertFromString("#4B3824"), Margin = new Thickness(6, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
      sec.Children.Add(dot); sec.Children.Add(lbl);
      return sec;
    };

    // 渲染列表（先声明，供卡片闭包引用）
    Action<string> render = null;

    // 构建单张卡片
    Func<IdeaItem, bool, Border> makeCard = null;
    makeCard = (it, inTrash) => {
      var card = new Border { Background = (Brush)bc.ConvertFromString("#FFF9EC"), BorderBrush = (Brush)bc.ConvertFromString("#E8D9BA"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 0, 0, 4) };
      card.MouseEnter += (s, e) => { card.BorderBrush = (Brush)bc.ConvertFromString("#D9C7A8"); };
      card.MouseLeave += (s, e) => { card.BorderBrush = (Brush)bc.ConvertFromString("#E8D9BA"); };
      var content = new StackPanel();
      string effF = EffectiveFolder(it, state.folders);
      var meta = new StackPanel { Orientation = Orientation.Horizontal };
      var tag = new Border { CornerRadius = new CornerRadius(6), Padding = new Thickness(8, 2, 8, 2) };
      var tagTxt = new TextBlock { FontSize = 11, Foreground = (Brush)bc.ConvertFromString("#8A5A2B") };
      tag.Child = tagTxt;
      var dateTxt = new TextBlock { FontSize = 11, Margin = new Thickness(8, 0, 0, 0), Foreground = (Brush)bc.ConvertFromString("#A08B6E") };
      var body = new TextBlock { Text = it.idea, TextWrapping = TextWrapping.Wrap, FontSize = 14, LineHeight = 22, Foreground = (Brush)bc.ConvertFromString("#493727"), Margin = new Thickness(0, 8, 0, 0) };
      var acts = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Right };
      if (inTrash) {
        tag.Background = (Brush)bc.ConvertFromString("#F5E7D2");
        tagTxt.Text = "原来在「" + effF + "」";
        dateTxt.Text = it.created_at;
        var restore = new Button { Content = "恢复", Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(0, 0, 8, 0), FontSize = 12, FontWeight = FontWeights.Bold, Foreground = Brushes.White, Background = (Brush)bc.ConvertFromString("#BD7C3D"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand, Style = btnStyle };
        var del = new Button { Content = "真正删除", Padding = new Thickness(12, 4, 12, 4), FontSize = 12, Foreground = Brushes.White, Background = (Brush)bc.ConvertFromString("#B4552D"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand, Style = btnStyle };
        IdeaItem captured = it;
        restore.Click += (s, e) => {
          captured.status = "active";
          if (!state.folders.Contains(captured.folder)) captured.folder = "未整理";
          WriteIdeas(state.items);
          render(Convert.ToString(filter.SelectedItem));
        };
        del.Click += (s, e) => {
          var r = MessageBox.Show(drawer, "真正删除后无法恢复，确定要删除这条灵感吗？", "inspiration", MessageBoxButton.YesNo, MessageBoxImage.Warning);
          if (r == MessageBoxResult.Yes) {
            state.items.Remove(captured);
            WriteIdeas(state.items);
            render(Convert.ToString(filter.SelectedItem));
          }
        };
        acts.Children.Add(restore); acts.Children.Add(del);
      } else {
        tag.Background = (Brush)bc.ConvertFromString("#F1E6CE");
        tagTxt.Text = effF;
        dateTxt.Text = it.created_at;
        var cat = new ComboBox { FontSize = 12, Margin = new Thickness(0, 0, 6, 0), Width = 132, Height = 22, Padding = new Thickness(4, 0, 4, 0), Background = Brushes.White, BorderBrush = (Brush)bc.ConvertFromString("#D9C7A8"), VerticalContentAlignment = VerticalAlignment.Center };
        foreach (var f in state.folders) cat.Items.Add("放入「" + f + "」");
        int fi = state.folders.IndexOf(effF);
        if (fi < 0) fi = 0;
        cat.SelectedIndex = fi;
        var trashBtn = new Button { Content = "垃圾桶", Padding = new Thickness(12, 4, 12, 4), FontSize = 12, Foreground = (Brush)bc.ConvertFromString("#B4552D"), Background = (Brush)bc.ConvertFromString("#F6E3D5"), BorderThickness = new Thickness(0), Cursor = Cursors.Hand, Style = btnStyle };
        IdeaItem cap2 = it;
        cat.SelectionChanged += (s, e) => {
          int sel = cat.SelectedIndex;
          if (sel >= 0 && sel < state.folders.Count) {
            string f2 = state.folders[sel];
            if (f2 != null && cap2.folder != f2) {
              cap2.folder = f2;
              WriteIdeas(state.items);
              render(Convert.ToString(filter.SelectedItem));
            }
          }
        };
        trashBtn.Click += (s, e) => {
          cap2.status = "trashed";
          WriteIdeas(state.items);
          render(Convert.ToString(filter.SelectedItem));
        };
        acts.Children.Add(cat); acts.Children.Add(trashBtn);
      }
      meta.Children.Add(tag); meta.Children.Add(dateTxt);
      content.Children.Add(meta); content.Children.Add(body); content.Children.Add(acts);
      card.Child = content;
      return card;
    };

    render = (string selected) => {
      stack.Children.Clear();
      bool isTrash = selected == "垃圾桶";
      allBtn.Visibility = isTrash ? Visibility.Collapsed : Visibility.Visible;
      allBtn.Content = state.allView ? "按夹子看" : "查看全部";
      allBtn.Background = (Brush)bc.ConvertFromString(state.allView ? "#BD7C3D" : "#F1E6CE");
      allBtn.Foreground = (Brush)bc.ConvertFromString(state.allView ? "White" : "#6A5138");
      if (state.allView) {
        delFolderBtn.Visibility = Visibility.Collapsed;
        var groups = new Dictionary<string, List<IdeaItem>>();
        int activeCount = 0;
        foreach (var it in state.items) {
          if (it.status != "active") continue;
          activeCount++;
          string eff = EffectiveFolder(it, state.folders);
          if (!groups.ContainsKey(eff)) groups[eff] = new List<IdeaItem>();
          groups[eff].Add(it);
        }
        if (activeCount == 0) {
          stack.Children.Add(new TextBlock { Text = "还没有任何灵感。", Foreground = (Brush)bc.ConvertFromString("#92775A"), Margin = new Thickness(4), FontSize = 13 });
        } else {
          var order = new List<string>();
          foreach (var f in state.folders) if (groups.ContainsKey(f)) order.Add(f);
          foreach (var k in groups.Keys) if (!order.Contains(k)) order.Add(k);
          foreach (var fname in order) {
            stack.Children.Add(makeSection(fname, groups[fname].Count));
            foreach (var it in groups[fname]) stack.Children.Add(makeCard(it, false));
          }
        }
      } else {
        var shown = new List<IdeaItem>();
        foreach (var it in state.items) {
          if (isTrash) { if (it.status == "trashed") shown.Add(it); continue; }
          if (it.status != "active") continue;
          string eff = EffectiveFolder(it, state.folders);
          if (eff == selected) shown.Add(it);
        }
        if (isTrash || selected == "未整理") delFolderBtn.Visibility = Visibility.Collapsed;
        else delFolderBtn.Visibility = Visibility.Visible;
        if (shown.Count == 0) {
          string empty = isTrash ? "垃圾桶是空的。" : (selected == "未整理" ? "「未整理」还是空的。" : "这个夹子还是空的。");
          stack.Children.Add(new TextBlock { Text = empty, Foreground = (Brush)bc.ConvertFromString("#92775A"), Margin = new Thickness(4), FontSize = 13, TextWrapping = TextWrapping.Wrap });
        } else {
          foreach (var it in shown) stack.Children.Add(makeCard(it, isTrash));
        }
      }
      updateHeight();
    };

    addBtn.Click += (s, e) => {
      string name = ShowFolderInput(drawer);
      if (string.IsNullOrWhiteSpace(name)) return;
      if (name == "垃圾桶" || name == "全部" || state.folders.Contains(name)) {
        MessageBox.Show(drawer, "已经有「" + name + "」了，换个名字吧。", "inspiration", MessageBoxButton.OK, MessageBoxImage.Information);
        return;
      }
      state.folders.Add(name);
      SaveFolders(state.folders);
      state.filter = name;
      state.allView = false;
      ResetFilterCombo();
      render(Convert.ToString(filter.SelectedItem));
    };

    delFolderBtn.Click += (s, e) => {
      string name = Convert.ToString(filter.SelectedItem);
      if (name == "未整理" || name == "垃圾桶" || name == "") return;
      var r = MessageBox.Show(drawer, "确定删除收纳夹「" + name + "」？里面的灵感会回到「未整理」。", "inspiration", MessageBoxButton.YesNo, MessageBoxImage.Warning);
      if (r == MessageBoxResult.Yes) {
        foreach (var it in state.items) { if (it.status == "active" && it.folder == name) it.folder = "未整理"; }
        state.folders.Remove(name);
        SaveFolders(state.folders);
        WriteIdeas(state.items);
        state.filter = "未整理";
        state.allView = false;
        ResetFilterCombo();
        render(Convert.ToString(filter.SelectedItem));
      }
    };

    allBtn.Click += (s, e) => {
      state.allView = !state.allView;
      render(Convert.ToString(filter.SelectedItem));
    };

    filter.SelectionChanged += (s, e) => {
      if (filter.SelectedItem != null) {
        state.filter = Convert.ToString(filter.SelectedItem);
        state.allView = false;
        render(Convert.ToString(filter.SelectedItem));
      }
    };

    ResetFilterCombo();
    render(state.filter);
    drawer.StateChanged += (s, e) => {
      try { if (drawer.WindowState == WindowState.Minimized) drawer.WindowState = WindowState.Normal; } catch { }
    };
    drawer.ShowDialog();
  }
}

public class DrawerState {
  public List<IdeaItem> items = new List<IdeaItem>();
  public List<string> folders = new List<string>();
  public string filter = "未整理";
  public bool allView = false;
}

public static class PetProgram {
  [STAThread]
  public static void Main() {
    try { new PetApp().Run(); }
    catch (Exception ex) {
      try {
        string dir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
        File.AppendAllText(Path.Combine(dir, "pet_crash.log"), "FATAL: " + ex + "\n", new UTF8Encoding(false));
      } catch { }
    }
  }
}
