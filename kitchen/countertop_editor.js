(()=>{
 if(document.getElementById('countertopMaterialButton'))return;
 const section=document.createElement('section');section.className='wide';section.id='countertopEditor';
 section.innerHTML='<h2>Countertop · entire kitchen</h2><button type="button" id="countertopMaterialButton">Choose countertop material...</button><label>Countertop thickness (in)<input id="countertopThickness" type="number" min="0.25" max="6" step="0.125" value="1.5"></label><button type="button" id="applyCountertopThickness">Apply thickness</button><h3>Island countertop</h3><label><input type="checkbox" id="islandCountertopMatch" style="width:auto">Same material as kitchen</label><button type="button" id="islandCountertopMaterial">Choose island material...</button>';
 document.getElementById('cabinetControls').prepend(section);
 document.getElementById('applyCountertopThickness').onclick=()=>sendCommands([{type:'update_settings',payload:{countertop_thickness:Number(document.getElementById('countertopThickness').value)}}]);
 const match=document.getElementById('islandCountertopMatch'),island=document.getElementById('islandCountertopMaterial');
 document.getElementById('countertopMaterialButton').onclick=()=>sketchup.countertop_materials('kitchen');
 island.onclick=()=>sketchup.countertop_materials('island');
 match.onchange=()=>{if(match.checked)sendCommands([{type:'update_settings',payload:{island_countertop_material:null}}]);else sketchup.countertop_materials('island');};
 const receive=window.receiveKitchen;window.receiveKitchen=function(data){const result=receive.apply(this,arguments);match.checked=!kitchenSettings.island_countertop_material;document.getElementById('countertopThickness').value=kitchenSettings.countertop_thickness??1.5;return result;};
})();
