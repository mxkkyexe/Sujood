// Pure scheduling logic. Every time is an epoch from the location's timezone.
var ORDER = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
var PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
function parse(raw, fallback) {
    try { return JSON.parse(raw) } catch (_) { return fallback }
}
function today(data, now) {
    var days = data && data.days || []
    for (var i = 0; i < days.length; i++)
        if (days[i].start <= now && now < days[i].end) return days[i]
    return null
}
function events(data, showSunrise) {
    var rows = [], days = data && data.days || []
    for (var i = 0; i < days.length; i++)
        for (var j = 0; j < days[i].rows.length; j++)
            if (PRAYERS.indexOf(days[i].rows[j].name) !== -1
                || (showSunrise === true && days[i].rows[j].name === "Sunrise")) rows.push(days[i].rows[j])
    return rows.sort(function(a,b) { return a.at-b.at })
}
function state(data, now, showSunrise) {
    var day = today(data, now)
    if (!day) return { phase: "unavailable", prayer: null, progress: 0 }
    var list = events(data, showSunrise)
    for (var i = list.length-1; i >= 0; i--) {
        var age = now-list[i].at
        if (age >= 0 && age < 60000)
            return { phase: "arrival", prayer: list[i], progress: 1 }
    }
    for (var k = 0; k < list.length; k++) {
        if (list[k].at > now) return { phase: "countdown", prayer: list[k],
            progress: Math.max(0, Math.min(1, 1-(list[k].at-now)/1800000)) }
    }
    return { phase: "unavailable", prayer: null, progress: 0 }
}
function label(state, now) {
    if (!state.prayer) return "Sujood | —"
    if (state.phase === "arrival") return state.prayer.name + " | Now"
    var mins = Math.max(1, Math.ceil((state.prayer.at-now)/60000))
    return state.prayer.name + " | " + (mins >= 60 ? Math.floor(mins/60)+"h " : "") + (mins%60) + "m"
}
// After Isha, show the actual upcoming Fajr in its row with an explicit date cue.
function rowState(row, status, day) {
    var prayer = status && status.prayer
    var tomorrow = !!(prayer && day && prayer.date > day.date)
    var highlighted = !!(prayer && row.name === prayer.name && (row.at === prayer.at || tomorrow))
    return {
        highlighted: highlighted,
        time: highlighted ? prayer.time : row.time,
        badge: highlighted ? (status.phase === "arrival" ? "Now" : (tomorrow ? "Next · Tomorrow" : "Next")) : ""
    }
}
function timeLabel(hhmm, use24) {
    if (use24) return hhmm
    var parts = hhmm.split(":"), h = Number(parts[0])
    return (h%12 || 12)+":"+parts[1]+(h >= 12 ? " PM" : " AM")
}
if (typeof module !== "undefined") module.exports = {today:today, events:events, state:state, label:label, timeLabel:timeLabel, rowState:rowState}
