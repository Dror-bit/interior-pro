function arrangeVanityEditor(){
 if(document.getElementById('vanityWorkspace'))return;
 const main=document.querySelector('main'),preview=el('preview'),caption=preview.nextElementSibling;
 const workspace=document.createElement('div');workspace.id='vanityWorkspace';
 const visual=document.createElement('section');visual.id='vanityVisual';visual.setAttribute('aria-label','תצוגה קבועה');
 const controls=document.createElement('section');controls.id='vanityControls';controls.setAttribute('aria-label','הגדרות הוונטי');
 const nodes=[...main.children];visual.append(preview);if(caption?.classList.contains('caption'))visual.append(caption);
 const pending=el('pendingChanges');if(pending)visual.append(pending);
 nodes.forEach(node=>{if(node.parentElement===main)controls.append(node)});
 workspace.append(visual,controls);main.append(workspace);
}
document.addEventListener('DOMContentLoaded',arrangeVanityEditor);
