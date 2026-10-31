/* Two interactive demos on sample data: the scanning treemap with a Safety-mode switch, and the Things threshold slider. */
(function () {
  "use strict";

  var KIND = { video: "#934350", image: "#DA5E85", audio: "#7E3DB0", document: "#5277F7", code: "#388100", app: "#27A4BD", archive: "#9D9138", other: "#6E6A62" };
  var TIER = { safe: "#FFB800", rebuild: "#B97F12", review: "#4A463F", never: "#1F1D1A", unknown: "#34312B" };
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- Treemap ---------- */

  /** Sample disk: [name, GB, kind, safety tier]. Names come from the demo disk, not from a real machine. */
  var DISK = [
    ["Docker.raw", 64, "archive", "review"], ["Photos Library", 41, "image", "never"], ["wedding-final-master.mov", 38, "video", "unknown"],
    ["Lossless", 35.7, "audio", "unknown"], ["Shoots", 30.2, "image", "unknown"], ["Iceland 2023", 29.7, "video", "unknown"],
    ["imagenet-subset.tar", 24, "archive", "unknown"], ["DerivedData", 18, "code", "rebuild"], ["Install macOS.pkg", 13, "archive", "review"],
    ["Caches", 12.6, "app", "rebuild"], ["node_modules", 9.4, "code", "rebuild"], ["Xcode_15.2.zip", 8.1, "archive", "review"],
    ["old-backup.zip", 6.4, "archive", "review"], ["Ubuntu-24.04.iso", 5.9, "archive", "review"], ["Homebrew downloads", 4.1, "archive", "safe"],
    [".npm", 3.3, "code", "rebuild"], ["Logs", 2.2, "document", "safe"]
  ];

  /** Squarified layout of items (sorted by value) into the rectangle; returns [{item,x,y,w,h}]. */
  function squarify(items, x, y, w, h) {
    var total = items.reduce(function (s, i) { return s + i.v; }, 0);
    var scale = (w * h) / total, out = [], row = [], rowArea = 0, i = 0;
    var pending = items.map(function (it) { return { item: it, a: it.v * scale }; });

    /** Worst aspect ratio of the row if laid along a side of length `side`. */
    function worst(rows, area, side) {
      var max = 0, min = Infinity;
      rows.forEach(function (r) { max = Math.max(max, r.a); min = Math.min(min, r.a); });
      var s2 = side * side;
      return Math.max((s2 * max) / (area * area), (area * area) / (s2 * min));
    }
    /** Places a finished row along the shorter side and shrinks the free rectangle. */
    function place(rows, area) {
      if (w >= h) {
        var rw = area / h, yy = y;
        rows.forEach(function (r) { var rh = r.a / rw; out.push({ item: r.item, x: x, y: yy, w: rw, h: rh }); yy += rh; });
        x += rw; w -= rw;
      } else {
        var rh2 = area / w, xx = x;
        rows.forEach(function (r) { var rw2 = r.a / rh2; out.push({ item: r.item, x: xx, y: y, w: rw2, h: rh2 }); xx += rw2; });
        y += rh2; h -= rh2;
      }
    }
    while (i < pending.length) {
      var next = pending[i], side = Math.min(w, h);
      if (!row.length || worst(row.concat([next]), rowArea + next.a, side) <= worst(row, rowArea, side)) {
        row.push(next); rowArea += next.a; i++;
      } else { place(row, rowArea); row = []; rowArea = 0; }
    }
    if (row.length) place(row, rowArea);
    return out;
  }

  /** Builds and runs the scanning treemap inside #tm. */
  function initTreemap() {
    var root = document.getElementById("tm");
    if (!root) return;
    var mode = "kind", scanned = false, tiles = [];
    var sweep = root.querySelector(".tm-sweep");
    var status = document.getElementById("tm-status");
    var legend = document.getElementById("tm-legend");
    var buttons = document.querySelectorAll("[data-mode]");
    if (reduce) root.classList.add("reduce");
    var items = DISK.map(function (d) { return { name: d[0], v: d[1], kind: d[2], tier: d[3] }; }).sort(function (a, b) { return b.v - a.v; });
    var totalGB = items.reduce(function (s, i) { return s + i.v; }, 0);
    var reclaim = items.filter(function (i) { return i.tier === "safe" || i.tier === "rebuild"; }).reduce(function (s, i) { return s + i.v; }, 0);

    /** Formats gigabytes with one decimal. */
    function gb(v) { return v.toFixed(1) + " GB"; }

    /** Lays the tiles out for the current container size. */
    function layout() {
      var w = root.clientWidth, h = root.clientHeight;
      root.querySelectorAll(".tile").forEach(function (t) { t.remove(); });
      tiles = squarify(items, 0, 0, w, h).map(function (r) {
        var el = document.createElement("div");
        el.className = "tile";
        el.style.cssText = "left:" + r.x + "px;top:" + r.y + "px;width:" + (r.w - 2) + "px;height:" + (r.h - 2) + "px";
        if (r.w > 70 && r.h > 34) el.innerHTML = "";
        var label = document.createElement("span");
        label.textContent = r.item.name;
        var small = document.createElement("small");
        small.textContent = gb(r.item.v);
        if (r.w > 70 && r.h > 34) { el.appendChild(label); el.appendChild(small); } else { el.title = r.item.name + ", " + gb(r.item.v); }
        root.appendChild(el);
        return { el: el, r: r };
      });
      paint();
      if (scanned) tiles.forEach(function (t) { t.el.classList.add("on"); });
    }

    /** Applies colour for the current mode. */
    function paint() {
      tiles.forEach(function (t) {
        var it = t.r.item, el = t.el;
        el.classList.remove("dim", "gold", "never");
        if (mode === "kind") { el.style.backgroundColor = KIND[it.kind]; return; }
        el.style.backgroundColor = TIER[it.tier];
        if (it.tier === "safe" || it.tier === "rebuild") el.classList.add("gold");
        else if (it.tier === "never") el.classList.add("never");
        else el.classList.add("dim");
      });
      buttons.forEach(function (b) {
        var on = b.getAttribute("data-mode") === mode;
        b.setAttribute("aria-pressed", on ? "true" : "false");
      });
      legend.innerHTML = mode === "kind"
        ? ["video", "image", "audio", "document", "code", "app", "archive"].map(function (k) { return '<span style="--c:' + KIND[k] + '">' + k + "</span>"; }).join("")
        : '<span style="--c:#FFB800">safe</span><span style="--c:#B97F12">rebuild</span><span style="--c:#4A463F">review</span><span style="--c:#1F1D1A;outline:1px solid #2E2B26">never offered</span>';
      if (scanned) status.innerHTML = mode === "safety"
        ? "<b>" + gb(reclaim) + "</b> of " + gb(totalGB) + " is gold (safe or rebuildable)."
        : "Sample disk, " + gb(totalGB) + ". Switch to Safety to see what is reclaimable.";
    }

    /** Switches colour mode. */
    function setMode(next) { mode = next; paint(); }
    buttons.forEach(function (b) { b.addEventListener("click", function () { setMode(b.getAttribute("data-mode")); }); });

    /** Reveals tiles under a sweeping scan line, then switches to Safety once. */
    function scan() {
      if (reduce) { scanned = true; tiles.forEach(function (t) { t.el.classList.add("on"); }); paint(); return; }
      var start = null, dur = 3200, w = root.clientWidth, done = false;
      sweep.style.opacity = 1;
      /** Reveals everything and hands over to Safety mode. Also runs from a timer, since browsers can pause animation frames. */
      function finish() {
        if (done) return;
        done = true;
        tiles.forEach(function (t) { t.el.classList.add("on"); });
        scanned = true; sweep.style.opacity = 0; paint();
        window.setTimeout(function () { if (mode === "kind") setMode("safety"); }, 1400);
      }
      window.setTimeout(finish, dur + 500);
      function frame(ts) {
        if (done) return;
        if (start === null) start = ts;
        var p = Math.min(1, (ts - start) / dur), x = p * w;
        sweep.style.left = x + "px";
        var shown = 0;
        tiles.forEach(function (t) {
          if (t.r.x + t.r.w / 2 <= x) { t.el.classList.add("on"); shown += t.r.item.v; }
        });
        status.textContent = "Scanning sample disk: " + gb(shown);
        if (p < 1) { window.requestAnimationFrame(frame); return; }
        finish();
      }
      window.requestAnimationFrame(frame);
    }

    layout();
    var lastW = root.clientWidth;
    window.addEventListener("resize", function () { if (root.clientWidth !== lastW) { lastW = root.clientWidth; layout(); } });
    var started = false;
    /** Starts the scan once the instrument is on screen. */
    function maybeStart() { if (started) return; started = true; scan(); }
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (e, o) { if (e[0].isIntersecting) { o.disconnect(); maybeStart(); } }, { threshold: 0.3 }).observe(root);
    } else { maybeStart(); }
  }

  /* ---------- Things ---------- */

  /** A file leaf, size in MB. */
  function F(name, mb) { return { name: name, size: mb, dir: false }; }
  /** A directory; atom directories stay whole until opened. */
  function D(name, kids, atom) {
    var size = kids.reduce(function (s, k) { return s + k.size; }, 0);
    return { name: name, size: size, dir: true, kids: kids, atom: !!atom, count: kids.reduce(function (s, k) { return s + (k.count || 1); }, 0) };
  }
  /** n files of equal size. */
  function many(prefix, n, mb) { var a = []; for (var i = 1; i <= n; i++) a.push(F(prefix + String(i).padStart(2, "0"), mb)); return a; }

  var SAMPLE = D("demo", [
    D("Downloads", [
      F("ubuntu-24.04.iso", 400),
      D("design-handoff", [F("handoff-v1.fig", 70), F("handoff-v2.fig", 60), F("handoff-v3.fig", 55), D("renders", many("r", 8, 15)), D("exports", many("e", 3, 35))]),
      D("conference-talks", [F("talk-1.mp4", 640), F("talk-2.mp4", 610), F("talk-3.mp4", 380), D("slides", many("s", 17, 10))]),
      F("Xcode_15.2.zip", 810)
    ]),
    D("Developer", [D("webapp", [D("node_modules", many("p", 76, 10), true), D(".git", many("g", 12, 10), true), D("src", many("f", 20, 5))]), D("notes", many("n", 40, 1))]),
    D("Movies", [F("wedding-final-master.mov", 3800),
      D("Iceland 2023", [F("C1005.mov", 720), F("C1007.mov", 660), F("C1014.mov", 230), F("C1011.mov", 220), F("C1008.mov", 200)].concat(many("clip", 10, 90)))]),
    D("Pictures", [D("Shoots", many("IMG_", 60, 50))])
  ]);
  var STOPS = [20, 50, 100, 200, 400, 800, 2000, 4000];

  /** One result row for a node. */
  function row(node) { return { label: node.name, kind: node.dir ? "folder" : "file", size: node.size, rest: false }; }
  /** The threshold cut under a directory: returns {rows, carry:{size,count}}; rows are disjoint and add up with the carry. */
  function cut(dir, t) {
    var big = dir.kids.filter(function (k) { return k.size >= t; });
    if (dir.atom || !big.length) return { rows: [row(dir)], carry: { size: 0, count: 0 } };
    var rows = [], remSize = 0, remCount = 0;
    dir.kids.forEach(function (k) {
      if (k.size < t) { remSize += k.size; remCount += k.count || 1; return; }
      if (k.dir && !k.atom) {
        var sub = cut(k, t);
        rows = rows.concat(sub.rows); remSize += sub.carry.size; remCount += sub.carry.count;
      } else { rows.push(row(k)); }
    });
    if (remSize >= t) { rows.push({ label: remCount + " smaller items in " + dir.name, kind: "", size: remSize, rest: true }); remSize = 0; remCount = 0; }
    return { rows: rows, carry: { size: remSize, count: remCount } };
  }

  /** Formats megabytes as MB or GB. */
  function fmt(mb) { return mb >= 1000 ? (mb / 1000).toFixed(2) + " GB" : Math.round(mb) + " MB"; }

  /** Wires the slider, the row list and the explanatory line. */
  function initThings() {
    var slider = document.getElementById("things-t");
    var list = document.getElementById("things-rows");
    if (!slider) return;
    var head = document.getElementById("things-head");
    var note = document.getElementById("things-note");
    slider.max = STOPS.length - 1; slider.value = STOPS.indexOf(400);

    /** Recomputes the cut for the slider position and redraws. */
    function render() {
      var t = STOPS[+slider.value];
      var res = cut(SAMPLE, t), rows = res.rows.slice();
      if (res.carry.size > 0) rows.push({ label: res.carry.count + " smaller items in demo", kind: "", size: res.carry.size, rest: true });
      rows.sort(function (a, b) { return b.size - a.size; });
      var sum = rows.reduce(function (s, r) { return s + r.size; }, 0), max = rows[0].size;
      var both = rows.some(function (r) { return r.label === "ubuntu-24.04.iso"; }) && rows.some(function (r) { return r.label === "design-handoff"; });
      head.innerHTML = "<span>Threshold <b>" + fmt(t) + "</b></span><span><b>" + rows.length + "</b> things</span><span>" + fmt(sum) + " of " + fmt(SAMPLE.size) + (sum === SAMPLE.size ? " (adds up)" : "") + "</span>";
      list.innerHTML = "";
      rows.forEach(function (r) {
        var li = document.createElement("li");
        if (r.label === "ubuntu-24.04.iso" || r.label === "design-handoff") li.className = "hl";
        var nm = document.createElement("span"); nm.className = "nm";
        nm.textContent = r.label + (r.kind ? " " : "");
        if (r.kind) { var em = document.createElement("em"); em.textContent = r.kind; nm.appendChild(em); }
        var sz = document.createElement("span"); sz.className = "sz"; sz.textContent = fmt(r.size);
        var bar = document.createElement("span"); bar.className = "bar";
        var fill = document.createElement("i"); fill.style.width = (100 * r.size / max).toFixed(1) + "%"; bar.appendChild(fill);
        li.appendChild(nm); li.appendChild(sz); li.appendChild(bar); list.appendChild(li);
      });
      note.textContent = both
        ? "A 400 MB file and a 410 MB folder, ranked as neighbours. A tree makes you pick a depth; a file list never shows the folder."
        : "Lower the threshold and folders open into their parts. Raise it and parts roll up into their parent.";
    }
    slider.addEventListener("input", render);
    render();
  }

  initTreemap();
  initThings();
})();
