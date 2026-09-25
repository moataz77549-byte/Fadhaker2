import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';

export interface Config {
  stationId:string; ownerId:string; databaseMode:'supabase'|'disabled'; supabaseUrl?:string; supabaseSecretKey?:string;
  ffmpegPath:string; ffprobePath:string; liquidsoapPath:string; liquidsoapLibraryPath?:string; liquidsoapAllowRoot:boolean; icecastHost:string; icecastPort:number; mount:string;
  sourceUser:string; sourcePassword:string; adminUser?:string; adminPassword?:string;
  playlistPath:string; fallbackPath:string; workspaceRoot:string; healthPort:number;
  leaseSeconds:number; heartbeatSeconds:number; sourceTimeoutSeconds:number; restartMax:number; version:string;
  schedulerPollSeconds:number; commandPollSeconds:number; missedGraceSeconds:number; queueLookaheadSeconds:number;
  liquidsoapControlPort:number;
  faultInjectionEnabled:boolean;
}

function required(name:string):string { const value=process.env[name]; if(!value) throw new Error(`${name} is required`); return value; }
function integer(name:string,fallback:number,min:number,max:number):number {
  const value=Number(process.env[name]??fallback); if(!Number.isInteger(value)||value<min||value>max) throw new Error(`${name} is invalid`); return value;
}
export function loadConfig():Config {
  const databaseMode=(process.env.TARTEEL_RADIO_ENGINE_DATABASE_MODE??'supabase') as Config['databaseMode'];
  if(!['supabase','disabled'].includes(databaseMode)) throw new Error('invalid database mode');
  const mount=process.env.TARTEEL_ICECAST_MOUNT??'/tarteel.mp3';
  if(!/^\/[a-z0-9][a-z0-9._-]*$/.test(mount)) throw new Error('invalid mount');
  const leaseSeconds=integer('TARTEEL_RADIO_ENGINE_LEASE_SECONDS',15,10,120);
  const heartbeatSeconds=integer('TARTEEL_RADIO_ENGINE_HEARTBEAT_SECONDS',5,2,30);
  if(heartbeatSeconds*2>=leaseSeconds) throw new Error('heartbeat must be less than half the lease');
  return {
    stationId:required('TARTEEL_STATION_ID'), ownerId:process.env.TARTEEL_RADIO_ENGINE_INSTANCE_ID??`radio-${randomUUID()}`,
    databaseMode, supabaseUrl:databaseMode==='supabase'?required('TARTEEL_SUPABASE_URL'):undefined,
    supabaseSecretKey:databaseMode==='supabase'?required('TARTEEL_SUPABASE_SECRET_KEY'):undefined,
    ffmpegPath:process.env.TARTEEL_FFMPEG_PATH??'ffmpeg',ffprobePath:process.env.TARTEEL_FFPROBE_PATH??'ffprobe',
    liquidsoapPath:process.env.TARTEEL_LIQUIDSOAP_PATH??'liquidsoap',liquidsoapLibraryPath:process.env.TARTEEL_LIQUIDSOAP_LIBRARY_PATH,
    liquidsoapAllowRoot:process.env.TARTEEL_LIQUIDSOAP_ALLOW_ROOT==='true',
    icecastHost:process.env.TARTEEL_ICECAST_HOST??'127.0.0.1',icecastPort:integer('TARTEEL_ICECAST_PORT',8000,1,65535),mount,
    sourceUser:process.env.TARTEEL_ICECAST_SOURCE_USER??'source',sourcePassword:required('TARTEEL_ICECAST_SOURCE_PASSWORD'),
    adminUser:process.env.TARTEEL_ICECAST_ADMIN_USER,adminPassword:process.env.TARTEEL_ICECAST_ADMIN_PASSWORD,
    playlistPath:resolve(required('TARTEEL_RADIO_PLAYLIST_PATH')),fallbackPath:resolve(required('TARTEEL_RADIO_FALLBACK_PATH')),
    workspaceRoot:resolve(process.env.TARTEEL_RADIO_WORKSPACE??'/tmp/tarteel/radio-engine'),healthPort:integer('TARTEEL_RADIO_HEALTH_PORT',8091,1,65535),
    leaseSeconds,heartbeatSeconds,sourceTimeoutSeconds:integer('TARTEEL_RADIO_SOURCE_TIMEOUT_SECONDS',20,5,120),
    schedulerPollSeconds:integer('TARTEEL_SCHEDULER_POLL_SECONDS',5,1,60),commandPollSeconds:integer('TARTEEL_COMMAND_POLL_SECONDS',2,1,30),
    missedGraceSeconds:integer('TARTEEL_SCHEDULE_MISSED_GRACE_SECONDS',120,0,3600),queueLookaheadSeconds:integer('TARTEEL_QUEUE_LOOKAHEAD_SECONDS',120,10,3600),
    liquidsoapControlPort:integer('TARTEEL_LIQUIDSOAP_CONTROL_PORT',1234,1024,65535),
    restartMax:integer('TARTEEL_RADIO_RESTART_MAX',5,1,20),version:process.env.TARTEEL_RADIO_ENGINE_VERSION??'0.1.0',
    faultInjectionEnabled:process.env.TARTEEL_RADIO_ENABLE_FAULT_INJECTION==='true'
  };
}
