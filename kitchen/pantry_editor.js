/* Three independent sections, stored as one cabinet. */
(()=>{
 let choices=[],device=null;
 const section=document.createElement('section');section.id='pantryEditor';section.className='wide';
 section.innerHTML=`<h2>Pantry sections</h2><label><input id="pantryEnabled" type="checkbox" style="width:auto;height:auto"> Three sections</label><div id="pantrySections">
 <h2 style="margin-top:14px">Top</h2><label>Front<select id="pantryTop"><option value="single">Single door</option><option value="double">Double doors</option><option value="lift">Lift-up door</option></select></label><div id="pantryTopHeight"></div>
 <h2 style="margin-top:14px">Middle</h2><label>Front or appliance<select id="pantryMiddle"><option value="single">Single door</option><option value="double">Double doors</option><option value="microwave">Microwave</option><option value="wall_oven">Wall oven</option></select></label><label>Section height (in)<input id="pantryMiddleHeight" type="number" min="8" step="any"></label><button id="pantryChoose" type="button" class="subtle">Choose compatible appliance…</button><div id="pantryDevice"></div>
 <h2 style="margin-top:14px">Bottom</h2><label>Front<select id="pantryBottom"><option value="combo_single">Top drawer + single door</option><option value="combo_double">Top drawer + double doors</option><option value="drawers">Drawers</option></select></label><label>Section height (in)<input id="pantryBottomHeight" type="number" min="8" step="any"></label><label id="pantryDrawerLabel">Drawer count<select id="pantryDrawers"><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></label>
 <div id="pantryDrawerSizing"><div id="pantryDrawerHeights" class="fields"></div><div id="pantryDrawerBalance" role="status" style="font-size:12px;margin:8px 0"></div><button id="pantryFitDrawer" class="subtle" type="button">Fit last drawer</button> <button id="pantryEqualDrawers" class="subtle" type="button">Equal heights</button></div>
 </div>`;
 $('frontEditor').before(section);
 for(const zone of ['Top','Middle','Bottom']){
  const label=document.createElement('label');label.id='pantry'+zone+'HingeLabel';label.textContent='Door opening';
  const input=document.createElement('select');input.id='pantry'+zone+'Hinge';input.setAttribute('form','form');input.innerHTML='<option value="left">Hinges on left</option><option value="right">Hinges on right</option>';label.append(input);$('pantry'+zone).closest('label').after(label);
 }

 // Pantry inspector: size, sections, style/color, toe kick, then all hardware.
 const controls=$('cabinetControls'),originalOrder=[...controls.children];
 function arrangePantryControls(){
  if(selected?.kind!=='tall'){for(const node of originalOrder)controls.append(node);return;}
  const label=id=>$(id)?.closest('label');
  const hardware=[label('inherit_handle'),label('handle'),controls.querySelector('.handle-choices'),$('handleEditor')].filter(Boolean);
  const molding=originalOrder.find(node=>node.tagName==='BUTTON'&&node.textContent==='Choose cabinet molding...');
  const first=[$('cabinetSizePanel'),section,$('frontEditor'),$('builtinEditor'),label('style'),label('inherit_finish'),label('finish'),molding,$('toeEditor')].filter(Boolean);
  for(const node of [...first,...originalOrder.filter(node=>!first.includes(node)&&!hardware.includes(node)),...hardware])controls.append(node);
 }

 const gallery=document.createElement('dialog');gallery.id='pantryGallery';gallery.style.cssText='width:min(850px,90vw);max-height:85vh;border:1px solid #ccd7cd;border-radius:12px;padding:20px';
 gallery.innerHTML='<h2>Compatible pantry appliances</h2><p>Choose a model that fits your pantry.</p><div data-grid style="display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px"></div><p data-empty></p><button type="button" class="subtle" data-close>Close</button>';
 document.body.append(gallery);gallery.querySelector('[data-close]').onclick=()=>gallery.close();
 function draft(){return {...selected,width:Number($('width').value),depth:Number($('depth').value),height:Number($('height').value),toe_height:Number($('toe_height').value)};}
 window.readPantryEditor=function(c){
  if(c.kind!=='tall'||!$('pantryEnabled').checked)return null;
  const p={version:1,drawer_height_basis:'section',top:$('pantryTop').value,middle:$('pantryMiddle').value,bottom:$('pantryBottom').value,bottom_height:Number($('pantryBottomHeight').value),middle_height:Number($('pantryMiddleHeight').value),drawers:Number($('pantryDrawers').value)};
  for(const zone of ['Top','Middle','Bottom'])p[zone.toLowerCase()+'_hinge']=$('pantry'+zone+'Hinge').value;
  if(p.bottom==='drawers')p.drawer_heights=drawerInputs().map(input=>Number(input.value));
  if(['microwave','wall_oven'].includes(p.middle)&&device)p.appliance=structuredClone(device);
  return p;
 };

 function drawerInputs(){return [...section.querySelectorAll('[data-pantry-drawer]')];}
 function renderDrawerHeights(values){
  const n=Number($('pantryDrawers').value),available=Number($('pantryBottomHeight').value);
  const heights=Array.isArray(values)&&values.length===n?values:PantryLayouts.equalDrawers(available,n);
  $('pantryDrawerHeights').replaceChildren();
  heights.forEach((height,i)=>{const label=document.createElement('label');label.textContent='Drawer '+(i+1)+(i===0?' · top':'')+' height (in)';const input=document.createElement('input');input.type='number';input.min='3';input.step='0.125';input.required=true;input.dataset.pantryDrawer=String(i);input.setAttribute('form','form');input.value=Number(height.toFixed(8));label.append(input);$('pantryDrawerHeights').append(label);});
 }
 $('pantryDrawers').addEventListener('change',()=>renderDrawerHeights());
 $('pantryEqualDrawers').onclick=()=>{renderDrawerHeights();refresh();refreshCabinetPreview();};
 $('pantryFitDrawer').onclick=()=>{const inputs=drawerInputs(),n=inputs.length;if(!n)return;const rest=inputs.slice(0,-1).reduce((sum,input)=>sum+Number(input.value),0);inputs[n-1].value=Number((Number($('pantryBottomHeight').value)-rest).toFixed(8));refresh();refreshCabinetPreview();};

 function refresh(){
  const enabled=selected?.kind==='tall'&&$('pantryEnabled').checked;
  $('pantrySections').hidden=!enabled;
  section.querySelectorAll('#pantrySections input,#pantrySections select').forEach(e=>{e.disabled=!enabled;});
  if(selected?.kind==='tall')$('frontEditor').hidden=enabled;
  for(const zone of ['Top','Middle','Bottom']){const single=$('pantry'+zone).value===(zone==='Bottom'?'combo_single':'single');$('pantry'+zone+'HingeLabel').hidden=!single;$('pantry'+zone+'Hinge').disabled=!enabled||!single;}
  const drawers=$('pantryBottom').value==='drawers';
  $('pantryDrawerLabel').hidden=$('pantryDrawerSizing').hidden=!drawers;
  drawerInputs().forEach(input=>input.disabled=!enabled||!drawers);
  const remaining=Number($('pantryBottomHeight').value)-drawerInputs().reduce((sum,input)=>sum+Number(input.value),0);
  $('pantryDrawerBalance').textContent=Math.abs(remaining)<.005?'Heights fit · front gaps calculated automatically':(remaining>0?'Remaining: ':'Over by: ')+fmt(Math.abs(remaining));
  $('pantryDrawerBalance').style.color=Math.abs(remaining)<.005?'#315f4f':'#a43425';
  const appliance=['microwave','wall_oven'].includes($('pantryMiddle').value);
  $('pantryChoose').hidden=!appliance;
  $('pantryDevice').textContent=appliance?(device?device.brand+' '+device.model:'Choose an appliance to complete this section.'):'';
  const c=draft(),h=c.height-c.toe_height-.5-Number($('pantryBottomHeight').value)-Number($('pantryMiddleHeight').value);
  $('pantryTopHeight').textContent='Remaining top height: '+fmt(h);
 }
 const oldFill=fill;fill=function(){
  // Populate before older fill wrappers request a live preview.
  const p=selected?.pantry||PantryLayouts.defaults();device=p.appliance?structuredClone(p.appliance):null;
  $('pantryEnabled').checked=!!selected?.pantry;section.hidden=selected?.kind!=='tall';
  for(const [key,id] of Object.entries({top:'pantryTop',middle:'pantryMiddle',bottom:'pantryBottom',bottom_height:'pantryBottomHeight',middle_height:'pantryMiddleHeight',drawers:'pantryDrawers'}))$(id).value=p[key];
  for(const zone of ['Top','Middle','Bottom'])$('pantry'+zone+'Hinge').value=p[zone.toLowerCase()+'_hinge']??'left';
  renderDrawerHeights(PantryLayouts.drawerSlots(p));
  const result=oldFill.apply(this,arguments);arrangePantryControls();refresh();refreshCabinetPreview();return result;
 };
 section.addEventListener('change',e=>{if(e.target.id==='pantryMiddle'&&device?.category!==e.target.value)device=null;refresh();refreshCabinetPreview();});
 section.addEventListener('input',()=>{refresh();refreshCabinetPreview();});
 for(const id of ['height','width','depth','toe_height'])$(id).addEventListener('input',refresh);
 $('pantryChoose').onclick=()=>{
  const c=draft(),height=Number($('pantryMiddleHeight').value),category=$('pantryMiddle').value,grid=gallery.querySelector('[data-grid]');grid.replaceChildren();
  const matches=choices.filter(v=>PantryLayouts.fits(v.snapshot,c,height,category));
  const available=choices.filter(v=>v.snapshot.category===category).map(v=>{const a=v.snapshot;return {model:a.model,width:Math.max(a.dimensions.width+.25,a.cutout.width+1.5),depth:a.cutout.depth+.5,height:Math.max(a.dimensions.height,a.cutout.height)};});
  available.sort((a,b)=>(Math.max(0,a.width-c.width)+Math.max(0,a.depth-c.depth)+Math.max(0,a.height-height))-(Math.max(0,b.width-c.width)+Math.max(0,b.depth-c.depth)+Math.max(0,b.height-height))||a.width-b.width);
  const minimum=available[0],inch=v=>fmt(Math.ceil(v*8-.000001)/8);
  gallery.querySelector('[data-empty]').textContent=matches.length?'':minimum?'No model fits. Minimum for '+minimum.model+': '+inch(minimum.width)+' wide × '+inch(minimum.depth)+' deep; middle section '+inch(minimum.height)+' high.':'No verified built-in model available.';
  for(const item of matches){
   const a=item.snapshot,p=item.product,button=document.createElement('button');button.type='button';button.className='subtle';
   const img=document.createElement('img');img.src=p.gallery_image||p.image||p.preview_path||p.image_path||'';img.alt=a.model;img.style.cssText='width:100%;height:145px;object-fit:contain';
   const text=document.createElement('div');text.textContent=a.brand+' '+a.model+' — '+a.dimensions.width+' × '+a.dimensions.height+' × '+a.dimensions.depth+' in';
   button.append(img,text);button.onclick=()=>{device=structuredClone(a);gallery.close();refresh();refreshCabinetPreview();};grid.append(button);
  }
  gallery.showModal();
 };
 const receive=window.receiveKitchen;window.receiveKitchen=function(data){choices=data.pantry_appliances||[];return receive.apply(this,arguments);};

 window.pantrySectionDimensions=function(c,x,base,s){
  const rows=PantryLayouts.rows(c),zones=new Map(),top=base-(c.z+c.height)*s;
  const measure=(xx,y1,y2,label,side)=>line(xx,y1,xx,y2,'#738571')+line(xx-4,y1,xx+4,y1,'#738571')+line(xx-4,y2,xx+4,y2,'#738571')+text(xx+side*9,(y1+y2)/2+4,label,{'font-size':12,'text-anchor':side<0?'end':'start',fill:'#365346'});
  const value=v=>fmt(v);let y=top+.125*s,out='',drawer=0;
  for(const row of rows){
   const end=y+row.height*s,zone=zones.get(row.zone);
   if(zone)zone.end=end;else zones.set(row.zone,{start:y,end});
   if(row.kind==='doors'&&row.doors===1&&row.opening!=='lift'){
    const right=(row.hinge==='right')!==!!c.flip_x,hx=x+(right?c.width-.125:.125)*s,free=x+(right?.125:c.width-.125)*s;
    out+=svg('polyline',{class:'pantry-door-swing',points:`${free},${y} ${hx},${(y+end)/2} ${free},${end}`,fill:'none',stroke:'#748b7d','stroke-width':1,'stroke-dasharray':'4 3'});
   }
   if(row.kind==='drawer')out+=measure(x+c.width*s+18,y,y+(row.allocated_height??row.height)*s,'D'+(++drawer)+' · '+value(row.allocated_height??row.height),1);
   y=end+.125*s;
  }
  for(const [key,zone] of zones)out+=measure(x-20,zone.start,zone.end,({top:'Top',middle:'Middle',bottom:'Bottom'}[key])+' · '+value((zone.end-zone.start)/s),-1);
  return svg('g',{class:'pantry-section-dimensions','pointer-events':'none'},out);
 };

 const oldDrawing=builtinDrawing;builtinDrawing=function(row,c,x,y,w,s){
  if(!row.pantry_appliance)return oldDrawing.apply(this,arguments);
  const a=row.pantry_appliance,parts=(choices.find(v=>v.snapshot.id===a.id&&v.snapshot.asset?.manifest_sha256===a.asset?.manifest_sha256)?.parts)||c.pantry_appliance_parts||[],dim=a.dimensions;
  let out=rect(x,y,w,row.height*s,colors[c.finish]);
  const xx=x+(c.width-dim.width)*s/2,yy=y+(row.height-dim.height)*s/2;
  for(const p of [...parts].sort((a,b)=>b.y-a.y))out+=rect(xx+p.x*s,yy+(dim.height-p.z-p.height)*s,p.width*s,p.height*s,p.color||'#b8c0c4','#606766');
  return out;
 };
 const layout=handleLayout;handleLayout=function(c,w,h,horizontal,left,rowIndex=0){
  if(c.pantry&&PantryLayouts.rows(c)[rowIndex]?.opening==='lift'){
   c={...c,handle_position:'bottom',_handle_model_key:'door_handle_model'};horizontal=true;
  }
  return layout(c,w,h,horizontal,left,rowIndex);
 };
})();
