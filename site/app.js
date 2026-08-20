// app.js — eLSOP Customer SOP Matrix

let filtered = [];
let sortCol = -1;
let sortAsc = true;

function esc(s) {
  if (!s) return "";
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function normalizeType(t) {
  if (!t) return "";
  const u = t.trim().toUpperCase();
  if (u.includes("WHOLESALE") || u.includes("DISTRIBUTOR")) return "Wholesaler/Distributor";
  if (u.includes("DIRECT") && u.includes("INDIRECT")) return "Direct/Indirect";
  if (u.includes("INDIRECT")) return "Indirect";
  if (u.includes("DIRECT")) return "Direct";
  if (u.includes("THIRD")) return "Third Party";
  return t.trim();
}

function typeClass(t) {
  const u = (t || "").toUpperCase();
  if (u.includes("WHOLESALE") || u.includes("DISTRIBUTOR")) return "type-wholesale";
  if (u.includes("INDIRECT")) return "type-indirect";
  if (u.includes("DIRECT")) return "type-direct";
  if (u.includes("THIRD")) return "type-third";
  return "type-unknown";
}

function portalFromBackup(backup) {
  if (!backup) return null;
  const m = backup.match(/is there a customer portal\?\s*(YES|NO)/i);
  return m ? m[1].toUpperCase() : null;
}

function ynBadge(v) {
  const s = (v || "").toString().trim().toUpperCase();
  if (s === "Y" || s === "YES") return `<span class="yn-badge yn-yes">Y</span>`;
  if (s === "N" || s === "NO")  return `<span class="yn-badge yn-no">N</span>`;
  return `<span class="yn-badge yn-na">—</span>`;
}

function signons(raw) {
  if (!raw) return [];
  return raw.split(/[\n,]+/).map(s => s.trim()).filter(Boolean);
}

function clientList(raw) {
  if (!raw) return [];
  return raw.split(/[\n,]+/).map(s => s.trim()).filter(s => s && s.toUpperCase() !== "N");
}

function buildRow(c, idx) {
  const type    = normalizeType(c.type);
  const sgns    = signons(c.signon);
  const clients = clientList(c.client);
  const portal  = portalFromBackup(c.backup);

  const signonHTML = sgns.length
    ? sgns.map(s => `<span class="signon-badge">${esc(s)}</span>`).join(" ")
    : `<span style="color:#9ca3af">—</span>`;

  const portalHTML = portal === "YES"
    ? `<span class="portal-chip portal-yes">✓ Yes</span>`
    : portal === "NO"
    ? `<span class="portal-chip portal-no">✕ No</span>`
    : `<span class="portal-chip portal-na">—</span>`;

  const sopHTML = c.sop
    ? `<a class="sop-link" href="sops/${esc(c.sop)}" download onclick="event.stopPropagation()">📄 Download</a>`
    : `<span style="color:#9ca3af;font-size:11px;">—</span>`;

  const claimsShort = c.claims.length > 130 ? c.claims.slice(0, 130) + "…" : c.claims;

  // Parse backup to surface the key line
  const backupLines = c.backup.split("\n").map(s => s.trim()).filter(Boolean);
  const autoLine  = backupLines.find(l => /^(automated|non-automated)/i.test(l)) || "";
  const emailLine = backupLines.find(l => l.includes("@") && !l.startsWith("•") && !l.toLowerCase().includes("if yes")) || "";
  let backupHTML = "";
  if (autoLine) backupHTML += `<strong>${esc(autoLine)}</strong>`;
  if (emailLine && emailLine !== autoLine) backupHTML += `<br><span style="color:#57606a;">${esc(emailLine)}</span>`;
  if (!backupHTML) backupHTML = `<span style="color:#9ca3af;">—</span>`;

  const clientHTML = clients.length
    ? `<span style="font-size:11.5px;">${esc(clients.slice(0, 3).join(" · "))}${clients.length > 3 ? ` +${clients.length - 3}` : ""}</span>`
    : `<span style="color:#9ca3af;">—</span>`;

  return `<tr data-idx="${idx}" onclick="openDrawer(${idx})">
  <td class="col-name"><div class="cust-name">${esc(c.name)}</div></td>
  <td class="col-signon"><div class="signon-list">${signonHTML}</div></td>
  <td class="col-type"><span class="type-badge ${typeClass(type)}">${esc(type) || "—"}</span></td>
  <td class="col-claims"><div class="cell-text" title="${esc(c.claims)}">${esc(claimsShort) || `<span style="color:#9ca3af;">—</span>`}</div></td>
  <td class="col-client">${clientHTML}</td>
  <td class="col-linelvl">${ynBadge(c.linelvl)}</td>
  <td class="col-backup"><div class="cell-text">${backupHTML}</div></td>
  <td class="col-portal">${portalHTML}</td>
  <td class="col-sop">${sopHTML}</td>
  <td class="col-updated updated-date">${esc(c.updated)}</td>
</tr>`;
}

function renderTable() {
  const tbody = document.getElementById("tableBody");
  const noRes = document.getElementById("noResults");
  const badge = document.getElementById("countBadge");

  if (!filtered.length) {
    tbody.innerHTML = "";
    noRes.style.display = "block";
    badge.textContent = "0 results";
    return;
  }
  noRes.style.display = "none";
  tbody.innerHTML = filtered.map(idx => buildRow(CUSTOMERS[idx], idx)).join("");
  badge.textContent = `${filtered.length} of ${CUSTOMERS.length} customers`;
}

function filterTable() {
  const q      = document.getElementById("searchInput").value.toLowerCase().trim();
  const type   = document.getElementById("typeFilter").value.toLowerCase();
  const portal = document.getElementById("portalFilter").value.toLowerCase();
  const sop    = document.getElementById("sopFilter").value.toLowerCase();

  filtered = [];
  CUSTOMERS.forEach((c, i) => {
    const t = (c.type || "").toLowerCase();

    // Type filter
    if (type) {
      if (type === "direct"      && !(/direct/.test(t) && !/indirect/.test(t))) return;
      if (type === "wholesaler"  && !(t.includes("wholesale") || t.includes("distributor"))) return;
      if (type === "indirect"    && !t.includes("indirect")) return;
      if (type === "third"       && !t.includes("third")) return;
    }

    // Portal filter
    if (portal) {
      const p = portalFromBackup(c.backup);
      if (portal === "yes" && p !== "YES") return;
      if (portal === "no"  && p !== "NO")  return;
    }

    // SOP filter
    if (sop === "yes" && !c.sop) return;

    // Search
    if (q) {
      const hay = [c.name, c.signon, c.client, c.claims, c.backup].join(" ").toLowerCase();
      if (!hay.includes(q)) return;
    }

    filtered.push(i);
  });

  // Re-apply sort
  if (sortCol >= 0) applySortToFiltered();

  renderTable();
}

function sortTable(col) {
  if (sortCol === col) {
    sortAsc = !sortAsc;
  } else {
    sortCol = col;
    sortAsc = true;
  }
  document.querySelectorAll(".sort-arrow").forEach(el => {
    el.classList.remove("asc", "desc");
  });
  const arrow = document.querySelector(`.sort-arrow[data-col="${col}"]`);
  if (arrow) arrow.classList.add(sortAsc ? "asc" : "desc");
  applySortToFiltered();
  renderTable();
}

function getVal(c, col) {
  if (col === 0) return c.name.toLowerCase();
  if (col === 2) return (c.type || "").toLowerCase();
  if (col === 9) return c.updated || "";
  return "";
}

function applySortToFiltered() {
  filtered.sort((a, b) => {
    const va = getVal(CUSTOMERS[a], sortCol);
    const vb = getVal(CUSTOMERS[b], sortCol);
    return sortAsc ? va.localeCompare(vb) : vb.localeCompare(va);
  });
}

function clearFilters() {
  document.getElementById("searchInput").value = "";
  document.getElementById("typeFilter").value = "";
  document.getElementById("portalFilter").value = "";
  document.getElementById("sopFilter").value = "";
  filterTable();
}

// ── Drawer ──
function openDrawer(idx) {
  const c = CUSTOMERS[idx];
  const type = normalizeType(c.type);
  const sgns = signons(c.signon);
  const clients = clientList(c.client);
  const portal = portalFromBackup(c.backup);
  const portalLabel = portal === "YES" ? "✓ Yes" : portal === "NO" ? "✕ No" : "—";

  document.getElementById("drawerName").textContent = c.name;

  let html = "";

  // Signons
  html += `<div class="drawer-section">
    <div class="drawer-label">Customer Signon(s)</div>
    <div class="drawer-value">${sgns.map(s => `<span class="signon-badge" style="display:inline-block;margin:2px;">${esc(s)}</span>`).join(" ")}</div>
  </div>`;

  // Type
  html += `<div class="drawer-section">
    <div class="drawer-label">Customer Type</div>
    <div class="drawer-value"><span class="type-badge ${typeClass(type)}">${esc(type) || "—"}</span></div>
  </div>`;

  // Claims
  if (c.claims) {
    html += `<div class="drawer-section">
      <div class="drawer-label">Claims Processing Information</div>
      <div class="drawer-value">${esc(c.claims)}</div>
    </div>`;
  }

  // Client specific
  if (clients.length) {
    html += `<div class="drawer-section">
      <div class="drawer-label">Client Specific Info</div>
      <div class="drawer-value">${esc(clients.join(", "))}</div>
    </div>`;
  }

  // Line level
  html += `<div class="drawer-section">
    <div class="drawer-label">Line Level Detail Indexed?</div>
    <div class="drawer-value">${ynBadge(c.linelvl)}</div>
  </div>`;

  // Backup
  if (c.backup) {
    html += `<div class="drawer-section">
      <div class="drawer-label">Backup Retrieval Information</div>
      <div class="drawer-value">${esc(c.backup)}</div>
    </div>`;
  }

  // Portal
  html += `<div class="drawer-section">
    <div class="drawer-label">Customer Portal Available?</div>
    <div class="drawer-value">${portalLabel}</div>
  </div>`;

  // Formal SOP
  if (c.sop) {
    html += `<div class="drawer-section">
      <div class="drawer-label">Formal SOP Document</div>
      <div class="drawer-value"><a class="sop-link" href="sops/${esc(c.sop)}" download>📄 Download SOP</a></div>
    </div>`;
  }

  // Updated
  if (c.updated) {
    html += `<div class="drawer-section">
      <div class="drawer-label">Last Updated</div>
      <div class="drawer-value">${esc(c.updated)}</div>
    </div>`;
  }

  document.getElementById("drawerContent").innerHTML = html;
  document.getElementById("drawer").style.display = "block";
  document.getElementById("drawerOverlay").style.display = "block";
  document.body.style.overflow = "hidden";
}

function closeDrawer() {
  document.getElementById("drawer").style.display = "none";
  document.getElementById("drawerOverlay").style.display = "none";
  document.body.style.overflow = "";
}

// Keyboard: Escape closes drawer
document.addEventListener("keydown", e => { if (e.key === "Escape") closeDrawer(); });

// Init
document.addEventListener("DOMContentLoaded", () => {
  filterTable();
});
