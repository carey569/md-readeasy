// ReadEasy 渲染层：Markdown → HTML，并通过 webkit.messageHandlers.bridge 与原生层通信。
(() => {
  'use strict';

  const APP_BASE = document.baseURI;
  const content = document.getElementById('content');
  const baseEl = document.createElement('base');
  document.head.appendChild(baseEl);

  const post = (type, data = {}) => {
    try { window.webkit.messageHandlers.bridge.postMessage({ type, ...data }); } catch (_) { /* 非 App 环境 */ }
  };

  const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const slugify = (s) => s.trim().toLowerCase()
    .replace(/[^\p{L}\p{N}\p{M}\s_-]/gu, '')
    .replace(/\s/g, '-');

  // —— Markdown 引擎 ——

  const md = window.markdownit({
    html: true,
    linkify: true,
    highlight(code, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try { return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value; } catch (_) { /* 退回纯文本 */ }
      }
      return '';
    },
  });
  md.use(window.markdownitFootnote);
  md.use(window.texmath, {
    engine: window.katex,
    delimiters: ['dollars', 'brackets'],
    katexOptions: { throwOnError: false, strict: 'ignore' },
  });

  const inlineText = (inline) => (inline && inline.children ? inline.children : [])
    .filter((t) => t.type === 'text' || t.type === 'code_inline' || t.type === 'math_inline')
    .map((t) => t.content)
    .join('');

  // 标题加 id，同时收集大纲
  md.core.ruler.push('heading_ids', (state) => {
    const used = Object.create(null);
    const headings = [];
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      if (t.type !== 'heading_open') continue;
      const text = inlineText(tokens[i + 1]);
      let id = slugify(text) || 'section';
      if (id in used) id = `${id}-${++used[id]}`;
      else used[id] = 0;
      t.attrSet('id', id);
      headings.push({ id, level: Number(t.tag.slice(1)), text });
    }
    state.env.headings = headings;
  });

  // GFM 任务列表：- [ ] / - [x]
  md.core.ruler.push('task_lists', (state) => {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i++) {
      const inline = tokens[i];
      if (inline.type !== 'inline' || tokens[i - 1].type !== 'paragraph_open' || tokens[i - 2].type !== 'list_item_open') continue;
      const first = inline.children[0];
      if (!first || first.type !== 'text') continue;
      const m = /^\[([ xX])\](?:\s+|$)/.exec(first.content);
      if (!m) continue;
      first.content = first.content.slice(m[0].length);
      const box = new state.Token('html_inline', '', 0);
      box.content = `<input type="checkbox" class="task" disabled${m[1] === ' ' ? '' : ' checked'}>`;
      inline.children.unshift(box);
      tokens[i - 2].attrJoin('class', 'task-item');
    }
  });

  // GitHub 提示块：> [!NOTE]
  const ALERTS = { NOTE: '说明', TIP: '提示', IMPORTANT: '重要', WARNING: '警告', CAUTION: '注意' };
  md.core.ruler.push('alerts', (state) => {
    const tokens = state.tokens;
    for (let i = 0; i + 2 < tokens.length; i++) {
      if (tokens[i].type !== 'blockquote_open' || tokens[i + 1].type !== 'paragraph_open' || tokens[i + 2].type !== 'inline') continue;
      const inline = tokens[i + 2];
      const first = inline.children[0];
      const m = first && first.type === 'text' && /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/i.exec(first.content);
      if (!m) continue;
      const kind = m[1].toUpperCase();
      inline.children.shift();
      const next = inline.children[0];
      if (next && (next.type === 'softbreak' || next.type === 'hardbreak')) inline.children.shift();
      if (!inline.children.length) {
        tokens[i + 1].hidden = true;
        tokens[i + 3].hidden = true;
      }
      tokens[i].attrJoin('class', `alert alert-${kind.toLowerCase()}`);
      const title = new state.Token('html_block', '', 0);
      title.content = `<p class="alert-title">${ALERTS[kind]}</p>\n`;
      tokens.splice(i + 1, 0, title);
    }
  });

  const defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const lang = token.info.trim().split(/\s+/)[0].toLowerCase();
    if (lang === 'mermaid') {
      env.mermaid = true;
      return `<div class="mermaid-block" data-src="${escapeHtml(token.content)}"></div>\n`;
    }
    if (lang === 'math') {
      return katex.renderToString(token.content, { displayMode: true, throwOnError: false, strict: 'ignore' });
    }
    const label = lang ? `<span class="code-lang">${escapeHtml(lang)}</span>` : '';
    return `<div class="code-block"><div class="code-tools">${label}<button class="code-copy" type="button">复制</button></div>${defaultFence(tokens, idx, options, env, self)}</div>\n`;
  };

  md.renderer.rules.table_open = () => '<div class="table-wrap"><table>\n';
  md.renderer.rules.table_close = () => '</table></div>\n';

  // —— Front matter ——

  const FRONT_MATTER = /^﻿?---[ \t]*\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/;

  function splitFrontMatter(src) {
    const m = FRONT_MATTER.exec(src);
    return m ? [m[1], src.slice(m[0].length)] : [null, src];
  }

  const frontMatterHtml = (yaml) =>
    `<details class="front-matter"><summary>Front Matter</summary><pre><code>${hljs.highlight(yaml, { language: 'yaml', ignoreIllegals: true }).value}</code></pre></details>`;

  // —— Mermaid（按需加载）——

  const darkQuery = matchMedia('(prefers-color-scheme: dark)');
  const mermaidCache = new Map();
  let mermaidLoading = null;
  let mermaidTheme = null;
  let mermaidSeq = 0;

  function loadMermaid() {
    if (window.mermaid) return Promise.resolve();
    if (!mermaidLoading) {
      mermaidLoading = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = new URL('vendor/mermaid.min.js', APP_BASE).href;
        s.onload = resolve;
        s.onerror = () => { mermaidLoading = null; reject(new Error('Mermaid 加载失败')); };
        document.head.appendChild(s);
      });
    }
    return mermaidLoading;
  }

  function showError(block, message) {
    block.innerHTML = `<pre class="render-error">${escapeHtml(message)}</pre>`;
  }

  async function renderMermaid(root) {
    const blocks = root.querySelectorAll('.mermaid-block');
    if (!blocks.length) return;
    try {
      await loadMermaid();
    } catch (e) {
      blocks.forEach((b) => showError(b, e.message));
      return;
    }
    const theme = darkQuery.matches ? 'dark' : 'default';
    if (mermaidTheme !== theme) {
      mermaid.initialize({
        startOnLoad: false,
        theme,
        securityLevel: 'strict',
        fontFamily: '-apple-system, "PingFang SC", sans-serif',
      });
      mermaidTheme = theme;
    }
    for (const block of blocks) {
      const src = block.dataset.src;
      const key = `${theme}\u0000${src}`;
      let svg = mermaidCache.get(key);
      if (!svg) {
        const id = `mermaid-${++mermaidSeq}`;
        try {
          ({ svg } = await mermaid.render(id, src));
          mermaidCache.set(key, svg);
        } catch (e) {
          document.getElementById(`d${id}`)?.remove();
          showError(block, `Mermaid 语法错误\n${e && e.message ? e.message : e}`);
          continue;
        }
      }
      block.innerHTML = svg;
    }
  }

  darkQuery.addEventListener('change', async () => {
    const viewing = viewerIndex();
    await renderMermaid(content);
    if (viewing >= 0) syncViewer(viewing);
  });

  // —— 渲染 ——

  let renderSeq = 0;
  let headingEls = [];

  async function render(p) {
    const seq = ++renderSeq;
    if (p.base) baseEl.href = p.base;
    const [frontMatter, body] = splitFrontMatter(p.markdown || '');
    const env = {};
    let html = md.render(body, env);
    if (frontMatter !== null) html = frontMatterHtml(frontMatter) + html;

    const staging = document.createElement('div');
    staging.innerHTML = html;
    if (env.mermaid) await renderMermaid(staging);
    if (seq !== renderSeq) return false;

    const prevY = window.scrollY;
    const viewing = p.keepScroll ? viewerIndex() : -1;
    content.replaceChildren(...staging.childNodes);
    headingEls = [...content.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]')];
    // 自动刷新时预览跟着更新；切换文件则关闭预览
    if (viewing >= 0) syncViewer(viewing);
    else closeViewer(false);

    if (p.anchor) settleScroll(() => scrollToId(p.anchor, false));
    else if (p.keepScroll) settleScroll(() => window.scrollTo(0, prevY));
    else settleScroll(() => window.scrollTo(0, p.scrollY || 0));

    post('headings', { headings: env.headings || [] });
    lastActive = undefined;
    updateActive();
    if (findQuery) refreshFind();
    return true;
  }

  // 图片加载会撑开页面，等图片就绪后再校正一次滚动位置（期间用户自己滚动过就不动）
  function settleScroll(apply) {
    apply();
    const pending = [...content.querySelectorAll('img')].filter((img) => !img.complete);
    if (!pending.length) return;
    const y0 = window.scrollY;
    const loaded = Promise.all(pending.map((img) => new Promise((r) => {
      img.addEventListener('load', r, { once: true });
      img.addEventListener('error', r, { once: true });
    })));
    Promise.race([loaded, new Promise((r) => setTimeout(r, 1500))]).then(() => {
      if (Math.abs(window.scrollY - y0) < 2) apply();
    });
  }

  function scrollToId(id, smooth) {
    const el = document.getElementById(id) || document.getElementById(slugify(id)) || document.getElementsByName(id)[0];
    if (el) el.scrollIntoView({ behavior: smooth ? 'smooth' : 'auto', block: 'start' });
  }

  // —— 当前阅读位置（大纲高亮）——

  let lastActive;
  let ticking = false;
  let scrollTimer = null;
  const reportScroll = () => post('scroll', { y: window.scrollY });

  function updateActive() {
    let active = headingEls.length ? headingEls[0].id : null;
    const atBottom = window.scrollY > 0
      && window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
    const limit = atBottom ? window.innerHeight : 90;
    for (const h of headingEls) {
      if (h.getBoundingClientRect().top <= limit) active = h.id;
      else break;
    }
    if (active !== lastActive) {
      lastActive = active;
      post('active', { id: active });
    }
  }

  window.addEventListener('scroll', () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(reportScroll, 120);
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { ticking = false; updateActive(); });
  }, { passive: true });

  // 窗口尺寸变化（例如开关侧边栏、大纲）会改变标题位置
  window.addEventListener('resize', () => requestAnimationFrame(updateActive));

  // —— 图片 / 图表预览 ——

  const VIEWER_PAD = 28;
  const VIEWER_BAR = 60; // 底部工具条占用的高度
  const VIEWER_STEPS = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.25, 1.5, 2, 3, 4, 5, 6, 8];
  const icon = (d) => `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${d}"/></svg>`;

  const viewerEl = document.createElement('div');
  viewerEl.className = 'viewer';
  viewerEl.innerHTML = '<div class="viewer-bar">'
    + `<button type="button" data-act="out" title="缩小">${icon('M3.5 8h9')}</button>`
    + '<button type="button" data-act="toggle" class="viewer-scale"></button>'
    + `<button type="button" data-act="in" title="放大">${icon('M3.5 8h9M8 3.5v9')}</button>`
    + '<span class="viewer-sep"></span>'
    + `<button type="button" data-act="close" title="关闭">${icon('M4.5 4.5l7 7M11.5 4.5l-7 7')}</button>`
    + '</div>';
  document.body.appendChild(viewerEl);
  const viewerScale = viewerEl.querySelector('.viewer-scale');

  // 当前预览：source 是页面里的原图，w/h 是原始尺寸，x/y/scale 是显示位置和倍率
  let view = null;
  let animTimer = null;
  let drag = null;
  let gestureBase = 1;

  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
  const areaW = () => innerWidth - VIEWER_PAD * 2;
  const areaH = () => innerHeight - VIEWER_PAD * 2 - VIEWER_BAR;
  const centerY = () => VIEWER_PAD + areaH() / 2;

  // 可以点开预览的元素：Mermaid 图表、没有被链接包住的图片
  const zoomables = () => [...content.querySelectorAll('.mermaid-block > svg, img')].filter((el) => !el.closest('a[href]'));
  const viewerIndex = () => (view ? zoomables().indexOf(view.source) : -1);

  function zoomableAt(target) {
    if (target.closest('a[href]')) return null;
    const svg = target.closest('.mermaid-block > svg');
    if (svg) return svg;
    const img = target.closest('img');
    return img && content.contains(img) && img.complete && img.naturalWidth ? img : null;
  }

  function viewerItem(source) {
    const rect = source.getBoundingClientRect();
    if (source instanceof SVGSVGElement) {
      const box = source.viewBox.baseVal;
      const w = box && box.width ? box.width : rect.width;
      const h = box && box.height ? box.height : rect.height;
      const item = source.cloneNode(true);
      ['width', 'height', 'style'].forEach((a) => item.removeAttribute(a));
      if (!item.hasAttribute('viewBox')) item.setAttribute('viewBox', `0 0 ${w} ${h}`);
      item.classList.add('viewer-item');
      return { item, w, h };
    }
    const item = new Image();
    item.src = source.currentSrc || source.src;
    item.alt = source.alt;
    item.draggable = false;
    item.className = 'viewer-item';
    return { item, w: source.naturalWidth || rect.width, h: source.naturalHeight || rect.height };
  }

  function fitScale() {
    return clamp(Math.min(areaW() / view.w, areaH() / view.h), 0.05, view.maxFit);
  }

  function setAnimating(on) {
    clearTimeout(animTimer);
    viewerEl.classList.toggle('animating', !!on);
    if (on) animTimer = setTimeout(() => viewerEl.classList.remove('animating'), 260);
  }

  function placeItem(x, y, w, h) {
    const s = view.item.style;
    s.width = `${w}px`;
    s.height = `${h}px`;
    s.transform = `translate(${x}px, ${y}px)`;
  }

  // 比可视区域小时居中；比可视区域大时限制拖动范围，图片边缘不会被拖进视野内部
  function layoutViewer() {
    const w = view.w * view.scale;
    const h = view.h * view.scale;
    view.x = w <= areaW() ? (innerWidth - w) / 2 : clamp(view.x, innerWidth - VIEWER_PAD - w, VIEWER_PAD);
    view.y = h <= areaH() ? VIEWER_PAD + (areaH() - h) / 2 : clamp(view.y, VIEWER_PAD + areaH() - h, VIEWER_PAD);
    placeItem(view.x, view.y, w, h);
    viewerEl.classList.toggle('pannable', w > areaW() || h > areaH());
    viewerScale.textContent = `${Math.round(view.scale * 100)}%`;
    viewerScale.title = view.fitted ? '实际大小' : '适合窗口';
  }

  function openViewer(source) {
    closeViewer(false);
    const { item, w, h } = viewerItem(source);
    if (!w || !h) return;
    const inline = source instanceof SVGSVGElement;
    // 矢量图放大不会糊，适合窗口时最多放大到 2 倍；位图最多显示到原始大小
    const maxFit = inline || /\.svg(?:[?#]|$)/i.test(source.src) ? 2 : 1;
    view = { source, item, w, h, inline, maxFit, src: inline ? '' : source.src, scale: 1, x: 0, y: 0, fitted: true };
    viewerEl.prepend(item);
    viewerEl.classList.add('visible');
    // 先放在原图的位置，再过渡到适合窗口的大小
    const from = source.getBoundingClientRect();
    placeItem(from.left, from.top, from.width, from.height);
    viewerEl.getBoundingClientRect();
    view.scale = fitScale();
    setAnimating(true);
    layoutViewer();
    viewerEl.classList.add('open');
    post('viewer', { open: true });
  }

  function closeViewer(animated) {
    if (!view) return;
    const { item, source } = view;
    const to = animated && source.isConnected ? source.getBoundingClientRect() : null;
    if (to && to.bottom > 0 && to.top < innerHeight) {
      setAnimating(true);
      placeItem(to.left, to.top, to.width, to.height);
    } else {
      item.style.opacity = 0;
    }
    view = null;
    drag = null;
    viewerEl.classList.remove('open', 'dragging');
    const finish = () => {
      item.remove();
      if (!view) viewerEl.classList.remove('visible');
    };
    if (animated) setTimeout(finish, 220);
    else finish();
    post('viewer', { open: false });
  }

  // 内容重新渲染后（自动刷新、切换深浅色）换成新的同一张图，保持缩放和位置
  function syncViewer(index) {
    if (!view) return;
    const next = zoomables()[index];
    if (!next || (next instanceof SVGSVGElement) !== view.inline || (!view.inline && next.src !== view.src)) {
      closeViewer(false);
      return;
    }
    view.source = next;
    if (!view.inline) return;
    const { item, w, h } = viewerItem(next);
    view.item.replaceWith(item);
    Object.assign(view, { item, w, h });
    if (view.fitted) view.scale = fitScale();
    layoutViewer();
  }

  function zoomAt(scale, cx, cy, animated) {
    const s = clamp(scale, Math.min(fitScale(), 1) / 2, VIEWER_STEPS[VIEWER_STEPS.length - 1]);
    view.x = cx - (cx - view.x) * (s / view.scale);
    view.y = cy - (cy - view.y) * (s / view.scale);
    view.scale = s;
    view.fitted = false;
    setAnimating(animated);
    layoutViewer();
  }

  function fitViewer() {
    view.scale = fitScale();
    view.fitted = true;
    setAnimating(true);
    layoutViewer();
  }

  function panBy(dx, dy, animated) {
    view.x += dx;
    view.y += dy;
    setAnimating(animated);
    layoutViewer();
  }

  // step：1 放大一档，-1 缩小一档，0 在「适合窗口」和「实际大小」之间切换
  function viewerZoom(step) {
    if (!view) return;
    if (step === 0) {
      if (view.fitted) zoomAt(1, innerWidth / 2, centerY(), true);
      else fitViewer();
      return;
    }
    const next = step > 0
      ? VIEWER_STEPS.find((v) => v > view.scale + 0.001)
      : [...VIEWER_STEPS].reverse().find((v) => v < view.scale - 0.001);
    zoomAt(next ?? view.scale, innerWidth / 2, centerY(), true);
  }

  viewerEl.querySelector('.viewer-bar').addEventListener('click', (e) => {
    const act = e.target.closest('button')?.dataset.act;
    if (act === 'in') viewerZoom(1);
    else if (act === 'out') viewerZoom(-1);
    else if (act === 'toggle') viewerZoom(0);
    else if (act === 'close') closeViewer(true);
  });

  // 拖动平移；在图片外单击（没有拖动）关闭预览
  viewerEl.addEventListener('pointerdown', (e) => {
    if (!view || e.button !== 0 || e.target.closest('.viewer-bar')) return;
    drag = { id: e.pointerId, x: e.clientX, y: e.clientY, moved: false, onItem: !!e.target.closest('.viewer-item') };
    viewerEl.setPointerCapture(e.pointerId);
  });

  viewerEl.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.x;
    const dy = e.clientY - drag.y;
    if (!drag.moved) {
      if (Math.hypot(dx, dy) < 3) return;
      drag.moved = true;
      viewerEl.classList.add('dragging');
    }
    drag.x = e.clientX;
    drag.y = e.clientY;
    panBy(dx, dy, false);
  });

  viewerEl.addEventListener('pointerup', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    const { moved, onItem } = drag;
    drag = null;
    viewerEl.classList.remove('dragging');
    if (!moved && !onItem) closeViewer(true);
  });

  viewerEl.addEventListener('pointercancel', () => {
    drag = null;
    viewerEl.classList.remove('dragging');
  });

  // 双击：适合窗口时放大到至少实际大小，否则恢复适合窗口
  viewerEl.addEventListener('dblclick', (e) => {
    if (!view || !e.target.closest('.viewer-item')) return;
    if (view.fitted) zoomAt(Math.max(1, view.scale * 2), e.clientX, e.clientY, true);
    else fitViewer();
  });

  // 触控板双指滑动平移；捏合或按住 ⌘ 滚动缩放
  viewerEl.addEventListener('wheel', (e) => {
    e.preventDefault();
    if (!view) return;
    if (e.ctrlKey || e.metaKey) {
      zoomAt(view.scale * clamp(Math.exp(-e.deltaY * 0.01), 0.8, 1.25), e.clientX, e.clientY, false);
    } else {
      const k = e.deltaMode === 1 ? 16 : 1;
      panBy(-e.deltaX * k, -e.deltaY * k, false);
    }
  }, { passive: false });

  // WebKit 在 macOS 上把触控板捏合作为 gesture 事件发给页面
  viewerEl.addEventListener('gesturestart', (e) => {
    e.preventDefault();
    if (view) gestureBase = view.scale;
  });
  viewerEl.addEventListener('gesturechange', (e) => {
    e.preventDefault();
    if (view) zoomAt(gestureBase * e.scale, e.clientX, e.clientY, false);
  });
  viewerEl.addEventListener('gestureend', (e) => e.preventDefault());

  document.addEventListener('keydown', (e) => {
    if (!view || e.metaKey || e.ctrlKey) return;
    const pan = { ArrowLeft: [80, 0], ArrowRight: [-80, 0], ArrowUp: [0, 80], ArrowDown: [0, -80] }[e.key];
    if (e.key === 'Escape') closeViewer(true);
    else if (pan) panBy(pan[0], pan[1], true);
    else if (![' ', 'PageUp', 'PageDown', 'Home', 'End'].includes(e.key)) return;
    // 预览打开时不让底下的页面跟着滚动
    e.preventDefault();
  });

  window.addEventListener('resize', () => {
    if (!view) return;
    if (view.fitted) view.scale = fitScale();
    layoutViewer();
  });

  // —— 点击：链接、复制代码、图片预览 ——

  document.addEventListener('click', (e) => {
    if (viewerEl.contains(e.target)) return;
    const zoomable = zoomableAt(e.target);
    if (zoomable) {
      openViewer(zoomable);
      return;
    }
    const copy = e.target.closest('.code-copy');
    if (copy) {
      const code = copy.closest('.code-block').querySelector('pre');
      post('copy', { text: code.textContent });
      copy.textContent = '已复制';
      copy.classList.add('done');
      setTimeout(() => { copy.textContent = '复制'; copy.classList.remove('done'); }, 1400);
      return;
    }
    const a = e.target.closest('a[href]');
    if (!a) return;
    e.preventDefault();
    const raw = a.getAttribute('href');
    if (raw.startsWith('#')) {
      scrollToId(decodeURIComponent(raw.slice(1)), true);
      return;
    }
    post('link', { href: a.href, newTab: e.metaKey });
  });

  // —— 文内查找 ——

  let findQuery = '';
  let hits = [];
  let hitIndex = -1;

  function clearHits() {
    const parents = new Set();
    for (const m of hits) {
      const parent = m.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(m.textContent), m);
      parents.add(parent);
    }
    parents.forEach((p) => p.normalize());
    hits = [];
    hitIndex = -1;
  }

  function collectHits(query) {
    const q = query.toLowerCase();
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const p = node.parentElement;
        if (!p || p.closest('svg, .katex-mathml, .code-tools')) return NodeFilter.FILTER_REJECT;
        return node.nodeValue.toLowerCase().includes(q) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const text = node.nodeValue;
      const lower = text.toLowerCase();
      const frag = document.createDocumentFragment();
      let start = 0;
      let idx;
      while ((idx = lower.indexOf(q, start)) !== -1) {
        if (idx > start) frag.append(text.slice(start, idx));
        const mark = document.createElement('mark');
        mark.className = 'find-hit';
        mark.textContent = text.slice(idx, idx + q.length);
        frag.append(mark);
        hits.push(mark);
        start = idx + q.length;
      }
      if (start < text.length) frag.append(text.slice(start));
      node.parentNode.replaceChild(frag, node);
    }
  }

  function markCurrent(scroll) {
    hits.forEach((m, i) => m.classList.toggle('current', i === hitIndex));
    const cur = hits[hitIndex];
    if (!cur || !scroll) return;
    const r = cur.getBoundingClientRect();
    if (r.top < 60 || r.bottom > window.innerHeight - 40) cur.scrollIntoView({ block: 'center' });
  }

  const findResult = () => ({ current: hits.length ? hitIndex + 1 : 0, total: hits.length });

  function find(query, backwards) {
    closeViewer(false);
    if (query !== findQuery || !hits.length) {
      clearHits();
      findQuery = query;
      if (!query) return findResult();
      collectHits(query);
      if (!hits.length) return findResult();
      hitIndex = hits.findIndex((m) => m.getBoundingClientRect().top >= 0);
      if (hitIndex < 0) hitIndex = 0;
    } else {
      hitIndex = (hitIndex + (backwards ? -1 : 1) + hits.length) % hits.length;
    }
    markCurrent(true);
    return findResult();
  }

  // 文件刷新后重新标记，保持当前序号
  function refreshFind() {
    const keep = hitIndex;
    hits = [];
    collectHits(findQuery);
    hitIndex = hits.length ? Math.min(Math.max(keep, 0), hits.length - 1) : -1;
    markCurrent(false);
    post('find', findResult());
  }

  function findClear() {
    clearHits();
    findQuery = '';
  }

  window.ReadEasy = {
    render,
    find,
    findClear,
    scrollToId: (id) => {
      closeViewer(false);
      scrollToId(id, true);
    },
    viewerZoom,
    viewerClose: () => closeViewer(true),
    setAccent: (color) => document.documentElement.style.setProperty('--accent', color),
  };

  post('ready');
})();
