/* Coordinate queries only. Creation and validation stay in the shared Ruby engine. */
const KitchenPointPlacement={
 localPoint(world,pose){return KitchenPlacement.rotate(world[0]-pose.x,world[1]-pose.y,-pose.angle);},
 suggest(world){
  const [x,y]=this.localPoint(world,KitchenPlacement.pose);
  if(y<=0&&x>=0&&x<36&&-y>Math.abs(x))return 'B';
  if(x>=0&&Math.abs(y)<48)return 'A';
  return 'I';
 },
 command(world,area,kind,width,items){
  if(!Number.isFinite(width)||width<(kind==='filler'?.5:12)||width>60)throw Error('Check cabinet width.');
  if(area==='I'&&!items.some(c=>KitchenPlacement.wall(c)==='I')){
   const [x,y]=this.localPoint(world,KitchenPlacement.pose);
   return {type:'create_island_cabinet',payload:{kind,origin:{x:Math.round(x*8)/8,y:Math.round(y*8)/8,angle:0},overrides:{width}}};
  }
  let x=KitchenPlacement.along(area,...world);const clicked=x;
  const edges=items.filter(c=>KitchenPlacement.wall(c)===area).flatMap(c=>[c.x,c.x+c.width]);
  const near=edges.filter(edge=>Math.abs(edge-x)<=3).sort((a,b)=>Math.abs(a-x)-Math.abs(b-x))[0];
  x=near??Math.round(x*8)/8;
  if(x<0||x>1200)throw Error('Choose a point along the positive direction of this run.');
  return {type:'create_cabinet',payload:{kind,wall:area,fit_space_at:clicked,overrides:{x,width}}};
 }
};
if(typeof module!=='undefined')module.exports=KitchenPointPlacement;
