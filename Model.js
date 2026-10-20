function usernames(value) {
  var raw = String(value || "").split(",")
  var result = []
  var seen = {}
  for (var i = 0; i < raw.length && result.length < 5; i++) {
    var name = raw[i].trim().replace(/^@/, "")
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,38}$/.test(name)) continue
    var key = name.toLowerCase()
    if (seen[key]) continue
    seen[key] = true
    result.push(name)
  }
  return result
}

function parseCommits(raw) {
  var payload = JSON.parse(raw)
  if (!payload || !Array.isArray(payload.data)) throw new Error("Invalid response")
  var result = []
  for (var i = 0; i < payload.data.length && result.length < 5; i++) {
    var item = payload.data[i]
    if (!item || !item.author || !item.created_at || !item.html_url) continue
    if (!/^https:\/\/dev-null\.sh\//.test(item.html_url)) continue
    result.push({
      id: String(item.id || ""),
      hash: String(item.short_hash || ""),
      body: String(item.body || ""),
      username: String(item.author.username || ""),
      createdAt: String(item.created_at),
      timestamp: Date.parse(item.created_at) || 0,
      stars: Number(item.stars_count) || 0,
      replies: Number(item.replies_count) || 0,
      url: String(item.html_url)
    })
  }
  return result
}

function merged(current, incoming) {
  var byId = {}
  var all = current.concat(incoming)
  var unique = []
  for (var i = 0; i < all.length; i++) {
    if (!all[i].id || byId[all[i].id]) continue
    byId[all[i].id] = true
    unique.push(all[i])
  }
  unique.sort(function(a, b) { return b.timestamp - a.timestamp })
  return unique.slice(0, 12)
}

function age(iso, now) {
  var elapsed = Math.max(0, Math.floor((now - Date.parse(iso)) / 1000))
  if (!isFinite(elapsed)) return ""
  if (elapsed < 60) return "now"
  if (elapsed < 3600) return Math.floor(elapsed / 60) + "m"
  if (elapsed < 86400) return Math.floor(elapsed / 3600) + "h"
  return Math.floor(elapsed / 86400) + "d"
}
