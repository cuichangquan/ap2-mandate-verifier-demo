/* Read-only readiness polling: never approve, provision, execute, or recover. */
(() => {
  'use strict';
  const panel = document.getElementById('readiness');
  if (!panel) return;
  const controls = Array.from(document.querySelectorAll('[data-operation]'));
  const summary = document.getElementById('readiness-summary');
  const checked = document.getElementById('readiness-checked');
  const recheck = document.getElementById('readiness-recheck');
  let timer;
  let active = false;
  const disable = () => controls.forEach(control => { control.disabled = true; });
  function replaceList(id, items, text) {
    const list = document.getElementById(id);
    const nodes = items.map(item => {
      const node = document.createElement('li');
      node.textContent = text(item);
      return node;
    });
    list.replaceChildren(...nodes);
  }
  async function refresh() {
    clearTimeout(timer);
    if (active || document.hidden) return;
    active = true;
    disable();
    summary.textContent = panel.dataset.checking;
    recheck.disabled = true;
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), 9000);
    try {
      const response = await fetch(panel.dataset.url, {
        method: 'GET', cache: 'no-store', credentials: 'same-origin',
        headers: {'Accept': 'application/json'}, redirect: 'error', signal: controller.signal
      });
      if (response.status !== 200 && response.status !== 503) throw new Error('unavailable');
      const result = await response.json();
      const display = result.display;
      if (!display || !Array.isArray(display.services) || !Array.isArray(display.certificates) ||
          !display.operations || typeof display.summary !== 'string') throw new Error('unavailable');
      summary.textContent = display.summary;
      checked.textContent = display.checked_at;
      replaceList('readiness-services', display.services, item => `${item.label}: ${item.status} ${item.details}`);
      replaceList('readiness-certificates', display.certificates, item => item.text);
      if (!document.hidden) controls.forEach(control => {
        control.disabled = display.operations[control.dataset.operation] !== true;
      });
    } catch (_) {
      summary.textContent = panel.dataset.failure;
      // Remove stale green service labels and certificate metadata. The previous
      // check time remains visible, clearly separated from the failed refresh.
      replaceList('readiness-services', [], () => '');
      replaceList('readiness-certificates', [], () => '');
      disable();
    } finally {
      clearTimeout(deadline);
      active = false;
      recheck.disabled = false;
      timer = setTimeout(refresh, 10000);
    }
  }
  recheck.addEventListener('click', refresh);
  document.addEventListener('visibilitychange', () => {
    disable();
    if (!document.hidden) refresh();
  });
  // Disable immediately on restored browser history, then obtain fresh status.
  window.addEventListener('pageshow', refresh);
  refresh();
})();
