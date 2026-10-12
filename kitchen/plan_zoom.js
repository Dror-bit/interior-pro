/* Main workspace viewport only. Cabinet data and model geometry stay unchanged. */
const PlanZoom={svg:$('drawing'),box:{x:0,y:0,w:960,h:600},zoom:1,pan:null};
const planZoomBar=document.createElement('div');
planZoomBar.style.cssText='display:flex;align-items:center;gap:4px;background:white;padding:4px;border:1px solid #d8dfd6;border-radius:7px';
planZoomBar.setAttribute('aria-label','Drawing zoom');
function applyPlanZoom(){const b=PlanZoom.box;PlanZoom.svg.setAttribute('viewBox',`${b.x} ${b.y} ${b.w} ${b.h}`);PlanZoom.output.textContent=Math.round(PlanZoom.zoom*100)+'%';}
function changePlanZoom(factor,anchor){
 const next=Math.max(.5,Math.min(8,PlanZoom.zoom*factor)),ratio=PlanZoom.zoom/next,b=PlanZoom.box;
 if(!anchor){const bb=PlanZoom.svg.querySelector('.cab[data-id="'+selected?.id+'"]')?.getBBox();anchor=bb?{x:bb.x+bb.width/2,y:bb.y+bb.height/2}:{x:b.x+b.w/2,y:b.y+b.h/2};if(bb){b.x=anchor.x-b.w/2;b.y=anchor.y-b.h/2;}}
 PlanZoom.box={x:anchor.x-(anchor.x-b.x)*ratio,y:anchor.y-(anchor.y-b.y)*ratio,w:b.w*ratio,h:b.h*ratio};PlanZoom.zoom=next;applyPlanZoom();
}
for(const [label,title,action] of [['−','Zoom out',()=>changePlanZoom(1/1.3)],['+','Zoom in',()=>changePlanZoom(1.3)],['Fit','Fit entire kitchen',()=>{PlanZoom.box={x:0,y:0,w:960,h:600};PlanZoom.zoom=1;applyPlanZoom();}]]){
 const button=document.createElement('button');button.type='button';button.className='subtle';button.textContent=label;button.title=title;button.setAttribute('aria-label',title);button.onclick=action;planZoomBar.append(button);
}
PlanZoom.output=document.createElement('output');PlanZoom.output.hidden=true;planZoomBar.append(PlanZoom.output);
// Zoom stays on the mouse wheel; no visible toolbar controls.
document.querySelector('.canvas-zone .toolbar').style.flexWrap='wrap';
PlanZoom.svg.addEventListener('wheel',e=>{e.preventDefault();if(!drag)changePlanZoom(e.deltaY<0?1.15:1/1.15,drawingPoint(e));},{passive:false});
PlanZoom.svg.addEventListener('pointerdown',e=>{if(e.button!==1||drag)return;e.preventDefault();e.stopImmediatePropagation();PlanZoom.pan={id:e.pointerId,start:drawingPoint(e)};PlanZoom.svg.setPointerCapture(e.pointerId);},true);
PlanZoom.svg.addEventListener('pointermove',e=>{if(!PlanZoom.pan||e.pointerId!==PlanZoom.pan.id)return;e.stopImmediatePropagation();const p=drawingPoint(e);PlanZoom.box.x+=PlanZoom.pan.start.x-p.x;PlanZoom.box.y+=PlanZoom.pan.start.y-p.y;applyPlanZoom();},true);
function stopPlanPan(e){if(!PlanZoom.pan||e.pointerId!==PlanZoom.pan.id)return;e.stopImmediatePropagation();if(PlanZoom.svg.hasPointerCapture(e.pointerId))PlanZoom.svg.releasePointerCapture(e.pointerId);PlanZoom.pan=null;}
PlanZoom.svg.addEventListener('pointerup',stopPlanPan,true);PlanZoom.svg.addEventListener('pointercancel',stopPlanPan,true);
PlanZoom.svg.addEventListener('auxclick',e=>{if(e.button===1)e.preventDefault();});
PlanZoom.svg.addEventListener('lostpointercapture',()=>{PlanZoom.pan=null;});
planZoomBar.title='Scroll to zoom · Hold middle mouse button to pan';applyPlanZoom();
function revealPlanSelection(){
 const bb=PlanZoom.svg.querySelector('.cab[data-id="'+selected?.id+'"]')?.getBBox();if(!bb)return;
 const b=PlanZoom.box,cx=bb.x+bb.width/2,cy=bb.y+bb.height/2;
 if(cx<b.x||cx>b.x+b.w||cy<b.y||cy>b.y+b.h){b.x=cx-b.w/2;b.y=cy-b.h/2;applyPlanZoom();}
}
const receiveBeforePlanZoom=window.receiveKitchen;
window.receiveKitchen=function(data){receiveBeforePlanZoom(data);revealPlanSelection();};
const chooseBeforePlanZoom=choose;
choose=function(id){chooseBeforePlanZoom(id);revealPlanSelection();};
