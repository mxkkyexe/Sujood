const {test} = require('node:test');
const assert = require('node:assert/strict');
const M = require('../Model.js');
const base=Date.parse('2026-10-31T00:00:00-02:30');
function day(start, label, fajr) {
    return {start,end:start+86400000,date:label,rows:[
      ['Fajr',fajr],['Sunrise',7],['Dhuhr',12],['Asr',15],['Maghrib',18],['Isha',20]
    ].map(([name,h])=>({name,at:start+h*3600000,date:label,time:String(Math.floor(h)).padStart(2,'0')+':'+String(Math.round((h%1)*60)).padStart(2,'0')}))};
}
const data={days:[day(base,'2026-10-31',5),day(base+86400000,'2026-11-01',5.1)]};
const isha=base+20*3600000;
test('30-minute progress has correct endpoints and midpoint',()=>{
    assert.equal(M.state(data,isha-1800000).progress,0);
    assert.equal(M.state(data,isha-900000).progress,.5);
    assert.ok(M.state(data,isha-1).progress>.999);
});
test('arrival is held for exactly one minute then rolls to actual next-day Fajr',()=>{
    assert.equal(M.state(data,isha).phase,'arrival');
    assert.equal(M.label(M.state(data,isha),isha),'Isha | Now');
    assert.equal(M.state(data,isha+59999).prayer.name,'Isha');
    const next=M.state(data,isha+60000);
    assert.equal(next.phase,'countdown');
    assert.equal(next.prayer.at,base+86400000+5.1*3600000);
    assert.equal(next.prayer.name,'Fajr');
});
test('sunrise never becomes next prayer or triggers arrival',()=>{
    assert.equal(M.state(data,base+6*3600000).prayer.name,'Dhuhr');
    assert.equal(M.state(data,base+7*3600000).phase,'countdown');
});
test('dated cache is never reinterpreted as today',()=>{
    assert.equal(M.state(data,base+3*86400000).phase,'unavailable');
    assert.equal(M.today(data,base-1),null);
});
test('subminute countdown never displays 0m',()=>{
    assert.equal(M.label(M.state(data,isha-1),isha-1),'Isha | 1m');
});
test('ISO timestamps retain timezone independently of system timezone',()=>{
    const t=Date.parse('2026-11-01T05:00:00-03:30');
    assert.equal(t,Date.parse('2026-11-01T08:30:00Z'));
});
test('sunrise is an optional bar event with the standard arrival interval',()=>{
    const between=base+6*3600000;
    assert.equal(M.state(data,between,false).prayer.name,'Dhuhr');
    assert.equal(M.state(data,between,true).prayer.name,'Sunrise');
    assert.equal(M.events(data,true).length,M.events(data,false).length+2);
    const sunrise=base+7*3600000;
    assert.equal(M.state(data,sunrise-900000,true).progress,.5);
    assert.equal(M.label(M.state(data,sunrise,true),sunrise),'Sunrise | Now');
    assert.equal(M.state(data,sunrise+59999,true).prayer.name,'Sunrise');
    assert.equal(M.state(data,sunrise+60000,true).prayer.name,'Dhuhr');
    assert.equal(M.state(data,sunrise,true).phase,'arrival');
    assert.equal(M.state(data,sunrise,false).phase,'countdown');
});
test('sunrise option retains Fajr after Isha and excludes expired calendar days',()=>{
    assert.equal(M.state(data,isha+60000,true).prayer.name,'Fajr');
    assert.equal(M.state(data,base+3*86400000,true).phase,'unavailable');
});
test('sunrise reuses the Dhuhr SVG with the same theme colours',()=>{
    const vm=require('node:vm'), fs=require('node:fs'), path=require('node:path');
    const icons=vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(__dirname,'../Icons.js'),'utf8'),icons);
    assert.equal(icons.source('Sunrise','#fff','#abc'),icons.source('Dhuhr','#fff','#abc'));
});
test('timetable clearly identifies the next prayer and arrival without highlighting other rows',()=>{
    const day=data.days[0], status=M.state(data,base+14*3600000);
    for (const row of day.rows) {
        const display=M.rowState(row,status,day);
        assert.equal(display.highlighted,row.name==='Asr');
        assert.equal(display.badge,row.name==='Asr' ? 'Next' : '');
    }
    const arrived=M.state(data,base+15*3600000);
    assert.equal(M.rowState(day.rows[3],arrived,day).badge,'Now');
});
test('after Isha the Fajr row shows tomorrow’s actual time and explicit date cue',()=>{
    const day=data.days[0],status=M.state(data,isha+60000);
    const result=M.rowState(day.rows[0],status,day);
    assert.equal(result.highlighted,true);
    assert.equal(result.badge,'Next · Tomorrow');
    assert.equal(result.time,data.days[1].rows[0].time);
    assert.notEqual(result.time,day.rows[0].time);
    const midnight=M.state(data,base+86400000);
    assert.equal(M.rowState(data.days[1].rows[0],midnight,data.days[1]).badge,'Next');
});
