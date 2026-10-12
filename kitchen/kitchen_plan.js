/* House-canvas overlay. Uses the host's world-inch projection. */
(function () {
  if (window.KP) return;
  let cabinets = [];
  window.KP = {
    load(payload) { cabinets = payload.cabinets || []; draw(); },
    hit(x,y) {
      return [...cabinets].reverse().find(c=>{
        let inside=false;const p=c.polygon;
        for(let i=0,j=p.length-1;i<p.length;j=i++){
          if(((p[i][1]>y)!==(p[j][1]>y))&&(x<(p[j][0]-p[i][0])*(y-p[i][1])/(p[j][1]-p[i][1])+p[i][0]))inside=!inside;
        }
        return inside;
      });
    },
    draw() {
      if (typeof activePage === 'undefined' || activePage !== 0) return;
      ctx.save();
      try {
        ctx.fillStyle = '#d4d8d2';
        ctx.strokeStyle = '#657367';
        ctx.lineWidth = 1;
        ctx.setLineDash([]);
        for (const cabinet of cabinets) {
          const polygon = cabinet.polygon;
          if (!polygon || polygon.length < 3) continue;
          ctx.beginPath();
          polygon.forEach((point, i) => {
            if (i === 0) ctx.moveTo(sx(point[0]), sy(point[1]));
            else ctx.lineTo(sx(point[0]), sy(point[1]));
          });
          ctx.closePath(); ctx.fill(); ctx.stroke();
        }
      } finally { ctx.restore(); }
    }
  };
  // Keep one host history and one keyboard route; only kitchen model entries
  // use the direct native Undo callback (independent of window focus).
  if(typeof histUndo==='function'){
    const hostUndo=histUndo;
    histUndo=function(){
      if(editHist.length&&editHist[editHist.length-1].what==='kitchen'&&typeof sketchup.kitchen_undo==='function'){
        editHist.pop();sketchup.kitchen_undo();return true;
      }
      return hostUndo.apply(this,arguments);
    };
  }
  if(typeof cv!=='undefined')cv.addEventListener('dblclick',event=>{
    if(activePage!==0||mode!=='sel'||event.ctrlKey||event.shiftKey||event.metaKey)return;
    const p={x:mx(event.offsetX),y:my(event.offsetY)};
    if(typeof hitDim==='function'&&hitDim(p))return;
    const cabinet=window.KP.hit(p.x,p.y);
    if(!cabinet||typeof sketchup.kitchen_edit_cabinet!=='function')return;
    event.preventDefault();event.stopImmediatePropagation();
    sketchup.kitchen_edit_cabinet(cabinet.id);
  },true);
})();
