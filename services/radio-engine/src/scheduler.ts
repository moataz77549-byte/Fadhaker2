import type { Priority } from './priority.js';

export type ScheduleType='ONE_TIME'|'DAILY'|'WEEKLY';
export interface ScheduleDefinition {
  id:string; version:number; type:ScheduleType; enabled:boolean; timezone:string;
  startDate:string; endDate?:string|null; startTime:string; daysOfWeek?:number[]|null;
  priority:Priority; createdAt:string;
}
export interface Occurrence {scheduleId:string;scheduleVersion:number;intendedAt:string;localKey:string;fold:number;shiftedForDst:boolean;}
type Parts={year:number;month:number;day:number;hour:number;minute:number;second:number;weekday:number};

const weekdayMap:Record<string,number>={Sun:0,Mon:1,Tue:2,Wed:3,Thu:4,Fri:5,Sat:6};
function partsAt(instant:number,timeZone:string):Parts {
  const values:Record<string,string>={};
  for(const p of new Intl.DateTimeFormat('en-CA',{timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23',weekday:'short'}).formatToParts(instant))if(p.type!=='literal')values[p.type]=p.value;
  return {year:Number(values.year),month:Number(values.month),day:Number(values.day),hour:Number(values.hour),minute:Number(values.minute),second:Number(values.second),weekday:weekdayMap[values.weekday??'']??-1};
}
function same(a:Parts,b:Omit<Parts,'weekday'>):boolean{return a.year===b.year&&a.month===b.month&&a.day===b.day&&a.hour===b.hour&&a.minute===b.minute&&a.second===b.second;}
function candidatesForLocal(local:Omit<Parts,'weekday'>,timeZone:string):number[]{
  const naive=Date.UTC(local.year,local.month-1,local.day,local.hour,local.minute,local.second);
  const offsets=new Set<number>();
  for(const delta of [-129600000,-86400000,0,86400000,129600000]){
    const probe=naive+delta,p=partsAt(probe,timeZone);
    offsets.add(Date.UTC(p.year,p.month-1,p.day,p.hour,p.minute,p.second)-probe);
  }
  return [...offsets].map(offset=>naive-offset).filter(value=>same(partsAt(value,timeZone),local)).sort((a,b)=>a-b);
}
function parseDate(value:string):[number,number,number]{const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(value);if(!m)throw new Error('invalid schedule date');return [Number(m[1]),Number(m[2]),Number(m[3])];}
function parseTime(value:string):[number,number,number]{const m=/^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value);if(!m)throw new Error('invalid schedule time');const result:[number,number,number]=[Number(m[1]),Number(m[2]),Number(m[3]??0)];if(result[0]>23||result[1]>59||result[2]>59)throw new Error('invalid schedule time');return result;}
function isoDate(y:number,m:number,d:number):string{return `${y.toString().padStart(4,'0')}-${m.toString().padStart(2,'0')}-${d.toString().padStart(2,'0')}`;}

export function assertIanaTimezone(timezone:string):void{try{new Intl.DateTimeFormat('en',{timeZone:timezone}).format();}catch{throw new Error(`invalid IANA timezone: ${timezone}`);}}
export function resolveLocalTime(date:string,time:string,timeZone:string):Array<{instant:number;fold:number;shifted:boolean}>{
  assertIanaTimezone(timeZone);const [year,month,day]=parseDate(date);const [hour,minute,second]=parseTime(time);
  let local={year,month,day,hour,minute,second};let values=candidatesForLocal(local,timeZone);let shift=0;
  while(values.length===0&&shift<180){shift++;const shifted=new Date(Date.UTC(year,month-1,day,hour,minute+shift,second));local={year:shifted.getUTCFullYear(),month:shifted.getUTCMonth()+1,day:shifted.getUTCDate(),hour:shifted.getUTCHours(),minute:shifted.getUTCMinutes(),second:shifted.getUTCSeconds()};values=candidatesForLocal(local,timeZone);}
  if(values.length===0)throw new Error('local time cannot be resolved');
  return values.map((instant,fold)=>({instant,fold,shifted:shift>0}));
}
export function materializeOccurrences(schedule:ScheduleDefinition,windowStart:Date,windowEnd:Date):Occurrence[]{
  if(!schedule.enabled||windowEnd<=windowStart)return[];assertIanaTimezone(schedule.timezone);
  const [sy,sm,sd]=parseDate(schedule.startDate);const startDay=Date.UTC(sy,sm-1,sd);const endDay=schedule.endDate?(()=>{const [y,m,d]=parseDate(schedule.endDate);return Date.UTC(y,m-1,d);})():Date.UTC(windowEnd.getUTCFullYear(),windowEnd.getUTCMonth(),windowEnd.getUTCDate())+172800000;
  const output:Occurrence[]=[];
  for(let day=startDay;day<=endDay;day+=86400000){
    const dateObj=new Date(day);const date=isoDate(dateObj.getUTCFullYear(),dateObj.getUTCMonth()+1,dateObj.getUTCDate());
    if(schedule.type==='ONE_TIME'&&date!==schedule.startDate)continue;
    if(schedule.type==='WEEKLY'&&!(schedule.daysOfWeek??[]).includes(dateObj.getUTCDay()))continue;
    // A repeated wall-clock time (DST fall-back) is executed once: the earlier fold.
    for(const resolved of resolveLocalTime(date,schedule.startTime,schedule.timezone).slice(0,1)){
      if(resolved.instant>=windowStart.getTime()&&resolved.instant<windowEnd.getTime())output.push({scheduleId:schedule.id,scheduleVersion:schedule.version,intendedAt:new Date(resolved.instant).toISOString(),localKey:`${date}T${schedule.startTime}[${schedule.timezone}]`,fold:resolved.fold,shiftedForDst:resolved.shifted});
    }
  }
  return output.sort((a,b)=>Date.parse(a.intendedAt)-Date.parse(b.intendedAt)||a.fold-b.fold);
}

export type DueState='DUE'|'MISSED'|'FUTURE';
export function classifyOccurrence(intendedAt:string,now:Date,graceSeconds:number):DueState{
  if(!Number.isInteger(graceSeconds)||graceSeconds<0)throw new Error('invalid grace');const age=now.getTime()-Date.parse(intendedAt);if(age<0)return'FUTURE';return age<=graceSeconds*1000?'DUE':'MISSED';
}
