const CabinetSelection={ids:new Set(),multiple:false,pointer:null};
const selectionTools=document.createElement('section');selectionTools.id='selectionTools';selectionTools.style.cssText='padding:12px 0;border-bottom:1px solid #dde3dc;margin-bottom:14px';
const mirrorIcon=axis=>'<svg width="25" height="25" viewBox="0 0 24 24" aria-hidden="true"><g'+(axis==='y'?' transform="rotate(90 12 12)"':'')+'><path d="M12 2V22" fill="none" stroke="currentColor" stroke-width="1.4" stroke-dasharray="2 2"/><path d="M3 18L9 6V18Z" fill="currentColor"/><path d="M21 18L15 6V18Z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></g></svg>';
selectionTools.innerHTML='<h2>Selection tools</h2><button type="button" class="subtle" id="selectMultiple" aria-pressed="false" style="width:100%">Select multiple</button><div style="display:flex;gap:7px;margin-top:8px"><button type="button" class="subtle" id="flipSelectionX" title="Flip left / right" aria-label="Flip selected cabinets left / right" style="flex:1;display:grid;justify-items:center;gap:3px">'+mirrorIcon('x')+'<span>Flip L / R</span></button><button type="button" class="subtle" id="flipSelectionY" title="Flip front / back" aria-label="Flip selected cabinets front / back" style="flex:1;display:grid;justify-items:center;gap:3px">'+mirrorIcon('y')+'<span>Flip F / B</span></button></div><p id="multiSelectionHint" class="tiny">Ctrl / Shift + click to select several cabinets.</p>';
$('selection').before(selectionTools);
const multiStyle=document.createElement('style');multiStyle.textContent='.cab.multi-selected>polygon,.cab.multi-selected .outline{stroke:#16866b!important;stroke-width:3!important}.cab.multi-selected>polygon{fill-opacity:0.8}#selectMultiple[aria-pressed="true"]{background:#e1eee4;border-color:#315f4f;color:#315f4f}';document.head.append(multiStyle);
function refreshCabinetSelection(){
 const existing=new Set(cabinets.map(c=>c.id));CabinetSelection.ids=new Set([...CabinetSelection.ids].filter(id=>existing.has(id)));
 const count=CabinetSelection.ids.size;
 for(const el of $('drawing').querySelectorAll('.cab')){const on=CabinetSelection.ids.has(el.dataset.id);el.classList.toggle('multi-selected',on);el.setAttribute('aria-selected',String(on));}
 const blocked=busy||!count||cabinets.some(c=>CabinetSelection.ids.has(c.id)&&KitchenPlacement.corner(c));
 $('flipSelectionX').disabled=blocked;$('flipSelectionY').disabled=blocked;$('selectMultiple').disabled=busy;
 $('selectMultiple').setAttribute('aria-pressed',String(CabinetSelection.multiple));
 $('multiSelectionHint').textContent=count>1?`${count} selected · Flip mirrors each cabinet in place. One Ctrl+Z undoes all.`:CabinetSelection.multiple?'Click cabinets to add or remove them from the selection.':'Ctrl / Shift + click to select several cabinets.';
 if(count>1)$('selection').textContent=count+' cabinets selected';
 $('form').hidden=count>1;$('openCabinet').disabled=busy||count!==1;$('remove').disabled=busy||count!==1;$('apply').disabled=busy||count!==1;
 const heading=$('form').previousElementSibling;if(heading?.tagName==='H2')heading.hidden=count>1;
}
const chooseBeforeMultiSelection=choose;
choose=function(id){CabinetSelection.ids=new Set(cabinets.some(c=>c.id===id)?[id]:[]);chooseBeforeMultiSelection(id);refreshCabinetSelection();};
const drawBeforeMultiSelection=draw;
draw=function(...args){drawBeforeMultiSelection(...args);if(!args[0])refreshCabinetSelection();};
const pendingBeforeMultiSelection=pending;
pending=function(value){pendingBeforeMultiSelection(value);refreshCabinetSelection();};
function toggleCabinetSelection(id){
 if(CabinetSelection.ids.has(id))CabinetSelection.ids.delete(id);else CabinetSelection.ids.add(id);
 selected=cabinets.find(c=>c.id===(CabinetSelection.ids.has(id)?id:[...CabinetSelection.ids].at(-1)))||null;
 if(selected){activeWall=wallOf(selected);$('active_wall').value=activeWall;}fill();draw();
}
$('selectMultiple').onclick=()=>{CabinetSelection.multiple=!CabinetSelection.multiple;refreshCabinetSelection();};
$('drawing').addEventListener('pointerdown',e=>{
 if(e.button!==0||busy||drag||!(CabinetSelection.multiple||e.ctrlKey||e.metaKey||e.shiftKey))return;
 const cab=e.target.closest('.cab');if(!cab)return;
 e.preventDefault();e.stopImmediatePropagation();clickStart=null;completedClick=false;lastCabinetClick=null;CabinetSelection.pointer=e.pointerId;toggleCabinetSelection(cab.dataset.id);$('drawing').setAttribute('tabindex','0');$('drawing').focus({preventScroll:true});
},true);
$('drawing').addEventListener('pointerup',e=>{if(CabinetSelection.pointer!==e.pointerId)return;e.preventDefault();e.stopImmediatePropagation();CabinetSelection.pointer=null;clickStart=null;completedClick=false;lastCabinetClick=null;},true);
$('drawing').addEventListener('pointercancel',()=>{CabinetSelection.pointer=null;});
function flipCabinetSelection(axis){
 if(busy||!CabinetSelection.ids.size)return;
 if(!window.sketchup?.command){$('error').textContent='Open from SketchUp to flip cabinets.';return;}
 const chosen=cabinets.filter(c=>CabinetSelection.ids.has(c.id));if(chosen.some(c=>KitchenPlacement.corner(c))){$('error').textContent='Corner cabinets stay aligned to their wall junction. Remove them from the selection to flip.';return;}
 const commands=chosen.map(c=>({type:'flip_cabinet',payload:{id:c.id,axis}}));pending(true);sendCommands(commands);
}
$('flipSelectionX').onclick=()=>flipCabinetSelection('x');$('flipSelectionY').onclick=()=>flipCabinetSelection('y');
const receiveBeforeMultiSelection=window.receiveKitchen;
window.receiveKitchen=function(data){const keep=new Set(CabinetSelection.ids);receiveBeforeMultiSelection(data);if(data.command_results?.some(r=>r.type.startsWith('create_')))CabinetSelection.ids=new Set(selected?[selected.id]:[]);else CabinetSelection.ids=new Set([...keep].filter(id=>cabinets.some(c=>c.id===id)));if(!CabinetSelection.ids.size&&selected)CabinetSelection.ids.add(selected.id);refreshCabinetSelection();};
$('active_wall').addEventListener('change',()=>{CabinetSelection.ids=new Set(selected?[selected.id]:[]);refreshCabinetSelection();});
if(selected)CabinetSelection.ids.add(selected.id);refreshCabinetSelection();
