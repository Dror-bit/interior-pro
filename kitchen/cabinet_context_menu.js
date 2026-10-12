// Double-click retains single-cabinet editing; layout commands live in the sidebar.
$('drawing').addEventListener('dblclick',e=>{const cab=e.target.closest('.cab');if(!cab||busy||e.ctrlKey||e.metaKey||e.shiftKey)return;e.preventDefault();if(typeof CabinetSelection!=='undefined'&&CabinetSelection.multiple)return;if(cabinetDialog.open)return;choose(cab.dataset.id);openCabinetEditor();});
