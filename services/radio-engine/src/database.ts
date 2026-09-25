import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { EngineSnapshot, Lease, LeaseStore } from './types.js';

export class SupabaseLeaseStore implements LeaseStore {
  private readonly client:SupabaseClient;
  constructor(url:string,key:string) { this.client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}}); }
  async acquire(stationId:string,ownerId:string,ttlSeconds:number):Promise<Lease|null> {
    const {data,error}=await this.client.schema('radio').rpc('acquire_station_lease',{p_station_id:stationId,p_owner_id:ownerId,p_ttl_seconds:ttlSeconds});
    if(error) throw error; const row=(data as Record<string,unknown>[]|null)?.[0]; if(!row)return null;
    return {stationId:String(row.station_id),ownerId:String(row.owner_id),fencingToken:Number(row.fencing_token),expiresAt:String(row.expires_at)};
  }
  async renew(lease:Lease,ttlSeconds:number):Promise<Lease> {
    const {data,error}=await this.client.schema('radio').rpc('renew_station_lease',{p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_ttl_seconds:ttlSeconds});
    if(error)throw error; return {...lease,expiresAt:String(data)};
  }
  async checkpoint(lease:Lease,s:EngineSnapshot,version:string):Promise<number> {
    const {data,error}=await this.client.schema('radio').rpc('checkpoint_engine_state',{
      p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken,p_mode:s.mode,
      p_source_connected:s.sourceConnected,p_stream_mount:s.streamMount,p_current_media_id:s.current?.mediaId??null,
      p_next_media_id:s.next?.mediaId??null,p_current_title:s.current?.title??null,p_next_title:s.next?.title??null,
      p_started_at:s.currentStartedAt,p_expected_end_at:s.expectedEndAt,p_source_started_at:s.sourceStartedAt,
      p_processing_profile:'LIVE_MP3_128K_V1',p_last_error:s.lastError,p_last_recovery_at:s.lastRecoveryAt,
      p_state_data:{reconnect_count:s.reconnectCount,track_failures:s.trackFailures,liquidsoap_alive:s.liquidsoapAlive,
        icecast_reachable:s.icecastReachable,mount_available:s.mountAvailable,broadcasting:s.broadcasting,
        playout_ack_count:s.playoutAckCount},p_version:version
    }); if(error)throw error; return Number(data);
  }
  async release(lease:Lease):Promise<void> { const {error}=await this.client.schema('radio').rpc('release_station_lease',{p_station_id:lease.stationId,p_owner_id:lease.ownerId,p_fencing_token:lease.fencingToken});if(error)throw error; }
}

export class DevelopmentLeaseStore implements LeaseStore {
  private current:Lease|null=null; private token=0;
  async acquire(stationId:string,ownerId:string,ttlSeconds:number):Promise<Lease|null>{
    if(this.current&&new Date(this.current.expiresAt)>new Date()&&this.current.ownerId!==ownerId)return null;
    if(!this.current||this.current.ownerId!==ownerId)this.token++;
    return this.current={stationId,ownerId,fencingToken:this.token,expiresAt:new Date(Date.now()+ttlSeconds*1000).toISOString()};
  }
  async renew(lease:Lease,ttlSeconds:number):Promise<Lease>{if(!this.current||this.current.fencingToken!==lease.fencingToken)throw new Error('station lease lost');return this.current={...lease,expiresAt:new Date(Date.now()+ttlSeconds*1000).toISOString()};}
  async checkpoint():Promise<number>{if(!this.current)throw new Error('station lease lost');return 1;}
  async release(lease:Lease):Promise<void>{if(this.current?.fencingToken===lease.fencingToken)this.current=null;}
}
