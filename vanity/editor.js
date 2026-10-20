let doc={revision:0,cabinets:[]};
const el=id=>document.getElementById(id);
const numeric=['width','depth','height','support_height'];
const strings=['mount','style','finish','handle'];
function showError(message){el('error').textContent=message;}
function values(){let v={};numeric.forEach(k=>v[k]=Number(el(k).value));strings.forEach(k=>v[k]=el(k).value);v.legs=el('legs').checked;v.drawer=el('product').value==='makeup'&&el('drawer').checked;v.basins=el('product').value==='makeup'?0:Number(el('basins').value);v.position={};['x','y','z','angle'].forEach(k=>v.position[k]=Number(el(k).value));return v;}
function render(source,gallery){const selected=el('list').value;doc=source;el('list').replaceChildren(new Option('New cabinet',''));doc.cabinets.forEach(c=>el('list').add(new Option(c.product_id+' · '+c.id,c.id)));el('list').value=doc.cabinets.some(c=>c.id===selected)?selected:'';el('gallery').replaceChildren();gallery.forEach(a=>el('gallery').add(new Option(a.name,a.id)));if(el('list').value)choose();}
function choose(){const c=doc.cabinets.find(c=>c.id===el('list').value);const imported=!!c&&c.product_id==='gallery';[...numeric,...strings,'legs','drawer','basins'].forEach(k=>el(k).disabled=imported);el('product').disabled=!!c;if(!c)return;if(!imported)el('product').value=c.product_id;numeric.concat(strings).forEach(k=>el(k).value=c[k]);el('legs').checked=c.legs;el('drawer').checked=c.drawer;el('basins').value=c.basins;['x','y','z','angle'].forEach(k=>el(k).value=c.position[k]);}
function send(action){const selected=doc.cabinets.find(c=>c.id===el('list').value);let v=values();if(action==='save'&&selected&&selected.product_id==='gallery')v={position:v.position};const p={action,revision:doc.revision,id:el('list').value,product:el('product').value,values:v,asset_id:el('gallery').value,name:el('gallery_name').value};sketchup.action(JSON.stringify(p));}
el('mount').addEventListener('change',()=>{if(el('mount').value==='floating'){el('legs').checked=false;if(Number(el('z').value)<=0)el('z').value=12;}else el('z').value=0;});
document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
