import { createClient,type SupabaseClient } from '@supabase/supabase-js';
import { materializeOccurrences,type ScheduleDefinition } from './scheduler.js';
import type { Lease } from './types.js';
import type { Priority } from './priority.js';
import type { InterruptPolicy,QueueSource } from './queue-manager.js';

export interface ClaimedOccurrence {id:string;schedule_id:string;station_id:string;content_type:'MEDIA'|'PLAYLIST';media_id:string|null;playlist_id:string|null;priority:Priority;interrupt_policy:InterruptPolicy;scheduled_for:string;}
export interface ClaimedCommand {id:string;station_id:string;command_type:string;payload:unknown;priority:Priority;created_at:string;}
export interface EnqueueInput {mediaId:string;source:QueueSource;priority:Priority;interruptPolicy:InterruptPolicy;idempotencyKey:string;intendedAt:string;sequence?:number;commandId?:string;occurrenceId?:string;playlistId?:string;playlistItemId?:string;metadata?:Record<string,unknown>;}

export class SupabaseAutomationStore {
  private client:SupabaseClient;
  constructor(url:string,key:string){this.client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});}
  async materialize(stationId:string,windowStart:Date,windowEnd:Date):Promise<number>{
    const query=this.client.schema('app').from('schedules')
      .select('id,version,schedule_type,enabled,timezone,start_date,end_date,start_time,days_of_week,priority,created_at,content_type,media_id,playlist_id,interrupt_policy')
      .eq('station_id',stationId).eq('enabled',true).is('deleted_at',null);
    const {data,error}=await query;if(error)throw error;
    const rows:Record<string,unknown>[]=[];
    for(const schedule of data??[]){
      if(schedule.content_type==='PROGRAM')continue;
      const definition:ScheduleDefinition={
        id:String(schedule.id),version:Number(schedule.version),type:schedule.schedule_type as ScheduleDefinition['type'],enabled:Boolean(schedule.enabled),
        timezone:String(schedule.timezone),startDate:String(schedule.start_date),endDate:schedule.end_date?String(schedule.end_date):null,
        startTime:String(schedule.start_time),daysOfWeek:schedule.days_of_week as number[]|null,priority:schedule.priority as Priority,createdAt:String(schedule.created_at)
      };
      for(const occurrence of materializeOccurrences(definition,windowStart,windowEnd)){
        rows.push({schedule_id:schedule.id,station_id:stationId,occurrence_key:`v${definition.version}:${occurrence.localKey}:fold${occurrence.fold}`,
          scheduled_for:occurrence.intendedAt,local_date:occurrence.localKey.slice(0,10),local_time:definition.startTime,timezone:definition.timezone,
          fold:occurrence.fold,priority:schedule.priority,interrupt_policy:schedule.interrupt_policy,schedule_version:definition.version,
          content_type:schedule.content_type,media_id:schedule.media_id,playlist_id:schedule.playlist_id,
          expires_at:new Date(Date.parse(occurrence.intendedAt)+3_600_000).toISOString(),result:{dst_shifted:occurrence.shiftedForDst}});
      }
    }
    if(rows.length===0)return 0;
    const {error:upsertError}=await this.client.schema('radio').from('schedule_occurrences').upsert(rows,{onConflict:'schedule_id,occurrence_key',ignoreDuplicates:true});
    if(upsertError)throw upsertError;
    return rows.length;
  }
  async claimOccurrence(lease:Lease,graceSeconds:number,now=new Date()):Promise<ClaimedOccurrence|null>{const {data,error}=await this.client.schema('radio').rpc('claim_due_occurrence',{p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_grace_seconds:graceSeconds,p_now:now.toISOString()});if(error)throw error;return(data as ClaimedOccurrence[]|null)?.[0]??null;}
  async claimCommand(lease:Lease):Promise<ClaimedCommand|null>{const {data,error}=await this.client.schema('radio').rpc('claim_radio_command',{p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken});if(error)throw error;return(data as ClaimedCommand[]|null)?.[0]??null;}
  async enqueue(lease:Lease,input:EnqueueInput):Promise<string>{const {data,error}=await this.client.schema('radio').rpc('enqueue_media',{p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_media_id:input.mediaId,p_source:input.source,p_priority:input.priority,p_interrupt_policy:input.interruptPolicy,p_idempotency_key:input.idempotencyKey,p_intended_at:input.intendedAt,p_sequence:input.sequence??0,p_command_id:input.commandId??null,p_occurrence_id:input.occurrenceId??null,p_playlist_id:input.playlistId??null,p_playlist_item_id:input.playlistItemId??null,p_metadata:input.metadata??{}});if(error)throw error;return String(data);}
  async completeCommand(lease:Lease,id:string,succeeded:boolean,result:Record<string,unknown>={},errorCode?:string,errorMessage?:string):Promise<boolean>{const {data,error}=await this.client.schema('radio').rpc('complete_radio_command',{p_command_id:id,p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_succeeded:succeeded,p_result:result,p_error_code:errorCode??null,p_error_message:errorMessage??null});if(error)throw error;return Boolean(data);}
  async recordPlayoutStart(lease:Lease,queueEntryId:string,playoutId:string,startedAt:string):Promise<number>{const {data,error}=await this.client.schema('radio').rpc('record_playout_start',{p_queue_entry_id:queueEntryId,p_playout_id:playoutId,p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_started_at:startedAt});if(error)throw error;return Number(data);}
  async recordPlayoutEnd(lease:Lease,playoutId:string,endedAt:string,completedNaturally:boolean,reason?:string):Promise<boolean>{const {data,error}=await this.client.schema('radio').rpc('record_playout_end',{p_playout_id:playoutId,p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_ended_at:endedAt,p_completed_naturally:completedNaturally,p_reason:reason??null});if(error)throw error;return Boolean(data);}
}
