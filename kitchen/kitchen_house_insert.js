(function(){
 if(window.KitchenHouseInsert)return;
 let payload={cabinets:[],walls:[]},armed=null,proposal=null,pending=false,waiting=false,ticket=0,frame=0,last=null;
 const note=document.createElement('div');note.id='kp-insert-note';note.style.cssText='position:absolute;left:20px;bottom:18px;padding:7px 11px;background:white;border:1px solid #dce3da;border-radius:6px;color:#315f4f;pointer-events:none;display:none;z-index:6';document.getElementById('canvasWrap').append(note);
 const say=text=>{note.textContent=text||'';note.style.display=text?'block':'none';};
 const restore=()=>{KitchenSymbols.load(payload);draw();};
 function cancel(){if(pending)return false;if(frame)cancelAnimationFrame(frame);frame=0;ticket++;waiting=false;armed=null;proposal=null;last=null;cv.style.cursor='';say('');restore();return true;}
 function refresh(){if(frame)cancelAnimationFrame(frame);frame=0;if(!armed||!last||pending)return;const c=armed.row.cabinet;
  const base=KitchenHousePlacement.rowAt(armed.row,{x:-c.width/2,y:(c.kind.startsWith('corner_')?c.width:c.depth)/2,angle:0,handedness:1});
  proposal=KitchenHousePlacement.propose(base,last,payload.walls||[],Math.min(8,10/Math.max(.1,Math.abs(sx(1)-sx(0)))),payload.cabinets,proposal);
  KitchenSymbols.load({...payload,cabinets:[...payload.cabinets,proposal.row]});say(proposal.error||'');draw();
 }
 const load=KP.load;KP.load=function(next){payload=next;const changed=armed&&(next.revision!==armed.revision||next.wall_token!==armed.wall_token);if(changed&&!pending){cancel();say('Drawing changed. Select a cabinet again.');}const result=load.call(this,next);if(armed&&!pending)refresh();return result;};
 const hostDraw=draw;draw=function(){const result=hostDraw.apply(this,arguments);if(activePage===0&&proposal){ctx.save();ctx.strokeStyle=proposal.error?'#b74c3b':'#315f4f';ctx.lineWidth=2;ctx.setLineDash([5,3]);ctx.beginPath();proposal.row.polygon.forEach((p,i)=>i?ctx.lineTo(sx(p[0]),sy(p[1])):ctx.moveTo(sx(p[0]),sy(p[1])));ctx.closePath();ctx.stroke();ctx.restore();}return result;};
 const point=e=>{const r=cv.getBoundingClientRect();return [mx(e.clientX-r.left),my(e.clientY-r.top)];};
 cv.addEventListener('mousemove',e=>{if(!armed||pending)return;last=point(e);if(!frame)frame=requestAnimationFrame(refresh);},true);
 cv.addEventListener('mouseleave',()=>{if(armed&&!pending){last=null;proposal=null;restore();}},true);
 window.addEventListener('mousedown',e=>{if(e.target!==cv||(!armed&&!pending)||e.button!==0)return;e.preventDefault();e.stopImmediatePropagation();if(pending)return;last=point(e);refresh();if(!proposal||proposal.error){if(proposal?.error?.startsWith('Window is too low'))window.alert(proposal.error);return;}pending=true;say('Placing cabinet…');sketchup.kitchen_open_catalog(JSON.stringify({action:'place',kind:armed.kind,wall:armed.wall,placement:proposal.placement,revision:armed.revision,wall_token:armed.wall_token}));},true);
 window.addEventListener('mouseup',e=>{if(e.target===cv&&(armed||pending)&&e.button===0){e.preventDefault();e.stopImmediatePropagation();}},true);
 window.addEventListener('keydown',e=>{if(e.key==='Escape'&&(armed||waiting)&&!pending){e.preventDefault();e.stopImmediatePropagation();cancel();KitchenSidebar.result(null);}},true);
 document.getElementById('kp-tool-rail').addEventListener('click',e=>{if(e.target.closest('button')&&!pending)cancel();},true);
 document.getElementById('kp-cab-area').addEventListener('change',()=>cancel());
 window.KitchenHouseInsert={
 request(){cancel();waiting=true;return ticket;},cancel,
 begin(data){if(!waiting||data.request_id!==ticket)return;waiting=false;armed=data;proposal=null;last=null;cv.style.cursor='crosshair';say('');},
 result(error){pending=false;if(!error){cancel();KitchenSidebar.result(null);return;}if(error.includes('changed')||!armed)cancel();say(error);},
 get state(){return {armed:!!armed,pending,waiting,preview:proposal?.row||null};}
 };
})();
