// Small placement dialog; the existing engine owns dimensions, collision and Undo.
const pointDialog=document.createElement('dialog');
pointDialog.id='pointPlacement';pointDialog.style.cssText='border:1px solid #cdd6cf;border-radius:12px;padding:22px;width:330px;color:#274b3c';
pointDialog.innerHTML='<h2>Place cabinet here</h2><p class="tiny">Click inside a gap. The cabinet will shift within that gap if needed to fit. A new island starts at the clicked point.</p><label>Place on<select id="pointArea"><option value="A">Run A</option><option value="B">Run B · perpendicular</option><option value="I">Island</option></select></label><label>Cabinet<select id="pointKind"><option value="doors">Base · doors</option><option value="drawers">Base · drawers</option><option value="sink">Sink base</option><option value="wall">Upper cabinet</option><option value="tall">Tall cabinet</option><option value="filler">Filler</option></select></label><label>Width ″<input id="pointWidth" type="number" value="36" min="0.5" max="60" step="0.125"></label><p id="pointNote" class="tiny"></p><p id="pointError" role="alert" style="color:#a43425"></p><div class="actions"><button id="pointCreate" class="primary" type="button">Place cabinet</button><button id="pointCancel" type="button">Cancel</button></div>';
document.body.append(pointDialog);
let pointWorld=null,pointPress=null,pointRequest=false;
function closePointPlacement(){pointDialog.close();pointWorld=null;$('drawing').querySelector('.point-marker')?.remove();}
function updatePointNote(){
 if(!pointWorld)return;
 try{const cmd=KitchenPointPlacement.command(pointWorld,$('pointArea').value,$('pointKind').value,Number($('pointWidth').value),cabinets);
 $('pointNote').textContent=cmd.type==='create_island_cabinet'?'New island · Move and rotate it with Island position.':'Preferred start from run origin: '+fmt(cmd.payload.overrides.x);$('pointError').textContent='';
 }catch(e){$('pointError').textContent=e.message;}
}
function openPointPlacement(world,area){
 if(busy)return;pointWorld=world;$('pointArea').value=area||KitchenPointPlacement.suggest(world);$('pointError').textContent='';updatePointNote();pointDialog.showModal();
 const p=[layout.ox+world[0]*layout.s,layout.base-world[1]*layout.s];
 $('drawing').insertAdjacentHTML('beforeend',svg('circle',{class:'point-marker',cx:p[0],cy:p[1],r:7,fill:'#16866b',stroke:'#fff','stroke-width':2,'pointer-events':'none'}));
}
$('pointKind').onchange=()=>{$('pointWidth').value=$('pointKind').value==='filler'?3:['drawers','tall'].includes($('pointKind').value)?24:36;updatePointNote();};
$('pointArea').onchange=updatePointNote;$('pointWidth').oninput=updatePointNote;
$('pointCancel').onclick=closePointPlacement;pointDialog.addEventListener('cancel',()=>{pointWorld=null;$('drawing').querySelector('.point-marker')?.remove();});
$('pointCreate').onclick=()=>{
 if(busy||!pointWorld)return;
 if(!window.sketchup?.command){$('pointError').textContent='Open from SketchUp to place cabinets.';return;}
 try{const cmd=KitchenPointPlacement.command(pointWorld,$('pointArea').value,$('pointKind').value,Number($('pointWidth').value),cabinets);activeWall=$('pointArea').value;$('active_wall').value=activeWall;pointRequest=true;pending(true);$('pointCreate').disabled=true;sendCommands([cmd]);}
 catch(e){pending(false);$('pointError').textContent=e.message;}
};
const receiveBeforePointPlacement=window.receiveKitchen;
window.receiveKitchen=function(data){receiveBeforePointPlacement(data);if(!pointRequest)return;pointRequest=false;$('pointCreate').disabled=false;if(data.error)$('pointError').textContent=data.error;else closePointPlacement();};

// Empty canvas clicks are inert unless the user explicitly starts an island.
let catalogDragKind=null,islandPlacementArmed=false;
const createIslandButton=document.createElement('button');
createIslandButton.id='createIsland';createIslandButton.type='button';createIslandButton.className='subtle';
createIslandButton.textContent='Create island';createIslandButton.style.cssText='width:100%;margin-bottom:12px';
$('settingsForm').closest('details').before(createIslandButton);
function armIslandPlacement(enabled){
 islandPlacementArmed=enabled;createIslandButton.textContent=enabled?'Cancel island placement':'Create island';
 $('drawing').style.cursor=enabled?'crosshair':'';
 $('status').textContent=enabled?'Click to place the first island cabinet, or drag a cabinet here.':'';
}
createIslandButton.onclick=()=>{
 if(busy)return;
 if(cabinets.some(c=>wallOf(c)==='I')){activeWall='I';$('active_wall').value='I';$('status').textContent='Island selected · Drag cabinets onto the island.';return;}
 document.querySelector('[data-view="top"]').click();armIslandPlacement(!islandPlacementArmed);
};
function catalogDropArea(world){
 if(islandPlacementArmed)return 'I';
 const areas=['A','B',...(cabinets.some(c=>wallOf(c)==='I')?['I']:[])];
 const choices=areas.map(area=>{const o=KitchenPlacement.point(area,0,-12),u=KitchenPlacement.point(area,1,-12),dx=u[0]-o[0],dy=u[1]-o[1],px=world[0]-o[0],py=world[1]-o[1];return {area,along:px*dx+py*dy,distance:Math.abs(px*dy-py*dx)};}).filter(r=>r.along>=0&&r.distance<=36).sort((a,b)=>a.distance-b.distance);
 if(!choices.length)throw Error('Drop on a wall run or choose Create island.');
 return choices[0].area;
}
function placeCatalogCabinet(world,kind){
 if(busy)return;
 if(!window.sketchup?.command){$('error').textContent='Open from SketchUp to place cabinets.';return;}
 try{
  const area=catalogDropArea(world),command=KitchenPointPlacement.command(world,area,kind,36,cabinets);
  // Let the engine choose the real catalog width, height and depth.
  delete command.payload.overrides.width;
  activeWall=area;$('active_wall').value=area;pending(true);sendCommands([command]);armIslandPlacement(false);
 }catch(error){pending(false);$('error').textContent=error.message;}
}
for(const tile of document.querySelectorAll('.tile[data-kind]')){
 tile.draggable=true;
 tile.addEventListener('dragstart',e=>{if(busy){e.preventDefault();return;}catalogDragKind=tile.dataset.kind;e.dataTransfer.setData('text/plain',catalogDragKind);e.dataTransfer.effectAllowed='copy';if(mode!=='top')document.querySelector('[data-view="top"]').click();});
 tile.addEventListener('dragend',()=>{catalogDragKind=null;});
}
$('drawing').addEventListener('dragover',e=>{if(catalogDragKind&&!busy){e.preventDefault();e.dataTransfer.dropEffect='copy';}});
$('drawing').addEventListener('drop',e=>{
 if(!catalogDragKind||busy)return;e.preventDefault();const p=drawingPoint(e),kind=catalogDragKind;catalogDragKind=null;
 placeCatalogCabinet([(p.x-layout.ox)/layout.s,(layout.base-p.y)/layout.s],kind);
});
$('drawing').addEventListener('click',e=>{
 if(!islandPlacementArmed||busy||e.target.closest('.cab,[data-island-grip],[data-island-dimension]'))return;
 const p=drawingPoint(e);placeCatalogCabinet([(p.x-layout.ox)/layout.s,(layout.base-p.y)/layout.s],'doors');
});
window.addEventListener('keydown',e=>{if(e.key==='Escape')armIslandPlacement(false);});
