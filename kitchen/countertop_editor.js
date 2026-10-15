(()=>{
 if(document.getElementById('countertopMaterialButton'))return;
 const section=document.createElement('section');section.className='wide';
 section.innerHTML='<h2>Countertop · entire kitchen</h2><button type="button" class="subtle" id="countertopMaterialButton">Choose Interior Pro material…</button>';
 document.getElementById('cabinetControls').prepend(section);
 document.getElementById('countertopMaterialButton').onclick=()=>sketchup.countertop_materials();
})();
