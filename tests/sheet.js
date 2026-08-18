
          var DOC=null, STATE=null, PAGE=null, BOUNDS=null, SCALES=[];
          var URLS={};                // path -> file:/// address, for the sheet
          var MODE='hand';            // hand | dim | note | erase
          var ERA=null;               // which SITE line the rubber is over
          var PEND=null;              // the first point of a dimension
          var HOVER=null;             // where the mouse is, in model inches
          var VIEW=null;              // how to get from the screen to the model
          var SEL=null;               // which mark is picked, by place in the list
          var EDIT=null;              // which note's words are open for changing
          var MDRAG=null;             // a mark being moved right now
          var GRAB=10;                // how near the mouse has to be, in pixels
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
              if(SEL!==null && marks()[SEL] && VIEW){
                var sm=marks()[SEL];
                var dot=function(p){
                  return '<circle cx="'+p[0].toFixed(1)+'" cy="'+p[1].toFixed(1)+
                         '" r="4" fill="#fff" stroke="#1f6feb" stroke-width="2"/>';
                };
                if(sm.t==='dim'){
                  var pa=screenOf(sm.x1,sm.y1), pb=screenOf(sm.x2,sm.y2);
                  o.push('<line x1="'+pa[0].toFixed(1)+'" y1="'+pa[1].toFixed(1)+
                         '" x2="'+pb[0].toFixed(1)+'" y2="'+pb[1].toFixed(1)+
                         '" stroke="#1f6feb" stroke-width="2" opacity=".55"/>');
                  o.push(dot(pa)); o.push(dot(pb));
                } else {
                  var pc=screenOf(sm.x,sm.y);
                  o.push('<circle cx="'+pc[0].toFixed(1)+'" cy="'+pc[1].toFixed(1)+
                         '" r="9" fill="none" stroke="#1f6feb" stroke-width="2"/>');
                  if(sm.kx!==undefined) o.push(dot(screenOf(sm.kx,sm.ky)));
                  if(sm.lx!==undefined) o.push(dot(screenOf(sm.lx,sm.ly)));
                }
              }

              // the dimension being stretched right now, before it is real
              if(PEND && HOVER && VIEW){
                var a=VIEW.toPaper(PEND[0],PEND[1]), b=VIEW.toPaper(HOVER[0],HOVER[1]);
                o.push('<line x1="'+(a[0]*k).toFixed(1)+'" y1="'+((ph-a[1])*k).toFixed(1)+
                       '" x2="'+(b[0]*k).toFixed(1)+'" y2="'+((ph-b[1])*k).toFixed(1)+
                       '" stroke="#1f6feb" stroke-width="1.5" stroke-dasharray="4 3"/>');
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
            var X=p[0], Y=p[1], best=null, bd=GRAB;
            marks().forEach(function(m,i){
              if(m.t==='dim'){
                var a=screenOf(m.x1,m.y1), b=screenOf(m.x2,m.y2);
                var da=Math.hypot(a[0]-X,a[1]-Y), db=Math.hypot(b[0]-X,b[1]-Y);
                if(da<bd){ bd=da; best={i:i,part:'a'}; }
                if(db<bd){ bd=db; best={i:i,part:'b'}; }
                var ds=distToSeg(X,Y,a,b);
                if(ds<bd){ bd=ds; best={i:i,part:'all'}; }
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
          function paintErase(){
            var svg=$('sheetWrap').firstChild; if(!svg) return;
            var old=svg.querySelector('#erahi');
            if(old&&old.parentNode) old.parentNode.removeChild(old);
            if(MODE!=='erase'||ERA===null||!VIEW) return;
            var lay=siteLayer(); if(!lay) return;
            var s=(lay.shapes||[])[ERA]; if(!s||!s.points) return;
            var pts=s.points.map(function(q){
              var t=screenOf(q[0],q[1]);
              return t[0].toFixed(1)+','+t[1].toFixed(1);
            }).join(' ');
            var n=document.createElementNS('http://www.w3.org/2000/svg','polyline');
            n.setAttribute('id','erahi');
            n.setAttribute('points',pts);
            n.setAttribute('fill','none');
            n.setAttribute('stroke','#e5484d');
            n.setAttribute('stroke-width','3');
            n.setAttribute('stroke-linecap','round');
            svg.appendChild(n);
          }

          // ---- one label at a time ----------------------------------------
          //
          // Double-click any writing on the sheet - a room name, a tag, a
          // dimension, a note - and set that one. Ruby keeps the choice under
          // the label's key (PlanCanvas.text_key) so it survives the sheet
          // being rebuilt from the model.
          var TSEL=null;   // {key, shape, paper} - the label being changed

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
            $('notebar').className=''; PEND=null; EDIT=null;
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
            var b=textBox(TSEL.shape, TSEL.paper);
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

          function moveMark(m, part, dx, dy){
            if(m.t==='dim'){
              if(part==='a'){ m.x1+=dx; m.y1+=dy; }
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
            if(SEL===null) return;
            marks().splice(SEL,1);
            SEL=null;
            push(); showMarks();
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
            MODE=m; PEND=null; HOVER=null; ERA=null;
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
            var tip={hand:'לחץ על סימון כדי לבחור, Delete מוחק.',
                     dim:'לחץ בהתחלה ואז בסוף.',
                     note:'לחץ על מה שההערה מדברת עליו.',
                     erase:'לחץ על קו כדי למחוק אותו מהתוכנית. המודל לא משתנה.'}[MODE];
            if(MODE==='hand'&&SEL!==null) tip='נבחר. Delete מוחק, גרירה מזיזה.';
            if(MODE==='erase'&&!siteLayer())
              tip='אין גיאומטריה חופשית על הדף, או ששכבת SITE כבויה.';
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
            svg.style.cursor = MODE==='hand' ? 'grab' : 'crosshair';

            svg.onmousemove=function(e){
              if(MODE==='erase'){
                var h3=hitSite(e);
                if(h3!==ERA){ ERA=h3; paintErase(); }
                svg.style.cursor = (ERA===null) ? 'crosshair' : 'pointer';
                return;
              }
              if(MODE==='dim'&&PEND){ HOVER=atMouse(e); render(); return; }
              if(MODE==='hand'&&!MDRAG&&!DRAG){
                svg.style.cursor = hitMark(e) ? 'move' : 'grab';
              }
            };

            svg.onmousedown=function(e){
              // In the hand tool a mark under the mouse is picked up; empty
              // paper still drags the plan the way it always did.
              if(MODE==='hand'&&!e.shiftKey){
                var h=hitMark(e);
                if(h){
                  SEL=h.i;
                  MDRAG={part:h.part, at:atMouse(e)};
                  svg.style.cursor='move';
                  render(); showMarks();
                  e.preventDefault();
                  return;
                }
                if(SEL!==null){ SEL=null; render(); showMarks(); }
              }
              if(MODE!=='hand'&&!e.shiftKey){ e.preventDefault(); return; }
              var stage=$('stage');
              var pan = e.shiftKey || e.button===1 || !(PAGE.views||[])[0];
              DRAG={x:e.clientX,y:e.clientY,ox:STATE.origin_x,oy:STATE.origin_y,
                    pan:pan, sl:stage.scrollLeft, st:stage.scrollTop};
              svg.style.cursor= pan ? 'move' : 'grabbing';
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
                var hi=hitSite(e);
                if(hi===null){
                  $('markinfo').textContent='אין קו מתחת לעכבר. רק גיאומטריה חופשית נמחקת כאן.';
                  return;
                }
                ERA=null; paintErase();
                sketchup.drop_site_line(JSON.stringify({i:hi}));
                return;
              }
              var p=atMouse(e);
              if(!p){ $('markinfo').textContent='אין תוכנית בדף הזה'; return; }
              if(MODE==='dim'){
                if(!PEND){ PEND=p; HOVER=p; showMarks(); return; }
                marks().push({t:'dim',x1:PEND[0],y1:PEND[1],x2:p[0],y2:p[1]});
                PEND=null; HOVER=null;
                push(); showMarks();
              } else if(MODE==='note'){
                PEND=p;
                $('notebar').className='on';
                $('notetext').value='';
                paintArrow();
                $('notetext').focus();
              }
            };
          }

          function onMove(e){
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
            if(MDRAG){
              var moved=MDRAG.moved;
              MDRAG=null;
              var svg0=$('sheetWrap').firstChild;
              if(svg0) svg0.style.cursor='move';
              if(moved) push();
              return;
            }
            if(!DRAG) return;
            var moved=!DRAG.pan;
            DRAG=null;
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor='grab';
            if(moved) push();
          }

          // ---- talking to Ruby -------------------------------------------
          function push(){ sketchup.set_state(JSON.stringify(STATE)); }

          function loadSheet(p){
            DOC=p.doc; STATE=p.state; BOUNDS=p.bounds; SCALES=p.scales;
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
          // Click a row to go there, press the x to throw that sheet away.
          // The plan sheet has no x: it is the drawing, not an extra.
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
            (DOC.pages||[]).forEach(function(pg,i){
              var d=document.createElement('div');
              d.className='thumb'+(i===(STATE.active||0)?' sel':'');
              d.onclick=function(){ goToPage(i); };
              d.innerHTML='<div class="sheet">'+sheetSVG(pg, W/pg.width, false)+
                          '</div><div class="cap">'+
                          esc((pg.sheet_number||('#'+(i+1)))+'  '+pg.name)+'</div>';
              box.appendChild(d);
            });
            var sel=box.querySelector('.thumb.sel');
            if(sel && sel.scrollIntoView) sel.scrollIntoView({block:'nearest'});
          }

          function toggleStrip(){
            var box=$('strip');
            var on = box.className!=='on';
            box.className = on ? 'on' : '';
            $('stripbtn').textContent = on ? 'הסתר את הדפים' : 'הצג את כל הדפים';
            STATE.strip = on;
            paintStrip();
            render();                        // the drawing area just changed width
          }

          function fillPages(){
            var box=$('pages'); box.innerHTML='';
            (DOC.pages||[]).forEach(function(p,i){
              var row=document.createElement('div');
              row.className='pg'+(i===(STATE.active||0)?' sel':'');
              row.onclick=function(){ $('pages').focus(); goToPage(i); };
              var num=document.createElement('b');
              num.textContent=p.sheet_number||('#'+(i+1));
              row.appendChild(num);
              var nm=document.createElement('span');
              nm.textContent=p.name; nm.title=p.name;
              row.appendChild(nm);
              if(p.kind && p.kind!=='plan'){
                var x=document.createElement('button');
                x.textContent='×'; x.title='הסר את הדף הזה';
                x.onclick=function(e){
                  e.stopPropagation();
                  sketchup.delete_page(JSON.stringify({kind:p.kind, ref:p.ref}));
                };
                row.appendChild(x);
              }
              box.appendChild(row);
            });
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
              if(e.key==='Delete'||e.key==='Backspace'){
                if(SEL!==null){ e.preventDefault(); dropMark(); }
              } else if(e.key==='Escape'){
                PEND=null; HOVER=null; SEL=null; ERA=null;
                closeTextBar();
                render(); showMarks();
              }
            });

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
              if(t&&PEND){
                // The words go up and to the right of the thing they describe,
                // with the leader running back to it. About 0.7 of a paper inch
                // whatever the scale, so it looks the same on every sheet - and
                // he drags the box wherever he likes afterwards.
                // The words go up and away from the thing they describe. The
                // knee sits at the same height as the words, on the side the
                // thing is on, so the shoulder comes out level - the shape in
                // the picture he sent. He drags any of the three afterwards.
                var off=0.7/scaleFactor(STATE.scale);
                var tx=PEND[0]+off, ty=PEND[1]+off;
                var toward = PEND[0] < tx ? -1 : 1;
                marks().push({t:'note', x:tx, y:ty,
                              kx:tx + toward*off*0.55, ky:ty,
                              lx:PEND[0], ly:PEND[1], text:t,
                              arrow: STATE.note_arrow!==false});
                SEL=marks().length-1;
              }
              closeNote();
              push(); showMarks();
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
          