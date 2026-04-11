"use strict";

const REFRESH_INTERVAL = 5000;

// DOM references
const dom = {
  statusBadge: document.getElementById("status-badge"),
  buddyName: document.getElementById("buddy-name"),
  uptime: document.getElementById("uptime"),
  foldersList: document.getElementById("folders-list"),
  foldersEmpty: document.getElementById("folders-empty"),
  buddiesList: document.getElementById("buddies-list"),
  buddiesEmpty: document.getElementById("buddies-empty"),
  logsContent: document.getElementById("logs-content"),
  logsContainer: document.getElementById("logs-container"),
};

// API helpers
const api = {
  async get(endpoint) {
    const res = await fetch(endpoint);
    return res.json();
  },

  async post(endpoint, body = {}) {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return res.json();
  },

  async del(endpoint) {
    const res = await fetch(endpoint, { method: "DELETE" });
    return res.json();
  },
};

// Formatting
const formatBytes = (bytes) => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.floor(bytes / 1024)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${Math.floor(bytes / (1024 * 1024))} MB`;
  return `${Math.floor(bytes / (1024 * 1024 * 1024))} GB`;
};

const formatUptime = (seconds) => {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return `${h}h ${m}m`;
};

// Render functions
const renderFolders = (folders) => {
  dom.foldersList.innerHTML = "";
  dom.foldersEmpty.hidden = folders.length > 0;

  for (const folder of folders) {
    const status = folder.status || {};
    const totalBytes = status.totalBytes || 0;
    const syncedBytes = status.syncedBytes || 0;
    const fileCount = status.fileCount || 0;
    const syncStatus = status.status || "idle";
    const fraction = totalBytes > 0 ? (syncedBytes / totalBytes) * 100 : 0;

    const item = document.createElement("div");
    item.className = "list-item";
    item.innerHTML = `
      <div class="list-item-info">
        <div class="list-item-name">${escHtml(folder.name)}</div>
        <div class="list-item-detail">${escHtml(folder.path)}</div>
        <div class="list-item-detail">
          ${escHtml(syncStatus)} &mdash;
          ${formatBytes(syncedBytes)} / ${formatBytes(totalBytes)}
          (${fileCount} files)
        </div>
      </div>
      <div class="list-item-right">
        ${syncStatus === "syncing" ? `
          <div class="progress-bar">
            <div class="progress-bar-fill" style="width:${fraction}%"></div>
          </div>
        ` : ""}
        <button class="btn btn-small btn-sync" data-folder="${escAttr(folder.name)}">Sync</button>
        <button class="btn btn-small btn-danger btn-remove-folder" data-folder="${escAttr(folder.name)}">Remove</button>
      </div>
    `;
    dom.foldersList.appendChild(item);
  }
};

const renderBuddies = (buddies) => {
  dom.buddiesList.innerHTML = "";
  dom.buddiesEmpty.hidden = buddies.length > 0;

  for (const buddy of buddies) {
    const state = buddy.state || "disconnected";
    const shortId = buddy.id ? buddy.id.substring(0, 16) + "..." : "";
    const latency = buddy.latencyMs >= 0 ? `${buddy.latencyMs}ms` : "";

    const item = document.createElement("div");
    item.className = "list-item";
    item.innerHTML = `
      <div class="list-item-info">
        <div class="list-item-name">${escHtml(buddy.name || "Unknown")}</div>
        <div class="list-item-detail">${escHtml(shortId)}</div>
      </div>
      <div class="list-item-right">
        ${latency ? `<span class="dim">${latency}</span>` : ""}
        <span class="state-${state === "connected" ? "connected" : "disconnected"}">${escHtml(state)}</span>
        <button class="btn btn-small btn-danger btn-remove-buddy" data-buddy="${escAttr(buddy.id)}">Remove</button>
      </div>
    `;
    dom.buddiesList.appendChild(item);
  }
};

const renderStatus = (data) => {
  const running = data.running || false;
  dom.statusBadge.textContent = running ? "Running" : "Stopped";
  dom.statusBadge.className = `badge ${running ? "badge-running" : "badge-stopped"}`;

  const name = data.buddy?.name || "Unknown";
  dom.buddyName.textContent = name;

  const uptime = data.uptime || 0;
  dom.uptime.textContent = running ? formatUptime(uptime) : "";
};

const renderLogs = (logs) => {
  const lines = logs.map((l) => l.raw || "").join("\n");
  dom.logsContent.textContent = lines;
  dom.logsContainer.scrollTop = dom.logsContainer.scrollHeight;
};

// HTML escaping
const escHtml = (str) => {
  const d = document.createElement("div");
  d.textContent = str;
  return d.innerHTML;
};

const escAttr = (str) => escHtml(str).replace(/"/g, "&quot;");

// Refresh all data
const refresh = async () => {
  try {
    const [status, folders, buddies] = await Promise.all([
      api.get("/status"),
      api.get("/folders"),
      api.get("/buddies"),
    ]);
    renderStatus(status);
    renderFolders(folders.folders || []);
    renderBuddies(buddies.buddies || []);
  } catch (e) {
    console.error("Refresh failed:", e);
  }
};

const refreshLogs = async () => {
  try {
    const data = await api.get("/logs");
    renderLogs(data.logs || []);
  } catch (e) {
    console.error("Logs refresh failed:", e);
  }
};

// Dialog helpers
const openDialog = (id) => {
  const dialog = document.getElementById(id);
  dialog.showModal();
};

const closeDialog = (id) => {
  document.getElementById(id).close();
};

// Event handlers
const initEvents = () => {
  // Header buttons
  document.getElementById("btn-refresh").addEventListener("click", () => {
    refresh();
    refreshLogs();
  });

  document.getElementById("btn-settings").addEventListener("click", async () => {
    try {
      const data = await api.get("/config");
      document.getElementById("settings-name").value = data.buddy?.name || "";
      const net = data.network || {};
      document.getElementById("settings-port").value = net.listen_port || "";
      document.getElementById("settings-announce").value = net.announce_addr || "";
      document.getElementById("settings-relay-url").value = net.relay_base_url || "";
      document.getElementById("settings-relay-region").value = net.relay_region || "";
      document.getElementById("settings-sync-start").value = net.sync_window_start || "";
      document.getElementById("settings-sync-end").value = net.sync_window_end || "";
    } catch (e) {
      // leave empty
    }
    openDialog("dialog-settings");
  });

  // Sync All
  document.getElementById("btn-sync-all").addEventListener("click", async () => {
    try {
      const data = await api.get("/folders");
      const folders = data.folders || [];
      await Promise.all(folders.map((f) => api.post(`/sync/${f.name}`)));
      await refresh();
    } catch (e) {
      console.error("Sync all failed:", e);
    }
  });

  // Per-folder sync and remove (delegated)
  dom.foldersList.addEventListener("click", async (e) => {
    const syncBtn = e.target.closest(".btn-sync");
    if (syncBtn) {
      const name = syncBtn.dataset.folder;
      await api.post(`/sync/${name}`);
      await refresh();
      return;
    }

    const removeBtn = e.target.closest(".btn-remove-folder");
    if (removeBtn) {
      const name = removeBtn.dataset.folder;
      if (confirm(`Remove folder "${name}"?`)) {
        await api.del(`/folders/${name}`);
        await refresh();
      }
    }
  });

  // Per-buddy remove (delegated)
  dom.buddiesList.addEventListener("click", async (e) => {
    const removeBtn = e.target.closest(".btn-remove-buddy");
    if (removeBtn) {
      const id = removeBtn.dataset.buddy;
      if (confirm("Remove this buddy?")) {
        await api.del(`/buddies/${id}`);
        await refresh();
      }
    }
  });

  // Add Folder dialog
  document.getElementById("btn-add-folder").addEventListener("click", () => {
    document.getElementById("folder-name").value = "";
    document.getElementById("folder-path").value = "";
    document.getElementById("folder-encrypt").checked = true;
    openDialog("dialog-add-folder");
  });

  document.getElementById("btn-cancel-folder").addEventListener("click", () => {
    closeDialog("dialog-add-folder");
  });

  document.getElementById("dialog-add-folder").addEventListener("close", async () => {
    const dialog = document.getElementById("dialog-add-folder");
    if (dialog.returnValue !== "default") return;
  });

  document.getElementById("btn-submit-folder").addEventListener("click", async (e) => {
    e.preventDefault();
    const name = document.getElementById("folder-name").value.trim();
    const path = document.getElementById("folder-path").value.trim();
    const encrypted = document.getElementById("folder-encrypt").checked;
    if (!name || !path) return;

    await api.post("/folders", { name, path, encrypted });
    closeDialog("dialog-add-folder");
    await refresh();
  });

  // Pair Buddy dialog
  document.getElementById("btn-pair-buddy").addEventListener("click", () => {
    document.getElementById("buddy-id").value = "";
    document.getElementById("buddy-pair-name").value = "";
    document.getElementById("buddy-code").value = "";
    openDialog("dialog-pair-buddy");
  });

  document.getElementById("btn-cancel-pair").addEventListener("click", () => {
    closeDialog("dialog-pair-buddy");
  });

  document.getElementById("btn-submit-pair").addEventListener("click", async (e) => {
    e.preventDefault();
    const buddyId = document.getElementById("buddy-id").value.trim();
    const buddyName = document.getElementById("buddy-pair-name").value.trim();
    const code = document.getElementById("buddy-code").value.trim();
    if (!buddyId || !code) return;

    await api.post("/buddies/pair", { buddyId, buddyName, code });
    closeDialog("dialog-pair-buddy");
    await refresh();
  });

  // Settings dialog
  document.getElementById("btn-cancel-settings").addEventListener("click", () => {
    closeDialog("dialog-settings");
  });

  document.getElementById("btn-submit-settings").addEventListener("click", async (e) => {
    e.preventDefault();
    const body = { buddy: {}, network: {} };

    const name = document.getElementById("settings-name").value.trim();
    if (name) body.buddy.name = name;

    const port = document.getElementById("settings-port").value.trim();
    if (port) body.network.listen_port = parseInt(port, 10);

    const announce = document.getElementById("settings-announce").value.trim();
    if (announce) body.network.announce_addr = announce;

    const relayUrl = document.getElementById("settings-relay-url").value.trim();
    if (relayUrl) body.network.relay_base_url = relayUrl;

    const relayRegion = document.getElementById("settings-relay-region").value.trim();
    if (relayRegion) body.network.relay_region = relayRegion;

    const syncStart = document.getElementById("settings-sync-start").value.trim();
    if (syncStart) body.network.sync_window_start = syncStart;

    const syncEnd = document.getElementById("settings-sync-end").value.trim();
    if (syncEnd) body.network.sync_window_end = syncEnd;

    await api.post("/config", body);
    closeDialog("dialog-settings");
    await refresh();
  });

  // Logs refresh
  document.getElementById("btn-refresh-logs").addEventListener("click", refreshLogs);
};

// Init
initEvents();
refresh();
refreshLogs();
setInterval(refresh, REFRESH_INTERVAL);
