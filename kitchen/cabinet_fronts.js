/* Visible front dimensions in inches, top to bottom. Kept in sync with Ruby front_rows. */
const FrontLayouts={
 builtin(c){return ['oven_tower','micro_tower','fridge_surround'].includes(c.kind);},
 corner(c){return ['corner_base','corner_upper','corner_lazy'].includes(c.kind);},
 builtinDefaults(c){return {appliance_width:c.kind==='fridge_surround'?36:28,appliance_height:c.kind==='fridge_surround'?72:28,appliance_bottom:c.kind==='micro_tower'?24:28,microwave_height:18};},
 builtinRows(c){
  const d={...this.builtinDefaults(c),...c},w=d.appliance_width,ah=d.appliance_height;
  if(!Number.isFinite(w)||w<12||w>d.width-1.5)throw Error('Appliance width must fit between the ¾ inch side panels');
  if(!Number.isFinite(ah)||ah<12)throw Error('Appliance height must be at least 12 inches');
  const toe=d.kind==='fridge_surround'?0:(d.toe_height??4),available=d.height-toe-.25;
  const rows=[{kind:'appliance',height:ah,width:w,device:d.kind==='fridge_surround'?'fridge':'wall_oven'}];
  if(d.kind==='micro_tower'){
   if(!Number.isFinite(d.microwave_height)||d.microwave_height<10)throw Error('Microwave height must be at least 10 inches');
   rows.unshift({kind:'appliance',height:d.microwave_height,width:w,device:'microwave'});
  }
  if(d.kind!=='fridge_surround'){
   const lower=d.appliance_bottom-toe-.25;
   if(!Number.isFinite(lower)||lower<8)throw Error('Leave at least 8 inches below the appliance');
   rows.push({kind:'doors',height:lower,doors:2});
  }
  const upper=available-rows.reduce((s,r)=>s+r.height,0)-.125*rows.length;
  if(!Number.isFinite(upper)||upper<8)throw Error('Leave at least 8 inches for the upper doors. Increase cabinet height or lower the appliances.');
  return [{kind:'doors',height:upper,doors:2},...rows];
 },
 infer(c){return c.front_layout||(c.kind==='drawers'?'drawers':c.kind==='sink'?(c.width<24?'combo_single':'combo_double'):(c.width<24?'single':'double'));},
 toe(c){return ['wall','fridge_surround','corner_upper'].includes(c.kind)?0:(c.toe_height??4);},
 available(c){return c.height-this.toe(c)-.25;},
 heights(c){return c.drawer_heights|| (this.infer(c)==='drawers'?[.24,.36,.40].map(r=>(this.available(c)-.25)*r):[5.875]);},
 rows(c){
  if(this.corner(c))return [{kind:'doors',height:this.available(c),doors:1}];
  if(['filler','corner'].includes(c.kind))return [];
  if(this.builtin(c))return this.builtinRows(c);
  const layout=this.infer(c),available=this.available(c);
  if(!['single','double','drawers','combo_single','combo_double'].includes(layout))throw Error('Invalid front layout');
  if(['single','double'].includes(layout))return [{kind:'doors',height:available,doors:layout==='single'?1:2}];
  const heights=this.heights(c);
  if(!Array.isArray(heights)||heights.length<1||heights.length>6)throw Error('Choose 1 to 6 drawers');
  if(layout!=='drawers'&&heights.length!==1)throw Error('Combined layout uses one top drawer');
  if(heights.some(v=>!Number.isFinite(v)||v<3))throw Error('Each drawer front must be at least 3 inches high');
  const rows=heights.map(height=>({kind:'drawer',height}));
  if(layout==='drawers'){
   if(Math.abs(heights.reduce((a,b)=>a+b,0)+.125*(heights.length-1)-available)>=.005)throw Error('Drawer heights must fill the available front height');
  }else{
   const remaining=available-heights[0]-.125;
   if(remaining<8)throw Error('Leave at least 8 inches for the doors');
   rows.push({kind:'doors',height:remaining,doors:layout==='combo_single'?1:2});
  }
  return rows;
 }
};
