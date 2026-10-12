/* Explicit per-cabinet links, separate from resolved color/handle controls. */
for(const [field,label] of [['finish','Use kitchen color'],['handle','Use kitchen handles']]){
  const node=document.createElement('label');node.dataset.cabinetField='';node.className='tiny';
  node.innerHTML=`<input type="checkbox" id="inherit_${field}" style="width:auto;display:inline;margin-right:7px">${label}`;
  $(field).parentElement.before(node);
  $(`inherit_${field}`).addEventListener('change',()=>{syncAppearanceControls();refreshCabinetPreview();});
}
function appearanceDraft(d){
  if(!d||isAppliance(d))return d;
  const o={};for(const field of ['finish','handle'])if(!$(`inherit_${field}`).checked)o[field]=$(field).value;
  return KitchenAppearance.resolve({...d,appearance_overrides:o},kitchenSettings);
}
function syncAppearanceControls(){
  if(!selected)return;
  const d=appearanceDraft({...selected,finish:$('finish').value,handle:$('handle').value});
  for(const field of ['finish','handle']){$(field).value=d[field];$(field).disabled=$(`inherit_${field}`).checked||(field==='handle'&&plainPanel(selected));}
  $('inherit_handle').parentElement.hidden=!selected||isAppliance(selected)||plainPanel(selected);
  $('inherit_finish').parentElement.hidden=!selected||isAppliance(selected);
}
const appearanceFill=fill;
fill=function(){appearanceFill();const o=selected?KitchenAppearance.overrides(selected):{};for(const field of ['finish','handle'])$(`inherit_${field}`).checked=!Object.hasOwn(o,field);syncAppearanceControls();refreshCabinetPreview();};
const appearanceCabinetDraft=cabinetDraft;
cabinetDraft=function(){return appearanceDraft(appearanceCabinetDraft());};
const appearanceSend=send;
send=function(name,...args){if(name==='apply'){const d=JSON.parse(args[0]);args[0]=JSON.stringify(cabinets.some(c=>c.id===d.id)?appearanceDraft(d):KitchenAppearance.resolve({...d,appearance_overrides:{}},kitchenSettings));}appearanceSend(name,...args);};
for(const [id,text] of [['global_finish','Default · Ivory'],['global_handle_type','Default · Bar'],['global_handle_color','Default · Brass']])$(id).querySelector('option[value=""]').textContent=text;
