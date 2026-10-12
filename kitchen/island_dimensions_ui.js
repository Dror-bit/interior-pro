let islandDimensionRows=[],islandDimensionEdit=null,islandDimensionWaiting=false;
const dimensionControls=document.createElement('div');dimensionControls.className='toolbar';dimensionControls.style.cssText='margin:7px 0;font-size:12px;gap:12px';
dimensionControls.innerHTML='<span id="islandDimensionHint" class="tiny"></span>';document.querySelector('.canvas-zone .toolbar').after(dimensionControls);
const dimensionDialog=document.createElement('dialog');dimensionDialog.id='islandDimensionDialog';dimensionDialog.style.cssText='border:1px solid #bccada;border-radius:12px;padding:22px;width:340px';
dimensionDialog.innerHTML='<h2>Set island distance</h2><p id="islandDimensionDescription" class="tiny"></p><form id="islandDimensionForm"><label>Clear distance ″<input id="islandDimensionValue" type="number" min="0" max="1200" step="any" required></label><p id="islandDimensionError" role="alert" style="color:#a43425"></p><div class="actions"><button id="islandDimensionApply" type="submit" class="primary">Move island</button><button id="islandDimensionCancel" type="button">Cancel</button></div></form>';
document.body.append(dimensionDialog);
function renderIslandDimensions(source,frame){
 islandDimensionRows=[];
 const preferences=kitchenSettings.island_dimensions||{};
 if(preferences.visible===false)return '';
 islandDimensionRows=KitchenDimensions.automatic(source,houseContext.items||[],preferences);

 $('islandDimensionHint').textContent=source.some(c=>wallOf(c)==='I')&&islandDimensionRows.length<2?'No cabinet or wall reference in one of the measurement directions.':''; const project=p=>{const w=KitchenPlacement.point('A',...p);return [frame.ox+w[0]*frame.s,frame.base-w[1]*frame.s];};
 return islandDimensionRows.map((m,index)=>{
  const basis=m.basis;const a=project(m.from),b=project(m.to),dx=b[0]-a[0],dy=b[1]-a[1],len=Math.hypot(dx,dy);if(len<1)return '';
  const ux=dx/len,uy=dy/len,tx=-uy,ty=ux,tick=p=>line(p[0]-4*(ux+tx),p[1]-4*(uy+ty),p[0]+4*(ux+tx),p[1]+4*(uy+ty),'#234eb6',{'stroke-width':1.2,'pointer-events':'none'});
  let angle=Math.atan2(dy,dx)*180/Math.PI;if(angle>90)angle-=180;if(angle< -90)angle+=180;
  const label=svg('g',{transform:`translate(${(a[0]+b[0])/2},${(a[1]+b[1])/2}) rotate(${angle})`},rect(-43,-18,86,36,'transparent','none')+text(0,-2,fmt(m.distance),{'font-size':15,fill:'#234eb6','font-weight':600})+text(0,12,basis==='body'?'cabinet gap':basis==='countertop'?'counter gap':'wall gap',{'font-size':9,fill:'#526b9a'}));
  return svg('g',{'data-island-dimension':index,class:'island-dimension',role:'button',tabindex:0,'aria-label':`${basis} ${m.side} gap ${fmt(m.distance)}. Set distance.`,style:'cursor:pointer'},line(...a,...b,'#234eb6',{'stroke-width':1.2,'pointer-events':'none'})+tick(a)+tick(b)+label);
 }).join('');
}
const drawPlanBeforeDimensions=drawPlan;
drawPlan=function(source,target=$('drawing'),currentDrag=drag,standalone=false){drawPlanBeforeDimensions(source,target,currentDrag,standalone);if(!standalone)target.insertAdjacentHTML('beforeend',renderIslandDimensions(source,layout));};

function editIslandDimension(el){
 if(busy||drag||islandDrag)return;const row=islandDimensionRows[Number(el.dataset.islandDimension)];if(!row)return;
 islandDimensionEdit={...row};islandDimensionWaiting=false;$('islandDimensionApply').disabled=false;
 $('islandDimensionValue').value=Number(row.distance.toFixed(6));$('islandDimensionError').textContent='';
 $('islandDimensionDescription').textContent=({body:'Cabinet body to cabinet body',countertop:'Countertop edge to countertop edge',wall:'Island cabinet body to wall face'})[row.basis]+'. The entire island moves; its size and angle stay unchanged.';
 dimensionDialog.showModal();$('islandDimensionValue').focus();$('islandDimensionValue').select();
}
$('drawing').addEventListener('click',e=>{const el=e.target.closest('[data-island-dimension]');if(el){e.stopPropagation();editIslandDimension(el);}});
$('drawing').addEventListener('keydown',e=>{const el=e.target.closest('[data-island-dimension]');if(el&&['Enter',' '].includes(e.key)){e.preventDefault();editIslandDimension(el);}});
$('islandDimensionCancel').onclick=()=>{if(!islandDimensionWaiting)dimensionDialog.close();};
dimensionDialog.addEventListener('cancel',e=>{if(islandDimensionWaiting)e.preventDefault();});
$('islandDimensionForm').onsubmit=e=>{
 e.preventDefault();if(busy||!islandDimensionEdit)return;
 if(!window.sketchup?.command){$('islandDimensionError').textContent='Open from SketchUp to move the island.';return;}
 const distance=Number($('islandDimensionValue').value);if(!Number.isFinite(distance)||distance<0||distance>1200){$('islandDimensionError').textContent='Enter a distance between 0 and 1200 inches.';return;}
 const m=islandDimensionEdit;islandDimensionWaiting=true;$('islandDimensionApply').disabled=true;pending(true);
 sendCommands([{type:'set_island_dimension',payload:{side:m.side,basis:m.basis,target_id:m.target_id,measured_distance:m.distance,distance}}]);
};
const receiveBeforeDimensions=window.receiveKitchen;window.receiveKitchen=function(data){receiveBeforeDimensions(data);if(islandDimensionWaiting){islandDimensionWaiting=false;$('islandDimensionApply').disabled=false;if(data.error)$('islandDimensionError').textContent=data.error;else dimensionDialog.close();}};
const islandSettingsDialog=document.createElement('details');islandSettingsDialog.id='islandSettingsDialog';islandSettingsDialog.style.cssText='margin-bottom:14px;border:1px solid #dde3dc;border-radius:7px;padding:9px';
islandSettingsDialog.innerHTML='<summary style="cursor:pointer;font-weight:600">Island settings</summary><div style="margin-top:10px"><label style="display:flex;align-items:center;gap:8px"><input id="islandMatchKitchen" type="checkbox" style="width:auto">Follow kitchen settings</label><label style="display:flex;align-items:center;gap:8px"><input id="islandDimensionsVisible" type="checkbox" style="width:auto">Show dimensions</label><h3 style="font-size:13px">Vertical dimension</h3><div id="verticalDimensionChoices"></div><h3 style="font-size:13px">Horizontal dimension</h3><div id="horizontalDimensionChoices"></div><p id="islandSettingsError" role="alert" style="color:#a43425"></p><div class="actions"><button type="button" class="primary" id="saveIslandSettings">Apply island settings</button></div></div>';
$('settingsForm').closest('details').after(islandSettingsDialog);let islandSettingsWaiting=false,islandStyleInitiallyMatched=false;
for(const [axis,sides] of [['vertical',['up','down']],['horizontal',['left','right']]])for(const side of sides){
 const label=document.createElement('label');label.style.cssText='display:flex;align-items:center;gap:8px';label.innerHTML='<input type="checkbox" data-dimension-axis="'+axis+'" value="'+side+'" style="width:auto">'+({up:'Top',down:'Bottom',left:'Left',right:'Right'})[side];$(axis+'DimensionChoices').append(label);
 label.firstChild.onchange=()=>{for(const input of islandSettingsDialog.querySelectorAll('[data-dimension-axis="'+axis+'"]'))input.checked=input.value===side;};
}
function fillIslandSettings(){if(busy)return;const p=kitchenSettings.island_dimensions||{},rows=KitchenDimensions.automatic(cabinets,houseContext.items||[],p);const v=p.vertical||rows.find(m=>['up','down'].includes(m.side))?.side||'up',h=p.horizontal||rows.find(m=>['left','right'].includes(m.side))?.side||'left';for(const input of islandSettingsDialog.querySelectorAll('[data-dimension-axis]'))input.checked=input.value===(input.dataset.dimensionAxis==='vertical'?v:h);const islandCabinets=cabinets.filter(c=>wallOf(c)==='I'&&!isAppliance(c));islandStyleInitiallyMatched=islandCabinets.length>0&&islandCabinets.every(c=>Object.keys(KitchenAppearance.overrides(c)).length===0);$('islandMatchKitchen').checked=islandStyleInitiallyMatched;$('islandDimensionsVisible').checked=p.visible!==false;$('islandSettingsError').textContent='';$('saveIslandSettings').disabled=!cabinets.some(c=>wallOf(c)==='I');};
islandSettingsDialog.addEventListener('toggle',()=>{if(islandSettingsDialog.open)fillIslandSettings();});
$('saveIslandSettings').onclick=()=>{if(busy)return;if(!window.sketchup?.command){$('islandSettingsError').textContent='Open from SketchUp to save.';return;}const vertical=islandSettingsDialog.querySelector('[data-dimension-axis="vertical"]:checked')?.value,horizontal=islandSettingsDialog.querySelector('[data-dimension-axis="horizontal"]:checked')?.value;islandSettingsWaiting=true;$('saveIslandSettings').disabled=true;pending(true);const commands=[{type:'set_island_dimension_directions',payload:{vertical,horizontal,visible:$('islandDimensionsVisible').checked}}];if($('islandMatchKitchen').checked!==islandStyleInitiallyMatched)commands.push({type:'set_island_style_match',payload:{enabled:$('islandMatchKitchen').checked}});sendCommands(commands);};
const receiveBeforeIslandSettings=window.receiveKitchen;
window.receiveKitchen=function(data){receiveBeforeIslandSettings(data);if(!islandSettingsWaiting){fillIslandSettings();return;}islandSettingsWaiting=false;$('saveIslandSettings').disabled=false;if(data.error)$('islandSettingsError').textContent=data.error;else fillIslandSettings();};
