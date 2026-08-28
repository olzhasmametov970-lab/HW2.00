(function () {
  'use strict';

  function esc(s) {
    if (s == null) return '';
    var d = document.createElement('div');
    d.textContent = String(s);
    return d.innerHTML;
  }

  function linkAttrs(href) {
    var h = String(href || '');
    if (/^https?:\/\//i.test(h)) {
      return ' href="' + esc(h) + '" target="_blank" rel="noopener noreferrer"';
    }
    return ' href="' + esc(h) + '"';
  }

  function navLink(item) {
    var cls = item.button ? 'btn btn-primary' : '';
    if (item.style === 'outline' || item.outline) {
      cls = 'btn btn-outline';
    }
    return (
      '<a' + linkAttrs(item.href) + (cls ? ' class="' + cls + '"' : '') + '>' +
      esc(item.label) +
      '</a>'
    );
  }

  function btnClass(style) {
    return style === 'outline' ? 'btn btn-outline' : 'btn btn-primary';
  }

  function renderPage(c) {
    var brand = c.brand || {};
    var meta = c.meta || {};
    var hero = c.hero || {};
    var features = c.features || {};
    var modes = c.modes || {};
    var how = c.how || {};
    var pricing = c.pricing || {};
    var dev = c.developers || {};
    var contact = c.contact || {};
    var footer = c.footer || {};

    document.title = meta.title || brand.name || 'ГидроВин';
    var desc = document.querySelector('meta[name="description"]');
    if (desc && meta.description) desc.setAttribute('content', meta.description);
    var theme = document.querySelector('meta[name="theme-color"]');
    if (theme && meta.themeColor) theme.setAttribute('content', meta.themeColor);

    var preview = hero.preview || { sensors: [] };
    var sensorsHtml = (preview.sensors || []).map(function (s) {
      return (
        '<div class="sensor-card ' + esc(s.state || 'ok') + '">' +
        '<div class="label">' + esc(s.label) + '</div>' +
        '<div class="value">' + esc(s.value) + '</div>' +
        '<div class="status">● ' + esc(s.status) + '</div>' +
        '</div>'
      );
    }).join('');

    var statsHtml = (hero.stats || []).map(function (s) {
      return '<div class="hero-stat"><strong>' + esc(s.value) + '</strong><span>' + esc(s.label) + '</span></div>';
    }).join('');

    var actionsHtml = (hero.actions || []).map(function (a) {
      return '<a' + linkAttrs(a.href) + ' class="' + btnClass(a.style) + '">' + esc(a.label) + '</a>';
    }).join('');

    var featuresHtml = (features.items || []).map(function (f) {
      return (
        '<article class="feature-card">' +
        '<div class="feature-icon">' + esc(f.icon) + '</div>' +
        '<h3>' + esc(f.title) + '</h3>' +
        '<p>' + esc(f.text) + '</p>' +
        '</article>'
      );
    }).join('');

    var modesHtml = (modes.items || []).map(function (m) {
      var tag = m.tag ? '<span class="tag">' + esc(m.tag) + '</span>' : '';
      var bullets = (m.bullets || []).map(function (b) { return '<li>' + esc(b) + '</li>'; }).join('');
      return (
        '<article class="mode-card' + (m.featured ? ' featured' : '') + '">' +
        tag +
        '<h3>' + esc(m.title) + '</h3>' +
        '<p class="subtitle">' + esc(m.subtitle) + '</p>' +
        '<ul>' + bullets + '</ul>' +
        '</article>'
      );
    }).join('');

    var stepsHtml = (how.steps || []).map(function (step, i) {
      return (
        '<div class="step">' +
        '<div class="step-num">' + (i + 1) + '</div>' +
        '<h3>' + esc(step.title) + '</h3>' +
        '<p>' + esc(step.text) + '</p>' +
        '</div>'
      );
    }).join('');

    var plansHtml = (pricing.plans || []).map(function (p) {
      var priceNote = p.priceNote ? ' <small>' + esc(p.priceNote) + '</small>' : '';
      var bullets = (p.bullets || []).map(function (b) { return '<li>' + esc(b) + '</li>'; }).join('');
      return (
        '<article class="price-card' + (p.popular ? ' popular' : '') + '">' +
        '<h3>' + esc(p.name) + '</h3>' +
        '<div class="price">' + esc(p.price) + priceNote + '</div>' +
        '<ul>' + bullets + '</ul>' +
        '</article>'
      );
    }).join('');

    var stackHtml = (dev.stack || []).map(function (t) {
      return '<span class="tech-tag">' + esc(t) + '</span>';
    }).join('');

    var repoHtml = (dev.repoItems || []).map(function (item) {
      return '<li><code>' + esc(item) + '</code></li>';
    }).join('');

    var footerProduct = (footer.productLinks || []).map(function (l) {
      return '<li><a' + linkAttrs(l.href) + '>' + esc(l.label) + '</a></li>';
    }).join('');

    var footerDocs = (footer.docItems || []).map(function (d) {
      return '<li>' + esc(d) + '</li>';
    }).join('');

    var navHtml = (c.nav || []).map(navLink).join('');

    var email = contact.email || 'hello@hydrowin.ru';
    var mailSubject = encodeURIComponent('Пилот ГидроВин');

    return (
      '<header class="site-header">' +
      '<div class="container header-inner">' +
      '<a href="#" class="logo">' +
      '<img src="assets/favicon.svg" alt="" width="36" height="36">' +
      esc(brand.name) +
      '</a>' +
      '<button class="nav-toggle" type="button" aria-label="Меню" aria-expanded="false">☰</button>' +
      '<nav class="nav" id="main-nav">' + navHtml + '</nav>' +
      '</div></header>' +
      '<main>' +
      '<section class="hero"><div class="container hero-grid"><div>' +
      '<span class="hero-badge">' + esc(hero.badge) + '</span>' +
      '<h1>' + esc(hero.title) + '</h1>' +
      '<p class="hero-lead">' + esc(hero.lead) + '</p>' +
      '<div class="hero-actions">' + actionsHtml + '</div>' +
      '<div class="hero-stats">' + statsHtml + '</div>' +
      '</div>' +
      '<div class="app-preview" aria-hidden="true"><div class="phone-frame"><div class="phone-screen">' +
      '<div class="phone-header">' + esc(preview.header) + '</div>' +
      '<div class="sensor-cards">' + sensorsHtml + '</div>' +
      '</div></div></div></div></section>' +
      '<section id="features"><div class="container">' +
      '<div class="section-title"><h2>' + esc(features.title) + '</h2><p>' + esc(features.subtitle) + '</p></div>' +
      '<div class="features-grid">' + featuresHtml + '</div></div></section>' +
      '<section id="modes" class="modes"><div class="container">' +
      '<div class="section-title"><h2>' + esc(modes.title) + '</h2><p>' + esc(modes.subtitle) + '</p></div>' +
      '<div class="modes-grid">' + modesHtml + '</div></div></section>' +
      '<section id="how"><div class="container">' +
      '<div class="section-title"><h2>' + esc(how.title) + '</h2><p>' + esc(how.subtitle) + '</p></div>' +
      '<div class="steps">' + stepsHtml + '</div></div></section>' +
      '<section id="pricing"><div class="container">' +
      '<div class="section-title"><h2>' + esc(pricing.title) + '</h2><p>' + esc(pricing.subtitle) + '</p></div>' +
      '<div class="pricing-grid">' + plansHtml + '</div></div></section>' +
      '<section id="developers" class="tech"><div class="container">' +
      '<div class="section-title"><h2>' + esc(dev.title) + '</h2><p>' + esc(dev.subtitle) + '</p></div>' +
      '<div class="tech-grid"><div>' +
      '<h3>Стек</h3><div class="tech-list" style="margin-bottom: 1.5rem;">' + stackHtml + '</div>' +
      '<h3>Статусы датчиков</h3>' +
      '<p style="color: var(--text-muted); font-size: 0.95rem;">' + esc(dev.statusNote) + '</p>' +
      '</div><div class="repo-links">' +
      '<h3>Материалы в репозитории</h3>' +
      '<p style="color: var(--text-muted); font-size: 0.9rem; margin: 0 0 1rem;">' + esc(dev.repoNote) + '</p>' +
      '<ul style="margin: 0; padding-left: 1.2rem; color: var(--text-muted); font-size: 0.95rem;">' + repoHtml + '</ul>' +
      '</div></div></div></section>' +
      '<section id="contact" class="cta"><div class="container">' +
      '<h2>' + esc(contact.title) + '</h2>' +
      '<p>' + esc(contact.text) + ' Напишите на ' +
      '<a href="mailto:' + esc(email) + '" style="color: #fff; font-weight: 700;">' + esc(email) + '</a></p>' +
      '<a href="mailto:' + esc(email) + '?subject=' + mailSubject + '" class="btn btn-primary">' + esc(contact.buttonLabel) + '</a>' +
      '</div></section></main>' +
      '<footer class="site-footer"><div class="container">' +
      '<div class="footer-grid">' +
      '<div><a href="#" class="logo" style="color: #fff; margin-bottom: 1rem;">' +
      '<img src="assets/favicon.svg" alt="" width="32" height="32">' + esc(brand.name) + '</a>' +
      '<p style="margin: 0; max-width: 320px; font-size: 0.9rem;">' + esc(brand.footerDescription) + '</p></div>' +
      '<div><h4>Продукт</h4><ul>' + footerProduct + '</ul></div>' +
      '<div><h4>Документы</h4><ul>' + footerDocs + '</ul></div>' +
      '</div><div class="footer-bottom">' + esc(brand.copyright) + '</div></div></footer>'
    );
  }

  function showError(msg) {
    var app = document.getElementById('app');
    if (!app) return;
    app.innerHTML =
      '<div style="padding:3rem;text-align:center;font-family:system-ui,sans-serif;">' +
      '<h1>Не удалось загрузить сайт</h1><p>' + esc(msg) + '</p>' +
      '<p style="color:#666;">Проверьте файл <code>data/content.json</code> или запустите сервер из <code>website/server</code>.</p></div>';
  }

  function loadContent() {
    return fetch('/data/content.json', { cache: 'no-store' })
      .catch(function () {
        return fetch('data/content.json', { cache: 'no-store' });
      });
  }

  var app = document.getElementById('app');
  if (!app) return;

  loadContent()
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(function (data) {
      app.innerHTML = renderPage(data);
      document.dispatchEvent(new CustomEvent('hydrowin:rendered'));
    })
    .catch(function (err) {
      showError(err.message || 'Ошибка загрузки');
    });
})();
