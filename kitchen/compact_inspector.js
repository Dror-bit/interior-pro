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
 return bases.length?{z:Math.max(...bases.map(b=>(b.z||0)+b.height+1.5)),actual:true}:{z:36,actual:false};
}
let upperReference=36;
function fillUpperClearance(){
 const show=!!selected&&['wall','corner_upper'].includes(selected.kind)&&!selected.surround_for&&!selected.appliance;
 const label=$('upperCounterClearanceLabel'),note=$('upperCounterClearanceNote');label.hidden=note.hidden=!show;label.style.display=show?'block':'none';note.style.display=show?'block':'none';$('upperCounterClearance').disabled=!show;
 if(show){const ref=upperCounterReference(selected,cabinets);upperReference=ref.z;$('upperCounterClearance').value=Math.round((selected.z-ref.z)*1000000)/1000000;note.textContent=ref.actual?'Measured from the countertop below to the cabinet bottom.':'No countertop below: using a standard 36 in countertop height.';}
}
const fillBeforeCompact=fill;fill=function(){const result=fillBeforeCompact.apply(this,arguments);fillUpperClearance();return result;};
$('upperCounterClearance').addEventListener('input',()=>{const input=$('upperCounterClearance');if(input.disabled||input.value==='')return;const gap=Number(input.value);if(Number.isFinite(gap)&&gap>=0){$('z').value=upperReference+gap;refreshCabinetPreview();}});
dimsTitle.remove();$('apply').hidden=true;fillUpperClearance();
