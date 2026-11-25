const field = (id) => document.getElementById(id);
const status = field("status");
async function api(path, method = "GET", data, confirmation) {
  const headers = {Authorization: "Bearer " + field("token").value};
  if (data !== undefined) headers["Content-Type"] = "application/json";
  if (confirmation) headers["X-Confirm"] = confirmation;
  const response = await fetch(path, {method, headers, body: JSON.stringify(data)});
  const result = await response.json();
  if (!response.ok) throw new Error(typeof result.detail === "string" ? result.detail : "请求失败");
  return result;
}
function bind(id, action) {
  field(id).onclick = async () => {
    try { await action(); } catch (error) { status.textContent = error.message; }
  };
}
async function load() {
  const state = await api("/admin/state?q=" + encodeURIComponent(field("query").value));
  const models = Object.entries(state.models).map(([name, model]) => name + " / " + model);
  status.textContent = "免费请求 " + state.attempts + "/" + state.limit + "（UTC 日）｜当前 " +
    state.preferred + "｜" + (models.join("、") || "无可用模型");
  const selector = field("provider");
  selector.replaceChildren(new Option("自动", "auto"));
  for (const name of Object.keys(state.models)) selector.add(new Option(name, name));
  selector.value = Object.hasOwn(state.models, state.preferred) ? state.preferred : "auto";
  const list = field("memory");
  list.replaceChildren();
  for (const item of state.memory) {
    const row = document.createElement("li");
    const edit = document.createElement("input");
    edit.value = item.fact;
    edit.maxLength = 1000;
    edit.setAttribute("aria-label", "记忆 " + item.id);
    row.append(edit);
    const actions = {
      "更新": () => api("/admin/memory/" + item.id, "PUT", {fact: edit.value}),
      "删除": () => confirm("删除这条记忆？") &&
        api("/admin/memory/" + item.id, "DELETE", undefined, "delete-memory-" + item.id)
    };
    for (const [label, action] of Object.entries(actions)) {
      const button = document.createElement("button");
      button.textContent = label;
      button.onclick = async () => {
        try { if (await action()) await load(); }
        catch (error) { status.textContent = error.message; }
      };
      row.append(button);
    }
    list.append(row);
  }
}
bind("load", load);
bind("select", async () => {
  await api("/admin/provider", "PUT", {provider: field("provider").value});
  await load();
});
bind("search", load);
bind("add", async () => {
  await api("/admin/memory", "POST", {fact: field("fact").value});
  field("fact").value = "";
  await load();
});
bind("backup", async () => {
  const backup = await api("/admin/backup");
  const url = URL.createObjectURL(new Blob([JSON.stringify(backup, null, 2)], {type: "application/json"}));
  const a = document.createElement("a");
  a.href = url;
  a.download = "homepod-gpt-backup.json";
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
});
bind("restore", async () => {
  const file = field("file").files[0];
  if (!file || file.size > 6_000_000) throw new Error("请选择备份文件，最大 6 MB");
  if (!confirm("将此备份恢复到空数据库？")) return;
  await api("/admin/restore", "POST", JSON.parse(await file.text()), "restore");
  await load();
});
bind("clear", async () => {
  if (!confirm("永久清除全部对话？")) return;
  await api("/admin/history", "DELETE", undefined, "delete-history");
  await load();
});
