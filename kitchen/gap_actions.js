/* Commands share the engine's transaction, validation and Undo path. */
const gapActions=document.createElement('dialog');gapActions.id='gapActions';gapActions.style.cssText='border:1px solid #cdd6cf;border-radius:10px;padding:20px;width:340px;color:#274b3c';
gapActions.innerHTML='<h2 id="gapActionTitle"></h2><p id="gapActionNote" class="tiny"></p><div style="display:grid;gap:9px"><button type="button" class="primary" id="gapPrimary"></button><button type="button" class="subtle" id="gapSecondary"></button><button type="button" class="subtle" id="gapCancel">Cancel</button></div><p id="gapActionError" role="alert" style="color:#a43425"></p>';document.body.append(gapActions);
let gapActionRequest=null;
function submitGapAction(command){if(busy)return;if(!window.sketchup?.command){$('gapActionError').textContent='Open from SketchUp to change the layout.';return;}gapActionRequest=true;pending(true);$('gapPrimary').disabled=true;$('gapSecondary').disabled=true;sendCommands([command]);}
function setupGapAction(title,note){$('gapActionTitle').textContent=title;$('gapActionNote').textContent=note;$('gapActionError').textContent='';$('gapPrimary').disabled=false;$('gapSecondary').disabled=false;gapActions.showModal();}
$('gapCancel').onclick=()=>{if(!busy)gapActions.close();};gapActions.addEventListener('cancel',e=>{if(busy)e.preventDefault();});
function openDeleteOptions(){if(!selected||busy||drag)return;const id=selected.id;setupGapAction('Delete cabinet','Close space shifts following cabinets in the same row. Other rows and islands stay in place. Ctrl+Z restores the whole action.');$('gapPrimary').textContent='Delete & close gap';$('gapSecondary').textContent='Delete & keep space';$('gapPrimary').disabled=KitchenPlacement.corner(selected)||(selected.rotation||0)%360!==0;$('gapPrimary').onclick=()=>submitGapAction({type:'remove_cabinet_and_close_gap',payload:{id}});$('gapSecondary').onclick=()=>submitGapAction({type:'remove_cabinet',payload:{id}});}
$('remove').addEventListener('click',e=>{e.stopImmediatePropagation();openDeleteOptions();},true);
function gapAtPoint(world){
 const ordered=[...cabinets].sort((a,b)=>(Math.abs(a.z-(selected?.z||0))-Math.abs(b.z-(selected?.z||0)))||a.x-b.x);
 for(const left of ordered){if((left.rotation||0)%360!==0)continue;
  const row=cabinets.filter(c=>wallOf(c)===wallOf(left)&&Math.abs(c.z-left.z)<.001&&Math.abs((c.offset_y||0)-(left.offset_y||0))<.001).sort((a,b)=>a.x-b.x),right=row[row.findIndex(c=>c.id===left.id)+1];
  if(!right||(right.rotation||0)%360!==0)continue;const start=left.x+left.width,gap=right.x-start;if(gap<=.001)continue;
  const area=wallOf(left),x=KitchenPlacement.along(area,...world),o=KitchenPlacement.point(area,0,0),n=KitchenPlacement.point(area,0,1),y=(world[0]-o[0])*(n[0]-o[0])+(world[1]-o[1])*(n[1]-o[1]);
  if(x>start+.001&&x<right.x-.001&&y<=(left.offset_y||0)+2&&y>=(left.offset_y||0)-Math.max(left.depth,right.depth)-2)return {left,right,gap,area};
 }return null;
}
$('drawing').addEventListener('contextmenu',e=>{if(mode!=='top'||busy||drag||e.target.closest('.cab,[data-cab-rotate],[data-island-grip],[data-island-dimension]'))return;const p=drawingPoint(e),world=[(p.x-layout.ox)/layout.s,(layout.base-p.y)/layout.s],gap=gapAtPoint(world);if(!gap)return;e.preventDefault();setupGapAction('Close '+fmt(gap.gap)+' gap','Shift cabinets on the right toward the left cabinet, within this row. Ctrl+Z restores the layout.');$('gapPrimary').textContent='Close gap';$('gapSecondary').textContent='Add cabinet here';$('gapPrimary').onclick=()=>submitGapAction({type:'close_gap',payload:{left_id:gap.left.id,right_id:gap.right.id,gap:gap.gap}});$('gapSecondary').onclick=()=>{gapActions.close();openPointPlacement(world,gap.area);};});
const receiveBeforeGapActions=window.receiveKitchen;
window.receiveKitchen=function(data){receiveBeforeGapActions(data);if(!gapActionRequest)return;gapActionRequest=null;$('gapPrimary').disabled=false;$('gapSecondary').disabled=false;if(data.error)$('gapActionError').textContent=data.error;else gapActions.close();};
