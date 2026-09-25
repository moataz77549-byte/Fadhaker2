import type { Lease } from './types.js';import type { SupabaseAutomationStore } from './automation-store.js';import type { Logger } from './logger.js';
export class SchedulerLoop{
  private timer?:NodeJS.Timeout;private running=false;
  constructor(private store:SupabaseAutomationStore,private lease:()=>Lease|null,private pollSeconds:number,private lookaheadSeconds:number,private graceSeconds:number,private logger:Logger){}
  start():void{if(this.timer)return;this.timer=setInterval(()=>void this.tick(),this.pollSeconds*1000);this.timer.unref();void this.tick();}
  stop():void{if(this.timer)clearInterval(this.timer);this.timer=undefined;}
  async tick(now=new Date()):Promise<void>{if(this.running)return;const lease=this.lease();if(!lease)return;this.running=true;try{const materialized=await this.store.materialize(lease.stationId,new Date(now.getTime()-this.graceSeconds*1000),new Date(now.getTime()+this.lookaheadSeconds*1000));const occurrence=await this.store.claimOccurrence(lease,this.graceSeconds,now);this.logger.info('SCHEDULER_TICK',{materialized,occurrence_id:occurrence?.id??null});}catch(error){this.logger.error('SCHEDULER_FAILED',error);}finally{this.running=false;}}
}
