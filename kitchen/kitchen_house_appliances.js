(function(){
 if(window.KitchenHouseAppliances)return;
 const categories={sink:'Sinks',fridge:'Refrigerators',range:'Ranges',dishwasher:'Dishwashers',cooktop:'Cooktops',wall_oven:'Wall ovens',hood:'Hoods',microwave:'Microwaves'};
 const kinds={sink:'sink',fridge:'fridge',oven:'range',dishwasher:'dishwasher',hood:'hood',microwave:'microwave',wall_oven:'wall_oven'};
 const section=document.getElementById('kp-kitchen'),library=document.getElementById('kp-cab-library');
 const panel=document.createElement('div');panel.id='kp-appliance-library';panel.hidden=true;
 panel.innerHTML='<button type="button" id="kp-appliance-back">← Cabinets</button><label>Appliances<select id="kp-appliance-category"></select></label><label>Brand<select id="kp-appliance-brand"></select></label><div id="kp-appliance-cards"></div>';
 section.append(panel);
 const category=panel.querySelector('#kp-appliance-category'),brand=panel.querySelector('#kp-appliance-brand'),cards=panel.querySelector('#kp-appliance-cards');
 const withoutLabel=document.createElement('label');withoutLabel.id='kp-without-cabinet-label';withoutLabel.style.cssText='display:flex;align-items:center;gap:7px';
 const without=document.createElement('input');without.type='checkbox';without.id='kp-without-cabinet';without.style.width='auto';
 withoutLabel.append(without,document.createTextNode('ללא ארון'));cards.before(withoutLabel);
 const coverLabel=document.createElement('label');coverLabel.textContent='Hood cover';coverLabel.id='kp-hood-cover-label';
 const cover=document.createElement('select');cover.id='kp-hood-cover-style';cover.add(new Option('Shaker','shaker'));cover.add(new Option('Plain','slab'));coverLabel.append(cover);cards.before(coverLabel);
 cover.onchange=()=>window.KitchenHouseInsert.cancel();
 without.onchange=()=>{if(!window.KitchenHouseInsert.cancel())without.checked=!without.checked;};
 for(const [key,label] of Object.entries(categories))category.add(new Option(label,key));
 const cache=new Map();let current=[];
 const error=message=>{document.getElementById('kp-cab-error').textContent=message||'';};
 function render(){
  cards.replaceChildren();
  for(const product of current.filter(p=>p.brand===brand.value)){
   const button=document.createElement('button');button.type='button';button.className='kp-appliance-card';button.dataset.productId=product.id;
   if(product.image){const img=document.createElement('img');img.src=product.image;img.alt=product.model;button.append(img);}
   const title=document.createElement('strong');title.textContent=product.model;button.append(title);
   const name=document.createElement('span');name.textContent=product.name;button.append(name);
   if(product.dimensions){const size=document.createElement('span');size.textContent=`${product.sku||product.model} · ${product.dimensions.width}″ W × ${product.dimensions.depth}″ D × ${product.dimensions.height}″ H`;button.append(size);}
   if(product.automatic_cutout_available===false){const status=document.createElement('span');status.textContent='Automatic countertop cutout unavailable — awaiting verified manufacturer template.';button.append(status);}
   button.onclick=()=>{
    if(window.KitchenHouseInsert.state.pending||window.KitchenHouseInsert.state.waiting)return;
    error('');const request_id=window.KitchenHouseInsert.request();
    sketchup.kitchen_open_catalog(JSON.stringify({action:'prepare',request_id,product_id:product.id,without_cabinet:without.checked,hood_style:cover.value,wall:document.getElementById('kp-cab-area').value}));
   };cards.append(button);
  }
 }
 function receive(key,products){
  cache.set(key,products);if(category.value!==key||panel.hidden)return;
  current=products;const previous=brand.value,brands=[...new Set(products.map(p=>p.brand))];brand.replaceChildren(...brands.map(b=>new Option(b,b)));
  if(brands.includes(previous))brand.value=previous;render();
 }
 function choose(){
  if(!window.KitchenHouseInsert.cancel())return;
  without.checked=false;withoutLabel.style.display=['fridge','microwave','wall_oven','hood'].includes(category.value)?'flex':'none';
  coverLabel.style.display=category.value==='hood'?'grid':'none';cover.value='shaker';
  error('');cards.replaceChildren();brand.replaceChildren();
  if(cache.has(category.value))receive(category.value,cache.get(category.value));else sketchup.kitchen_appliance_library(category.value);
 }
 function open(key='range'){
  if(window.KitchenHouseInsert.state.pending)return;
  library.hidden=true;panel.hidden=false;category.value=key;choose();
 }
 panel.querySelector('#kp-appliance-back').onclick=()=>{if(!window.KitchenHouseInsert.cancel())return;panel.hidden=true;library.hidden=false;error('');};
 category.onchange=choose;brand.onchange=()=>{if(window.KitchenHouseInsert.cancel())render();};
 library.addEventListener('click',event=>{const tile=event.target.closest('button[data-kind]'),key=tile&&kinds[tile.dataset.kind];if(!key)return;event.preventDefault();event.stopImmediatePropagation();open(key);},true);
 const entry=document.createElement('button');entry.type='button';entry.id='kp-manufacturer-appliances';entry.textContent='Appliance models';entry.onclick=()=>open();library.prepend(entry);
 const style=document.createElement('style');style.textContent='#kp-appliance-library[hidden],#kp-cab-library[hidden]{display:none!important}#kp-appliance-library{display:grid;gap:12px}#kp-appliance-cards{display:grid;gap:10px}.kp-appliance-card{display:flex;flex-direction:column;align-items:center;gap:6px;background:#fafbf8;border:1px solid #dce3da;border-radius:8px;padding:12px;color:#365446;text-align:center}.kp-appliance-card:hover{border-color:#71967e;background:#edf4ea}.kp-appliance-card img{width:100%;height:145px;object-fit:contain}.kp-appliance-card strong{font-size:13px}.kp-appliance-card span{font-size:12px}#kp-manufacturer-appliances{width:100%;margin-top:10px;padding:10px}';document.head.append(style);
 window.KitchenHouseAppliances={open,receive,fail:error};
})();
