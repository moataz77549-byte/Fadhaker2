import { createServer, type Server } from 'node:http';
import type { EngineSnapshot } from './types.js';

export function startHealthServer(port:number,getSnapshot:()=>EngineSnapshot,ready:()=>boolean):Promise<Server>{
  const server=createServer((request,response)=>{
    const isReady=request.url==='/ready';const isHealth=request.url==='/health';const isState=request.url==='/state';
    if(!isReady&&!isHealth&&!isState){response.writeHead(404).end();return;}
    const snapshot=getSnapshot();const ok=isHealth||isState?true:ready();
    response.writeHead(ok?200:503,{'content-type':'application/json','cache-control':'no-store'});
    response.end(JSON.stringify(isState?snapshot:{
      status:ok?'ok':'not_ready',mode:snapshot.mode,engine_alive:true,
      liquidsoap_alive:snapshot.liquidsoapAlive,icecast_reachable:snapshot.icecastReachable,
      source_connected:snapshot.sourceConnected,mount_available:snapshot.mountAvailable,
      broadcasting:snapshot.broadcasting
    }));
  });
  return new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',()=>resolve(server));});
}
