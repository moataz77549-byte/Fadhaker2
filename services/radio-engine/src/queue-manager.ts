import { PRIORITY_RANK,type Priority } from './priority.js';

export type QueueSource='LIVE'|'EMERGENCY'|'MANUAL'|'SCHEDULED'|'AUTO'|'FALLBACK';
export type InterruptPolicy='FINISH_CURRENT'|'INTERRUPT'|'PLAY_NEXT';
export interface QueueItem {id:string;mediaId:string;title:string;path:string;durationSeconds:number;source:QueueSource;priority:Priority;interruptPolicy:InterruptPolicy;intendedAt:string;createdAt:string;commandId?:string;occurrenceId?:string;playlistId?:string;sequence:number;}
export interface PlaybackDecision {item:QueueItem;interruptCurrent:boolean;reason:string;}

const sourceRank:Readonly<Record<QueueSource,number>>={LIVE:60,EMERGENCY:50,MANUAL:40,SCHEDULED:30,AUTO:20,FALLBACK:10};
export class QueueManager {
  private pending:QueueItem[]=[];private current:QueueItem|null=null;private stopRequested=false;private autoCursor=0;
  constructor(private autoItems:QueueItem[],private readonly fallback:QueueItem){if(fallback.source!=='FALLBACK')throw new Error('fallback source required');}
  setCurrent(item:QueueItem|null):void{this.current=item;}
  enqueue(item:QueueItem):void{if(this.pending.some(existing=>existing.id===item.id))return;this.pending.push(item);}
  requestStopAfterCurrent():void{this.stopRequested=true;}
  resumeAuto():void{this.stopRequested=false;this.pending=this.pending.filter(item=>item.source!=='MANUAL');}
  skipCurrent():QueueItem|null{const previous=this.current;this.current=null;return previous;}
  next(boundary:boolean):PlaybackDecision|null{
    if(this.stopRequested&&boundary){this.current=null;return null;}
    const eligible=this.pending.filter(item=>boundary||item.interruptPolicy==='INTERRUPT');
    eligible.sort((a,b)=>PRIORITY_RANK[b.priority]-PRIORITY_RANK[a.priority]||sourceRank[b.source]-sourceRank[a.source]||Date.parse(a.intendedAt)-Date.parse(b.intendedAt)||Date.parse(a.createdAt)-Date.parse(b.createdAt)||a.sequence-b.sequence||a.id.localeCompare(b.id));
    const chosen=eligible[0];
    if(chosen){this.pending=this.pending.filter(item=>item.id!==chosen.id);const interrupt=Boolean(this.current&&!boundary&&chosen.interruptPolicy==='INTERRUPT');this.current=chosen;return{item:chosen,interruptCurrent:interrupt,reason:`${chosen.source}:${chosen.interruptPolicy}`};}
    if(!boundary&&this.current)return null;
    const auto=this.autoItems.length?this.autoItems[this.autoCursor++%this.autoItems.length]!:this.fallback;this.current=auto;return{item:auto,interruptCurrent:false,reason:auto.source==='FALLBACK'?'FALLBACK_ACTIVATED':'DEFAULT_PLAYLIST'};
  }
  snapshot():Readonly<{current:QueueItem|null;pending:QueueItem[];stopRequested:boolean;autoCursor:number}>{return{current:this.current,pending:[...this.pending],stopRequested:this.stopRequested,autoCursor:this.autoCursor};}
}
