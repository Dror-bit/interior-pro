const orientationPanel=document.createElement('section');orientationPanel.className='wide';
orientationPanel.innerHTML='<h2>Cabinet direction</h2><div class="fields"><label>Rotation °<input id="rotation" type="number" min="-360" max="360" step="1" form="form"></label><label>Depth offset ″<input id="offset_y" type="number" min="-1200" max="1200" step="0.125" form="form"></label></div><div class="actions"><button id="cabTurn90" type="button">Flip Left / Right</button><button id="cabTurn180" type="button">Flip Front / Back</button></div><div class="tiny">Rotation is around the cabinet center. Positive offset moves behind the run; negative moves forward. Save cabinet to apply. Corners follow their two runs.</div>';
$('cabinetControls').prepend(orientationPanel);fields.push('rotation','offset_y','rotation_pivot','flip_x','flip_y');for(const axis of ['x','y']){const input=document.createElement('input');input.type='checkbox';input.id='flip_'+axis;input.hidden=true;orientationPanel.append(input);}
const pivotLabel=document.createElement('label');pivotLabel.innerHTML='Rotate around corner<select id="rotation_pivot" form="form"><option value="back_left">Back left</option><option value="back_right">Back right</option><option value="front_left">Front left · door side</option><option value="front_right">Front right · door side</option><option value="center">Center · previous setting</option></select>';
orientationPanel.querySelector('h2').after(pivotLabel);
orientationPanel.querySelector('.tiny').textContent='The selected corner stays fixed while rotating. Front means the door side. Positive depth offset moves behind the run. Save cabinet to apply.';
let previousPivot='back_left';
const fillBeforeOrientation=fill;
fill=function(){fillBeforeOrientation();$('rotation').value=selected?.rotation||0;$('offset_y').value=selected?.offset_y||0;previousPivot=selected?.rotation_pivot||((selected?.rotation||0)!==0?'center':'back_left');$('rotation_pivot').value=previousPivot;orientationPanel.hidden=!selected||KitchenPlacement.corner(selected);};
$('rotation_pivot').addEventListener('change',()=>{
 if(!selected)return;
 const draft=cabinetDraft(),old=KitchenPlacement.cabinetPivot({...draft,rotation_pivot:previousPivot}),next=KitchenPlacement.cabinetPivot(draft);
 const delta=[old[0]-next[0],old[1]-next[1]],rot=KitchenPlacement.rotate(...delta,draft.rotation||0);
 $('x').value=Math.round((draft.x+delta[0]-rot[0])*1000000)/1000000;
 $('offset_y').value=Math.round(((draft.offset_y||0)+delta[1]-rot[1])*1000000)/1000000;
 previousPivot=draft.rotation_pivot;refreshCabinetPreview();
});
for(const [id,axis] of [['cabTurn90','x'],['cabTurn180','y']])$(id).onclick=()=>{if(busy)return;const input=$('flip_'+axis);input.checked=!input.checked;refreshCabinetPreview();};
const clearancePanel=document.createElement('section');
clearancePanel.innerHTML='<h2>Island clearance</h2><label>From cabinet fronts<select id="clearanceRun"><option value="A">Run A</option><option value="B">Run B · perpendicular</option></select></label><label>Clear distance ″<input id="clearanceDistance" type="number" min="0" max="1200" step="0.125" value="42"></label><button id="applyClearance" type="button" class="subtle">Set distance</button><p class="tiny">Measured perpendicular to the run, between cabinet bodies, including the rotated island footprint. Excludes handles and countertop overhang.</p><div id="clearanceCurrent" class="tiny"></div>';
islandControls.append(clearancePanel);
function currentClearance(run){
 const islands=cabinets.filter(c=>wallOf(c)==='I');if(!islands.length)return null;
 const peers=cabinets.filter(c=>wallOf(c)===run&&c.z<Math.max(...islands.map(d=>d.z+d.height))&&c.z+c.height>Math.min(...islands.map(d=>d.z)));if(!peers.length)return null;
 const local=points=>points.map(p=>KitchenPointPlacement.localPoint(p,KitchenPlacement.pose));
 const ip=local(islands.flatMap(c=>KitchenPlacement.polygon(c))),rp=local(peers.flatMap(c=>KitchenPlacement.polygon(c)));
 return run==='A'?Math.min(...rp.map(p=>p[1]))-Math.max(...ip.map(p=>p[1])):Math.min(...ip.map(p=>p[0]))-Math.max(...rp.map(p=>p[0]));
}
function showClearance(){const d=currentClearance($('clearanceRun').value);$('clearanceCurrent').textContent=d===null?'Add island and run cabinets to measure.':'Current perpendicular clearance: '+fmt(d);}
$('clearanceRun').onchange=showClearance;
$('applyClearance').onclick=()=>{if(busy)return;const distance=Number($('clearanceDistance').value);if(!Number.isFinite(distance)||distance<0||distance>1200){$('error').textContent='Enter a distance between 0 and 1200 inches.';return;}if(!window.sketchup?.command){$('error').textContent='Open from SketchUp to set clearance.';return;}pending(true);sendCommands([{type:'set_island_clearance',payload:{run:$('clearanceRun').value,distance}}]);};
const receiveBeforeOrientation=window.receiveKitchen;window.receiveKitchen=function(data){receiveBeforeOrientation(data);showClearance();};
