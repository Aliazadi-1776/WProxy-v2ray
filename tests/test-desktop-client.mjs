import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require=createRequire(new URL('../desktop/package.json',import.meta.url));
const ts=require('typescript');
function moduleFrom(file){const text=ts.transpileModule(readFileSync(new URL(file,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;return import(`data:text/javascript;base64,${Buffer.from(text).toString('base64')}`);}
const {createDesktopClient}=await moduleFrom('../desktop/src/v4-client.ts');
const ID='0123456789abcdef';
const snapshot={platform:'linux',nodes:[{id:ID,name:'Fixture',source:'fedcba9876543210'}],status:{active:false,node_id:null},routing:{mode:'all',apps:[],domains:[]},preferences:{remember_authorization:true,auto_update:false}};
const json=value=>({code:0,stdout:JSON.stringify(value),stderr:''});
function fixture(respond=()=>json({})){const calls=[];const invoke=async(command,args)=>{calls.push({command,args});return respond(command,args);};return {calls,client:createDesktopClient(invoke,true)};}

test('browser preview never invokes a native mutation',async()=>{
 const calls=[];const client=createDesktopClient(async(...args)=>{calls.push(args);},false);
 await assert.rejects(()=>client.connect(ID,snapshot),/Design preview/);
 await assert.rejects(()=>client.disconnect(),/Design preview/);
 assert.deepEqual(calls,[]);
});
test('connect uses the existing tunnel bridge and scoped-approval preference',async()=>{
 const {client,calls}=fixture();await client.connect(ID,snapshot);
 assert.deepEqual(calls,[{command:'tunnel',args:{action:'up',nodeId:ID,remember:true}}]);
});
test('an active matching route is a no-op, and empty Only selected cannot connect',async()=>{
 const {client,calls}=fixture();await client.connect(ID,{...snapshot,status:{active:true,node_id:ID}});
 await assert.rejects(()=>client.connect(ID,{...snapshot,routing:{mode:'only',apps:[],domains:[]}}),/no apps or sites/);
 assert.deepEqual(calls,[]);
});
test('Quick connect rejects unverified, stale and malformed measurements before activation',async()=>{
 for(const best of [{id:ID,verified:false,latency_ms:2},{id:'stale',verified:true,latency_ms:2},{id:ID,verified:true,latency_ms:-1}]){
  const {client,calls}=fixture(()=>json(best));await assert.rejects(()=>client.quickConnect(snapshot));
  assert.equal(calls.length,1);assert.equal(calls[0].command,'run_ctl');
 }
});
test('Quick connect activates only the saved HTTPS-verified selection',async()=>{
 const {client,calls}=fixture((command)=>command==='run_ctl'?json({id:ID,verified:true,latency_ms:0}):json({}));
 const best=await client.quickConnect(snapshot);assert.equal(best.latency_ms,0);
 assert.deepEqual(calls.at(-1),{command:'tunnel',args:{action:'up',nodeId:ID,remember:true}});
});
test('bridge nonzero exits stay failures',async()=>{
 const {client}=fixture(()=>({code:7,stdout:'',stderr:'Fixture activation failed'}));
 await assert.rejects(()=>client.connect(ID,snapshot),/Fixture activation failed/);
});
test('routing reuses the established Linux sync/reconnect path and leaves Windows activation to its next connection',async()=>{
 const disconnected=fixture();await disconnected.client.route(['mode','bypass'],snapshot);
 assert.equal(disconnected.calls.at(-1).command,'sync_linux');
 const connected=fixture();await connected.client.route(['app','add','/fixture/app'],{...snapshot,status:{active:true,node_id:ID}});
 assert.deepEqual(connected.calls.at(-1),{command:'tunnel',args:{action:'up',nodeId:ID,remember:true}});
 const windows=fixture();await windows.client.route(['mode','only'],{...snapshot,platform:'windows'});
 assert.equal(windows.calls.length,1);
});
test('deletion rechecks the actual current status and protects an active node or subscription',async()=>{
 const {client,calls}=fixture(()=>json({active:true,node_id:ID}));
 await assert.rejects(()=>client.remove('node',ID,snapshot),/Disconnect/);
 await assert.rejects(()=>client.remove('sub','fedcba9876543210',snapshot),/Disconnect/);
 assert(calls.every(call=>call.command==='tunnel_status'));
});
test('subscription add updates only the returned ID before the existing Linux profile sync',async()=>{
 const id='fedcba9876543210';const {client,calls}=fixture((command,args)=>args?.args?.[1]==='add'?{code:0,stderr:'',stdout:id+'\n'}:json({}));
 await client.addSubscription('https://example.invalid/sub','Fixture',snapshot.platform);
 assert.deepEqual(calls.map(call=>[call.command,call.args?.args]),[
  ['run_ctl',['sub','add','https://example.invalid/sub','--name','Fixture']],
  ['run_ctl',['sub','update',id]],['sync_linux',undefined],
 ]);
});
