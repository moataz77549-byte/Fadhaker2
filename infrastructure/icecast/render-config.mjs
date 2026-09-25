import { readFile,writeFile } from 'node:fs/promises';
const [template,target]=process.argv.slice(2);if(!template||!target)throw new Error('usage: render-config.mjs TEMPLATE TARGET');
const names=['TARTEEL_ICECAST_SOURCE_PASSWORD','TARTEEL_ICECAST_RELAY_PASSWORD','TARTEEL_ICECAST_ADMIN_USER','TARTEEL_ICECAST_ADMIN_PASSWORD','TARTEEL_ICECAST_HOSTNAME','TARTEEL_ICECAST_PORT','TARTEEL_ICECAST_BASEDIR','TARTEEL_ICECAST_LOGDIR'];
const escape=(value)=>value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
let config=await readFile(template,'utf8');for(const name of names){const value=process.env[name];if(!value)throw new Error(`${name} is required`);config=config.replaceAll(`\${${name}}`,escape(value));}
if(/\$\{TARTEEL_/.test(config))throw new Error('unresolved configuration placeholder');await writeFile(target,config,{mode:0o600,flag:'wx'});
