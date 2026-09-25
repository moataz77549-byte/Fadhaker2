import { spawn, type ChildProcess } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
import { createConnection } from 'node:net';
import type { Config } from './config.js';

function liq(value:string):string{return JSON.stringify(value);}
export function buildLiquidsoapScript(config:Config,playlistPath:string):string{
  return `${config.liquidsoapAllowRoot?'settings.init.allow_root := true\n':''}settings.log.stdout := true\nsettings.log.file := false\n`+
    `settings.server.telnet := true\nsettings.server.telnet.bind_addr := "127.0.0.1"\nsettings.server.telnet.port := ${config.liquidsoapControlPort}\n`+
    `main = playlist(mode="normal", reload=60, ${liq(playlistPath)})\n`+
    `automation = request.queue(id="automation")\n`+
    `def track_started(m) = print("TARTEEL_EVENT TRACK_START #{metadata.json.stringify(m)}") end\n`+
    `emergency = single(${liq(config.fallbackPath)})\n`+
    `radio = fallback(track_sensitive=false, [automation, main, emergency])\n`+
    `radio.on_track(track_started)\n`+
    `def source_connected() = print("TARTEEL_EVENT SOURCE_CONNECTED") end\n`+
    `def source_disconnected() = print("TARTEEL_EVENT SOURCE_DISCONNECTED") end\n`+
    `def source_error(error) = print("TARTEEL_EVENT SOURCE_ERROR: #{error}"); 2.0 end\n`+
    `output.icecast(%mp3(bitrate=128, samplerate=44100, stereo=true), id="tarteel", host=${liq(config.icecastHost)}, port=${config.icecastPort}, user=${liq(config.sourceUser)}, password=${liq(config.sourcePassword)}, mount=${liq(config.mount)}, name="ترتيل", genre="Quran and Islamic audio", description="Tarteel development radio", public=false, format="audio/mpeg", connection_timeout=5.0, timeout=10.0, on_connect=source_connected, on_disconnect=source_disconnected, on_error=source_error, radio)\n`;
}

export class LiquidsoapSource {
  child:ChildProcess|null=null;
  constructor(private readonly config:Config,private readonly playlistPath:string,private readonly scriptPath:string){}
  async prepare():Promise<void>{await writeFile(this.scriptPath,buildLiquidsoapScript(this.config,this.playlistPath),{encoding:'utf8',flag:'wx',mode:0o600});}
  start(onExit:(code:number|null,signal:NodeJS.Signals|null)=>void,onLog:(line:string)=>void,onEvent:(event:string,payload?:string)=>void):void{
    if(this.child)throw new Error('source already running');
    const env:NodeJS.ProcessEnv={PATH:process.env.PATH??''};if(this.config.liquidsoapLibraryPath)env.LD_LIBRARY_PATH=this.config.liquidsoapLibraryPath;
    const child=spawn(this.config.liquidsoapPath,['--strict',this.scriptPath],{stdio:['ignore','pipe','pipe'],env});
    this.child=child;let pending='';
    const consume=(chunk:unknown)=>{pending+=String(chunk);const lines=pending.split('\n');pending=lines.pop()??'';for(const raw of lines){const line=redact(raw);const marker=line.match(/TARTEEL_EVENT (SOURCE_[A-Z_]+)/);if(marker?.[1])onEvent(marker[1]);const track=line.match(/TARTEEL_EVENT TRACK_START\s+(.+)$/);if(track?.[1])onEvent('TRACK_START',track[1]);onLog(line);}};
    child.stdout?.on('data',consume);child.stderr?.on('data',consume);
    child.once('exit',(code,signal)=>{this.child=null;onExit(code,signal);});
    child.once('error',error=>onLog(redact(error.message)));
  }
  stop(signal:NodeJS.Signals='SIGTERM'):void{this.child?.kill(signal);}
  async reloadPlaylist(interrupt=false):Promise<void>{await liquidsoapCommand(this.config.liquidsoapControlPort,'main.reload');if(interrupt)await liquidsoapCommand(this.config.liquidsoapControlPort,'main.skip');}
  async pushTrack(path:string,mediaId:string|null,queueEntryId:string|null,interrupt=false,activeSource:'main'|'automation'='main'):Promise<void>{
    if(!path.startsWith('/')||/[\0\r\n]/.test(path))throw new Error('invalid automation path');
    const clean=(value:string|null)=>String(value??'none').replace(/[^a-zA-Z0-9._-]/g,'_').slice(0,200);
    await liquidsoapCommand(this.config.liquidsoapControlPort,'automation.push',`annotate:media_id="${clean(mediaId)}",queue_entry_id="${clean(queueEntryId)}":${path}`);
    if(interrupt)await liquidsoapCommand(this.config.liquidsoapControlPort,`${activeSource}.skip`);
  }
  get pid():number|null{return this.child?.pid??null;}
}
export async function liquidsoapCommand(port:number,command:string,argument?:string,timeoutMs=3000):Promise<string>{
  if(!/^[a-z0-9_.-]+$/i.test(command))throw new Error('invalid Liquidsoap command');
  if(argument!==undefined&&(/[\0\r\n]/.test(argument)||argument.length>4096))throw new Error('invalid Liquidsoap argument');
  return await new Promise((resolve,reject)=>{const socket=createConnection({host:'127.0.0.1',port});let output='';const timer=setTimeout(()=>{socket.destroy();reject(new Error('Liquidsoap control timeout'));},timeoutMs);socket.setEncoding('utf8');socket.once('connect',()=>socket.write(`${command}${argument===undefined?'':` ${argument}`}\n`));socket.on('data',chunk=>{output+=chunk;if(output.includes('END')){clearTimeout(timer);socket.end();const safe=output.slice(0,4096);if(/(^|\n)(ERROR|Unknown|No such)/i.test(safe))reject(new Error(`Liquidsoap rejected ${command}`));else resolve(safe);}});socket.once('error',error=>{clearTimeout(timer);reject(error);});socket.once('close',()=>{if(!output.includes('END')){clearTimeout(timer);reject(new Error('Liquidsoap control closed'));}});});
}
export function redact(value:string):string{
  return value
    .replace(/\b(icecast|https?):\/\/[^@\s]+@/gi,'$1://[REDACTED]@')
    .replace(/\b(password|authorization|secret|token)\s*[=:]\s*[^\s,;]+/gi,'$1=[REDACTED]')
    .slice(0,2048);
}
