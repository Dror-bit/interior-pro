/* Labels must never turn the empty space beside a cabinet into a hit target. */
function containPlanLabels(target){
 const ns='http://www.w3.org/2000/svg';
 for(const group of target.querySelectorAll('.cab')){
  const outline=group.querySelector('polygon');if(!outline)continue;
  const id='plan-label-'+target.id+'-'+group.dataset.id;
  const clip=document.createElementNS(ns,'clipPath');clip.id=id;clip.setAttribute('clipPathUnits','userSpaceOnUse');
  const boundary=document.createElementNS(ns,'polygon');boundary.setAttribute('points',outline.getAttribute('points'));clip.append(boundary);
  const defs=document.createElementNS(ns,'defs');defs.append(clip);group.prepend(defs);
  const title=document.createElementNS(ns,'title');title.textContent=group.querySelector('text')?.textContent||'';group.prepend(title);
  for(const label of group.querySelectorAll('text')){label.setAttribute('pointer-events','none');label.setAttribute('clip-path','url(#'+id+')');}
 }
}
const drawPlanBeforeContainedLabels=drawPlan;
drawPlan=function(...args){drawPlanBeforeContainedLabels(...args);containPlanLabels(args[1]||$('drawing'));};
if(mode==='top')draw();
