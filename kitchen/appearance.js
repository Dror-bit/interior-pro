/* 2D display/mock counterpart; Ruby Appearance is authoritative on commit. */
(function(root){
  const appliance=c=>['fridge','oven','wall_oven','dishwasher','hood','microwave'].includes(c.kind);
  const overrides=c=>c.appearance_overrides??{finish:c.finish,handle:c.handle};
  function resolve(c,s){
    if(appliance(c))return c;
    const o=overrides(c),handle=s.global_handle_type==='none'?'none':s.global_handle_color||'brass';
    return {...c,appearance_overrides:{...o},finish:o.finish??(s.global_finish||'ivory'),handle:['filler','corner'].includes(c.kind)?'none':o.handle??handle};
  }
  root.KitchenAppearance={overrides,resolve};
})(globalThis);
