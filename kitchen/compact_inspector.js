// Keep dimensions with the cabinet editor, rather than repeating an inspector in the sidebar.
const cabinetSizePanel=document.createElement('section');cabinetSizePanel.id='cabinetSizePanel';
cabinetSizePanel.innerHTML='<h2>Cabinet size</h2><div class="fields" id="cabinetSizeFields"></div><details style="margin-top:12px"><summary style="cursor:pointer">Position details</summary><div class="fields" id="cabinetPositionFields" style="margin-top:8px"></div></details>';
$('cabinetControls').prepend(cabinetSizePanel);
for(const id of ['preset','width','height','depth','wall','x','z']){
 const input=$(id);input.setAttribute('form','form');$( ['wall','x','z'].includes(id)?'cabinetPositionFields':'cabinetSizeFields').append(input.closest('label'));
}
dimsTitle.remove();$('apply').hidden=true;
