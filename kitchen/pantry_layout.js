/* Inch-based section contract shared with kitchen_pantry.rb. */
const PantryLayouts={
 defaults(){return {version:1,top:'double',middle:'double',bottom:'combo_double',bottom_height:28,middle_height:30,drawers:3};},
 fits(a,c,height,category){
  if(!a||a.category!==category||!['microwave','wall_oven'].includes(category)||a.appearance?.door==='drawer'||['over_range','under_counter'].includes(a.appearance?.installation))return false;
  const d=a.dimensions,k=a.cutout;
  return [d,k].every(v=>v&&['width','height','depth'].every(key=>Number.isFinite(v[key])&&v[key]>0))&&k.width<=c.width-1.5+.0001&&k.depth<=c.depth-.5+.0001&&k.height<=height&&d.width<=c.width-.25+.0001&&d.height<=height;
 },
 rows(c){
  const p=c.pantry;
  if(!p||p.version!==1)throw Error('Invalid pantry settings');
  if(!['single','double','lift'].includes(p.top)||!['single','double','microwave','wall_oven'].includes(p.middle)||!['combo_single','combo_double','drawers'].includes(p.bottom))throw Error('Invalid pantry section');
  const lower=Number(p.bottom_height),middle=Number(p.middle_height),upper=c.height-(c.toe_height??4)-.5-lower-middle;
  if(![lower,middle,upper].every(v=>Number.isFinite(v)&&v>=8))throw Error('Each pantry section must be at least 8 inches high');
  const out=[{kind:'doors',doors:p.top==='double'?2:1,height:upper,zone:'top',opening:p.top==='lift'?'lift':'swing'}];
  if(['microwave','wall_oven'].includes(p.middle)){
   if(!this.fits(p.appliance,c,middle,p.middle))throw Error('Choose a compatible appliance for the middle section');
   out.push({kind:'appliance',height:middle,width:p.appliance.dimensions.width,device:p.middle,pantry_appliance:p.appliance,zone:'middle'});
  }else out.push({kind:'doors',height:middle,doors:p.middle==='double'?2:1,zone:'middle'});
  if(p.bottom==='drawers'){
   const n=Number(p.drawers);
   if(!Number.isInteger(n)||n<1||n>5)throw Error('Choose 1 to 5 lower drawers');
   const heights=p.drawer_heights??Array(n).fill((lower-.125*(n-1))/n);
   if(!Array.isArray(heights)||heights.length!==n)throw Error('Provide one height for each lower drawer');
   if(!heights.every(v=>Number.isFinite(v)&&v>=3))throw Error('Lower drawers must be at least 3 inches high');
   if(Math.abs(heights.reduce((a,b)=>a+b,0)+.125*(n-1)-lower)>=.005)throw Error('Drawer heights plus reveals must fill the bottom section');
   for(const height of heights)out.push({kind:'drawer',height,zone:'bottom'});
  }else{
   if(lower<14)throw Error('Lower section needs 14 inches for a drawer and doors');
   out.push({kind:'drawer',height:5.875,zone:'bottom'},{kind:'doors',height:lower-6,doors:p.bottom==='combo_double'?2:1,zone:'bottom'});
  }
  return out;
 }
};
