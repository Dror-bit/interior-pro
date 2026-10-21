let doc={revision:0,cabinets:[]},mount='floating',columns=[{kind:'doors',count:2}],selectedColumn=0,position={x:0,y:0,z:12,angle:0},legs=false,supportHeight=4;
const el=id=>document.getElementById(id),clone=v=>JSON.parse(JSON.stringify(v));
function showError(message){el('error').textContent=message;}
function current(){return doc.cabinets.find(c=>c.id===el('list').value);}
function values(){const v={};['width','depth','height'].forEach(k=>v[k]=Number(el(k).value));['style','finish','handle'].forEach(k=>v[k]=el(k).value);v.mount=mount;v.legs=mount==='floor'&&legs;v.support_height=supportHeight;v.leg_style=el('legStyle').value;v.drawer=el('product').value==='makeup'&&el('drawer').checked;v.basins=el('product').value==='makeup'?0:Number(el('basins').value);v.position={...position,z:mount==='floor'?0:Number(el('z').value)};v.faucet_id=el('product').value==='vanity'?el('faucet_id').value:'none';v.sink_parts=el('product').value==='vanity'?clone(sinkParts):null;v.accessories=clone(accessoryItems);v.basin_faucets=basinChoices(v.basins);v.countertop='white';v.surfaces=surfaces();v.front_columns=el('product').value==='vanity'?clone(columns):[];return v;}
function setMount(value){mount=value;legs=value==='floor';if(value==='floating'&&Number(el('z').value)<=0)el('z').value=12;update();}
function initializeWidths(total){if(columns.every(c=>c.width!==undefined))return;const ticks=Math.round(total*8),base=Math.floor(ticks/columns.length);columns=columns.map((c,i)=>({...c,width:(base+(i<ticks%columns.length?1:0))/8}));}
function setPartCount(count){if(!Number.isInteger(count)||count<1||count>6)return;initializeWidths(Number(el('width').value));columns=Array.from({length:count},(_,i)=>columns[i]||{kind:'doors',count:2,width:24});selectedColumn=Math.min(selectedColumn,count-1);update();}
function selectColumn(){selectedColumn=Number(el('column').value);update();}
function setMakeupSide(side){
 const selected=columns[selectedColumn],makeup=columns.filter(c=>c.kind==='makeup'),cabinets=columns.filter(c=>c.kind!=='makeup');
 if(!makeup.length||!cabinets.length)return;
 columns=side==='left'?[...makeup,...cabinets]:[...cabinets,...makeup];
 selectedColumn=columns.indexOf(selected);update();
}
function rect(x,y,w,h,fill,extra=''){return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="1" fill="${fill}" stroke="#777f74" stroke-width="1" ${extra}/>`;}
function update(){
 const custom=el('product').value==='vanity'&&current()?.product_id!=='gallery';
 if(custom){initializeWidths(Number(el('width').value));el('width').value=columns.reduce((sum,c)=>sum+c.width,0);}
 el('width').readOnly=custom;
 if(document.activeElement!==el('columnWidth'))el('columnWidth').value=columns[selectedColumn].width??Number(el('width').value)/columns.length;
 syncSinkLocations();syncAccessoryControls();checkLightClearance();updateFaucetGallery();
 const v=values(),imported=current()?.product_id==='gallery',make=el('product').value==='makeup';
 el('legStyleLabel').hidden=mount!=='floor'||imported;
 el('mountHeight').hidden=mount!=='floating'||imported;el('basinLabel').hidden=make||imported;el('makeupDrawer').hidden=!make||imported;el('layoutTitle').hidden=el('columnEditor').hidden=make||imported;
 document.querySelectorAll('#mountChoices button').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.value===mount));b.disabled=imported;});
 if(Number.isFinite(v.width)&&v.width>0&&columns.every(c=>c.width===undefined||c.width>=4))el('preview').innerHTML=renderPreview(v,imported);
 el('sinkSettings').hidden=make||imported;el('surfaceSettings').hidden=imported;
 ['sink_width','sink_depth','sink_height'].forEach(id=>el(id).readOnly=el('sink_shape').value==='icera_muse');
 el('makeupSide').hidden=true;
 document.querySelectorAll('#makeupSide button').forEach(button=>{
  const side=button.dataset.side,index=side==='left'?0:columns.length-1;
  button.setAttribute('aria-pressed',String(columns[index].kind==='makeup'));
 });
 el('partCount').value=columns.length;
 const isMakeup=columns[selectedColumn].kind==='makeup';
 el('columnDrawerLabel').hidden=!['makeup','doors','doors_drawer'].includes(columns[selectedColumn].kind);
 el('columnDrawerText').textContent=isMakeup?'מגירה במייק־אפ':'מגירה מעל הדלתות';
 el('columnDrawer').checked=isMakeup?columns[selectedColumn].count===1:columns[selectedColumn].kind==='doors_drawer';
 el('columnCountLabel').parentElement.hidden=isMakeup;
 el('columnCountLabel').textContent=isMakeup?'מגירה במייק־אפ':columns[selectedColumn].kind==='drawers'?'מספר מגירות':'מספר דלתות';
 el('columnCount').replaceChildren(...(isMakeup?[new Option('ללא מגירה',0),new Option('מגירה אחת',1)]:[1,2,3,4].map(n=>new Option(n,n))));
 el('column').replaceChildren(...columns.map((_,i)=>new Option(columns.length===1?'כל החזית':`חלק ${i+1} ${i===0?'(שמאל)':i===columns.length-1?'(ימין)':''}`,i)));el('column').value=selectedColumn;el('columnKind').value=columns[selectedColumn].kind;el('columnCount').value=columns[selectedColumn].count;
 el('primary').textContent=current()?'עדכן ארון':'הצב במודל';el('existingActions').hidden=!current();
 const saved=current(),pending=saved&&!imported&&Object.entries(v).some(([key,value])=>JSON.stringify(value)!==JSON.stringify(saved[key]));
 el('pendingChanges').hidden=!pending;
 el('pendingChanges').textContent=pending?'השינויים בתצוגה עדיין לא הוחלו במודל — לחץ ״עדכן ארון״':'';
}
function render(source,gallery){const selected=el('list').value;doc=source;el('list').replaceChildren(new Option('ארון חדש',''));doc.cabinets.forEach((c,i)=>el('list').add(new Option(`${c.product_id==='makeup'?'מייק־אפ':c.product_id==='gallery'?'מהגלריה':'וונטי'} ${i+1} · ${c.width}″`,c.id)));el('list').value=doc.cabinets.some(c=>c.id===selected)?selected:'';const asset=el('gallery').value;el('gallery').replaceChildren(...gallery.map(a=>new Option(a.name,a.id)));if(gallery.some(a=>a.id===asset))el('gallery').value=asset;el('galleryPlace').disabled=!gallery.length;if(current())choose();else update();}
function choose(){loadAccessoryState(current());const c=current(),imported=c?.product_id==='gallery';document.querySelectorAll('input,select').forEach(e=>{if(!['list','gallery','gallery_name'].includes(e.id))e.disabled=!!imported;});el('product').disabled=!!c;if(!c){newCabinet();return;}sinkParts=c.sink_parts?clone(c.sink_parts):null;if(!imported)el('product').value=c.product_id;['width','depth','height','style','finish','handle'].forEach(k=>el(k).value=c[k]);el('faucet_id').value=c.faucet_id||'none';el('legStyle').value=c.leg_style||'square';mount=c.mount;legs=c.legs;supportHeight=c.support_height;el('drawer').checked=c.drawer;el('basins').value=c.basins||1;position=clone(c.position);el('z').value=c.position.z;columns=c.front_columns?.length?clone(c.front_columns):Array.from({length:c.basins||1},()=>({kind:'doors',count:2}));selectedColumn=0;Object.entries({...legacySurfaceDefaults,...c.surfaces}).forEach(([k,v])=>el(k).value=v);if(c.basin_faucets?.[0]){el('faucet_id').value=c.basin_faucets[0].id;el('faucet_finish').value=c.basin_faucets[0].finish;}update();}
function newCabinet(){loadAccessoryState(null);el('legStyle').value='square';sinkParts=null;el('list').value='';document.querySelectorAll('input,select').forEach(e=>e.disabled=false);el('product').value='vanity';el('faucet_id').value='none';position={x:0,y:0,z:12,angle:0};mount='floating';legs=false;supportHeight=4;el('z').value=12;el('width').value=36;el('depth').value=21;el('height').value=30;el('style').value='slab';el('finish').value='white';el('handle').value='keaton';Object.entries(surfaceDefaults).forEach(([k,v])=>el(k).value=v);el('basins').value=1;el('drawer').checked=false;columns=[{kind:'doors',count:2}];selectedColumn=0;showError('');update();}
function send(action){if(['save','place'].includes(action)&&!checkLightClearance()){showError('המנורה חופפת למראה — שנה צד, מרווח או גובה.');return;}const c=current();let v=values();if(action==='save'&&c?.product_id==='gallery')v={position:clone(c.position)};if(['place','save'].includes(action)&&c?.product_id!=='gallery'){if(v.front_columns.some(c=>!Number.isFinite(c.width)||c.width<4||Math.abs(c.width*8-Math.round(c.width*8))>1e-6)||v.width>120){showError('רוחב כל חלק: לפחות 4 אינץ׳ בכפולות של שמינית. רוחב כולל: עד 120 אינץ׳.');return;}if(v.basins===2&&v.width<48){showError('לשני כיורים נדרש רוחב של 48 אינץ׳ לפחות.');return;}if(['width','depth','height'].some(k=>!Number.isFinite(v[k])||v[k]<=0)){showError('יש להזין מידות תקינות.');return;}}sketchup.action(JSON.stringify({action,revision:doc.revision,id:el('list').value,product:el('product').value,values:v,asset_id:el('gallery').value,name:el('gallery_name').value}));}
document.querySelectorAll('input,select').forEach(e=>{if(!['list','column','columnKind','columnCount','columnWidth','columnDrawer','partCount','gallery','sinkPart0','sinkPart1','faucetBasin'].includes(e.id))e.addEventListener('input',update);});
el('columnDrawer').addEventListener('change',()=>{
 const column=columns[selectedColumn];
 if(column.kind==='makeup')column.count=el('columnDrawer').checked?1:0;
 else if(['doors','doors_drawer'].includes(column.kind))column.kind=el('columnDrawer').checked?'doors_drawer':'doors';
 update();
});
el('sink_shape').addEventListener('change',()=>{
 const values=el('sink_shape').value==='icera_muse'?surfaceDefaults:legacySurfaceDefaults;
 ['sink_width','sink_depth','sink_height'].forEach(id=>el(id).value=values[id]);update();
});
['columnKind','columnCount'].forEach(id=>el(id).addEventListener('change',()=>{columns[selectedColumn]={...columns[selectedColumn],kind:el('columnKind').value,count:el('columnKind').value==='makeup'?Math.min(1,Number(el('columnCount').value)):Math.max(1,Number(el('columnCount').value))};update();}));
el('columnWidth').addEventListener('input',()=>{const width=Number(el('columnWidth').value);if(!Number.isFinite(width))return;columns[selectedColumn].width=width;update();});
el('columnWidth').addEventListener('change',()=>{el('columnWidth').value=columns[selectedColumn].width;});
el('preview').addEventListener('click',event=>{const target=event.target.closest('[data-column]');if(target){selectedColumn=Number(target.dataset.column);update();}});
faucetAssets.forEach(a=>el('faucet_id').add(new Option(a.label,a.id)));
document.addEventListener('DOMContentLoaded',()=>{update();sketchup.ready();});
