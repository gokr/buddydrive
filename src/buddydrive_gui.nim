import std/[os, json, httpclient, strutils]

when defined(gtk3):
  {.passl: gorge("pkg-config --libs gtk+-3.0").}
else:
  {.passl: gorge("pkg-config --libs gtk4").}

type
  GtkWidget* = pointer
  GtkWindow* = pointer
  GtkButton* = pointer
  GtkBox* = pointer
  GtkLabel* = pointer
  GtkListBox* = pointer
  GtkListBoxRow* = pointer
  GtkProgressBar* = pointer
  GtkApplication* = pointer
  GtkApplicationWindow* = pointer
  GtkScrolledWindow* = pointer
  GApplication* = pointer
  GObject* = pointer
  GCallback* = pointer
  GApplicationFlags* = cint
  GConnectFlags* = cint
  GSourceFunc* = proc(data: pointer): cint {.cdecl.}

const
  GAPPLICATIONFLAGSNONE* = 0.GApplicationFlags
  GTKORIENTATIONHORIZONTAL* = 0.cint
  GTKORIENTATIONVERTICAL* = 1.cint

proc gtkInit*() {.cdecl, importc: "gtk_init".}
proc gtkWindowNew*(): GtkWindow {.cdecl, importc: "gtk_window_new".}
proc gtkWindowSetTitle*(window: GtkWindow, title: cstring) {.cdecl, importc: "gtk_window_set_title".}
proc gtkWindowSetDefaultSize*(window: GtkWindow, width: cint, height: cint) {.cdecl, importc: "gtk_window_set_default_size".}
proc gtkWindowSetChild*(window: GtkWindow, child: GtkWidget) {.cdecl, importc: "gtk_window_set_child".}
proc gtkWidgetShow*(widget: GtkWidget) {.cdecl, importc: "gtk_widget_show".}
proc gtkWidgetSetVisible*(widget: GtkWidget, visible: cint) {.cdecl, importc: "gtk_widget_set_visible".}
proc gtkBoxNew*(orientation: cint, spacing: cint): GtkBox {.cdecl, importc: "gtk_box_new".}
proc gtkBoxAppend*(box: GtkBox, child: GtkWidget) {.cdecl, importc: "gtk_box_append".}
proc gtkBoxPrepend*(box: GtkBox, child: GtkWidget) {.cdecl, importc: "gtk_box_prepend".}
proc gtkLabelNew*(text: cstring): GtkLabel {.cdecl, importc: "gtk_label_new".}
proc gtkLabelSetText*(label: GtkLabel, text: cstring) {.cdecl, importc: "gtk_label_set_text".}
proc gtkButtonNewWithLabel*(label: cstring): GtkButton {.cdecl, importc: "gtk_button_new_with_label".}
proc gtkButtonSetLabel*(button: GtkButton, label: cstring) {.cdecl, importc: "gtk_button_set_label".}
proc gtkApplicationNew*(applicationId: cstring, flags: GApplicationFlags): GtkApplication {.cdecl, importc: "gtk_application_new".}
proc gApplicationRun*(app: GApplication, argc: cint, argv: pointer): cint {.cdecl, importc: "g_application_run".}
proc gSignalConnectData*(instance: GObject, detailedSignal: cstring, cHandler: GCallback, data: pointer, destroyData: pointer, connectFlags: GConnectFlags): culong {.cdecl, importc: "g_signal_connect_data".}
proc gtkApplicationWindowNew*(app: GtkApplication): GtkWindow {.cdecl, importc: "gtk_application_window_new".}
proc gtkWidgetAddCssClass*(widget: GtkWidget, cssClass: cstring) {.cdecl, importc: "gtk_widget_add_css_class".}
proc gtkWidgetSetMarginStart*(widget: GtkWidget, margin: cint) {.cdecl, importc: "gtk_widget_set_margin_start".}
proc gtkWidgetSetMarginEnd*(widget: GtkWidget, margin: cint) {.cdecl, importc: "gtk_widget_set_margin_end".}
proc gtkWidgetSetMarginTop*(widget: GtkWidget, margin: cint) {.cdecl, importc: "gtk_widget_set_margin_top".}
proc gtkWidgetSetMarginBottom*(widget: GtkWidget, margin: cint) {.cdecl, importc: "gtk_widget_set_margin_bottom".}
proc gtkWidgetSetHexpand*(widget: GtkWidget, expand: cint) {.cdecl, importc: "gtk_widget_set_hexpand".}
proc gtkWidgetSetVexpand*(widget: GtkWidget, expand: cint) {.cdecl, importc: "gtk_widget_set_vexpand".}
proc gtkListBoxNew*(): GtkListBox {.cdecl, importc: "gtk_list_box_new".}
proc gtkListBoxAppend*(list: GtkListBox, row: GtkWidget) {.cdecl, importc: "gtk_list_box_append".}
proc gtkListBoxRemove*(list: GtkListBox, row: GtkWidget) {.cdecl, importc: "gtk_list_box_remove".}
proc gtkProgressBarNew*(): GtkProgressBar {.cdecl, importc: "gtk_progress_bar_new".}
proc gtkProgressBarSetFraction*(bar: GtkProgressBar, fraction: cdouble) {.cdecl, importc: "gtk_progress_bar_set_fraction".}
proc gtkProgressBarSetText*(bar: GtkProgressBar, text: cstring) {.cdecl, importc: "gtk_progress_bar_set_text".}
proc gtkProgressBarSetShowText*(bar: GtkProgressBar, showText: cint) {.cdecl, importc: "gtk_progress_bar_set_show_text".}
proc gtkScrolledWindowNew*(): GtkScrolledWindow {.cdecl, importc: "gtk_scrolled_window_new".}
proc gtkScrolledWindowSetChild*(window: GtkScrolledWindow, child: GtkWidget) {.cdecl, importc: "gtk_scrolled_window_set_child".}
proc gtkScrolledWindowSetPolicy*(window: GtkScrolledWindow, hscrollbar: cint, vscrollbar: cint) {.cdecl, importc: "gtk_scrolled_window_set_policy".}
proc gTimeoutAdd*(interval: cuint, function: GSourceFunc, data: pointer): cuint {.cdecl, importc: "g_timeout_add".}

const
  GTK_POLICY_AUTOMATIC = 1.cint

proc gSignalConnect*(instance: GObject, signal: cstring, cHandler: GCallback, data: pointer): culong =
  gSignalConnectData(instance, signal, cHandler, data, nil, 0.GConnectFlags)

proc gtkWindowSetDefaultIconName*(name: cstring) {.cdecl, importc: "gtk_window_set_default_icon_name".}

const
  AppId = "org.buddydrive.app"
  ApiBase = "http://127.0.0.1:17521"

type
  AppState = object
    window: GtkWindow
    client: HttpClient
    foldersList: GtkListBox
    buddiesList: GtkListBox
    statusLabel: GtkLabel
    buddyNameLabel: GtkLabel
    uptimeLabel: GtkLabel
    running: bool

var
  app: GtkApplication
  state: AppState

proc apiGet(endpoint: string): JsonNode =
  try:
    let resp = state.client.getContent(ApiBase & endpoint)
    result = parseJson(resp)
  except:
    result = %*{"error": getCurrentExceptionMsg()}

proc apiPost(endpoint: string, body: JsonNode = %*{}): JsonNode =
  try:
    let resp = state.client.postContent(ApiBase & endpoint, $body)
    result = parseJson(resp)
  except:
    result = %*{"error": getCurrentExceptionMsg()}

proc formatBytes(bytes: int64): string =
  if bytes < 1024:
    $bytes & " B"
  elif bytes < 1024 * 1024:
    $(bytes div 1024) & " KB"
  elif bytes < 1024 * 1024 * 1024:
    $(bytes div (1024 * 1024)) & " MB"
  else:
    $(bytes div (1024 * 1024 * 1024)) & " GB"

proc createSectionCard(title: string): tuple[box: GtkBox, content: GtkBox] =
  let card = gtkBoxNew(GTKORIENTATIONVERTICAL, 8)
  gtkWidgetAddCssClass(card, "card")
  gtkWidgetSetMarginStart(card, 12)
  gtkWidgetSetMarginEnd(card, 12)
  gtkWidgetSetMarginTop(card, 12)
  gtkWidgetSetMarginBottom(card, 12)
  
  let titleLabel = gtkLabelNew(cstring(title))
  gtkWidgetAddCssClass(titleLabel, "title-4")
  gtkWidgetSetMarginBottom(titleLabel, 8)
  gtkBoxAppend(card, titleLabel)
  
  let content = gtkBoxNew(GTKORIENTATIONVERTICAL, 4)
  gtkBoxAppend(card, content)
  
  result = (card, content)

proc createFolderRow(folder: JsonNode): GtkBox =
  let row = gtkBoxNew(GTKORIENTATIONHORIZONTAL, 12)
  gtkWidgetSetMarginStart(row, 8)
  gtkWidgetSetMarginEnd(row, 8)
  gtkWidgetSetMarginTop(row, 8)
  gtkWidgetSetMarginBottom(row, 8)
  
  let leftBox = gtkBoxNew(GTKORIENTATIONVERTICAL, 4)
  gtkWidgetSetHexpand(leftBox, 1)
  
  let nameText = folder{"name"}.getStr("Unknown")
  let nameLabel = gtkLabelNew(cstring(nameText))
  gtkWidgetAddCssClass(nameLabel, "title")
  gtkWidgetSetHexpand(nameLabel, 1)
  gtkBoxAppend(leftBox, nameLabel)
  
  let pathText = folder{"path"}.getStr("")
  let pathLabel = gtkLabelNew(cstring(pathText))
  gtkWidgetAddCssClass(pathLabel, "dim-label")
  gtkWidgetAddCssClass(pathLabel, "caption")
  gtkBoxAppend(leftBox, pathLabel)
  
  let status = folder{"status"}
  let totalBytes = status{"totalBytes"}.getInt(0)
  let syncedBytes = status{"syncedBytes"}.getInt(0)
  let fileCount = status{"fileCount"}.getInt(0)
  let syncStatus = status{"status"}.getStr("idle")
  
  let statusText = syncStatus & " - " & formatBytes(syncedBytes) & " / " & formatBytes(totalBytes) & " (" & $fileCount & " files)"
  let statusLabel = gtkLabelNew(cstring(statusText))
  gtkWidgetAddCssClass(statusLabel, "caption")
  gtkBoxAppend(leftBox, statusLabel)
  
  gtkBoxAppend(row, leftBox)
  
  if syncStatus == "syncing":
    let progress = gtkProgressBarNew()
    let fraction = if totalBytes > 0: syncedBytes.float / totalBytes.float else: 0.0
    gtkProgressBarSetFraction(progress, fraction.cdouble)
    gtkProgressBarSetShowText(progress, 1)
    gtkBoxAppend(row, progress)
  
  result = row

proc createBuddyRow(buddy: JsonNode): GtkBox =
  let row = gtkBoxNew(GTKORIENTATIONHORIZONTAL, 12)
  gtkWidgetSetMarginStart(row, 8)
  gtkWidgetSetMarginEnd(row, 8)
  gtkWidgetSetMarginTop(row, 8)
  gtkWidgetSetMarginBottom(row, 8)
  
  let leftBox = gtkBoxNew(GTKORIENTATIONVERTICAL, 4)
  gtkWidgetSetHexpand(leftBox, 1)
  
  let nameText = buddy{"name"}.getStr("Unknown")
  let nameLabel = gtkLabelNew(cstring(nameText))
  gtkWidgetAddCssClass(nameLabel, "title")
  gtkWidgetSetHexpand(nameLabel, 1)
  gtkBoxAppend(leftBox, nameLabel)
  
  let buddyId = buddy{"id"}.getStr("")
  let idLabel = gtkLabelNew(cstring(buddyId[0..min(15, buddyId.len-1)] & "..."))
  gtkWidgetAddCssClass(idLabel, "dim-label")
  gtkWidgetAddCssClass(idLabel, "caption")
  gtkBoxAppend(leftBox, idLabel)
  
  gtkBoxAppend(row, leftBox)
  
  let stateText = buddy{"state"}.getStr("disconnected")
  let stateLabel = gtkLabelNew(cstring(stateText))
  let cssClass = if stateText == "connected": "success" else: "warning"
  gtkWidgetAddCssClass(stateLabel, cstring(cssClass))
  gtkBoxAppend(row, stateLabel)
  
  result = row

proc clearListBox(list: GtkListBox) =
  var child = cast[GtkBox](list)
  discard child

proc refreshUI(userData: pointer): cint {.cdecl.} =
  let statusJson = apiGet("/status")
  
  state.running = statusJson{"running"}.getBool(false)
  
  let buddyName = statusJson{"buddy"}{"name"}.getStr("Unknown")
  let nameText = "Identity: " & buddyName
  gtkLabelSetText(state.buddyNameLabel, cstring(nameText))
  
  let uptime = statusJson{"uptime"}.getInt(0)
  let hours = uptime div 3600
  let mins = (uptime mod 3600) div 60
  let uptimeText = "Uptime: " & $hours & "h " & $mins & "m"
  gtkLabelSetText(state.uptimeLabel, cstring(uptimeText))
  
  let statusText = if state.running: "Running" else: "Stopped"
  gtkLabelSetText(state.statusLabel, cstring(statusText))
  
  if state.running:
    let foldersJson = apiGet("/folders")
    let folders = foldersJson{"folders"}.getElems()
    
    for folder in folders:
      let row = createFolderRow(folder)
      gtkListBoxAppend(state.foldersList, row)
    
    let buddiesJson = apiGet("/buddies")
    let buddies = buddiesJson{"buddies"}.getElems()
    
    for buddy in buddies:
      let row = createBuddyRow(buddy)
      gtkListBoxAppend(state.buddiesList, row)
  
  result = 1

proc createMainWindow(app: GtkApplication): GtkWindow =
  let window = gtkApplicationWindowNew(app)
  gtkWindowSetTitle(window, "BuddyDrive")
  gtkWindowSetDefaultSize(window, 700, 600)
  
  let mainBox = gtkBoxNew(GTKORIENTATIONVERTICAL, 0)
  
  let headerBox = gtkBoxNew(GTKORIENTATIONHORIZONTAL, 12)
  gtkWidgetSetMarginStart(headerBox, 16)
  gtkWidgetSetMarginEnd(headerBox, 16)
  gtkWidgetSetMarginTop(headerBox, 16)
  gtkWidgetSetMarginBottom(headerBox, 8)
  
  let titleBox = gtkBoxNew(GTKORIENTATIONVERTICAL, 4)
  gtkWidgetSetHexpand(titleBox, 1)
  
  let titleLabel = gtkLabelNew("BuddyDrive")
  gtkWidgetAddCssClass(titleLabel, "title-1")
  gtkBoxAppend(titleBox, titleLabel)
  
  state.statusLabel = gtkLabelNew("Stopped")
  gtkWidgetAddCssClass(state.statusLabel, "dim-label")
  gtkBoxAppend(titleBox, state.statusLabel)
  
  gtkBoxAppend(headerBox, titleBox)
  
  let refreshBtn = gtkButtonNewWithLabel("Refresh")
  gtkBoxAppend(headerBox, refreshBtn)
  
  gtkBoxAppend(mainBox, headerBox)
  
  let infoBox = gtkBoxNew(GTKORIENTATIONHORIZONTAL, 24)
  gtkWidgetSetMarginStart(infoBox, 16)
  gtkWidgetSetMarginEnd(infoBox, 16)
  gtkWidgetSetMarginBottom(infoBox, 12)
  
  state.buddyNameLabel = gtkLabelNew("Identity: --")
  gtkBoxAppend(infoBox, state.buddyNameLabel)
  
  state.uptimeLabel = gtkLabelNew("Uptime: 0h 0m")
  gtkBoxAppend(infoBox, state.uptimeLabel)
  
  gtkBoxAppend(mainBox, infoBox)
  
  let foldersCard = createSectionCard("Folders")
  state.foldersList = gtkListBoxNew()
  gtkWidgetAddCssClass(state.foldersList, "boxed-list")
  gtkBoxAppend(foldersCard.content, state.foldersList)
  
  let folderBtnBox = gtkBoxNew(GTKORIENTATIONHORIZONTAL, 8)
  gtkWidgetSetMarginTop(folderBtnBox, 8)
  
  let syncAllBtn = gtkButtonNewWithLabel("Sync All")
  gtkWidgetAddCssClass(syncAllBtn, "suggested-action")
  gtkBoxAppend(folderBtnBox, syncAllBtn)
  
  let addFolderBtn = gtkButtonNewWithLabel("Add Folder...")
  gtkBoxAppend(folderBtnBox, addFolderBtn)
  
  gtkBoxAppend(foldersCard.content, folderBtnBox)
  
  gtkBoxAppend(mainBox, foldersCard.box)
  
  let buddiesCard = createSectionCard("Buddies")
  state.buddiesList = gtkListBoxNew()
  gtkWidgetAddCssClass(state.buddiesList, "boxed-list")
  gtkBoxAppend(buddiesCard.content, state.buddiesList)
  
  let pairBtn = gtkButtonNewWithLabel("Pair with Buddy...")
  gtkWidgetAddCssClass(pairBtn, "suggested-action")
  gtkWidgetSetMarginTop(pairBtn, 8)
  gtkBoxAppend(buddiesCard.content, pairBtn)
  
  gtkBoxAppend(mainBox, buddiesCard.box)
  
  proc onRefreshClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    discard refreshUI(nil)
  
  discard gSignalConnect(cast[GObject](refreshBtn), "clicked", cast[GCallback](onRefreshClick), nil)
  
  proc onSyncAllClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    let foldersJson = apiGet("/folders")
    for folder in foldersJson{"folders"}.getElems():
      let name = folder{"name"}.getStr("")
      if name.len > 0:
        discard apiPost("/sync/" & name)
  
  discard gSignalConnect(cast[GObject](syncAllBtn), "clicked", cast[GCallback](onSyncAllClick), nil)
  
  proc onPairClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    let pairingJson = apiPost("/buddies/pairing-code")
    let code = pairingJson{"pairingCode"}.getStr("")
    let buddyId = pairingJson{"buddyId"}.getStr("")
    echo "Pairing code: ", code, " for buddy: ", buddyId
  
  discard gSignalConnect(cast[GObject](pairBtn), "clicked", cast[GCallback](onPairClick), nil)
  
  gtkWindowSetChild(window, mainBox)
  result = window

proc onActivate(app: GtkApplication, userData: pointer) {.cdecl.} =
  state.client = newHttpClient()
  state.window = createMainWindow(app)
  gtkWidgetShow(state.window)
  
  discard gTimeoutAdd(5000, refreshUI, nil)
  discard refreshUI(nil)

proc installIcon() =
  let iconDir = getHomeDir() / ".local/share/icons/hicolor"
  let sizes = ["48x48", "256x256"]
  
  let iconPath = currentSourcePath().parentDir().parentDir() / "icons" / "buddydrive.png"
  
  if fileExists(iconPath):
    for size in sizes:
      let destDir = iconDir / size / "apps"
      createDir(destDir)
      let dest = destDir / "buddydrive.png"
      if not fileExists(dest):
        copyFile(iconPath, dest)

proc main() =
  installIcon()
  gtkWindowSetDefaultIconName("buddydrive")
  
  app = gtkApplicationNew(AppId, GAPPLICATIONFLAGSNONE)
  discard gSignalConnect(cast[GObject](app), "activate", cast[GCallback](onActivate), nil)
  
  let status = gApplicationRun(cast[GApplication](app), 0, nil)
  quit(status)

when isMainModule:
  main()
