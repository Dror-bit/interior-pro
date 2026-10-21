let accessoryItems=[],lightingCatalog=[],individualFaucets=[],activeFaucetBasin=0,accessoryControlKey='';
function loadAccessoryState(c){
 accessoryItems=clone(c?.accessories||[]);individualFaucets=clone(c?.basin_faucets||Array.from({length:c?.basins||1},()=>({id:c?.faucet_id||'none',finish:c?.surfaces?.faucet_finish||'brushed_nickel'})));activeFaucetBasin=0;accessoryControlKey='';
 if(el('faucetBasin'))el('faucetBasin').value='0';
 // choose() restores legacy controls afterwards; per-basin values are restored on sync.
}
function basinChoices(count){
 individualFaucets[activeFaucetBasin]={id:el('faucet_id').value,finish:el('faucet_finish').value};
 return Array.from({length:count},(_,i)=>clone(individualFaucets[i]||individualFaucets[0]||{id:'none',finish:'brushed_nickel'}));
}
function chooseBasinFaucet(i){
 basinChoices(Number(el('basins').value));activeFaucetBasin=i;
 const a=individualFaucets[i]||individualFaucets[0];el('faucet_id').value=a.id;el('faucet_finish').value=a.finish;update();
}
function basinPreview(v,i){const a=v.basin_faucets?.[i];return a?{...v,faucet_id:a.id,surfaces:{...v.surfaces,faucet_finish:a.finish}}:v;}
function setLightingCatalog(list){lightingCatalog=list;accessoryControlKey='';syncAccessoryControls();update();}
function addAccessory(kind){
 if(kind==='light'&&!lightingCatalog.length){showError('אין מנורות קיר זמינות בגלריית החשמל');return;}
 accessoryItems.push({kind,part:selectedColumn,width:kind==='mirror'?24:6,height:kind==='mirror'?30:16,above:kind==='mirror'?6:12,offset:0,shape:'rectangle',product:lightingCatalog[0]?.name||''});accessoryControlKey='';update();
}
function mirrorOptions(a){return {frame:false,frame_width:.125,frame_color:'black',front_light:false,back_light:false,light_color:'warm',...a};}
function mirrorControls(a){return `<label><input type="checkbox" data-key="frame" ${a.frame?'checked':''}> עם מסגרת</label><div class="row"><button type="button" onclick="setThinMirrorFrame(this)">מסגרת דקה · ⅛ אינץ׳</button><label>צבע מסגרת<select data-key="frame_color"><option value="black">שחור</option><option value="white">לבן</option><option value="nickel">ניקל מוברש</option><option value="brass">Satin Brass</option></select></label><label>רוחב מסגרת (אינץ׳)<input type="number" data-key="frame_width" min="0.0625" max="3" step="0.0625" value="${a.frame_width}"></label></div><div class="row"><label><input type="checkbox" data-key="back_light" ${a.back_light?'checked':''}> תאורה אחורית</label><label><input type="checkbox" data-key="front_light" ${a.front_light?'checked':''}> פס תאורה קדמי</label></div><label>גוון התאורה<select data-key="light_color"><option value="warm">לבן חם</option><option value="neutral">לבן טבעי</option><option value="cool">לבן קר</option></select></label>`;}
function mirrorSvg(a,i,x,y,px,py){
 const o=mirrorOptions(a),w=a.width*px,h=a.height*py,fill={black:'#25272a',white:'#f5f5f0',nickel:'#b8b6af',brass:'#c4a568'},light={warm:'#fff0bc',neutral:'#fffbef',cool:'#e4f3ff'}[o.light_color],cy=y+h/2;
 const shape=(inset,attrs)=>{const ww=(a.width-2*inset)*px,hh=(a.height-2*inset)*py,xx=x-ww/2,yy=cy-hh/2;if(ww<=0||hh<=0)return '';
  if(a.shape==='oval')return `<ellipse cx="${x}" cy="${cy}" rx="${ww/2}" ry="${hh/2}" ${attrs}/>`;
  if(a.shape==='arch'){const ry=(a.width/2-inset)*py;return `<path d="M${xx} ${yy+hh}V${yy+ry}A${ww/2} ${ry} 0 0 1 ${xx+ww} ${yy+ry}V${yy+hh}Z" ${attrs}/>`;}
  const r=a.shape==='rounded'?Math.min(a.width-2*inset,a.height-2*inset)*.12:0;
  return `<rect x="${xx}" y="${yy}" width="${ww}" height="${hh}" rx="${r*px}" ry="${r*py}" ${attrs}/>`;
 };
 const inset=o.frame?o.frame_width:0;
 const halo=o.back_light?`<g data-mirror-back-light="true">${shape(-.5,`fill="${light}" opacity=".45" stroke="${light}" stroke-width="5"`)}${shape(-.15,`fill="${light}" opacity=".75"`)}</g>`:'';
 const frame=o.frame?`<g data-mirror-frame="${o.frame_color}">${shape(0,`fill="${fill[o.frame_color]}" stroke="#647078" stroke-width=".5"`)}</g>`:'';
 const led=o.front_light?`<g data-mirror-front-light="true">${shape(inset+.5,`fill="${light}"`)}${shape(inset+.75,'fill="#c9dfe3"')}</g>`:'';
 return `<g data-preview-accessory="${i}" data-kind="mirror">${halo}${frame}${shape(inset,'fill="#c9dfe3" stroke="#647f82" stroke-width=".5"')}${led}<path d="M${x-w*.25} ${y+h*.65}l${w*.35} -${h*.3}" stroke="white" opacity=".65" stroke-width="2"/></g>`;
}
function escapeAccessory(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function syncAccessoryControls(){
 normalizeLightLinks();
 const count=Number(el('basins').value);el('faucetBasin').options[1].hidden=count<2;
 if(activeFaucetBasin>=count)chooseBasinFaucet(0);
 el('accessorySettings').hidden=el('product').value!=='vanity'||current()?.product_id==='gallery';
 const key=JSON.stringify([accessoryItems.map(a=>[a.kind,a.mirror_ref??-1]),columns.length,lightingCatalog]);
 if(key===accessoryControlKey)return;accessoryControlKey=key;
 const options=columns.map((_,i)=>`<option value="${i}">חלק ${i+1} (משמאל)</option>`).join('');
 el('accessoryControls').innerHTML=accessoryItems.map((a,i)=>`<fieldset data-accessory="${i}" style="margin-top:12px;border:1px solid #d3ddd5;border-radius:8px"><legend>${a.kind==='mirror'?'מראה':'מנורה'} ${i+1}</legend><label>מעל חלק<select data-key="part">${options}</select></label>${a.kind==='mirror'?'<label>צורה<select data-key="shape"><option value="rectangle">מלבנית</option><option value="rounded">מלבנית עם פינות מעוגלות</option><option value="oval">עגולה / אובלית</option><option value="arch">קשת</option></select></label>':`<label>מגלריית החשמל<select data-key="product">${lightingCatalog.map(p=>`<option value="${escapeAccessory(p.name)}">${escapeAccessory(p.name)}</option>`).join('')}</select></label>`}<div class="row">${[['width','רוחב'],['height','גובה'],['above','תחתית מעל משטח'],['offset','הזזה ימינה (+) / שמאלה (−)']].map(([k,label])=>`<label>${label}<input data-key="${k}" type="number" step="0.125" value="${a[k]}"></label>`).join('')}</div>${a.kind==='mirror'?mirrorControls(mirrorOptions(a)):lightLinkControls(a)}<button type="button" data-remove="${i}">הסר ${a.kind==='mirror'?'מראה':'מנורה'}</button></fieldset>`).join('');
 el('accessoryControls').querySelectorAll('[data-accessory]').forEach(field=>{
  const a={mirror_ref:-1,mirror_side:'right',mirror_gap:3,height_offset:0,...mirrorOptions(accessoryItems[Number(field.dataset.accessory)])};field.querySelectorAll('[data-key]').forEach(e=>{if(e.type==='checkbox')e.checked=a[e.dataset.key];else e.value=a[e.dataset.key];e.disabled=a.kind==='light'&&a.mirror_ref>=0&&['part','above','offset'].includes(e.dataset.key);if(e.disabled)e.closest('label').hidden=true;});
 });
}
function accessorySvg(v){
 const px=300/v.width,py=150/v.height,layout=columnLayout(columns,v.width);
 return (v.accessories||[]).map((a,i)=>{
  const row=layout[a.part];if(!row&&!(a.kind==='light'&&(a.mirror_ref??-1)>=0))return '';
  const pos=accessoryPosition(a,v);const x=pos.x*px+18,w=a.width*px,h=a.height*py,y=-50-(v.surfaces.countertop_thickness+pos.above+a.height)*py;
  if(a.kind==='light'){
   if(lightMirrorOverlap(a,v))return '';
   const product=lightingCatalog.find(p=>p.name===a.product);
   return `<g data-preview-accessory="${i}" data-kind="light"><rect x="${x-w/2}" y="${y}" width="${w}" height="${h}" fill="#eee6cc" opacity=".2"/><image href="${escapeAccessory(product?.image||'')}" x="${x-w/2}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="none"/></g>`;
  }
  return mirrorSvg(a,i,x,y,px,py);
 }).join('');
}
document.addEventListener('DOMContentLoaded',()=>{
 el('accessoryControls').addEventListener('input',event=>{
  const e=event.target,field=e.closest('[data-accessory]');if(!field||!e.dataset.key)return;
  const key=e.dataset.key;accessoryItems[Number(field.dataset.accessory)][key]=e.type==='checkbox'?e.checked:['shape','product','frame_color','light_color','mirror_side'].includes(key)?e.value:Number(e.value);update();
 });
 el('accessoryControls').addEventListener('click',event=>{
  const e=event.target.closest('[data-remove]');if(!e)return;removeAccessory(Number(e.dataset.remove));
 });
});

function setThinMirrorFrame(button){const i=Number(button.closest("[data-accessory]").dataset.accessory);accessoryItems[i].frame=true;accessoryItems[i].frame_width=.125;accessoryControlKey="";update();}
function lightLinkControls(a){return `<label>מיקום ביחס למראה<select data-key="mirror_ref">${accessoryItems.some(m=>m.kind==='mirror')?'':'<option value="-1">ללא מראה · מיקום לפי חלק</option>'}${accessoryItems.map((m,i)=>m.kind==='mirror'?`<option value="${i}">מראה ${i+1} · חלק ${m.part+1}</option>`:'').join('')}</select></label><div class="row"><label>צד<select data-key="mirror_side"><option value="right">מימין למראה</option><option value="left">משמאל למראה</option><option value="above">מעל המראה</option></select></label><label>מרווח בין הקצוות (אינץ׳)<input type="number" data-key="mirror_gap" min="0" max="60" step="0.125" value="${a.mirror_gap??3}"></label><label>התאמת גובה (+ למעלה / − למטה)<input type="number" data-key="height_offset" min="-100" max="100" step="0.125" value="${a.height_offset??0}"></label></div><p class="caption">בצדדים: מרכז המנורה מול מרכז המראה. מעל: המרווח מתחתית המנורה. לאחר שיוך, המנורה עוקבת אחרי המראה.</p>`;}
function accessoryPosition(a,v){
 const layout=columnLayout(columns,v.width),row=layout[a.part];
 const manual={x:(row?.x||0)+(row?.width||0)/2+a.offset,above:a.above};
 const ref=a.mirror_ref??-1,m=accessoryItems[ref];if(a.kind!=='light'||ref<0||m?.kind!=='mirror')return manual;
 const p=accessoryPosition(m,v),gap=a.mirror_gap??3,side=a.mirror_side||'right';
 return {x:p.x+(side==='above'?0:(side==='left'?-1:1)*(m.width/2+gap+a.width/2)),above:(side==='above'?p.above+m.height+gap:p.above+m.height/2-a.height/2)+(a.height_offset??0)};
}
function removeAccessory(index){
 const v=values();accessoryItems.forEach(a=>{if(a.kind!=='light')return;const ref=a.mirror_ref??-1;
  if(ref===index){const p=accessoryPosition(a,v),m=accessoryItems[index],row=columnLayout(columns,v.width)[m.part];a.part=m.part;a.above=p.above;a.offset=p.x-row.x-row.width/2;a.mirror_ref=-1;}
  else if(ref>index)a.mirror_ref=ref-1;
 });accessoryItems.splice(index,1);accessoryControlKey='';update();
}
function nearestMirror(part){const matches=accessoryItems.map((m,i)=>({m,i})).filter(r=>r.m.kind==='mirror');return (matches.find(r=>r.m.part===part)||matches[0])?.i??-1;}
function normalizeLightLinks(){
 accessoryItems.forEach(a=>{if(a.kind!=='light')return;
  if(accessoryItems[a.mirror_ref]?.kind!=='mirror'){
   const ref=nearestMirror(a.part);if(ref<0)return;
   Object.assign(a,{mirror_ref:ref,mirror_side:'above',mirror_gap:3,height_offset:0});
  }
 });
}
function addSideLights(){
 const ref=nearestMirror(selectedColumn);if(ref<0){showError('הוסף מראה לפני הוספת זוג מנורות');return;}
 if(!lightingCatalog.length){showError('אין מנורות קיר זמינות בגלריית החשמל');return;}
 if(accessoryItems.length>16){showError('אפשר להוסיף עד 18 פריטים');return;}
 const source=accessoryItems.find(a=>a.kind==='light'&&a.mirror_ref===ref);
 for(const side of ['left','right'])accessoryItems.push({...source,kind:'light',part:accessoryItems[ref].part,width:source?.width||6,height:source?.height||16,above:12,offset:0,product:source?.product||lightingCatalog[0].name,mirror_ref:ref,mirror_side:side,mirror_gap:source?.mirror_gap??3,height_offset:0});
 accessoryControlKey='';showError('');update();
}
function lightMirrorOverlap(a,v){
 if((a.mirror_ref??-1)>=0&&a.mirror_side==='above'&&(a.mirror_gap??3)+(a.height_offset??0)<0)return true;
 const p=accessoryPosition(a,v);
 return accessoryItems.filter(m=>m.kind==='mirror').some(m=>{const q=accessoryPosition(m,v);return Math.abs(p.x-q.x)<(a.width+m.width)/2-1e-6&&Math.abs(p.above+a.height/2-q.above-m.height/2)<(a.height+m.height)/2-1e-6;});
}
function checkLightClearance(){
 const v=values(),invalid=accessoryItems.some(a=>a.kind==='light'&&lightMirrorOverlap(a,v)),e=el('lightClearanceError');
 if(e){e.hidden=!invalid;e.textContent=invalid?'אין מקום למנורה במיקום הזה — היא חופפת למראה ולא תוצג או תוצב. שנה צד, מרווח או גובה.':'';}
 return !invalid;
}
