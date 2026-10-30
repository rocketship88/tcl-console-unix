const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1200, height: 1000 } });
  const errs = []; p.on('pageerror', e => errs.push('pageerror: ' + e.message)); p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.type() + ': ' + m.text()); });
  await p.goto('file://' + __dirname + '/console_stepper.html?check=1');
  await p.waitForTimeout(500);
  console.log(JSON.stringify(await p.evaluate(() => window.__selfcheck)));
  console.log(errs.join('\n'));
  await b.close();
})();
