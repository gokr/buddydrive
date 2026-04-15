import std/[os, json, httpclient, strutils]

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
  GtkGrid* = pointer
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
proc gtkWidgetGetFirstChild*(widget: GtkWidget): GtkWidget {.cdecl, importc: "gtk_widget_get_first_child".}
proc gtkWidgetGetNextSibling*(widget: GtkWidget): GtkWidget {.cdecl, importc: "gtk_widget_get_next_sibling".}
proc gtkProgressBarNew*(): GtkProgressBar {.cdecl, importc: "gtk_progress_bar_new".}
proc gtkProgressBarSetFraction*(bar: GtkProgressBar, fraction: cdouble) {.cdecl, importc: "gtk_progress_bar_set_fraction".}
proc gtkProgressBarSetText*(bar: GtkProgressBar, text: cstring) {.cdecl, importc: "gtk_progress_bar_set_text".}
proc gtkProgressBarSetShowText*(bar: GtkProgressBar, showText: cint) {.cdecl, importc: "gtk_progress_bar_set_show_text".}
proc gtkScrolledWindowNew*(): GtkScrolledWindow {.cdecl, importc: "gtk_scrolled_window_new".}
proc gtkScrolledWindowSetChild*(window: GtkScrolledWindow, child: GtkWidget) {.cdecl, importc: "gtk_scrolled_window_set_child".}
proc gtkScrolledWindowSetPolicy*(window: GtkScrolledWindow, hscrollbar: cint, vscrollbar: cint) {.cdecl, importc: "gtk_scrolled_window_set_policy".}
proc gtkGridNew*(): GtkGrid {.cdecl, importc: "gtk_grid_new".}
proc gtkGridAttach*(grid: GtkGrid, child: GtkWidget, left: cint, top: cint, width: cint, height: cint) {.cdecl, importc: "gtk_grid_attach".}
proc gtkGridColumnSetSpacing*(grid: GtkGrid, spacing: cint) {.cdecl, importc: "gtk_grid_set_column_spacing".}
proc gtkGridRowSetSpacing*(grid: GtkGrid, spacing: cint) {.cdecl, importc: "gtk_grid_set_row_spacing".}
proc gtkWidgetSetHalign*(widget: GtkWidget, align: cint) {.cdecl, importc: "gtk_widget_set_halign".}
proc gtkLabelSetWrap*(label: GtkLabel, wrap: cint) {.cdecl, importc: "gtk_label_set_wrap".}
proc gtkLabelSetWrapMode*(label: GtkLabel, mode: cint) {.cdecl, importc: "gtk_label_set_wrap_mode".}
proc gTimeoutAdd*(interval: cuint, function: GSourceFunc, data: pointer): cuint {.cdecl, importc: "g_timeout_add".}

proc gSignalConnect*(instance: GObject, signal: cstring, cHandler: GCallback, data: pointer): culong =
  gSignalConnectData(instance, signal, cHandler, data, nil, 0.GConnectFlags)

proc gtkWindowSetDefaultIconName*(name: cstring) {.cdecl, importc: "gtk_window_set_default_icon_name".}

# Additional GTK imports for dialogs
proc gtkDialogNew*(): GtkWindow {.cdecl, importc: "gtk_dialog_new".}
proc gtkDialogAddButton*(dialog: GtkWindow, buttonText: cstring, responseId: cint): GtkButton {.cdecl, importc: "gtk_dialog_add_button".}
proc gtkDialogGetContentArea*(dialog: GtkWindow): GtkBox {.cdecl, importc: "gtk_dialog_get_content_area".}
proc gtkEntryNew*(): pointer {.cdecl, importc: "gtk_entry_new".}
proc gtkEditableGetText*(entry: pointer): cstring {.cdecl, importc: "gtk_editable_get_text".}
proc gtkEditableSetText*(entry: pointer, text: cstring) {.cdecl, importc: "gtk_editable_set_text".}
proc gtkEntrySetPlaceholderText*(entry: pointer, text: cstring) {.cdecl, importc: "gtk_entry_set_placeholder_text".}
proc gtkCheckButtonNew*(): pointer {.cdecl, importc: "gtk_check_button_new".}
proc gtkCheckButtonGetActive*(button: pointer): cint {.cdecl, importc: "gtk_check_button_get_active".}
proc gtkCheckButtonSetLabel*(button: pointer, label: cstring) {.cdecl, importc: "gtk_check_button_set_label".}
proc gtkWidgetGrabFocus*(widget: GtkWidget) {.cdecl, importc: "gtk_widget_grab_focus".}
proc gtkWindowSetTransientFor*(window: GtkWindow, parent: GtkWindow) {.cdecl, importc: "gtk_window_set_transient_for".}
proc gtkWindowSetModal*(window: GtkWindow, modal: cint) {.cdecl, importc: "gtk_window_set_modal".}

const
  GTK_RESPONSE_OK = -5.cint
  GTK_RESPONSE_CANCEL = -6.cint

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
    recoveryStatusLabel: GtkLabel
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

proc refreshUI(userData: pointer): cint {.cdecl.}

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
  let shortBuddyId =
    if buddyId.len == 0: ""
    elif buddyId.len <= 16: buddyId
    else: buddyId[0 .. 15] & "..."
  let idLabel = gtkLabelNew(cstring(shortBuddyId))
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
  var child = gtkWidgetGetFirstChild(list)
  while child != nil:
    let next = gtkWidgetGetNextSibling(child)
    gtkListBoxRemove(list, child)
    child = next

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
  
  let recoveryJson = apiGet("/recovery")
  let recoveryEnabled = recoveryJson{"enabled"}.getBool(false)
  let recoveryText = if recoveryEnabled: "Recovery enabled" else: "Not set up"
  gtkLabelSetText(state.recoveryStatusLabel, cstring(recoveryText))
  
  if state.running:
    let foldersJson = apiGet("/folders")
    let folders = foldersJson{"folders"}.getElems()

    clearListBox(state.foldersList)
    for folder in folders:
      let row = createFolderRow(folder)
      gtkListBoxAppend(state.foldersList, row)

    let buddiesJson = apiGet("/buddies")
    let buddies = buddiesJson{"buddies"}.getElems()

    clearListBox(state.buddiesList)
    for buddy in buddies:
      let row = createBuddyRow(buddy)
      gtkListBoxAppend(state.buddiesList, row)
  else:
    clearListBox(state.foldersList)
    clearListBox(state.buddiesList)
  
  result = 1

# Dialog helper procs
type
  AddFolderData = object
    dialog: GtkWindow
    nameEntry: pointer
    pathEntry: pointer
    encryptCheck: pointer
  
  PairBuddyData = object
    dialog: GtkWindow
    idEntry: pointer
    nameEntry: pointer
    codeEntry: pointer
  
  SettingsData = object
    dialog: GtkWindow
    nameEntry: pointer
    portEntry: pointer
    announceEntry: pointer
    relayUrlEntry: pointer
    relayRegionEntry: pointer
    syncStartEntry: pointer
    syncEndEntry: pointer

  SetupRecoveryData = object
    dialog: GtkWindow
    wordEntries: ptr UncheckedArray[pointer]
    verifyLabel: GtkLabel

  RecoverData = object
    dialog: GtkWindow
    wordEntries: ptr UncheckedArray[pointer]

proc onAddFolderResponse(w: GtkWindow, responseId: cint, userData: pointer) {.cdecl.} =
  let data = cast[ptr AddFolderData](userData)
  if responseId == GTK_RESPONSE_OK:
    let name = $gtkEditableGetText(data.nameEntry)
    let path = $gtkEditableGetText(data.pathEntry)
    let encrypted = gtkCheckButtonGetActive(data.encryptCheck) == 1
    
    if name.len > 0 and path.len > 0:
      let body = %*{"name": name, "path": path, "encrypted": encrypted}
      discard apiPost("/folders", body)
      discard refreshUI(nil)
  
  gtkWidgetSetVisible(data.dialog, 0)
  deallocShared(userData)

proc onPairBuddyResponse(w: GtkWindow, responseId: cint, userData: pointer) {.cdecl.} =
  let data = cast[ptr PairBuddyData](userData)
  if responseId == GTK_RESPONSE_OK:
    let buddyId = $gtkEditableGetText(data.idEntry)
    let buddyName = $gtkEditableGetText(data.nameEntry)
    let code = $gtkEditableGetText(data.codeEntry)
    
    if buddyId.len > 0 and code.len > 0:
      let body = %*{"buddyId": buddyId, "buddyName": buddyName, "code": code}
      discard apiPost("/buddies/pair", body)
      discard refreshUI(nil)
  
  gtkWidgetSetVisible(data.dialog, 0)
  deallocShared(userData)

proc onSettingsResponse(w: GtkWindow, responseId: cint, userData: pointer) {.cdecl.} =
  let data = cast[ptr SettingsData](userData)
  if responseId == GTK_RESPONSE_OK:
    var body = %*{"buddy": {}, "network": {}}
    
    let name = $gtkEditableGetText(data.nameEntry)
    if name.len > 0:
      body["buddy"]["name"] = %name
    
    let portStr = $gtkEditableGetText(data.portEntry)
    if portStr.len > 0:
      try:
        body["network"]["listen_port"] = %portStr.parseInt()
      except:
        discard
    
    let announce = $gtkEditableGetText(data.announceEntry)
    if announce.len > 0:
      body["network"]["announce_addr"] = %announce
    
    let relayUrl = $gtkEditableGetText(data.relayUrlEntry)
    if relayUrl.len > 0:
      body["network"]["relay_base_url"] = %relayUrl
    
    let relayRegion = $gtkEditableGetText(data.relayRegionEntry)
    if relayRegion.len > 0:
      body["network"]["relay_region"] = %relayRegion
    
    let syncStart = $gtkEditableGetText(data.syncStartEntry)
    if syncStart.len > 0:
      body["network"]["sync_window_start"] = %syncStart
    
    let syncEnd = $gtkEditableGetText(data.syncEndEntry)
    if syncEnd.len > 0:
      body["network"]["sync_window_end"] = %syncEnd
    
    discard apiPost("/config", body)
    discard refreshUI(nil)
  
  gtkWidgetSetVisible(data.dialog, 0)
  deallocShared(userData)

proc showAddFolderDialog() =
  let dialog = gtkDialogNew()
  gtkWindowSetTitle(dialog, "Add Folder")
  gtkWindowSetModal(dialog, 1)
  gtkWindowSetTransientFor(dialog, state.window)
  gtkWindowSetDefaultSize(dialog, 450, 250)
  
  discard gtkDialogAddButton(dialog, "Cancel", GTK_RESPONSE_CANCEL)
  discard gtkDialogAddButton(dialog, "Add", GTK_RESPONSE_OK)
  
  let content = gtkDialogGetContentArea(dialog)
  gtkWidgetSetMarginStart(content, 16)
  gtkWidgetSetMarginEnd(content, 16)
  gtkWidgetSetMarginTop(content, 16)
  gtkWidgetSetMarginBottom(content, 16)
  
  let nameLabel = gtkLabelNew("Folder name:")
  gtkWidgetSetHexpand(nameLabel, 1)
  gtkBoxAppend(content, nameLabel)
  
  let nameEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(nameEntry, "My Documents")
  gtkWidgetSetMarginBottom(nameEntry, 12)
  gtkBoxAppend(content, nameEntry)
  
  let pathLabel = gtkLabelNew("Folder path:")
  gtkBoxAppend(content, pathLabel)
  
  let pathEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(pathEntry, "/home/user/Documents")
  gtkWidgetSetMarginBottom(pathEntry, 12)
  gtkBoxAppend(content, pathEntry)
  
  let encryptCheck = gtkCheckButtonNew()
  gtkCheckButtonSetLabel(encryptCheck, "Encrypt folder contents")
  gtkWidgetSetMarginBottom(encryptCheck, 8)
  gtkBoxAppend(content, encryptCheck)
  
  let data = cast[ptr AddFolderData](allocShared0(sizeof(AddFolderData)))
  data.dialog = dialog
  data.nameEntry = nameEntry
  data.pathEntry = pathEntry
  data.encryptCheck = encryptCheck
  
  discard gSignalConnect(cast[GObject](dialog), "response", cast[GCallback](onAddFolderResponse), cast[pointer](data))
  
  gtkWidgetShow(dialog)
  gtkWidgetGrabFocus(nameEntry)

proc showPairBuddyDialog() =
  let dialog = gtkDialogNew()
  gtkWindowSetTitle(dialog, "Pair with Buddy")
  gtkWindowSetModal(dialog, 1)
  gtkWindowSetTransientFor(dialog, state.window)
  gtkWindowSetDefaultSize(dialog, 450, 280)
  
  discard gtkDialogAddButton(dialog, "Cancel", GTK_RESPONSE_CANCEL)
  discard gtkDialogAddButton(dialog, "Pair", GTK_RESPONSE_OK)
  
  let content = gtkDialogGetContentArea(dialog)
  gtkWidgetSetMarginStart(content, 16)
  gtkWidgetSetMarginEnd(content, 16)
  gtkWidgetSetMarginTop(content, 16)
  gtkWidgetSetMarginBottom(content, 16)
  
  let infoLabel = gtkLabelNew("Enter your buddy's information:")
  gtkWidgetSetMarginBottom(infoLabel, 12)
  gtkBoxAppend(content, infoLabel)
  
  let idLabel = gtkLabelNew("Buddy ID:")
  gtkBoxAppend(content, idLabel)
  
  let idEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(idEntry, "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
  gtkWidgetSetMarginBottom(idEntry, 8)
  gtkBoxAppend(content, idEntry)
  
  let nameLabel = gtkLabelNew("Buddy name (optional):")
  gtkBoxAppend(content, nameLabel)
  
  let nameEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(nameEntry, "Alice")
  gtkWidgetSetMarginBottom(nameEntry, 8)
  gtkBoxAppend(content, nameEntry)
  
  let codeLabel = gtkLabelNew("Pairing code:")
  gtkBoxAppend(content, codeLabel)
  
  let codeEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(codeEntry, "ABCD-EFGH")
  gtkBoxAppend(content, codeEntry)
  
  let data = cast[ptr PairBuddyData](allocShared0(sizeof(PairBuddyData)))
  data.dialog = dialog
  data.idEntry = idEntry
  data.nameEntry = nameEntry
  data.codeEntry = codeEntry
  
  discard gSignalConnect(cast[GObject](dialog), "response", cast[GCallback](onPairBuddyResponse), cast[pointer](data))
  
  gtkWidgetShow(dialog)
  gtkWidgetGrabFocus(idEntry)

proc showSettingsDialog() =
  let configJson = apiGet("/config")
  
  let dialog = gtkDialogNew()
  gtkWindowSetTitle(dialog, "Settings")
  gtkWindowSetModal(dialog, 1)
  gtkWindowSetTransientFor(dialog, state.window)
  gtkWindowSetDefaultSize(dialog, 500, 450)
  
  discard gtkDialogAddButton(dialog, "Cancel", GTK_RESPONSE_CANCEL)
  discard gtkDialogAddButton(dialog, "Save", GTK_RESPONSE_OK)
  
  let content = gtkDialogGetContentArea(dialog)
  gtkWidgetSetMarginStart(content, 16)
  gtkWidgetSetMarginEnd(content, 16)
  gtkWidgetSetMarginTop(content, 16)
  gtkWidgetSetMarginBottom(content, 16)
  
  # Identity section
  let identityLabel = gtkLabelNew("Identity")
  gtkWidgetAddCssClass(identityLabel, "title-3")
  gtkWidgetSetMarginBottom(identityLabel, 8)
  gtkBoxAppend(content, identityLabel)
  
  let nameLabel = gtkLabelNew("Your name:")
  gtkBoxAppend(content, nameLabel)
  
  let nameEntry = gtkEntryNew()
  let currentName = configJson{"buddy"}{"name"}.getStr("")
  if currentName.len > 0:
    gtkEditableSetText(nameEntry, currentName.cstring)
  gtkWidgetSetMarginBottom(nameEntry, 16)
  gtkBoxAppend(content, nameEntry)
  
  # Network section
  let networkLabel = gtkLabelNew("Network")
  gtkWidgetAddCssClass(networkLabel, "title-3")
  gtkWidgetSetMarginBottom(networkLabel, 8)
  gtkBoxAppend(content, networkLabel)
  
  let portLabel = gtkLabelNew("Listen port:")
  gtkBoxAppend(content, portLabel)
  
  let portEntry = gtkEntryNew()
  let currentPort = configJson{"network"}{"listen_port"}.getInt(41721)
  gtkEditableSetText(portEntry, cstring($currentPort))
  gtkWidgetSetMarginBottom(portEntry, 8)
  gtkBoxAppend(content, portEntry)
  
  let announceLabel = gtkLabelNew("Announce address (optional):")
  gtkBoxAppend(content, announceLabel)
  
  let announceEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(announceEntry, "/ip4/203.0.113.10/tcp/41721")
  let currentAnnounce = configJson{"network"}{"announce_addr"}.getStr("")
  if currentAnnounce.len > 0:
    gtkEditableSetText(announceEntry, currentAnnounce.cstring)
  gtkWidgetSetMarginBottom(announceEntry, 16)
  gtkBoxAppend(content, announceEntry)
  
  # Relay section
  let relayLabel = gtkLabelNew("Relay Fallback")
  gtkWidgetAddCssClass(relayLabel, "title-3")
  gtkWidgetSetMarginBottom(relayLabel, 8)
  gtkBoxAppend(content, relayLabel)
  
  let relayUrlLabel = gtkLabelNew("Relay base URL:")
  gtkBoxAppend(content, relayUrlLabel)
  
  let relayUrlEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(relayUrlEntry, "https://buddydrive.net/relays")
  let currentRelayUrl = configJson{"network"}{"relay_base_url"}.getStr("")
  if currentRelayUrl.len > 0:
    gtkEditableSetText(relayUrlEntry, currentRelayUrl.cstring)
  gtkWidgetSetMarginBottom(relayUrlEntry, 8)
  gtkBoxAppend(content, relayUrlEntry)
  
  let relayRegionLabel = gtkLabelNew("Relay region:")
  gtkBoxAppend(content, relayRegionLabel)
  
  let relayRegionEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(relayRegionEntry, "eu")
  let currentRelayRegion = configJson{"network"}{"relay_region"}.getStr("")
  if currentRelayRegion.len > 0:
    gtkEditableSetText(relayRegionEntry, currentRelayRegion.cstring)
  gtkWidgetSetMarginBottom(relayRegionEntry, 16)
  gtkBoxAppend(content, relayRegionEntry)
  
  # Sync window section
  let syncLabel = gtkLabelNew("Sync Window")
  gtkWidgetAddCssClass(syncLabel, "title-3")
  gtkWidgetSetMarginBottom(syncLabel, 8)
  gtkBoxAppend(content, syncLabel)
  
  let syncStartLabel = gtkLabelNew("Start time (HH:MM, leave empty for always):")
  gtkBoxAppend(content, syncStartLabel)
  
  let syncStartEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(syncStartEntry, "22:00")
  let currentSyncStart = configJson{"network"}{"sync_window_start"}.getStr("")
  if currentSyncStart.len > 0:
    gtkEditableSetText(syncStartEntry, currentSyncStart.cstring)
  gtkWidgetSetMarginBottom(syncStartEntry, 8)
  gtkBoxAppend(content, syncStartEntry)
  
  let syncEndLabel = gtkLabelNew("End time (HH:MM):")
  gtkBoxAppend(content, syncEndLabel)
  
  let syncEndEntry = gtkEntryNew()
  gtkEntrySetPlaceholderText(syncEndEntry, "06:00")
  let currentSyncEnd = configJson{"network"}{"sync_window_end"}.getStr("")
  if currentSyncEnd.len > 0:
    gtkEditableSetText(syncEndEntry, currentSyncEnd.cstring)
  gtkBoxAppend(content, syncEndEntry)
  
  let data = cast[ptr SettingsData](allocShared0(sizeof(SettingsData)))
  data.dialog = dialog
  data.nameEntry = nameEntry
  data.portEntry = portEntry
  data.announceEntry = announceEntry
  data.relayUrlEntry = relayUrlEntry
  data.relayRegionEntry = relayRegionEntry
  data.syncStartEntry = syncStartEntry
  data.syncEndEntry = syncEndEntry
  
  discard gSignalConnect(cast[GObject](dialog), "response", cast[GCallback](onSettingsResponse), cast[pointer](data))
  
  gtkWidgetShow(dialog)

proc showSetupRecoveryDialog() =
  let dialog = gtkDialogNew()
  gtkWindowSetTitle(dialog, "Set Up Recovery")
  gtkWindowSetModal(dialog, 1)
  gtkWindowSetTransientFor(dialog, state.window)
  gtkWindowSetDefaultSize(dialog, 600, 500)
  
  discard gtkDialogAddButton(dialog, "Cancel", GTK_RESPONSE_CANCEL)
  discard gtkDialogAddButton(dialog, "Verify Words", -10)
  
  let content = gtkDialogGetContentArea(dialog)
  gtkWidgetSetMarginStart(content, 16)
  gtkWidgetSetMarginEnd(content, 16)
  gtkWidgetSetMarginTop(content, 16)
  gtkWidgetSetMarginBottom(content, 16)
  
  let result = apiPost("/recovery/setup")
  let words = result{"words"}.getElems()
  
  let warningLabel = gtkLabelNew("Write down these 12 words and keep them safe.\nAnyone with these words can recover your data.")
  gtkWidgetAddCssClass(warningLabel, "warning")
  gtkWidgetSetMarginBottom(warningLabel, 16)
  gtkBoxAppend(content, warningLabel)
  
  let grid = gtkGridNew()
  gtkGridColumnSetSpacing(grid, 12)
  gtkGridRowSetSpacing(grid, 8)
  
  var wordEntries = cast[ptr UncheckedArray[pointer]](allocShared0(12 * sizeof(pointer)))
  
  for i in 0 ..< 12:
    let numLabel = gtkLabelNew(cstring($ (i + 1) & "."))
    gtkWidgetAddCssClass(numLabel, "dim-label")
    gtkGridAttach(grid, numLabel, cint(0), cint(i), 1, 1)
    
    let wordText = if i < words.len: words[i].getStr("") else: ""
    let wordLabel = gtkLabelNew(cstring(wordText))
    gtkWidgetAddCssClass(wordLabel, "heading")
    gtkGridAttach(grid, wordLabel, cint(1), cint(i), 1, 1)
    
    let entry = gtkEntryNew()
    gtkEntrySetPlaceholderText(entry, "type word here")
    gtkGridAttach(grid, entry, cint(2), cint(i), 1, 1)
    wordEntries[i] = entry
  
  gtkBoxAppend(content, grid)
  
  let verifyLabel = gtkLabelNew("")
  gtkWidgetSetMarginTop(verifyLabel, 12)
  gtkBoxAppend(content, verifyLabel)
  
  let data = cast[ptr SetupRecoveryData](allocShared0(sizeof(SetupRecoveryData)))
  data.dialog = dialog
  data.wordEntries = wordEntries
  data.verifyLabel = verifyLabel
  
  proc onSetupRecoveryResponse(w: GtkWindow, responseId: cint, userData: pointer) {.cdecl.} =
    let d = cast[ptr SetupRecoveryData](userData)
    
    if responseId == -10:
      var correct = 0
      var checked = 0
      for i in 0 ..< 12:
        let typed = $gtkEditableGetText(d.wordEntries[i])
        if typed.len > 0:
          inc checked
          let result = apiPost("/recovery/verify-word", %*{"index": i, "word": typed})
          if result{"correct"}.getBool(false):
            inc correct
      
      if checked == 0:
        gtkLabelSetText(d.verifyLabel, "Please type some words to verify.")
      elif correct == checked:
        gtkLabelSetText(d.verifyLabel, "All words correct! Recovery is set up.")
        discard apiPost("/recovery/sync-config")
        discard refreshUI(nil)
      else:
        gtkLabelSetText(d.verifyLabel, cstring($correct & " of " & $checked & " words correct. Try again."))
    else:
      gtkWidgetSetVisible(d.dialog, 0)
      deallocShared(userData)
  
  discard gSignalConnect(cast[GObject](dialog), "response", cast[GCallback](onSetupRecoveryResponse), cast[pointer](data))
  
  gtkWidgetShow(dialog)

proc showRecoverDialog() =
  let dialog = gtkDialogNew()
  gtkWindowSetTitle(dialog, "Recover from Mnemonic")
  gtkWindowSetModal(dialog, 1)
  gtkWindowSetTransientFor(dialog, state.window)
  gtkWindowSetDefaultSize(dialog, 600, 500)
  
  discard gtkDialogAddButton(dialog, "Cancel", GTK_RESPONSE_CANCEL)
  discard gtkDialogAddButton(dialog, "Recover", GTK_RESPONSE_OK)
  
  let content = gtkDialogGetContentArea(dialog)
  gtkWidgetSetMarginStart(content, 16)
  gtkWidgetSetMarginEnd(content, 16)
  gtkWidgetSetMarginTop(content, 16)
  gtkWidgetSetMarginBottom(content, 16)
  
  let infoLabel = gtkLabelNew("Enter your 12-word recovery phrase:")
  gtkWidgetSetMarginBottom(infoLabel, 12)
  gtkBoxAppend(content, infoLabel)
  
  let grid = gtkGridNew()
  gtkGridColumnSetSpacing(grid, 12)
  gtkGridRowSetSpacing(grid, 8)
  
  var wordEntries = cast[ptr UncheckedArray[pointer]](allocShared0(12 * sizeof(pointer)))
  
  for i in 0 ..< 12:
    let numLabel = gtkLabelNew(cstring($ (i + 1) & "."))
    gtkWidgetAddCssClass(numLabel, "dim-label")
    gtkGridAttach(grid, numLabel, cint(0), cint(i), 1, 1)
    
    let entry = gtkEntryNew()
    gtkGridAttach(grid, entry, cint(1), cint(i), 1, 1)
    wordEntries[i] = entry
  
  gtkBoxAppend(content, grid)
  
  let data = cast[ptr RecoverData](allocShared0(sizeof(RecoverData)))
  data.dialog = dialog
  data.wordEntries = wordEntries
  
  proc onRecoverResponse(w: GtkWindow, responseId: cint, userData: pointer) {.cdecl.} =
    let d = cast[ptr RecoverData](userData)
    if responseId == GTK_RESPONSE_OK:
      var words: seq[string] = @[]
      for i in 0 ..< 12:
        let word = $gtkEditableGetText(d.wordEntries[i])
        words.add(word)
      
      let mnemonic = words.join(" ")
      let result = apiPost("/recovery/recover", %*{"mnemonic": mnemonic})
      
      if result{"ok"}.getBool(false):
        discard apiPost("/recovery/sync-config")
        discard refreshUI(nil)
    else:
      gtkWidgetSetVisible(d.dialog, 0)
      deallocShared(userData)
  
  discard gSignalConnect(cast[GObject](dialog), "response", cast[GCallback](onRecoverResponse), cast[pointer](data))
  
  gtkWidgetShow(dialog)
  gtkWidgetGrabFocus(wordEntries[0])

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
  
  # Settings card
  let settingsCard = createSectionCard("Settings")
  
  let settingsBtn = gtkButtonNewWithLabel("Configure Settings...")
  gtkWidgetAddCssClass(settingsBtn, "suggested-action")
  gtkBoxAppend(settingsCard.content, settingsBtn)
  
  gtkBoxAppend(mainBox, settingsCard.box)
  
  let recoveryCard = createSectionCard("Recovery")
  
  state.recoveryStatusLabel = gtkLabelNew("Not set up")
  gtkWidgetAddCssClass(state.recoveryStatusLabel, "dim-label")
  gtkWidgetSetMarginBottom(state.recoveryStatusLabel, 8)
  gtkBoxAppend(recoveryCard.content, state.recoveryStatusLabel)
  
  let recoveryBtnBox = gtkBoxNew(GTKORIENTATIONHORIZONTAL, 8)
  
  let setupRecoveryBtn = gtkButtonNewWithLabel("Set Up Recovery...")
  gtkWidgetAddCssClass(setupRecoveryBtn, "suggested-action")
  gtkBoxAppend(recoveryBtnBox, setupRecoveryBtn)
  
  let recoverBtn = gtkButtonNewWithLabel("Recover from Mnemonic...")
  gtkBoxAppend(recoveryBtnBox, recoverBtn)
  
  gtkBoxAppend(recoveryCard.content, recoveryBtnBox)
  
  gtkBoxAppend(mainBox, recoveryCard.box)
  
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
  
  proc onAddFolderClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    showAddFolderDialog()
  
  discard gSignalConnect(cast[GObject](addFolderBtn), "clicked", cast[GCallback](onAddFolderClick), nil)
  
  proc onPairClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    showPairBuddyDialog()
  
  discard gSignalConnect(cast[GObject](pairBtn), "clicked", cast[GCallback](onPairClick), nil)
  
  proc onSettingsClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    showSettingsDialog()
  
  discard gSignalConnect(cast[GObject](settingsBtn), "clicked", cast[GCallback](onSettingsClick), nil)
  
  proc onSetupRecoveryClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    showSetupRecoveryDialog()
  
  discard gSignalConnect(cast[GObject](setupRecoveryBtn), "clicked", cast[GCallback](onSetupRecoveryClick), nil)
  
  proc onRecoverClick(btn: GtkButton, userData: pointer) {.cdecl.} =
    showRecoverDialog()
  
  discard gSignalConnect(cast[GObject](recoverBtn), "clicked", cast[GCallback](onRecoverClick), nil)
  
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
