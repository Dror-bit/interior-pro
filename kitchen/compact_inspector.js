// Dimensions only; plan placement remains authoritative.
const cabinetSizePanel=document.createElement('section');cabinetSizePanel.id='cabinetSizePanel';
cabinetSizePanel.innerHTML='<h2>Cabinet size</h2><div class="fields" id="cabinetSizeFields"></div><label id="upperCounterClearanceLabel" hidden>Height above countertop (in)<input id="upperCounterClearance" type="number" min="0" max="120" step="any" form="form"></label><p id="upperCounterClearanceNote" class="tiny" hidden></p>';
$('cabinetControls').prepend(cabinetSizePanel);
for(const id of ['preset','width','height','depth','wall','x','z']){
 const input=$(id);input.setAttribute('form','form');const label=input.closest('label');$('cabinetSizeFields').append(label);
 if(['wall','x','z'].includes(id)){label.hidden=true;label.style.display='none';}
}
// Retain internal coordinates for existing model data and plan controls.
orientationPanel.hidden=true;orientationPanel.style.display='none';
function upperCounterReference(c,items){
 const kinds=['doors','drawers','sink','dishwasher','corner','corner_base','corner_lazy'];
 const bases=items.filter(b=>b.id!==c.id&&!b.surround_for&&kinds.includes(b.kind)&&KitchenPlacement.overlap({...c,z:0,height:1},{...b,z:0,height:1}));
 return bases.length?{z:Math.max(...bases.map(b=>(b.z||0)+b.height+(kitchenSettings.countertop_thickness??1.5))),actual:true}:{z:36,actual:false};
}
let upperReference=36;
function fillUpperClearance(){
 const show=!!selected&&['wall','corner_upper'].includes(selected.kind)&&!selected.surround_for&&!selected.appliance;
 const label=$('upperCounterClearanceLabel'),note=$('upperCounterClearanceNote');label.hidden=note.hidden=!show;label.style.display=show?'block':'none';note.style.display=show?'block':'none';$('upperCounterClearance').disabled=!show;
 if(show){const ref=upperCounterReference(selected,cabinets);upperReference=ref.z;$('upperCounterClearance').value=Math.round((selected.z-ref.z)*8)/8;note.textContent=ref.actual?'Measured from the countertop below to the cabinet bottom.':'No countertop below: using a standard 36 in countertop height.';}
}
const fillBeforeCompact=fill;fill=function(){const result=fillBeforeCompact.apply(this,arguments);fillUpperClearance();return result;};
$('upperCounterClearance').addEventListener('input',()=>{const input=$('upperCounterClearance');if(input.disabled||input.value==='')return;const gap=Number(input.value);if(Number.isFinite(gap)&&gap>=0){$('z').value=upperReference+gap;refreshCabinetPreview();}});
dimsTitle.remove();$('apply').hidden=true;fillUpperClearance();

// The waterfall belongs to the selected cabinet; its material remains kitchen-wide.
const waterfallLabel=document.createElement('label');waterfallLabel.textContent='Countertop waterfall';
const waterfallInput=document.createElement('select');waterfallInput.innerHTML='<option value="none">None</option><option value="left">Left exposed side</option><option value="right">Right exposed side</option><option value="both">Both exposed sides</option>';waterfallLabel.append(waterfallInput);cabinetSizePanel.append(waterfallLabel);
const beforeWaterfallFill=fill;fill=function(){const r=beforeWaterfallFill.apply(this,arguments);waterfallLabel.hidden=!selected||!['doors','drawers','sink','dishwasher','corner_base','corner_lazy'].includes(selected.kind);waterfallInput.value=selected?.waterfall||'none';return r;};
const beforeWaterfallDraft=cabinetDraft;cabinetDraft=function(){const c=beforeWaterfallDraft.apply(this,arguments);return waterfallLabel.hidden?c:{...c,waterfall:waterfallInput.value};};

const lightingPanel=document.createElement('section');lightingPanel.id='cabinetLightingPanel';lightingPanel.innerHTML='<h2>Shelves and lighting</h2><label id="cabinetShelfCountLabel">Glass cabinet shelves<select id="cabinetShelfCount"><option value="2">2</option><option value="3">3</option></select></label><label><input id="cabinetUnderLight" type="checkbox" style="width:auto"> Under-cabinet lighting</label><label id="cabinetShelfLightLabel"><input id="cabinetShelfLight" type="checkbox" style="width:auto"> Lighting under shelves</label>';cabinetSizePanel.after(lightingPanel);
const beforeLightFill=fill;fill=function(){const r=beforeLightFill.apply(this,arguments);lightingPanel.hidden=!selected||!!selected.appliance||!!selected.surround_for||!['wall','tall','doors','corner_upper'].includes(selected.kind);$('cabinetShelfCountLabel').hidden=$('cabinetShelfLightLabel').hidden=selected?.style!=='glass';$('cabinetUnderLight').closest('label').hidden=!['wall','corner_upper'].includes(selected?.kind)||!!selected?.appliance_garage;$('cabinetShelfCount').value=selected?.shelf_count??3;$('cabinetUnderLight').checked=selected?.under_lighting===true;$('cabinetShelfLight').checked=selected?.shelf_lighting===true;return r;};
const beforeLightDraft=cabinetDraft;cabinetDraft=function(){const c=beforeLightDraft.apply(this,arguments);return lightingPanel.hidden?c:{...c,shelf_count:Number($('cabinetShelfCount').value),under_lighting:$('cabinetUnderLight').checked,shelf_lighting:$('cabinetShelfLight').checked};};
