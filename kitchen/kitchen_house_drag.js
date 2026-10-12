(function(){
 if(window.KitchenHouseDrag)return;
 let payload={cabinets:[],walls:[]},gesture=null,preview=null,selected=null,pending=false,frame=0,latest=null;
 const note=document.createElement('div');note.id='kp-drag-note';note.style.cssText='position:absolute;left:20px;bottom:18px;padding:7px 11px;background:#fff;border:1px solid #dce3da;border-radius:6px;color:#315f4f;pointer-events:none;display:none;z-index:5';document.getElementById('canvasWrap').append(note);
 const message=text=>{note.textContent=text||'';note.style.display=text?'block':'none';};
 const world=e=>{const r=cv.getBoundingClientRect();return [mx(e.clientX-r.left),my(e.clientY-r.top)];};
 const load=KP.load;KP.load=function(next){if(gesture&&next.revision===payload.revision&&next.wall_token===payload.wall_token)return;payload=next;if(gesture){gesture=null;preview=null;latest=null;}return load.call(this,next);};
 const hostDraw=draw;draw=function(){const result=hostDraw.apply(this,arguments);if(activePage===0){const row=preview?.row||payload.cabinets.find(c=>c.id===selected);if(row){ctx.save();ctx.strokeStyle=preview?.error?'#b74c3b':'#315f4f';ctx.lineWidth=2;ctx.setLineDash(preview?[5,3]:[]);ctx.beginPath();row.polygon.forEach((p,i)=>i?ctx.lineTo(sx(p[0]),sy(p[1])):ctx.moveTo(sx(p[0]),sy(p[1])));ctx.closePath();ctx.stroke();ctx.restore();}}return result;};
 function flush(){if(frame)cancelAnimationFrame(frame);frame=0;if(!gesture||!latest)return;const p=latest;latest=null;const delta=p.map((v,i)=>v-gesture.start[i]),scale=Math.abs(sx(1)-sx(0));preview=KitchenHousePlacement.propose(gesture.row,delta,payload.walls||[],Math.min(8,10/Math.max(.1,scale)),payload.cabinets,preview);KitchenSymbols.load({...payload,cabinets:payload.cabinets.map(c=>c.id===selected?preview.row:c)});message(preview.error||'');draw();}
 function reset(){if(frame)cancelAnimationFrame(frame);frame=0;latest=null;gesture=null;preview=null;KitchenSymbols.load(payload);draw();}
 cv.addEventListener('mousedown',e=>{if(activePage!==0||mode!=='sel'||e.button!==0||e.ctrlKey||e.metaKey||e.shiftKey||pending)return;const p=world(e);if(hitOpening({x:p[0],y:p[1]}))return;const hit=KP.hit(...p);if(!hit)return;e.preventDefault();e.stopImmediatePropagation();selected=hit.id;gesture={row:hit,start:p,screen:[e.clientX,e.clientY],moved:false};message('');draw();},true);
 window.addEventListener('mousemove',e=>{if(!gesture)return;e.preventDefault();e.stopImmediatePropagation();if(!gesture.moved&&Math.hypot(e.clientX-gesture.screen[0],e.clientY-gesture.screen[1])<4)return;gesture.moved=true;latest=world(e);if(!frame)frame=requestAnimationFrame(flush);},true);
 window.addEventListener('mouseup',e=>{if(!gesture)return;e.preventDefault();e.stopImmediatePropagation();if(gesture.moved){latest=world(e);flush();}const proposal=preview,moved=gesture.moved,id=gesture.row.id;if(!moved){reset();message('');return;}if(!proposal||proposal.error){reset();message(proposal?.error);if(proposal?.error?.startsWith('Window is too low'))window.alert(proposal.error);return;}
  // Keep the dropped preview visible until Ruby confirms the new model state.
  gesture=null;latest=null;pending=true;message('Updating cabinet…');sketchup.kitchen_move_cabinet(JSON.stringify({id,placement:proposal.placement,revision:payload.revision,wall_token:payload.wall_token}));
 },true);
 window.addEventListener('keydown',e=>{if(e.key==='Escape'&&gesture){e.preventDefault();e.stopImmediatePropagation();reset();message('');}},true);
 window.addEventListener('blur',()=>{if(gesture){reset();message('');}});
 window.KitchenHouseDrag={result(error){pending=false;reset();message(error||'');},get state(){return {pending,dragging:!!gesture,selected};}};
})();
