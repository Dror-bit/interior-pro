(()=>{
 if(document.getElementById('backsplashEditor'))return;
 const section=document.createElement('section');section.id='backsplashEditor';section.className='wide';
 section.innerHTML='<h2>Backsplash · entire kitchen</h2><label>Covering<select id="backsplashMode"><option value="none">None</option><option value="countertop">Match countertop</option><option value="tile">Tile</option></select></label><div id="backsplashFields"><label>Height above countertop ″<input id="backsplashHeight" type="number" min="1" max="60" step="0.25" value="18"></label><label>Thickness ″<input id="backsplashThickness" type="number" min="0.125" max="2" step="0.125" value="0.75"></label><div id="backsplashTile"><div class="fields"><label>Tile width ″<input id="backsplashTileWidth" type="number" min="1" max="48" value="6"></label><label>Tile height ″<input id="backsplashTileHeight" type="number" min="1" max="48" value="3"></label><label>Grout ″<input id="backsplashGrout" type="number" min="0.03125" max="0.5" step="0.03125" value="0.125"></label></div><button id="backsplashMaterial" type="button" class="subtle">Choose tile material…</button></div></div><button type="button" id="applyKitchenBacksplash">Apply backsplash to entire kitchen</button>';
 document.getElementById('cabinetControls').prepend(section);
 const field=id=>document.getElementById(id);
 function eligible(c){return c&&!c.surround_for&&(['doors','drawers','sink','dishwasher','filler','corner','corner_base','corner_lazy'].includes(c.kind)||(c.kind==='microwave'&&(c.appliance?.appearance?.door==='drawer'||c.appliance?.appearance?.installation==='under_counter')));}
 function visible(){field('backsplashFields').hidden=field('backsplashMode').value==='none';field('backsplashTile').hidden=field('backsplashMode').value!=='tile';}
 function draft(){const b={...(kitchenSettings.backsplash||{}),mode:field('backsplashMode').value};for(const [key,id] of [['height','Height'],['thickness','Thickness'],['tile_width','TileWidth'],['tile_height','TileHeight'],['grout','Grout']])b[key]=Number(field('backsplash'+id).value);return b;}
 const prevFill=fill;fill=function(...args){prevFill(...args);section.hidden=!eligible(selected);const b=kitchenSettings.backsplash||{};field('backsplashMode').value=b.mode||'none';for(const [key,id,def] of [['height','Height',18],['thickness','Thickness',0.75],['tile_width','TileWidth',6],['tile_height','TileHeight',3],['grout','Grout',0.125]])field('backsplash'+id).value=b[key]??def;visible();};
 field('applyKitchenBacksplash').onclick=()=>{if(!busy)sendCommands([{type:'update_settings',payload:{backsplash:draft()}}]);};
 field('backsplashMode').onchange=()=>{field('backsplashThickness').value=field('backsplashMode').value==='tile'?0.375:0.75;visible();};
 field('backsplashMaterial').onclick=()=>{if(selected&&!busy)sketchup.backsplash_materials(selected.id,JSON.stringify(draft()));};
 visible();
})();
