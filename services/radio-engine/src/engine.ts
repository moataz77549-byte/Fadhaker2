import { mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import type { Server } from 'node:http';
import type { Config } from './config.js';
import type { EngineMode, EngineSnapshot, Lease, LeaseStore, Track } from './types.js';
import { Logger } from './logger.js';
import { loadAndValidatePlaylist, writeSourcePlaylist } from './playlist.js';
import { LiquidsoapSource } from './source.js';
import { startHealthServer } from './health.js';

const allowed:Record<EngineMode,EngineMode[]>= {
  STARTING:['AUTO','SCHEDULED','MANUAL','RECOVERING','ERROR','STOPPED'],
  AUTO:['SCHEDULED','MANUAL','LIVE','RECOVERING','ERROR','STOPPED'],
  SCHEDULED:['AUTO','MANUAL','LIVE','RECOVERING','ERROR','STOPPED'],
  MANUAL:['AUTO','SCHEDULED','LIVE','RECOVERING','ERROR','STOPPED'],
  LIVE:['AUTO','SCHEDULED','MANUAL','RECOVERING','ERROR','STOPPED'],
  RECOVERING:['AUTO','SCHEDULED','MANUAL','LIVE','ERROR','STOPPED'],ERROR:['RECOVERING','STOPPED'],STOPPED:['STARTING']
};

export class RadioEngine {
  private lease:Lease|null=null;private source:LiquidsoapSource|null=null;private server:Server|null=null;
  private stopping=false;private heartbeat?:NodeJS.Timeout;private tracks:Track[]=[];private trackIndex=0;
  private restartCount=0;private workspace='';
  readonly snapshot:EngineSnapshot={mode:'STOPPED',sourceConnected:false,liquidsoapAlive:false,icecastReachable:false,mountAvailable:false,broadcasting:false,streamMount:'',current:null,next:null,currentStartedAt:null,expectedEndAt:null,sourceStartedAt:null,lastError:null,lastRecoveryAt:null,reconnectCount:0,trackFailures:0,playoutAckCount:0};
  constructor(private readonly config:Config,private readonly store:LeaseStore,private readonly logger=new Logger()) {this.snapshot.streamMount=config.mount;}
  private transition(next:EngineMode):void{if(!allowed[this.snapshot.mode].includes(next)&&this.snapshot.mode!==next)throw new Error(`invalid transition ${this.snapshot.mode} -> ${next}`);this.snapshot.mode=next;}
  async start():Promise<void>{
    this.transition('STARTING');this.logger.info('ENGINE_START',{station_id:this.config.stationId,instance_id:this.config.ownerId});
    this.lease=await this.store.acquire(this.config.stationId,this.config.ownerId,this.config.leaseSeconds);
    if(!this.lease){this.transition('ERROR');throw new Error('station ownership unavailable');}
    this.logger.info('ENGINE_OWNERSHIP_ACQUIRED',{station_id:this.config.stationId,fencing_token:this.lease.fencingToken});
    this.workspace=join(this.config.workspaceRoot,this.config.ownerId.replace(/[^a-zA-Z0-9._-]/g,'_'));await mkdir(this.workspace,{recursive:true,mode:0o700});
    const result=await loadAndValidatePlaylist(this.config.playlistPath,this.config.fallbackPath,this.config.ffprobePath);
    this.snapshot.trackFailures=result.failed.length;for(const failure of result.failed)this.logger.warn('TRACK_FAILED',{reason:failure});
    if(result.fallbackUsed)this.logger.warn('FALLBACK_SELECTED',{reason:'no valid development tracks'});
    this.tracks=result.tracks;const playlistPath=join(this.workspace,'playlist.m3u');const scriptPath=join(this.workspace,'radio.liq');await rm(playlistPath,{force:true});await rm(scriptPath,{force:true});await writeSourcePlaylist(playlistPath,this.tracks);
    this.source=new LiquidsoapSource(this.config,playlistPath,scriptPath);await this.source.prepare();this.server=await startHealthServer(this.config.healthPort,()=>this.snapshot,()=>this.snapshot.mode==='AUTO'&&this.snapshot.broadcasting);
    this.heartbeat=setInterval(()=>void this.heartbeatTick(),this.config.heartbeatSeconds*1000);this.heartbeat.unref();
    this.startSource();
  }
  private startSource():void{
    if(!this.source||this.stopping)return;this.snapshot.sourceConnected=false;this.snapshot.sourceStartedAt=new Date().toISOString();
    this.logger.info('SOURCE_START',{station_id:this.config.stationId,mount:this.config.mount});
    this.source.start((code,signal)=>void this.onSourceExit(code,signal),line=>this.logger.info('SOURCE_LOG',{message:line}),(event,payload)=>this.onSourceEvent(event,payload));
    this.snapshot.liquidsoapAlive=true;
    setTimeout(()=>{if(!this.stopping&&!this.snapshot.sourceConnected&&this.source?.pid)this.logger.warn('SOURCE_CONNECTION_PENDING',{timeout_seconds:this.config.sourceTimeoutSeconds});},this.config.sourceTimeoutSeconds*1000).unref();
  }
  private onSourceEvent(event:string,payload?:string):void{
    // Liquidsoap can emit its final disconnect line after stop() has begun.
    // Shutdown owns the final STOPPED checkpoint and lease release, so late
    // source callbacks must not attempt a fenced write with a released lease.
    if(this.stopping)return;
    if(event==='SOURCE_CONNECTED'){
      this.restartCount=0;this.snapshot.sourceConnected=true;this.snapshot.lastError=null;
      if(this.snapshot.mode==='STARTING'||this.snapshot.mode==='RECOVERING')this.transition('AUTO');
      this.logger.info('SOURCE_CONNECTED',{station_id:this.config.stationId,mount:this.config.mount,pid:this.source?.pid});
      void this.refreshDistributionHealth().then(()=>this.checkpoint());
    }else if(event==='TRACK_START'){
      this.handleTrackStart(payload);
    }else if(event==='SOURCE_DISCONNECTED'||event==='SOURCE_ERROR'){
      this.snapshot.sourceConnected=false;this.snapshot.mountAvailable=false;this.snapshot.broadcasting=false;this.snapshot.lastError=event;this.snapshot.lastRecoveryAt=new Date().toISOString();
      if(this.snapshot.mode==='AUTO')this.transition('RECOVERING');this.logger.warn(event,{mount:this.config.mount});void this.checkpoint();
    }
  }
  private handleTrackStart(payload?:string):void{
    let acknowledgedIndex:number|undefined;try{const metadata=JSON.parse(payload??'{}') as Record<string,unknown>;const parsed=Number(metadata.tarteel_index);if(Number.isInteger(parsed)&&parsed>=0)acknowledgedIndex=parsed;}catch{}
    const index=acknowledgedIndex??this.trackIndex%this.tracks.length;
    const previous=this.snapshot.current;if(previous)this.logger.info('TRACK_END',{media_id:previous.mediaId,title:previous.title,ended_at:new Date().toISOString(),ack_source:'liquidsoap'});
    const track=this.tracks[index];if(!track)return;this.trackIndex=(index+1)%this.tracks.length;const next=this.tracks[this.trackIndex]??null;const now=Date.now();
    this.snapshot.current=track;this.snapshot.next=next;this.snapshot.currentStartedAt=new Date(now).toISOString();this.snapshot.expectedEndAt=new Date(now+track.durationSeconds*1000).toISOString();this.snapshot.playoutAckCount++;
    this.logger.info('TRACK_START',{media_id:track.mediaId,title:track.title,duration_seconds:track.durationSeconds,started_at:this.snapshot.currentStartedAt,ack_source:'liquidsoap'});
    void this.updateIcecastMetadata(track);void this.checkpoint();
  }
  private async refreshDistributionHealth():Promise<void>{
    try{
      const response=await fetch(`http://${this.config.icecastHost}:${this.config.icecastPort}/status-json.xsl`,{signal:AbortSignal.timeout(2000)});
      this.snapshot.icecastReachable=response.ok;if(!response.ok)throw new Error(`icecast HTTP ${response.status}`);
      const body=await response.json() as {icestats?:{source?:unknown}};const sources=Array.isArray(body.icestats?.source)?body.icestats?.source:[body.icestats?.source];
      this.snapshot.mountAvailable=sources.some(value=>typeof value==='object'&&value!==null&&String((value as Record<string,unknown>).listenurl??'').endsWith(this.config.mount));
    }catch{this.snapshot.icecastReachable=false;this.snapshot.mountAvailable=false;}
    this.snapshot.broadcasting=this.snapshot.sourceConnected&&this.snapshot.mountAvailable;
  }
  private async updateIcecastMetadata(track:Track):Promise<void>{if(!this.config.adminUser||!this.config.adminPassword)return;try{const url=new URL(`http://${this.config.icecastHost}:${this.config.icecastPort}/admin/metadata`);url.searchParams.set('mount',this.config.mount);url.searchParams.set('mode','updinfo');url.searchParams.set('song',track.title);const response=await fetch(url,{headers:{authorization:`Basic ${Buffer.from(`${this.config.adminUser}:${this.config.adminPassword}`).toString('base64')}`},signal:AbortSignal.timeout(3000)});if(!response.ok)throw new Error(`metadata HTTP ${response.status}`);this.logger.info('METADATA_UPDATED',{title:track.title});}catch(error){this.logger.error('METADATA_UPDATE_FAILED',error);}}
  private async onSourceExit(code:number|null,signal:NodeJS.Signals|null):Promise<void>{if(this.stopping)return;this.snapshot.sourceConnected=false;this.snapshot.liquidsoapAlive=false;this.snapshot.mountAvailable=false;this.snapshot.broadcasting=false;this.snapshot.lastError=`source exited code=${code} signal=${signal}`;this.logger.warn('SOURCE_DISCONNECTED',{code,signal});
    if(this.snapshot.mode!=='RECOVERING')this.transition('RECOVERING');this.snapshot.lastRecoveryAt=new Date().toISOString();this.logger.warn('RECOVERY_START',{attempt:this.restartCount+1});await this.checkpoint().catch(()=>{});
    if(++this.restartCount>this.config.restartMax){this.transition('ERROR');this.logger.error('RECOVERY_FAILED',new Error('restart budget exhausted'));await this.checkpoint().catch(()=>{});return;}
    const delay=Math.min(30_000,1000*2**(this.restartCount-1));setTimeout(()=>{this.snapshot.reconnectCount++;this.startSource();},delay).unref();}
  private async heartbeatTick():Promise<void>{if(!this.lease||this.stopping)return;try{this.lease=await this.store.renew(this.lease,this.config.leaseSeconds);await this.refreshDistributionHealth();await this.checkpoint();}catch(error){this.logger.error('ENGINE_OWNERSHIP_LOST',error);this.snapshot.sourceConnected=false;this.snapshot.broadcasting=false;this.snapshot.lastError='station lease lost';this.source?.stop('SIGTERM');if(this.snapshot.mode!=='ERROR')this.transition('ERROR');}}
  private async checkpoint():Promise<void>{if(this.lease)await this.store.checkpoint(this.lease,this.snapshot,this.config.version);}
  crashSourceForTest():void{if(!this.config.faultInjectionEnabled)throw new Error('fault injection disabled');this.source?.stop('SIGKILL');}
  async applyAutomationTracks(tracks:Track[],interrupt=false):Promise<void>{if(!this.source||tracks.length===0)throw new Error('radio source is not ready');const activeSource=this.snapshot.current?.queueEntryId?'automation':'main';this.tracks=[...tracks];this.trackIndex=0;const first=tracks[0]!;await this.source.pushTrack(first.path,first.mediaId,first.queueEntryId??null,interrupt,activeSource);this.logger.info('QUEUE_CHANGED',{track_count:tracks.length,interrupt,control:'request.queue',active_source:activeSource});}
  async setAutomationMode(mode:Extract<EngineMode,'AUTO'|'SCHEDULED'|'MANUAL'>):Promise<void>{this.transition(mode);await this.checkpoint();}
  async stop():Promise<void>{if(this.stopping)return;this.stopping=true;if(this.heartbeat)clearInterval(this.heartbeat);this.source?.stop('SIGTERM');this.snapshot.sourceConnected=false;this.snapshot.liquidsoapAlive=false;this.snapshot.mountAvailable=false;this.snapshot.broadcasting=false;if(this.snapshot.mode!=='STOPPED')this.transition('STOPPED');await this.checkpoint().catch(()=>{});if(this.lease)await this.store.release(this.lease).catch(()=>{});await new Promise<void>(resolve=>this.server?this.server.close(()=>resolve()):resolve());await rm(this.workspace,{recursive:true,force:true});this.logger.info('ENGINE_STOP',{station_id:this.config.stationId});}
}
