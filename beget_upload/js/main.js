(function () {
  'use strict';

  function bindNav() {
    var toggle = document.querySelector('.nav-toggle');
    var nav = document.getElementById('main-nav');

    if (!toggle || !nav) return;

    toggle.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(open));
      toggle.textContent = open ? '✕' : '☰';
    });

    nav.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        nav.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
        toggle.textContent = '☰';
      });
    });
  }

  function bindHeaderShadow() {
    var header = document.querySelector('.site-header');
    if (!header) return;
    window.addEventListener('scroll', function () {
      header.style.boxShadow = window.scrollY > 8
        ? '0 4px 20px rgba(0,0,0,0.08)'
        : 'none';
    });
  }

  function init() {
    bindNav();
    bindHeaderShadow();
  }

  if (document.getElementById('app') && !document.querySelector('.site-header')) {
    document.addEventListener('hydrowin:rendered', init, { once: true });
  } else {
    init();
  }
})();
