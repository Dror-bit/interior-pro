(()=>{
 if(document.getElementById('countertopMaterialButton'))return;
 const section=document.createElement('section');section.className='wide';
 section.innerHTML='<h2>Countertop · entire kitchen</h2><button type="button" id="countertopMaterialButton">Choose countertop material...</button><h3>Island countertop</h3><label><input type="checkbox" id="islandCountertopMatch" style="width:auto">Same material as kitchen</label><button type="button" id="islandCountertopMaterial">Choose island material...</button>';
 document.getElementById('cabinetControls').prepend(section);
 const match=document.getElementById('islandCountertopMatch'),island=document.getElementById('islandCountertopMaterial');
 document.getElementById('countertopMaterialButton').onclick=()=>sketchup.countertop_materials('kitchen');
 island.onclick=()=>sketchup.countertop_materials('island');
 match.onchange=()=>{if(match.checked)sendCommands([{type:'update_settings',payload:{island_countertop_material:null}}]);else sketchup.countertop_materials('island');};
 const receive=window.receiveKitchen;window.receiveKitchen=function(data){const result=receive.apply(this,arguments);match.checked=!kitchenSettings.island_countertop_material;return result;};
})();
