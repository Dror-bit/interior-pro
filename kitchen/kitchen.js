/* All dimensions are inches, matching SketchUp and Interior Pro. */
const $=id=>document.getElementById(id);
const names={doors:'Doors',drawers:'Drawers',sink:'Sink base',wall:'Wall',tall:'Tall',oven_tower:'Wall oven cabinet',micro_tower:'Oven + microwave',fridge_surround:'Fridge surround',fridge:'Refrigerator',oven:'Range / oven',dishwasher:'Dishwasher'};
const isAppliance=c=>c&&['fridge','oven','wall_oven','dishwasher','hood','microwave'].includes(c.kind);
names.wall_oven='Wall oven';
const applianceColors={stainless:'#b8c0c4',black:'#303538',white:'#ecede9'};
const colors={ivory:'#e8e4da',sage:'#87978b',charcoal:'#3d4549',oak:'#ba9365'};
names.hood='Range hood';names.microwave='Microwave';
Object.assign(names,{corner_base:'Base corner',corner_upper:'Upper corner',corner_lazy:'Lazy Susan corner'});
const elevated=c=>['wall','wall_oven','hood','microwave'].includes(c.kind);
names.filler='Filler';names.corner='Closed corner';
let activeWall='A';
let houseContext={items:[],level:1};
const wallOf=c=>c.wall||'A';
const plainPanel=c=>c&&['filler','corner'].includes(c.kind);
let kitchenSettings={shaker_width:2.25,shaker_inset:.25};
let editorPreview=null;
let cabinets=[],selected=null,mode='top',busy=false,drag=null,layout=null;
let dragFrameRequest=null,latestDragEvent=null;
function clearDragFrame(){if(dragFrameRequest!==null)cancelAnimationFrame(dragFrameRequest);dragFrameRequest=null;latestDragEvent=null;}
function queueDrag(e){
 if(!drag||e.pointerId!==drag.pointer)return;
 latestDragEvent={pointerId:e.pointerId,clientX:e.clientX,clientY:e.clientY};
 if(dragFrameRequest===null)dragFrameRequest=requestAnimationFrame(()=>{dragFrameRequest=null;const next=latestDragEvent;latestDragEvent=null;if(next)moveDrag(next);});
}
const fields=['wall','width','height','depth','x','z','style','handle','finish','appliance_finish','toe_height','toe_setback','handle_position','handle_offset','handle_side','appliance_width','appliance_height','appliance_bottom','microwave_height'];
let kitchenRevision=null;
function sendCommands(commands){window.sketchup.command(JSON.stringify({commands,expected_revision:kitchenRevision}));}
function send(name,...args){if(window.sketchup?.command){const commands=KitchenCommands.commandsFor(name,args);if(commands){sendCommands(commands);return;}}if(window.sketchup&&window.sketchup[name])window.sketchup[name](...args);else $('status').textContent='Preview only — open from SketchUp';}
function pending(value){busy=value;document.querySelectorAll('#apply,#remove,#applySettings,.tile').forEach(b=>b.disabled=value);}
function fillCrown(){KitchenPlacement.island={x:kitchenSettings.island_x??48,y:kitchenSettings.island_y??84,angle:kitchenSettings.island_angle??0};KitchenPlacement.pose={x:0,y:0,z:0,angle:0,level:1,...kitchenSettings.kitchen_pose};for(const [k,v] of Object.entries({crown_profile:'none',crown_height:4,crown_depth:3,crown_color:'cabinet',global_finish:'',global_handle_type:'',global_handle_color:''}))$(k).value=kitchenSettings[k]??v;}
function fillLayout(){
 $('wall').value=selected?wallOf(selected):activeWall;
 $('width').min=selected?.kind==='filler'?.5:12;
 for(const id of ['frontEditor','handleEditor'])if(plainPanel(selected)){$(id).hidden=true;$(id).querySelectorAll('input,select,button').forEach(el=>el.disabled=true);}
 $('style').disabled=!!plainPanel(selected);$('handle').disabled=!!plainPanel(selected);
 if(FrontLayouts.corner(selected||{})){$('frontEditor').hidden=true;$('frontEditor').querySelectorAll('input,select,button').forEach(el=>el.disabled=true);}
 $('x').disabled=!!selected&&KitchenPlacement.corner(selected);$('wall').disabled=$('x').disabled;
 if(FrontLayouts.corner(selected||{}))$('itemNote').textContent='';
}
document.querySelectorAll('[data-corner]').forEach(b=>b.addEventListener('click',()=>{if(busy)return;pending(true);send('corner',b.dataset.corner);}));
$('active_wall').addEventListener('change',()=>{cancelDrag();activeWall=$('active_wall').value;selected=cabinets.find(c=>wallOf(c)===activeWall)||null;fill();draw();});
$('addCorner').addEventListener('click',()=>{if(busy)return;const existing=cabinets.find(c=>['corner_base','corner_lazy'].includes(c.kind));if(existing){choose(existing.id);return;}pending(true);send('corner','corner_base');});
window.receiveKitchen=function(data){kitchenRevision=data.revision??null;const created=data.command_results?.filter(r=>r.type.startsWith('create_')).at(-1);if(created)selected={id:created.id};if(typeof cancelIslandDrag==='function')cancelIslandDrag();houseContext=data.house_context||{items:[],level:1};cancelDrag();pending(false);kitchenSettings=data.settings||{shaker_width:2.25,shaker_inset:.25};$('shaker_width').value=kitchenSettings.shaker_width;fillCrown();$('shaker_inset').value=kitchenSettings.shaker_inset;$('settingsError').textContent=data.error||'';cabinets=data.cabinets;selected=cabinets.find(c=>c.id===selected?.id)||cabinets[0]||null;fill();draw();$('error').textContent=data.error||'';$('status').textContent=data.error?'Update failed':'Kitchen ready';};
function fill(){editorPreview=null;const appliance=isAppliance(selected);document.querySelectorAll('[data-cabinet-field]').forEach(el=>el.hidden=!!appliance);$('applianceFinishField').hidden=!appliance&&!FrontLayouts.builtin(selected||{});$('apply').textContent=appliance?'Update appliance':'Update cabinet';$('itemNote').textContent=appliance?'Generic exterior model. Edit dimensions to match your chosen appliance. Dishwasher countertop adds 1½″.':'All dimensions in inches. Body height includes the toe kick; countertop adds 1½″. Exterior design only.';for(const key of fields)$(key).value=selected?(selected[key]??(key==='appliance_finish'?'stainless':'')):'';$('preset').value=selected&&[18,24,30,36,42,48].includes(selected.width)?String(selected.width):'';$('selection').textContent=selected?`${names[selected.kind]} · ${selected.width}″`:'Select a cabinet to edit';$('apply').disabled=!selected;$('remove').disabled=!selected;fillToeEditor();fillHandleEditor();fillBuiltinEditor();fillFrontEditor();fillLayout();}
function readHandleEditor(){return {handle_position:$('handle_position').value,handle_offset:Number($('handle_offset').value),handle_side:Number($('handle_side').value)};}
function fillBuiltinEditor(){
 const built=selected&&FrontLayouts.builtin(selected);$('builtinEditor').hidden=!built;
 const defaults=FrontLayouts.builtinDefaults(selected||{});
 $('builtin_preset').innerHTML='<option value="">Custom dimensions</option>'+ (selected?.kind==='fridge_surround'?[36,39,42,48]:[27,30,33,36]).map(w=>`<option value="${w}">${w}″ cabinet / ${w-1.5}″ appliance</option>`).join('');
 $('builtin_preset').value=selected&&selected.appliance_width===selected.width-1.5?String(selected.width):'';
 for(const key of ['appliance_width','appliance_height','appliance_bottom','microwave_height']){$(key).value=selected?.[key]??defaults[key];$(key).disabled=!built;}
 $('applianceBottomField').hidden=selected?.kind==='fridge_surround';$('microwaveHeightField').hidden=selected?.kind!=='micro_tower';
}
$('builtin_preset').addEventListener('change',()=>{const w=Number($('builtin_preset').value);if(w){$('width').value=w;$('appliance_width').value=w-1.5;$('preset').value=String(w);}});
for(const key of ['width','appliance_width','appliance_height','appliance_bottom','microwave_height'])$(key).addEventListener('input',()=>{$('builtin_preset').value='';});
function builtinDrawing(row,c,x,y,w,s){
 const aw=row.width*s,h=row.height*s,ax=x+(w-aw)/2,metal=applianceColors[c.appliance_finish||'stainless'],glass='#18262d';
 let out=rect(x,y,w,h,colors[c.finish])+rect(ax,y,aw,h,metal);
 if(row.device==='fridge'){
  out+=line(ax,y+h*.7,ax+aw,y+h*.7)+line(ax+aw/2,y,ax+aw/2,y+h*.7);
  for(const offset of [-1.25,1.25])out+=line(ax+aw/2+offset*s,y+h*.42,ax+aw/2+offset*s,y+h*.66,'#e9edee',{'stroke-width':2});
  out+=line(ax+aw*.2,y+h*.75,ax+aw*.8,y+h*.75,'#e9edee',{'stroke-width':2});
 }else{
  out+=rect(ax+aw*.08,y+h*.2,aw*.84,h*.68,glass)+rect(ax+aw*.38,y+h*.07,aw*.24,h*.05,glass);
  out+=row.device==='microwave'?line(ax+aw*.89,y+h*.3,ax+aw*.89,y+h*.78,'#e9edee',{'stroke-width':2}):line(ax+aw*.12,y+h*.24,ax+aw*.88,y+h*.24,'#e9edee',{'stroke-width':2});
 }
 return out;
}
function fillHandleEditor(){
 const rail=['shaker','glass'].includes(selected?.style)?kitchenSettings.shaker_width:2;
 $('handle_position').value=selected?.handle_position??'auto';$('handle_offset').value=selected?.handle_offset??rail;$('handle_side').value=selected?.handle_side??rail/2;
 document.querySelectorAll('#handleEditor input,#handleEditor select').forEach(el=>el.disabled=!selected||!!isAppliance(selected)||selected.handle==='none');
}
function handleLayout(c,w,h,horizontal,left,rowIndex=0){
 if(c.pullout){horizontal=true;c={...c,handle_position:c.pullout.type==='waste'&&rowIndex===0?'center':'top'};}
 let pos=c.handle_position??'auto';const auto=pos==='auto';if(auto)pos=horizontal||c.kind==='tall'?'center':['wall','corner_upper'].includes(c.kind)||(FrontLayouts.builtin(c)&&rowIndex===0)?'bottom':'top';
 const rail=['shaker','glass'].includes(c.style)?kitchenSettings.shaker_width:2;
 const gap=auto?rail:(c.handle_offset??rail),edge=auto?rail/2:(c.handle_side??rail/2),len=horizontal?Math.min(5,w-4):Math.min(5,h-2);
 const hx=horizontal?(w-len)/2:(left?w-edge:edge)-.16;
 const hz=horizontal?(pos==='top'?h-gap-.16:pos==='bottom'?gap-.16:(h-.32)/2):(pos==='top'?h-gap-len+.5:pos==='bottom'?gap-.5:(h-len)/2);
 return [hx,hz,horizontal?len:.32,horizontal?.32:len];
}
for(const id of ['handle_position','handle_offset','handle_side'])$(id).addEventListener('input',()=>{
 if(id!=='handle_position'&&$('handle_position').value==='auto')$('handle_position').value=selected?.kind==='tall'?'center':['wall','corner_upper'].includes(selected?.kind)||FrontLayouts.builtin(selected||{})?'bottom':'top';
 frontPreview(true);
});
function checkHandles(c){
 if(isAppliance(c)||c.handle==='none')return;
 for(const [rowIndex,row] of FrontLayouts.rows(c).entries()){
  if(row.kind==='appliance'||(c.kind==='sink'&&row.kind==='drawer'))continue;
  const n=row.kind==='drawer'?1:row.doors,w=FrontLayouts.corner(c)?c.width-c.depth-.25:(c.width-.125*(n+1))/n;
  const [x,z,hw,hh]=handleLayout(c,w,row.height,row.kind==='drawer',true,rowIndex);
  if(![x,z,hw,hh].every(Number.isFinite)||x<0||z<0||x+hw>w||z+hh>row.height)throw Error('Handle falls outside the front. Reduce the edge distances.');
 }
}
function readToeEditor(){return {toe_height:['wall','fridge_surround','corner_upper'].includes(selected?.kind)?0:Number($('toe_height').value),toe_setback:Number($('toe_setback').value)};}
function validateToe(d){
 if(!Number.isFinite(d.toe_height)||d.toe_height<0||d.toe_height>12||d.height-d.toe_height<8.25)throw Error('Toe kick height must be 0–12 inches and leave at least 8 inches for fronts');
 if(!Number.isFinite(d.toe_setback)||d.toe_setback<0||d.toe_setback>d.depth-.6)throw Error('Toe kick setback must fit inside the cabinet depth');
}
function checkShaker(c,s=kitchenSettings){
 if(!['shaker','glass'].includes(c.style)||isAppliance(c))return;
 for(const row of FrontLayouts.rows(c)){
  if(row.kind==='appliance')continue;
  const n=row.kind==='drawer'?1:row.doors,width=FrontLayouts.corner(c)?c.width-c.depth-.25:(c.width-.125*(n+1))/n;
  if(Math.min(width,row.height)<2*s.shaker_width+.25)throw Error(`Shaker frame too wide for ${names[c.kind]} at X=${c.x}. Reduce frame width or enlarge the front.`);
 }
}
$('settingsForm').addEventListener('submit',e=>{
 e.preventDefault();if(busy)return;
 const s={shaker_width:Number($('shaker_width').value),shaker_inset:Number($('shaker_inset').value)};
 Object.assign(s,{crown_profile:$('crown_profile').value,crown_height:Number($('crown_height').value),crown_depth:Number($('crown_depth').value),crown_color:$('crown_color').value});
 Object.assign(s,{global_finish:$('global_finish').value,global_handle_type:$('global_handle_type').value,global_handle_color:$('global_handle_color').value});
 try{cabinets.forEach(c=>checkShaker(c,s));}catch(error){$('settingsError').textContent=error.message;return;}
 pending(true);send('settings',JSON.stringify(s));
});
function fillToeEditor(){
 const hidden=!selected||isAppliance(selected)||['wall','fridge_surround','corner_upper'].includes(selected.kind);
 $('toeEditor').hidden=hidden;
 $('toe_height').value=selected?FrontLayouts.toe(selected):4;
 $('toe_setback').value=selected?.toe_setback??3;
 $('toe_height').disabled=hidden;$('toe_setback').disabled=hidden;
}
$('toe_height').addEventListener('input',()=>{
 if($('front_layout').value==='drawers')$('balanceDrawers').click();
 else frontPreview(true);
});
$('toe_setback').addEventListener('input',()=>frontPreview(true));
$('depth').addEventListener('input',()=>frontPreview(true));
function fillFrontEditor(){
 $('frontEditor').hidden=!selected||isAppliance(selected)||FrontLayouts.builtin(selected);
 document.querySelectorAll('#frontEditor input,#frontEditor select,#frontEditor button').forEach(el=>el.disabled=!selected||!!isAppliance(selected));
 if(!selected||isAppliance(selected)||FrontLayouts.builtin(selected))return;
 $('front_layout').value=FrontLayouts.infer(selected);
 const heights=FrontLayouts.heights(selected);
 $('drawer_count').value=String(heights.length);
 renderDrawerFields(heights);
 frontPreview(false);
}
function readFrontEditor(){
 const front_layout=$('front_layout').value;
 const drawer_heights=[...document.querySelectorAll('[data-drawer-height]')].map(el=>Number(el.value));
 return {front_layout,drawer_heights:['single','double'].includes(front_layout)?[]:drawer_heights};
}
function renderDrawerFields(heights){
 const kind=$('front_layout').value,drawers=kind==='drawers',has=drawers||kind.startsWith('combo');
 $('drawerControls').hidden=!has;$('drawerCountField').hidden=!drawers;$('balanceDrawers').hidden=!drawers;
 $('drawerHeights').innerHTML=has?heights.map((h,i)=>`<label>${drawers?'Drawer '+(i+1):'Top drawer'} ″${i===0?' · top':''}<input type="number" data-drawer-height="${i}" aria-label="Drawer ${i+1} height" min="3" step="any" value="${Math.round(h*1000)/1000}" required></label>`).join(''):'';
 document.querySelectorAll('[data-drawer-height]').forEach(el=>el.addEventListener('input',()=>frontPreview(true)));
}
function frontPreview(showDraft){
 if(!selected||isAppliance(selected)||plainPanel(selected))return;
 const d={...selected,height:Number($('height').value),depth:Number($('depth').value),...readToeEditor(),...readFrontEditor(),...readHandleEditor()};
 const available=FrontLayouts.available(d),kind=d.front_layout;
 let message='⅛″ reveals · '+(Math.round(available*1000)/1000)+'″ available';
 try{
  if(!Number.isFinite(d.height)||d.height<(d.kind==='wall'?12:18)||d.height>96)throw Error('Enter a valid body height');
  validateToe(d);checkHandles(d);const rows=FrontLayouts.rows(d);
  if(kind.startsWith('combo'))message+=' · Doors '+(Math.round(rows[1].height*1000)/1000)+'″';
  $('frontSummary').style.color='';$('frontSummary').textContent=message;
  if(showDraft){editorPreview=d;$('status').textContent='Front preview · Update cabinet to save';}
 }catch(error){
  editorPreview=null;$('frontSummary').style.color='#a43425';
  const used=d.drawer_heights.reduce((a,b)=>a+b,0)+.125*(d.drawer_heights.length-1);
  $('frontSummary').textContent=message+' · '+(kind==='drawers'?`${Math.round((available-used)*1000)/1000}″ remaining. `:'')+error.message;
 }
 if(showDraft)draw();
}
$('front_layout').addEventListener('change',()=>{
 const kind=$('front_layout').value,d={...selected,height:Number($('height').value),depth:Number($('depth').value),...readToeEditor()};
 let heights=[5.875];
 if(kind==='drawers'){const n=3,total=FrontLayouts.available(d)-.125*(n-1);heights=[.24,.36,.4].map(r=>Math.round(total*r*1000)/1000);heights[2]=total-heights[0]-heights[1];$('drawer_count').value='3';}
 renderDrawerFields(heights);frontPreview(true);
});
$('drawer_count').addEventListener('change',()=>{
 const n=Number($('drawer_count').value),total=FrontLayouts.available({...selected,height:Number($('height').value),depth:Number($('depth').value),...readToeEditor()})-.125*(n-1);
 const h=Math.floor(total/n*8)/8,heights=Array(n).fill(h);heights[n-1]=total-h*(n-1);
 renderDrawerFields(heights);frontPreview(true);
});
$('balanceDrawers').addEventListener('click',()=>{
 const inputs=[...document.querySelectorAll('[data-drawer-height]')];if(!inputs.length)return;
 const total=FrontLayouts.available({...selected,height:Number($('height').value),depth:Number($('depth').value),...readToeEditor()})-.125*(inputs.length-1);
 const remaining=total-inputs.slice(0,-1).reduce((a,el)=>a+Number(el.value),0);
 inputs[inputs.length-1].value=Math.round(remaining*1000)/1000;frontPreview(true);
});
$('height').addEventListener('input',()=>frontPreview(true));
function choose(id){selected=cabinets.find(c=>c.id===id);if(selected){activeWall=wallOf(selected);$('active_wall').value=activeWall;}fill();draw();}
function overlaps(c){return cabinets.some(o=>o.id!==c.id&&KitchenPlacement.overlap(c,o));}
function snapPosition(raw,c,s){
 const candidates=[{x:0,edge:0}];
 for(const o of cabinets){if(o.id===c.id||wallOf(o)!==wallOf(c))continue;candidates.push({x:o.x+o.width,edge:o.x+o.width},{x:o.x-c.width,edge:o.x},{x:o.x,edge:o.x},{x:o.x+o.width-c.width,edge:o.x+o.width});}
 const near=candidates.filter(p=>p.x>=0&&p.x<=1200&&Math.abs(p.x-raw)*s<=12).sort((a,b)=>Math.abs(a.x-raw)-Math.abs(b.x-raw));
 // Prefer an available adjacent position over an alignment inside another cabinet.
 const snapped=near.find(p=>!overlaps({...c,x:p.x}))||near[0];
 return snapped?{x:snapped.x,edge:snapped.edge}:{x:Math.round(Math.max(0,Math.min(1200,raw))*8)/8,edge:null};
}
function drawingPoint(e){const p=$('drawing').createSVGPoint();p.x=e.clientX;p.y=e.clientY;return p.matrixTransform($('drawing').getScreenCTM().inverse());}
function cancelDrag(){clearDragFrame();if(!drag)return;const id=drag.pointer;drag=null;try{if($('drawing').hasPointerCapture(id))$('drawing').releasePointerCapture(id);}catch(_){}$('drawing').classList.remove('dragging');draw();fill();}
function beginDrag(e){
 const cab=e.target.closest('.cab');if(!cab||busy||drag||e.button!==0)return;
 e.preventDefault();$('drawing').setAttribute('tabindex','0');$('drawing').focus({preventScroll:true});choose(cab.dataset.id);const p=drawingPoint(e);
 if(KitchenPlacement.corner(selected))return;
 drag={pointer:e.pointerId,start:p,original:{...selected},preview:{...selected},frame:{...layout},moved:false,edge:null,valid:true};
 try{$('drawing').setPointerCapture(e.pointerId);}catch(_){}
 $('error').textContent='';
}
function moveDrag(e){
 if(!drag||e.pointerId!==drag.pointer)return;
 const p=drawingPoint(e),vertical=mode==='front'&&elevated(drag.original);
 const along=pt=>KitchenPlacement.along(wallOf(drag.original),(pt.x-drag.frame.ox)/drag.frame.s,-(pt.y-drag.frame.base)/drag.frame.s);
 const delta=mode==='top'?(along(p)-along(drag.start))*drag.frame.s:p.x-drag.start.x;
 if(!drag.moved&&(mode==='top'?Math.hypot(p.x-drag.start.x,p.y-drag.start.y):Math.max(Math.abs(delta),vertical?Math.abs(p.y-drag.start.y):0))<3)return;
 drag.moved=true;
 if(mode==='top'){
  const world=[(p.x-drag.frame.ox)/drag.frame.s,(drag.frame.base-p.y)/drag.frame.s];
  const transfer=KitchenPlacement.transfer(cabinets,drag.original,world,drag.frame.s,drag.transferWall);
  if(transfer){
   drag.transferWall=wallOf(transfer.preview);drag.preview=transfer.preview;drag.placed=transfer.items;drag.valid=transfer.valid;
   drag.floating={...drag.preview};drag.insertion=null;drag.insertionSlot=null;drag.edge=null;
   $('drawing').classList.add('dragging');$('status').textContent=drag.valid?`Move to ${drag.transferWall==='I'?'Island':'Run '+drag.transferWall} · Release to place`:'Cabinet overlaps here · Move along the destination run';draw();return;
  }
  drag.transferWall=null;
 }
 let z=drag.original.z;
 if(vertical){
  const raw=Math.max(0,Math.min(120,z-(p.y-drag.start.y)/drag.frame.s));
  const levels=[54,drag.original.z,...cabinets.filter(c=>c.id!==drag.original.id).flatMap(c=>[c.z,c.z+c.height-drag.original.height])];
  const near=levels.filter(v=>v>=0&&v<=120&&Math.abs(v-raw)*drag.frame.s<=8).sort((a,b)=>Math.abs(a-raw)-Math.abs(b-raw));
  z=near[0]??Math.round(raw*8)/8;
 }
 const snapped=snapPosition(drag.original.x+delta/drag.frame.s,{...drag.original,z},drag.frame.s);
 drag.floating={x:drag.original.x+delta/drag.frame.s,z:vertical?drag.original.z-(p.y-drag.start.y)/drag.frame.s:drag.original.z};
 drag.preview={...drag.original,x:snapped.x,z};drag.edge=snapped.edge;
 const proposal=KitchenPlacement.plan(cabinets,drag.original,drag.preview,$('drag_mode').value,mode==='top'?along(p):(p.x-drag.frame.ox)/drag.frame.s,20/drag.frame.s,drag.insertionSlot);
 drag.insertionSlot=proposal.valid?proposal.insertionSlot:null;
 drag.insertion=proposal.insertion;
 if($('drag_mode').value==='insert')drag.edge=null;
 drag.placed=proposal.items;drag.valid=proposal.valid;
 if(drag.valid)drag.preview=drag.placed.find(c=>c.id===drag.original.id);
 $('drawing').classList.add('dragging');$('x').value=drag.preview.x;$('z').value=drag.preview.z;
 $('status').textContent=drag.valid?(drag.insertion!=null?'Insert here · Release to place':`Position: ${fmt(drag.preview.x)}${drag.edge!==null?' · Snapped to edge':''} · Release to place`):'Move the pointer to a cabinet edge to insert';
 draw();
}
function endDrag(e){
 if(!drag||e.pointerId!==drag.pointer)return;
 clearDragFrame();moveDrag(e); // Flush the final pointer position before committing.
 const result=drag;cancelDrag();
 if(!result.moved)return;
 if(!result.valid){$('error').textContent='Not enough space — cabinet position unchanged.';$('status').textContent='Placement cancelled';return;}
 if(result.transferWall){
  const c=result.preview;activeWall=c.wall;$('active_wall').value=activeWall;pending(true);send('place',JSON.stringify({positions:[{id:c.id,x:c.x,z:c.z,wall:c.wall,rotation:c.rotation,offset_y:c.offset_y}]}));return;
 }
 const changes=(result.placed||[result.preview]).filter(c=>{const old=cabinets.find(o=>o.id===c.id);return old&&(Math.abs(c.x-old.x)>.001||Math.abs(c.z-old.z)>.001);}).map(c=>({id:c.id,x:c.x,z:c.z}));
 if(!changes.length){$('status').textContent='Cabinet position unchanged';return;}
 pending(true);send('place',JSON.stringify({positions:changes}));
}
$('drawing').addEventListener('pointerdown',beginDrag);
$('drawing').addEventListener('pointermove',queueDrag);
$('drawing').addEventListener('pointerup',endDrag);
$('drawing').addEventListener('pointercancel',()=>{cancelDrag();$('status').textContent='Drag cancelled';});
window.addEventListener('keydown',e=>{if(e.key==='Escape'&&drag){cancelDrag();$('status').textContent='Drag cancelled';}});
window.addEventListener('blur',()=>cancelDrag());
function fillerReference(){
 const neighbors=cabinets.filter(c=>wallOf(c)===activeWall&&!['filler','corner','fridge','oven','wall_oven','dishwasher','hood','microwave'].includes(c.kind));
 return neighbors.find(c=>c.id===selected?.id)||neighbors.sort((a,b)=>(a.z||0)-(b.z||0)||(b.x+b.width)-(a.x+a.width))[0];
}
function add(kind){if(busy)return;if(!window.sketchup?.command){addPreview(kind);return;}pending(true);sendCommands([{type:'create_cabinet',payload:{kind,wall:activeWall,reference_id:selected?.id}}]);}
// Isolated browser mock only; native creation uses the Ruby command engine.
function addPreview(kind){if(busy)return;const glassCabinet=kind==='glass_wall';if(glassCabinet)kind='wall';const related=cabinets.filter(c=>wallOf(c)===activeWall&&(elevated({kind})?elevated(c):!elevated(c)));const x=Math.max(0,...related.map(c=>c.x+c.width));const c={id:'c-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6),width:kind==='drawers'?24:kind==='tall'?24:36,height:kind==='wall'?30:kind==='tall'?96:34.5,depth:kind==='wall'?12:24,x,z:kind==='wall'?54:0,kind,style:'shaker',finish:'ivory',handle:'brass'};c.wall=activeWall;c.finish=kitchenSettings.global_finish||c.finish;c.handle=kitchenSettings.global_handle_type==='none'?'none':kitchenSettings.global_handle_color||c.handle;if(glassCabinet)c.style='glass';if(kind==='filler')Object.assign(c,{width:3,style:'slab',handle:'none',height:fillerReference()?.height||34.5,depth:fillerReference()?.depth||24,z:fillerReference()?.z||0});if(isAppliance(c)){Object.assign(c,{fridge:{width:36,height:70,depth:30},oven:{width:30,height:36,depth:26},dishwasher:{width:24,height:34.5,depth:24},hood:{width:30,height:30,depth:20,z:66},microwave:{width:30,height:18,depth:16,z:54}}[kind],{appliance_finish:'stainless'});}if(FrontLayouts.builtin(c)){Object.assign(c,{width:kind==='fridge_surround'?39:30,height:96,depth:kind==='fridge_surround'?30:24,appliance_finish:'stainless'},FrontLayouts.builtinDefaults(c));}if(elevated(c)||activeWall==='B'){const positions=[...new Set([c.x,0,...cabinets.flatMap(o=>KitchenPlacement.polygon(o).map(p=>KitchenPlacement.along(activeWall,...p)))].filter(x=>x>=0&&x<=1200))].sort((a,b)=>a-b);const free=positions.find(px=>!overlaps({...c,x:px}));if(free===undefined){$('error').textContent='No free space on this wall. Move a cabinet or change its height.';return;}c.x=free;}if(['hood','microwave'].includes(kind)){const range=cabinets.find(o=>o.kind==='oven'&&wallOf(o)===activeWall);if(range){const px=range.x+(range.width-c.width)/2;if(px>=0&&!overlaps({...c,x:px}))c.x=px;}}selected=c;pending(true);send('apply',JSON.stringify(c));}
document.querySelectorAll('[data-kind]').forEach(b=>b.addEventListener('click',()=>add(b.dataset.kind)));
$('form').addEventListener('submit',e=>{e.preventDefault();if(!selected||busy)return;const d={...selected};for(const key of fields)d[key]=$(key).type==='checkbox'?$(key).checked:['wall','style','handle','finish','appliance_finish','handle_position','rotation_pivot'].includes(key)?$(key).value:Number($(key).value);try{if(!isAppliance(d)&&!plainPanel(d)){Object.assign(d,readFrontEditor());if(d.kind==='tall'&&window.readPantryEditor)d.pantry=readPantryEditor(d);validateToe(d);checkHandles(d);checkShaker(d);FrontLayouts.rows(d);}}catch(error){$('error').textContent=error.message;return;}pending(true);send('apply',JSON.stringify(d));});
$('preset').addEventListener('change',()=>{if($('preset').value)$('width').value=$('preset').value;});
$('width').addEventListener('input',()=>{$('preset').value='';});
$('remove').addEventListener('click',()=>{if(selected&&!busy){pending(true);send('remove',selected.id);}});
window.addEventListener('keydown',e=>{
 if(e.key.toLowerCase()!=='z'||!(e.ctrlKey||e.metaKey)||e.shiftKey||e.altKey||e.repeat||e.isComposing)return;
 const editing=el=>el instanceof Element&&(el.closest('input,textarea,select,[contenteditable]:not([contenteditable="false"])')||el.isContentEditable);
 if(editing(e.target)||editing(document.activeElement))return;
 e.preventDefault();
 if(busy||document.querySelector('dialog[open]:not(#cabinetDialog)'))return;
 if(drag){cancelDrag();return;}
 if(typeof islandDrag!=='undefined'&&islandDrag){cancelIslandDrag();return;}
 if(!window.sketchup?.undo){$('status').textContent='Open from SketchUp to undo a model action.';return;}
 pending(true);send('undo');
});
window.addEventListener('keydown',e=>{
 if(e.key!=='Delete'||e.repeat||e.isComposing||e.ctrlKey||e.altKey||e.metaKey||busy||!selected||drag)return;
 if(typeof islandDrag!=='undefined'&&islandDrag)return;
 const editing=el=>el instanceof Element&&(el.closest('input,textarea,select,[contenteditable]:not([contenteditable="false"])')||el.isContentEditable);
 if(editing(e.target)||editing(document.activeElement)||document.querySelector('dialog[open]'))return;
 e.preventDefault();$('remove').click();
});

$('refresh').addEventListener('click',()=>send('refresh'));
document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>{cancelDrag();mode=b.dataset.view;document.querySelectorAll('[data-view]').forEach(t=>t.classList.toggle('active',t===b));draw();}));
function fmt(n){const whole=Math.floor(n);const frac=Math.round((n-whole)*8);const symbols=['','⅛','¼','⅜','½','⅝','¾','⅞'];return frac===8?`${whole+1}″`:`${whole||!frac?whole:''}${symbols[frac]}″`;}
function svg(tag,attrs,children=''){return `<${tag} ${Object.entries(attrs).map(([k,v])=>`${k}="${v}"`).join(' ')}>${children}</${tag}>`;}
function rect(x,y,w,h,fill,stroke='#6d756b',extra={}){return svg('rect',{x,y,width:w,height:h,fill,stroke,'stroke-width':1,...extra});}
function line(x1,y1,x2,y2,stroke='#7d897e',extra={}){return svg('line',{x1,y1,x2,y2,stroke,'stroke-width':1,...extra});}
function text(x,y,label,attrs={}){return svg('text',{x,y,fill:'#4e6255','font-size':15,'text-anchor':'middle','font-family':'Segoe UI,Arial',direction:'ltr',...attrs},label);}
function dimension(x1,x2,y,label,id){return svg('g',{class:'dim','data-dim':id||''},line(x1,y,x2,y)+line(x1,y-7,x1,y+7)+line(x2,y-7,x2,y+7)+rect((x1+x2)/2-30,y-12,60,23,'#fafbf8','none')+text((x1+x2)/2,y+5,label));}
function cornerDrawing(c,x,base,s,active){
 const y=base-(c.z+c.height)*s,w=c.width*s,h=c.height*s,arm=c.depth*s,r=kitchenSettings.shaker_width*s,fh=(c.height-FrontLayouts.toe(c)-.25)*s,fx=x+arm+.125*s,fy=y+.125*s,fw=w-arm-.25*s,fill=colors[c.finish];
 let out=rect(x,y,w,h,fill,active?'#315f4f':'#6d756b')+rect(x,y,arm,h,'#8b9992','#6d756b',{'fill-opacity':.22});
 out+=rect(fx,fy,fw,fh,fill);
 if(['shaker','glass'].includes(c.style))out+=rect(fx+r,fy+r,fw-2*r,fh-2*r,c.style==='glass'?'#afdae2':fill,'#8a9184');
 if(c.handle!=='none'){const hp=handleLayout(c,fw/s,fh/s,false,activeWall==='B');out+=rect(fx+hp[0]*s,fy+fh-(hp[1]+hp[3])*s,hp[2]*s,hp[3]*s,c.handle==='brass'?'#a38344':'#232b26');}
 out+=text(x+arm/2,y+h/2,'Corner',{'font-size':11});return out;
}
function overheadDrawing(c,x,base,s,active){
 const w=c.width*s,h=c.height*s,y=base-(c.z+c.height)*s,metal=applianceColors[c.appliance_finish||'stainless'];let out='';
 if(c.kind==='hood'){
  out+=rect(x+w*.35,y,w*.3,h*.65,metal);
  out+=svg('polygon',{points:`${x+w*.35},${y+h*.65} ${x+w*.65},${y+h*.65} ${x+w},${y+h-2*s} ${x},${y+h-2*s}`,fill:metal,stroke:'#6d756b'});
  out+=rect(x,y+h-2*s,w,2*s,metal)+rect(x+w*.42,y+h-1.1*s,w*.16,.5*s,'#18262d');
 }else{
  out+=rect(x,y,w,h,metal)+rect(x+w*.05,y+h*.19,w*.7,h*.65,'#18262d')+rect(x+w*.82,y+h*.18,w*.12,h*.18,'#18262d');
  out+=rect(x+w*.76,y+h*.25,.35*s,h*.5,'#dce1e2');
  for(let i=0;i<3;i++)out+=line(x+w*.08,y+h*(.07+i*.03),x+w*.73,y+h*(.07+i*.03),'#18262d');
 }
 if(active)out+=rect(x,y,w,h,'none','#315f4f',{'stroke-width':2.5});return out;
}
function applianceDrawing(c,x,base,s,active){
 if(c.appliance&&typeof catalogElevation==='function')return catalogElevation(c,x,base,s);
 if(['hood','microwave'].includes(c.kind))return overheadDrawing(c,x,base,s,active);
 const w=c.width*s,h=(mode==='top'?c.depth:c.height)*s,y=mode==='top'?base-h:base-(c.z+c.height)*s;
 const metal=applianceColors[c.appliance_finish||'stainless'],glass='#203039',pull='#edf1f2';
 let out=rect(x,y,w,h,metal,'#65727a');
 const r=(xx,yy,ww,hh,fill,stroke='#65727a')=>rect(x+xx*w,y+yy*h,ww*w,hh*h,fill,stroke);
 const l=(a,b,cc,d,ink=pull)=>line(x+a*w,y+b*h,x+cc*w,y+d*h,ink,{'stroke-width':2.5});
 if(mode==='top'){
  out+=l(0,.96,1,.96,'#65727a');
  if(c.kind==='oven'){
   out+=r(.04,.04,.92,.88,glass);
   for(const cx of [.27,.73])for(const cy of [.26,.70])out+=svg('circle',{cx:x+cx*w,cy:y+cy*h,r:Math.min(w,h)*.13,fill:'none',stroke:pull,'stroke-width':1.5});
  }else out+=text(x+w/2,y+h/2,c.kind==='fridge'?'REF':'DW',{'font-size':15,fill:c.appliance_finish==='black'?pull:glass});
 }else if(c.kind==='fridge'){
  out+=l(0,.70,1,.70,'#65727a')+l(.5,0,.5,.70,'#65727a');
  out+=l(.44,.41,.44,.64)+l(.56,.41,.56,.64)+l(.2,.75,.8,.75);
  out+=r(0,.975,1,.025,glass,'none');
 }else if(c.kind==='oven'){
  out+=r(.015,.12,.97,.81,glass)+r(.13,.34,.74,.43,'#344850');
  out+=l(.12,.18,.88,.18);
  for(const cx of [.2,.4,.6,.8])out+=svg('circle',{cx:x+cx*w,cy:y+.055*h,r:Math.max(1.5,.4*s),fill:glass});
 }else{
  out+=r(.01,.015,.98,.075,glass)+r(.65,.033,.18,.02,pull,'none');
  out+=l(.18,.13,.82,.13)+r(0,.94,1,.06,glass,'none');
  out+=rect(x,y-1.5*s,w,1.5*s,'#f0eee6');
 }
 out+=rect(x,y,w,h,'none',active?'#315f4f':'transparent',{class:'outline','stroke-width':active?2.5:1});
 return out;
}
function crownRuns(source){
 if(!kitchenSettings.crown_profile||kitchenSettings.crown_profile==='none')return [];
 const runs=[];
 source.filter(c=>['wall','tall','oven_tower','micro_tower','fridge_surround'].includes(c.kind)).sort((a,b)=>(a.z+a.height-b.z-b.height)||(a.depth-b.depth)||(a.x-b.x)).forEach(c=>{
  const r=runs[runs.length-1];
  if(r&&Math.abs(r.right-c.x)<.001&&Math.abs(r.top-c.z-c.height)<.001&&r.depth===c.depth&&r.finish===c.finish)r.right=c.x+c.width;
  else runs.push({left:c.x,right:c.x+c.width,top:c.z+c.height,depth:c.depth,finish:c.finish});
 });return runs;
}
function drawPlan(source,target=$('drawing'),currentDrag=drag,standalone=false){
 const drag=currentDrag,boxes=source.map(c=>KitchenPlacement.footprint(c,standalone));
 const refs=standalone?[]:houseContext.items||[],points=refs.flatMap(r=>r.points);
 const minX=Math.min(0,...boxes.map(b=>b[0]),...points.map(p=>p[0]))-12,maxX=Math.max(50,...boxes.map(b=>b[1]),...points.map(p=>p[0]))+35;
 const minY=Math.min(standalone?-50:-180,...boxes.map(b=>b[2]),...points.map(p=>p[1]))-35,maxY=Math.max(0,...boxes.map(b=>b[3]),...points.map(p=>p[1]))+12;
 const scale=Math.min(740/(maxX-minX),390/(maxY-minY));
 const frame=drag?drag.frame:!standalone&&typeof islandDrag!=='undefined'&&islandDrag?islandDrag.frame:{s:scale,ox:100-minX*scale,base:85+maxY*scale,local:standalone};
 if(!standalone)layout=frame;
 const {s,ox,base}=frame,project=p=>[ox+p[0]*s,base-p[1]*s];
 const polygon=(pts,attrs)=>svg('polygon',{points:pts.map(p=>p.join(',')).join(' '),...attrs});
 let out='',floating='';
 for(const ref of refs)out+=polygon(ref.points.map(project),{fill:ref.type==='wall'?'#d4d7d2':ref.type==='window'?'#acd9e8':'#e9d2a6',stroke:'#929d94','stroke-width':1,'fill-opacity':.55,'pointer-events':'none'});
 if(!standalone){
  const origin=project(KitchenPlacement.point('A',0,0));
  for(const [area,label] of [['A','Run A'],['B','Run B']]){const q=project(KitchenPlacement.point(area,Math.max(area==='B'?144:48,...source.filter(c=>wallOf(c)===area).map(c=>c.x+c.width)),0));out+=line(...origin,...q,'#315f4f',{'stroke-width':2,'stroke-dasharray':'6 4'})+text(q[0],q[1]-12,label,{'font-size':12});}
  if(refs.length)out+=text(100,35,'House reference · Level '+houseContext.level+' · Not collision checked',{'font-size':12});
 }
 for(const c of source){
  const b=KitchenPlacement.footprint(c,standalone),x=ox+b[0]*s,y=base-b[3]*s,w=(b[1]-b[0])*s,h=(b[3]-b[2])*s,active=c.id===selected?.id,moving=drag?.moved&&drag.original.id===c.id;
  const shape=FrontLayouts.corner(c)?[[0,0],[c.width,0],[c.width,c.depth],[c.depth,c.depth],[c.depth,c.width],[0,c.width]].map(p=>planPoint(c,p[0],p[1],frame)):KitchenPlacement.polygon(c,standalone).map(project);
  const outline=polygon(shape,{fill:colors[c.finish],stroke:active?'#315f4f':'#7b897e','stroke-width':active?3:1,'fill-opacity':['wall','corner_upper'].includes(c.kind)?.45:.9,'stroke-dasharray':c.kind==='wall'?'5 4':'none'});
  const body=outline+(c.appliance&&typeof catalogPlan==='function'?catalogPlan(c,frame):'')+text(x+w/2,y+h/2,fmt(c.width),{'font-size':11,'pointer-events':'none'})+planDetails(c,frame)+(typeof sinkPlan==='function'?sinkPlan(c,frame):'');
  if(moving){out+=polygon(shape,{fill:'#478b6318',stroke:'#388453','stroke-dasharray':'5 4',class:'drop-placeholder'});const a=project(KitchenPlacement.point(wallOf(c),0,0)),b=project(KitchenPlacement.point(wallOf(c),drag.floating.x-c.x,0));floating=svg('g',{class:'cab floating-cabinet','data-id':c.id,opacity:.75,'pointer-events':'none',transform:'translate('+(b[0]-a[0])+' '+(b[1]-a[1])+')'},body);}
  else out+=svg('g',{class:'cab','data-id':c.id},body);
 }
 if(drag?.moved&&drag.insertion!=null){const c={...drag.original,x:drag.insertion},a=planPoint(c,0,-2,frame),b=planPoint(c,0,c.depth+2,frame);out+=line(...a,...b,'#16866b',{'stroke-width':4});}
 if(boxes.length){const lo=Math.min(...boxes.map(b=>b[0])),hi=Math.max(...boxes.map(b=>b[1]));out+=dimension(ox+lo*s,ox+hi*s,510,fmt(hi-lo));}
 if(standalone){const c=source[0],a=planPoint(c,c.width+6,0,frame),b=planPoint(c,c.width+6,c.depth,frame);out+=line(...a,...b)+text((a[0]+b[0])/2+18,(a[1]+b[1])/2,fmt(c.depth),{'font-size':17});}
 else if(source.some(c=>wallOf(c)==='I')){const p=planPoint({wall:'I',x:0},0,-6,frame);out+=svg('g',{'data-island-grip':'true',style:'cursor:move'},rect(p[0],p[1]-20,135,25,'#315f4f')+text(p[0]+67,p[1]-3,'↔ Move island',{fill:'#fff','font-size':13}));}
 target.innerHTML=out+floating;
}

function draw(single=null,view=mode,currentDrag=drag,target=null){
 if(!single)$('active_wall').parentElement.hidden=view!=='front';
 const mode=view,drag=currentDrag,drawing=target||(single?$('cabinetPreview'):$('drawing'));
 if(!single){
 $('empty').style.display=cabinets.length?'none':'grid';$('count').textContent=`${cabinets.length} items`;$('stamp').textContent=mode==='front'?'Elevation A':'Plan · Top view';
 if(!cabinets.length&&mode!=='top'){drawing.innerHTML='';return;}
 }
 const displayed=single?[single]:editorPreview?cabinets.map(c=>c.id===editorPreview.id?editorPreview:c):cabinets;
 const all=drag&&drag.moved?(drag.placed||displayed.map(c=>c.id===drag.original.id?drag.preview:c)):displayed;
 if(mode==='top'){drawPlan(all,drawing,drag,!!single);return;}
 const source=single?all:all.filter(c=>wallOf(c)===activeWall||(activeWall!=='I'&&FrontLayouts.corner(c)));if(!single)$('stamp').textContent='Elevation '+activeWall;
 if(!source.length){drawing.innerHTML='';$('empty').style.display='grid';return;}
 const crowns=single?[]:crownRuns(source),ch=kitchenSettings.crown_height||4,cp=kitchenSettings.crown_depth||3;
 const end=Math.max(...source.map(c=>c.x+c.width));const height=Math.max(40,...source.map(c=>c.z+c.height+1.5+(c.sink?.type!=='none'&&c.sink?.faucet!=='none'?(c.sink?.faucet_height||0):0)),...crowns.map(r=>r.top+ch));const depth=Math.max(...source.map(c=>c.depth+1),...crowns.map(r=>r.depth+cp));
 const autoScale=Math.min(740/Math.max(end,50),365/(mode==='front'?height:Math.max(depth,40)));
 const frame=drag?drag.frame:{s:autoScale,ox:(960-end*autoScale)/2,base:mode==='front'?475:180+depth*autoScale};
 const {s,ox,base}=frame;if(!single)layout=frame;
 let out='',floatingCabinet='';
 if(mode==='front')out+=line(ox-28,base,ox+end*s+28,base,'#9aab98');
 for(const c of source){const x=ox+c.x*s,w=c.width*s;let inner='';const fill=colors[c.finish];const active=c.id===selected?.id;
  if(FrontLayouts.corner(c)){inner=cornerDrawing(c,x,base,s,active);}else if(plainPanel(c)){const yy=base-(c.z+c.height)*s;inner=rect(x,yy,w,c.height*s,fill,'#66796a')+text(x+w/2,yy+c.height*s/2,c.kind==='corner'?'Closed corner':'Filler',{'font-size':11});}else if(isAppliance(c)){inner=applianceDrawing(c,x,base,s,active);
  }else if(mode==='top'){
   const y=base-c.depth*s;
   inner+=rect(x,y,w,c.depth*s,fill,'#66796a',c.kind==='wall'?{'stroke-dasharray':'6 4','fill-opacity':.4}:{});
   inner+=line(x,base-2*s,x+w,base-2*s,'#66796a');inner+=text(x+w/2,y+c.depth*s/2,`${c.width} × ${c.depth}`,{'font-size':13,fill:c.finish==='charcoal'?'#eaece5':'#536454'});
   if(c.kind!=='wall'&&FrontLayouts.toe(c)>0)inner+=line(x,base-(c.toe_setback??3)*s,x+w,base-(c.toe_setback??3)*s,'#315f4f',{'stroke-dasharray':'4 3'});
   inner+=rect(x,y,w,c.depth*s,'none',active?'#315f4f':'transparent',{class:'outline','stroke-width':active?2.5:1});
  }else{
   const y=base-(c.z+c.height)*s;const toe=FrontLayouts.toe(c);const frontH=c.height-toe;
   inner+=rect(x,y,w,c.height*s,fill);
   if(toe)inner+=rect(x,base-(c.z+toe)*s,w,toe*s,fill);
   const fronts=[];
   let yy=y+(.125+(c.sink?.product_id==='kohler-k-6489'?8.9375:0))*s;
   FrontLayouts.rows(c).forEach((row,rowIndex)=>{
    const fh=row.height*s;
    if(row.kind==='appliance')inner+=builtinDrawing(row,c,x,yy,w,s);
    else if(row.kind==='drawer')fronts.push([x+(.125-(c.front_overlay||0))*s,yy,w+((c.front_overlay||0)*2-.25)*s,fh,true,'left',rowIndex]);
    else if(row.doors===1)fronts.push([x+.125*s,yy,w-.25*s,fh,row.opening==='lift','left',rowIndex]);
    else {const dw=(w-.375*s)/2;fronts.push([x+.125*s,yy,dw,fh,false,'left',rowIndex],[x+dw+.25*s,yy,dw,fh,false,'right',rowIndex]);}
    yy+=fh+.125*s;
   });
   fronts.forEach(([fx,fy,fw,fh,horiz,side,rowIndex],i)=>{inner+=rect(fx,fy,fw,fh,fill);if(['shaker','glass'].includes(c.style)){const r=kitchenSettings.shaker_width*s;inner+=rect(fx+r,fy+r,Math.max(0,fw-2*r),Math.max(0,fh-2*r),fill,'#8a9184')+rect(fx+r,fy+r,Math.max(0,fw-2*r),Math.max(0,fh-2*r),'#23382b','none',{'fill-opacity':kitchenSettings.shaker_inset*.18});}if(c.style==='glass'&&!horiz){const r=kitchenSettings.shaker_width*s;inner+=rect(fx+r,fy+r,fw-2*r,fh-2*r,'#afdae2','#7fa5af',{'fill-opacity':.55})+line(fx+r+3,fy+fh-r-3,fx+fw-r-3,fy+r+3,'#edf9fc');}if(c.handle!=='none'&&!(c.kind==='sink'&&horiz)){const ink=c.handle==='brass'?'#a38344':'#232b26';const hp=handleLayout(c,fw/s,fh/s,horiz,side==='left',rowIndex);inner+=rect(fx+hp[0]*s,fy+(fh/s-hp[1]-hp[3])*s,hp[2]*s,hp[3]*s,ink,ink);}});
   if(!['wall','tall','oven_tower','micro_tower','fridge_surround'].includes(c.kind))inner+=rect(x,y-1.5*s,w,1.5*s,'#f0eee6');
   inner+=rect(x,y,w,c.height*s,'none',active?'#315f4f':'transparent',{class:'outline','stroke-width':active?2.5:1});
  }
  if(mode==='front'&&typeof sinkElevation==='function')inner+=sinkElevation(c,x,base,s);
  if(c.flip_y&&!single)inner=rect(x,base-(c.z+c.height)*s,w,c.height*s,colors[c.finish],'#66796a');
  if(c.flip_x)inner=svg('g',{transform:`translate(${2*x+w} 0) scale(-1 1)`},inner);
  const moving=drag&&drag.moved&&c.id===drag.original.id;
  if(moving){const yy=mode==='front'?base-(c.z+c.height)*s:base-c.depth*s;const hh=(mode==='front'?c.height:c.depth)*s;inner+=rect(x,yy,w,hh,drag.valid?'#478b6330':'#c9464638',drag.valid?'#388453':'#c94646',{'stroke-width':3});}
  if(moving&&drag.floating){
   const yy=mode==='front'?base-(c.z+c.height)*s:base-c.depth*s,hh=(mode==='front'?c.height:c.depth)*s;
   out+=rect(x,yy,w,hh,'#478b6318',drag.valid?'#388453':'#c94646',{'stroke-width':2,'stroke-dasharray':'6 4',class:'drop-placeholder'});
   floatingCabinet=svg('g',{class:'cab floating-cabinet','data-id':c.id,opacity:.78,'pointer-events':'none',transform:`translate(${(drag.floating.x-c.x)*s} ${mode==='front'?(c.z-drag.floating.z)*s:0})`},inner);
  }else out+=svg('g',{class:'cab','data-id':c.id},inner);
  if(single&&c.pantry&&typeof pantrySectionDimensions==='function')out+=pantrySectionDimensions(c,x,base,s);
  // Separate dimension rows for upper and lower cabinets.
  const dy=mode==='front'?(c.kind==='wall'?75:base+34):(c.kind==='wall'?130:base+34);
  out+=dimension(x,x+w,dy,fmt(c.width),c.id);
 }
 for(const r of crowns){
  const x=ox+(r.left-cp)*s,w=(r.right-r.left+cp*2)*s,fill=kitchenSettings.crown_color==='white'?'#f5f3ed':colors[r.finish];
  if(mode==='front'){
   const y=base-(r.top+ch)*s;out+=rect(x,y,w,ch*s,fill,'#66796a');
   if(kitchenSettings.crown_profile==='crown')for(const t of [.1,.18,.9])out+=line(x,y+ch*s*t,x+w,y+ch*s*t,'#8a9184');
   out+=text(x+w/2,y-8,`Top ${fmt(r.top+ch)}`,{fill:'#627369','font-size':12});
  }else out+=rect(x,base-(r.depth+cp)*s,w,cp*s,fill,'#66796a');
 }
 out+=dimension(ox,ox+end*s,base+79,fmt(end));
 const c=single||drag?.preview||editorPreview||selected;
 const tall=mode==='front'?source.filter(item=>['tall','fridge','oven_tower','micro_tower','fridge_surround'].includes(item.kind)).sort((a,b)=>b.height-a.height)[0]:null;
 const measurements=[];
 if(c&&(!tall||c.height!==tall.height||c.z!==tall.z))measurements.push({cabinet:c,lane:0});
 if(tall)measurements.push({cabinet:tall,lane:1});
 measurements.forEach(({cabinet:d,lane})=>{
  const xx=ox+end*s+28+40*lane+(single?.pantry?110:0),dim=mode==='front'?d.height:d.depth;
  const y1=mode==='front'?base-(d.z+d.height)*s:base-d.depth*s;
  const y2=mode==='front'?base-d.z*s:base;
  const edge=ox+(d.x+d.width)*s;
  out+=svg('g',{class:'height-dimension','data-cabinet-id':d.id},
   line(edge+3,y1,xx+6,y1,'#b7c1b5')+line(edge+3,y2,xx+6,y2,'#b7c1b5')+
   line(xx,y1,xx,y2)+line(xx-6,y1,xx+6,y1)+line(xx-6,y2,xx+6,y2)+
   text(xx+18,(y1+y2)/2,fmt(dim),{transform:`rotate(-90 ${xx+18} ${(y1+y2)/2})`}));
 });
 if(drag&&drag.moved){if(drag.insertion!=null){const xx=ox+drag.insertion*s,col=drag.valid?'#16866b':'#c94646';out+=line(xx,85,xx,base+18,col,{'stroke-width':4})+line(xx-9,85,xx+9,85,col,{'stroke-width':4})+line(xx-9,base+18,xx+9,base+18,col,{'stroke-width':4})+text(xx,72,'Insert here',{fill:col,'font-size':16});}else if(drag.edge!==null){const xx=ox+drag.edge*s;out+=line(xx,95,xx,base+12,drag.valid?'#388453':'#c94646',{'stroke-width':2,'stroke-dasharray':'5 4'});}out+=text(480,590,`X = ${fmt(drag.preview.x)}`,{fill:drag.valid?'#315f4f':'#b53030','font-size':17});}
 drawing.innerHTML=out+floatingCabinet;
 (single?[]:drawing.querySelectorAll('[data-dim]')).forEach(el=>el.addEventListener('click',()=>{if(!el.dataset.dim)return;choose(el.dataset.dim);$('width').focus();$('width').select();}));
}
window.addEventListener('load',()=>{send('ready');send('fit_height',Math.max(680,Math.min(820,document.body.scrollHeight)));});

