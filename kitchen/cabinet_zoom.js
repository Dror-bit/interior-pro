/* Presentation only: independent SVG viewports, no cabinet or model changes. */
const CabinetPreviewZoom={views:new Map(),cabinetId:null};
const zoomStyle=document.createElement('style');zoomStyle.textContent=`
.cabinet-zoom-pane{position:relative;width:100%;min-height:0;overflow:hidden;flex:58 1 0;border-bottom:1px solid #dce3d9}
.cabinet-zoom-pane+ .cabinet-zoom-pane{flex:42 1 0}
.cabinet-zoom-toolbar{position:absolute;top:6px;left:8px;z-index:2;display:flex;align-items:center;gap:4px;padding:3px 5px;background:#fffffff2;border:1px solid #d6dfd3;border-radius:6px;font-size:11px}
.cabinet-zoom-toolbar button{padding:3px 8px;min-width:29px;font-size:13px;border:1px solid #cbd5ca;border-radius:4px;background:#fff;cursor:pointer}
.cabinet-zoom-toolbar output{min-width:36px;text-align:center}
.editor-preview .cabinet-zoom-pane svg{height:100%!important;width:100%;pointer-events:auto;touch-action:none;cursor:grab;border:0!important}
.editor-preview .cabinet-zoom-pane svg.zoom-panning{cursor:grabbing}
.editor-preview>span{pointer-events:none;background:#f5f7f1d9;padding:2px 5px;z-index:2}
`;document.head.append(zoomStyle);
function zoomApply(view){const b=view.box;view.svg.setAttribute('viewBox',`${b.x} ${b.y} ${b.w} ${b.h}`);view.output.textContent=Math.round(view.zoom*100)+'%';}
function zoomFit(view){
 const b=view.svg.getBBox();if(!b.width||!b.height)return;
 const padding=25;view.fit={x:b.x-padding,y:b.y-padding,w:b.width+padding*2,h:b.height+padding*2};view.box={...view.fit};view.zoom=1;zoomApply(view);
}
function zoomPoint(view,event){const p=view.svg.createSVGPoint();p.x=event.clientX;p.y=event.clientY;return p.matrixTransform(view.svg.getScreenCTM().inverse());}
function zoomChange(view,factor,anchor=null){
 if(!view.fit)return;const next=Math.max(.5,Math.min(8,view.zoom*factor)),ratio=view.zoom/next,b=view.box;
 if(!anchor){const cab=view.svg.querySelector('.cab');const bb=cab?.getBBox();anchor=view.zoom===1&&bb?{x:bb.x+bb.width/2,y:bb.y+bb.height/2}:{x:b.x+b.w/2,y:b.y+b.h/2};}
 view.box={x:anchor.x-(anchor.x-b.x)*ratio,y:anchor.y-(anchor.y-b.y)*ratio,w:b.w*ratio,h:b.h*ratio};view.zoom=next;zoomApply(view);
}
for(const [id,label] of [['cabinetPreview','Elevation'],['cabinetTopPreview','Top']]){
 const svgEl=$(id),pane=document.createElement('div');pane.className='cabinet-zoom-pane';svgEl.before(pane);pane.append(svgEl);
 const bar=document.createElement('div');bar.className='cabinet-zoom-toolbar';
 const title=document.createElement('b');title.textContent=label;bar.append(title);
 const view={svg:svgEl,box:{x:0,y:0,w:960,h:600},fit:null,zoom:1,pan:null};
 for(const [text,action] of [['−',()=>zoomChange(view,1/1.3)],['+',()=>zoomChange(view,1.3)],['Fit',()=>zoomFit(view)]]){
  const button=document.createElement('button');button.type='button';button.textContent=text;button.setAttribute('aria-label',label+' '+(text==='+'?'zoom in':text==='−'?'zoom out':'fit drawing'));button.onclick=action;bar.append(button);
 }
 view.output=document.createElement('output');bar.append(view.output);pane.append(bar);CabinetPreviewZoom.views.set(id,view);
 svgEl.addEventListener('wheel',e=>{e.preventDefault();zoomChange(view,e.deltaY<0?1.15:1/1.15,zoomPoint(view,e));},{passive:false});
 svgEl.addEventListener('pointerdown',e=>{if(e.button!==0)return;e.preventDefault();view.pan={id:e.pointerId,start:zoomPoint(view,e),box:{...view.box}};svgEl.setPointerCapture(e.pointerId);svgEl.classList.add('zoom-panning');});
 svgEl.addEventListener('pointermove',e=>{if(!view.pan||view.pan.id!==e.pointerId)return;const p=zoomPoint(view,e);view.box.x+=view.pan.start.x-p.x;view.box.y+=view.pan.start.y-p.y;zoomApply(view);});
 const stop=()=>{if(view.pan&&svgEl.hasPointerCapture(view.pan.id))svgEl.releasePointerCapture(view.pan.id);view.pan=null;svgEl.classList.remove('zoom-panning');};
 svgEl.addEventListener('pointerup',stop);svgEl.addEventListener('pointercancel',stop);svgEl.addEventListener('lostpointercapture',()=>{view.pan=null;svgEl.classList.remove('zoom-panning');});
}
const refreshBeforeZoom=refreshCabinetPreview;
refreshCabinetPreview=function(){
 refreshBeforeZoom();if(!cabinetDialog.open||!selected)return;
 let previewDraft;try{previewDraft=cabinetDraft();}catch{return;}
 const changed=CabinetPreviewZoom.cabinetId!==selected.id;CabinetPreviewZoom.cabinetId=selected.id;
 const pantryDimensions=!!previewDraft.pantry;if(CabinetPreviewZoom.pantryDimensions!==pantryDimensions){CabinetPreviewZoom.pantryDimensions=pantryDimensions;const elevation=CabinetPreviewZoom.views.get('cabinetPreview');if(elevation)elevation.fit=null;}
 const pose=JSON.stringify([previewDraft.rotation,previewDraft.rotation_pivot]);for(const view of CabinetPreviewZoom.views.values()){if(changed||!view.fit||(view.svg.id==='cabinetTopPreview'&&CabinetPreviewZoom.pose!==pose))zoomFit(view);else zoomApply(view);}CabinetPreviewZoom.pose=pose;
};
cabinetDialog.addEventListener('close',()=>{for(const view of CabinetPreviewZoom.views.values())view.pan=null;});
