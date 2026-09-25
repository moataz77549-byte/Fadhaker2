import { mkdtemp,mkdir,writeFile,rm } from 'node:fs/promises';
import { spawn,spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join,resolve } from 'node:path';

const root=resolve(import.meta.dirname,'../../..');
const composeFile=join(root,'infrastructure/docker-compose.radio.yml');
const port=Number(process.env.TARTEEL_TEST_ICECAST_PORT??8000);
const healthPort=Number(process.env.TARTEEL_TEST_HEALTH_PORT??8091);
const soakSeconds=Math.max(1800,Number(process.env.TARTEEL_E2E_SOAK_SECONDS??1800));
const sourcePassword=required('TARTEEL_ICECAST_SOURCE_PASSWORD');
const adminPassword=required('TARTEEL_ICECAST_ADMIN_PASSWORD');
const adminUser=process.env.TARTEEL_ICECAST_ADMIN_USER??'admin';
const streamUrl=`http://127.0.0.1:${port}/tarteel.mp3`;
const statusUrl=`http://127.0.0.1:${port}/status-json.xsl`;
const started=Date.now();const work=await mkdtemp(join(tmpdir(),'tarteel-real-icecast-'));
const logs=[];const engineEvents=[];const listeners=[];let engine;

function required(name){const value=process.env[name];if(!value)throw new Error(`${name} is required`);return value;}
function run(command,args,options={}){const result=spawnSync(command,args,{encoding:'utf8',timeout:120_000,...options});if(result.status!==0)throw new Error(`${command} failed: ${(result.stderr||result.stdout||'').slice(0,2000)}`);return result;}
function compose(...args){return run('docker',['compose','-f',composeFile,...args],{cwd:root,env:process.env});}
async function waitFor(check,timeoutMs,label){const deadline=Date.now()+timeoutMs;let last;while(Date.now()<deadline){try{const value=await check();if(value)return value;}catch(error){last=error;}await new Promise(resolvePromise=>setTimeout(resolvePromise,250));}throw new Error(`${label} timeout${last?`: ${last}`:''}`);}
async function stop(child,signal='SIGTERM'){if(!child||child.exitCode!==null)return;child.kill(signal);await Promise.race([new Promise(resolvePromise=>child.once('exit',resolvePromise)),new Promise(resolvePromise=>setTimeout(resolvePromise,3000))]);if(child.exitCode===null)child.kill('SIGKILL');}
function collectLines(child,name){for(const stream of [child.stdout,child.stderr]){if(!stream)continue;let pending='';stream.on('data',chunk=>{pending+=String(chunk);const lines=pending.split('\n');pending=lines.pop()??'';for(const line of lines){logs.push({at:Date.now(),name,line});if(name==='engine'){try{const event=JSON.parse(line);if(event?.event)engineEvents.push({...event,observedAt:Date.now()});}catch{}}}});}}
async function icecastStatus(){const response=await fetch(statusUrl,{signal:AbortSignal.timeout(1500)});if(!response.ok)throw new Error(`status HTTP ${response.status}`);return await response.json();}
function sourceFrom(status){const value=status?.icestats?.source;if(Array.isArray(value))return value.find(item=>String(item?.listenurl??'').endsWith('/tarteel.mp3'))??null;return value&&String(value.listenurl??'').endsWith('/tarteel.mp3')?value:null;}
async function state(){const response=await fetch(`http://127.0.0.1:${healthPort}/state`,{signal:AbortSignal.timeout(1000)});if(!response.ok)throw new Error(`state HTTP ${response.status}`);return await response.json();}
async function ready(){try{return (await fetch(`http://127.0.0.1:${healthPort}/ready`,{signal:AbortSignal.timeout(1000)})).ok;}catch{return false;}}
function startEngine(manifest,fallback){const child=spawn(process.execPath,[join(root,'services/radio-engine/dist/src/cli.js')],{cwd:root,detached:true,stdio:['ignore','pipe','pipe'],env:{...process.env,TARTEEL_STATION_ID:'00000000-0000-0000-0000-000000000001',TARTEEL_RADIO_ENGINE_INSTANCE_ID:`phase5b-${Date.now()}`,TARTEEL_RADIO_ENGINE_DATABASE_MODE:'disabled',TARTEEL_LIQUIDSOAP_PATH:process.env.TARTEEL_LIQUIDSOAP_PATH??'liquidsoap',TARTEEL_LIQUIDSOAP_ALLOW_ROOT:'false',TARTEEL_RADIO_ENABLE_FAULT_INJECTION:'false',TARTEEL_ICECAST_HOST:'127.0.0.1',TARTEEL_ICECAST_PORT:String(port),TARTEEL_ICECAST_MOUNT:'/tarteel.mp3',TARTEEL_ICECAST_SOURCE_USER:'source',TARTEEL_ICECAST_SOURCE_PASSWORD:sourcePassword,TARTEEL_ICECAST_ADMIN_USER:adminUser,TARTEEL_ICECAST_ADMIN_PASSWORD:adminPassword,TARTEEL_RADIO_PLAYLIST_PATH:manifest,TARTEEL_RADIO_FALLBACK_PATH:fallback,TARTEEL_RADIO_WORKSPACE:join(work,'engine'),TARTEEL_RADIO_HEALTH_PORT:String(healthPort),TARTEEL_RADIO_ENGINE_LEASE_SECONDS:'15',TARTEEL_RADIO_ENGINE_HEARTBEAT_SECONDS:'5'}});collectLines(child,'engine');return child;}
function startListener(name){const child=spawn('ffmpeg',['-hide_banner','-loglevel','warning','-fflags','nobuffer','-f','mp3','-i',streamUrl,'-map','0:a:0','-ac','1','-ar','8000','-f','s16le','pipe:1'],{stdio:['ignore','pipe','pipe']});const listener={name,child,connectedAt:Date.now(),frequencies:[],stderr:[],lastChunkAt:null,maxChunkGapMs:0,samples:[]};child.stdout.on('data',chunk=>{const now=Date.now();if(listener.lastChunkAt)listener.maxChunkGapMs=Math.max(listener.maxChunkGapMs,now-listener.lastChunkAt);listener.lastChunkAt=now;for(let i=0;i+1<chunk.length;i+=2)listener.samples.push(chunk.readInt16LE(i));while(listener.samples.length>=8000){const frame=listener.samples.splice(0,8000);let crossings=0;for(let i=1;i<frame.length;i++)if(frame[i-1]<0&&frame[i]>=0)crossings++;listener.frequencies.push({at:Date.now(),hz:crossings});}});child.stderr.on('data',chunk=>listener.stderr.push(String(chunk)));listeners.push(listener);return listener;}
const closest=(rows,target)=>rows.reduce((best,row)=>Math.abs(row.hz-target)<Math.abs(best.hz-target)?row:best,rows[0]);
const expectedHz=title=>title?.endsWith('A')?440:title?.endsWith('B')?660:title?.endsWith('C')?880:null;
const iso=value=>new Date(value).toISOString();
const sanitize=value=>String(value).replaceAll(sourcePassword,'[REDACTED]').replaceAll(adminPassword,'[REDACTED]').slice(0,2048);

let finalResult={status:'FAILED',error:null};
try{
  const fixtures=join(work,'fixtures');run('bash',[join(root,'infrastructure/scripts/generate-radio-fixtures.sh'),fixtures]);
  const manifest=join(work,'playlist.json');await writeFile(manifest,JSON.stringify({tracks:[{title:'Invalid Track',path:join(work,'missing.mp3')},{title:'Development Track A',path:join(fixtures,'track-a.m4a')},{title:'Development Track B',path:join(fixtures,'track-b.m4a')},{title:'Development Track C',path:join(fixtures,'track-c.m4a')}]}));
  engine=startEngine(manifest,join(fixtures,'fallback.m4a'));
  await waitFor(ready,30_000,'engine real Icecast readiness');const sourceReadyAt=Date.now();
  const initialStatus=await icecastStatus();const initialSource=sourceFrom(initialStatus);if(!initialSource)throw new Error('real Icecast mount missing');
  const headerResponse=await fetch(streamUrl,{signal:AbortSignal.timeout(3000)});const contentType=headerResponse.headers.get('content-type');await headerResponse.body?.cancel();if(contentType!=='audio/mpeg')throw new Error(`unexpected content type ${contentType}`);

  await new Promise(resolvePromise=>setTimeout(resolvePromise,6000));
  const listenerA=startListener('A');await waitFor(()=>listenerA.frequencies.length>=2,8000,'Listener A audio');
  await new Promise(resolvePromise=>setTimeout(resolvePromise,5000));const listenerB=startListener('B');const listenerBJoinDelayMs=listenerB.connectedAt-listenerA.connectedAt;await waitFor(()=>listenerB.frequencies.length>=2,8000,'Listener B audio');
  const transitionAB_A=await waitFor(()=>listenerA.frequencies.find(row=>row.hz>550),25_000,'A transition A-B');const transitionAB_B=await waitFor(()=>listenerB.frequencies.find(row=>row.hz>550),8000,'B transition A-B');
  await new Promise(resolvePromise=>setTimeout(resolvePromise,3000));const listenerC=startListener('C');await waitFor(()=>listenerC.frequencies.length>=2,8000,'Listener C audio');
  const transitionBC_B=await waitFor(()=>listenerB.frequencies.find(row=>row.hz>800),25_000,'B transition B-C');const transitionBC_C=await waitFor(()=>listenerC.frequencies.find(row=>row.hz>800),8000,'C transition B-C');
  const listenerStatus=sourceFrom(await icecastStatus());const observedListenerCount=Number(listenerStatus?.listeners??0);
  await Promise.all([stop(listenerA.child),stop(listenerB.child),stop(listenerC.child)]);

  const beforeNoListeners=(await state()).playoutAckCount;const noListenerStarted=Date.now();await new Promise(resolvePromise=>setTimeout(resolvePromise,25_000));const noListenerEnded=Date.now();const afterNoListeners=await state();if(afterNoListeners.playoutAckCount<=beforeNoListeners)throw new Error('playout did not advance with no listeners');
  const listenerD=startListener('D');await waitFor(()=>listenerD.frequencies.length>=2,8000,'Listener D after no-listener period');const expectedAfterNoListeners=expectedHz(afterNoListeners.current?.title);const dObserved=expectedAfterNoListeners?closest(listenerD.frequencies,expectedAfterNoListeners).hz:null;await stop(listenerD.child);

  const listenerE=startListener('E-before-restart');await waitFor(()=>listenerE.frequencies.length>=2,8000,'pre-restart listener audio');
  const icecastStoppedAt=Date.now();compose('stop','icecast');
  await waitFor(async()=>!(await ready()),20_000,'Icecast failure detection');const failureDetectedAt=Date.now();
  await waitFor(()=>listenerE.child.exitCode!==null,15_000,'existing listener TCP close');
  const icecastRestartedAt=Date.now();compose('up','-d','icecast');
  const icecastProcessAvailableAt=await waitFor(async()=>{try{return await icecastStatus()&&Date.now();}catch{return false;}},30_000,'Icecast process restart');
  await waitFor(ready,45_000,'Liquidsoap reconnect readiness');const sourceReconnectedAt=Date.now();
  const mountAvailableAt=await waitFor(async()=>sourceFrom(await icecastStatus())&&Date.now(),10_000,'mount restoration');
  const listenerF=startListener('F-after-restart');await waitFor(()=>listenerF.frequencies.length>=2,12_000,'listener audio restoration');const listenerAudioRestoredAt=Date.now();await stop(listenerF.child);

  const monitor=startListener('soak');const metadataTitles=new Set();let mountProbeFailures=0;let maxListeners=observedListenerCount;
  while(Date.now()-sourceReadyAt<soakSeconds*1000){
    try{const source=sourceFrom(await icecastStatus());if(!source)mountProbeFailures++;else{metadataTitles.add(String(source.title??''));maxListeners=Math.max(maxListeners,Number(source.listeners??0));}}
    catch{mountProbeFailures++;}
    if(!(await ready()))mountProbeFailures++;
    await new Promise(resolvePromise=>setTimeout(resolvePromise,10_000));
  }
  await waitFor(()=>monitor.frequencies.length>=5,5000,'soak listener decode');await stop(monitor.child);

  const trackStarts=engineEvents.filter(event=>event.event==='TRACK_START'&&event.ack_source==='liquidsoap');
  const trackEnds=engineEvents.filter(event=>event.event==='TRACK_END'&&event.ack_source==='liquidsoap');
  const sourceStarts=engineEvents.filter(event=>event.event==='SOURCE_START');
  const sourceConnections=engineEvents.filter(event=>event.event==='SOURCE_CONNECTED');
  const disconnected=engineEvents.find(event=>event.event==='SOURCE_DISCONNECTED'&&Date.parse(event.timestamp)>=icecastStoppedAt);
  const ackB=trackStarts.find(event=>event.title==='Development Track B'&&Date.parse(event.timestamp)<=transitionAB_A.at);
  const ackC=trackStarts.find(event=>event.title==='Development Track C'&&Date.parse(event.timestamp)<=transitionBC_B.at);
  const ackErrorsMs=[ackB?transitionAB_A.at-Date.parse(ackB.timestamp):null,ackC?transitionBC_B.at-Date.parse(ackC.timestamp):null].filter(Number.isFinite);
  const stableDecoderErrors=monitor.stderr.filter(line=>/error|invalid|malformed/i.test(line)).length;
  const finalStatus=sourceFrom(await icecastStatus());const audioInfo=String(finalStatus?.audio_info??'');
  const allLogs=logs.map(row=>row.line).join('\n');const secretLeak=[sourcePassword,adminPassword].some(secret=>allLogs.includes(secret));
  const dockerState=JSON.parse(compose('ps','--format','json').stdout.trim());
  finalResult={status:'PASS',test_environment:'GitHub Actions Ubuntu Linux + Docker',icecast_version:String(initialStatus?.icestats?.server_id??'unknown'),liquidsoap_version:run(process.env.TARTEEL_LIQUIDSOAP_PATH??'liquidsoap',['--version']).stdout.split('\n')[0],mount:'/tarteel.mp3',content_type:contentType,bitrate_kbps:Number(finalStatus?.bitrate??128),audio_info:audioInfo,listeners_used:6,icecast_listener_count_observed:observedListenerCount,peak_listener_count:maxListeners,listener_b_join_delay_ms:listenerBJoinDelayMs,listener_a_first_hz:listenerA.frequencies[0]?.hz,listener_b_first_hz:listenerB.frequencies[0]?.hz,listener_c_first_hz:listenerC.frequencies[0]?.hz,transition_ab_difference_ms:Math.abs(transitionAB_A.at-transitionAB_B.at),transition_bc_difference_ms:Math.abs(transitionBC_B.at-transitionBC_C.at),no_listener_seconds:Math.round((noListenerEnded-noListenerStarted)/100)/10,no_listener_ack_advance:afterNoListeners.playoutAckCount-beforeNoListeners,listener_d_observed_hz:dObserved,icecast_stopped_at:iso(icecastStoppedAt),failure_detected_at:iso(failureDetectedAt),icecast_restarted_at:iso(icecastRestartedAt),icecast_process_available_at:iso(icecastProcessAvailableAt),source_reconnected_at:iso(sourceReconnectedAt),mount_available_at:iso(mountAvailableAt),listener_audio_restored_at:iso(listenerAudioRestoredAt),detection_time_ms:failureDetectedAt-icecastStoppedAt,icecast_process_restart_ms:icecastProcessAvailableAt-icecastRestartedAt,source_reconnect_ms:sourceReconnectedAt-icecastRestartedAt,mount_restore_ms:mountAvailableAt-icecastRestartedAt,listener_audio_restore_ms:listenerAudioRestoredAt-icecastRestartedAt,liquidsoap_survived_icecast_restart:sourceStarts.length===1,source_connection_count:sourceConnections.length,playout_ack_track_starts:trackStarts.length,playout_ack_track_ends:trackEnds.length,now_playing_audio_error_ms:ackErrorsMs,now_playing_max_error_ms:ackErrorsMs.length?Math.max(...ackErrorsMs):null,soak_duration_seconds:Math.round((Date.now()-sourceReadyAt)/100)/10,track_transitions_observed:trackEnds.length,mount_probe_failures_after_recovery:mountProbeFailures,metadata_titles_observed:[...metadataTitles].filter(Boolean),max_stable_audio_chunk_gap_ms:monitor.maxChunkGapMs,stable_decoder_errors:stableDecoderErrors,stream_frames_analyzed:monitor.frequencies.length,existing_listener_disconnected_on_restart:true,source_disconnect_event_observed:Boolean(disconnected),secret_leak:secretLeak,docker_health:dockerState.Health,docker_state:dockerState.State};
  const sameDelayedTrack=Math.abs((listenerA.frequencies[0]?.hz??0)-(listenerB.frequencies[0]?.hz??9999))<50;
  if(contentType!=='audio/mpeg'||observedListenerCount<2||!sameDelayedTrack||finalResult.transition_ab_difference_ms>2000||finalResult.transition_bc_difference_ms>2000||!finalResult.liquidsoap_survived_icecast_restart||secretLeak||finalResult.soak_duration_seconds<1800||trackEnds.length<2||mountProbeFailures>0||stableDecoderErrors>0||dockerState.Health!=='healthy'||dockerState.State!=='running')finalResult.status='FAILED';
}catch(error){finalResult={...finalResult,error:error instanceof Error?error.message:String(error),diagnostics:logs.slice(-80).map(row=>({at:iso(row.at),name:row.name,line:sanitize(row.line)}))};throw error;
}finally{
  for(const listener of listeners)await stop(listener.child);if(engine?.pid)try{process.kill(-engine.pid,'SIGTERM');}catch{}
  await mkdir(join(root,'artifacts'),{recursive:true});await writeFile(join(root,'artifacts/phase5b-result.json'),`${JSON.stringify(finalResult,null,2)}\n`);
  process.stdout.write(`${JSON.stringify(finalResult,null,2)}\n`);await rm(work,{recursive:true,force:true});
}
if(finalResult.status!=='PASS')process.exitCode=1;
