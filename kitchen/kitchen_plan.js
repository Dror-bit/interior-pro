/* House-canvas overlay. Uses the host's world-inch projection. */
(function () {
  if (window.KP) return;
  let cabinets = [];
  window.KP = {
    load(payload) { cabinets = payload.cabinets || []; draw(); },
    hit(x,y) {
      const rows=[...cabinets].reverse().filter(c=>Array.isArray(c.polygon)&&c.polygon.length>=3);
      const exact=rows.find(c=>{
        let inside=false;const p=c.polygon;
        for(let i=0,j=p.length-1;i<p.length;j=i++){
          if(((p[i][1]>y)!==(p[j][1]>y))&&(x<(p[j][0]-p[i][0])*(y-p[i][1])/(p[j][1]-p[i][1])+p[i][0]))inside=!inside;
        }
        return inside;
      });
      if(exact)return exact;
      // Fixed screen-space tolerance keeps thin panels selectable at every zoom.
      const px=sx(x),py=sy(y);let nearest=null,best=7*7;
      for(const row of rows){const p=row.polygon;
        for(let i=0,j=p.length-1;i<p.length;j=i++){
          const ax=sx(p[j][0]),ay=sy(p[j][1]),dx=sx(p[i][0])-ax,dy=sy(p[i][1])-ay;
          const len=dx*dx+dy*dy,t=len?Math.max(0,Math.min(1,((px-ax)*dx+(py-ay)*dy)/len)):0;
          const distance=(px-ax-t*dx)**2+(py-ay-t*dy)**2;
          if(distance<=best&&(!nearest||distance<best)){best=distance;nearest=row;}
        }
      }
      return nearest;
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
  // Kitchen edits use histModel('kitchen') and the unchanged host histUndo.
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
