(function(){
 if(window.KitchenHouseInsert)return;
 let payload={cabinets:[],walls:[]},armed=null,proposal=null,pending=false,waiting=false,ticket=0,frame=0,last=null;
 const note=document.createElement('div');note.id='kp-insert-note';note.style.cssText='position:absolute;left:20px;bottom:18px;padding:7px 11px;background:white;border:1px solid #dce3da;border-radius:6px;color:#315f4f;pointer-events:none;display:none;z-index:6';document.getElementById('canvasWrap').append(note);
 const size=document.createElement('label');size.style.cssText='display:none;padding:10px;background:#edf4ea';size.innerHTML='Width before placement (in)<input id="kp-insert-width" type="number" min="0.5" max="60" step="0.125" style="width:100%">';document.getElementById('kp-cab-library').before(size);
 const width=size.querySelector('input');width.addEventListener('input',()=>{if(!armed||armed.product_id||!width.checkValidity())return;const value=Number(width.value);if(!Number.isFinite(value)||value<=0)return;armed.width=value;armed.row={...armed.row,cabinet:{...armed.row.cabinet,width:value}};proposal=null;refresh();});
 const hoodTarget=document.createElement('label');hoodTarget.style.cssText='display:none;padding:10px;background:#edf4ea';hoodTarget.innerHTML='Center hood over range<select style="width:100%"><option value="">Place freely</option></select>';size.after(hoodTarget);
 const rangeSelect=hoodTarget.querySelector('select');rangeSelect.onchange=()=>{proposal=null;refresh();};
 const say=text=>{note.textContent=text||'';note.style.display=text?'block':'none';};
 const restore=()=>{KitchenSymbols.load(payload);draw();};
 function cancel(){if(pending)return false;if(frame)cancelAnimationFrame(frame);frame=0;ticket++;waiting=false;armed=null;size.style.display='none';hoodTarget.style.display='none';proposal=null;last=null;cv.style.cursor='';say('');restore();return true;}
 function refresh(){if(frame)cancelAnimationFrame(frame);frame=0;if(!armed||pending)return;const c=armed.row.cabinet;const target=payload.cabinets.find(r=>r.id===rangeSelect.value);if(target){const b=target.basis,u=b[1].map((v,i)=>v-b[0][i]),front=b[2].map((v,i)=>v-b[0][i]);last=b[0].map((v,i)=>v+u[i]*target.cabinet.width/2+front[i]*c.depth/2);}if(!last)return;
  const base=KitchenHousePlacement.rowAt(armed.row,{x:-c.width/2,y:(c.kind.startsWith('corner_')?c.width:c.depth)/2,angle:0,handedness:1});
  proposal=KitchenHousePlacement.propose(base,last,payload.walls||[],Math.min(8,10/Math.max(.1,Math.abs(sx(1)-sx(0)))),payload.cabinets,proposal);
  if(target){const b=target.basis,u=b[1].map((v,i)=>v-b[0][i]),v=b[2].map((q,i)=>b[0][i]-q),origin=b[0].map((q,i)=>q+u[i]*(target.cabinet.width-c.width)/2);const h=KitchenHousePlacement.placement(c,origin,u,v,target.cabinet.house_placement?.wall_id?{wall_id:target.cabinet.house_placement.wall_id,face:target.cabinet.house_placement.face}:{});const row=KitchenHousePlacement.rowAt(armed.row,h);proposal={row,placement:h,error:KitchenHousePlacement.bundleError([row],payload.cabinets,payload.walls||[])};}
  const rows=armed.parts?armed.parts.map(row=>{const h=proposal.placement,transform=q=>KitchenHousePlacement.point({},h,...q);return {...row,polygon:row.polygon.map(transform),basis:row.basis.map(transform)};}):[proposal.row];
  KitchenSymbols.load({...payload,cabinets:[...payload.cabinets,...rows]});say(proposal.error||'');draw();
 }
 const load=KP.load;KP.load=function(next){payload=next;const changed=armed&&(next.revision!==armed.revision||next.wall_token!==armed.wall_token);if(changed&&!pending){cancel();say('Drawing changed. Select a cabinet again.');}const result=load.call(this,next);if(armed&&!pending)refresh();return result;};
 const hostDraw=draw;draw=function(){const result=hostDraw.apply(this,arguments);if(activePage===0&&proposal){ctx.save();ctx.strokeStyle=proposal.error?'#b74c3b':'#315f4f';ctx.lineWidth=2;ctx.setLineDash([5,3]);ctx.beginPath();proposal.row.polygon.forEach((p,i)=>i?ctx.lineTo(sx(p[0]),sy(p[1])):ctx.moveTo(sx(p[0]),sy(p[1])));ctx.closePath();ctx.stroke();ctx.restore();}return result;};
 const point=e=>{const r=cv.getBoundingClientRect();return [mx(e.clientX-r.left),my(e.clientY-r.top)];};
 cv.addEventListener('mousemove',e=>{if(!armed||pending)return;last=point(e);if(!frame)frame=requestAnimationFrame(refresh);},true);
 cv.addEventListener('mouseleave',()=>{if(armed&&!pending){last=null;proposal=null;restore();}},true);
 window.addEventListener('mousedown',e=>{if(e.target!==cv||(!armed&&!pending)||e.button!==0)return;e.preventDefault();e.stopImmediatePropagation();if(pending)return;last=point(e);refresh();if(!proposal||proposal.error){if(proposal?.error?.startsWith('Window is too low'))window.alert(proposal.error);return;}pending=true;say('Placing cabinet…');sketchup.kitchen_open_catalog(JSON.stringify({action:'place',kind:armed.kind,product_id:armed.product_id,without_cabinet:armed.without_cabinet,hood_style:armed.hood_style,...(armed.width!=null?{width:armed.width}:{}),wall:armed.wall,placement:proposal.placement,revision:armed.revision,wall_token:armed.wall_token}));},true);
 window.addEventListener('mouseup',e=>{if(e.target===cv&&(armed||pending)&&e.button===0){e.preventDefault();e.stopImmediatePropagation();}},true);
 window.addEventListener('keydown',e=>{if(e.key==='Escape'&&(armed||waiting)&&!pending){e.preventDefault();e.stopImmediatePropagation();cancel();KitchenSidebar.result(null);}},true);
 document.getElementById('kp-tool-rail').addEventListener('click',e=>{if(e.target.closest('button')&&!pending)cancel();},true);
 document.getElementById('kp-cab-area').addEventListener('change',()=>cancel());
 window.KitchenHouseInsert={
 request(){cancel();waiting=true;return ticket;},cancel,
 begin(data){if(!waiting||data.request_id!==ticket)return;waiting=false;armed=data;rangeSelect.replaceChildren(new Option('Place freely',''));for(const r of payload.cabinets.filter(r=>r.cabinet.kind==='oven'||r.cabinet.appliance?.category==='cooktop'))rangeSelect.add(new Option((r.cabinet.appliance?.model||'Range')+' · '+r.cabinet.width+' in',r.id));hoodTarget.style.display=data.kind==='hood'?'block':'none';size.style.display=data.product_id||data.parts?'none':'block';width.value=data.row.cabinet.width;width.min=data.row.cabinet.kind==='filler'?.5:12;if(data.row.cabinet.pullout?.type==='spice')width.min=9;proposal=null;last=null;cv.style.cursor='crosshair';say('');},
 result(error){pending=false;if(!error){cancel();KitchenSidebar.result(null);if(typeof armHiddenUndo==='function')armHiddenUndo();return;}if(error.includes('changed')||!armed)cancel();say(error);},
 get state(){return {armed:!!armed,pending,waiting,preview:proposal?.row||null};}
 };
})();
