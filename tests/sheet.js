
          var DOC=null, STATE=null, PAGE=null, BOUNDS=null, SCALES=[];
          // Told by Ruby in the payload, never guessed here - see markTextH.
          var DIM_TEXT_H=5, DIM_LABEL_OFF=0.8;
          var URLS={};                // path -> file:/// address, for the sheet
          var MODE='hand';            // hand | dim | note | erase
          var ERA=null;               // which SITE line the rubber is over
          var PEND=null;              // the first point of a dimension
          // The second point, and then the dimension is not finished yet
          // (2026-08-19). A dimension tool in SketchUp, in LayOut and in Rayon
          // takes THREE clicks: what to measure from, what to measure to, and
          // then you pull the line off the wall and click to leave it there.
          //
          // Ours took two, and where the line sat was a separate job with a
          // separate tool afterwards - which is exactly the "צריך לעשות פעמיים
          // כדי להגיע לתוצאה פשוטה" the user called out, and exactly what the
          // "fewer clicks, always" rule in CLAUDE.md exists to stop.
          var PEND2=null;
          var PEND3=null;             // and the end of a note's shoulder
          var PENDOFF=0;              // how far off the wall, while he is choosing
          var HOVER=null;             // where the mouse is, in model inches
          var VIEW=null;              // how to get from the screen to the model
          var SEL=null;               // which mark is picked, by place in the list
          var EDIT=null;              // which note's words are open for changing
          var MDRAG=null;             // a mark being moved right now
          // CARRYING (2026-08-19). The user: "אני רוצה שהוא יזיז את הקו או כל
          // דבר אחר בלייב ואז עוד לחיצה זה יקבע אותם שם... מספיק עם העיגולים
          // הכחולים האלו."
          //
          // So a mark is not dragged with handles - it is PICKED UP by a click,
          // it follows the mouse, and the next click puts it down. SketchUp's
          // move tool, and Rayon's. Holding the button and dragging still works
          // for anyone who reaches for it; letting go without having moved is
          // what starts a carry.
          //
          // {i, part, at:[model x,y], snap:<the mark as it was>}
          var CARRY=null;
          // Everything picked, not just the last thing (2026-08-19). The user:
          // "כמו בסקאצ'אפ אני רוצה למתוח נגיד ריבוע לבחירת דברים ומחוק ביחד."
          // SEL stays the ONE that the panels talk about; SELS is the whole
          // pick, and Delete and carrying both work on all of it.
          var SELS=[];
          // The rubber band being pulled right now, in screen pixels.
          var BAND=null;
          var GRAB=10;                // how near the mouse has to be, in pixels
          // ...except for a MARK, which gets a much wider one (2026-08-19).
          //
          // MEASURED, not chosen. The user reported over three rounds that he
          // could not pick up or erase a dimension. The click probe wrote down
          // every press: they landed 11 to 43 pixels from the dimension line,
          // most of them 11-22. At GRAB=10 not one of them could ever have
          // caught. Nothing was broken - the target was a hair wide, on a
          // sheet 15,876 pixels across, with 1622 free lines lying over it for
          // the mouse to find instead.
          //
          // 26 catches every attempt he made bar the wildest, and a mark is
          // tested BEFORE the free lines, so a dimension always wins over a
          // line lying under it. tests/t51.js pins both.
          var MARK_GRAB=26;
          var SF = {};      // scale label -> paper inches per model inch
          var ZOOM = null;  // null = fit the window; otherwise a multiplier

          function $(id){ return document.getElementById(id); }

          function scaleFactor(lbl){ return SF[lbl] || 0.25/12; }

          // ---- drawing ---------------------------------------------------
          function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

          function shapeSVG(s, tp, k, ph){
            var o=[];
            function P(x,y){ var p=tp(x,y); return (p[0]*k).toFixed(2)+','+((ph-p[1])*k).toFixed(2); }
            var w = ((s.weight||0.012)*k).toFixed(2);
            if(s.type==='line'){
              o.push('<line x1="'+P(s.x1,s.y1).split(',')[0]+'" y1="'+P(s.x1,s.y1).split(',')[1]+
                     '" x2="'+P(s.x2,s.y2).split(',')[0]+'" y2="'+P(s.x2,s.y2).split(',')[1]+
                     '" stroke="#000" stroke-width="'+Math.max(w,0.6)+'"/>');
            } else if(s.type==='polyline'||s.type==='polygon'){
              var pts=s.points.map(function(p){ return P(p[0],p[1]); }).join(' ');
              if(s.fill){
                var c='rgb('+s.fill[0]+','+s.fill[1]+','+s.fill[2]+')';
                o.push('<polygon points="'+pts+'" fill="'+c+'" stroke="none"/>');
              } else {
                o.push('<'+(s.closed?'polygon':'polyline')+' points="'+pts+
                       '" fill="none" stroke="#000" stroke-width="'+Math.max(w,0.6)+'"/>');
              }
            } else if(s.type==='text'){
              var p=tp(s.x,s.y), px=p[0]*k, py=(ph-p[1])*k;
              // text drawn on the plan is in model inches and shrinks with the
              // scale; text put straight on the sheet is already paper inches.
              var hp = s.h * (s.__paper ? 1 : scaleFactor(STATE.scale));
              var fs = hp * k / 0.717;
              if(fs<1.5) return '';
              var anchor = s.__paper ? 'start' : 'middle';
              var base   = s.__paper ? 'alphabetic' : 'central';
              var rot = s.rotation ? ' transform="rotate('+(-s.rotation)+','+px.toFixed(1)+','+py.toFixed(1)+')"' : '';
              o.push('<text x="'+px.toFixed(1)+'" y="'+py.toFixed(1)+'" font-family="Helvetica,Arial"'+
                     ' font-size="'+fs.toFixed(1)+'" text-anchor="'+anchor+'" dominant-baseline="'+base+
                     '" fill="#000"'+(s.bold?' font-weight="700"':'')+(s.italic?' font-style="italic"':'')+
                     rot+'>'+esc(s.text)+'</text>');
            } else if(s.type==='table'){
              var cols=s.col_widths||[], rh=s.row_h||0.22, th=s.h||0.1;
              var all=[s.headers||[]].concat(s.rows||[]);
              var tw=cols.reduce(function(a,b){return a+b;},0);
              function L(x1,y1,x2,y2){
                o.push('<line x1="'+(x1*k).toFixed(1)+'" y1="'+((ph-y1)*k).toFixed(1)+
                       '" x2="'+(x2*k).toFixed(1)+'" y2="'+((ph-y2)*k).toFixed(1)+
                       '" stroke="#000" stroke-width="0.7"/>');
              }
              for(var i=0;i<=all.length;i++) L(s.x, s.y-i*rh, s.x+tw, s.y-i*rh);
              var xa=0;
              L(s.x, s.y, s.x, s.y-all.length*rh);
              for(var c=0;c<cols.length;c++){ xa+=cols[c]; L(s.x+xa, s.y, s.x+xa, s.y-all.length*rh); }
              all.forEach(function(row,ri){
                var cx=0;
                row.forEach(function(cell,ci){
                  var fs=th*k/0.717;
                  if(fs>=1.5&&cell) o.push('<text x="'+((s.x+cx+0.05)*k).toFixed(1)+'" y="'+
                    ((ph-(s.y-(ri+1)*rh+rh*0.3))*k).toFixed(1)+
                    '" font-family="Helvetica,Arial" font-size="'+fs.toFixed(1)+
                    '" fill="#000"'+(ri===0?' font-weight="700"':'')+'>'+esc(cell)+'</text>');
                  cx+=cols[ci]||1.2;
                });
              });
            } else if(s.type==='image'){
              var a=tp(s.x,s.y);
              var ix=(a[0]*k).toFixed(1), iy=((ph-(s.y+s.h))*k).toFixed(1);
              var iw=(s.w*k).toFixed(1), ih=(s.h*k).toFixed(1);
              var t=URLS[s.path];
              if(t){
                // meet = keep the proportions and sit in the middle, which is
                // exactly what plan_pdf does when it prints.
                o.push('<image x="'+ix+'" y="'+iy+'" width="'+iw+'" height="'+ih+
                       '" preserveAspectRatio="xMidYMid meet" href="'+t+'"/>');
              } else {
                o.push('<rect x="'+ix+'" y="'+iy+'" width="'+iw+'" height="'+ih+
                       '" fill="none" stroke="#bbb" stroke-dasharray="3 3"/>');
              }
            }
            return o.join('');
          }

          function activePage(){
            if(!DOC||!DOC.pages.length) return null;
            var i=STATE.active||0;
            return DOC.pages[i]||DOC.pages[0];
          }

          function fitK(){
            var stage=$('stage');
            return Math.min((stage.clientWidth-56)/PAGE.width,(stage.clientHeight-56)/PAGE.height);
          }

          // ONE routine draws a sheet, whether it fills the window or sits in
          // the page strip at 180 pixels wide. Two drawing routines would drift
          // apart the same way the window and the PDF would, and the whole file
          // is built to stop that happening.
          //
          // live = the sheet the user is working on: it remembers how to get
          // from the screen back to the house, shows the view frame, and paints
          // what is picked. A thumbnail wants none of that.
          function sheetSVG(pg, k, live){
            var W=pg.width*k, H=pg.height*k, ph=pg.height;
            function same(x,y){ return [x,y]; }
            var o=['<svg xmlns="http://www.w3.org/2000/svg" width="'+W.toFixed(0)+
                   '" height="'+H.toFixed(0)+'" viewBox="0 0 '+W.toFixed(0)+' '+
                   H.toFixed(0)+'" style="display:block">'];
            o.push('<rect width="100%" height="100%" fill="#fff"/>');

            var v=(pg.views||[])[0];
            if(live) VIEW=null;
            if(v){
              var sf=scaleFactor(STATE.scale);
              var cx=v.x+v.w/2, cy=v.y+v.h/2;
              var toPaper=function(mx,my){ return [cx+(mx-STATE.origin_x)*sf, cy+(my-STATE.origin_y)*sf]; };
              // remembered so a click on the screen can be turned back into a
              // place in the house
              if(live) VIEW={k:k, sf:sf, cx:cx, cy:cy, toPaper:toPaper};
              var cid='vclip'+(live?'':'t'+(pg.name||'').replace(/[^A-Za-z0-9]/g,''));
              o.push('<clipPath id="'+cid+'"><rect x="'+(v.x*k).toFixed(1)+'" y="'+((ph-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+'"/></clipPath>');
              o.push('<g clip-path="url(#'+cid+')">');
              var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
              if(cv) cv.layers.forEach(function(l){
                if(STATE.hidden.indexOf(l.name)>=0) return;
                l.shapes.forEach(function(s){ o.push(shapeSVG(s,toPaper,k,ph)); });
              });
              o.push('</g>');
              // the window itself, so the user can see where the plan may sit
              if(live) o.push('<rect x="'+(v.x*k).toFixed(1)+'" y="'+((ph-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+
                     '" fill="none" stroke="#bcd" stroke-width="1" stroke-dasharray="5 4"/>');
            }

            (pg.layers||[]).forEach(function(l){
              if(STATE.hidden.indexOf(l.name)>=0) return;
              l.shapes.forEach(function(s){ s.__paper=true; o.push(shapeSVG(s,same,k,ph)); });
            });

            if(live){
              // what is picked, drawn over the top. Presentation only - the mark
              // itself is still the one Ruby built, so the paper cannot drift.
              var picked = SELS.length ? SELS : (SEL===null ? [] : [SEL]);
              picked.forEach(function(pi){
              if(marks()[pi] && VIEW){
                var sm=marks()[pi];
                // No handles. The user, 2026-08-19: "מספיק עם העיגולים
                // הכחולים האלו." What is picked is shown by drawing the THING
                // in blue over itself - the same way SketchUp shows a
                // selection - and it is moved by carrying it, not by grabbing
                // a dot on it.
                if(sm.t==='dim'){
                  // the dimension line where it actually stands...
                  var dl=dimLine(sm);
                  var pa=screenOf(dl[0],dl[1]), pb=screenOf(dl[2],dl[3]);
                  o.push('<line x1="'+pa[0].toFixed(1)+'" y1="'+pa[1].toFixed(1)+
                         '" x2="'+pb[0].toFixed(1)+'" y2="'+pb[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="2" opacity=".55"/>');
                  // ...and the two points on the object that it measures
                  // and its witness lines, so the whole dimension reads as
                  // picked rather than just its middle
                  var wa=screenOf(sm.x1,sm.y1), wb=screenOf(sm.x2,sm.y2);
                  o.push('<line x1="'+wa[0].toFixed(1)+'" y1="'+wa[1].toFixed(1)+
                         '" x2="'+pa[0].toFixed(1)+'" y2="'+pa[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="1.5" opacity=".45"/>');
                  o.push('<line x1="'+wb[0].toFixed(1)+'" y1="'+wb[1].toFixed(1)+
                         '" x2="'+pb[0].toFixed(1)+'" y2="'+pb[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="1.5" opacity=".45"/>');
                } else {
                  // a note: its leader, drawn over itself in blue
                  var seg=function(p1,p2){
                    o.push('<line x1="'+p1[0].toFixed(1)+'" y1="'+p1[1].toFixed(1)+
                           '" x2="'+p2[0].toFixed(1)+'" y2="'+p2[1].toFixed(1)+
                           '" stroke="#1f6feb" stroke-width="2" opacity=".55"/>');
                  };
                  var pw=screenOf(sm.x,sm.y);
                  if(sm.kx!==undefined){
                    var pk=screenOf(sm.kx,sm.ky);
                    if(sm.lx!==undefined) seg(screenOf(sm.lx,sm.ly), pk);
                    seg(pk, pw);
                  } else if(sm.lx!==undefined){
                    seg(screenOf(sm.lx,sm.ly), pw);
                  }
                }
              }
              });

              // the dimension being drawn right now, before it is real
              if(PEND && VIEW){
                var SP=function(mx,my){
                  var q=VIEW.toPaper(mx,my);
                  return [(q[0]*k), ((ph-q[1])*k)];
                };
                var dash=function(p1,p2,w){
                  o.push('<line x1="'+p1[0].toFixed(1)+'" y1="'+p1[1].toFixed(1)+
                         '" x2="'+p2[0].toFixed(1)+'" y2="'+p2[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="'+(w||1.5)+
                         '" stroke-dasharray="4 3"/>');
                };
                if(MODE==='note'){
                  // the leader being drawn, one segment per click
                  var kp = PEND2 || HOVER;
                  if(kp) dash(SP(PEND[0],PEND[1]), SP(kp[0],kp[1]), 1.5);
                  if(PEND2){
                    var ep = PEND3 || HOVER;
                    // the shoulder is level with the knee whatever height the
                    // mouse is at - he is choosing its LENGTH
                    if(ep) dash(SP(PEND2[0],PEND2[1]), SP(ep[0],PEND2[1]), 1.5);
                  }
                } else if(PEND2){
                  // stage three: the real thing, following the mouse. What he
                  // is looking at IS the dimension he is about to leave there,
                  // witness lines and all - not a hint of one.
                  var tmp={t:'dim', x1:PEND[0], y1:PEND[1],
                           x2:PEND2[0], y2:PEND2[1], off:PENDOFF};
                  var L=dimLine(tmp);
                  dash(SP(PEND[0],PEND[1]),  SP(L[0],L[1]), 1);   // witness
                  dash(SP(PEND2[0],PEND2[1]),SP(L[2],L[3]), 1);   // witness
                  dash(SP(L[0],L[1]), SP(L[2],L[3]), 2);          // the line
                } else if(HOVER){
                  dash(SP(PEND[0],PEND[1]), SP(HOVER[0],HOVER[1]));
                }
              }
            }
            o.push('</svg>');
            return o.join('');
          }

          function render(){
            PAGE=activePage();
            if(!DOC||!PAGE) return;
            $('sheetWrap').innerHTML=sheetSVG(PAGE, fitK()*(ZOOM||1), true);
            hookDrag();
            paintErase();
            paintSnap();
            paintTextPick();
            if($('strip').className==='on') paintStrip();
          }

          function setZoom(z){
            ZOOM = z;
            STATE.zoom = z;
            render();
          }

          // Zoom towards a point on the screen instead of towards a corner.
          //
          // Zooming only makes the sheet bigger; the scroll box stays where it
          // was, so whatever happened to be at the top left stayed put and
          // everything the user was looking at slid away. Remember which spot
          // on the SHEET is under the mouse, redraw, then scroll so that same
          // spot is back under the mouse. Works the same whether the sheet is
          // centred in the window or scrolled.
          function zoomAt(cx, cy, z){
            z = Math.min(Math.max(z, 0.2), 14);
            var stage = $('stage');
            var svg = $('sheetWrap').firstChild;
            if(!svg){ setZoom(z); return; }
            var r = svg.getBoundingClientRect();
            if(!r.width || !r.height){ setZoom(z); return; }
            // 0..1 across the sheet. Off the sheet, hold on to the nearest edge
            // rather than flinging the page away.
            var fx = Math.max(0, Math.min(1, (cx - r.left) / r.width));
            var fy = Math.max(0, Math.min(1, (cy - r.top) / r.height));

            setZoom(z);

            var svg2 = $('sheetWrap').firstChild;
            if(!svg2) return;
            var r2 = svg2.getBoundingClientRect();
            stage.scrollLeft += (r2.left + fx * r2.width)  - cx;
            stage.scrollTop  += (r2.top  + fy * r2.height) - cy;
          }

          // ---- from the screen back to the house --------------------------
          //
          // render() draws the house onto paper and the paper onto the screen.
          // To put a dimension where the user clicked, both have to be undone.
          function atMouse(e){
            var svg=$('sheetWrap').firstChild;
            if(!svg||!VIEW||!PAGE) return null;
            var r=svg.getBoundingClientRect();
            var px=(e.clientX-r.left)/VIEW.k;                 // paper inches
            var py=PAGE.height-(e.clientY-r.top)/VIEW.k;
            return [(px-VIEW.cx)/VIEW.sf+STATE.origin_x,      // model inches
                    (py-VIEW.cy)/VIEW.sf+STATE.origin_y];
          }

          function marks(){ return STATE.marks||(STATE.marks=[]); }

          // ---- snapping a dimension onto the drawing ----------------------
          //
          // The user, 2026-08-19: "הלחיצה צריכה להינעל על פינות וקצוות כמו
          // בשאר הכלים". A dimension that starts a quarter of an inch off the
          // corner reads 15' 1/16" when the wall is 15' - and he has no way to
          // see which one it did.
          //
          // So the click looks for a corner first: every END of a line and
          // every VERTEX of a polyline or polygon that is drawn on the plan -
          // walls, free geometry, anything on a visible layer. The search is
          // in SCREEN pixels, not model inches, so the pull feels the same
          // however far he is zoomed in, exactly like SketchUp.
          var SNAP_PX = 12;
          var SNAPPED = null;   // where the last snap landed, for the marker

          function eachVertex(fn){
            if(!DOC||!STATE||!PAGE) return;
            var v=(PAGE.views||[])[0]; if(!v) return;
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
            if(!cv) return;
            var hid=STATE.hidden||[];
            cv.layers.forEach(function(l){
              if(hid.indexOf(l.name)>=0) return;
              (l.shapes||[]).forEach(function(s){
                if(s.type==='line'){ fn(s.x1,s.y1); fn(s.x2,s.y2); }
                else if(s.points){ s.points.forEach(function(q){ fn(q[0],q[1]); }); }
              });
            });
            // the ends of dimensions already drawn, so a run of them lines up
            marks().forEach(function(m){
              if(m.t==='dim'){ fn(m.x1,m.y1); fn(m.x2,m.y2); }
            });
          }

          // p is where the mouse really is, in model inches. Returns the
          // corner it should lock onto, or p itself when there is none near.
          function snapPoint(p){
            if(!p||!VIEW) return p;
            var ps=screenOf(p[0],p[1]);
            var best=null, bd=SNAP_PX;
            eachVertex(function(x,y){
              var q=screenOf(x,y);
              var d=Math.hypot(q[0]-ps[0], q[1]-ps[1]);
              if(d<bd){ bd=d; best=[x,y]; }
            });
            SNAPPED = best ? best.slice() : null;
            return best || p;
          }

          // model inches -> pixels inside the drawing, for hit testing
          function screenOf(mx,my){
            var p=VIEW.toPaper(mx,my);
            return [p[0]*VIEW.k, (PAGE.height-p[1])*VIEW.k];
          }

          function mouseAt(e){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return null;
            var r=svg.getBoundingClientRect();
            return [e.clientX-r.left, e.clientY-r.top];
          }

          function distToSeg(X,Y,a,b){
            var vx=b[0]-a[0], vy=b[1]-a[1];
            var L=vx*vx+vy*vy;
            var t = L ? ((X-a[0])*vx+(Y-a[1])*vy)/L : 0;
            t=Math.max(0,Math.min(1,t));
            return Math.hypot(a[0]+vx*t-X, a[1]+vy*t-Y);
          }

          // What is under the mouse, and which bit of it. The ends of a
          // dimension and the arrow tip of a note win over the body, so a
          // careful click adjusts instead of dragging the whole thing.
          function hitMark(e){
            if(!VIEW||!PAGE) return null;
            var p=mouseAt(e); if(!p) return null;
            var X=p[0], Y=p[1], best=null, bd=MARK_GRAB;
            marks().forEach(function(m,i){
              if(m.t==='dim'){
                // the two CLICKED points - they sit on the thing being
                // measured and they are what 'a' and 'b' move
                var a=screenOf(m.x1,m.y1), b=screenOf(m.x2,m.y2);
                var da=Math.hypot(a[0]-X,a[1]-Y), db=Math.hypot(b[0]-X,b[1]-Y);
                if(da<bd){ bd=da; best={i:i,part:'a'}; }
                if(db<bd){ bd=db; best={i:i,part:'b'}; }
                // the NUMBER itself, before the line: they overlap on a short
                // dimension, and the thing he reached for is the one he can
                // see (2026-08-19). The ends still win over both.
                var lp=dimLabelXY(m), ls=screenOf(lp[0],lp[1]);
                var dl=Math.hypot(ls[0]-X,ls[1]-Y);
                if(dl<bd){ bd=dl; best={i:i,part:'text'}; }
                // and the DIMENSION LINE, which is where it stands now - not
                // where it was clicked. Dragging it pulls it off the wall.
                var L=dimLine(m);
                var la=screenOf(L[0],L[1]), lb=screenOf(L[2],L[3]);
                var ds=distToSeg(X,Y,la,lb);
                if(ds<bd){ bd=ds; best={i:i,part:'off'}; }
              } else if(m.t==='note'){
                if(m.lx!==undefined){
                  var t=screenOf(m.lx,m.ly);
                  var dt=Math.hypot(t[0]-X,t[1]-Y);
                  if(dt<bd){ bd=dt; best={i:i,part:'tip'}; }
                }
                if(m.kx!==undefined){
                  var kp=screenOf(m.kx,m.ky);
                  var dk=Math.hypot(kp[0]-X,kp[1]-Y);
                  if(dk<bd){ bd=dk; best={i:i,part:'knee'}; }
                }
                var c=screenOf(m.x,m.y);
                var dc=Math.hypot(c[0]-X,c[1]-Y);
                if(dc<bd+8){ bd=Math.min(bd,dc); best={i:i,part:'all'}; }
              }
            });
            return best;
          }

          // ---- rubbing a line off the sheet ------------------------------
          //
          // Only the free geometry - the lines traced off the model by hand.
          // The walls, doors and windows are drawn from their attributes and
          // are switched off by their own layer, not one at a time.
          //
          // Shape number i on this layer is line number i in Ruby's list; see
          // the note over drop_site_line. Nothing is looked up by position, so
          // two lines lying on top of each other cannot be confused.
          function siteLayer(){
            if(!DOC||!PAGE||!STATE) return null;
            if((STATE.hidden||[]).indexOf('SITE')>=0) return null;   // switched off
            var v=(PAGE.views||[])[0]; if(!v) return null;
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
            if(!cv) return null;
            return (cv.layers||[]).filter(function(l){ return l.name==='SITE'; })[0]||null;
          }

          function hitSite(e){
            var lay=siteLayer(); if(!lay||!VIEW) return null;
            var p=mouseAt(e); if(!p) return null;
            var X=p[0], Y=p[1], best=null, bd=GRAB;
            (lay.shapes||[]).forEach(function(s,i){
              var pts=s.points; if(!pts||pts.length<2) return;
              for(var j=0;j<pts.length-1;j++){
                var a=screenOf(pts[j][0],pts[j][1]);
                var b=screenOf(pts[j+1][0],pts[j+1][1]);
                var d=distToSeg(X,Y,a,b);
                if(d<bd){ bd=d; best=i; }
              }
            });
            return best;
          }

          // The line about to go, in red.
          //
          // Painted straight onto the drawing as ONE extra element instead of
          // going through render(). A real back yard is thousands of lines and
          // rebuilding all of them every time the mouse crosses a new one would
          // make the rubber feel stuck.
          //
          // It sits outside the view frame's clip, so a line running off the
          // edge of the sheet lights up along its whole length. That is on
          // purpose: it shows what is about to be deleted, not what is printed.
          // WHAT THE ERASER CAN TAKE (2026-08-19).
          //
          // It used to rub out free SITE geometry and nothing else, so a
          // dimension could only go by picking it and pressing Delete - which
          // is not how the user works. In SketchUp the eraser is THE way you
          // get rid of a dimension: you pass over it, it lights up, you click
          // or you drag across a run of them. He sent a picture of exactly
          // that. So the eraser now takes marks too - dimensions and notes -
          // and marks win over site lines, because they are the small thing
          // drawn on top and they are what he is aiming at.
          //
          // ERA is {kind:'mark'|'site', i:index} or null.
          function hitErase(e){
            var h=hitMark(e);
            if(h) return {kind:'mark', i:h.i};
            var s=hitSite(e);
            return (s===null) ? null : {kind:'site', i:s};
          }

          function sameEra(a,b){
            if(a===null||b===null) return a===b;
            return a.kind===b.kind && a.i===b.i;
          }

          function eraKey(x){ return x.kind+':'+x.i; }

          // Everything the current sweep has crossed, in the order it was
          // crossed. Dragging the eraser over a run of things is how SketchUp
          // does it, and one round trip per item would make it crawl - so the
          // sweep collects and the whole lot goes on letting go.
          var ERASWEEP=null;
          var ERADONE=false;   // a sweep just ran; swallow the click behind it

          function eraShapePoints(x){
            if(x.kind==='site'){
              var lay=siteLayer(); if(!lay) return null;
              var s=(lay.shapes||[])[x.i];
              return (s&&s.points) ? s.points.map(function(q){ return screenOf(q[0],q[1]); }) : null;
            }
            var m=marks()[x.i]; if(!m) return null;
            if(m.t==='dim'){
              var L=dimLine(m);
              return [screenOf(L[0],L[1]), screenOf(L[2],L[3])];
            }
            // a note: ring its words
            var c=screenOf(m.x,m.y);
            return [[c[0]-14,c[1]],[c[0]+14,c[1]]];
          }

          // The green square on the corner the dimension is about to lock to.
          // Painted straight onto the drawing, like the eraser's highlight -
          // going through render() on every mouse move would make it stick.
          // ---- the rubber band ---------------------------------------------
          //
          // Painted straight onto the drawing, like the eraser's highlight and
          // the snap marker: going through render() on every mouse move would
          // rebuild every line on the sheet and the band would feel stuck.
          function paintBand(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#bandhi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(!BAND) return;
            var x=Math.min(BAND.x0,BAND.x1), y=Math.min(BAND.y0,BAND.y1);
            var w=Math.abs(BAND.x1-BAND.x0), h=Math.abs(BAND.y1-BAND.y0);
            var n=document.createElementNS('http://www.w3.org/2000/svg','rect');
            n.setAttribute('id','bandhi');
            n.setAttribute('x',x.toFixed(1)); n.setAttribute('y',y.toFixed(1));
            n.setAttribute('width',w.toFixed(1)); n.setAttribute('height',h.toFixed(1));
            n.setAttribute('fill','#1f6feb');
            n.setAttribute('fill-opacity','.08');
            n.setAttribute('stroke','#1f6feb');
            n.setAttribute('stroke-width','1');
            n.setAttribute('stroke-dasharray','4 3');
            svg.appendChild(n);
          }

          // Is any part of this mark inside the box he pulled? A mark that
          // merely CROSSES it counts - reaching a dimension means reaching its
          // line, and asking him to swallow the whole of a 70 foot one before
          // it will pick would be its own kind of fiddling.
          function markInBox(m, x0, y0, x1, y1) {
            var lo=[Math.min(x0,x1), Math.min(y0,y1)];
            var hi=[Math.max(x0,x1), Math.max(y0,y1)];
            var inside=function(p){
              return p[0]>=lo[0] && p[0]<=hi[0] && p[1]>=lo[1] && p[1]<=hi[1];
            };
            var pts=[];
            if(m.t==='dim'){
              var L=dimLine(m);
              pts.push(screenOf(m.x1,m.y1), screenOf(m.x2,m.y2),
                       screenOf(L[0],L[1]), screenOf(L[2],L[3]));
              var lab=dimLabelXY(m); pts.push(screenOf(lab[0],lab[1]));
              // and the middle, so a long dimension lying across the box counts
              pts.push(screenOf((L[0]+L[2])/2, (L[1]+L[3])/2));
            } else {
              pts.push(screenOf(m.x,m.y));
              if(m.kx!==undefined) pts.push(screenOf(m.kx,m.ky));
              if(m.lx!==undefined) pts.push(screenOf(m.lx,m.ly));
            }
            return pts.some(inside);
          }

          function pickInBand(band){
            SELS=[];
            marks().forEach(function(m,i){
              if(markInBox(m, band.x0, band.y0, band.x1, band.y1)) SELS.push(i);
            });
            SEL = SELS.length ? SELS[0] : null;
          }

          function paintSnap(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#snaphi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(MODE!=='dim'||!SNAPPED||!VIEW) return;
            var q=screenOf(SNAPPED[0],SNAPPED[1]);
            var n=document.createElementNS('http://www.w3.org/2000/svg','rect');
            n.setAttribute('id','snaphi');
            n.setAttribute('x',(q[0]-4).toFixed(1)); n.setAttribute('y',(q[1]-4).toFixed(1));
            n.setAttribute('width','8'); n.setAttribute('height','8');
            n.setAttribute('fill','none');
            n.setAttribute('stroke','#2fbf5f');
            n.setAttribute('stroke-width','2');
            svg.appendChild(n);
          }

          function paintErase(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#erahi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(MODE!=='erase'||!VIEW) return;
            var show=[];
            if(ERASWEEP) show=ERASWEEP.slice();
            else if(ERA) show=[ERA];
            if(!show.length) return;
            var g=document.createElementNS('http://www.w3.org/2000/svg','g');
            g.setAttribute('id','erahi');
            show.forEach(function(x){
              var pts=eraShapePoints(x); if(!pts) return;
              var n=document.createElementNS('http://www.w3.org/2000/svg','polyline');
              n.setAttribute('points',pts.map(function(t){
                return t[0].toFixed(1)+','+t[1].toFixed(1); }).join(' '));
              n.setAttribute('fill','none');
              // Blue, like the picture he sent of SketchUp: this is "the
              // eraser is on it", not "it is already gone".
              n.setAttribute('stroke','#1f6feb');
              n.setAttribute('stroke-width','4');
              n.setAttribute('stroke-linecap','round');
              n.setAttribute('opacity','.85');
              g.appendChild(n);
            });
            svg.appendChild(g);
          }

          // Take everything the sweep crossed. Marks live in the settings, so
          // they go here; site lines live in Ruby, so they go in ONE message.
          function eraseSweep(list){
            if(!list||!list.length) return;
            var seen={}, marksGone=[], siteGone=[];
            list.forEach(function(x){
              var k=eraKey(x); if(seen[k]) return; seen[k]=1;
              if(x.kind==='mark') marksGone.push(x.i); else siteGone.push(x.i);
            });
            // highest first, so taking one out cannot move the next
            marksGone.sort(function(a,b){ return b-a; })
                     .forEach(function(i){ marks().splice(i,1); });
            if(marksGone.length){ SEL=null; push(); render(); showMarks(); }
            if(siteGone.length) sketchup.drop_site_line(JSON.stringify({is:siteGone}));
          }

          // The eraser's own pointer, so the tool says what it is the way it
          // does in SketchUp - he asked for this by name. Drawn here rather
          // than shipped as a file: it is eleven characters of path data and a
          // missing file would silently fall back to an arrow.
          // The select tool's own pointer - a plain black arrow, which is what
          // it is in SketchUp and what the user asked for. A grabbing hand said
          // "this pans", and panning is not what this tool does any more.
          function arrowCursor(){
            var s='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'+
                  '<path d="M4 2 L4 18 L8.4 14 L11.2 20.4 L14 19.2 L11.3 13 L17 13 Z" '+
                  'fill="#000" stroke="#fff" stroke-width="1.1" stroke-linejoin="round"/>'+
                  '</svg>';
            return 'url("data:image/svg+xml;utf8,'+encodeURIComponent(s)+'") 4 2, default';
          }

          function eraserCursor(){
            var s='<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26">'+
                  '<g fill="none" stroke="#000" stroke-width="1.6" stroke-linejoin="round">'+
                  '<path d="M3 17.5 L10.5 10 L18 17.5 L14 21.5 L7 21.5 Z" fill="#fff"/>'+
                  '<path d="M10.5 10 L15 5.5 L22.5 13 L18 17.5"/>'+
                  '<path d="M7 21.5 L18.5 21.5"/>'+
                  '</g></svg>';
            return 'url("data:image/svg+xml;utf8,'+encodeURIComponent(s)+'") 4 21, crosshair';
          }

          // ---- one label at a time ----------------------------------------
          //
          // Double-click any writing on the sheet - a room name, a tag, a
          // dimension, a note - and set that one. Ruby keeps the choice under
          // the label's key (PlanCanvas.text_key) so it survives the sheet
          // being rebuilt from the model.
          var TSEL=null;   // {key, shape, paper} - the label being changed
          // A label being shoved right now. Ruby draws the writing, so the
          // window cannot really move it until Ruby has heard - a round trip
          // per mouse move would crawl. So the highlight box moves live and
          // the real move is sent once, on letting go.
          var TDRAG=null;
          // and a label being CARRIED - picked up by a click, put down by the
          // next one. See CARRY.
          var TCARRY=null;

          // Where a piece of writing sits on the screen, near enough to click.
          //
          // The width is ESTIMATED - half the height per letter is close for
          // Helvetica, and plan_pdf's real width tables are Ruby's. A box a
          // little too wide is the right way to be wrong here: it makes small
          // writing easier to hit, and the worst case is that a click near a
          // tag opens that tag.
          function textBox(s, paper){
            var h = s.h * (paper ? 1 : scaleFactor(STATE.scale));  // paper inches
            var w = Math.max(String(s.text||'').length * h * 0.55, h * 0.8);
            var p = paper ? [s.x, s.y] : VIEW.toPaper(s.x, s.y);
            var cx = p[0], cy = p[1];
            // Writing put straight on the sheet hangs off its start point;
            // writing on the plan is centred on it. Same rule as shapeSVG.
            if(paper){ cx = p[0] + w/2; cy = p[1] + h/2; }
            return { x:(cx - w/2)*VIEW.k, y:(PAGE.height - cy - h/2)*VIEW.k,
                     w:w*VIEW.k, h:h*VIEW.k };
          }

          // Every piece of writing on the sheet right now, with its key.
          // VIEW is deliberately NOT required here. This also runs straight
          // after a sheet arrives, to point the open panel at the label that
          // came back, and at that moment nothing has been drawn yet.
          function eachText(fn){
            if(!DOC||!STATE) return;
            var PG = PAGE || activePage(); if(!PG) return;
            var hid = STATE.hidden||[];
            var v=(PG.views||[])[0];
            if(v){
              var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
              if(cv) cv.layers.forEach(function(l){
                if(hid.indexOf(l.name)>=0) return;
                (l.shapes||[]).forEach(function(s){
                  if(s.type==='text'&&s.key) fn(s,false);
                });
              });
            }
            (PG.layers||[]).forEach(function(l){
              if(hid.indexOf(l.name)>=0) return;
              (l.shapes||[]).forEach(function(s){
                if(s.type==='text'&&s.key) fn(s,true);
              });
            });
          }

          function hitText(e){
            var p=mouseAt(e); if(!p||!VIEW||!PAGE) return null;
            var X=p[0], Y=p[1], best=null, ba=Infinity;
            eachText(function(s,paper){
              var b=textBox(s,paper);
              if(X<b.x||X>b.x+b.w||Y<b.y||Y>b.y+b.h) return;
              var a=b.w*b.h;             // the tightest box wins, not the first
              if(a<ba){ ba=a; best={key:s.key, shape:s, paper:paper}; }
            });
            return best;
          }

          function textMarks(){ return STATE.text_marks||(STATE.text_marks={}); }

          function openTextBar(hit){
            TSEL=hit;
            var m=textMarks()[hit.key]||{};
            // What it is RIGHT NOW, not what was overridden - so the number in
            // the box is the number on the sheet and he is never editing blind.
            var shown = m.pct ? +m.pct
                      : Math.round((hit.shape.h/(hit.shape.h0||hit.shape.h))*100);
            $('txsize').value = isFinite(shown)&&shown>0 ? shown : 100;
            $('txbold').className   = 'tool'+(hit.shape.bold?' on':'');
            $('txitalic').className = 'tool'+(hit.shape.italic?' on':'');
            $('txwhat').textContent = String(hit.shape.text||'').slice(0,22);
            $('textbar').className='on';
            placeTextBar();
            paintTextPick();
            $('txsize').focus();
            $('txsize').select();
          }

          // Shutting the note bar, from OUT HERE.
          //
          // closeNote() is declared inside the window's load handler, so it
          // does not exist at this level. Calling it from the drawing's
          // dblclick threw a ReferenceError that killed the handler on its
          // first line - two clicks on a label did nothing at all, and the
          // window looked like the feature had never shipped. That was the
          // user's "אין לי בכלל את האופציה לבחור את הכיתוב" (2026-08-17).
          //
          // Nothing in the console said so: an error inside an event handler
          // is swallowed by the page. t46 drives the real handler now, which
          // is the only reason this was found rather than argued about.
          function hideNoteBar(){
            $('notebar').className=''; PEND=null; PEND2=null; PEND3=null; EDIT=null;
          }

          function closeTextBar(){
            $('textbar').className='';
            TSEL=null;
            paintTextPick();
          }

          // ---- parking the panel ------------------------------------------
          //
          // Fixed keeps it on screen, but the middle of the top is exactly
          // where a label can be. Dragging it by its name lets him put it
          // somewhere it is not in the way. Where he puts it is remembered for
          // as long as the window is open - not written onto the model, since
          // it says nothing about the drawing.
          var TBAR=null;    // {x, y} in pixels, or null for "where it starts"

          function placeTextBar(){
            var el=$('textbar');
            if(!TBAR){ el.style.left='50%'; el.style.top='22px';
                       el.style.transform='translateX(-50%)'; return; }
            el.style.left=TBAR.x+'px';
            el.style.top=TBAR.y+'px';
            el.style.transform='none';
          }

          function dragTextBar(e){
            var el=$('textbar');
            var r=el.getBoundingClientRect();
            var grab={ dx:e.clientX-r.left, dy:e.clientY-r.top, w:r.width, h:r.height };
            function move(ev){
              // Kept on screen. A panel dragged off the edge cannot be dragged
              // back, and closing it is not the same as putting it away.
              var x=Math.min(Math.max(ev.clientX-grab.dx, 4),
                             Math.max((window.innerWidth||900)-grab.w-4, 4));
              var y=Math.min(Math.max(ev.clientY-grab.dy, 4),
                             Math.max((window.innerHeight||700)-grab.h-4, 4));
              TBAR={x:x, y:y};
              placeTextBar();
              ev.preventDefault();
            }
            function up(){
              window.removeEventListener('mousemove', move);
              window.removeEventListener('mouseup', up);
            }
            window.addEventListener('mousemove', move);
            window.addEventListener('mouseup', up);
            e.preventDefault();
          }

          // A blue box round the label being changed. Its own element on top of
          // the drawing, for the same reason the rubber's red line is - render()
          // rebuilds the whole sheet and this happens while he is clicking.
          function paintTextPick(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#txhi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(!TSEL||!VIEW||!PAGE) return;
            // The document is rebuilt from the model on every change, so the
            // shape object we are holding is a ghost the moment Ruby answers.
            // Find the label by its KEY again - that is what the key is for.
            if(!TDRAG && !TCARRY){
              var want=TSEL.key, found=null;
              eachText(function(s,paper){
                if(!found && s.key===want) found={key:s.key, shape:s, paper:paper};
              });
              if(found) TSEL=found;
            }
            var b=textBox(TSEL.shape, TSEL.paper);
            // while it is being shoved, the box follows the mouse even though
            // the writing itself cannot move until Ruby redraws it
            var tc = TDRAG || TCARRY;
            if(tc){
              b.x += tc.dx*VIEW.sf*VIEW.k;
              b.y -= tc.dy*VIEW.sf*VIEW.k;      // paper y is up, screen y is down
            }
            var n=document.createElementNS('http://www.w3.org/2000/svg','rect');
            n.setAttribute('id','txhi');
            n.setAttribute('x',b.x.toFixed(1)); n.setAttribute('y',b.y.toFixed(1));
            n.setAttribute('width',Math.max(b.w,3).toFixed(1));
            n.setAttribute('height',Math.max(b.h,3).toFixed(1));
            n.setAttribute('fill','none');
            n.setAttribute('stroke','#1f6feb');
            n.setAttribute('stroke-width','1.5');
            svg.appendChild(n);
          }

          // Shove the picked label by dx,dy MORE than it is already shoved.
          // Only the position is sent - the size and the weight are left out
          // of the message entirely, so a drag cannot quietly reset them
          // (set_text_mark merges what it is given onto what is there).
          // Put down what is being carried, wherever it is now.
          function dropCarry(){
            if(!CARRY) return;
            CARRY=null;
            push(); render(); showMarks();
          }

          function dropTextCarry(){
            if(!TCARRY) return;
            var dx=TCARRY.dx, dy=TCARRY.dy;
            TCARRY=null;
            if(dx||dy) nudgeText(dx, dy);
            else { paintTextPick(); showMarks(); }
          }

          // Esc while carrying puts it back where it was picked up from -
          // otherwise a slip of the mouse costs him the position he had.
          function cancelCarry(){
            if(CARRY){
              if(CARRY.many && CARRY.many.length>1 && CARRY.snaps){
                CARRY.many.forEach(function(i,n){
                  if(marks()[i] && CARRY.snaps[n]) marks()[i]=CARRY.snaps[n];
                });
              } else if(marks()[CARRY.i] && CARRY.snap){
                marks()[CARRY.i]=CARRY.snap;
              }
              CARRY=null;
              render();
            }
            if(TCARRY){ TCARRY=null; paintTextPick(); }
          }

          function nudgeText(dx, dy){
            if(!TSEL) return;
            var cur=textMarks()[TSEL.key]||{};
            var bx=(typeof cur.dx==='number')?cur.dx:0;
            var by=(typeof cur.dy==='number')?cur.dy:0;
            sketchup.set_text_mark(JSON.stringify(
              {key:TSEL.key, dx:bx+dx, dy:by+dy}));
          }

          function sendTextMark(extra){
            if(!TSEL) return;
            var v=parseFloat($('txsize').value);
            if(!isFinite(v)||v<=0) v=100;
            v=Math.min(400,Math.max(25,v));
            $('txsize').value=v;
            var out={ key:TSEL.key, pct:v,
                      bold:$('txbold').className.indexOf('on')>=0,
                      italic:$('txitalic').className.indexOf('on')>=0 };
            if(extra) for(var k in extra) out[k]=extra[k];
            sketchup.set_text_mark(JSON.stringify(out));
          }

          // How tall a dimension's number is when the mark carries no height of
          // its own - which is every mark this window makes. Ruby says the
          // number in the payload rather than the window guessing it; a guess
          // here is how the window and the paper start disagreeing.
          function markTextH(){ return (DIM_TEXT_H>0) ? DIM_TEXT_H : 5; }

          // Where a dimension's NUMBER sits. The SAME arithmetic as
          // PlanCanvas.dim_label_xy - see the long note over it. Two copies of
          // one formula is a drift risk and is treated as one: rt81 and t50
          // check both sides against the same numbers.
          //
          //   oa  along the line   - his right/left
          //   oc  across the line  - his up/down
          // in the LINE'S own frame, so the number keeps its place relative to
          // the dimension however the line was drawn or later moved.
          // The two ends of the DIMENSION LINE - the clicked points pushed off
          // the object by `off`. The SAME arithmetic as PlanCanvas.dim_line.
          // Returns [ax,ay,bx,by,ux,uy,len].
          // How far point q lies to the LEFT of a -> b. This is the number the
          // third click of the dimension tool is choosing, and it is the same
          // `off` the finished mark stores - so what he sees while he is
          // pulling it is exactly what he gets.
          function offsetToward(a, b, q){
            var dx=b[0]-a[0], dy=b[1]-a[1];
            var L=Math.sqrt(dx*dx+dy*dy);
            if(L<1e-9) return 0;
            var ux=dx/L, uy=dy/L;
            return (q[0]-a[0])*(-uy) + (q[1]-a[1])*(ux);
          }

          function dimLine(m){
            var dx=m.x2-m.x1, dy=m.y2-m.y1;
            var len=Math.sqrt(dx*dx+dy*dy);
            if(len<1e-9) return [m.x1,m.y1,m.x2,m.y2,0,0,len];
            var ux=dx/len, uy=dy/len;
            var off=(m.off===undefined||m.off===null)?0:m.off;
            var nx=-uy*off, ny=ux*off;
            return [m.x1+nx,m.y1+ny,m.x2+nx,m.y2+ny,ux,uy,len];
          }

          function dimLabelXY(m){
            var L=dimLine(m);
            var mx=(L[0]+L[2])/2, my=(L[1]+L[3])/2;
            if(L[6]<1e-9) return [mx,my];
            var ux=L[4], uy=L[5];
            var h=(m.h>0)?m.h:markTextH();
            var oa=(m.oa===undefined||m.oa===null)?0:m.oa;
            var oc=(m.oc===undefined||m.oc===null)?h*DIM_LABEL_OFF:m.oc;
            return [mx+ux*oa-uy*oc, my+uy*oa+ux*oc];
          }

          // How far a NEW dimension stands off the wall. Remembered, because
          // a distance he liked once he will like again.
          function dimOff(){
            var v=(STATE&&STATE.dim_off);
            return (typeof v==='number' && isFinite(v)) ? v : 0;
          }

          // The box shows the PICKED dimension's own distance when there is
          // one, and the setting for the next one when there is not - so the
          // number in the box is always the number that typing in it changes.
          function paintDimOff(){
            var b=$('dimoff'); if(!b) return;
            var m=(SEL!==null)?marks()[SEL]:null;
            var v=(m&&m.t==='dim') ? ((m.off===undefined||m.off===null)?0:m.off)
                                   : dimOff();
            if(document.activeElement!==b) b.value=Math.round(v*100)/100;
          }

          function setDimOff(v){
            if(!isFinite(v)) return;
            var m=(SEL!==null)?marks()[SEL]:null;
            if(m && m.t==='dim'){ m.off=v; }      // the one he has picked
            else { STATE.dim_off=v; }             // and otherwise the next one
            push(); render(); showMarks();
          }

          // Everything a press knows about itself, written to a file so it can
          // be READ instead of argued about. Wrapped whole: if the probe
          // itself throws it must not take the click down with it, which is
          // the exact failure it exists to catch.
          function probeClick(e){
            try {
              var p=mouseAt(e), am=atMouse(e);
              var h=null, ht=null, hs=null;
              try { h=hitMark(e); } catch(err){ h={ERROR:String(err)}; }
              try { var t=hitText(e); ht=t?t.key:null; } catch(err){ ht='ERROR '+String(err); }
              try { hs=hitSite(e); } catch(err){ hs='ERROR '+String(err); }
              var ms=[];
              (STATE&&STATE.marks?STATE.marks:[]).forEach(function(m,i){
                if(m.t!=='dim'){ ms.push({i:i,t:m.t}); return; }
                var L=dimLine(m);
                var a=screenOf(L[0],L[1]), b=screenOf(L[2],L[3]);
                var lab=dimLabelXY(m), ls=screenOf(lab[0],lab[1]);
                ms.push({i:i, t:'dim',
                         a:[Math.round(a[0]),Math.round(a[1])],
                         b:[Math.round(b[0]),Math.round(b[1])],
                         label:[Math.round(ls[0]),Math.round(ls[1])],
                         dLine: p?Math.round(distToSeg(p[0],p[1],a,b)):null,
                         dLabel: p?Math.round(Math.hypot(ls[0]-p[0],ls[1]-p[1])):null});
              });
              sketchup.sheet_probe(JSON.stringify({
                mode:MODE, shift:!!e.shiftKey,
                mouseScreen: p?[Math.round(p[0]),Math.round(p[1])]:null,
                mouseModel: am?[Math.round(am[0]*10)/10,Math.round(am[1]*10)/10]:null,
                svgSize: (function(){
                  var s=$('sheetWrap').firstChild;
                  if(!s) return 'NO SVG';
                  var r=s.getBoundingClientRect();
                  return {rectW:Math.round(r.width), rectH:Math.round(r.height),
                          attrW:s.getAttribute?s.getAttribute('width'):null,
                          attrH:s.getAttribute?s.getAttribute('height'):null};
                })(),
                view: VIEW?{k:Math.round(VIEW.k*100)/100, sf:VIEW.sf,
                            cx:VIEW.cx, cy:VIEW.cy}:null,
                pageH: PAGE?PAGE.height:null,
                grab: GRAB,
                hitMark: h, hitTextKey: ht, hitSite: hs,
                SEL: SEL, TSEL: TSEL?TSEL.key:null,
                marks: ms
              }));
            } catch(err){
              try { sketchup.sheet_probe(JSON.stringify({PROBE_THREW:String(err)})); }
              catch(e2){ /* nothing left to do */ }
            }
          }

          // A note from the THREE points HE clicked (2026-08-19), which is
          // the shape in the Rayon screenshot he sent:
          //
          //   tip  --\                                  the arrow, click 1
          //           \____________________  [123]      the knee is click 2,
          //           knee            end              the shoulder end is 3
          //
          // The shoulder is kept level with the knee - he chooses how LONG it
          // is, not how crooked - and the words sit a small gap past its end.
          // All three points still drag afterwards.
          //
          // The gap is measured in PAPER inches and divided back out by the
          // scale, so a note looks the same on a 1/8" sheet and a 1/2" one.
          //
          // Its own function so t52 can build the note THE WINDOW builds,
          // rather than a copy of it - saveNote lives inside the load handler
          // and no suite can reach in there.
          function noteMark(tip, knee, end, text, arrow, sf){
            var off = 0.7 / (sf || (1/96));
            // Which way the shoulder runs is HIS - it is the third click.
            var away = (end[0] >= knee[0]) ? 1 : -1;
            // x/y is the MIDDLE of the words (draw_mark_note centres them), so
            // clearing the end of the line means half the words plus a pad -
            // not a flat nudge. With a flat one the left half of a long note
            // ran back over the shoulder, which is not what the picture shows:
            // there the box STARTS after the line ends.
            //
            // The width is the same rough estimate plan_canvas falls back to
            // (0.6 of the height per letter). It only decides where the words
            // start, so being a few per cent out costs nothing.
            var h = markTextH();
            var half = String(text || '').length * h * 0.6 / 2;
            // The shoulder is kept LEVEL with the knee, the way it is in the
            // picture he sent: he chooses how long it is, not how crooked.
            return {t:'note',
                    x: end[0] + away*(half + off*0.12), y: knee[1],
                    kx: knee[0], ky: knee[1],
                    lx: tip[0],  ly: tip[1],
                    text: text, arrow: !!arrow};
          }

          function moveMark(m, part, dx, dy){
            if(m.t==='dim'){
              if(part==='text'){
                // The mouse moved dx,dy across the sheet; the mark stores the
                // move ALONG the line and ACROSS it, so it survives the line
                // being dragged somewhere else afterwards.
                var ddx=m.x2-m.x1, ddy=m.y2-m.y1;
                var L=Math.sqrt(ddx*ddx+ddy*ddy);
                if(L<1e-9) return;
                var ux=ddx/L, uy=ddy/L;
                var h=(m.h>0)?m.h:markTextH();
                if(m.oa===undefined||m.oa===null) m.oa=0;
                if(m.oc===undefined||m.oc===null) m.oc=h*DIM_LABEL_OFF;
                m.oa += dx*ux + dy*uy;
                m.oc += dx*(-uy) + dy*ux;
              }
              else if(part==='off'){
                // Dragging the dimension LINE pulls it off the wall, the way a
                // dimension behaves in any drawing program. Only the sideways
                // part of the drag counts - sliding it along its own length
                // would mean nothing, and the two clicked points stay exactly
                // on the thing being measured.
                var edx=m.x2-m.x1, edy=m.y2-m.y1;
                var E=Math.sqrt(edx*edx+edy*edy);
                if(E<1e-9) return;
                if(m.off===undefined||m.off===null) m.off=0;
                m.off += dx*(-edy/E) + dy*(edx/E);
              }
              else if(part==='a'){ m.x1+=dx; m.y1+=dy; }
              else if(part==='b'){ m.x2+=dx; m.y2+=dy; }
              else { m.x1+=dx; m.y1+=dy; m.x2+=dx; m.y2+=dy; }
            } else {
              if(part==='tip'){ m.lx+=dx; m.ly+=dy; }
              else if(part==='knee'){ m.kx+=dx; m.ky+=dy; }
              else {
                // moving the words takes the shoulder with them, so the label
                // never drifts away from its own leader
                m.x+=dx; m.y+=dy;
                if(m.kx!==undefined){ m.kx+=dx; m.ky+=dy; }
              }
            }
          }

          function dropMark(){
            // Everything he picked, not just one - that is what the rubber band
            // is for (2026-08-19). Highest index first, or taking one out moves
            // the next.
            var gone = SELS.length ? SELS.slice() : (SEL===null ? [] : [SEL]);
            if(!gone.length) return;
            gone.sort(function(a,b){ return b-a; })
                .forEach(function(i){ if(marks()[i]) marks().splice(i,1); });
            SELS=[]; SEL=null;
            push(); render(); showMarks();
          }

          // A head on the end of the leader, or a bare line. SketchUp's own text
          // tool draws a bare one - the user sent a picture of it and asked for
          // both. Whatever he chose last is what the next note starts with.
          function paintArrow(){
            $('notearrow').className = 'tool' + (STATE.note_arrow===false ? '' : ' on');
          }

          function undoMark(){
            if(!marks().length) return;
            marks().pop();
            SEL=null;
            push(); showMarks();
          }

          function setMode(m){
            cancelCarry();
            BAND=null; SELS=[];
            MODE=m; PEND=null; PEND2=null; PEND3=null; HOVER=null; ERA=null; ERASWEEP=null; ERADONE=false; SNAPPED=null;
            if(m!=='hand') SEL=null;
            ['thand','tdim','tnote','terase'].forEach(function(id){
              $(id).className='tool'+(($(id).id==='t'+m)?' on':'');
            });
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor = m==='hand' ? 'default' : 'crosshair';
            showMarks();
            render();
          }

          function showMarks(){
            var n=marks().length;
            $('tundo').disabled = !n;
            var tip={hand:'לחץ על סימון כדי לבחור · מתח ריבוע לבחירת כמה · Delete מוחק · Alt+גרירה מזיז את התוכנית.',
                     dim:'1 לחץ בהתחלה · 2 לחץ בסוף · 3 משוך את הקו מהקיר ולחץ.',
                     note:'1 לחץ על מה שההערה מדברת עליו · 2 איפה שהקו נשבר · 3 סוף הקו · ואז כתוב.',
                     erase:'העבר על מידה, הערה או קו — הם נצבעים. לחיצה או גרירה מוחקת. המודל לא משתנה.'}[MODE];
            if(MODE==='note'&&PEND&&!PEND2) tip='2 עכשיו לחץ איפה שהקו נשבר.';
            if(MODE==='note'&&PEND&&PEND2&&!PEND3) tip='3 עכשיו לחץ בסוף הקו, שם ייכתב הטקסט.';
            if(MODE==='dim'&&PEND&&!PEND2) tip='2 עכשיו לחץ על הנקודה השנייה.';
            if(MODE==='dim'&&PEND&&PEND2)
              tip='3 משוך את הקו לאיפה שאתה רוצה ולחץ. Esc מבטל.';
            if(MODE==='hand'&&SEL!==null){
              tip='נבחר. לחיצה מרימה, לחיצה שנייה מניחה. Delete מוחק.';
              if(marks()[SEL] && marks()[SEL].t==='dim')
                tip='נבחר. לחץ על הקו או על המספר כדי להרים, הזז, ולחץ שוב להניח. חיצים לדיוק.';
            }
            if(SELS.length>1) tip=SELS.length+' נבחרו. לחיצה מרימה את כולם יחד, Delete מוחק את כולם.';
            if(CARRY||TCARRY) tip='מחזיק — הזז ולחץ כדי להניח. Esc מחזיר.';
            paintDimOff();
            // No free geometry is no longer a dead end - the eraser still
            // takes dimensions and notes (2026-08-19).
            if(MODE==='erase'&&!siteLayer()&&!n)
              tip='אין מה למחוק על הדף הזה.';
            // The mark counter belongs to the marks, not to the rubber.
            $('markinfo').textContent = tip +
              ((n && MODE!=='erase') ? ('  ·  ' + n + ' על הדף') : '');
            headings();
          }

          // ---- dragging the plan -----------------------------------------
          var DRAG=null;
          function hookDrag(){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return;
            svg.style.cursor = MODE==='hand' ? arrowCursor()
                             : MODE==='erase' ? eraserCursor() : 'crosshair';

            svg.onmousemove=function(e){
              if(MODE==='erase'){
                var h3=hitErase(e);
                if(ERASWEEP){
                  // dragging: everything crossed joins the sweep
                  if(h3 && !ERASWEEP.some(function(x){ return sameEra(x,h3); })){
                    ERASWEEP.push(h3);
                  }
                  paintErase();
                } else if(!sameEra(h3,ERA)){
                  ERA=h3; paintErase();
                }
                svg.style.cursor = eraserCursor();
                return;
              }
              if(MODE==='note'&&PEND&&!PEND3){
                var np=atMouse(e);
                if(np){ HOVER=np; render(); }
                return;
              }
              if(MODE==='dim'){
                if(PEND&&PEND2){
                  // the third stage: the mouse is choosing how far off the
                  // wall the line sits. Only the sideways part of where he is
                  // counts - sliding along the measured line means nothing.
                  var mp=atMouse(e);
                  if(mp){ PENDOFF=offsetToward(PEND,PEND2,mp); render(); }
                  return;
                }
                // Show the corner it will lock onto BEFORE he clicks, so he is
                // never guessing whether it caught - the whole point of a snap.
                var hp=snapPoint(atMouse(e));
                if(PEND){ HOVER=hp; render(); }
                else { paintSnap(); }
                return;
              }
              if(MODE==='hand'&&!MDRAG&&!DRAG){
                svg.style.cursor = hitMark(e) ? 'move' : arrowCursor();
              }
            };

            svg.onmousedown=function(e){
              // In the hand tool a mark under the mouse is picked up; empty
              // paper still drags the plan the way it always did.
              if(MODE==='hand'&&!e.shiftKey){
                // Carrying something? Then this click PUTS IT DOWN. Nothing
                // else gets to happen on it.
                if(CARRY){ dropCarry(); e.preventDefault(); return; }
                if(TCARRY){ dropTextCarry(); e.preventDefault(); return; }
                var h=hitMark(e);
                if(h){
                  if(TSEL) closeTextBar();
                  // clicking one thing picks that one thing, and drops
                  // whatever the band had picked before
                  if(SELS.indexOf(h.i)<0) SELS=[h.i];
                  SEL=h.i;
                  MDRAG={part:h.part, at:atMouse(e)};
                  svg.style.cursor='move';
                  render(); showMarks();
                  e.preventDefault();
                  return;
                }
                // Nothing hand-drawn under the mouse - so try any WRITING on
                // the sheet (2026-08-19). This is the one the user was after:
                // the dimensions the plugin draws on the walls itself are not
                // marks, so there was nothing to grab and the click panned the
                // whole plan instead. They could already be picked with two
                // clicks to change their SIZE; now one click picks them and
                // they drag, the way they do in every other program.
                var ht=hitText(e);
                if(ht){
                  SEL=null;
                  TSEL=ht;
                  TDRAG={at:atMouse(e), dx:0, dy:0, moved:false};
                  TCARRY=null;
                  svg.style.cursor='move';
                  paintTextPick(); showMarks();
                  e.preventDefault();
                  return;
                }
                if(TSEL){ closeTextBar(); }
                if(SEL!==null||SELS.length){ SEL=null; SELS=[]; render(); showMarks(); }
              }
              // Write down what this press was given and what the hit test
              // made of it (2026-08-19). See the sheet_probe callback.
              if(MODE==='hand'||MODE==='erase') probeClick(e);
              // The eraser starts a SWEEP: whatever the mouse crosses from
              // here until it is let go goes together, the way dragging the
              // eraser across a drawing works in SketchUp (2026-08-19).
              if(MODE==='erase'&&!e.shiftKey){
                var h4=hitErase(e);
                ERASWEEP = h4 ? [h4] : [];
                ERA=null;
                paintErase();
                e.preventDefault();
                return;
              }
              if(MODE!=='hand'&&!e.shiftKey){ e.preventDefault(); return; }
              // Empty paper in SELECT mode pulls a rubber band, the way it does
              // in SketchUp (2026-08-19). Moving the DRAWING around the sheet
              // used to live on this gesture; it is on Alt-drag now, and the
              // hint line says so. Shift still pans the view.
              if(MODE==='hand' && !e.shiftKey && !e.altKey && e.button!==1 &&
                 (PAGE.views||[])[0]){
                var bp=mouseAt(e);
                if(bp){
                  BAND={x0:bp[0], y0:bp[1], x1:bp[0], y1:bp[1], moved:false};
                  paintBand();
                  e.preventDefault();
                  return;
                }
              }
              var stage=$('stage');
              var pan = e.shiftKey || e.button===1 || !(PAGE.views||[])[0];
              DRAG={x:e.clientX,y:e.clientY,ox:STATE.origin_x,oy:STATE.origin_y,
                    pan:pan, sl:stage.scrollLeft, st:stage.scrollTop};
              svg.style.cursor= pan ? 'move' : arrowCursor();
              e.preventDefault();
            };

            // Two clicks on a note open its words for changing, the way any
            // drawing program does it. The leader and the box stay where they
            // are; only the writing changes.
            svg.ondblclick=function(e){
              var h=hitMark(e);
              // A note's own words come first - two clicks on a note has meant
              // "change what it says" since 2026-08-14 and that is not being
              // taken away. Anything else falls through to the size and weight
              // of whatever writing is under the mouse.
              if(!h || marks()[h.i].t!=='note'){
                var ht=hitText(e);
                if(ht){ hideNoteBar(); openTextBar(ht); e.preventDefault(); }
                return;
              }
              closeTextBar();
              var m=marks()[h.i];
              SEL=h.i;
              EDIT=h.i;
              PEND=null;
              $('notebar').className='on';
              $('notetext').value=m.text||'';
              STATE.note_arrow = m.arrow!==false;
              paintArrow();
              $('notetext').focus();
              $('notetext').select();
              e.preventDefault();
            };

            svg.onclick=function(e){
              if(MODE==='hand'||e.shiftKey) return;
              if(MODE==='erase'){
                // Letting go has already taken the sweep; this click is the
                // browser's echo of it and has nothing left to do.
                if(ERADONE){ ERADONE=false; return; }
                var hi=hitErase(e);
                if(hi===null){
                  $('markinfo').textContent='אין כלום מתחת לעכבר.';
                  return;
                }
                ERA=null; paintErase();
                eraseSweep([hi]);
                return;
              }
              var p=atMouse(e);
              if(!p){ $('markinfo').textContent='אין תוכנית בדף הזה'; return; }
              if(MODE==='dim'){
                // THREE clicks, like every other drawing program:
                //   1  what to measure from   (locks onto a corner)
                //   2  what to measure to     (locks onto a corner)
                //   3  where the line sits    (pull it off the wall)
                if(!PEND){
                  PEND=snapPoint(p); HOVER=PEND; PEND2=null; PENDOFF=dimOff();
                  showMarks(); return;
                }
                if(!PEND2){
                  PEND2=snapPoint(p);
                  PENDOFF=dimOff();      // start from the distance he last used
                  HOVER=PEND2;
                  render(); showMarks(); return;
                }
                // the third click leaves it where he pulled it to
                marks().push({t:'dim',x1:PEND[0],y1:PEND[1],x2:PEND2[0],y2:PEND2[1],
                              off:PENDOFF});
                STATE.dim_off=PENDOFF;   // and the next one starts there too
                PEND=null; PEND2=null; PEND3=null; HOVER=null; SNAPPED=null;
                push(); render(); showMarks();
              } else if(MODE==='note'){
                // A leader is DRAWN, not guessed (2026-08-19). The user, on
                // how Rayon does it: "קודם לחיצה אחת זה מותח קו אחד, ואז עוד
                // לחיצה מותח קו שני, ורק אז כותבים בריבוע מה שרוצים."
                //
                //   1  what the note is about   (the arrow tip, snaps)
                //   2  where the leader bends   (and the words sit there)
                //   3  type
                //
                // It used to be one click and the plugin chose the other two
                // points for him - up and to the right, always - and then he
                // dragged them where he actually wanted them. Two jobs for one
                // note, which is the thing he called out.
                if($('notebar').className==='on') return;   // already typing
                if(!PEND){
                  PEND=snapPoint(p); PEND2=null; PEND3=null; HOVER=PEND;
                  render(); showMarks(); return;
                }
                if(!PEND2){
                  PEND2=p; HOVER=p;
                  render(); showMarks(); return;
                }
                PEND3=p;
                HOVER=p;
                render();
                $('notebar').className='on';
                $('notetext').value='';
                paintArrow();
                $('notetext').focus();
              }
            };
          }

          function onMove(e){
            if(BAND){
              var bq=mouseAt(e);
              if(bq){ BAND.x1=bq[0]; BAND.y1=bq[1]; BAND.moved=true; paintBand(); }
              return;
            }
            // carrying a mark: it follows the mouse, live, with no button held
            if(CARRY){
              var nc=atMouse(e);
              if(nc){
                var ddx=nc[0]-CARRY.at[0], ddy=nc[1]-CARRY.at[1];
                if(CARRY.many && CARRY.many.length>1){
                  // several things picked: they all travel together, and they
                  // travel WHOLE - nobody wants one end of one dimension to
                  // come along and not the other
                  CARRY.many.forEach(function(i){
                    if(marks()[i]) moveMark(marks()[i], 'all', ddx, ddy);
                  });
                } else if(marks()[CARRY.i]){
                  moveMark(marks()[CARRY.i], CARRY.part, ddx, ddy);
                }
                CARRY.at=nc;
                render();
              }
              return;
            }
            // and carrying a label - only the highlight can move live, because
            // Ruby draws the writing; the real move goes on the drop click
            if(TCARRY){
              var nt2=atMouse(e);
              if(nt2){
                TCARRY.dx += nt2[0]-TCARRY.at[0];
                TCARRY.dy += nt2[1]-TCARRY.at[1];
                TCARRY.at = nt2;
                paintTextPick();
              }
              return;
            }
            if(TDRAG){
              var nowt=atMouse(e);
              if(nowt){
                TDRAG.dx += nowt[0]-TDRAG.at[0];
                TDRAG.dy += nowt[1]-TDRAG.at[1];
                TDRAG.at = nowt;
                TDRAG.moved = true;
                paintTextPick();
              }
              return;
            }
            if(MDRAG){
              var now=atMouse(e);
              if(now){
                moveMark(marks()[SEL], MDRAG.part, now[0]-MDRAG.at[0], now[1]-MDRAG.at[1]);
                MDRAG.at=now;
                MDRAG.moved=true;
                render();
              }
              return;
            }
            if(!DRAG) return;
            var stage=$('stage');
            if(DRAG.pan){
              stage.scrollLeft = DRAG.sl-(e.clientX-DRAG.x);
              stage.scrollTop  = DRAG.st-(e.clientY-DRAG.y);
              return;
            }
            var k=fitK()*(ZOOM||1);
            var sf=scaleFactor(STATE.scale);
            STATE.origin_x=DRAG.ox-(e.clientX-DRAG.x)/k/sf;
            STATE.origin_y=DRAG.oy+(e.clientY-DRAG.y)/k/sf;
            render();
          }

          function onUp(){
            if(BAND){
              var band=BAND;
              BAND=null;
              paintBand();
              if(band.moved) pickInBand(band); else { SELS=[]; SEL=null; }
              render(); showMarks();
              return;
            }
            if(ERASWEEP){
              var sweep=ERASWEEP;
              ERASWEEP=null;
              ERADONE=true;          // the click that follows has nothing left to do
              paintErase();
              eraseSweep(sweep);
              return;
            }
            if(TDRAG){
              var tmoved=TDRAG.moved, tdx=TDRAG.dx, tdy=TDRAG.dy, tat=TDRAG.at;
              TDRAG=null;
              var svgt=$('sheetWrap').firstChild;
              if(svgt) svgt.style.cursor='move';
              if(tmoved){ nudgeText(tdx, tdy); }
              else {
                // a plain click on a label PICKS IT UP
                TCARRY={at:tat, dx:0, dy:0};
                paintTextPick(); showMarks();
              }
              return;
            }
            if(MDRAG){
              var moved=MDRAG.moved, mpart=MDRAG.part, mat=MDRAG.at;
              MDRAG=null;
              var svg0=$('sheetWrap').firstChild;
              if(svg0) svg0.style.cursor='move';
              if(moved){ push(); }
              else if(SEL!==null && marks()[SEL]){
                // a plain click PICKS IT UP - it now follows the mouse and the
                // next click puts it down
                CARRY={i:SEL, part:mpart, at:mat,
                       many:SELS.slice(),
                       snap:JSON.parse(JSON.stringify(marks()[SEL])),
                       snaps:JSON.parse(JSON.stringify(SELS.map(function(i){ return marks()[i]; })))};
                showMarks();
              }
              return;
            }
            if(!DRAG) return;
            var moved=!DRAG.pan;
            DRAG=null;
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor = MODE==='hand' ? arrowCursor() : 'crosshair';
            if(moved) push();
          }

          // ---- talking to Ruby -------------------------------------------
          function push(){ sketchup.set_state(JSON.stringify(STATE)); }

          function loadSheet(p){
            DOC=p.doc; STATE=p.state; BOUNDS=p.bounds; SCALES=p.scales;
            if(p.dim_text_h>0) DIM_TEXT_H=p.dim_text_h;
            if(p.dim_label_off!==undefined && p.dim_label_off!==null)
              DIM_LABEL_OFF=p.dim_label_off;
            // Every picture the sheet can show needs an address here, not just
            // the renders. The logo is a picture too - it sits in the title
            // block - and leaving it out of this list is why the user picked a
            // logo and saw nothing but the empty dashed box (2026-08-14).
            URLS={};
            (p.images||[]).forEach(function(im){ if(im.url) URLS[im.path]=im.url; });
            if(p.logo && p.logo.url) URLS[p.logo.path]=p.logo.url;
            if(STATE.active===undefined||STATE.active===null) STATE.active=0;
            ZOOM = STATE.zoom || null;
            PAGE=DOC.pages[0];
            SF={};
            // 12" = 1' means one foot of building is 12 paper inches
            var per={'12"':12,'6"':6,'3"':3,'1-1/2"':1.5,'1"':1,'3/4"':0.75,'1/2"':0.5,
                     '3/8"':0.375,'1/4"':0.25,'3/16"':0.1875,'1/8"':0.125,'3/32"':0.09375,
                     '1/16"':0.0625,'1/32"':0.03125,'1/64"':0.015625,'1/128"':0.0078125};
            SCALES.forEach(function(s){ SF[s]=(per[s]||0.25)/12; });
            // First time on this model: nothing was ever chosen, so open on a
            // scale that shows the whole house instead of an empty-looking
            // sheet. From then on his own choice is kept, whatever it is.
            var first = (STATE.origin_x===undefined||STATE.origin_x===null);
            if(first) centerPlan(true);
            fill('size',p.page_sizes,STATE.size);
            fill('scale',SCALES,STATE.scale);
            $('address').value=DOC.job_address||'';
            $('num').value=STATE.sheet_number||'';
            $('title').value=STATE.sheet_title||'';
            $('ownpage').checked = STATE.tables_own_page!==false;
            siteDropped(STATE.site_count||0, STATE.site_dropped||0);
            showTextScale();
            // The label that is open for changing is a shape out of the OLD
            // document, and the one that just came back is a different object
            // with the same key. Point at the new one, or the blue box would
            // stay where the label used to be and the next change would be
            // worked out from a stale size.
            if(TSEL){
              var again=null;
              eachText(function(s){ if(s.key===TSEL.key) again=s; });
              if(again) TSEL.shape=again; else closeTextBar();
            }
            if(!STATE.marks) STATE.marks=[];
            if(STATE.strip){
              $('strip').className='on';
              $('stripbtn').textContent='הסתר את הדפים';
            }
            buildLayers();
            buildSections();
            showLogo(p.logo);
            fillPages();
            showMarks();
            if(first){ fitPlan(); return; }
            showFit();
            render();
          }

          function applyPages(pages, marksLayer){
            DOC.pages=pages;
            if(marksLayer) putLayer('MODEL', marksLayer);
            if(STATE.active>=pages.length) STATE.active=0;
            fillPages();
            buildLayers();
            showFit();
            render();
          }

          // Drop a layer Ruby just rebuilt in over the one we were holding.
          function putLayer(canvasName, lay){
            var cv=(DOC.canvases||[]).filter(function(c){ return c.name===canvasName; })[0];
            if(!cv) return;
            var at=-1;
            cv.layers.forEach(function(l,i){ if(l.name===lay.name) at=i; });
            if(at>=0) cv.layers[at]=lay; else cv.layers.push(lay);
          }

          // One list for every sheet in the set - plan, schedules, renders.
          // Click a row to go there, the TICK says whether it goes into the
          // PDF, the x throws it away. Since 2026-08-19 the x is on every row
          // including the plan sheet, and the tick is the answer to "print
          // only some of these" - two different questions, two controls.
          // ---- the page strip ---------------------------------------------
          //
          // Every sheet drawn small, down the far side of the drawing. Same
          // routine as the big one - see sheetSVG - so a thumbnail can never
          // show something the sheet does not.
          function goToPage(i){
            if(!DOC||!DOC.pages.length) return;
            STATE.active=Math.max(0, Math.min(DOC.pages.length-1, i));
            fillPages(); showFit(); render(); push();
          }

          function paintStrip(){
            var box=$('strip');
            if(box.className!=='on'){ box.innerHTML=''; return; }
            // Drawn at 520 across and shown at 166. shapeSVG throws away any
            // text under 1.5 pixels, because at that size it is a smudge - so
            // a thumbnail built at its finished size came out with no words on
            // it at all (t36 caught this). Draw it big, let the browser shrink
            // it, and the little sheet says the same things the big one does.
            var W=520;
            box.innerHTML='';
            var skip=(STATE.pdf_skip||[]);
            (DOC.pages||[]).forEach(function(pg,i){
              var key=pageKey(pg);
              var out=skip.indexOf(key)>=0;
              var d=document.createElement('div');
              d.className='thumb'+(i===(STATE.active||0)?' sel':'')+(out?' off':'');
              d.onclick=function(){ goToPage(i); };
              d.innerHTML='<div class="sheet">'+sheetSVG(pg, W/pg.width, false)+'</div>';
              // the tick lives HERE now - next to the picture of the sheet, so
              // he is choosing pages he can see
              var cap=document.createElement('div');
              cap.className='cap';
              var c=document.createElement('input');
              c.type='checkbox'; c.checked=!out;
              c.title='לצרף את הדף הזה ל-PDF';
              c.onclick=function(e){ e.stopPropagation(); togglePdf(key); };
              cap.appendChild(c);
              var t=document.createElement('span');
              t.textContent=(pg.sheet_number||('#'+(i+1)))+'  '+pg.name;
              cap.appendChild(t);
              d.appendChild(cap);
              box.appendChild(d);
            });
            var sel=box.querySelector('.thumb.sel');
            if(sel && sel.scrollIntoView) sel.scrollIntoView({block:'nearest'});
          }

          function toggleStrip(){
            var box=$('strip');
            var on = box.className!=='on';
            box.className = on ? 'on' : '';
            $('stripbtn').textContent = on ? 'הסתר את הדפים' : 'הצג את הדפים ובחר מה יוצא ל-PDF';
            STATE.strip = on;
            paintStrip();
            render();                        // the drawing area just changed width
          }

          // The name a sheet answers to in the settings. The SAME three lines
          // as PlanSheetDialog.page_key on the Ruby side - not the number and
          // not the position, because both of those move the moment a sheet is
          // added or thrown away, and a tick that moved with them would
          // quietly start meaning a different sheet.
          function pageKey(p){
            var k=(p&&p.kind)||'plan';
            return k==='image' ? ('image:'+p.ref) : k;
          }

          // The tick keeps the sheet in the set and only leaves it out of the
          // print. Nothing is deleted here and nothing is rebuilt - the state
          // goes back to Ruby and the PDF reads it at export time.
          function togglePdf(key){
            var s=(STATE.pdf_skip||[]).slice();
            var at=s.indexOf(key);
            if(at>=0) s.splice(at,1); else s.push(key);
            STATE.pdf_skip=s;
            fillPages();      // which repaints the strip too
            push();
          }

          function fillPages(){
            var box=$('pages'); box.innerHTML='';
            var skip=(STATE.pdf_skip||[]);
            var off=0;
            (DOC.pages||[]).forEach(function(p,i){
              var key=pageKey(p);
              var out=skip.indexOf(key)>=0;
              if(out) off++;
              var row=document.createElement('div');
              row.className='pg'+(i===(STATE.active||0)?' sel':'')+(out?' off':'');
              row.onclick=function(){ $('pages').focus(); goToPage(i); };
              // The tick moved to the THUMBNAILS (2026-08-19). The user:
              // "אני רוצה שהווי יעבור לתמונות של הדפים... כי מרגיש לי שיותר קל
              // לבחור דפים שרואים בהוצאה ל-PDF." So this list is the x - what
              // is in the set - and the strip is the tick - what gets printed.
              // A row still shows struck through when its sheet is out, which
              // tells him where things stand without being a second control.
              var num=document.createElement('b');
              num.textContent=p.sheet_number||('#'+(i+1));
              row.appendChild(num);
              var nm=document.createElement('span');
              nm.textContent=p.name; nm.title=p.name;
              row.appendChild(nm);
              // and the x - every sheet, the plan sheet included (2026-08-19).
              var x=document.createElement('button');
              x.textContent='×'; x.title='למחוק את הדף הזה מהתוכנית';
              x.onclick=function(e){
                e.stopPropagation();
                sketchup.delete_page(JSON.stringify({kind:(p.kind||'plan'), ref:p.ref}));
              };
              row.appendChild(x);
              box.appendChild(row);
            });
            // the one page that cannot be added back from anywhere else
            if(STATE.drop_plan){
              var b=document.createElement('button');
              b.id='planback'; b.textContent='החזר את דף התוכנית';
              b.onclick=function(){ sketchup.restore_plan(); };
              box.appendChild(b);
            }
            var t=$('pagestag');
            if(t){
              var n=(DOC.pages||[]).length;
              t.textContent = off ? ((n-off)+' מתוך '+n+' ל-PDF') : '';
            }
            var sel=box.querySelector('.pg.sel');
            if(sel && sel.scrollIntoView) sel.scrollIntoView({block:'nearest'});
            paintStrip();
          }

          function fill(id,list,val){
            var el=$(id); el.innerHTML='';
            list.forEach(function(s){
              var o=document.createElement('option'); o.value=s; o.textContent=s;
              if(s===val) o.selected=true; el.appendChild(o);
            });
          }

          // ---- the boxes that open ----------------------------------------
          //
          // The side used to be one long column with everything on show at
          // once. Now every group is a box with a heading you press. Only the
          // page list starts open; the rest wait until they are wanted.
          //
          // Each heading carries a small note of what is inside - how many
          // layers are switched off, how many marks are on the sheet - because
          // a setting that is both changed AND out of sight is how a drawing
          // comes out wrong and nobody can see why.
          var OPEN_AT_FIRST = {pages:true};

          function sections(){
            return document.querySelectorAll('#side .sec');
          }

          function openSection(key, on){
            var l=sections();
            for(var i=0;i<l.length;i++){
              if(l[i].getAttribute('data-k')!==key) continue;
              l[i].className='sec'+(on?' open':'');
              var ar=l[i].querySelector('.ar');
              if(ar) ar.innerHTML = on ? '&#9662;' : '&#9656;';
            }
            if(!STATE.open) STATE.open={};
            STATE.open[key]=!!on;
          }

          function isOpen(key){
            var o=STATE.open||{};
            return o[key]===undefined ? (OPEN_AT_FIRST[key]===true) : !!o[key];
          }

          function buildSections(){
            var l=sections();
            for(var i=0;i<l.length;i++){
              (function(sec){
                var key=sec.getAttribute('data-k');
                sec.querySelector('h4').onclick=function(){
                  openSection(key, sec.className.indexOf('open')<0);
                  push();
                };
                openSection(key, isOpen(key));
              })(l[i]);
            }
          }

          function tag(id, text){
            var el=$(id);
            if(el) el.textContent = text || '';
          }

          function layerCount(){
            var off=(STATE.hidden||[]).length;
            tag('laycount', off ? (off + ' כבויות') : '');
          }

          // what each heading says about itself when it is shut
          function headings(){
            layerCount();
            var n=marks().length;
            tag('markstag', n ? (n + ' על הדף') : '');
            var imgs=(DOC&&DOC.pages||[]).filter(function(p){ return p.kind==='image'; }).length;
            tag('imgtag', imgs ? (imgs + ' דפים') : '');
            tag('papertag', (STATE.size||'') + ' · ' + (STATE.scale||''));
            tag('sitetag', STATE.site_count ? (STATE.site_count + ' קווים') : '');
          }

          function buildLayers(){
            var box=$('layers'); box.innerHTML='';
            var names=[];
            function add(n){ if(names.indexOf(n)<0) names.push(n); }
            (DOC.canvases||[]).forEach(function(c){ c.layers.forEach(function(l){ add(l.name); }); });
            // every sheet's layers, so a layer that moved to another page can
            // still be turned off from here
            (DOC.pages||[]).forEach(function(p){ (p.layers||[]).forEach(function(l){ add(l.name); }); });
            if(STATE.hidden.indexOf('SCHEDULES')>=0) add('SCHEDULES');
            names.forEach(function(n){
              var lab=document.createElement('label'); lab.className='chk';
              var cb=document.createElement('input'); cb.type='checkbox';
              cb.checked=STATE.hidden.indexOf(n)<0;
              cb.onchange=function(){
                var i=STATE.hidden.indexOf(n);
                if(cb.checked){ if(i>=0) STATE.hidden.splice(i,1); } else if(i<0) STATE.hidden.push(n);
                layerCount(); render(); push();
              };
              lab.appendChild(cb);
              lab.appendChild(document.createTextNode(n));
              box.appendChild(lab);
            });
            layerCount();
          }

          function centerPlan(quiet){
            if(!BOUNDS) return;
            STATE.origin_x=(BOUNDS[0]+BOUNDS[2])/2;
            STATE.origin_y=(BOUNDS[1]+BOUNDS[3])/2;
            if(!quiet){ render(); push(); }
          }

          // The user pressed a button, so this one MAY change the scale: the
          // biggest one in his list that holds the whole drawing, centred.
          function fitPlan(){
            var pg=activePage(), v=pg&&(pg.views||[])[0];
            if(!BOUNDS||!v) return;
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              if((BOUNDS[2]-BOUNDS[0])*SF[s]<=v.w&&(BOUNDS[3]-BOUNDS[1])*SF[s]<=v.h) best=s;
            });
            if(best){ STATE.scale=best; $('scale').value=best; }
            centerPlan(true);
            ZOOM=null; STATE.zoom=null;
            showFit(); render(); push();
          }

          // says what would fit. never changes the scale by itself.
          function showFit(){
            var pg=activePage();
            var v=pg&&(pg.views||[])[0];
            if(!BOUNDS||!v){ $('fit').textContent=''; return; }
            var sf=scaleFactor(STATE.scale);
            var mw=(BOUNDS[2]-BOUNDS[0])*sf, mh=(BOUNDS[3]-BOUNDS[1])*sf;
            if(mw<=v.w&&mh<=v.h){ $('fit').textContent='נכנס בדף ✓'; $('fit').style.color='#8fdf8f'; return; }
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              var f=SF[s];
              if((BOUNDS[2]-BOUNDS[0])*f<=v.w&&(BOUNDS[3]-BOUNDS[1])*f<=v.h) best=s;
            });
            $('fit').textContent='לא נכנס. הכי גדול שנכנס: '+(best||'—');
            $('fit').style.color='#f0a860';
          }

          // ---- carrying dragged / ticked files across ----------------------
          //
          // The window never learns where a file lives, only what is in it. So
          // the bytes go to Ruby in pieces and Ruby writes them down.
          //
          // Each piece is base64'd on its own and decoded on its own at the
          // other end, so the pieces can be any size - the bytes are appended,
          // never the text. 786432 is three quarters of a megabyte: big enough
          // that a 7MB render is ten trips and not two hundred, small enough
          // that no single message is enormous. It also divides by three, so
          // no piece wastes room on padding.
          //
          // Ruby answers every piece before the next one is sent. Without that
          // the window would race ahead and queue a whole 100MB of messages.
          var CHUNK = 786432;
          var DROP = { list:[], fi:0, off:0, busy:false };

          function takeFiles(list){
            if(DROP.busy) return;
            var files=[];
            for(var i=0;i<list.length;i++){
              var f=list[i];
              if(/\.(jpe?g|png)$/i.test(f.name)) files.push(f);
            }
            if(!files.length){ $('imginfo').textContent='לא היו תמונות בגרירה'; return; }
            DROP.list=files; DROP.fi=0; DROP.busy=true;
            setBusy(true);
            nextFile();
          }

          function setBusy(on){
            ['addmany','pdf','rebuild'].forEach(function(id){
              if($(id)) $(id).disabled=on;
            });
          }

          function nextFile(){
            if(DROP.fi>=DROP.list.length){
              $('imginfo').textContent='מסיים...';
              sketchup.drop_finish();
              DROP.busy=false; setBusy(false);
              return;
            }
            var f=DROP.list[DROP.fi];
            $('imginfo').textContent='מעתיק '+(DROP.fi+1)+' מתוך '+DROP.list.length+
                                     ' · '+f.name;
            sketchup.drop_begin(JSON.stringify({name:f.name,size:f.size}));
          }

          function dropReady(already){
            if(already){ sketchup.drop_end(); return; }
            DROP.off=0; sendChunk();
          }

          function sendChunk(){
            var f=DROP.list[DROP.fi];
            if(DROP.off>=f.size){ sketchup.drop_end(); return; }
            var end=Math.min(DROP.off+CHUNK,f.size);
            var blob=f.slice(DROP.off,end);
            DROP.off=end;
            var r=new FileReader();
            r.onload=function(){
              var s=r.result;
              sketchup.drop_chunk(s.substring(s.indexOf(',')+1));
            };
            r.onerror=function(){ dropFailed('לא הצלחתי לקרוא את '+f.name); };
            r.readAsDataURL(blob);
          }

          function chunkDone(){ sendChunk(); }
          function fileDone(){ DROP.fi++; nextFile(); }
          function dropFailed(m){
            $('imginfo').textContent='שגיאה: '+m;
            DROP.busy=false; setBusy(false);
          }

          // ---- the logo ----------------------------------------------------
          function showLogo(l){
            var img=$('logoshow');
            if(l && l.url && l.there){
              img.src=l.url; img.className='on';
              $('logoinfo').textContent=l.name;
              tag('settag','לוגו');
              $('logoclear').style.display='';
            } else {
              img.removeAttribute('src'); img.className='';
              $('logoinfo').textContent = l && !l.there
                ? ('הקובץ לא נמצא: ' + l.name) : '';
              tag('settag','');
              $('logoclear').style.display = l ? '' : 'none';
            }
          }

          function logoDone(err){
            $('logoinfo').textContent = err ? ('שגיאה: '+err) : '';
          }

          function imageReport(n, err){
            $('imginfo').textContent = err ? ('שגיאה: '+err)
              : (n ? (n===1 ? 'נוספה תמונה אחת' : ('נוספו '+n+' תמונות'))
                   : 'לא נבחר כלום');
          }

          // ---- how big the writing is -------------------------------------
          //
          // Ruby owns the sizes. These boxes only say what they are and send a
          // new number; the picture comes back from the same routine that
          // writes the PDF, so what he sees is what prints.
          var TS_FIELDS = { dims:'tsDims', rooms:'tsRooms',
                            tags:'tsTags', tables:'tsTables' };

          function textScale(){ return STATE.text_scale||(STATE.text_scale={}); }

          function showTextScale(){
            var ts=textScale(), off=0;
            for(var k in TS_FIELDS){
              var v=ts[k]; if(v===undefined||v===null||!(+v>0)) v=100;
              $(TS_FIELDS[k]).value = +v;
              if(+v!==100) off++;
            }
            // The heading says so when something is not at 100, because the
            // box is shut most of the time and a shrunken tag three sheets
            // later is otherwise a mystery.
            $('texttag').textContent = off ? (off+' שונו') : '';
            $('tsReset').disabled = !off;
          }

          function sendTextScale(){
            var out={};
            for(var k in TS_FIELDS){
              var v=parseFloat($(TS_FIELDS[k]).value);
              if(!isFinite(v)||v<=0) v=100;
              v=Math.min(400,Math.max(25,v));
              $(TS_FIELDS[k]).value=v;
              out[k]=v;
            }
            textScale();
            for(var k2 in out) STATE.text_scale[k2]=out[k2];
            showTextScale();
            sketchup.set_text_scale(JSON.stringify(out));
          }

          function resetTextScale(){
            for(var k in TS_FIELDS) $(TS_FIELDS[k]).value=100;
            sendTextScale();
          }

          function siteDone(n, err){
            $('siteinfo').textContent = err ? ('לא נוסף: ' + err)
              : (n ? (n + ' קווים על הדף') : 'אין גיאומטריה חופשית');
          }

          // After a line is rubbed out, or after they all come back. Says how
          // many are left AND how many are waiting to be put back, so the
          // "put them back" button is never a button whose effect is a mystery.
          function siteDropped(left, dropped){
            var t = left ? (left + ' קווים על הדף') : 'אין גיאומטריה חופשית';
            if(dropped) t += '  ·  ' + dropped + ' נמחקו';
            $('siteinfo').textContent = t;
            $('undrop').disabled = !dropped;
          }

          // Says where it got to, so an empty result is never a mystery.
          function siteReport(sel, r){
            var t = 'נבחרו ' + sel + ' · קווים במודל ' + r.edges +
                    ' · נוספו ' + r.lines + ' · על הדף ' + (r.total||r.lines);
            if(r.skipped) t += ' · ' + r.skipped + ' דולגו';
            if(!r.edges)      t += '  ⟵ אין קווים במה שבחרת';
            else if(!r.lines) t += '  ⟵ כל הקווים סוננו';
            else if(!r.kept)  t += '  ⟵ גדול מדי לשמירה, יישאר עד סגירת סקצ\'אפ';
            $('siteinfo').textContent = t;
          }

          function exportDone(path){
            $('msg').textContent = path ? ('נשמר: '+path) : 'בוטל';
          }
          function exportFailed(m){ $('msg').textContent='שגיאה: '+m; }

          // ---- wiring -----------------------------------------------------
          window.addEventListener('load',function(){
            $('size').onchange=function(){ STATE.size=this.value; push(); };
            $('scale').onchange=function(){ STATE.scale=this.value; showFit(); render(); push(); };
            $('ownpage').onchange=function(){ STATE.tables_own_page=this.checked; push(); };
            $('stage').addEventListener('wheel',function(e){
              e.preventDefault();
              zoomAt(e.clientX, e.clientY, (ZOOM||1)*(e.deltaY<0?1.15:1/1.15));
            },{passive:false});
            window.addEventListener('mousemove',onMove);
            window.addEventListener('mouseup',onUp);
            $('land').onclick=function(){ STATE.orientation='landscape'; push(); };
            $('port').onclick=function(){ STATE.orientation='portrait'; push(); };
            $('center').onclick=function(){ centerPlan(false); };
            $('fitplan').onclick=function(){ fitPlan(); };
            $('rebuild').onclick=function(){ sketchup.rebuild(); };
            $('addsel').onclick=function(){
              $('siteinfo').textContent='קורא מהמודל...'; sketchup.add_selection();
            };
            $('clrsel').onclick=function(){ sketchup.clear_selection(); };
            $('thand').onclick=function(){ setMode('hand'); };
            $('tdim').onclick=function(){ setMode('dim'); };
            $('tnote').onclick=function(){ setMode('note'); };
            $('terase').onclick=function(){ setMode('erase'); };
            $('tundo').onclick=function(){ undoMark(); };
            $('undrop').onclick=function(){ sketchup.restore_site_lines(); };
            for(var tk in TS_FIELDS){
              // change, not input: typing "1" on the way to "130" would send a
              // sheet at 25% and a full redraw with it.
              $(TS_FIELDS[tk]).onchange=function(){ sendTextScale(); };
            }
            $('tsReset').onclick=function(){ resetTextScale(); };

            $('txsize').onchange=function(){ sendTextMark(); };
            $('txsize').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); sendTextMark(); }
            };
            $('txbold').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              sendTextMark();
            };
            $('txitalic').onclick=function(){
              this.className='tool'+(this.className.indexOf('on')>=0?'':' on');
              sendTextMark();
            };
            // Back to whatever its group says, rather than back to 100 - the
            // group is the drawing's own standard and that is what "normal"
            // means for one label inside it.
            $('txreset').onclick=function(){
              if(!TSEL) return;
              sketchup.set_text_mark(JSON.stringify({key:TSEL.key, clear:true}));
              closeTextBar();
            };
            $('txdone').onclick=function(){ closeTextBar(); };
            $('txwhat').onmousedown=function(e){ dragTextBar(e); };
            $('txwhat').title='גרור כדי להזיז את החלונית';

            $('stripbtn').onclick=function(){ toggleStrip(); };
            $('logopick').onclick=function(){
              $('logoinfo').textContent='בוחר קובץ...'; sketchup.choose_logo();
            };
            $('logoclear').onclick=function(){ sketchup.clear_logo(); };

            // Once he has clicked a page in the list, up and down walk through
            // the set without going back to the mouse.
            $('pages').onkeydown=function(e){
              if(e.key==='ArrowDown'||e.key==='ArrowUp'){
                e.preventDefault();
                goToPage((STATE.active||0)+(e.key==='ArrowDown'?1:-1));
              } else if(e.key==='Home'){ e.preventDefault(); goToPage(0); }
              else if(e.key==='End'){ e.preventDefault(); goToPage((DOC.pages||[]).length-1); }
            };

            // Delete removes what is picked. Not while he is typing a note, and
            // not while the cursor is in the address or sheet-number boxes.
            window.addEventListener('keydown',function(e){
              var t=(e.target&&e.target.tagName)||'';
              if(t==='INPUT'||t==='SELECT'||t==='TEXTAREA') return;
              if(e.target && e.target.id==='pages') return;   // the list handles its own keys
              // The space bar picks the arrow up, the way it does in SketchUp.
              // Whatever tool he is in, one thump on the widest key on the
              // keyboard puts him back in select-and-drag - his words, and the
              // same habit the modelling window gives him.
              if(e.key===' '||e.code==='Space'||e.key==='Spacebar'){
                e.preventDefault();
                closeNote(); closeTextBar();
                setMode('hand');
                return;
              }
              // Nudging the picked dimension's number, for when the mouse is
              // not accurate enough (2026-08-19). The arrows move it the way
              // he sees it; what is STORED is along-and-across the line, so it
              // stays put when the dimension itself is moved later.
              // Shift = a whole text height a press, otherwise a quarter.
              var ar={ArrowLeft:[-1,0],ArrowRight:[1,0],
                      ArrowUp:[0,1],ArrowDown:[0,-1]}[e.key];
              if(ar && MODE==='hand' && SEL!==null && marks()[SEL] &&
                 marks()[SEL].t==='dim'){
                e.preventDefault();
                var st1=markTextH()*(e.shiftKey?1:0.25);
                moveMark(marks()[SEL],'text',ar[0]*st1,ar[1]*st1);
                push(); render(); showMarks();
                return;
              }
              // and the same for a picked LABEL - the plugin's own dimensions,
              // a room name, a tag
              if(ar && MODE==='hand' && SEL===null && TSEL){
                e.preventDefault();
                var st2=markTextH()*(e.shiftKey?1:0.25);
                nudgeText(ar[0]*st2, ar[1]*st2);
                return;
              }
              if(e.key==='Delete'||e.key==='Backspace'){
                if(SEL!==null){ e.preventDefault(); dropMark(); }
              } else if(e.key==='Escape'){
                cancelCarry();
                BAND=null; SELS=[];
                PEND=null; PEND2=null; PEND3=null; HOVER=null; SEL=null; ERA=null;
                closeTextBar();
                render(); showMarks();
              }
            });

            $('dimoff').onchange=function(){ setDimOff(parseFloat(this.value)); };
            $('dimoff').onkeydown=function(e){
              if(e.key==='Enter'){ e.preventDefault(); this.blur(); }
            };

            $('notearrow').onclick=function(){
              STATE.note_arrow = (STATE.note_arrow===false);
              paintArrow();
              $('notetext').focus();
            };

            // One place knows how to shut this bar; see hideNoteBar above.
            function closeNote(){ hideNoteBar(); }
            function saveNote(){
              var t=$('notetext').value.trim();
              if(EDIT!==null && marks()[EDIT]){
                // changing one that is already there
                if(t){
                  marks()[EDIT].text=t;
                  marks()[EDIT].arrow=(STATE.note_arrow!==false);
                } else {
                  marks().splice(EDIT,1);       // emptied it = threw it away
                  SEL=null;
                }
                closeNote();
                push(); showMarks();
                return;
              }
              if(t&&PEND&&PEND2&&PEND3){
                marks().push(noteMark(PEND, PEND2, PEND3, t,
                                      STATE.note_arrow!==false,
                                      scaleFactor(STATE.scale)));
                SEL=marks().length-1;
              }
              closeNote();
              push(); render(); showMarks();
            }
            $('noteok').onclick=saveNote;
            $('notecancel').onclick=function(){ closeNote(); showMarks(); };
            $('notetext').onkeydown=function(e){
              if(e.key==='Enter') saveNote();
              else if(e.key==='Escape'){ closeNote(); showMarks(); }
            };

            $('addmany').onclick=function(){ $('filepick').value=''; $('filepick').click(); };
            $('filepick').onchange=function(){ takeFiles(this.files||[]); };

            // Drop anywhere on the window. The browser opens a dropped file in
            // place unless BOTH of these are stopped, which loses the sheet.
            var deep=0;
            window.addEventListener('dragenter',function(e){
              e.preventDefault(); deep++; $('curtain').className='on';
            });
            window.addEventListener('dragover',function(e){ e.preventDefault(); });
            window.addEventListener('dragleave',function(e){
              e.preventDefault(); if(--deep<=0){ deep=0; $('curtain').className=''; }
            });
            window.addEventListener('drop',function(e){
              e.preventDefault(); deep=0; $('curtain').className='';
              takeFiles((e.dataTransfer&&e.dataTransfer.files)||[]);
            });
            $('pdf').onclick=function(){ $('msg').textContent='שומר...'; sketchup.export_pdf(JSON.stringify(STATE)); };
            ['address','num','title'].forEach(function(id){
              $(id).onchange=function(){
                STATE.address=$('address').value;
                STATE.sheet_number=$('num').value;
                STATE.sheet_title=$('title').value;
                push();
              };
            });
            window.addEventListener('resize',render);
            sketchup.sheet_ready();
          });
          