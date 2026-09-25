import type { InterruptPolicy,QueueItem } from './queue-manager.js';
import type { Priority } from './priority.js';

export type CommandType='PLAY_NOW'|'PLAY_NEXT'|'SKIP'|'STOP_AFTER_CURRENT'|'RESUME_AUTO'|'START_LIVE'|'STOP_LIVE';
export interface RadioCommand {id:string;stationId:string;type:CommandType;priority:Priority;payload:unknown;createdAt:string;}
export interface ContentResolver {resolveMedia(id:string):Promise<Omit<QueueItem,'id'|'source'|'priority'|'interruptPolicy'|'intendedAt'|'createdAt'|'sequence'>>;resolvePlaylist(id:string):Promise<Array<Omit<QueueItem,'id'|'source'|'priority'|'interruptPolicy'|'intendedAt'|'createdAt'|'sequence'>>>;}
export type CommandEffect={kind:'ENQUEUE';items:QueueItem[]}|{kind:'SKIP'}|{kind:'STOP_AFTER_CURRENT'}|{kind:'RESUME_AUTO'};
function object(value:unknown):Record<string,unknown>{if(typeof value!=='object'||value===null||Array.isArray(value))throw new Error('invalid command payload');return value as Record<string,unknown>;}
export async function commandEffect(command:RadioCommand,resolver:ContentResolver):Promise<CommandEffect>{
  if(command.type==='START_LIVE'||command.type==='STOP_LIVE')throw new Error('live input is deferred');
  if(command.type==='SKIP')return{kind:'SKIP'};if(command.type==='STOP_AFTER_CURRENT')return{kind:'STOP_AFTER_CURRENT'};if(command.type==='RESUME_AUTO')return{kind:'RESUME_AUTO'};
  const payload=object(command.payload),mediaId=typeof payload.media_id==='string'?payload.media_id:null,playlistId=typeof payload.playlist_id==='string'?payload.playlist_id:null;
  if((mediaId===null)===(playlistId===null))throw new Error('exactly one of media_id or playlist_id is required');
  const policy:InterruptPolicy=command.type==='PLAY_NEXT'?'PLAY_NEXT':payload.interrupt===true?'INTERRUPT':'FINISH_CURRENT';
  const resolved=mediaId?[await resolver.resolveMedia(mediaId)]:await resolver.resolvePlaylist(playlistId!);if(!resolved.length)throw new Error('content is empty');
  return{kind:'ENQUEUE',items:resolved.map((item,index)=>({...item,id:`${command.id}:${index}`,source:command.priority==='EMERGENCY'?'EMERGENCY':'MANUAL',priority:command.priority,interruptPolicy:policy,intendedAt:command.createdAt,createdAt:command.createdAt,commandId:command.id,sequence:index}))};
}
