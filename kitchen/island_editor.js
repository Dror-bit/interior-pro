let islandDrag=null;
function renderIslandMoveArrows(target){
 const grip=target.querySelector('[data-island-grip]');if(!grip||grip.dataset.arrows)return;
 const boxes=cabinets.filter(c=>wallOf(c)==='I').map(c=>KitchenPlacement.footprint(c));if(!boxes.length)return;
 const right=Math.max(...boxes.map(b=>b[1])),bottom=Math.min(...boxes.map(b=>b[2])),top=Math.max(...boxes.map(b=>b[3]));
 const x=layout.ox+right*layout.s+3,y=layout.base-top*layout.s-3;
 grip.dataset.arrows='true';grip.setAttribute('aria-label','Drag to move island');
 grip.innerHTML=svg('title',{},'Drag to move island')+svg('g',{transform:`translate(${x},${y}) scale(0.40)`},
 svg('circle',{cx:0,cy:0,r:8,fill:'#fafbf8',stroke:'#315f4f','stroke-width':1})+svg('path',{transform:'scale(0.35)',d:'M 0 -15 V 15 M -15 0 H 15 M -5 -10 L 0 -15 L 5 -10 M -5 10 L 0 15 L 5 10 M -10 -5 L -15 0 L -10 5 M 10 -5 L 15 0 L 10 5',fill:'none',stroke:'#315f4f','stroke-width':2.5,'stroke-linecap':'round','stroke-linejoin':'round','pointer-events':'none'}));
}
const drawPlanBeforeIslandArrows=drawPlan;
drawPlan=function(...args){drawPlanBeforeIslandArrows(...args);renderIslandMoveArrows(args[1]||$('drawing'));};
const islandControls=document.createElement('section');islandControls.id='islandControls';islandControls.hidden=true;
islandControls.innerHTML='<h2>Island position</h2><div class="fields"><label>Along Run A ″<input id="islandX" type="number" min="-1200" max="1200" step="0.125"></label><label>Distance from Run A ″<input id="islandY" type="number" min="-1200" max="1200" step="0.125"></label><label>Rotation °<input id="islandAngle" type="number" min="-360" max="360" step="1"></label><button id="turnIsland" type="button" class="subtle">Rotate 90°</button></div><button type="button" id="moveIsland" class="subtle" style="margin:10px 0">Apply island position</button><div class="tiny">Rotation is around the island origin. Top view: drag the green four-arrow move handle.</div>';
$('form').before(islandControls);
const layoutFillBeforeIsland=fillLayout;
fillLayout=function(){layoutFillBeforeIsland();islandControls.hidden=true;$('islandX').value=KitchenPlacement.island.x;$('islandY').value=KitchenPlacement.island.y;$('islandAngle').value=KitchenPlacement.island.angle||0;for(const k of ['x','y','z','angle','level'])$('pose_'+k).value=KitchenPlacement.pose[k];};
function applyIslandPosition(){if(busy)return;const x=Number($('islandX').value),y=Number($('islandY').value),angle=Number($('islandAngle').value);if(![x,y].every(v=>Number.isFinite(v)&&v>=-1200&&v<=1200)||!Number.isFinite(angle)||Math.abs(angle)>360){$('error').textContent='Check island position and rotation.';return;}pending(true);send('island',JSON.stringify({x,y,angle}));}
$('moveIsland').addEventListener('click',applyIslandPosition);
$('turnIsland').addEventListener('click',()=>{if(busy)return;$('islandAngle').value=((Number($('islandAngle').value)||0)+90)%360;applyIslandPosition();});
$('drawing').addEventListener('pointerdown',e=>{
 if(busy||!e.target.closest('[data-island-grip]'))return;e.preventDefault();cancelDrag();
 islandDrag={pointer:e.pointerId,start:drawingPoint(e),original:{...KitchenPlacement.island},frame:{...layout}};
 $('drawing').setPointerCapture(e.pointerId);
});
function updateIslandDrag(e){
 if(!islandDrag||e.pointerId!==islandDrag.pointer)return;
 const p=drawingPoint(e),d=islandDrag;
 const [dx,dy]=KitchenPlacement.rotate((p.x-d.start.x)/d.frame.s,-(p.y-d.start.y)/d.frame.s,-KitchenPlacement.pose.angle);
 KitchenPlacement.island={...d.original,x:Math.round(Math.max(-1200,Math.min(1200,d.original.x+dx))*8)/8,y:Math.round(Math.max(-1200,Math.min(1200,d.original.y-dy))*8)/8};
 d.valid=!cabinets.some((c,i)=>cabinets.slice(i+1).some(o=>KitchenPlacement.overlap(c,o)));
 $('status').textContent=d.valid?'Move island · Release to place':'Island overlaps cabinets · Move farther away';draw();
}
$('drawing').addEventListener('pointermove',updateIslandDrag);
function cancelIslandDrag(){if(!islandDrag)return;KitchenPlacement.island=islandDrag.original;try{$('drawing').releasePointerCapture(islandDrag.pointer);}catch(_){}islandDrag=null;draw();}
$('drawing').addEventListener('pointerup',e=>{
 if(!islandDrag)return;updateIslandDrag(e);const result=islandDrag,next={...KitchenPlacement.island};cancelIslandDrag();
 if(!result.valid){$('error').textContent='Island overlaps cabinets. Position unchanged.';return;}
 if(next.x===result.original.x&&next.y===result.original.y)return;pending(true);send('island',JSON.stringify(next));
});
$('drawing').addEventListener('pointercancel',cancelIslandDrag);
window.addEventListener('keydown',e=>{if(e.key==='Escape')cancelIslandDrag();});
window.addEventListener('blur',cancelIslandDrag);
const poseControls=document.createElement('details');
poseControls.innerHTML='<summary>Kitchen location in house</summary><div class="fields" style="margin-top:12px">'+[['x','House X ″'],['y','House Y ″'],['z','Floor height ″'],['angle','Rotation °'],['level','Level']].map(([k,label])=>'<label>'+label+'<input id="pose_'+k+'" type="number" step="'+(k==='level'?'1':'0.125')+'"></label>').join('')+'</div><button id="applyPose" type="button" class="subtle" style="margin:10px 0">Move whole kitchen</button><div class="tiny">House coordinates. Floor height is absolute; cabinet heights stay relative to this floor. Level selects house references; it does not automatically set floor height.</div>';
poseControls.hidden=true;islandControls.before(poseControls);
$('applyPose').addEventListener('click',()=>{if(busy)return;const p=Object.fromEntries(['x','y','z','angle','level'].map(k=>[k,Number($('pose_'+k).value)]));if(!Object.values(p).every(Number.isFinite)||!Number.isInteger(p.level)||p.level<1||p.level>100||Math.abs(p.angle)>360||['x','y','z'].some(k=>Math.abs(p[k])>12000)){$('error').textContent='Check kitchen coordinates, rotation and level.';return;}pending(true);send('pose',JSON.stringify(p));});
